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
