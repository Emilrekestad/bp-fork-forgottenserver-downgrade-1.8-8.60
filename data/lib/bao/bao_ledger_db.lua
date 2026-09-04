-- Bao's Ledger — the database mirror.
--
-- bao_ledger.lua owns the Ledger and keeps every rank in the player's kv
-- store. That stays the runtime source of truth: every effect accessor in that
-- file still reads BaoLedger.getRank, and nothing in the game reads the tables
-- written here.
--
-- What this adds is the ability to ASK. `kv_store.value` is a longblob holding
-- TFS's serialised ValueWrapper, so no query can read a rank out of it, let
-- alone order by one. Migration 74's two tables answer "how far has this
-- character got" and "who has got furthest"; this file keeps them true.
--
-- The pattern is Loyalty.publishLadder()'s and AchievementsDB's: the server
-- republishes its own config into the database at startup, so the website
-- renders what the server is actually enforcing and the copies cannot drift.
--
-- (!) There is no rebuildAll(). The kv store is only reachable through a
-- Player object, so a character's row can only be written while they are
-- online. That is sufficient rather than a compromise: ranks can ONLY change
-- while online too, so an offline character's row is as of their last login,
-- which is also as of their last possible change.

BaoLedgerDB = {}

-- ─── Catalogue ──────────────────────────────────────────────────────────

-- Rewrites `bao_ledger_tracks` from BaoConfig.Ledger. Thirteen rows, so this
-- is unconditional rather than checksum-gated the way the 398-row achievement
-- catalogue has to be.
--
-- Pending tracks are excluded, matching BaoLedger.orderedKeys() and
-- BaoLedger.maxRanks(). They cannot be bought, so publishing them would quote
-- the site a denominator no player can ever reach.
function BaoLedgerDB.publishTracks()
	local rows, keep = {}, {}

	for _, key in ipairs(BaoLedger.orderedKeys(false)) do
		local track = BaoConfig.Ledger[key]
		keep[#keep + 1] = db.escapeString(key)
		rows[#rows + 1] = string.format("(%s, %d, %d, %s, %s, %s, %d, %d)",
			db.escapeString(key),
			tonumber(track.book) or 1,
			tonumber(track.order) or 0,
			db.escapeString(track.displayName or key),
			db.escapeString(track.summary or ""),
			-- `effect` is a printf template ("-%d%% required kills"); the site
			-- fills the number per rank, so it is stored as authored.
			db.escapeString(track.effect or ""),
			tonumber(track.perRank) or 0,
			tonumber(track.maxRank) or 0)
	end

	if #rows == 0 then
		return 0
	end

	db.query(
		"INSERT INTO `bao_ledger_tracks` (`track_key`, `book`, `ordering`, `name`, `summary`, `effect`, `per_rank`, `max_rank`) VALUES " ..
		table.concat(rows, ",") ..
		" ON DUPLICATE KEY UPDATE `book` = VALUES(`book`), `ordering` = VALUES(`ordering`)," ..
		" `name` = VALUES(`name`), `summary` = VALUES(`summary`), `effect` = VALUES(`effect`)," ..
		" `per_rank` = VALUES(`per_rank`), `max_rank` = VALUES(`max_rank`)")

	-- A track deleted from the Lua config (or newly marked pending) disappears
	-- from the site too. Summaries are untouched -- see the migration's note on
	-- why there is no foreign key.
	db.query("DELETE FROM `bao_ledger_tracks` WHERE `track_key` NOT IN (" ..
		table.concat(keep, ",") .. ")")

	return #rows
end

-- ─── Per-character summary ──────────────────────────────────────────────

-- Reads one character's whole Ledger out of the kv store and writes the row.
--
-- Called after every purchase and on every login. Both matter: the purchase
-- write is what makes the board current the moment a rank is bought, and the
-- login write is the repair path for anything bought before this mirror
-- existed, or lost to a crash between the kv write and this one.
function BaoLedgerDB.refreshSummary(player)
	local playerId = player and player:getGuid()
	if not playerId or playerId <= 0 then
		return
	end

	local ranks, started, mastered = 0, 0, 0
	local topKey, topRank = "", 0

	-- orderedKeys is sorted by `order` then key, so the tie-break below is
	-- stable: two tracks at the same rank always resolve to the same one
	-- rather than reshuffling between calls the way a raw pairs() would.
	for _, key in ipairs(BaoLedger.orderedKeys(false)) do
		local track = BaoConfig.Ledger[key]
		local rank = BaoLedger.getRank(player, key)
		if rank > 0 then
			ranks = ranks + rank
			started = started + 1
			if rank >= track.maxRank then
				mastered = mastered + 1
			end
			if rank > topRank then
				topKey, topRank = key, rank
			end
		end
	end

	-- Nothing bought: no row. A board of characters at zero is noise, and the
	-- delete is what removes a row after a GM wipes someone's Ledger.
	if ranks == 0 then
		db.asyncQuery(string.format(
			"DELETE FROM `bao_ledger_summary` WHERE `player_id` = %d", playerId))
		return
	end

	db.asyncQuery(string.format([[
		INSERT INTO `bao_ledger_summary`
			(`player_id`, `ranks`, `tracks_started`, `tracks_mastered`, `invested`, `top_track`, `top_rank`, `updated_at`)
		VALUES (%d, %d, %d, %d, %d, %s, %d, %d)
		ON DUPLICATE KEY UPDATE `ranks` = VALUES(`ranks`),
			`tracks_started` = VALUES(`tracks_started`),
			`tracks_mastered` = VALUES(`tracks_mastered`),
			`invested` = VALUES(`invested`),
			`top_track` = VALUES(`top_track`),
			`top_rank` = VALUES(`top_rank`),
			`updated_at` = VALUES(`updated_at`)
	]], playerId, ranks, started, mastered, BaoLedger.totalInvested(player),
		db.escapeString(topKey), topRank, os.time()))
end

-- ─── Reporting ──────────────────────────────────────────────────────────

-- Startup log line. `maxRanks` comes from the config rather than from SUM() of
-- the table just written, so a publish that silently wrote nothing shows up as
-- a mismatch in the log instead of agreeing with itself.
function BaoLedgerDB.totals()
	local tracked, denominator = 0, 0
	local resultId = db.storeQuery(
		"SELECT COUNT(*) AS `n`, COALESCE(SUM(`max_rank`), 0) AS `m` FROM `bao_ledger_tracks`")
	if resultId ~= false then
		tracked = result.getNumber(resultId, "n")
		denominator = result.getNumber(resultId, "m")
		result.free(resultId)
	end
	return tracked, denominator, BaoLedger.maxRanks()
end
