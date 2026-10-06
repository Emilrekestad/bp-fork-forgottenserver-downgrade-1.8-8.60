-- Rashid's travelling week (11-rashid-build-plan.md, R1).
--
-- One immutable schedule (RashidRework.Schedule) drives this, the journal and
-- the quest log. Rashid is no longer in data/world/world-npc.xml: this script
-- creates him at startup and moves him at the UTC day boundary, and it is the
-- only thing that ever does either.
--
-- Exactly one Rashid. Every check removes extra instances (a reload, a stray
-- spawn entry, a GM's /n) before anything else, and a missing Rashid is only
-- ever recreated, never duplicated. If his stop and both fallbacks are
-- blocked, he stays where he is and RashidRework.current says so, so the
-- journal never claims a town he failed to reach; the next check retries.
--
-- Moving him ends open conversations the ordinary way: his NpcHandler sees the
-- player out of range on its next think, says goodbye and closes the shop
-- window. Any late transaction is refused by Rashid.lua's own range check.
--
-- Deliberately :interval(), not :type("think") -- see autosave_players.lua.

local NAME = "Rashid"
local CHECK_MS = 30 * 1000
local WALK_RADIUS = 1

local function chebyshev(a, b)
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function candidates(stop)
	local list = { stop.pos }
	for _, pos in ipairs(stop.fallback) do
		list[#list + 1] = pos
	end
	return list
end

local function isAtStop(pos, stop)
	for _, candidate in ipairs(candidates(stop)) do
		if pos.z == candidate.z and chebyshev(pos, candidate) <= 3 then
			return true
		end
	end
	return false
end

-- Teleporting a creature ignores what is on the tile, so check it ourselves:
-- a real floor, nothing solid, nobody standing there, not a house, not stairs.
local function placeable(pos)
	local tile = Tile(pos)
	if not tile or not tile:getGround() or tile:getHouse() then
		return false
	end
	if tile:hasFlag(TILESTATE_BLOCKSOLID) or tile:getCreatureCount() > 0 then
		return false
	end
	if TILESTATE_FLOORCHANGE and tile:hasFlag(TILESTATE_FLOORCHANGE) then
		return false
	end
	if TILESTATE_TELEPORT and tile:hasFlag(TILESTATE_TELEPORT) then
		return false
	end
	return true
end

local function stopAt(pos)
	for wday, stop in pairs(RashidRework.Schedule) do
		if pos.z == stop.pos.z and chebyshev(pos, stop.pos) <= 10 then
			return wday, stop
		end
	end
	return nil
end

local function record(npc, placed)
	local wday, stop
	if npc then
		wday, stop = stopAt(npc:getPosition())
	end
	RashidRework.current = {
		placed = placed and stop ~= nil,
		wday = wday,
		town = stop and stop.town or nil,
		host = stop and stop.host or nil,
	}
end

local warnedFor = nil

local function reconcile()
	local wday = RashidRework.utcWday()
	local stop = RashidRework.Schedule[wday]

	local found = {}
	for _, npc in ipairs(Game.getNpcs()) do
		if npc:getName() == NAME then
			found[#found + 1] = npc
		end
	end
	-- Keep one: preferably one already at today's stop.
	table.sort(found, function(a, b)
		return isAtStop(a:getPosition(), stop) and not isAtStop(b:getPosition(), stop)
	end)
	for index = #found, 2, -1 do
		found[index]:remove()
		found[index] = nil
	end

	local npc = found[1]
	if npc and isAtStop(npc:getPosition(), stop) then
		record(npc, true)
		return true
	end

	for _, pos in ipairs(candidates(stop)) do
		if placeable(pos) then
			if npc then
				if npc:teleportTo(pos) then
					npc:setMasterPos(pos, WALK_RADIUS)
					record(npc, true)
					return true
				end
			else
				local created = Game.createNpc(NAME, pos, false, false, CONST_ME_NONE)
				if created then
					created:setMasterPos(pos, WALK_RADIUS)
					record(created, true)
					return true
				end
			end
		end
	end

	record(npc, false)
	local stamp = RashidRework.utcDate()
	if warnedFor ~= stamp then
		warnedFor = stamp
		logWarning(string.format("[RashidSchedule] Could not place Rashid in %s (%d, %d, %d or its fallbacks); retrying every %d s.",
			stop.town, stop.pos.x, stop.pos.y, stop.pos.z, CHECK_MS / 1000))
	end
	return false
end

RashidRework.reconcile = reconcile

local startup = GlobalEvent("RashidScheduleStartup")

function startup.onStartup()
	reconcile()
	-- print, not logInfo: the console level on this server swallows INFO, and
	-- this line is what a deploy check looks for.
	local current = RashidRework.current
	if current and current.placed then
		print(string.format("[RashidSchedule] Rashid is at his cabin (UTC %s).", RashidRework.Schedule[RashidRework.utcWday()].day))
	end
	return true
end

startup:register()

local watch = GlobalEvent("RashidScheduleWatch")

function watch.onThink(interval)
	reconcile()
	return true
end

watch:interval(CHECK_MS)
watch:register()
