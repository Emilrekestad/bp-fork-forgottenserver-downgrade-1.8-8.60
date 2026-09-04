-- World Missions — Cull tracking. Registers on the same real
-- Monster:onDropLoot event data/scripts/creaturescripts/rarity/
-- rarity_loot_drop.lua already hooks (confirmed working pattern this
-- session) -- fires on every monster death server-wide. Doesn't touch
-- corpse contents at all (only the dying monster's own name/position), so
-- unlike the rarity system it has no ordering dependency on the default
-- loot-creation handler -- registered at index 60 anyway for consistency
-- with how every other rarity/Bao handler on this event explicitly
-- states its index rather than leaving it at the silent default.

-- Reads directly into the Lua Zone implementation's own {name, areas={{
-- from=Position, to=Position}}} shape (data/lib/functions/boss_lever.lua)
-- -- that object is plain Lua, not opaque, and exposes no ready-made
-- "is this position inside me" query of its own (only spectator-based
-- :getCreatures()/:getPlayers()/:countPlayers()), so this is the smallest
-- correct way to ask "did this kill happen inside the mission's zone."
local function isPositionInZone(pos, zone)
	if not zone or not zone.areas then
		return false
	end
	for _, area in ipairs(zone.areas) do
		if pos.z == area.from.z
				and pos.x >= math.min(area.from.x, area.to.x) and pos.x <= math.max(area.from.x, area.to.x)
				and pos.y >= math.min(area.from.y, area.to.y) and pos.y <= math.max(area.from.y, area.to.y) then
			return true
		end
	end
	return false
end

-- `zone` and `monsters` are both optional -- a Cull mission with neither
-- (Oramond: "500,000 total creatures in the world") counts every kill
-- anywhere, no filtering. A mission with just `monsters` but no `zone`
-- would count that monster set anywhere; just `zone` with no `monsters`
-- would count anything killed inside it. All four combinations are valid.
local worldMissionsCull = Event()

function worldMissionsCull.onDropLoot(monster, corpse)
	local monsterName = monster:getName():lower()
	local deathPos = monster:getPosition()

	for missionId, mission in pairs(WorldMissions.Missions) do
		if mission.type == "cull" and WorldMissions.isRevealed(missionId) and not WorldMissions.isApplied(missionId) then
			local matchesMonster = true
			if mission.monsters then
				matchesMonster = false
				for _, name in ipairs(mission.monsters) do
					if name:lower() == monsterName then
						matchesMonster = true
						break
					end
				end
			end

			local matchesZone = not mission.zone or isPositionInZone(deathPos, Zone(mission.zone))

			if matchesMonster and matchesZone then
				WorldMissions.addProgress(missionId, 1)
			end
		end
	end
end

worldMissionsCull:register(60)
