-- Rashid, the Travelling Trader.
--
-- Rebuilt 2026-09-03: this NPC previously only existed as a RevScript
-- (data/npc/lua/Rashid.lua) with a sell-only shop and ZERO quest logic, and
-- was never placed anywhere on the map -- so "The Travelling Trader Quest"
-- could never start (Mission 1) or finish (Missions 6-7), even though the
-- five NPCs downstream of him (Willard, Snake Eye, Miraia, Briasol, Uzgod)
-- were already fully and correctly wired to Storage.TravellingTrader.*.
--
-- Converted to the classic NpcHandler system (matching those five NPCs,
-- instead of the RevScript NpcsHandler API the old file used) so the whole
-- chain shares one consistent style. The dialogue and item/gold amounts are
-- ported from a reference "Rashid" implementation (data/npc/crystalserver/
-- shops/mixed/rashid_custom.lua) with two changes:
--   1. Dropped the day-of-the-week gate the reference used (real Tibia's
--      Rashid only offers each mission step on a specific day) -- this
--      server has no "travelling" implementation to hang that on, and it
--      would just make the quest needlessly stall for players.
--   2. Mission 2 (the package) is checked at value 3, not 4. The reference's
--      own Willard+Snake Eye equivalents produced a different end value than
--      THIS project's already-deployed, already-working Willard.lua/
--      Snake Eye.lua do (confirmed by reading both live scripts): visiting
--      Willard then Snake Eye here lands on Mission02 == 3, never 4. Rashid
--      is written to match what those two NPCs actually do, not the
--      reference's numbering -- they were not touched.
-- All item ids below (7397 deer trophy, 145 heavy package, 169 scarab
-- cheese, 227 fine vase, 7385 crimson sword, 5929 goldfish bowl) were
-- individually verified against this project's own data/items/items.xml
-- before use.

local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid) npcHandler:onCreatureAppear(cid) end
function onCreatureDisappear(cid) npcHandler:onCreatureDisappear(cid) end
function onCreatureSay(cid, type, msg) npcHandler:onCreatureSay(cid, type, msg) end
function onThink() npcHandler:onThink() end

-- ============================================================
-- SHOP (sell-only: Rashid buys these rare items from the player)
-- Ported unchanged from the old RevScript version's item/price list.
-- ============================================================
local shopModule = ShopModule:new()
npcHandler:addModule(shopModule)

local sellItems = {
	{7426, 8000},    -- amber staff
	{3025, 200},     -- ancient amulet
	{7404, 9000},    -- assassin dagger
	{3344, 1500},    -- beastslayer axe
	{3441, 80},      -- bone shield
	{3408, 7500},    -- bonelord helmet
	{3079, 40000},   -- boots of haste
	{7379, 1500},    -- brutetamer's staff
	{3435, 5000},    -- castle shield
	{3556, 1000},    -- crocodile boots
	{3382, 15000},   -- crown legs
	{3419, 5000},    -- crown shield
	{3333, 12000},   -- crystal mace
	{7449, 600},     -- crystal sword
	{3327, 110},     -- daramian mace
	{3328, 1000},    -- daramian waraxe
	{3421, 400},     -- dark shield
	{3388, 250000},  -- demon armor
	{3420, 30000},   -- demon shield
	{7382, 10000},   -- demonrage sword
	{3356, 1000},    -- devil helmet
	{7387, 3000},    -- diamond sceptre
	{3386, 40000},   -- dragon scale mail
	{7402, 15000},   -- dragon slayer
	{7430, 3000},    -- dragonbone staff
	{10388, 10000},  -- drakinata
	{3320, 10000},   -- fire axe
	{7457, 2000},    -- fur boots
	{7432, 1000},    -- furry club
	{3281, 10000},   -- giant sword
	{3063, 2000},    -- gold ring
	{3360, 20000},   -- golden armor
	{3364, 70000},   -- golden legs
	{3422, 1000000}, -- great shield
	{10323, 35000},  -- guardian boots
	{3340, 8000},    -- heavy mace
	{3330, 90},      -- heavy machete
	{10451, 9000},   -- jade hat
	{3370, 5000},    -- knight armor
	{7461, 200},     -- krimhorn helmet
	{3404, 1000},    -- leopard armor
	{5710, 300},     -- light shovel
	{828, 2500},     -- lightning headband
	{825, 11000},    -- lightning robe
	{3366, 150000},  -- magic plate armor
	{5904, 8000},    -- magic sulphur
	{7463, 6000},    -- mammoth fur cape
	{7381, 300},     -- mammoth whopper
	{3414, 50000},   -- mastermind shield
	{3436, 9000},    -- medusa shield
	{7418, 35000},   -- nightmare blade
	{5461, 3000},    -- pirate boots
	{6096, 1000},    -- pirate hat
	{5918, 200},     -- pirate knee breeches
	{6095, 500},     -- pirate shirt
	{3055, 2500},    -- platinum amulet
	{7462, 400},     -- ragnir helmet
	{3392, 40000},   -- royal helmet
	{7437, 7000},    -- sapphire hammer
	{3018, 200},     -- scarab amulet
	{3440, 2000},    -- scarab shield
	{7451, 5000},    -- shadow sceptre
	{3290, 500},     -- silver dagger
	{5741, 40000},   -- skull helmet
	{10438, 10000},  -- spellweaver's robe
	{5879, 100},     -- spider silk
	{3554, 20000},   -- steel boots
	{7425, 500},     -- taurus mace
	{3309, 250000},  -- thunder hammer
	{6131, 150},     -- tortoise shield
	{10392, 500},    -- twin hooks
	{3434, 25000},   -- vampire shield
	{3342, 9000},    -- war axe
	{3369, 6000},    -- warrior helmet
	{7408, 1500},    -- wyvern fang
	{10384, 14000},  -- zaoan armor
	{10406, 500},    -- zaoan halberd
	{10387, 14000},  -- zaoan legs
	{10386, 14000},  -- zaoan shoes
	{10390, 30000},  -- zaoan sword
}
for _, entry in ipairs(sellItems) do
	shopModule:addSellableItem(nil, entry[1], entry[2])
