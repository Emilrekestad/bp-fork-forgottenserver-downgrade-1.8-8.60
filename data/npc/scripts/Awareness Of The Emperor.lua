-- Awareness of the Emperor: the last piece of the Emperor's mind, freed when Zalamon falls.
-- He thanks the player and, on "yes", sends them to the reward room.
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()					end

local MISSION_5, MISSION_6 = 13006, 13014
local REWARD_ROOM = Position(33075, 31172, 8)

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	local state = player:getStorageValue(MISSION_5)

	if state < 3 then
		npcHandler:say("I am not meant to speak to you yet. Finish what the dragon asked of you.", cid)
		return true
	end

	if msgcontains(msg, "yes") then
		if player:getStorageValue(MISSION_5) < 4 then
			player:setStorageValue(MISSION_5, 4)
		end
		if player:getStorageValue(MISSION_6) < 1 then
			player:setStorageValue(MISSION_6, 1)
		end
		npcHandler:say("Then go. You have earned everything in that room.", cid)
		npcHandler.topic[cid] = 0
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		player:teleportTo(REWARD_ROOM)
		REWARD_ROOM:sendMagicEffect(CONST_ME_TELEPORT)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Choose wisely: one of the three chests, and the wardrobe with the Wayfarer outfit.")
		npcHandler:releaseFocus(cid)
		return true
	elseif msgcontains(msg, "no") then
		npcHandler:say("Take your time. I will be here.", cid)
		npcHandler.topic[cid] = 0
		return true
	elseif msgcontains(msg, "reward") then
		npcHandler:say("Are you ready for your reward?", cid)
		npcHandler.topic[cid] = 1
		return true
	end
	return false
end

keywordHandler:addKeyword({ "dragon" }, StdModule.say, { npcHandler = npcHandler, text = "She sleeps without pain for the first time in a thousand years. You did that." })
keywordHandler:addKeyword({ "zalamon" }, StdModule.say, { npcHandler = npcHandler, text = "He was our friend and he was the Emperor's tool, and he was never given the choice. He is free of it now." })
keywordHandler:addKeyword({ "emperor" }, StdModule.say, { npcHandler = npcHandler, text = "I am what is left of his awareness, the part that never wanted any of this. The rest of him cannot hurt Zao any more." })
keywordHandler:addKeyword({ "name" }, StdModule.say, { npcHandler = npcHandler, text = "I am the Awareness of the Emperor. It is a long name for a very small thing." })

npcHandler:setMessage(MESSAGE_GREET, "|PLAYERNAME|... You did it. You freed Zalamon and ended the curse. The Zao region is alleviated, and the {dragon} is finally at peace. Are you ready for your {reward}?")
npcHandler:setMessage(MESSAGE_FAREWELL, "Go well, |PLAYERNAME|. Zao will remember you.")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Go well. Zao will remember you.")

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())
