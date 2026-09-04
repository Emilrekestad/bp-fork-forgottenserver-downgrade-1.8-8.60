local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)		end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()				end

npcHandler:setMessage(MESSAGE_GREET, "Purr.. Oh great, one of \"Jespers\".  |PLAYERNAME|, state your business. ")
npcHandler:setMessage(MESSAGE_FAREWELL, "Leave with dignity. Jesper will get the door.")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Fine. Die outside. Apparently we were raised in a fucking barn.")
npcHandler:setMessage(MESSAGE_SENDTRADE, "Sure.")

keywordHandler:addKeyword({ "job" }, StdModule.say, { npcHandler = npcHandler, text = "Hah! I have my person working for me." })
keywordHandler:addKeyword({ "cat" }, StdModule.say, { npcHandler = npcHandler, text = "Finally, a word worth saying." })
keywordHandler:addKeyword({ "morris" }, StdModule.say, { npcHandler = npcHandler, text = "A powerful name. Chosen by... actually, never mind" })
keywordHandler:addKeyword({ "jesper" }, StdModule.say, { npcHandler = npcHandler, text = "Good boy. Limited potential. Jesper and I have an arrangement. He works. I don't." })
keywordHandler:addKeyword({ "mission" }, StdModule.say, { npcHandler = npcHandler, text = "To sleep, leave me alone." })

local voices = {
	{ text = "Nine lives. Zero responsibilities." },
	{ text = "Sometimes I wonder what I'd do without Jesper... Probably starve... Unacceptable." },
	{ text = "He forgot the pot again.. fire." },
	{ text = "Perhaps violence." },
}

npcHandler:addModule(VoiceModule:new(voices))
npcHandler:addModule(FocusModule:new())
