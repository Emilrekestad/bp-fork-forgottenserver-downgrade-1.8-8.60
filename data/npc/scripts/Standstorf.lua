local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)		end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()				end

npcHandler:setMessage(MESSAGE_GREET, "Fire! |PLAYERNAME|, do you have a lighter?")
npcHandler:setMessage(MESSAGE_FAREWELL, "Bring me with you, take me to Aifur. ")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Remember! Steel can break. Melon can bruise. Respect both.")
npcHandler:setMessage(MESSAGE_SENDTRADE, "Sure.")

keywordHandler:addKeyword({ "job" }, StdModule.say, { npcHandler = npcHandler, text = "Where there is smoke... I probably started it." })
keywordHandler:addKeyword({ "trade" }, StdModule.say, { npcHandler = npcHandler, text = "There is no mistake a grinder cannot erase." })
keywordHandler:addKeyword({ "philosophy" }, StdModule.say, { npcHandler = npcHandler, text = "A man is measured not by his possessions, but by the melon in his refrigerator." })

local voices = {
	{ text = "Could use a smoke. Could use a beer. Could use both. In that order." },
	{ text = "ZIP! *lighter* halleluljah" },
	{ text = "They say smoking takes ten years off your life... That's ten fewer years of work... Interesting..." },
	{ text = "If the TV is 100, I am 60." },
}

npcHandler:addModule(VoiceModule:new(voices))
npcHandler:addModule(FocusModule:new())
