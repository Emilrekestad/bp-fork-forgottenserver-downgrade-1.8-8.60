-- Admin console telemetry: the game server's side of the ledger.
--
-- Three writers live here.
--
--   GameEvents.emit  -- one typed row per notable thing that happened
--   Sessions         -- one row per login, closed on logout or at next boot
--   Metrics.write    -- one row per sampled number
--
-- All of them use db.asyncQuery. Nothing the console records is worth making
-- the game thread wait on: a dropped metric is a gap in a chart, while a
-- blocked dispatcher is a stutter every player feels. The coin ledger is the
-- deliberate exception -- it runs synchronously inside a transaction with the
-- balance change, because a coin movement that is not recorded is worse than
-- a slow one.
--
-- Payloads are versioned. When a payload's shape changes, bump the version in
-- GameEvents.VERSIONS rather than reusing the old number: the console reads
-- historic rows and needs to know which shape it is looking at.

Console = Console or {}
GameEvents = GameEvents or {}
Sessions = Sessions or {}
Metrics = Metrics or {}
Kills = Kills or {}
Bosses = Bosses or {}
Loot = Loot or {}

local function escaped(value)
	return db.escapeString(tostring(value))
end

local function numberOrNull(value)
	if value == nil then
		return "NULL"
	end
	local n = tonumber(value)
	if not n then
		return "NULL"
	end
	return tostring(math.floor(n))
end

-- ---------------------------------------------------------------- events

GameEvents.VERSIONS = {
	["session.login"]      = 1,
	["session.logout"]     = 1,
	["player.death"]       = 1,
	["player.level"]       = 1,
	["player.achievement"] = 1,
	["quest.progress"]     = 1,
	["store.purchase"]     = 1,
	["chat.message"]       = 1,
	["gm.command"]         = 1,
	["server.start"]       = 1,
	["server.stop"]        = 1,
	["server.save"]        = 1,
	["agent.action"]       = 1,
	["raid.start"]         = 1,
	["world.message"]      = 1,
}

--- Records that something happened.
-- @param eventType string a key of GameEvents.VERSIONS
-- @param fields table optional: accountId, playerId, subjectType, subjectId,
--        position (a Position or {x,y,z}), payload (table), sync (boolean)
--
-- `sync` writes the row before returning instead of queueing it. Use it only
-- on the shutdown path: an async query is handed to a worker thread that the
-- process does not wait for, so a `server.stop` emitted that way is lost every
-- time, and every clean restart then looks like a crash to the console.
-- Everywhere else async is correct -- a dropped event is a gap in a chart,
-- while a blocked dispatcher is a stutter every player feels.
function GameEvents.emit(eventType, fields)
	local version = GameEvents.VERSIONS[eventType]
	if not version then
		-- Unknown types are dropped rather than stored: an unversioned row is
		-- one the console cannot interpret later, and a typo should be loud
		-- here rather than silent in a chart six weeks from now.
		logger.warn("[Console] refusing to emit unknown event type '%s'", tostring(eventType))
		return false
	end

	fields = fields or {}
	local pos = fields.position
	local x, y, z
	if pos then
		x, y, z = pos.x, pos.y, pos.z
	end

	local query = string.format(
		"INSERT INTO `game_events` " ..
		"(`ts`, `type`, `version`, `account_id`, `player_id`, `subject_type`, `subject_id`, " ..
		"`pos_x`, `pos_y`, `pos_z`, `payload`) " ..
		"VALUES (%d, %s, %d, %s, %s, %s, %s, %s, %s, %s, %s)",
		os.time(),
		escaped(eventType),
		version,
		numberOrNull(fields.accountId),
		numberOrNull(fields.playerId),
		fields.subjectType and escaped(fields.subjectType) or "NULL",
		fields.subjectId and escaped(fields.subjectId) or "NULL",
		numberOrNull(x), numberOrNull(y), numberOrNull(z),
		fields.payload and escaped(json.encode(fields.payload)) or "NULL"
	)

	if fields.sync then
		return db.query(query)
	end
	return db.asyncQuery(query)
end

--- Convenience: emit for a player, filling in account, guid and position.
function GameEvents.emitForPlayer(eventType, player, payload, subjectType, subjectId)
	if not player then
		return false
	end
	return GameEvents.emit(eventType, {
		accountId = player:getAccountId(),
		playerId = player:getGuid(),
		position = player:getPosition(),
		subjectType = subjectType,
		subjectId = subjectId,
		payload = payload,
	})
