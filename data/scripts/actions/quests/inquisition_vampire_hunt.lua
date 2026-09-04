-- The Inquisition Quest - Vampire Hunt (Mission 3). Ported from the
-- avelino/Otxserver-New reference's inquisition/vampireHunt.lua (2026-08-26),
-- triggered off the actionid startup_quest_map_repair.lua tags onto the 3
-- altar positions (real, confirmed on our map - see that file).
--
-- Simplified from the reference: it checked whether a specific decoration
-- item (its "obelisk", id 2199) was still present on all 3 altars to decide
-- between spawning "The Count" (full fight) or "The Weakened Count" (reward
-- for an intact ritual) - that decoration item isn't present at these
-- coordinates on our map, so that branch is unreachable here. Always spawns
-- "The Count", which is what the reference itself falls back to whenever the
-- altars aren't all intact - i.e. the common case, not a degraded one.
local action = Action()

local VAMPIRE_ALTAR_ACTIONID = 60401

function action.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if item.actionid ~= VAMPIRE_ALTAR_ACTIONID then
		return false
	end

	if player:getStorageValue(Storage.TheInquisition.Questline) ~= 8 then
		return true
	end

	player:setStorageValue(Storage.TheInquisition.Questline, 9)
	player:setStorageValue(Storage.TheInquisition.Mission03, 4) -- The Inquisition Questlog- "Mission 3: Vampire Hunt"
	Game.createMonster("The Count", toPosition)
	return true
end

action:aid(60401)
action:register()
