-- Periodic player autosave (docs/security/dupe-and-crash-audit-2026-09-08.md)
--
-- Before this file existed a player was written to the database on logout and
-- at the 09:55 ServerSave, and at no other time. A crash therefore rolled
-- every online player back by up to a day, which turns every crash bug into
-- a duplication bug: give value away, get the server to fall over, log back
-- in with it.
--
-- This sweep runs once a minute and queues an asynchronous save for every
-- player whose last queued save is older than AUTOSAVE_AFTER_MS, at most
-- MAX_PER_TICK of them per run so a full server is spread across the window
-- instead of hitting the save worker in one burst. It goes through
-- Player.saveOnTransfer, so it shares the coalescing and retry logic with the
-- transfer saves and never blocks the dispatcher.
--
-- Deliberately NOT saveServer()/saveAll(): that path closes the game and
-- kicks players, which is a server save, not an autosave.
--
-- Deliberately NOT :type("think"): a think globalevent silently disables the
-- other think events (see console_telemetry.lua). :interval() is the shape.

local TICK_MS = 60 * 1000
local AUTOSAVE_AFTER_MS = 10 * 60 * 1000
local MAX_PER_TICK = 60

-- Security audit 2026-10-05 (PERS-1/PERS-2). Until now the KV store (gems,
-- wheel points and tokens, boss cooldowns, battle pass, Bao ledger), game and
-- account storage and house items were written ONLY at the 09:55 ServerSave
-- and on a clean shutdown, while players are autosaved every 10 minutes. A
-- crash therefore rolled a sold gem back into its owner's list while the gold
-- stayed in the bank: one dupe per gem per crash. saveWorldState() is the
-- C++ half of saveAll() without the player kick/snapshot; it runs on the
-- dispatcher and costs one house-items INSERT (about 2.5 MB on prod).
local WORLD_SAVE_EVERY_TICKS = 10
local worldTick = 0

-- Players who logged in this session but have never been saved by us yet get
-- their "last save" clock started at first sight, so a fresh login is not
-- saved a second later for nothing (login already loaded them from disk).
local firstSeen = {}

local autosave = GlobalEvent("PlayerAutosave")

function autosave.onTime(interval)
	local now = os.mtime()
	local due = {}
	local online = Game.getPlayers()

	for _, player in ipairs(online) do
		if player:isPlayer() and not player:isRemoved() then
			local guid = player:getGuid()
			local age = player:getIntegritySaveAge()
			if age == nil then
				if not firstSeen[guid] then
					firstSeen[guid] = now
				end
				age = now - firstSeen[guid]
			end
			if age >= AUTOSAVE_AFTER_MS then
				due[#due + 1] = { player = player, age = age }
			end
		end
	end

	-- Oldest first, so a player who keeps missing the cut cannot starve.
	table.sort(due, function(a, b) return a.age > b.age end)

	local saved = 0
	for i = 1, math.min(#due, MAX_PER_TICK) do
		local player = due[i].player
		if player:saveOnTransfer("autosave") then
			firstSeen[player:getGuid()] = nil
			saved = saved + 1
		end
	end

	if saved > 0 then
		logger.info("[Autosave] queued %d of %d online players (%d were due)", saved, #online, #due)
	end

	-- Forget players who are gone so the table does not grow forever.
	if #online == 0 then
		firstSeen = {}
	end

	worldTick = worldTick + 1
	if worldTick >= WORLD_SAVE_EVERY_TICKS then
		worldTick = 0
		if saveWorldState then
			if not saveWorldState() then
				logger.warn("[Autosave] world state save reported errors (see SaveManager lines above)")
			end
		end
	end
	return true
end

autosave:interval(TICK_MS)
autosave:register()
