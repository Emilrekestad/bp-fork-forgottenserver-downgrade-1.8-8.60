-- Joel -- leg 3 of "The Lamp That Wanted a Job": the striker.
-- He knows where the stone is. He has known for years. He has also been
-- searching the same side of the same cliff for years, because his one
-- weakness is that he never gives up and never changes method.
-- Shared definition in data/lib/quests/lamp_quest.lua; the pile itself is
-- data/scripts/actions/quests/lamp_striker.lua.
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

-- Multi-line answers go through NpcHandler:doNPCTalkALot, which defaults to a
-- SIX second gap between lines -- half a minute for a five-line answer, and
-- long enough that the player says something else and cancels the rest of it
-- (every say() cancels the queue before it). Four seconds still reads at a
-- speaking pace and keeps the longest answer here under twenty seconds.
local SAY_INTERVAL = 4000
local function sayLines(message, cid, publicize)
	return npcHandler:say(message, cid, publicize, true, SAY_INTERVAL)
end

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)		end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()				end

npcHandler:setMessage(MESSAGE_GREET, "Hihi |PLAYERNAME|, what are you doing here?")
npcHandler:setMessage(MESSAGE_FAREWELL, "Williwaspthewicked has arrived! Another time!")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Irrwispi..")
npcHandler:setMessage(MESSAGE_SENDTRADE, "Sure.")

keywordHandler:addKeyword({ "job" }, StdModule.say, { npcHandler = npcHandler, text = "I shoot stuff, and search for stuff, for long periods, my biggest weakness is I never give up. Some people call me a mad man, but I call myself.. Joel." })

local function strikerCallback(cid, message, keywords, parameters, node)
	local player = Player(cid)
	if not player then
		return true
	end

	local state = LampQuest.get(player, "striker")

	if state >= 3 then
		sayLines({
			"Fitted. Snug. It will throw a spark every time now, which is more than I can say for me on a cold morning.",
			"Twelve years, hihi. Twelve years on the wrong side of one rock. Do not tell Neck.",
		}, cid)
		return true
	end

	if state < 1 then
		sayLines({
			"Stones? I know stones. I know every stone from here down to the water and back up again, in order.",
			"But you have not asked me for one, so I am going to keep knowing them quietly.",
		}, cid)
		return true
	end

	if state == 2 then
		-- Only the stone the pile issued to this player counts (or, for a
		-- character from before stones were stamped, their untagged original),
		-- and exactly that item is taken -- never some other flintstone.
		local stone = LampQuest.findStone(player)
		if not stone then
			sayLines("You found it and then you did not bring it. Hihi. That is a Joel move. Go and get it.", cid)
			return true
		end

		if not LampQuest.hasLamp(player) then
			sayLines("Stone, yes. Lamp, no. I cannot fit a striker to the idea of a lamp.", cid)
			return true
		end

		if not stone:remove() then
			sayLines("It slipped. Everything slips up here. Try again.", cid)
			return true
		end

		LampQuest.set(player, "striker", 3)
		player:getPosition():sendMagicEffect(CONST_ME_FIREATTACK)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Joel seated the greenish flintstone in the lamp's striker. It sparks.")

		sayLines({
			"...greenish. Greenish! Hihi! Let me see it. Let me... yes. That is the one. That is the exact one.",
			"*scrape* Hear that? *scrape* That is a spark. That is a proper spark and not a sad little noise.",
			"Elvenbane. The southern tip of the main floor. I walked past it twice and never once turned it over. I am not going to think about that tonight.",
			"Take it. It is done. Whoever finishes the rest of it, tell them a hunter did the hard part.",
		}, cid)
		LampQuest.checkWhole(player)
		return true
	end

	sayLines({
		"A striker! Now that I can help with, and I mean actually help, not the kind where I talk for an hour.",
		"You want a greenish flintstone. Not grey. Grey is everywhere and grey is useless. Greenish, and it has to come out of this cliff, because the cliff is what makes it greenish.",
		"I have been sifting the scree on the sunny side for... a while. A long while. It is a very good scree. It has no greenish flintstone in it.",
		"But on the southern tip of Elvenbane, on the main floor, I once saw a pile of stones with a faint green glow to it. It looked a lot like what you need. I have been far too busy sifting this scree to walk over and look. You go. Turn it over.",
	}, cid)
	return true
end

keywordHandler:addKeyword({ "lamp", "striker", "stone", "stones", "flint", "flintstone", "spark", "search" }, strikerCallback)

keywordHandler:addKeyword({ "neck" }, StdModule.say, { npcHandler = npcHandler, text = {
	"Neck! Hihi. He shouts about daggers and he is right about daggers, and that is the worst part.",
	"He sends me things. Usually problems. Occasionally people.",
} })

keywordHandler:addKeyword({ "horse", "horses" }, StdModule.say, { npcHandler = npcHandler, text = "Mini horses. Careful with your step. They are quiet and they are unforgiving." })

local voices = {
	{ text = "ZZzzZzz.. three thousands scouts, no bow.. *nightmares*" },
	{ text = "I'm swift, swiftiswift the swifter." },
	{ text = "I think fast, super fast, just as fast as a.... hmm.." },
	{ text = "Careful with your step, I got mini horses running around." },
	{ text = "Greenish. Not grey. Twelve years of grey and not one greenish. Hihi." },
}

npcHandler:addModule(VoiceModule:new(voices))
npcHandler:addModule(FocusModule:new())
