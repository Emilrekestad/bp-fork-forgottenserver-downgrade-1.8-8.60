local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()		npcHandler:onThink()		end

local voices = { {text = 'Passages to Carlin, Ab\'Dendriel, Edron, Venore, Port Hope, Liberty Bay, Roshamuul, Krailos, Oramond, Svargrond and Daram Island.'} }
npcHandler:addModule(VoiceModule:new(voices))
 
-- Travel
local function addTravelKeyword(keyword, cost, destination, action)
	local travelKeyword = keywordHandler:addKeyword({keyword}, StdModule.say, {npcHandler = npcHandler, text = 'Do you seek a passage to ' .. keyword:titleCase() .. ' for |TRAVELCOST|?', cost = cost, discount = 'postman'})
		travelKeyword:addChildKeyword({'yes'}, StdModule.travel, {npcHandler = npcHandler, premium = false, cost = cost, discount = 'postman', destination = destination}, nil, action)
		travelKeyword:addChildKeyword({'no'}, StdModule.say, {npcHandler = npcHandler, text = 'We would like to serve you some time.', reset = true})
end

addTravelKeyword('carlin', 110, Position(32387, 31820, 6), function(player) if player:getStorageValue(Storage.postman.Mission01) == 1 then player:setStorageValue(Storage.postman.Mission01, 2) end end)
addTravelKeyword('ab\'dendriel', 130, Position(32734, 31668, 6))
addTravelKeyword('edron', 160, Position(33175, 31764, 6))
addTravelKeyword('venore', 170, Position(32954, 32022, 6))
addTravelKeyword('port hope', 160, Position(32527, 32784, 6))
addTravelKeyword('svargrond', 180, Position(32341, 31108, 6))
addTravelKeyword('krailos', 270, Position(33492, 31712, 6))
addTravelKeyword('daram island', 210, Position(32777, 33026, 6))

-- Liberty Bay, Oramond and Roshamuul -- all three World Missions
-- destinations. Per owner's spec: Bluebear still OFFERS all three
-- normally (quotes the price, same as any real route) -- he only backs
-- out at the "yes" confirmation, with an in-character, per-destination
-- safety excuse pointing the player at Bender Shun, rather than pretending
-- the place doesn't exist. Once the mission is applied the gate is gone
-- and it behaves exactly like every other addTravelKeyword() route.
-- Checked again at "yes" specifically (not just relying on the prompt
-- having already been shown) since a mission can apply mid-conversation
-- (completion fires the instant its threshold is met, not on a delay).
-- Reimplements the small prompt/confirm/pay/teleport flow rather than
-- reusing addTravelKeyword's StdModule.travel machinery, which has no
-- built-in hook for a runtime availability condition -- same gold-check-
-- then-teleport shape already proven working in this exact codebase
-- (data/npc/scripts/Captain Waverider.lua).
local function addGatedTravelKeyword(keyword, cost, destination, missionId, notYetText)
	local function promptCallback(cid, message, keywords, parameters, node)
		npcHandler:say('Do you seek a passage to ' .. keyword:titleCase() .. ' for ' .. cost .. ' gold?', cid)
		return true
	end

	local function yesCallback(cid, message, keywords, parameters, node)
		if not WorldMissions.isApplied(missionId) then
			npcHandler:say(notYetText, cid)
			return true
		end

		local player = Player(cid)
		if player:getMoney() < cost then
			npcHandler:say("You don't have enough money.", cid)
			return true
		end

		player:removeMoney(cost)
		npcHandler:say('And there we go!', cid)
		player:teleportTo(destination)
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		return true
	end

	local promptNode = keywordHandler:addKeyword({keyword}, promptCallback, {})
	promptNode:addChildKeyword({'yes'}, yesCallback, {})
	promptNode:addChildKeyword({'no'}, StdModule.say, {npcHandler = npcHandler, text = 'We would like to serve you some time.', reset = true})
end

addGatedTravelKeyword('liberty bay', 180, Position(32285, 32892, 6), 'liberty_bay',
	"That door hasn't opened in years, and I'm not sailing you to knock on it myself. Someone said four levers might do it -- Bender Shun would know more than I do.")
addGatedTravelKeyword('oramond', 180, Position(33479, 31985, 7), 'oramond',
	"The furnaces under Oramond aren't lit, and I won't sail you into cold machinery and worse. Check with Bender Shun before you go looking for smoke.")
addGatedTravelKeyword('roshamuul', 210, Position(33494, 32567, 7), 'roshamuul',
	"Roshamuul's still shifting rock -- and worse than rock, if the stories are true. Not a crossing I'll make until Bender Shun says it's settled.")

-- Kick
keywordHandler:addKeyword({'kick'}, StdModule.kick, {npcHandler = npcHandler, destination = {Position(32320, 32219, 6), Position(32321, 32210, 6)}})

