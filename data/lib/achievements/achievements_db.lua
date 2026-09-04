-- Achievements: the database mirror.
--
-- lib/core/achievements.lua owns the achievements themselves and keeps every
-- unlock in `player_storage` at key 300000 + id. That file is untouched by
-- this one beyond two one-line calls, and it stays the runtime source of
-- truth: hasAchievement() still reads storage, and so does every one of the
-- 188 award sites in the data tree.
--
-- What this adds is the ability to ASK. Storage cannot answer "how many points
-- does this character have" (points live only in Lua), nor "who has the most"
-- (player_storage is keyed (player_id, key), so a cross-player query cannot
-- use the index), nor "how rare is this" (nothing ever counted). Three tables
-- created in migration 73 answer all three, and this file keeps them true.
--
-- The pattern is Loyalty.publishLadder()'s: the server republishes its own
-- config into the database at startup, so the website and the client render
-- what the server is actually enforcing and the copies cannot drift.

AchievementsDB = {}

-- Rarity is quoted against characters that have actually left the tutorial.
-- Counting every level-1 alt ever created would push every achievement toward
-- "0.1% of characters" and make the figure meaningless -- the number is only
-- interesting if its denominator is people who play.
AchievementsDB.RARITY_MIN_LEVEL = 8

-- Regular players only. Staff characters would otherwise show up owning
-- everything, which is exactly the population a rarity figure must exclude.
AchievementsDB.PLAYER_GROUP_ID = 1

local CATALOGUE_CHUNK = 40
local CHECKSUM_CONFIG = "achievements_checksum"

-- ─── Catalogue checksum ─────────────────────────────────────────────────
--
-- FNV-1a over the whole authored catalogue, description text included. Two
-- jobs: skip the republish when nothing changed, and give the client window a
-- value to compare its shipped catalogue file against. The client ships the
-- public names and descriptions rather than receiving them (see the note in
-- achievements_protocol.lua), so a client built from an older achievements.lua
-- would silently draw wrong text with nothing anywhere to say so. The checksum
-- turns that into a visible notice.
--
-- Bytes, not characters: two descriptions carry an en-dash and an em-dash, and
-- the generator reads the file as latin1 for exactly this reason. Feeding
-- decoded characters on either side would make the two disagree forever.

local cachedChecksum = nil

function AchievementsDB.catalogueChecksum()
	if cachedChecksum then
		return cachedChecksum
	end

	local hash = 2166136261
	local function feed(text)
		for index = 1, #text do
			hash = (hash ~ text:byte(index)) & 0xFFFFFFFF
			hash = (hash * 16777619) & 0xFFFFFFFF
		end
	end

	for id = 1, #achievements do
		local entry = achievements[id]
		if entry then
			feed(string.format("%d|%s|%d|%d|%d|%s", id, entry.name or "",
				tonumber(entry.grade) or 1, tonumber(entry.points) or 0,
				entry.secret and 1 or 0, entry.description or ""))
		end
	end

	cachedChecksum = hash
	return cachedChecksum
end

-- ─── Publishing ─────────────────────────────────────────────────────────

local function storedChecksum()
	local resultId = db.storeQuery(string.format(
		"SELECT `value` FROM `server_config` WHERE `config` = %s",
		db.escapeString(CHECKSUM_CONFIG)))
	if resultId == false then
		return nil
	end
	local value = tonumber(result.getString(resultId, "value"))
	result.free(resultId)
	return value
end

