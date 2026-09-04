-- Grand Jarl Karl -- fierce Nordic-Italian warrior, obsessive grinder,
-- rare-item collector, shortcut hunter and mechanics optimizer. Completely
-- separate from Old Man Bao -- they don't know each other and should never
-- reference each other in dialogue.
--
-- Foundation only, per owner's instruction: greeting/farewell/walkaway/job/
-- trade + randomized idle speech. Deliberately NOT built yet (a separate
-- design pass still to come): the "Bag You Want/Desire/Covet" trading
-- system, any real item IDs, currencies, or the rare-item/exploration
-- questline. Future work should extend this same keywordHandler/npcHandler,
-- same pattern as Old Man Bao and Bender Shun.

local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()					end

npcHandler:setMessage(MESSAGE_GREET, "Welcome, welcome! Sit down, stand up, whatever, we have loot to discuss!")
npcHandler:setMessage(MESSAGE_FAREWELL, "Go with fortune, amico, and if fortune fails then grind until statistics surrender!")
npcHandler:setMessage(MESSAGE_WALKAWAY, "He left before I finished… clever, I had forgotten the ending anyway!")

keywordHandler:addKeyword({ "job" }, StdModule.say, { npcHandler = npcHandler, text = "My job? Fight, hunt, find shortcuts, collect rarities and occasionally make catastrophic statistical decisions!" })
keywordHandler:addKeyword({ "trade" }, StdModule.say, { npcHandler = npcHandler, text = "Gold is everywhere, but THESE things, mamma mia, these things have stories!" })

-- Randomized idle speech -- same VoiceModule Old Man Bao and Bender Shun
-- already use, fires periodically and unprompted. Exactly the two canonical
-- idle lines given -- not padded out with invented ones.
local voices = {
	{ text = "Djagons… DJAGONS… Dragons." },
	{ text = "Wait, where have I been?" },
}

npcHandler:addModule(VoiceModule:new(voices))
npcHandler:addModule(FocusModule:new())
