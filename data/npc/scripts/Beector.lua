local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)		end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()				end

npcHandler:setMessage(MESSAGE_GREET, "Beehold! A customer |PLAYERNAME| - what can I do for you? ")
npcHandler:setMessage(MESSAGE_FAREWELL, "Farewell! May your code compile and bees comply. ")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Well, that session timed out. He's gone. Deploy the bees")
npcHandler:setMessage(MESSAGE_SENDTRADE, "Sure.")

keywordHandler:addKeyword({ "job" }, StdModule.say, { npcHandler = npcHandler, text = "I spend my weekdays eliminating bugs and my weekends feeding them. Have you tried turning the hive off and on again?" })
keywordHandler:addKeyword({ "bee" }, StdModule.say, { npcHandler = npcHandler, text = "To understand the hive, first accept that the hive does not care." })
keywordHandler:addKeyword({ "trade" }, StdModule.say, { npcHandler = npcHandler, text = "Production is just testing with consequences. My stuff work all the time.. I hope." })

local voices = {
	{ text = "Beeholder, tihi." },
	{ text = "The bees seem productive today. Suspiciously productive." },
	{ text = "Could a bee use a keyboard?... Tiny keyboard. I'll look into it." },
	{ text = "Technically... all my coworkers are bugs." },
}

npcHandler:addModule(VoiceModule:new(voices))
npcHandler:addModule(FocusModule:new())
