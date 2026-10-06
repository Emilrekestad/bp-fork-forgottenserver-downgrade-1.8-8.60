-- Zlak, a rebel lizard of Lizard City, gives out the Wrath of the Emperor (see
-- scripts/quests/wrath_of_the_emperor/wrath.lua for what the map does).
-- Lizards say "z" where we say "s".
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()					end

-- Keys are written out here (not read from the Storage lib) so that /reload npcs is enough.
local K = {
	Questline = 13001, M1 = 13002, M2 = 13003, M3 = 13004, M4 = 13005, M5 = 13006,
	DrakenKills = 13007, Fury = 13008, Wrath = 13009, Scorn = 13010, Spite = 13011,
}
local REPLICA = 11362
local DRAKENS_NEEDED = 50

local function bossesDone(player)
	local done = 0
	for _, key in ipairs({ K.Fury, K.Wrath, K.Scorn, K.Spite }) do
		if player:getStorageValue(key) >= 1 then
			done = done + 1
		end
	end
	return done
end

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	local started = player:getStorageValue(K.Questline) >= 1
	local m1, m2, m3, m4, m5 = player:getStorageValue(K.M1), player:getStorageValue(K.M2), player:getStorageValue(K.M3), player:getStorageValue(K.M4), player:getStorageValue(K.M5)

	if msgcontains(msg, "mission") or msgcontains(msg, "quest") or msgcontains(msg, "report") or msgcontains(msg, "help") then
		if not started then
			npcHandler:say({
				"Ztranger... you walk our ztreetz with ze eyez of zomeone who hazz ztill zomezing to prove. Good. We need zuch eyez. ...",
				"Ze lizardz of Zao are dying, ztranger. Ze Emperor'z curze creepz over ze zteppe like ze zhadow of a cloud zat never lifts, and ze dragon who dreamz beneath our city cannot find peace. ...",
				"Zalamon, once ze wizezt of all uz, iz now ze curze'z own voice. If Zalamon can be broken, ze Emperor loozez hiz grip on Zao. ...",
				"Will you help uz?"
			}, cid)
			npcHandler.topic[cid] = 1
		elseif m1 == 1 then
			npcHandler:say("Go to Zalamon, far in ze eaztern mountainz, and try to talk him into zettling peace in Zao. Zpeak of {peace} to him. Then come back and tell me how it went.", cid)
		elseif m1 == 2 then
			npcHandler:say({
				"Ze old Zalamon would have lizztened to you. Ze new one zhut you up and zet hiz guardz on you? Hah. I ezpected nozzing elze. ...",
				"But you livez, and now we know for zertain: zere iz no peace to be talked, only a curze to be broken. ...",
				"Zo. Ze real work. Ze Emperor hid ze old zcripturez zat tell how he wazs bound once. One chest, far out in ze zteppe, north-eazt of ze city. Ze lizardz zat guard it will not leave it. Find it, open it, and bring ze zcripturez to me."
			}, cid)
			player:setStorageValue(K.M1, 3)
			player:setStorageValue(K.M2, 1)
		elseif m2 == 1 then
			npcHandler:say("Ze zcripturez are in a chest far out in ze zteppe, north-eazt of ze city. Open it and come back to me. Do not tarry.", cid)
		elseif m2 == 2 then
			npcHandler:say({
				"Ze zcripturez! Zo you found zem. Let me read... Yez. Yez. Zis iz how it began... and how it can end. ...",
				"Ze Emperor'z ztrength liez in hiz drakenz, ze ones zat still believe hiz lie. Zere are too many of zem. We will thin zeir ranks. ...",
				"Kill fifty Draken Zpellweaverz or Draken Warmasterz, fifty in total. And bring friendz: all who tag a draken get ze kill in zeir count. I keep ze tally."
			}, cid)
			player:setStorageValue(K.M2, 3)
			player:setStorageValue(K.M3, 1)
			player:setStorageValue(K.DrakenKills, 0)
		elseif m3 == 1 then
			local kills = math.max(player:getStorageValue(K.DrakenKills), 0)
			npcHandler:say(string.format("Ze count zo far: %d of %d. Draken Zpellweaverz and Draken Warmasterz, as many as you can, and bring friendz. All who tag a draken get ze kill.", kills, DRAKENS_NEEDED), cid)
		elseif m3 == 2 then
			npcHandler:say({
				"Fifty! Ze drakenz will think twice before zey guard ze Emperor'z road again. ...",
				"Now comez ze long mission, ze one I fear for you. Ze Emperor'z curze lives in Zalamon, and Zalamon'z curze lives in four creaturez zat guard ze basement of ze Draken Cazztle: Fury, Wrath, Scorn and Zpite of ze Emperor. ...",
				"Make your way up to ze Draken Cazztle, zen down into ze basement. Kill all four. ...",
				"Take zis. A replica of ze zceptre. Ze real one iz long lost, but zis one will answer to ze dead. Uze it on ze corpze of each of ze four to verify ze kill. Zey must all be verified, or ze curze will not weaken. ...",
				"When all four are done, leave ze basement and speak to me again."
			}, cid)
			player:setStorageValue(K.M3, 3)
			player:setStorageValue(K.M4, 1)
			player:addItem(REPLICA, 1)
		elseif m4 == 1 then
			local done = bossesDone(player)
			npcHandler:say(string.format("Ze four in ze Draken Cazztle basement: Fury, Wrath, Scorn and Zpite of ze Emperor. Uze ze replica of ze zceptre on each corpze. You have verified %d of 4. If you lozt ze replica, azk me for ze {sceptre}.", done), cid)
		elseif m4 == 2 then
			npcHandler:say({
				"All four... and ze zceptre verified every one. I can feel ze curze trembling from here. ...",
				"Now ze final tezt. Zalamon himzelf. Go up ze tower again, ze one in ze far north of ze city. You will find a teleport at ze top. It will take you to ze dragon who dreamz beneath uz. ...",
				"Zpeak to her. She hazs been waiting a long time for zomeone to hear her. And bring ze replica of ze zceptre. You will need it."
			}, cid)
			player:setStorageValue(K.M4, 3)
			player:setStorageValue(K.M5, 1)
		elseif m5 == 1 then
			npcHandler:say("Go up ze tower in ze far north of ze city. At ze top is a teleport. It will take you to ze Zleeping Dragon. Zpeak to her, and bring ze replica of ze zceptre.", cid)
		elseif m5 == 2 then
			npcHandler:say("You have heard ze dragon. Now walk north in her chamber to ze gate, and find ze place where Zalamon waitz. Bring friendz who have also heard her, and do not forget ze replica of ze zceptre.", cid)
		elseif m5 >= 3 then
			npcHandler:say("Ze Emperor'z grip iz broken, ztranger. Ze Zao region breathez at last. Our people will zing of you for a hundred yearz. Ze dragon dreamz in peace.", cid)
		end
		return true
	end

	if msgcontains(msg, "sceptre") or msgcontains(msg, "replica") then
		if m4 == 1 then
			if player:getItemCount(REPLICA) < 1 then
				npcHandler:say("You lozt it? Careless. Here, take anozer. Do not lose zis one.", cid)
				player:addItem(REPLICA, 1)
			else
				npcHandler:say("You already carry ze replica of ze zceptre. Use it on ze corpze of each of ze four.", cid)
			end
		elseif m5 == 1 or m5 == 2 then
			if player:getItemCount(REPLICA) < 1 then
				npcHandler:say("You will need ze replica for Zalamon. Here, take it. Do not lose it.", cid)
				player:addItem(REPLICA, 1)
			else
				npcHandler:say("You carry ze replica already. Keep it close.", cid)
			end
		else
			npcHandler:say("A replica of ze Emperor'z zceptre. It answerz to ze dead, nozzing more.", cid)
		end
		return true
	end

	if msgcontains(msg, "yes") and npcHandler.topic[cid] == 1 then
		npcHandler:say({
			"Zen lizzen well. Your firzt tazk iz ze one I ezpect to fail, but it must be tried. ...",
			"Go to Zalamon, far in ze eaztern mountainz, and try to convince him to zettle peace in Zao. Zpeak to him of {peace}. ...",
			"Whatever happenz, come back and tell me. I want to hear how he anzwerz."
		}, cid)
		player:setStorageValue(K.Questline, 1)
		player:setStorageValue(K.M1, 1)
		npcHandler.topic[cid] = 0
		return true
	elseif msgcontains(msg, "no") and npcHandler.topic[cid] == 1 then
		npcHandler:say("Zen go, and zay nozzing of what you heard. Ze walls have eyes.", cid)
		npcHandler.topic[cid] = 0
		return true
	end

	return false
