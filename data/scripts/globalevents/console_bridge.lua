-- The console's hands and eyes inside the running server.
--
-- Two tables, both following the `bazaar_commands` pattern that already works
-- in production (src/item_bazaar.cpp): status 0 pending, 1 claimed, 2 done,
-- 3 failed, with the claim guarded on still-pending so a restart mid-tick can
-- never execute a row twice.
--
--   agent_queries   read-only questions about live memory state -- who is
--                   where, what is a player's HP, which boosts are running.
--                   None of that is in the database; it only exists in this
--                   process.
--
--   agent_commands  changes to the world. These exist because the console
--                   must never write `players` or `accounts` directly: an
--                   online character's row is overwritten from memory on the
--                   next save, so a direct edit is silently undone. Running
--                   the change here, where the Player object is, is the only
--                   correct way.
--
-- The safety property worth protecting: a command row is ignored unless
-- `confirmed_at` is set, and only a human action in the console UI or through
-- MCP sets it. An agent that decides on its own to hand out coins writes a
-- row that sits there and expires.

local QUERY_POLL_MS = 1000
local COMMAND_POLL_MS = 1000
local MAX_PER_TICK = 16

local STATUS_PENDING, STATUS_CLAIMED, STATUS_DONE, STATUS_FAILED = 0, 1, 2, 3

local function escaped(value)
	return db.escapeString(tostring(value))
end

local function claim(tableName, id)
	return db.query(string.format(
		"UPDATE `%s` SET `status` = %d, `claimed_at` = %d WHERE `id` = %d AND `status` = %d",
		tableName, STATUS_CLAIMED, os.time(), id, STATUS_PENDING)) and db.affectedRows() == 1
end

local function decodeParams(raw)
	if not raw or raw == "" then
		return {}
	end
	local ok, decoded = pcall(json.decode, raw)
	if not ok or type(decoded) ~= "table" then
		return {}
	end
	return decoded
end

-- ---------------------------------------------------------------- queries

local queryHandlers = {}

queryHandlers["players.online"] = function()
	local rows = {}
	for _, player in ipairs(Game.getPlayers()) do
		local position = player:getPosition()
		rows[#rows + 1] = {
			name = player:getName(),
			guid = player:getGuid(),
			account_id = player:getAccountId(),
			level = player:getLevel(),
			vocation = player:getVocation() and player:getVocation():getName() or nil,
			health = player:getHealth(),
			max_health = player:getMaxHealth(),
			town = player:getTown() and player:getTown():getName() or nil,
			x = position.x, y = position.y, z = position.z,
		}
	end
	return {count = #rows, players = rows}
end

queryHandlers["player.state"] = function(params)
	local player = params.name and Player(params.name) or nil
	if not player then
		return {online = false}
	end
	local position = player:getPosition()
	local target = player:getTarget()
	return {
		online = true,
		name = player:getName(),
		guid = player:getGuid(),
		account_id = player:getAccountId(),
		level = player:getLevel(),
		experience = player:getExperience(),
		health = player:getHealth(),
		max_health = player:getMaxHealth(),
		mana = player:getMana(),
		max_mana = player:getMaxMana(),
		soul = player:getSoul(),
		capacity = player:getCapacity(),
		coins = Coins.balance(player:getAccountId()),
		target = target and target:getName() or nil,
		x = position.x, y = position.y, z = position.z,
	}
end

queryHandlers["world.boosts"] = function()
	if not GlobalBoosts then
		return {available = false}
	end
	local active = {}
	for _, entry in ipairs(GlobalBoosts.active()) do
		active[#active + 1] = {
			id = entry.id,
			name = entry.boost and entry.boost.name or tostring(entry.id),
			remaining_seconds = entry.remaining,
			contributor = entry.contributor,
		}
	end
	return {available = true, active = active}
end

queryHandlers["server.uptime"] = function()
	return {
		uptime_seconds = os.time() - (Console.bootTime or os.time()),
		players_online = #Game.getPlayers(),
		boot_time = Console.bootTime,
	}
end

-- ---------------------------------------------------------------- commands

local commandHandlers = {}

commandHandlers["broadcast"] = function(params)
	local text = tostring(params.text or "")
	if text == "" then
		return false, "no text"
	end
	Game.broadcastMessage(text, MESSAGE_STATUS_WARNING)
	return true, "broadcast to " .. #Game.getPlayers() .. " players"
end

commandHandlers["player.message"] = function(params)
	local player = params.name and Player(params.name) or nil
	if not player then
		return false, "player is not online"
	end
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, tostring(params.text or ""))
	return true, "delivered"
end

commandHandlers["kick"] = function(params)
	local player = params.name and Player(params.name) or nil
	if not player then
		return false, "player is not online"
	end
	Sessions.close(player, "kick")
	player:remove()
	return true, "kicked"
end

commandHandlers["coins.grant"] = function(params)
	local amount = math.floor(tonumber(params.amount) or 0)
	if amount == 0 then
		return false, "amount must not be zero"
	end

	-- Resolve by character name so the console never has to know account ids,
	-- and so the audit trail names someone recognisable.
	local accountId, playerGuid, playerName
	if params.name then
		local resultId = db.storeQuery(string.format(
			"SELECT `id`, `account_id`, `name` FROM `players` WHERE LOWER(`name`) = LOWER(%s) LIMIT 1",
			escaped(params.name)))
		if not resultId then
			return false, "no such character"
		end
		playerGuid = result.getNumber(resultId, "id")
		accountId = result.getNumber(resultId, "account_id")
		playerName = result.getString(resultId, "name")
		result.free(resultId)
	elseif params.account_id then
		accountId = math.floor(tonumber(params.account_id))
	end

	if not accountId then
		return false, "no account resolved"
	end

	local ok, moveResult = Coins.move(accountId, amount, "grant.admin", nil, {
		actor = tostring(params.requested_by or "console"),
		reason = tostring(params.reason or ""),
		target_name = playerName,
		via = "console",
	}, playerGuid)

	if not ok then
		return false, tostring(moveResult)
	end

	local online = playerName and Player(playerName) or nil
	if online then
		online:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, amount > 0
			and string.format("You received %d Bp Coins.", amount)
			or string.format("%d Bp Coins were removed from your account.", -amount))
	end

	return true, string.format("balance is now %d", moveResult)
