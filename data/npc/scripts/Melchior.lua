local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()					end

-- Melchior -- "The Third Place at the Table", chapter 1
-- (docs/quest-reworks/12-djinn-build-plan.md, D1). He teaches the word of
-- greeting and how to ask for hospitality as a guest. The old warning that a
-- visitor must choose a side for ever, and the Factions greeting storage it
-- wrote, were retired 2026-09-11: nothing he says is an oath.

local SAY_INTERVAL = 4000
local function sayLines(message, cid)
	return npcHandler:say(message, cid, false, true, SAY_INTERVAL)
end

local TOPIC_DJINN = 1

local function greetCallback(cid)
	npcHandler:setMessage(MESSAGE_GREET, Player(cid):getSex() == PLAYERSEX_FEMALE and 'Welcome, |PLAYERNAME|! The lovely sound of your voice shines like a beam of light through my solitary darkness!' or 'Greetings, |PLAYERNAME|. I do not see your face, but I can read a thousand things in your voice!')
	return true
end

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end

	local player = Player(cid)
	local tooLow = player:getLevel() < DjinnNeutral.MIN_LEVEL

	if msgcontains(msg, 'djinn') or msgcontains(msg, 'words of greeting') then
		if tooLow then
			npcHandler:say(DjinnNeutral.Lines.tooLow, cid)
			return true
		end
		npcHandler:say('You want to trade with them? Then learn how to enter a conversation before you enter a fortress. Their word of greeting is {djanni\'hah}. It asks for hospitality. It need not offer your sword. Say it to me, and I will tell you where to begin.', cid)
		npcHandler.topic[cid] = TOPIC_DJINN
	elseif msgcontains(msg, 'djanni\'hah') or msgcontains(msg, 'djannihah') then
		-- Saying the word is the whole introduction (owner, 2026-10-06): it starts the quest.
		if tooLow then
			npcHandler:say(DjinnNeutral.Lines.tooLow, cid)
			return true
		end
		npcHandler.topic[cid] = 0
		if DjinnNeutral.has(player, 'introduced') then
			npcHandler:say(DjinnNeutral.logText(player), cid)
			return true
		end
		DjinnNeutral.set(player, 'introduced')
		npcHandler:say({
			'Good. That is how a guest asks for hospitality, with a word and not a sword.',
			'Umar receives visitors at the blue fortress, Ashta\'daramai. Begin there and ask to speak with Nah\'Bob. The green fortress is Mal\'ouquah; its guard is Ubaid. Neither guard has been told to like you.'
		}, cid, false, true, SAY_INTERVAL)
	elseif msgcontains(msg, 'hospitality') then
		if tooLow then
			npcHandler:say(DjinnNeutral.Lines.tooLow, cid)
			return true
		end
		npcHandler:say('Both courts will ask for your loyalty. Ask instead to be received as a {guest}. Gabel values an honest account. Malor values an advantage. Perhaps there is room between those two things for a trader.', cid)
		npcHandler.topic[cid] = TOPIC_DJINN
	elseif msgcontains(msg, 'guest') then
		if tooLow then
			npcHandler:say(DjinnNeutral.Lines.tooLow, cid)
			return true
		end
		if not DjinnNeutral.has(player, 'introduced') and npcHandler.topic[cid] ~= TOPIC_DJINN then
			npcHandler:say('A guest of whom? Ask me about the {djinn} first.', cid)
			return true
		end
		npcHandler.topic[cid] = 0
		if DjinnNeutral.has(player, 'introduced') and DjinnNeutral.has(player, 'blueVisitor') then
			npcHandler:say(DjinnNeutral.logText(player), cid)
			return true
		end
		DjinnNeutral.set(player, 'introduced')
		npcHandler:say('Umar receives visitors at the blue fortress, Ashta\'daramai. Begin there and ask to speak with Nah\'Bob. The green fortress is Mal\'ouquah; its guard is Ubaid. Neither guard has been told to like you.', cid)
	elseif msgcontains(msg, 'undertaking') then
		if DjinnNeutral.has(player, 'complete') then
			npcHandler:say('Both names on one page? Then you listened well. They will still disagree with each other tomorrow. You have given them one less reason to disagree about you.', cid)
		end
	elseif msgcontains(msg, 'mission') or msgcontains(msg, 'journal') then
		if DjinnNeutral.has(player, 'introduced') then
			npcHandler:say(DjinnNeutral.logText(player), cid)
		end
	end
	return true
end

npcHandler:setMessage(MESSAGE_FAREWELL, 'Farewell, stranger. May Uman the Wise guide your steps in this treacherous land.')
npcHandler:setMessage(MESSAGE_WALKAWAY, 'Farewell, stranger. May Uman the Wise guide your steps in this treacherous land.')

npcHandler:setCallback(CALLBACK_GREET, greetCallback)
npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())
