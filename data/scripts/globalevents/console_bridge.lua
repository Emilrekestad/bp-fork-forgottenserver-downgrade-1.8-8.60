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
		-- Counts sitting in the telemetry buffers, not yet written. Two uses:
		-- a flush timer that has stopped firing shows up as a number that only
		-- ever grows, and a counter module that failed to load reports nil
		-- rather than zero -- which is the difference between "nothing is
		-- happening" and "nothing is being recorded".
		buffered = {
			kills = Kills and Kills.pending() or nil,
			loot = Loot and Loot.pending() or nil,
			activity = Activity and Activity.pending() or nil,
			rarity = Rarity and Rarity.pending() or nil,
		},
	}
end

-- Answers "would a raid actually put a monster here?" using the exact test the
-- raid engine uses, on the same map, in the same process.
--
-- AreaSpawnEvent::executeEvent (src/raids.cpp) accepts a tile when it exists,
-- is not moveable-blocking, is not a protection zone, and carries no creature.
-- It draws a random tile from the box and gives up after 10 tries per monster,
-- so a single valid tile is not the question -- the DENSITY of valid tiles in
-- the box is what decides whether a raid spawns or announces into an empty
-- mountain. That is what killed the dragon raid, and `pct` below is the number
-- that would have caught it.
--
-- SingleSpawnEvent is far more forgiving: it calls placeCreature with
-- forced = true, which succeeds on any tile that exists at all. `exists` is
-- therefore the whole test for a boss position -- but a forced placement onto
-- a blocking tile leaves the boss shoved into a wall, so `valid` is still what
-- we should aim a boss at.
local PROBE_TILE_BUDGET = 24000

local function tileReport(x, y, z)
	local tile = Tile(x, y, z)
	if not tile then
		return {exists = false}
	end
	local blocking = tile:getGround() == nil or tile:hasFlag(TILESTATE_BLOCKSOLID)
	local pz = tile:hasFlag(TILESTATE_PROTECTIONZONE)
	local creature = tile:getTopCreature() ~= nil
	return {
		exists = true,
		blocking = blocking,
		pz = pz,
		creature = creature,
		house = tile:getHouse() ~= nil,
		valid = not blocking and not pz and not creature,
	}
end