-- Basic
keywordHandler:addKeyword({'name'}, StdModule.say, {npcHandler = npcHandler, text = 'My name is Captain Bluebear from the Royal Tibia Line.'})
keywordHandler:addKeyword({'job'}, StdModule.say, {npcHandler = npcHandler, text = 'I am the captain of this sailing-ship.'})
keywordHandler:addKeyword({'captain'}, StdModule.say, {npcHandler = npcHandler, text = 'I am the captain of this sailing-ship.'})
keywordHandler:addKeyword({'ship'}, StdModule.say, {npcHandler = npcHandler, text = 'The Royal Tibia Line connects all seaside towns of Tibia.'})
keywordHandler:addKeyword({'line'}, StdModule.say, {npcHandler = npcHandler, text = 'The Royal Tibia Line connects all seaside towns of Tibia.'})
keywordHandler:addKeyword({'company'}, StdModule.say, {npcHandler = npcHandler, text = 'The Royal Tibia Line connects all seaside towns of Tibia.'})
keywordHandler:addKeyword({'tibia'}, StdModule.say, {npcHandler = npcHandler, text = 'The Royal Tibia Line connects all seaside towns of Tibia.'})
keywordHandler:addKeyword({'good'}, StdModule.say, {npcHandler = npcHandler, text = 'We can transport everything you want.'})
keywordHandler:addKeyword({'passenger'}, StdModule.say, {npcHandler = npcHandler, text = 'We would like to welcome you on board.'})
keywordHandler:addKeyword({'trip'}, StdModule.say, {npcHandler = npcHandler, text = 'Where do you want to go? To {Carlin}, {Ab\'Dendriel}, {Venore}, {Port Hope}, {Liberty Bay}, {Svargrond}, {Roshamuul}, {krailos}, {Oramond}, {Edron} or {Daram Island}?'})
keywordHandler:addKeyword({'route'}, StdModule.say, {npcHandler = npcHandler, text = 'Where do you want to go? To {Carlin}, {Ab\'Dendriel}, {Venore}, {Port Hope}, {Liberty Bay}, {Svargrond}, {Roshamuul}, {krailos}, {Oramond}, {Edron} or {Daram Island}?'})
keywordHandler:addKeyword({'passage'}, StdModule.say, {npcHandler = npcHandler, text = 'Where do you want to go? To {Carlin}, {Ab\'Dendriel}, {Venore}, {Port Hope}, {Liberty Bay}, {Svargrond}, {Roshamuul}, {krailos}, {Oramond}, {Edron} or {Daram Island}?'})
keywordHandler:addKeyword({'town'}, StdModule.say, {npcHandler = npcHandler, text = 'Where do you want to go? To {Carlin}, {Ab\'Dendriel}, {Venore}, {Port Hope}, {Liberty Bay}, {Svargrond}, {Roshamuul}, {krailos}, {Oramond}, {Edron} or {Daram Island}?'})
keywordHandler:addKeyword({'destination'}, StdModule.say, {npcHandler = npcHandler, text = 'Where do you want to go? To {Carlin}, {Ab\'Dendriel}, {Venore}, {Port Hope}, {Liberty Bay}, {Svargrond}, {Roshamuul}, {krailos}, {Oramond}, {Edron} or {Daram Island}?'})
keywordHandler:addKeyword({'sail'}, StdModule.say, {npcHandler = npcHandler, text = 'Where do you want to go? To {Carlin}, {Ab\'Dendriel}, {Venore}, {Port Hope}, {Liberty Bay}, {Svargrond}, {Roshamuul}, {krailos}, {Oramond}, {Edron} or {Daram Island}?'})
keywordHandler:addKeyword({'go'}, StdModule.say, {npcHandler = npcHandler, text = 'Where do you want to go? To {Carlin}, {Ab\'Dendriel}, {Venore}, {Port Hope}, {Liberty Bay}, {Svargrond}, {Roshamuul}, {krailos}, {Oramond}, {Edron} or {Daram Island}?'})
keywordHandler:addKeyword({'ice'}, StdModule.say, {npcHandler = npcHandler, text = 'I\'m sorry, but we don\'t serve the routes to the Ice Islands.'})
keywordHandler:addKeyword({'senja'}, StdModule.say, {npcHandler = npcHandler, text = 'I\'m sorry, but we don\'t serve the routes to the Ice Islands.'})
keywordHandler:addKeyword({'folda'}, StdModule.say, {npcHandler = npcHandler, text = 'I\'m sorry, but we don\'t serve the routes to the Ice Islands.'})
keywordHandler:addKeyword({'vega'}, StdModule.say, {npcHandler = npcHandler, text = 'I\'m sorry, but we don\'t serve the routes to the Ice Islands.'})
keywordHandler:addKeyword({'darashia'}, StdModule.say, {npcHandler = npcHandler, text = 'I\'m not sailing there. This route is afflicted by a ghostship! However I\'ve heard that Captain Fearless from Venore sails there.'})
keywordHandler:addKeyword({'darama'}, StdModule.say, {npcHandler = npcHandler, text = 'I\'m not sailing there. This route is afflicted by a ghostship! However I\'ve heard that Captain Fearless from Venore sails there.'})
keywordHandler:addKeyword({'ghost'}, StdModule.say, {npcHandler = npcHandler, text = 'Many people who sailed to Darashia never returned because they were attacked by a ghostship! I\'ll never sail there!'})
keywordHandler:addKeyword({'thais'}, StdModule.say, {npcHandler = npcHandler, text = 'This is Thais. Where do you want to go?'})

npcHandler:setMessage(MESSAGE_GREET, 'Welcome on board, |PLAYERNAME|. Where can I {sail} you today?')
npcHandler:setMessage(MESSAGE_FAREWELL, 'Good bye. Recommend us if you were satisfied with our service.')
npcHandler:setMessage(MESSAGE_WALKAWAY, 'Good bye then.')

npcHandler:addModule(FocusModule:new())
