-- Item Rarity system — activates this system's per-player CreatureEvents on
-- every logging-in player (combat modifiers, and Rebirth's death-prepare
-- veto). Without this, they're defined but never registered against a
-- specific creature, so they never fire (this fork requires explicit
-- per-instance opt-in for creature events -- confirmed against
-- src/creature.cpp, no XML auto-registration exists here). Mirrors
-- data/scripts/creaturescripts/harmony.lua's own harmonyLogin pattern.

local rarityLogin = CreatureEvent("RarityLogin")

function rarityLogin.onLogin(player)
	player:registerEvent("RarityHealthChange")
	player:registerEvent("RarityManaChange")
	player:registerEvent("RarityRebirthDeath")
	player:registerEvent("RarityRebirthModal")
	return true
end

rarityLogin:register()
