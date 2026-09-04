-- Old Man Bao — activates the BaoDeath CreatureEvent on any monster instance
-- relevant to a configured hunt. Without this, BaoDeath is defined but never
-- registered against a specific monster, so it never fires. Mirrors
-- custom_bestiary.lua's CustomBestiarySpawn MonsterEvent.

local baoSpawn = MonsterEvent and MonsterEvent("BaoSpawn") or Event()

function baoSpawn.onSpawn(monster)
	if monster and BaoLookup and BaoLookup.getHuntsFor(monster:getName()) then
		monster:registerEvent("BaoDeath")
	end
	return true
end

baoSpawn:register()
