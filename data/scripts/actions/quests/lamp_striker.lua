-- "The Lamp That Wanted a Job" -- Joel's stone pile.
--
-- Registered on the exact map position rather than on an item id or an action
-- id, the same pattern as data/scripts/actions/worldmissions/
-- worldmissions_liberty_bay_levers.lua and BossLever:register(). A position
-- action wins over the used item's own action (src/actions.cpp:212), so it
-- fires no matter what the player happens to click there, and nothing has to
-- be tagged in RME. The pile itself is created at boot by
-- data/scripts/globalevents/quests/lamp_quest_props.lua.
--
-- The stone is a generation-stamped personal token (LampQuest.issueStone).
-- A player at striker 2 who has lost it can sift the pile again: they get one
-- replacement, and any earlier stone stops counting
-- (docs/quest-reworks/13-hireling-build-plan.md, H5). Progress is never reset,
-- and nobody past striker 3 gets another stone.
local pile = LampQuest.Prop.strikerPile

local NO_ROOM = "You have no room to carry it, and you are not leaving it on the ground after all this."

local action = Action()

function action.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local state = LampQuest.get(player, "striker")

	if state >= 3 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Grey stones, all of them. The greenish one was a one-off, and it is already in your lamp.")
		return true
	end

	if state < 1 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "A pile of stones in the shadow of the cliff. Somebody has clearly never turned it over.")
		return true
	end

	if state == 2 and LampQuest.findStone(player) then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have already taken the greenish flintstone. Joel is the one who wants to see it.")
		return true
	end

	if not LampQuest.issueStone(player) then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, NO_ROOM)
		return true
	end

	pile.pos:sendMagicEffect(CONST_ME_POFF)
	if state == 2 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
			"You sift the shadowed stones again and find another greenish flake. This time, keep it until Joel has fitted it.")
		return true
	end

	LampQuest.set(player, "striker", 2)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
		"You turn the pile over. Third stone down, dull and faintly green, cold on one face: a greenish flintstone. Twelve years of sifting the wrong cliff. Take it back to Joel.")
	return true
end

action:position(pile.pos)
action:register()