end

-- --------------------------------------------------------------- sessions

-- guid -> session row id, so logout can close the row it opened without a
-- lookup. Lost on restart, which is exactly what crash recovery is for.
local openSessions = {}

--- Masks an IP to its /24. The console never needs the host part, and this way
--- the raw address is not sitting in a table the agent can read.
local function maskIp(intIp)
	if not intIp or intIp == 0 then
		return "0.0.0.0"
	end
	local b1 = intIp % 256
	local b2 = math.floor(intIp / 256) % 256
	local b3 = math.floor(intIp / 65536) % 256
	return string.format("%d.%d.%d.0", b1, b2, b3)
end

function Sessions.open(player)
	if not player then
		return
	end
	local guid = player:getGuid()
	local now = os.time()

	-- storeQuery rather than asyncQuery: the row id is needed to close the
	-- session later, and this runs once per login rather than per tick.
	local ok = db.query(string.format(
		"INSERT INTO `player_sessions` " ..
		"(`account_id`, `player_id`, `login_at`, `ip_masked`, `client_version`, `level_in`, `town_in`) " ..
		"VALUES (%d, %d, %d, %s, %s, %d, %d)",
		player:getAccountId(),
		guid,
		now,
		escaped(maskIp(player:getIp())),
		escaped(tostring(player:getClient() and player:getClient().version or "")),
		player:getLevel(),
		player:getTown() and player:getTown():getId() or 0
	))
	if ok then
		openSessions[guid] = db.lastInsertId()
	end
end

--- Closes an open session row.
-- `sync` is for the shutdown path, where a queued query would never be flushed
-- and every session would be left open for the next boot to recover.
function Sessions.close(player, reason, sync)
	if not player then
		return
	end
	local guid = player:getGuid()
	local sessionId = openSessions[guid]
	openSessions[guid] = nil
	if not sessionId then
		return
	end

	local now = os.time()
	local query = string.format(
		"UPDATE `player_sessions` SET `logout_at` = %d, `duration` = %d - `login_at`, " ..
		"`close_reason` = %s, `level_out` = %d WHERE `id` = %d AND `logout_at` IS NULL",
		now, now, escaped(reason or "logout"), player:getLevel(), sessionId)

	if sync then
		db.query(query)
	else
		db.asyncQuery(query)
	end
end

--- Counts a chat message against the current session.
-- Content is never stored: only that a message happened, on what kind of
-- channel. That is enough for activity charts and for spotting a bot's
-- cadence, and it keeps the console clear of player conversation.
function Sessions.countChat(player, isPrivate)
	if not player then
		return
	end
	-- Counted for the fingerprint whether or not a session row exists. A
	-- player who talks is the single cheapest evidence that somebody is at
	-- the keyboard, so it must not be lost to a missing session row.
	if Activity then
		Activity.recordChat(player)
	end

	local sessionId = openSessions[player:getGuid()]
	if not sessionId then
		return
	end
	local column = isPrivate and "chat_private" or "chat_public"
	db.asyncQuery(string.format(
		"UPDATE `player_sessions` SET `%s` = `%s` + 1 WHERE `id` = %d", column, column, sessionId))
end

--- Closes rows left open by a crash. Called at startup, before any login can
--- create a new one. `lastlogout` is the best available estimate of when the
--- character actually stopped playing; where it is missing the login time is
--- used, which produces a zero-length session rather than a false marathon.
function Sessions.recoverOrphans()
	db.query([[
		UPDATE `player_sessions` s
		INNER JOIN `players` p ON p.`id` = s.`player_id`
		SET s.`logout_at` = GREATEST(COALESCE(NULLIF(p.`lastlogout`, 0), s.`login_at`), s.`login_at`),
		    s.`duration` = GREATEST(COALESCE(NULLIF(p.`lastlogout`, 0), s.`login_at`), s.`login_at`) - s.`login_at`,
		    s.`close_reason` = 'crash_recovery'
		WHERE s.`logout_at` IS NULL
	]])
end

--- True while the given character has an open session row this boot.
function Sessions.isTracked(guid)
	return openSessions[guid] ~= nil
end

-- ---------------------------------------------------------------- metrics

