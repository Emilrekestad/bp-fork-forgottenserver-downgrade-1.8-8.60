local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)		end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()				end

npcHandler:setMessage(MESSAGE_GREET, "Ylfder |PLAYERNAME|, willzkommen to my cabin.")
npcHandler:setMessage(MESSAGE_FAREWELL, "Farewell wanderer, careful. ")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Veree behaviour!")
npcHandler:setMessage(MESSAGE_SENDTRADE, "Sure.")

keywordHandler:addKeyword({ "job" }, StdModule.say, { npcHandler = npcHandler, text = "I watch over the snowy lands and protect what needs to be protected. And of course, sell shiny things." })

local voices = {
	{ text = "Hunters, hunters, more! MORE!" },
	{ text = "Jack.. I remember Jack." },
	{ text = "Reading.. reading.. I think you say... mission.. yes." },
}

npcHandler:addModule(VoiceModule:new(voices))
npcHandler:addModule(FocusModule:new())
