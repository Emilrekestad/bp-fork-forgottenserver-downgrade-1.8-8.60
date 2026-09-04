-- Highscores — the projection and the query engine.
--
-- Two jobs:
--
--   1. publishBoards() rewrites `highscore_boards` from HighscoresConfig at
--      startup, so the website renders the catalogue the server is actually
--      serving. Same pattern as Loyalty.publishLadder and
--      BaoLedgerDB.publishTracks.
--   2. fetch() answers a board request for the in-game window.
--
-- (!) EVERY REQUEST HERE IS A LIVE SOCKET, which is the difference between
-- this and the website. The site has MyAAC's page cache in front of it and one
-- visitor costs one page; here twenty players opening the window at once would
-- be twenty full scans of `players`. So results are cached per
-- (board, vocation, page) and reused for CACHE_TTL seconds.

HighscoresDB = {}

-- Rows per page. Deliberately smaller than the website's 50: the client draws
-- real widgets rather than table rows, and a page is one screenful.
HighscoresDB.PAGE_SIZE = 25

-- Seconds. A highscore is a talking point, not a live counter -- the website
-- quotes minutes-old numbers too. Long enough that a player spamming the board
-- buttons costs one query, short enough that a level-up shows up while they
-- still care.
HighscoresDB.CACHE_TTL = 60

-- (!) VISIBILITY IS READ FROM MyAAC, NOT DECIDED HERE.
--
-- The website hides characters two ways: a minimum staff group
-- (`highscores_groups_hidden`) and an explicit id list
-- (`highscores_ids_hidden`), both edited in the admin panel and both stored in
-- `myaac_settings` in this same database.
--
-- The first version of this file hardcoded "group_id <= 2 and hide nobody",
-- and the two boards immediately disagreed in public: a level-5,000 test
-- character sat at rank 1 in the client while the website -- correctly --
-- showed nothing of the sort, because someone had hidden ids 2-6 months ago
-- and the game server had no idea. Reading the same rows is the only way the
-- two stay in sync, and it keeps the admin panel as the one place to manage it.
--
-- Defaults match MyAAC's own for a server with no settings table at all.
HighscoresDB.DEFAULT_GROUPS_HIDDEN = 3
HighscoresDB.VISIBILITY_TTL = 300

local visibility = nil
local visibilityExpires = 0
local cache = {}

local function cacheKey(boardId, vocationId, page)
	return boardId .. ":" .. vocationId .. ":" .. page
end

function HighscoresDB.invalidate()
	cache = {}
end

-- ─── Projection ─────────────────────────────────────────────────────────