--- Writes one sample. `tags` is optional and must be a flat table.
function Metrics.write(metric, value, tags)
	local tagsJson = tags and json.encode(tags) or nil
	-- The hash is what makes (metric, ts, tags) a primary key without putting
	-- a variable-length JSON blob in it. An empty tag set hashes to '' rather
	-- than to the hash of "null", so untagged series stay readable in SQL.
	local hash = ""
	if tagsJson then
		hash = string.sub(tostring(tagsJson):gsub("%W", ""), 1, 32)
	end

	db.asyncQuery(string.format(
		"INSERT INTO `server_metrics` (`metric`, `ts`, `tags_hash`, `value`, `tags`) " ..
		"VALUES (%s, %d, %s, %f, %s) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)",
		escaped(metric),
		-- Align to the minute so a sampler that drifts still produces one row
		-- per minute rather than a smear the console has to bucket itself.
		math.floor(os.time() / 60) * 60,
		escaped(hash),
		tonumber(value) or 0,
		tagsJson and escaped(tagsJson) or "NULL"
	))
end

-- ------------------------------------------------------------------ kills

-- Kill counters, buffered.
--
-- A busy hour is thousands of monster deaths. One row per kill would be
-- millions of rows a month for something nobody reads individually, and one
-- query per kill would put a database round trip inside the death handler.
-- Instead kills accumulate in this table and are flushed as aggregated
-- UPSERTs, so a hunted spawn costs one row per hour no matter how hard it is
-- hunted.
--
-- What is lost on a crash is at most one flush interval of counts. That is the
-- right trade for a metric: an approximate kill count is useful, a stutter in
-- combat is not.

Kills = Kills or {}

local pending = {}       -- monster name -> {kills = n, boss = bool}
local pendingCount = 0

--- Counts one kill. Cheap by design: two table lookups and an add.
function Kills.record(name, isBoss)
	name = tostring(name or "")
	if name == "" then
		return
	end

	local entry = pending[name]
	if entry then
		entry.kills = entry.kills + 1
	else
		pending[name] = {kills = 1, boss = isBoss and true or false}
		pendingCount = pendingCount + 1
	end
end

