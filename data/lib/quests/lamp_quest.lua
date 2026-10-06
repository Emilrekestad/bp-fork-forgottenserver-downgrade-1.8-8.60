-- "The Lamp That Wanted a Job" -- the hireling starter quest.
--
-- One shared definition, because seven scripts have to agree on it and they do
-- not all live in the same Lua interface: five NPC scripts (the npc interface,
-- which loads data/lib/lib.lua via src/npc.cpp:1125), two Actions and one
-- GlobalEvent (the scripts interface, which loads the same file via
-- src/scriptmanager.cpp:89). Putting the storage keys, item ids and the two
-- world positions anywhere else would mean maintaining them twice.
--
-- The reward is a real hireling: Player:addNewHireling(name, sex, "hand")
-- (data/scripts/lib/hireling.lua). The lamp a hireling lives in is item 29432
-- and cannot be handed out any other way -- it is unmovable and carries a
-- custom attribute naming one row of `player_hirelings`. The lamp carried
-- during the quest is a different, dead item (2916, "used lamp"), which is a
-- prop and nothing else.

LampQuest = {}

-- Deliberately early. This is the entry point to the whole hireling system,
-- so it must not sit behind premium, a Bao rank or another quest.
LampQuest.MIN_LEVEL = 40

-- Reserved range 51000-51099. Verified free: data/XML/quests.xml tops out at
-- 50719 and nothing in lib/core/storages.lua uses 51xxx.
LampQuest.Storage = {
	quest = 51000, -- 1 = started, 2 = the lamp is whole
	body = 51001, -- Standstorf: 1 = open, 2 = done
	wick = 51002, -- Beector:    1 = open, 2 = done
	striker = 51003, -- Joel:       1 = open, 2 = stone found, 3 = done
	rite = 51004, -- Soder:      1 = waiting, 2 = ready to light, 3 = lit, 4 = done
	reward = 51005, -- 1 = the hireling has been granted (a second one is refused)
	shape = 51006, -- 1 = male, 2 = female (chosen at the naming)
	stoneGen = 51007, -- generation of the quest-issued flintstone (see below)
}

LampQuest.Item = {
	lamp = 2916, -- used lamp -- the dead prop, and the only quest item
	coal = 12600, -- Firestarters drop it at 15.28%, and they stand next to Standstorf
	torch = 2921, -- lit torch
	honeycomb = 5902, -- Old Wasps drop it at 3%, and they stand next to Beector
	honeycombsNeeded = 10,
	flintstone = 35337, -- greenish flintstone -- no monster drops it, only the pile does
}

-- The striker pile is created at boot by
-- data/scripts/globalevents/quests/lamp_quest_props.lua and used through an
-- Action registered on the exact position, the same pattern the Liberty Bay
-- levers use -- so it needs no unique or action id set in RME, and the
-- owner does not have to place anything by hand.
--
-- Position probed live before being written here (see the map.probe rule):
-- 32583,31669,7 is the southern tip of the Elvenbane main floor (owner's choice, 2026-10-04);
-- the pile glows green there (lamp_quest_props.lua). It used to sit 5 tiles west of Joel.
LampQuest.Prop = {
	strikerPile = { id = 1822, pos = Position(32583, 31669, 7) }, -- stone pile
}

-- Where the lamp is lit (owner 2026-10-03): the fire pit in the mine,
-- north of the stairs down. Soder no longer has a cabin, so the old fire pit
-- under the crag north of it is gone. The rite fires when the player uses the
-- lamp anywhere inside this box; nothing is placed on the map.
LampQuest.RitePlace = { fromx = 32145, tox = 32150, fromy = 31100, toy = 31108, z = 9 }

function LampQuest.inRitePlace(pos)
	local r = LampQuest.RitePlace
	return pos.z == r.z and pos.x >= r.fromx and pos.x <= r.tox and pos.y >= r.fromy and pos.y <= r.toy
end

-- "Alone" for the rite. Small enough that a friend standing on your screen
-- edge does not spoil it, large enough that you cannot both light it at once.
LampQuest.RITE_SOLITUDE_RANGE = 5

function LampQuest.get(player, key)
	return player:getStorageValue(LampQuest.Storage[key])
end

function LampQuest.set(player, key, value)
	return player:setStorageValue(LampQuest.Storage[key], value)
end

function LampQuest.isStarted(player)
	return LampQuest.get(player, "quest") >= 1
end

function LampQuest.isFinished(player)
	return LampQuest.get(player, "reward") >= 1
end

function LampQuest.hasLamp(player)
	return player:getItemCount(LampQuest.Item.lamp) > 0
end

-- Handing the lamp over is its own function because Neck does it twice: once
-- to start the quest, and again, grudgingly, to anyone who has lost it.
-- canDropOnMap is false on purpose: Player:addItem defaults it to TRUE, which
-- dropped the prop at the player's feet on a full backpack and still reported
-- success -- so Neck's "your hands are full" lines could never be reached.
function LampQuest.giveLamp(player)
	return player:addItem(LampQuest.Item.lamp, 1, false) ~= nil
end

-- The greenish flintstone (docs/quest-reworks/13-hireling-build-plan.md, H5).
-- The pile used to refuse anyone at striker 2 even when the stone was gone,
-- while Joel insisted on the stone: a soft lock. The pile now reissues it, and
-- every issue is a generation-stamped personal token
-- (data/lib/quests/access_quest_tokens.lua), so a replacement never leaves two
-- stones that both count -- an older copy in a depot or a friend's backpack
-- stops working the moment a new one is issued.
QuestTokens.define("lamp", "flintstone", {
	itemId = LampQuest.Item.flintstone,
	genKey = LampQuest.Storage.stoneGen,
	description = "Greenish, and cold on one face. Joel will want to see it.",
})

function LampQuest.issueStone(player)
	return QuestTokens.give(player, { { "lamp", "flintstone" } })
end

-- The stone Joel will accept. A character who took an untagged stone from the
-- pile before stones were stamped (no generation ever issued) may hand in that
-- original -- a narrow adoption path, not a generic one: as soon as any stamped
-- stone has been issued, untagged stones stop counting.
function LampQuest.findStone(player)
	local stone = QuestTokens.find(player, "lamp", "flintstone")
	if stone then
		return stone
	end
	if player:getStorageValue(LampQuest.Storage.stoneGen, 0) <= 0 then
		for _, item in ipairs(QuestTokens.carried(player)) do
			if item:getId() == LampQuest.Item.flintstone and not QuestTokens.isToken(item) then
				return item
			end
		end
	end
	return nil
end

function LampQuest.partsDone(player)
	local done = 0
	if LampQuest.get(player, "body") >= 2 then
		done = done + 1
	end
	if LampQuest.get(player, "wick") >= 2 then
		done = done + 1
	end
	if LampQuest.get(player, "striker") >= 3 then
		done = done + 1
	end
	return done
end

-- Called by each of the three part NPCs after their own hand-in. The body has
-- to come before the wick -- Beector will not seat a wick in a bent body --
-- and the striker is independent of both, so whichever part happens to be last
-- is the one that opens the rite; none of them can know that in advance.
function LampQuest.checkWhole(player)
	if LampQuest.partsDone(player) < 3 then
		return false
	end
	if LampQuest.get(player, "rite") >= 2 then
		return false
	end

	LampQuest.set(player, "quest", 2)
	LampQuest.set(player, "rite", 2)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
		"The lamp is whole: a struck body, a spun wick and a striker that bites. It still will not light. Soder said it would not, until it is lit alone in the cold.")
	return true
end

return LampQuest
