-- Zumtah: the old New Frontier / Children of the Revolution / Wrath of the Emperor dialogue was
-- removed on 2026-10-04. This NPC now only chats. (The new Wrath of the Emperor starts with Zlak
-- in Lizard City.)
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()					end

keywordHandler:addKeyword({ "job" }, StdModule.say, { npcHandler = npcHandler, text = "I am Zumtah. I am... waiting. Do not mind me." })
keywordHandler:addKeyword({ "name" }, StdModule.say, { npcHandler = npcHandler, text = "I am Zumtah." })
keywordHandler:addKeyword({ "mission" }, StdModule.say, { npcHandler = npcHandler, text = "I have no work for you. Zlak in Lizard City might." })
keywordHandler:addKeyword({ "quest" }, StdModule.say, { npcHandler = npcHandler, text = "I have no work for you. Zlak in Lizard City might." })

npcHandler:setMessage(MESSAGE_GREET, "Another visitor to this constricted, cosy, calm realm. Muhaha.")
npcHandler:setMessage(MESSAGE_FAREWELL, "Farewell.")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Farewell.")

npcHandler:addModule(FocusModule:new())