end

-- ============================================================
-- QUEST: The Travelling Trader Quest
-- ============================================================
local ITEM_DEER_TROPHY = 7397
local ITEM_PACKAGE = 145
local ITEM_SCARAB_CHEESE = 169
local ITEM_FINE_VASE = 227
local ITEM_CRIMSON_SWORD = 7385
local ITEM_GOLDFISH_BOWL = 5929

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end

	local player = Player(cid)
	local m01 = player:getStorageValue(Storage.TravellingTrader.Mission01)
	local m02 = player:getStorageValue(Storage.TravellingTrader.Mission02)
	local m03 = player:getStorageValue(Storage.TravellingTrader.Mission03)
	local m04 = player:getStorageValue(Storage.TravellingTrader.Mission04)
	local m05 = player:getStorageValue(Storage.TravellingTrader.Mission05)
	local m06 = player:getStorageValue(Storage.TravellingTrader.Mission06)
	local m07 = player:getStorageValue(Storage.TravellingTrader.Mission07)

	if msgcontains(msg, "mission") then
		if m01 < 1 then
			npcHandler:say("Well, you could attempt the mission to become a recognised trader, but it requires a lot of travelling. Are you willing to try?", cid)
			npcHandler.topic[cid] = 1
		elseif m01 == 1 then
			npcHandler:say("Have you managed to obtain a rare deer trophy for my customer?", cid)
			npcHandler.topic[cid] = 3
		elseif m01 == 2 and m02 < 1 then
			npcHandler:say("So, my friend, are you willing to proceed to the next mission to become a recognised trader?", cid)
			npcHandler.topic[cid] = 4
		elseif m02 == 3 then
			npcHandler:say("Did you bring me the package?", cid)
			npcHandler.topic[cid] = 6
		elseif m02 == 5 and m03 < 1 then
			npcHandler:say("So, my friend, are you willing to proceed to the next mission to become a recognised trader?", cid)
			npcHandler.topic[cid] = 7
		elseif m03 == 2 then
			npcHandler:say("Have you brought me the scarab cheese?", cid)
			npcHandler.topic[cid] = 9
		elseif m03 == 3 and m04 < 1 then
			npcHandler:say("Well, that's good to hear. From you as my trader and deliveryman, I expect more than bringing stinky cheese. I wonder if you are able to deliver goods so fragile they almost break when looked at. I have ordered a special elven vase from Briasol in Ab'Dendriel. Get it from him and don't even touch it, just bring it to me. Everything clear and understood?", cid)
			npcHandler.topic[cid] = 10
		elseif m04 == 2 then
			npcHandler:say("Have you brought me the vase?", cid)
			npcHandler.topic[cid] = 11
		elseif m04 == 3 and m05 < 1 then
			npcHandler:say({
				"Fine! There's one more skill that I need to test and which is cruicial for a successful trader. ...",
				"Of course you must be able to haggle, else you won't survive long in this business. To make things as hard as possible for you, I have the perfect trade partner for you. ...",
				"Dwarves are said to be the most stubborn of all traders. Travel to Kazordoon and try to get the smith Uzgod to sell a crimson sword to you. ...",
				"Of course, it has to be cheap. Don't come back with anything more expensive than 400 gold. And the quality must not suffer, of course! Everything clear and understood?"
			}, cid)
			npcHandler.topic[cid] = 13
		elseif m05 == 2 then
			npcHandler:say("Have you brought me the crimson sword?", cid)
			npcHandler.topic[cid] = 14
		elseif m05 == 3 and m06 < 1 then
			npcHandler:say({
				"My friend, it seems you have already learnt a lot about the art of trading. I think you are more than worthy to become a recognised trader. ...",
				"There is just one little favour that I would ask from you... something personal, actually, forgive my boldness. ...",
				"I have always dreamed to have a small pet, one that I could take with me and which wouldn't cause problems. ...",
				"Could you - just maybe - bring me a small goldfish in a bowl? I know that you would be able to get one, wouldn't you?"
			}, cid)
			npcHandler.topic[cid] = 16
		elseif m06 == 1 then
			npcHandler:say("Have you brought me a goldfish bowl?", cid)
			npcHandler.topic[cid] = 18
		elseif m06 == 2 and m07 ~= 1 then
			npcHandler:say("Ah, right. <ahem> I hereby declare you - one of my recognised traders! Feel free to offer me your wares!", cid)
			player:setStorageValue(Storage.TravellingTrader.Mission07, 1)
			player:addAchievement("Recognised Trader")
		else
			npcHandler:say("Come back to me another day, my friend, I have nothing new for you right now.", cid)
		end
		return true
	end

	if msgcontains(msg, "yes") then
		local topic = npcHandler.topic[cid]
		if topic == 1 then
			npcHandler:say({
				"Very good! I need talented people who are able to handle my wares with care, find good offers and the like, so I'm going to test you. ...",
				"First, I'd like to see if you can dig up rare wares. Something like a ... mastermind shield! ...",
				"Haha, just kidding, fooled you there, didn't I? Always control your nerves, that's quite important during bargaining. ...",
				"Okay, all I want from you is one of these rare deer trophies. I have a customer who ordered one, so I'd like you to deliver it to me. Everything clear and understood?"
			}, cid)
			npcHandler.topic[cid] = 2
		elseif topic == 2 then
			npcHandler:say("Fine. Then get a hold of that deer trophy and bring it to me. Just ask me about your {mission}.", cid)
			player:setStorageValue(Storage.TravellingTrader.Mission01, 1)
			npcHandler.topic[cid] = 0
		elseif topic == 3 then
			if player:removeItem(ITEM_DEER_TROPHY, 1) then
				npcHandler:say("Well done! I'll take that from you. <snags it> Come see me another day, I'll be busy for a while now.", cid)
				player:setStorageValue(Storage.TravellingTrader.Mission01, 2)
			else
				npcHandler:say("You don't have a deer trophy on you.", cid)
			end
			npcHandler.topic[cid] = 0
		elseif topic == 4 then
			npcHandler:say({
				"Alright, that's good to hear. From you as my trader and deliveryman, I expect more than finding rare items. ...",
				"You also need to be able to transport heavy wares, weaklings won't get far here. I have ordered a special package from Edron. ...",
				"Pick it up from Willard and bring it back to me. Everything clear and understood?"
			}, cid)
			npcHandler.topic[cid] = 5
		elseif topic == 5 then
			npcHandler:say("Fine. Then off you go, just ask Willard about the 'package for Rashid'.", cid)
			player:setStorageValue(Storage.TravellingTrader.Mission02, 1)
			npcHandler.topic[cid] = 0
		elseif topic == 6 then
			if player:removeItem(ITEM_PACKAGE, 1) then
				npcHandler:say("Great. Just place it over there - yes, thanks, that's it. Come see me another day, I'll be busy for a while now.", cid)
				player:setStorageValue(Storage.TravellingTrader.Mission02, 5)
			else
				npcHandler:say("You don't have the package on you.", cid)
			end
			npcHandler.topic[cid] = 0
		elseif topic == 7 then
			npcHandler:say({
				"Well, that's good to hear. From you as my trader and deliveryman, I expect more than carrying heavy packages. ...",
				"You also need to be fast and deliver wares in time. I have ordered a very special cheese wheel made from Darashian milk. ...",
				"Unfortunately, the high temperature makes it rot really fast, so it must not stay in the sun for too long. ...",
				"Please get the cheese from Miraia and bring it to me. Everything clear and understood?"
			}, cid)
			npcHandler.topic[cid] = 8
		elseif topic == 8 then
			npcHandler:say("Okay, then please find Miraia and ask her about the 'scarab cheese'.", cid)
			player:setStorageValue(Storage.TravellingTrader.Mission03, 1)
			npcHandler.topic[cid] = 0
		elseif topic == 9 then
			if player:removeItem(ITEM_SCARAB_CHEESE, 1) then
				npcHandler:say("Mmmhh, the lovely odeur of scarab cheese! I really can't understand why most people can't stand it. Thanks, well done!", cid)
				player:setStorageValue(Storage.TravellingTrader.Mission03, 3)
			else
				npcHandler:say("You don't have the scarab cheese on you.", cid)
			end
			npcHandler.topic[cid] = 0
		elseif topic == 10 then
			npcHandler:say("Okay, then please find Briasol in Ab'Dendriel and ask for a 'fine vase'.", cid)
			player:setStorageValue(Storage.TravellingTrader.Mission04, 1)
			player:addMoney(1000)
			npcHandler.topic[cid] = 0
		elseif topic == 11 then
			if player:removeItem(ITEM_FINE_VASE, 1) then
				npcHandler:say("I'm surprised that you managed to bring this vase without a single crack. That was what I needed to know, thank you.", cid)
				player:setStorageValue(Storage.TravellingTrader.Mission04, 3)
			else
				npcHandler:say("You don't have the vase on you.", cid)
			end
			npcHandler.topic[cid] = 0
		elseif topic == 13 then
			npcHandler:say("Okay, I'm curious how you will do with Uzgod. Good luck!", cid)
			player:setStorageValue(Storage.TravellingTrader.Mission05, 1)
			npcHandler.topic[cid] = 0
		elseif topic == 14 then
			if player:removeItem(ITEM_CRIMSON_SWORD, 1) then
				npcHandler:say("Ha! You are clever indeed, well done! I'll take this from you. Come see me tomorrow, I think we two might get into business after all.", cid)
				player:setStorageValue(Storage.TravellingTrader.Mission05, 3)
			else
				npcHandler:say("You don't have the crimson sword on you.", cid)
			end
			npcHandler.topic[cid] = 0
		elseif topic == 16 then
			npcHandler:say("Thanks so much! I'll be waiting eagerly for your return then.", cid)
			player:setStorageValue(Storage.TravellingTrader.Mission06, 1)
			npcHandler.topic[cid] = 0
		elseif topic == 18 then
			if player:removeItem(ITEM_GOLDFISH_BOWL, 1) then
				npcHandler:say("Thank you!! Ah, this makes my day! I'll take the rest of the day off to get to know this little guy. Come see me tomorrow, if you like.", cid)
				player:setStorageValue(Storage.TravellingTrader.Mission06, 2)
			else
				npcHandler:say("You don't have a goldfish bowl on you.", cid)
			end
			npcHandler.topic[cid] = 0
		end
		return true
	end

	if msgcontains(msg, "no") and npcHandler.topic[cid] ~= 0 then
		npcHandler:say("A pity. Come back if you change your mind.", cid)
		npcHandler.topic[cid] = 0
		return true
	end

	return true
end

keywordHandler:addKeyword({"job"}, StdModule.say, {npcHandler = npcHandler, text = "I am a travelling trader. I don't buy everything, though. And not from everyone, for that matter."})
keywordHandler:addKeyword({"name"}, StdModule.say, {npcHandler = npcHandler, text = "I am Rashid, son of the desert."})

npcHandler:setMessage(MESSAGE_GREET, "Hello |PLAYERNAME|. I buy helmets, armors, legs, boots, weapons and shields. Say {trade}! And if you're looking for work, ask me about my {mission}.")
npcHandler:setMessage(MESSAGE_FAREWELL, "Farewell, |PLAYERNAME|!")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Farewell, |PLAYERNAME|!")
npcHandler:setMessage(MESSAGE_SENDTRADE, "Here is what I offer!")

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())
