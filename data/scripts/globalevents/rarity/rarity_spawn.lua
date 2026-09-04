-- Item Rarity system — activates the combat-modifier CreatureEvents on every
-- spawned monster. Unlike Bao's own spawn hook (which only registers events
-- on monsters relevant to a configured hunt), this is deliberately
-- unconditional: rarity rolls fire on ALL qualifying monster drops
-- server-wide (per design decision), so any monster could plausibly deal
-- damage to a player wearing rolled gear, or take damage from a player
-- wielding rolled gear -- both directions need the target's health/mana
-- change event registered to fire at all (this fork's healthchange/
-- manachange events dispatch off the TARGET's registration, not the
-- attacker's -- confirmed against src/game.cpp's combatChangeHealth/Mana
-- call sites). Mirrors data/scripts/globalevents/bao/bao_spawn.lua's
-- structural pattern.

local raritySpawn = MonsterEvent and MonsterEvent("RaritySpawn") or Event()

function raritySpawn.onSpawn(monster)
	if monster then
		monster:registerEvent("RarityHealthChange")
		monster:registerEvent("RarityManaChange")
	end
	return true
end

raritySpawn:register()
