 local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()		npcHandler:onThink()		end

local voices = { {text = 'Feel the wind in your hair during one of my carpet rides!'} }
npcHandler:addModule(VoiceModule:new(voices))

-- Travel
local function addTravelKeyword(keyword, text, cost, destination, condition, action)
	--if condition then
		--keywordHandler:addKeyword({keyword}, StdModule.say, {npcHandler = npcHandler, text = 'Never heard about a place like this.'}, condition)
	--end

	local travelKeyword = keywordHandler:addKeyword({keyword}, StdModule.say, {npcHandler = npcHandler, text = text, cost = cost, discount = 'postman'})
		travelKeyword:addChildKeyword({'yes'}, StdModule.travel, {npcHandler = npcHandler, premium = true, text = 'Hold on!', cost = cost, discount = 'postman', destination = destination}, nil, action)
		travelKeyword:addChildKeyword({'no'}, StdModule.say, {npcHandler = npcHandler, text = 'You shouldn\'t miss the experience.', reset = true})
end

-- Eclipse: only for inquisition recruits who hold Henricus's holy water (Mission 3, stages 2-3).
local function eclipseAllowed(player)
	local stage = player:getStorageValue(Storage.TheInquisition.Mission03)
	return stage == 2 or stage == 3
end
local eclipseNode = keywordHandler:addKeyword({'eclipse'}, function(cid, message, keywords, parameters, node)
	local player = Player(cid)
	if not player then
		return false
	end
	if not eclipseAllowed(player) then
		npcHandler:say('Never heard about a place like this.', cid)
		return true
	end
	npcHandler:say('Oh no, so the time has come? Do you really want me to fly you to this unholy place?', cid)
	return true
end, {})
eclipseNode:addChildKeyword({'yes'}, function(cid, message, keywords, parameters, node)
	local player = Player(cid)
	if not player or not eclipseAllowed(player) then
		return false
	end
	if player:isPzLocked() then
		npcHandler:say('First get rid of those blood stains! You are not going to ruin my vehicle!', cid)
		npcHandler:resetNpc(cid)
		return true
	end
	npcHandler:say('Hold on!', cid)
	npcHandler:releaseFocus(cid)
	local destination = Position(32660, 31915, 0)
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(destination)
	destination:sendMagicEffect(CONST_ME_TELEPORT)
	npcHandler:resetNpc(cid)
	return true
end, {})
eclipseNode:addChildKeyword({'no'}, StdModule.say, {npcHandler = npcHandler, text = 'You shouldn\'t miss the experience.', reset = true})
addTravelKeyword('farmine', 'Do you seek a ride to Farmine for |TRAVELCOST|?', 0, Position(32983, 31539, 1), function(player) return player:getStorageValue(Storage.TheNewFrontier.Mission10) ~= 1 end)
addTravelKeyword('edron', 'Do you seek a ride to Edron for |TRAVELCOST|?', 0, Position(33193, 31783, 3))
addTravelKeyword('darashia', 'Do you seek a ride to Darashia on Darama for |TRAVELCOST|?', 0, Position(33270, 32441, 6))
addTravelKeyword('svargrond', 'Do you seek a ride to Svargrond for |TRAVELCOST|?', 0, Position(32253, 31097, 4))
addTravelKeyword('kazordoon', 'Do you seek a ride to Kazordoon for |TRAVELCOST|?', 0, Position(32588, 31942, 0))

