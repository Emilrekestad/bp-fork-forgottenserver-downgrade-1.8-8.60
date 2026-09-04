-- The Enraged Thorn Knight's steed is the fight's last stage: it appears
-- only once the knight himself is dead, never as its own spawnable boss.
local deathEvent = CreatureEvent("EnragedThornKnightDeath")

function deathEvent.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local pos = creature:getPosition()
	local steed = Game.createMonster("Thorn Steed", pos, false, true, CONST_ME_MAGIC_RED)
	if steed then
		steed:say("The steed rears up, riderless and enraged!", TALKTYPE_MONSTER_SAY)
	end
	return true
end

deathEvent:type("death")
deathEvent:register()