end

commandHandlers["teleport"] = function(params)
	local player = params.name and Player(params.name) or nil
	if not player then
		return false, "player is not online"
	end
	local x, y, z = tonumber(params.x), tonumber(params.y), tonumber(params.z)
	if not x or not y or not z then
		return false, "need x, y and z"
	end
	local destination = Position(x, y, z)
	if not player:teleportTo(destination) then
		return false, "the destination is not reachable"
	end
	destination:sendMagicEffect(CONST_ME_TELEPORT)
	return true, string.format("moved to %d, %d, %d", x, y, z)
end

commandHandlers["boost.start"] = function(params)
	if not GlobalBoosts then
		return false, "the boost system is not loaded"
	end
	local boost = GlobalBoosts.ByKey and GlobalBoosts.ByKey[tostring(params.boost or ""):lower()]
	if not boost then
		return false, "unknown boost"
	end
	local minutes = math.floor(tonumber(params.minutes) or 0)
	if minutes <= 0 then
		return false, "minutes must be positive"
	end
	GlobalBoosts.extend(boost.id, minutes * 60)
	return true, string.format("%s extended by %d minutes", boost.name, minutes)
end

-- ------------------------------------------------------------------ pumps

local function processQueries()
	local resultId = db.storeQuery(string.format(
		"SELECT `id`, `kind`, `params` FROM `agent_queries` WHERE `status` = %d ORDER BY `id` ASC LIMIT %d",
		STATUS_PENDING, MAX_PER_TICK))
	if not resultId then
		return
	end

	local pending = {}
	repeat
		pending[#pending + 1] = {
			id = result.getNumber(resultId, "id"),
			kind = result.getString(resultId, "kind"),
			params = result.getString(resultId, "params"),
		}
	until not result.next(resultId)
	result.free(resultId)

	for _, row in ipairs(pending) do
		if claim("agent_queries", row.id) then
			local handler = queryHandlers[row.kind]
			local payload
			if handler then
				local ok, value = pcall(handler, decodeParams(row.params))
				payload = ok and value or {error = tostring(value)}
			else
				payload = {error = "unknown query kind: " .. tostring(row.kind)}
			end

			db.asyncQuery(string.format(
				"UPDATE `agent_queries` SET `status` = %d, `result` = %s, `completed_at` = %d WHERE `id` = %d",
				payload.error and STATUS_FAILED or STATUS_DONE,
				escaped(json.encode(payload)), os.time(), row.id))
		end
	end
end

local function processCommands()
	-- `confirmed_at IS NOT NULL` is the gate. An unconfirmed row is simply
	-- never selected, so it expires untouched.
	local resultId = db.storeQuery(string.format(
		"SELECT `id`, `kind`, `params`, `requested_by` FROM `agent_commands` " ..
		"WHERE `status` = %d AND `confirmed_at` IS NOT NULL ORDER BY `id` ASC LIMIT %d",
		STATUS_PENDING, MAX_PER_TICK))
	if not resultId then
		return
	end

	local pending = {}
	repeat
		pending[#pending + 1] = {
			id = result.getNumber(resultId, "id"),
			kind = result.getString(resultId, "kind"),
			params = result.getString(resultId, "params"),
			requestedBy = result.getString(resultId, "requested_by"),
		}
	until not result.next(resultId)
	result.free(resultId)

	for _, row in ipairs(pending) do
		if claim("agent_commands", row.id) then
			local handler = commandHandlers[row.kind]
			local ok, message = false, "unknown command kind: " .. tostring(row.kind)
			if handler then
				local params = decodeParams(row.params)
				params.requested_by = row.requestedBy
				local called, a, b = pcall(handler, params)
				if called then
					ok, message = a, b
				else
					ok, message = false, tostring(a)
				end
			end

			db.asyncQuery(string.format(
				"UPDATE `agent_commands` SET `status` = %d, `result_code` = %d, `result_message` = %s, " ..
				"`completed_at` = %d WHERE `id` = %d",
				ok and STATUS_DONE or STATUS_FAILED, ok and 0 or 1,
				escaped(tostring(message or ""):sub(1, 512)), os.time(), row.id))

			-- Every executed command is itself an event, so "what did the
			-- console do last week" is answerable from the same place as
			-- everything else.
			GameEvents.emit("agent.action", {
				subjectType = "command",
				subjectId = tostring(row.id),
				payload = {
					kind = row.kind,
					requested_by = row.requestedBy,
					ok = ok,
					message = tostring(message or ""),
				},
			})
		end
	end
end

local queryPump = GlobalEvent("ConsoleQueryPump")
function queryPump.onThink(interval)
	processQueries()
	return true
end
queryPump:interval(QUERY_POLL_MS)
queryPump:register()

local commandPump = GlobalEvent("ConsoleCommandPump")
function commandPump.onThink(interval)
	processCommands()
	return true
end
commandPump:interval(COMMAND_POLL_MS)
commandPump:register()