--- Writes everything buffered and empties the buffer.
-- Both grains are written from the same buffer in one pass, so the hourly and
-- daily tables can never disagree about a kill.
--
-- `sync` is for the shutdown path only. An async query is handed to a worker
-- thread the process does not wait for, so anything still buffered when the
-- server stops would simply be lost.
function Kills.flush(sync)
	if pendingCount == 0 then
		return 0
	end

	local buffered = pending
	local count = pendingCount
	pending = {}
	pendingCount = 0

	local now = os.time()
	local hour = math.floor(now / 3600) * 3600
	local day = os.date("%Y-%m-%d", now)

	-- Batched into multi-row INSERTs: 300 distinct monsters in an hour would
	-- otherwise be 600 statements every flush.
	local hourlyValues, dailyValues = {}, {}
	for name, entry in pairs(buffered) do
		local escapedName = db.escapeString(name)
		local boss = entry.boss and 1 or 0
		hourlyValues[#hourlyValues + 1] =
			string.format("(%d, %s, %d, %d)", hour, escapedName, entry.kills, boss)
		dailyValues[#dailyValues + 1] =
			string.format("(%s, %s, %d, %d)", db.escapeString(day), escapedName, entry.kills, boss)
	end

	local write = sync and db.query or db.asyncQuery

	write(
		"INSERT INTO `monster_kills_hourly` (`hour_ts`, `monster_name`, `kills`, `boss`) VALUES " ..
		table.concat(hourlyValues, ", ") ..
		" ON DUPLICATE KEY UPDATE `kills` = `kills` + VALUES(`kills`), `boss` = VALUES(`boss`)")

	write(
		"INSERT INTO `monster_kills_daily` (`day`, `monster_name`, `kills`, `boss`) VALUES " ..
		table.concat(dailyValues, ", ") ..
		" ON DUPLICATE KEY UPDATE `kills` = `kills` + VALUES(`kills`), `boss` = VALUES(`boss`)")

	return count
end

--- How many distinct monsters are waiting to be written. For the console's
--- own health tile, and for deciding whether a shutdown flush is worth it.
function Kills.pending()
	return pendingCount
end

-- --------------------------------------------------------- boss encounters

Bosses = Bosses or {}

-- monster id -> encounter row id, so the death handler can close the row its
-- spawn opened without a lookup. Lost on restart, which is correct: an
-- encounter the server no longer remembers is one nobody can still be fighting.
local openEncounters = {}

--- Opens an encounter row when a boss appears.
-- Synchronous because the row id is needed to close it later, and a boss
-- spawning is rare enough that one INSERT costs nothing.
function Bosses.opened(monster, source, position)
	if not monster then
		return
	end

	local ok = db.query(string.format(
		"INSERT INTO `boss_encounters` " ..
		"(`monster_name`, `spawned_at`, `source`, `pos_x`, `pos_y`, `pos_z`) " ..
		"VALUES (%s, %d, %s, %s, %s, %s)",
		db.escapeString(monster:getName()),
		os.time(),
		db.escapeString(source or "spawn"),
		position and tostring(math.floor(position.x)) or "NULL",
		position and tostring(math.floor(position.y)) or "NULL",
		position and tostring(math.floor(position.z)) or "NULL"))

	if ok then
		openEncounters[monster:getId()] = db.lastInsertId()
	end
end

--- Closes the encounter this boss opened.
-- Guarded on `killed_at IS NULL` so a replay can never overwrite a kill, and
-- silently does nothing for a boss whose spawn this run did not see -- which
-- is every boss already standing when the server booted.
function Bosses.killed(monster, killerName, byPlayer)
	if not monster then
		return
	end
	local monsterId = monster:getId()
	local encounterId = openEncounters[monsterId]
	openEncounters[monsterId] = nil
	if not encounterId then
		return
	end

	local now = os.time()
	db.asyncQuery(string.format(
		"UPDATE `boss_encounters` SET `killed_at` = %d, `seconds_alive` = %d - `spawned_at`, " ..
		"`killer_name` = %s, `by_player` = %d WHERE `id` = %d AND `killed_at` IS NULL",
		now, now,
		killerName and db.escapeString(killerName) or "NULL",
		byPlayer and 1 or 0,
		encounterId))
end

--- Forgets an encounter without recording a kill, for a boss that despawned.
function Bosses.forget(monsterId)
	openEncounters[monsterId] = nil
end

-- ------------------------------------------------------------------- loot

-- What the server actually put in each corpse.
--
-- Buffered exactly like Kills, and flushed in the same pass, which is what
-- makes a drop rate trustworthy: drops and the corpses they came from are
-- written together, so a flush lost to a crash loses both and leaves the
-- ratio unbiased rather than inflating it.
--
-- The distinction this module exists to preserve is `plain` versus everything
-- else. The loot generator gives extra roll passes whenever a modifier is
-- active, so a corpse rolled under a boost cannot be compared against the
-- configured chance. Only plain corpses go in the comparable denominator.

Loot = Loot or {}

-- monster name -> {corpses, plain, boosted, blocked, empty, items = {[id] = {...}}}
local lootPending = {}
local lootPendingCount = 0

local function monsterBucket(name)
	local bucket = lootPending[name]
	if not bucket then
		bucket = {corpses = 0, plain = 0, boosted = 0, blocked = 0, empty = 0, items = {}}
		lootPending[name] = bucket
		lootPendingCount = lootPendingCount + 1
	end
	return bucket
end

--- Records one corpse and everything in it.
-- @param name string monster name
-- @param items table array of {id, count, rare}
-- @param state string "plain" | "boosted" | "blocked"
function Loot.record(name, items, state)
	name = tostring(name or "")
	if name == "" then
		return
	end

	local bucket = monsterBucket(name)
	bucket.corpses = bucket.corpses + 1
	bucket[state] = (bucket[state] or 0) + 1

	if #items == 0 then
		bucket.empty = bucket.empty + 1
		return
	end

	-- A stack of 97 gold is ONE drop of quantity 97. Collapsing the two would
	-- make gold read as a guaranteed drop of a single coin.
	local seen = {}
	for _, entry in ipairs(items) do
		local row = bucket.items[entry.id]
		if not row then
			row = {drops = 0, quantity = 0, plain = 0, rare = 0}
			bucket.items[entry.id] = row
		end
		row.quantity = row.quantity + (entry.count or 1)
		if entry.rare then
			row.rare = row.rare + 1
		end
		if not seen[entry.id] then
			seen[entry.id] = true
			row.drops = row.drops + 1
			if state == "plain" then
				row.plain = row.plain + 1
			end
		end
	end
end

--- Writes everything buffered. `sync` is for the shutdown path only.
function Loot.flush(sync)
	if lootPendingCount == 0 then
		return 0
	end

	local buffered = lootPending
	local count = lootPendingCount
	lootPending = {}
	lootPendingCount = 0

	local day = db.escapeString(os.date("%Y-%m-%d", os.time()))
	local write = sync and db.query or db.asyncQuery

	local corpseValues, lootValues = {}, {}
	for name, bucket in pairs(buffered) do
		local escapedName = db.escapeString(name)
		corpseValues[#corpseValues + 1] = string.format("(%s, %s, %d, %d, %d, %d, %d)",
			day, escapedName, bucket.corpses, bucket.plain, bucket.boosted, bucket.blocked, bucket.empty)

		for itemId, row in pairs(bucket.items) do
			lootValues[#lootValues + 1] = string.format("(%s, %s, %d, %d, %d, %d, %d)",
				day, escapedName, itemId, row.drops, row.quantity, row.plain, row.rare)
		end
	end

	write(
		"INSERT INTO `monster_corpses_daily` " ..
		"(`day`, `monster_name`, `corpses`, `corpses_plain`, `corpses_boosted`, `corpses_blocked`, `empty_corpses`) " ..
		"VALUES " .. table.concat(corpseValues, ", ") ..
		" ON DUPLICATE KEY UPDATE `corpses` = `corpses` + VALUES(`corpses`), " ..
		"`corpses_plain` = `corpses_plain` + VALUES(`corpses_plain`), " ..
		"`corpses_boosted` = `corpses_boosted` + VALUES(`corpses_boosted`), " ..
		"`corpses_blocked` = `corpses_blocked` + VALUES(`corpses_blocked`), " ..
		"`empty_corpses` = `empty_corpses` + VALUES(`empty_corpses`)")

	if #lootValues > 0 then
		-- Chunked: a heavily hunted hour can touch a few thousand
		-- (monster, item) pairs, and one statement that long is a packet
		-- problem rather than a query problem.
		local CHUNK = 400
		for start = 1, #lootValues, CHUNK do
			local slice = {}
			for i = start, math.min(start + CHUNK - 1, #lootValues) do
				slice[#slice + 1] = lootValues[i]
			end
			write(
				"INSERT INTO `monster_loot_daily` " ..
				"(`day`, `monster_name`, `item_id`, `drops`, `quantity`, `plain_drops`, `rare_drops`) " ..
				"VALUES " .. table.concat(slice, ", ") ..
				" ON DUPLICATE KEY UPDATE `drops` = `drops` + VALUES(`drops`), " ..
				"`quantity` = `quantity` + VALUES(`quantity`), " ..
				"`plain_drops` = `plain_drops` + VALUES(`plain_drops`), " ..
				"`rare_drops` = `rare_drops` + VALUES(`rare_drops`)")
		end
	end

	return count
end

function Loot.pending()
	return lootPendingCount
end

-- ------------------------------------------------------------- activity

-- The botting fingerprint: four numbers per player-hour.
--
-- A bot is not any one of these being unusual. A dedicated player has a high
-- kill rate; a fisherman stands still; a quiet person does not chat; anyone
-- can play for six hours. What almost nobody does is all four at once, for
-- hours, without a break -- and the 15-minute idle kick means an unbroken
-- session required continuous input the whole time.
--
-- This records; it never judges. The detector in the console reads these rows
-- and opens a case for a person to look at, and the numbers here are an
-- indicator rather than proof. That distinction is the whole reason the
-- fingerprint is four cheap counters instead of a clever score: a number
-- somebody has to interpret invites interpretation, and a score invites
-- trusting it.

Activity = Activity or {}

-- player id -> {kills, exp, chat, level, tiles = {key -> true}, tileCount,
--               lastExp, hour}
local activityPending = {}
local activityPendingCount = 0

local function activityEntry(playerId, hour)
	local entry = activityPending[playerId]
	-- A new hour is a new row, so the buffer is reset rather than carried
	-- over. Otherwise the distinct-tile set would span hours and a player who
	-- moved once an hour would look like one who never stopped moving.
	if not entry or entry.hour ~= hour then
		if not entry then
			activityPendingCount = activityPendingCount + 1
		end
		entry = {
			hour = hour, kills = 0, exp = 0, chat = 0, level = 0,
			tiles = {}, tileCount = 0, samples = 0, lastExp = nil,
		}
		activityPending[playerId] = entry
	end
	return entry
end

local function currentHour()
	return math.floor(os.time() / 3600) * 3600
end

--- One kill, credited to the player who earned it.
function Activity.recordKill(player)
	if not player then
		return
	end
	local entry = activityEntry(player:getGuid(), currentHour())
	entry.kills = entry.kills + 1
end

--- One line of chat. Called from Sessions.countChat, which already runs on
--- every message and already knows whether it was public or private.
function Activity.recordChat(player)
	if not player then
		return
	end
	local entry = activityEntry(player:getGuid(), currentHour())
	entry.chat = entry.chat + 1
end

--- The once-a-minute sample: where they are standing, and how much experience
--- they have gained since the last look.
--
-- Position is reduced to a tile key rather than stored as a trail. "Stood on
-- eight distinct tiles in an hour" is the fact that matters and is one
-- number; a trail would be a movement log of a named person, which is a far
-- heavier thing to keep and answers no question this needs to ask.
function Activity.sample(player)
	if not player then
		return
	end

	local entry = activityEntry(player:getGuid(), currentHour())
	entry.samples = entry.samples + 1
	entry.level = player:getLevel()

	local position = player:getPosition()
	local key = position.x * 100000 + position.y * 16 + position.z
	if not entry.tiles[key] then
		entry.tiles[key] = true
		entry.tileCount = entry.tileCount + 1
	end

	local experience = player:getExperience()
	if entry.lastExp and experience > entry.lastExp then
		entry.exp = entry.exp + (experience - entry.lastExp)
	end
	entry.lastExp = experience
end

--- Writes the buffer. Kept separate from Kills.flush only in name: it is
--- called from the same timer, so a lost flush loses both together and the
--- kill rate stays consistent with the hours it was earned in.
function Activity.flush(sync)
	if activityPendingCount == 0 then
		return 0
	end

	local values = {}
	local written = 0
	local hour = currentHour()

	for playerId, entry in pairs(activityPending) do
		if entry.kills > 0 or entry.exp > 0 or entry.chat > 0 or entry.samples > 0 then
			values[#values + 1] = string.format("(%d, %d, %d, %d, %d, %d, %d, %d)",
				entry.hour, playerId, entry.kills, entry.exp, entry.tileCount,
				entry.samples, entry.chat, entry.level)
			written = written + 1
		end

		-- Counters reset, the tile set does not: it belongs to the hour, and
		-- the column is written with GREATEST so a later flush in the same
		-- hour carries the superset rather than double-counting.
		entry.kills, entry.exp, entry.chat, entry.samples = 0, 0, 0, 0
		if entry.hour ~= hour then
			activityPending[playerId] = nil
			activityPendingCount = activityPendingCount - 1
		end
	end

	if written == 0 then
		return 0
	end

	local write = sync and db.query or db.asyncQuery
	write(
		"INSERT INTO `player_activity_hourly` (`hour`, `player_id`, `kills`, `exp_gained`, " ..
		"`tiles_distinct`, `samples`, `chat`, `level`) VALUES " .. table.concat(values, ", ") ..
		" ON DUPLICATE KEY UPDATE `kills` = `kills` + VALUES(`kills`), " ..
		"`exp_gained` = `exp_gained` + VALUES(`exp_gained`), " ..
		"`tiles_distinct` = GREATEST(`tiles_distinct`, VALUES(`tiles_distinct`)), " ..
		"`samples` = `samples` + VALUES(`samples`), " ..
		"`chat` = `chat` + VALUES(`chat`), `level` = VALUES(`level`)")

	return written
end

--- Forgets a player who has logged out. Their final counts are flushed first
--- by the caller; keeping the entry would hold a tile set for somebody who is
--- no longer generating one.
function Activity.forget(playerId)
	if activityPending[playerId] then
		activityPending[playerId] = nil
		activityPendingCount = activityPendingCount - 1
	end
end

function Activity.pending()
	return activityPendingCount
end