-- Rewrites `achievements` from the Lua catalogue. Rows are upserted in chunks
-- and anything no longer authored is pruned, so deleting an achievement from
-- the Lua file removes it from the site too -- while `player_achievements`
-- keeps the record of everyone who earned it (no foreign key, on purpose).
--
-- `owners` and `owners_permille` are NOT written here: they are recomputed
-- state that publishing must not stamp back to zero on every boot.
function AchievementsDB.publishCatalogue(force)
	local checksum = AchievementsDB.catalogueChecksum()
	if not force and storedChecksum() == checksum then
		return false
	end

	local rows, keep = {}, {}

	local function flush()
		if #rows == 0 then
			return
		end
		db.query(
			"INSERT INTO `achievements` (`id`, `name`, `grade`, `points`, `secret`, `description`) VALUES " ..
			table.concat(rows, ",") ..
			" ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `grade` = VALUES(`grade`)," ..
			" `points` = VALUES(`points`), `secret` = VALUES(`secret`)," ..
			" `description` = VALUES(`description`)")
		rows = {}
	end

	for id = 1, #achievements do
		local entry = achievements[id]
		if entry then
			keep[#keep + 1] = id
			rows[#rows + 1] = string.format("(%d, %s, %d, %d, %d, %s)", id,
				db.escapeString(entry.name or ("Achievement " .. id)),
				tonumber(entry.grade) or 1,
				tonumber(entry.points) or 0,
				entry.secret and 1 or 0,
				db.escapeString(entry.description or ""))
			if #rows >= CATALOGUE_CHUNK then
				flush()
			end
		end
	end
	flush()

	if #keep > 0 then
		db.query("DELETE FROM `achievements` WHERE `id` NOT IN (" .. table.concat(keep, ",") .. ")")
	else
		db.query("DELETE FROM `achievements`")
	end

	db.query(string.format(
		"INSERT INTO `server_config` (`config`, `value`) VALUES (%s, %s)" ..
		" ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)",
		db.escapeString(CHECKSUM_CONFIG), db.escapeString(tostring(checksum))))

	print(string.format(">> Achievements: published %d entries (checksum %d)", #keep, checksum))
	return true
end

-- ─── Totals ─────────────────────────────────────────────────────────────
--
-- Computed once from the Lua catalogue rather than queried. The window header
-- needs these on every sync and they only change when the file does.

local cachedTotals = nil

function AchievementsDB.totals()
	if cachedTotals then
		return cachedTotals
	end

	-- byGrade is what lets the client draw its per-difficulty meters. It cannot
	-- count them itself: the catalogue it ships holds only the public entries,
	-- so every secret would be missing from the denominator.
	local totals = { count = 0, points = 0, secrets = 0, publicCount = 0, byGrade = {} }
	for id = 1, #achievements do
		local entry = achievements[id]
		if entry then
			local grade = tonumber(entry.grade) or 1
			totals.count = totals.count + 1
			totals.points = totals.points + (tonumber(entry.points) or 0)
			totals.byGrade[grade] = (totals.byGrade[grade] or 0) + 1
			if entry.secret then
				totals.secrets = totals.secrets + 1
			else
				totals.publicCount = totals.publicCount + 1
			end
		end
	end

	cachedTotals = totals
	return totals
end

-- ─── Summaries ──────────────────────────────────────────────────────────

local SUMMARY_SELECT = [[
	SELECT pa.`player_id`, COUNT(*), COALESCE(SUM(a.`points`), 0),
	       COALESCE(SUM(a.`secret`), 0), COALESCE(MAX(pa.`unlocked_at`), 0), %d
	FROM `player_achievements` pa
	JOIN `achievements` a ON a.`id` = pa.`achievement_id`
	%s
	GROUP BY pa.`player_id`
]]

local SUMMARY_UPSERT = [[
	INSERT INTO `player_achievement_summary`
		(`player_id`, `unlocked`, `points`, `secrets`, `last_unlocked_at`, `updated_at`)
	%s
	ON DUPLICATE KEY UPDATE `unlocked` = VALUES(`unlocked`), `points` = VALUES(`points`),
		`secrets` = VALUES(`secrets`), `last_unlocked_at` = VALUES(`last_unlocked_at`),
		`updated_at` = VALUES(`updated_at`)
]]

-- Recomputes one character's row from the two authoritative tables. Called
-- after every unlock, so the website and the highscore are current the moment
-- an achievement is earned rather than at the character's next save.
function AchievementsDB.refreshSummary(playerId)
	playerId = tonumber(playerId)
	if not playerId or playerId <= 0 then
		return
	end

	db.query(string.format(SUMMARY_UPSERT,
		string.format(SUMMARY_SELECT, os.time(),
			string.format("WHERE pa.`player_id` = %d", playerId))))

	-- Removing the last achievement leaves an orphan summary the upsert above
	-- can never reach, because it selects from a set that is now empty.
	db.query(string.format([[
		DELETE s FROM `player_achievement_summary` s
		LEFT JOIN `player_achievements` pa ON pa.`player_id` = s.`player_id`
		WHERE s.`player_id` = %d AND pa.`player_id` IS NULL
	]], playerId))
end

-- Recomputes every character in one statement. Runs at startup: it is what
-- fills the summary after migration 73's backfill (which cannot compute points
-- because the catalogue is not published until the server boots), and it is
-- the repair path for anything that ever drifts.
function AchievementsDB.rebuildAllSummaries()
	db.query(string.format(SUMMARY_UPSERT, string.format(SUMMARY_SELECT, os.time(), "")))
	db.query([[
		DELETE s FROM `player_achievement_summary` s
		LEFT JOIN `player_achievements` pa ON pa.`player_id` = s.`player_id`
		WHERE pa.`player_id` IS NULL
	]])
end

-- ─── Showcase ───────────────────────────────────────────────────────────
--
-- The one achievement a character puts on their public page. Stored on the
-- summary row so the website sees it immediately, rather than in
-- `player_storage`, which would not reach the database until the next save.

function AchievementsDB.getShowcase(playerId)
	playerId = tonumber(playerId)
	if not playerId or playerId <= 0 then
		return 0
	end

	local showcase = 0
	local resultId = db.storeQuery(string.format(
		"SELECT `showcase_id` FROM `player_achievement_summary` WHERE `player_id` = %d", playerId))
	if resultId ~= false then
		showcase = result.getNumber(resultId, "showcase_id")
		result.free(resultId)
	end
	return showcase
end

-- Nominates an achievement, or clears the nomination with an id of 0.
--
-- Ownership is re-checked here against storage rather than trusted from the
-- caller: this is reachable from the network, and a client that asked to
-- showcase something it had not earned would otherwise put a lie on a public
-- page. Returns false when the character does not hold it.
function AchievementsDB.setShowcase(player, achievementId)
	local playerId = player and player:getGuid()
	if not playerId or playerId <= 0 then
		return false
	end

	achievementId = tonumber(achievementId) or 0
	if achievementId ~= 0 then
		if not achievements[achievementId] then
			return false
		end
		if player:getStorageValue(PlayerStorageKeys.achievementsBase + achievementId) <= 0 then
			return false
		end
	end

	-- UPDATE, not upsert: a character with no summary row holds no
	-- achievements, so there is nothing it could legitimately be nominating.
	db.query(string.format(
		"UPDATE `player_achievement_summary` SET `showcase_id` = %d WHERE `player_id` = %d",
		achievementId, playerId))

	return true
end

-- ─── Rarity ─────────────────────────────────────────────────────────────

-- Recounts how many characters hold each achievement.
--
-- Permille, not percent: almost everything interesting here sits under 1%, and
-- a board full of "0%" says nothing. Rounded up to 1 permille whenever anyone
-- at all holds it, so a genuinely-owned achievement never displays as 0.0%.
-- Last computed population and rarity column. Both are read on every window
-- sync and change once an hour, so they are cached here rather than re-queried
-- per request.
AchievementsDB.population = 0
local cachedRarity = nil

function AchievementsDB.refreshRarity()
	local denominator = 0
	local resultId = db.storeQuery(string.format([[
		SELECT COUNT(*) AS `n` FROM `players`
		WHERE `deletion` = 0 AND `group_id` = %d AND `level` >= %d
	]], AchievementsDB.PLAYER_GROUP_ID, AchievementsDB.RARITY_MIN_LEVEL))
	if resultId ~= false then
		denominator = result.getNumber(resultId, "n")
		result.free(resultId)
	end

	db.query(string.format([[
		UPDATE `achievements` a
		LEFT JOIN (
			SELECT pa.`achievement_id` AS `aid`, COUNT(*) AS `n`
			FROM `player_achievements` pa
			JOIN `players` p ON p.`id` = pa.`player_id`
			WHERE p.`deletion` = 0 AND p.`group_id` = %d AND p.`level` >= %d
			GROUP BY pa.`achievement_id`
		) c ON c.`aid` = a.`id`
		SET a.`owners` = COALESCE(c.`n`, 0),
		    a.`owners_permille` = IF(%d > 0 AND COALESCE(c.`n`, 0) > 0,
		        GREATEST(1, LEAST(1000, ROUND(COALESCE(c.`n`, 0) * 1000 / %d))), 0)
	]], AchievementsDB.PLAYER_GROUP_ID, AchievementsDB.RARITY_MIN_LEVEL,
		denominator, math.max(1, denominator)))

	AchievementsDB.population = denominator
	cachedRarity = nil
	return denominator
end

-- The whole rarity column, cached until the next hourly recount.
function AchievementsDB.rarityTable()
	if cachedRarity then
		return cachedRarity
	end

	local rarity = {}
	local resultId = db.storeQuery("SELECT `id`, `owners_permille` FROM `achievements`")
	if resultId == false then
		return rarity
	end

	repeat
		rarity[result.getNumber(resultId, "id")] = result.getNumber(resultId, "owners_permille")
	until not result.next(resultId)
	result.free(resultId)

	cachedRarity = rarity
	return rarity
end

-- ─── Recording ──────────────────────────────────────────────────────────

-- Called from Player.addAchievement the moment an achievement is earned.
--
-- INSERT IGNORE rather than a check-then-insert: the composite primary key
-- already forbids a duplicate, so the database settles the race instead of
-- Lua trying to.
function AchievementsDB.recordUnlock(player, achievementId, unlockedAt)
	local playerId = player and player:getGuid()
	if not playerId or playerId <= 0 then
		return
	end

	db.query(string.format(
		"INSERT IGNORE INTO `player_achievements` (`player_id`, `achievement_id`, `unlocked_at`) VALUES (%d, %d, %d)",
		playerId, achievementId, unlockedAt or os.time()))

	AchievementsDB.refreshSummary(playerId)
end

function AchievementsDB.recordRemoval(player, achievementId)
	local playerId = player and player:getGuid()
	if not playerId or playerId <= 0 then
		return
	end

	db.query(string.format(
		"DELETE FROM `player_achievements` WHERE `player_id` = %d AND `achievement_id` = %d",
		playerId, achievementId))

	AchievementsDB.refreshSummary(playerId)
end

-- ─── Login reconciliation ───────────────────────────────────────────────

-- Brings the mirror back in line with storage for one character.
--
-- Storage stays authoritative, so anything that writes it directly -- a GM
-- setting a storage by hand, a script bypassing addAchievement, or simply an
-- unlock earned before this system existed -- is picked up here rather than
-- being lost. Reads are in-memory (the storage map is loaded with the player),
-- and the two repair queries only run when there is actually a difference.
function AchievementsDB.reconcilePlayer(player)
	local playerId = player and player:getGuid()
	if not playerId or playerId <= 0 then
		return 0, 0
	end

	local base = PlayerStorageKeys.achievementsBase
	local inStorage = {}
	for id = 1, #achievements do
		if player:getStorageValue(base + id) > 0 then
			inStorage[id] = true
		end
	end

	local inMirror = {}
	local resultId = db.storeQuery(string.format(
		"SELECT `achievement_id` FROM `player_achievements` WHERE `player_id` = %d", playerId))
	if resultId ~= false then
		repeat
			inMirror[result.getNumber(resultId, "achievement_id")] = true
		until not result.next(resultId)
		result.free(resultId)
	end

	local missing, stale = {}, {}
	for id in pairs(inStorage) do
		if not inMirror[id] then
			missing[#missing + 1] = string.format("(%d, %d, %d)", playerId, id,
				math.max(0, player:getStorageValue(base + id)))
		end
	end
	for id in pairs(inMirror) do
		if not inStorage[id] then
			stale[#stale + 1] = id
		end
	end

	if #missing == 0 and #stale == 0 then
		return 0, 0
	end

	if #missing > 0 then
		db.query("INSERT IGNORE INTO `player_achievements` (`player_id`, `achievement_id`, `unlocked_at`) VALUES " ..
			table.concat(missing, ","))
	end
	if #stale > 0 then
		db.query(string.format(
			"DELETE FROM `player_achievements` WHERE `player_id` = %d AND `achievement_id` IN (%s)",
			playerId, table.concat(stale, ",")))
	end

	AchievementsDB.refreshSummary(playerId)
	return #missing, #stale
end
