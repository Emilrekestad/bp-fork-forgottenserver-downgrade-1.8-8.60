-- Wires EnragedThornKnightDeath onto every live instance of the monster,
-- mirroring the BaoSpawn/CustomBestiarySpawn pattern used elsewhere for
-- attaching a death hook to a naturally world-spawned monster.
local spawnEvent = MonsterEvent and MonsterEvent("EnragedThornKnightSpawn") or Event()

function spawnEvent.onSpawn(monster)
	if monster and monster:getName():lower() == "the enraged thorn knight" then
		monster:registerEvent("EnragedThornKnightDeath")
	end
	return true
end

spawnEvent:register()