end

keywordHandler:addKeyword({ "zalamon" }, StdModule.say, { npcHandler = npcHandler, text = "Zalamon wazs ze wizezt of uz. Now he iz ze curze'z own voice. Where he ztandz, ze Emperor'z shadow ztandz with him." })
keywordHandler:addKeyword({ "emperor" }, StdModule.say, { npcHandler = npcHandler, text = "Ze Emperor rulez Zao from ze palace below, and hiz curze iz why ze dragon cannot rezt. Zere iz a way to end it. It will cozt blood." })
keywordHandler:addKeyword({ "dragon" }, StdModule.say, { npcHandler = npcHandler, text = "Ze Zleeping Dragon dreamz beneath ze city. Her dream iz what holdz ze zteppe togezzer, and ze curze iz poizoning it." })
keywordHandler:addKeyword({ "draken" }, StdModule.say, { npcHandler = npcHandler, text = "Ze drakenz serve ze Emperor. Zpellweaverz and Warmasterz, mostly. Zey will not stop until zomeone makez zem." })
keywordHandler:addKeyword({ "job" }, StdModule.say, { npcHandler = npcHandler, text = "I am Zlak. I keep ze rebelz alive and ze zecretz zecret. And I look for people who can do what we cannot. Do you want a {mission}?" })
keywordHandler:addKeyword({ "name" }, StdModule.say, { npcHandler = npcHandler, text = "I am Zlak of Lizard City." })

npcHandler:setMessage(MESSAGE_GREET, "Zhh. Keep your voice down, |PLAYERNAME|. Ze walls have ears in Lizard City. If you want to help ze rebelz, azk me for a {mission}.")
npcHandler:setMessage(MESSAGE_FAREWELL, "Go carefully, |PLAYERNAME|.")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Zhh. Gone already...")

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())