-- Basic
keywordHandler:addKeyword({'name'}, StdModule.say, {npcHandler = npcHandler, text = "I am known as Uzon Ibn Kalith."})
keywordHandler:addKeyword({'job'}, StdModule.say, {npcHandler = npcHandler, text = "I am a licensed Darashian carpetpilot. I can bring you to {Darashia}, {Kazordoon}, {Svargrond} or {Edron}."})
keywordHandler:addKeyword({'caliph'}, StdModule.say, {npcHandler = npcHandler, text = "The caliph welcomes travellers to his land."})
keywordHandler:addKeyword({'kazzan'}, StdModule.say, {npcHandler = npcHandler, text = "The caliph welcomes travellers to his land."})
keywordHandler:addKeyword({'daraman'}, StdModule.say, {npcHandler = npcHandler, text = "Oh, there is so much to tell about Daraman. You better travel to Darama to learn about his teachings."})
keywordHandler:addKeyword({'ferumbras'}, StdModule.say, {npcHandler = npcHandler, text = "I would never transport this one."})
keywordHandler:addKeyword({'drefia'}, StdModule.say, {npcHandler = npcHandler, text = "So you heard about haunted Drefia? Many adventures travel there to test their skills against the undead: vampires, mummies, and ghosts."})
keywordHandler:addKeyword({'excalibug'}, StdModule.say, {npcHandler = npcHandler, text = "Some people claim it is hidden somewhere under the endless sands of the devourer desert in Darama."})
keywordHandler:addKeyword({'thais'}, StdModule.say, {npcHandler = npcHandler, text = "Thais is noisy and overcrowded. That's why I like Darashia more."})
keywordHandler:addKeyword({'tibia'}, StdModule.say, {npcHandler = npcHandler, text = "I have seen almost every place on the continent."})
keywordHandler:addKeyword({'continent'}, StdModule.say, {npcHandler = npcHandler, text = "I could retell the tales of my travels for hours. Sadly another flight is scheduled soon."})
keywordHandler:addKeyword({'carlin'}, StdModule.say, {npcHandler = npcHandler, text = "Just another Thais but with women to lead them."})
keywordHandler:addKeyword({'flying'}, StdModule.say, {npcHandler = npcHandler, text = "You can buy flying carpets only in Darashia."})
keywordHandler:addKeyword({'fly'}, StdModule.say, {npcHandler = npcHandler, text = "I transport travellers to the continent of Darama for a small fee. So many want to see the wonders of the desert and learn the secrets of Darama."})
keywordHandler:addKeyword({'new'}, StdModule.say, {npcHandler = npcHandler, text = "I heard too many news to recall them all."})
keywordHandler:addKeyword({'rumors'}, StdModule.say, {npcHandler = npcHandler, text = "I heard too many news to recall them all."})
keywordHandler:addKeyword({'passage'}, StdModule.say, {npcHandler = npcHandler, text = "I can fly you to {Darashia} on Darama, {Kazordoon}, {Svargrond} or {Edron} if you like. Where do you want to go?"})
keywordHandler:addKeyword({'transport'}, StdModule.say, {npcHandler = npcHandler, text = "I can fly you to {Darashia} on Darama, {Kazordoon}, {Svargrond} or {Edron} if you like. Where do you want to go?"})
keywordHandler:addKeyword({'ride'}, StdModule.say, {npcHandler = npcHandler, text = "I can fly you to {Darashia} on Darama, {Kazordoon}, {Svargrond} or {Edron} if you like. Where do you want to go?"})
keywordHandler:addKeyword({'trip'}, StdModule.say, {npcHandler = npcHandler, text = "I can fly you to {Darashia} on Darama, {Kazordoon}, {Svargrond} or {Edron} if you like. Where do you want to go?"})

-- The same NPC name stands in two places: Femor Hills (z4) and the Eclipse island (z0).
-- Two XML files with the name "Uzon" made the server use one script for both, so this one
-- script behaves by where the player is. On the island he only flies you back.
local function onEclipseIsland(player)
	local position = player:getPosition()
	return position.z == 0 and position.x >= 32640 and position.x <= 32680 and position.y >= 31900 and position.y <= 31945
end

local function islandReply(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	if not player or not onEclipseIsland(player) then
		return false
	end
	if msgcontains(msg, "ride") or msgcontains(msg, "trip") then
		npcHandler:say("You'll have to leave this unholy place first!", cid)
	elseif msgcontains(msg, "back") or msgcontains(msg, "leave") or msgcontains(msg, "passage") or msgcontains(msg, "transport") then
		npcHandler:say("Do you really want to leave this unholy place?", cid)
		npcHandler.topic[cid] = 1
	elseif msgcontains(msg, "yes") and npcHandler.topic[cid] == 1 then
		local destination = Position(32535, 31837, 4)
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		player:teleportTo(destination)
		destination:sendMagicEffect(CONST_ME_TELEPORT)
		npcHandler:say("So be it!", cid)
		npcHandler.topic[cid] = 0
	else
		return false
	end
	return true
end

-- CALLBACK_CREATURE_SAY runs before the keywords, and returning false stops the message there.
local function creatureSayCallback(cid, type, msg)
	return not islandReply(cid, type, msg)
end

npcHandler:setCallback(CALLBACK_CREATURE_SAY, creatureSayCallback)
npcHandler:setMessage(MESSAGE_GREET, "Daraman's blessings, traveller |PLAYERNAME|.")
npcHandler:setMessage(MESSAGE_FAREWELL, "Daraman's blessings")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Daraman's blessings")

npcHandler:addModule(FocusModule:new())
