-- Zalamon, the Emperor's voice. In mission 1 of Wrath of the Emperor, Zlak sends the player to
-- try and talk him into peace; Zalamon shushes them and sets five Lizard Chosen on them.
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()					end

local MISSION_1 = 13002

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	if player:getStorageValue(MISSION_1) == 1 and (msgcontains(msg, "peace") or msgcontains(msg, "zlak") or msgcontains(msg, "settle")) then
		npcHandler:say({
			"Peace? Zlak sent you to talk of PEACE? ...",
			"Hssh. Hush now, little one. Hush. The Emperor does not negotiate with the dying, and I do not negotiate at all. ...",
			"Guards! Show our guest what the Emperor's mercy looks like!"
		}, cid)
		player:setStorageValue(MISSION_1, 2)
		local position = Position(33340, 31410, 8)
		for _ = 1, 5 do
			local chosen = Game.createMonster("Lizard Chosen", position, true, true)
			if chosen then
				chosen:getPosition():sendMagicEffect(CONST_ME_MORTAREA)
			end
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Zalamon silences you and five Lizard Chosen rise up to the west. Zlak was right: there is no peace to be talked. Fight your way out and report back to Zlak in Lizard City.")
		npcHandler:releaseFocus(cid)
		return true
	end
	return false
end

keywordHandler:addKeyword({ "job" }, StdModule.say, { npcHandler = npcHandler, text = "I serve. As you will, in time." })
keywordHandler:addKeyword({ "name" }, StdModule.say, { npcHandler = npcHandler, text = "I was Zalamon. I am what the Emperor needs me to be." })
keywordHandler:addKeyword({ "emperor" }, StdModule.say, { npcHandler = npcHandler, text = "The Emperor is patient. Everything bows to him in the end, even the sleeping dragon." })
keywordHandler:addKeyword({ "dragon" }, StdModule.say, { npcHandler = npcHandler, text = "Hssh. Do not speak of her here." })

npcHandler:setMessage(MESSAGE_GREET, "Not many travellerzz come this far, |PLAYERNAME|. Did Zlak send you to talk of {peace}, perhapzz?")
npcHandler:setMessage(MESSAGE_FAREWELL, "Hssh. Another time.")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Hssh. Another time.")

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())
