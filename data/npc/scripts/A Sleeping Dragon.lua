-- The Sleeping Dragon beneath Lizard City. In mission 5 of Wrath of the Emperor she speaks in her sleep
-- about ending Zalamon; after that the gate north of her opens.
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()					end

local MISSION_5 = 13006

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	local state = player:getStorageValue(MISSION_5)
	if state == 1 then
		npcHandler:say({
			"...zzzZzz... you came... I can hear your heartbeat, little wayfarer... it is a good heartbeat... ...",
			"...the dream is breaking... long ago the Emperor wove his hunger into my sleep... I cannot wake... I cannot rest... ...",
			"...Zalamon... he was kind once... he held my head when the dream first turned... now he is the thread the Emperor pulls... ...",
			"...he must end... not for hate... for mercy... ...",
			"...the gate to the north will open for you... beyond it waits the place where the thread is tied... bring those who have heard me... and the sceptre that answers the dead... ...",
			"...he will change as he falls... the essence... the thing... the abomination... and last, himself... do not stop... ...",
			"...when he is gone, hold the sceptre over his body... and I will sleep... at last... zzzZzz..."
		}, cid)
		player:setStorageValue(MISSION_5, 2)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The Sleeping Dragon has spoken. The gate to the north will open for you now. Your mission is to kill Mutated Zalamon. Bring friends who have heard her too, and your replica of the sceptre.")
	elseif state >= 2 then
		npcHandler:say({
			"...zzzZzz... every time he strikes a heart in Zao... I feel it... like a claw drawn slowly through my dream... ...",
			"...the Emperor pulls the thread through Zalamon, and the thread is tied to me... when Zalamon screams, I scream... and nobody hears, because I cannot wake... ...",
			"...a thousand years of it... little wayfarer, I am so tired... so tired of the ache... ...",
			"...north... the gate... bring the sceptre... end him... for mercy... ...zzzZzz..."
		}, cid)
	else
		npcHandler:say("...zzzZzz... a warm light... not yet... not yet... ...zzzZzz...", cid)
	end
	return true
end

local function kw(words, text)
	keywordHandler:addKeyword(words, StdModule.say, { npcHandler = npcHandler, text = text })
end

kw({ "pain" }, "...it never stops... a burn behind my eyes where the dream used to be soft... each night Zalamon is made to hurt another, the burn grows... and I feel every one of them... ...zzzZzz...")
kw({ "zalamon" }, "...he was gentle once... he sang to me when the dream was cold... now the Emperor sings through his throat, and the song is cruelty... I hear him weep underneath it, and I cannot reach him... ...zzzZzz...")
kw({ "emperor" }, "...a hunger that learned to speak... he pushed his will into my sleep and I could not push it out... he uses my dream to keep Zalamon bound... ...zzzZzz...")
kw({ "dream" }, "...it was a green and quiet place once... warm grass, slow rivers... now there are teeth in it... and every night they come closer... ...zzzZzz...")
kw({ "mercy" }, "...for him, mercy... for me, mercy... for every lizard who still suffers because of him... one ending, and so many freed... ...zzzZzz...")
kw({ "sceptre" }, "...the sceptre answers the dead... when he falls, hold it over his body... only then will the thread truly break... ...zzzZzz...")
kw({ "gate" }, "...north... where the dream gives way to stone... it opens for those who have heard me... ...zzzZzz...")
kw({ "wayfarer" }, "...yes... one who walks far for others... I can hear your heartbeat... it is steady... ...zzzZzz...")
kw({ "help" }, "...you already are... listening is the first mercy... the rest is the gate, the sceptre and your courage... ...zzzZzz...")

npcHandler:setMessage(MESSAGE_GREET, "...zzzZzz... who... disturbs... my dream...? Speak softly, little {wayfarer}...")
npcHandler:setMessage(MESSAGE_FAREWELL, "...zzzZzz...")
npcHandler:setMessage(MESSAGE_WALKAWAY, "...zzzZzz...")

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())