queryHandlers["map.probe"] = function(params)
	local budget = PROBE_TILE_BUDGET
	local result = {points = {}, areas = {}, budget = PROBE_TILE_BUDGET}

	for _, point in ipairs(params.points or {}) do
		local x, y, z = tonumber(point.x), tonumber(point.y), tonumber(point.z)
		local entry = {x = x, y = y, z = z}
		if not (x and y and z) then
			entry.error = "x, y and z are required"
		else
			for key, value in pairs(tileReport(x, y, z)) do
				entry[key] = value
			end
			-- When the asked-for tile is not usable, name the closest one that
			-- is, so a bad coordinate comes back with its own correction
			-- instead of just a "no".
			if not entry.valid then
				local search = math.min(tonumber(point.search) or 4, 10)
				local best
				for dx = -search, search do
					for dy = -search, search do
						local distance = math.max(math.abs(dx), math.abs(dy))
						if distance > 0 and (not best or distance < best.distance) and budget > 0 then
							budget = budget - 1
							local probe = tileReport(x + dx, y + dy, z)
							if probe.valid then
								best = {x = x + dx, y = y + dy, z = z, distance = distance}
							end
						end
					end
				end
				entry.nearest = best
			end
		end
		result.points[#result.points + 1] = entry
	end

	for _, area in ipairs(params.areas or {}) do
		local x, y, z = tonumber(area.x), tonumber(area.y), tonumber(area.z)
		local radius = math.min(tonumber(area.radius) or 10, 30)
		local entry = {x = x, y = y, z = z, radius = radius}
		if not (x and y and z) then
			entry.error = "x, y and z are required"
		else
			local side = radius * 2 + 1
			if side * side > budget then
				entry.error = string.format("probe budget exhausted (%d tiles needed, %d left)", side * side, budget)
			else
				budget = budget - side * side
				local total, exists, valid, pz, blocking, occupied = 0, 0, 0, 0, 0, 0
				-- The centre of mass of the valid tiles: a better raid centre
				-- than the one asked about, because it sits inside the usable
				-- part of the box rather than at the geometric middle.
				local sumX, sumY = 0, 0
				for px = x - radius, x + radius do
					for py = y - radius, y + radius do
						total = total + 1
						local probe = tileReport(px, py, z)
						if probe.exists then
							exists = exists + 1
							if probe.blocking then blocking = blocking + 1 end
							if probe.pz then pz = pz + 1 end
							if probe.creature then occupied = occupied + 1 end
							if probe.valid then
								valid = valid + 1
								sumX, sumY = sumX + px, sumY + py
							end
						end
					end
				end
				entry.total = total
				entry.exists = exists
				entry.valid = valid
				entry.blocking = blocking
				entry.pz = pz
				entry.occupied = occupied
				entry.pct = total > 0 and math.floor(valid / total * 1000 + 0.5) / 10 or 0
				if valid > 0 then
					entry.suggested = {x = math.floor(sumX / valid + 0.5), y = math.floor(sumY / valid + 0.5), z = z}
				end
				-- 10 tries per monster on a uniformly random tile: the chance
				-- that one monster fails to place is (1 - pct)^10. Anything
				-- under about 20% starts dropping monsters visibly.
				entry.verdict = entry.pct >= 25 and "good" or entry.pct >= 10 and "thin" or entry.pct > 0 and "poor" or "dead"
			end
		end
		result.areas[#result.areas + 1] = entry
	end

	result.remaining = budget
	return result
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

	-- The same guard /kick has had all along. Without it the console is a way
	-- to disconnect a gamemaster who is in the middle of dealing with
	-- something, which is the one moment it must not be possible.
	if player:getGroup():getAccess() then
		return false, string.format("%s is staff and cannot be kicked from the console", player:getName())
	end

	Sessions.close(player, "kick")
	player:remove()
	return true, string.format("kicked %s", player:getName())
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

-- ------------------------------------------------- server and world verbs

commandHandlers["server.save"] = function(params)
	local startedAt = os.mtime()
	local onlineBefore = #Game.getPlayers()

	-- The same sequence serversave.lua runs on its timer, minus the warning
	-- countdown: a save asked for by hand is wanted now, and the operator
	-- broadcasts first themselves if they want to warn anyone.
	local closeDuring = configManager.getBoolean(configKeys.SERVER_SAVE_CLOSE)
	if closeDuring then
		Game.setGameState(GAME_STATE_CLOSED)
	end

	saveServer()

	if closeDuring then
		Game.setGameState(GAME_STATE_NORMAL)
	end

	local duration = os.mtime() - startedAt

	-- Emitted with the same type and payload shape as the scheduled save, so
	-- the save-duration chart and the save_drift detector see one series
	-- rather than two. `manual` is what lets a slow hand-run be excluded from
	-- the baseline if it ever needs to be.
	GameEvents.emit("server.save", {
		payload = {
			duration_ms = duration,
			players_online = onlineBefore,
			kicked = 0,
			cleaned_map = false,
			shutdown = false,
			manual = true,
			requested_by = tostring(params.requested_by or "console"),
		},
	})

	return true, string.format("saved in %d ms with %d online", duration, onlineBefore)
end

commandHandlers["server.clean"] = function(params)
	-- cleanMap() prints its own count to the console and returns nothing, so
	-- the message here says what was asked rather than what was removed.
	cleanMap()
	return true, "map cleaned"
end

commandHandlers["server.state"] = function(params)
	local wanted = tostring(params.state or ""):lower()
	local states = {
		normal = GAME_STATE_NORMAL,
		closed = GAME_STATE_CLOSED,
	}
	local target = states[wanted]
	if not target then
		return false, "state must be normal or closed"
	end

	Game.setGameState(target)
	return true, wanted == "closed"
		and "the server is closed; nobody new can log in"
		or "the server is open"
end

commandHandlers["server.restart"] = function(params)
	local minutes = math.floor(tonumber(params.minutes) or 0)
	if minutes < 0 or minutes > 60 then
		return false, "minutes must be between 0 and 60"
	end

	-- Restart, not shutdown, and the difference is entirely in the unit file:
	-- tfs.service is Restart=always, so exiting brings the server back. Under
	-- the old on-failure policy this same call left the server down, which is
	-- why the unit change is a prerequisite of this handler and not a tidy-up.
	local function finish()
		Game.setGameState(GAME_STATE_SHUTDOWN)
	end

	if minutes == 0 then
		Game.broadcastMessage("The server is restarting now.", MESSAGE_STATUS_WARNING)
		addEvent(finish, 2000)
		return true, "restarting now"
	end

	local function step(remaining)
		if remaining <= 0 then
			finish()
			return
		end
		Game.broadcastMessage(string.format(
			"The server is restarting in %d minute%s. Please log out.",
			remaining, remaining == 1 and "" or "s"), MESSAGE_STATUS_WARNING)
		if remaining > 1 then
			addEvent(step, 60000, remaining - 1)
		else
			addEvent(function()
				Game.broadcastMessage("The server is restarting in 30 seconds.", MESSAGE_STATUS_WARNING)
			end, 30000)
			addEvent(function()
				Game.broadcastMessage("The server is restarting in 10 seconds.", MESSAGE_STATUS_WARNING)
			end, 50000)
			addEvent(finish, 60000)
		end
	end

	step(minutes)
	return true, string.format("restarting in %d minute(s); %d online", minutes, #Game.getPlayers())
end

commandHandlers["raid.start"] = function(params)
	local name = tostring(params.name or "")
	if name == "" then
		return false, "no raid named"
	end

	local returnValue = Game.startRaid(name)
	if returnValue ~= RETURNVALUE_NOERROR then
		return false, Game.getReturnMessage(returnValue)
	end
	return true, string.format("raid '%s' started", name)
end

-- ------------------------------------------------------------ enforcement

-- Resolves a character name to the account behind it, and says whether that
-- account is staff. Every enforcement verb starts here so they all agree
-- about who a name refers to and all refuse the same people.
local function resolveTarget(name)
	if not name or name == "" then
		return nil, "no character named"
	end

	local resultId = db.storeQuery(string.format(
		"SELECT `p`.`id`, `p`.`name`, `p`.`account_id`, `p`.`group_id`, `p`.`lastip`, `a`.`type` " ..
		"FROM `players` `p` JOIN `accounts` `a` ON `a`.`id` = `p`.`account_id` " ..
		"WHERE LOWER(`p`.`name`) = LOWER(%s) LIMIT 1", escaped(name)))
	if not resultId then
		return nil, "no such character"
	end

	local target = {
		playerId = result.getNumber(resultId, "id"),
		name = result.getString(resultId, "name"),
		accountId = result.getNumber(resultId, "account_id"),
		groupId = result.getNumber(resultId, "group_id"),
		lastIp = result.getNumber(resultId, "lastip"),
		accountType = result.getNumber(resultId, "type"),
	}
	result.free(resultId)

	-- Staff are deliberately un-bannable from the console. Removing a
	-- colleague's access is a decision that should cost an SSH session, and a
	-- console account that has been taken over must not be able to lock out
	-- the people who would notice.
	target.isStaff = target.accountType >= 2 or target.groupId >= 2
	return target
end

-- Every character of an account, online right now.
local function onlineCharactersOfAccount(accountId)
	local found = {}
	for _, player in ipairs(Game.getPlayers()) do
		if player:getAccountId() == accountId then
			found[#found + 1] = player
		end
	end
	return found
end

-- Sessions.close before remove(), always. Removing a player without it
-- leaves the session row open, and the next startup counts it as a crash
-- recovery -- so a routine kick would quietly look like the server had died.
local function removeWithSession(player, reason)
	Sessions.close(player, reason or "kick")
	player:remove()
end

local function requireBanner(params)
	local bannedBy = math.floor(tonumber(params.banned_by_player_id) or 0)
	if bannedBy <= 0 then
		return nil, "no staff character configured to attribute this to"
	end

	-- account_bans.banned_by is a foreign key to players.id. An id that does
	-- not exist fails the constraint at INSERT time with a message nobody
	-- reading the console would understand, so it is checked here instead.
	local resultId = db.storeQuery(string.format(
		"SELECT 1 FROM `players` WHERE `id` = %d LIMIT 1", bannedBy))
	if not resultId then
		return nil, string.format("the configured staff character (id %d) does not exist", bannedBy)
	end
	result.free(resultId)
	return bannedBy
end

commandHandlers["ban.account"] = function(params)
	local reason = tostring(params.reason or "")
	if reason:gsub("%s", "") == "" then
		return false, "a ban needs a reason"
	end

	local days = math.floor(tonumber(params.days) or 0)
	if days <= 0 or days > 3650 then
		return false, "days must be between 1 and 3650"
	end

	local target, problem = resolveTarget(params.name)
	if not target then
		return false, problem
	end
	if target.isStaff then
		return false, string.format("%s is staff and cannot be banned from the console", target.name)
	end

	local bannedBy, bannerProblem = requireBanner(params)
	if not bannedBy then
		return false, bannerProblem
	end

	-- account_bans is keyed on account_id, so a second ban on a banned
	-- account is a duplicate-key error rather than an extension. Saying so is
	-- more useful than either failing opaquely or silently overwriting
	-- somebody else's ban and its reason.
	local existing = db.storeQuery(string.format(
		"SELECT `expires_at` FROM `account_bans` WHERE `account_id` = %d", target.accountId))
	if existing then
		local expires = result.getNumber(existing, "expires_at")
		result.free(existing)
		return false, string.format("account %d is already banned until %s",
			target.accountId, os.date("%Y-%m-%d %H:%M", expires))
	end

	local now = os.time()
	local ok = db.query(string.format(
		"INSERT INTO `account_bans` (`account_id`, `reason`, `banned_at`, `expires_at`, `banned_by`) " ..
		"VALUES (%d, %s, %d, %d, %d)",
		target.accountId, escaped(reason:sub(1, 255)), now, now + (days * 86400), bannedBy))
	if not ok then
		return false, "the ban could not be written"
	end

	local kicked = {}
	for _, player in ipairs(onlineCharactersOfAccount(target.accountId)) do
		kicked[#kicked + 1] = player:getName()
		removeWithSession(player, "kick")
	end

	return true, string.format("banned account %d for %d day(s)%s", target.accountId, days,
		#kicked > 0 and (", kicked " .. table.concat(kicked, ", ")) or " (nobody was online)")
end

commandHandlers["ban.remove"] = function(params)
	local target, problem = resolveTarget(params.name)
	if not target then
		return false, problem
	end

	local resultId = db.storeQuery(string.format(
		"SELECT `reason`, `banned_at`, `banned_by` FROM `account_bans` WHERE `account_id` = %d",
		target.accountId))
	if not resultId then
		return false, string.format("account %d is not banned", target.accountId)
	end
	local reason = result.getString(resultId, "reason")
	local bannedAt = result.getNumber(resultId, "banned_at")
	local bannedBy = result.getNumber(resultId, "banned_by")
	result.free(resultId)

	-- Into the history table before deleting, so lifting a ban does not erase
	-- the fact that there was one. A player with three lifted bans looks very
	-- different from a player with none, and only the history says which.
	db.query(string.format(
		"INSERT INTO `account_ban_history` (`account_id`, `reason`, `banned_at`, `expired_at`, `banned_by`) " ..
		"VALUES (%d, %s, %d, %d, %d)",
		target.accountId, escaped(reason), bannedAt, os.time(), bannedBy))
	db.query(string.format("DELETE FROM `account_bans` WHERE `account_id` = %d", target.accountId))

	return true, string.format("unbanned account %d (%s)", target.accountId, target.name)
end

commandHandlers["ban.ip"] = function(params)
	local reason = tostring(params.reason or "")
	if reason:gsub("%s", "") == "" then
		return false, "an IP ban needs a reason"
	end

	local days = math.floor(tonumber(params.days) or 0)
	if days <= 0 or days > 3650 then
		return false, "days must be between 1 and 3650"
	end

	local target, problem = resolveTarget(params.name)
	if not target then
		return false, problem
	end
	if target.isStaff then
		return false, string.format("%s is staff and cannot be banned from the console", target.name)
	end

	local bannedBy, bannerProblem = requireBanner(params)
	if not bannedBy then
		return false, bannerProblem
	end

	-- The live address beats the stored one: lastip is only written at
	-- logout, so for somebody who is online right now it is where they were
	-- last time, not where they are.
	local address = target.lastIp
	local online = Player(target.name)
	if online then
		address = online:getIp()
	end
	if not address or address == 0 then
		return false, "no address is known for that character"
	end

	local existing = db.storeQuery(string.format("SELECT 1 FROM `ip_bans` WHERE `ip` = %d", address))
	if existing then
		result.free(existing)
		return false, "that address is already banned"
	end

	local now = os.time()
	local ok = db.query(string.format(
		"INSERT INTO `ip_bans` (`ip`, `reason`, `banned_at`, `expires_at`, `banned_by`) " ..
		"VALUES (%d, %s, %d, %d, %d)",
		address, escaped(reason:sub(1, 255)), now, now + (days * 86400), bannedBy))
	if not ok then
		return false, "the IP ban could not be written"
	end

	local kicked = 0
	for _, player in ipairs(Game.getPlayers()) do
		if player:getIp() == address then
			kicked = kicked + 1
			removeWithSession(player, "kick")
		end
	end

	return true, string.format("banned the address behind %s for %d day(s), kicked %d character(s)",
		target.name, days, kicked)
end

commandHandlers["ban.ip_remove"] = function(params)
	local address = math.floor(tonumber(params.ip) or 0)
	if address <= 0 then
		return false, "no address given"
	end
	db.query(string.format("DELETE FROM `ip_bans` WHERE `ip` = %d", address))
	return true, db.affectedRows() == 1 and "address unbanned" or "that address was not banned"
end

commandHandlers["namelock"] = function(params)
	local reason = tostring(params.reason or "")
	if reason:gsub("%s", "") == "" then
		return false, "a namelock needs a reason"
	end

	local target, problem = resolveTarget(params.name)
	if not target then
		return false, problem
	end
	if target.isStaff then
		return false, string.format("%s is staff and cannot be namelocked from the console", target.name)
	end

	local lockedBy, bannerProblem = requireBanner(params)
	if not lockedBy then
		return false, bannerProblem
	end

	local existing = db.storeQuery(string.format(
		"SELECT 1 FROM `player_namelocks` WHERE `player_id` = %d", target.playerId))
	if existing then
		result.free(existing)
		return false, string.format("%s is already namelocked", target.name)
	end

	local ok = db.query(string.format(
		"INSERT INTO `player_namelocks` (`player_id`, `reason`, `namelocked_at`, `namelocked_by`) " ..
		"VALUES (%d, %s, %d, %d)",
		target.playerId, escaped(reason:sub(1, 255)), os.time(), lockedBy))
	if not ok then
		return false, "the namelock could not be written"
	end

	local online = Player(target.name)
	if online then
		removeWithSession(online, "kick")
	end

	return true, string.format("namelocked %s", target.name)
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
