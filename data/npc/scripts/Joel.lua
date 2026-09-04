local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)		end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()				end

npcHandler:setMessage(MESSAGE_GREET, "Hihi |PLAYERNAME|, what are you doing here?")
npcHandler:setMessage(MESSAGE_FAREWELL, "Williwaspthewicked has arrived! Another time!")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Irrwispi..")
npcHandler:setMessage(MESSAGE_SENDTRADE, "Sure.")

keywordHandler:addKeyword({ "job" }, StdModule.say, { npcHandler = npcHandler, text = "I shoot stuff, and search for stuff, for long periods, my biggest weakness is I never give up. Some people call me a mad man, but I call myself.. Joel." })

local voices = {
	{ text = "ZZzzZzz.. three thousands scouts, no bow.. *nightmares*" },
	{ text = "I'm swift, swiftiswift the swifter." },
	{ text = "I think fast, super fast, just as fast as a.... hmm.." },
	{ text = "Careful with your step, I got mini horses running around." },
}

npcHandler:addModule(VoiceModule:new(voices))
npcHandler:addModule(FocusModule:new())