-- Rewrites `highscore_boards`. Fourteen rows at most, so this is unconditional
-- rather than checksum-gated the way the 398-row achievement catalogue has to
-- be.
--
-- (!) Only AVAILABLE boards are published, not every authored one. That makes
-- the table the single answer to "what does this server offer", so the website
-- needs no availability logic of its own -- a disabled board and one whose
-- mirror table has not been created yet are both simply absent, and both
-- reappear on the next startup once that changes.
function HighscoresDB.publishBoards()
	local rows, keep = {}, {}

	for _, board in ipairs(HighscoresDB.availableBoards()) do
		local group = HighscoresConfig.Groups[board.group]
		keep[#keep + 1] = db.escapeString(board.key)
		rows[#rows + 1] = string.format("(%d, %s, %s, %d, %d, %s, %s, %s, %s, %d, %d)",
			board.id,
			db.escapeString(board.key),
			db.escapeString(board.group),
			group and group.ordering or 99,
			board.ordering or 0,
			db.escapeString(board.label),
			db.escapeString(board.title),
			db.escapeString(board.unit or board.title),
			db.escapeString(board.extraLabel or ""),
			board.vocation and 1 or 0,
			board.enabled and 1 or 0)
	end

	if #rows == 0 then
		return 0
	end

	db.query(
		"INSERT INTO `highscore_boards` (`id`, `board_key`, `group_key`, `group_ordering`, `ordering`, " ..
		"`label`, `title`, `unit`, `extra_label`, `has_vocation`, `enabled`) VALUES " ..
		table.concat(rows, ",") ..
		" ON DUPLICATE KEY UPDATE `board_key` = VALUES(`board_key`), `group_key` = VALUES(`group_key`)," ..
		" `group_ordering` = VALUES(`group_ordering`), `ordering` = VALUES(`ordering`)," ..
		" `label` = VALUES(`label`), `title` = VALUES(`title`), `unit` = VALUES(`unit`)," ..
		" `extra_label` = VALUES(`extra_label`), `has_vocation` = VALUES(`has_vocation`)," ..
		" `enabled` = VALUES(`enabled`)")

	-- A board deleted from the Lua config disappears from the website too.
	db.query("DELETE FROM `highscore_boards` WHERE `board_key` NOT IN (" ..
		table.concat(keep, ",") .. ")")

	return #rows
end

-- ─── Availability ───────────────────────────────────────────────────────

local tableCache = {}

local function tableExists(name)
	if tableCache[name] ~= nil then
		return tableCache[name]
	end

	local resultId = db.storeQuery(string.format(
		"SELECT 1 FROM `information_schema`.`tables` WHERE `table_schema` = DATABASE() AND `table_name` = %s LIMIT 1",
		db.escapeString(name)))

	local exists = resultId ~= false
	if resultId ~= false then
		result.free(resultId)
	end

	tableCache[name] = exists
	return exists
end

-- A board is offered only if it is enabled AND the table it depends on has
-- actually been created. A server running an older database must not be shown
-- a board whose query would error.
function HighscoresDB.isAvailable(board)
	if not board or not board.enabled then
		return false
	end
	if board.requiresTable and not tableExists(board.requiresTable) then
		return false
	end
	return true
end

function HighscoresDB.availableBoards()
	local list = {}
	for _, board in ipairs(HighscoresConfig.ordered()) do
		if HighscoresDB.isAvailable(board) then
			list[#list + 1] = board
		end
	end
	return list
end

-- ─── Vocations ──────────────────────────────────────────────────────────

-- Base vocations only, with their promotions folded in. A "Knight" filter has
-- to catch Elite Knights too, which is the same fold the website performs.
function HighscoresDB.vocationFilter(vocationId)
	vocationId = tonumber(vocationId) or 0
	if vocationId <= 0 then
		return ""
	end

	local ids = {}
	for id = 0, 12 do
		local voc = Vocation(id)
		if voc then
			local base = voc:getBase()
			if base and base:getId() == vocationId then
				ids[#ids + 1] = id
			end
		end
	end

	if #ids == 0 then
		return ""
	end

	return " AND p.`vocation` IN (" .. table.concat(ids, ",") .. ")"
end

function HighscoresDB.vocationName(vocationId)
	local voc = Vocation(tonumber(vocationId) or 0)
	return voc and voc:getName() or "None"
end

-- ─── Fetching ───────────────────────────────────────────────────────────

-- One MyAAC setting, or nil. `key` is a reserved word in MySQL, hence the
-- backticks -- the column really is named that.
local function readSetting(key)
	local resultId = db.storeQuery(string.format(
		"SELECT `value` FROM `myaac_settings` WHERE `name` = 'core' AND `key` = %s LIMIT 1",
		db.escapeString(key)))
	if resultId == false then
		return nil
	end
	local value = result.getString(resultId, "value")
	result.free(resultId)
	return value
end

-- Cached for VISIBILITY_TTL rather than read per query: it is two extra
-- SELECTs on a path that already runs per board request, and the answer
-- changes when an admin edits it, which is not often.
function HighscoresDB.visibility()
	local now = os.time()
	if visibility and visibilityExpires > now then
		return visibility
	end

	local groupsHidden = HighscoresDB.DEFAULT_GROUPS_HIDDEN
	local hidden = {}

	-- A server without MyAAC has no settings table; storeQuery simply returns
	-- false and the defaults stand.
	local raw = readSetting("highscores_groups_hidden")
	if raw then
		groupsHidden = tonumber(raw) or groupsHidden
	end

	-- Stored as a human-typed list, e.g. "2, 3, 4, 5, 6". Parsed rather than
	-- trusted: anything non-numeric is dropped instead of reaching the query.
	raw = readSetting("highscores_ids_hidden")
	if raw then
		for piece in string.gmatch(raw, "[^,]+") do
			local id = tonumber((piece:gsub("%s", "")))
			if id and id > 0 then
				hidden[#hidden + 1] = math.floor(id)
			end
		end
	end

	visibility = { groupsHidden = groupsHidden, hidden = hidden }
	visibilityExpires = now + HighscoresDB.VISIBILITY_TTL
	return visibility
end

-- `group_id <`, not `<=`: that is the comparison highscores.php makes, and a
-- board that hid one group more or less than the website would be exactly the
-- desync this exists to prevent.
local function visibilityClause(alias)
	alias = alias or "p"
	local rules = HighscoresDB.visibility()

	local clause = string.format(" %s.`deletion` = 0 AND %s.`group_id` < %d",
		alias, alias, rules.groupsHidden)

	if #rules.hidden > 0 then
		clause = clause .. string.format(" AND %s.`id` NOT IN (%s)",
			alias, table.concat(rules.hidden, ","))
	end

	return clause
end

-- Thousands separators, server-side. See the note on why values cross the wire
-- as strings in achievements_protocol.lua.
function HighscoresDB.formatNumber(value)
	local text = string.format("%d", math.floor(tonumber(value) or 0))
	local done
	repeat
		text, done = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
	until done == 0
	return text
end

-- The account-scoped board. Ranked per account but FRONTED BY A CHARACTER:
-- `accounts.name` is a login credential and must never reach a public board,
-- which is the same rule loyalty-highscores.php enforces.
local function fetchLoyalty(page)
	local offset = (page - 1) * HighscoresDB.PAGE_SIZE
	local rows = {}

	local resultId = db.storeQuery(string.format([[
		SELECT a.`premium_days` AS `value`, a.`streak_days` AS `extra`,
		       p.`name`, p.`level`, p.`vocation`,
		       p.`looktype`, p.`lookhead`, p.`lookbody`, p.`looklegs`, p.`lookfeet`, p.`lookaddons`
		FROM `loyalty_account` a
		JOIN `players` p ON p.`id` = COALESCE(
			(SELECT n.`id` FROM `players` n
			 WHERE n.`id` = a.`primary_player_id` AND n.`account_id` = a.`account_id`
			   AND %s),
			(SELECT f.`id` FROM `players` f
			 WHERE f.`account_id` = a.`account_id`
			   AND %s
			 ORDER BY f.`level` DESC, f.`experience` DESC LIMIT 1))
		WHERE a.`premium_days` > 0
		ORDER BY a.`premium_days` DESC, p.`level` DESC
		LIMIT %d OFFSET %d
	]], visibilityClause("n"), visibilityClause("f"),
		HighscoresDB.PAGE_SIZE, offset))

	if resultId ~= false then
		repeat
			rows[#rows + 1] = {
				name = result.getString(resultId, "name"),
				level = result.getNumber(resultId, "level"),
				vocation = HighscoresDB.vocationName(result.getNumber(resultId, "vocation")),
				value = result.getNumber(resultId, "value"),
				extra = result.getNumber(resultId, "extra"),
				outfit = {
					type = result.getNumber(resultId, "looktype"),
					head = result.getNumber(resultId, "lookhead"),
					body = result.getNumber(resultId, "lookbody"),
					legs = result.getNumber(resultId, "looklegs"),
					feet = result.getNumber(resultId, "lookfeet"),
					addons = result.getNumber(resultId, "lookaddons"),
				},
			}
		until not result.next(resultId)
		result.free(resultId)
	end

	return rows
end

local function fetchPlayers(board, vocationId, page)
	local offset = (page - 1) * HighscoresDB.PAGE_SIZE
	local rows = {}

	local resultId = db.storeQuery(string.format([[
		SELECT p.`name`, p.`level`, p.`vocation`,
		       p.`looktype`, p.`lookhead`, p.`lookbody`, p.`looklegs`, p.`lookfeet`, p.`lookaddons`,
		       %s AS `value`, %s AS `extra`
		FROM `players` p
		WHERE %s%s
		ORDER BY %s
		LIMIT %d OFFSET %d
	]], board.value, board.extra or "0", visibilityClause(),
		HighscoresDB.vocationFilter(vocationId), board.order,
		HighscoresDB.PAGE_SIZE, offset))

	if resultId ~= false then
		repeat
			rows[#rows + 1] = {
				name = result.getString(resultId, "name"),
				level = result.getNumber(resultId, "level"),
				vocation = HighscoresDB.vocationName(result.getNumber(resultId, "vocation")),
				value = result.getNumber(resultId, "value"),
				extra = result.getNumber(resultId, "extra"),
				outfit = {
					type = result.getNumber(resultId, "looktype"),
					head = result.getNumber(resultId, "lookhead"),
					body = result.getNumber(resultId, "lookbody"),
					legs = result.getNumber(resultId, "looklegs"),
					feet = result.getNumber(resultId, "lookfeet"),
					addons = result.getNumber(resultId, "lookaddons"),
				},
			}
		until not result.next(resultId)
		result.free(resultId)
	end

	return rows
end

-- One page of one board, cached. Ranks are assigned here rather than in SQL so
-- ties share a rank, which is what the website does and what every Tibia board
-- has always done.
function HighscoresDB.fetch(boardId, vocationId, page)
	local board = HighscoresConfig.byId(boardId)
	if not HighscoresDB.isAvailable(board) then
		return nil
	end

	page = math.max(1, math.min(tonumber(page) or 1, 40))
	vocationId = board.vocation and (tonumber(vocationId) or 0) or 0

	local key = cacheKey(board.id, vocationId, page)
	local hit = cache[key]
	local now = os.time()
	if hit and hit.expires > now then
		return hit.data
	end

	local rows = board.accountScoped and fetchLoyalty(page) or fetchPlayers(board, vocationId, page)

	local offset = (page - 1) * HighscoresDB.PAGE_SIZE
	local lastValue, lastRank = nil, 0
	for index, row in ipairs(rows) do
		if lastValue ~= nil and row.value == lastValue then
			row.rank = lastRank
		else
			row.rank = offset + index
		end
		lastRank, lastValue = row.rank, row.value
	end

	local data = { board = board, rows = rows, page = page, vocation = vocationId }
	cache[key] = { data = data, expires = now + HighscoresDB.CACHE_TTL }
	return data
end

-- Where one character stands on a board, regardless of which page that is.
-- The client pins this under the list -- it is the one thing the in-game
-- window can say that the website cannot, because it knows who is looking.
--
-- Returns nil for a board the player does not appear on at all.
function HighscoresDB.rankOf(player, boardId, vocationId)
	local board = HighscoresConfig.byId(boardId)
	if not HighscoresDB.isAvailable(board) or not player then
		return nil
	end

	-- Account-scoped boards rank an ACCOUNT; resolving "my rank" would mean
	-- re-running the primary-character fold per request for a single row.
	-- Skipped rather than approximated.
	if board.accountScoped then
		return nil
	end

	-- Rank is "how many beat me, plus one" -- a correlated COUNT rather than a
	-- window function, because this database is MySQL 5.7-era and ROW_NUMBER()
	-- is not available. The inner copy of the board's value expression is the
	-- same string with its table alias rewritten, so a board can never rank
	-- itself by one formula and place the player by another.
	-- (!) The VIEWER is filtered by the same visibility rules as everyone else.
	-- Without that clause a hidden character was told "You are ranked 1" under
	-- a list they do not appear in -- which is exactly what a GM saw, since the
	-- subquery counted only visible players and found none above them.
	local guid = player:getGuid()
	local resultId = db.storeQuery(string.format([[
		SELECT %s AS `value`,
		       (SELECT COUNT(*) + 1 FROM `players` q WHERE %s AND (%s) > (%s)) AS `rank`
		FROM `players` p
		WHERE p.`id` = %d AND %s
	]], board.value,
		visibilityClause("q"),
		(board.value:gsub("p%.`", "q.`")),
		board.value,
		guid,
		visibilityClause("p")))

	if resultId == false then
		return nil
	end

	local row = { value = result.getNumber(resultId, "value"), rank = result.getNumber(resultId, "rank") }
	result.free(resultId)
	return row
end
