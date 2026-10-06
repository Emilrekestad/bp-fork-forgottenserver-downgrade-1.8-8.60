-- Rashid, the travelling trader -- "The Price of a Good Name".
-- Spec: docs/quest-reworks/11-rashid-build-plan.md; dialogue from
-- 02-rashid-owner-spoiler.md. Shared state in data/lib/quests/rashid_rework.lua.
--
-- This is the ONE Rashid definition. The RevScript copy that used to register
-- "Rashid" (data/npc/lua/shops/sell/Rashid.lua) won every lookup over this
-- file (src/npc.cpp checks registered Lua NPC types first) and opened his shop
-- to anyone who said trade; it now lives in docs/superseded-scripts/. The old
-- seven-errand quest that lived here (deer trophy, package, cheese, vase,
-- sword, goldfish) is retired with it.
--
-- He is placed and moved by data/scripts/globalevents/quests/rashid_schedule.lua.
-- His shop is the deployed sell list, byte for byte (80 entries; compared
-- against the RevScript copy before it was retired). Trade needs recognition,
-- checked on opening the window AND on every sale, so a window left open from
-- before, or kept open while he moves on, cannot be used either.

local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid) npcHandler:onCreatureAppear(cid) end
function onCreatureDisappear(cid) npcHandler:onCreatureDisappear(cid) end
function onCreatureSay(cid, type, msg) npcHandler:onCreatureSay(cid, type, msg) end
function onThink() npcHandler:onThink() end

-- NpcHandler:say puts six seconds between the lines of a table; four reads at
-- a speaking pace without the player talking over the rest of it.
local SAY_INTERVAL = 4000
local function sayLines(message, cid)
	return npcHandler:say(message, cid, false, true, SAY_INTERVAL)
end

-- ============================================================
-- SHOP (sell-only: Rashid buys these from recognised traders)
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

local NOT_RECOGNISED = "I do not buy from you yet. Ask me for a task first."

local function isNearMe(player)
	local npc = Npc()
	if not npc then
		return false
	end
	local a, b = player:getPosition(), npc:getPosition()
	return a.z == b.z and math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) <= npcHandler.talkRadius + 1
end

local function onTradeRequest(cid)
	local player = Player(cid)
	if not player then
		return false
	end
	if RashidRework.isTrusted(player) then
		return true
	end
	if not RashidRework.isEnrolled(player) then
		npcHandler:say("I do not know you yet. Ask me for a {task} first.", cid)
		return false
	end
	if RashidRework.allSixReported(player) then
		if not RashidRework.isSunday() then
			npcHandler:say("You have done every task. Come back on Sunday and say {trade}.", cid)
			return false
		end
		-- Sunday: saying trade is the meeting
		RashidRework.set(player, "sunMeeting", 1)
		if RashidRework.checkRecognition(player) then
			npcHandler:say(RashidRework.RecognitionLine, cid)
			return true
		end
	end
	npcHandler:say("Not yet. First finish the tasks I give you. Ask me for today's {task}.", cid)
	return false
end

-- Every sale and purchase, including from a window that was already open.
local function guardTransaction(cid)
	local player = Player(cid)
	if not player then
		return false
	end
	if not RashidRework.isTrusted(player) then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, NOT_RECOGNISED)
		return false
	end
	if not isNearMe(player) then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You are too far from Rashid. Step closer and try again.")
		return false
	end
	return true
end

npcHandler:setCallback(CALLBACK_ONTRADEREQUEST, onTradeRequest)
npcHandler:setCallback(CALLBACK_ONSELL, function(cid) return guardTransaction(cid) end)
npcHandler:setCallback(CALLBACK_ONBUY, function(cid) return guardTransaction(cid) end)

-- ============================================================
-- QUEST: The Price of a Good Name
-- ============================================================
local T = RashidRework.Task
local Days, DayByKey = RashidRework.Days, RashidRework.DayByKey
local Lines = QuestTokens.Lines
local ctask, cset = RashidRework.ctask, RashidRework.cset

local TOPIC_ACCEPT, TOPIC_REPORT, TOPIC_CATCHUP = 2, 3, 5
local pending = {}

-- One collection per weekday (owner, 2026-10-04). Rashid gives it on that day; once taken, the goods
-- can be brought in any later day. He keeps the goods and the day is done.
local TASK_INTRO = {
	mon = "Monday is for hides and fangs. A trader always needs them.",
	tue = "Tuesday is for scales and leather. Armourers pay well for good stock.",
	wed = "Wednesday is for small stones. Every buyer wants them.",
	thu = "Thursday is for beast parts. A good trader can always find them.",
	fri = "Friday is for dragon goods. Meat for the road, and charms for good luck.",
	sat = "Saturday is for the hard trade. Buyers never forget it.",
}

local SETTLED_TEXT = {
	mon = "Good hides and honest fangs. Monday is done.",
	tue = "Clean scales and good leather. Tuesday is done.",
	wed = "Small stones, just as I asked. Wednesday is done.",
	thu = "Fine beast parts. Thursday is done.",
	fri = "Good goods for the road. Friday is done.",
	sat = "I did not think you would finish this one. Saturday is done.",
}

local function braceList(days)
	local names = {}
	for _, day in ipairs(days) do
		names[#names + 1] = "{" .. day.name .. "}"
	end
	if #names <= 1 then
		return names[1] or ""
	end
	return table.concat(names, ", ", 1, #names - 1) .. ", or " .. names[#names]
end

local function allDone(player)
	return RashidRework.allSixReported(player)
end

local function sayJournal(cid, player)
	local lines = RashidRework.journalLines(player)
	sayLines({
		table.concat(lines, " ", 1, 3),
		table.concat(lines, " ", 4, 6),
		lines[7],
	}, cid)
end

local function finishWith(cid, player, text)
	if allDone(player) and not RashidRework.isTrusted(player) then
		sayLines({ text, "That is all six tasks. Come to me on Sunday and say {trade}." }, cid)
	else
		npcHandler:say(text, cid)
	end
end

local function offerTask(cid, player, day, catchup)
	local value = ctask(player, day.key)
	if value >= T.REPORTED then
		npcHandler:say("You have done today's task. Come back tomorrow.", cid)
		npcHandler.topic[cid] = 0
	elseif value >= T.ACCEPTED then
		npcHandler:say("You already have that task. Ask for your {journal} to see what is missing, or say {report} when you have the goods.", cid)
		npcHandler.topic[cid] = 0
	else
		sayLines({
			TASK_INTRO[day.key],
			"I want " .. RashidRework.wantText(day.key) .. ". Bring them to me and say {report}.",
			"Do you take this task?",
		}, cid)
		npcHandler.topic[cid] = TOPIC_ACCEPT
		pending[cid] = { day = day.key, catchup = catchup }
	end
end

local function sundayOpening(cid, player)
	if allDone(player) and RashidRework.get(player, "sunMeeting") < 1 then
		sayLines({
			"Today is Sunday. I do not give tasks on Sunday.",
			"But you have done every task I gave you. So now, say {trade}.",
		}, cid)
	else
		sayLines({
			"Today is Sunday. I do not give tasks on Sunday.",
			"If you missed a day, ask me for a {missed task}. I will give you one today. Then bring me the goods.",
		}, cid)
	end
	npcHandler.topic[cid] = 0
end

local function offerToday(cid, player)
	local day = RashidRework.today()
	if day then
		offerTask(cid, player, day, false)
	else
		sundayOpening(cid, player)
	end
end

local function acceptTask(cid, player)
	local offer = pending[cid]
	pending[cid] = nil
	npcHandler.topic[cid] = 0
	local day = offer and DayByKey[offer.day]
	if not day then
		return
	end
	if ctask(player, day.key) ~= T.UNSET then
		npcHandler:say("You already have that task. Ask for your {journal}.", cid)
		return
	end
	-- Revalidate: the day may have turned while we were talking.
	if offer.catchup then
		if not RashidRework.isSunday() then
			npcHandler:say("The day has changed while we talked. Ask me for today's {task}.", cid)
			return
		end
		if RashidRework.get(player, "catchupDate") == RashidRework.utcDate() then
			npcHandler:say("I already gave you a missed task today. Finish it first. The others wait for their day.", cid)
			return
		end
	elseif RashidRework.utcWday() ~= day.wday then
		npcHandler:say("The day has changed while we talked. Ask me for today's {task}.", cid)
		return
	end

	cset(player, day.key, T.ACCEPTED)
	if offer.catchup then
		RashidRework.set(player, "catchupDate", RashidRework.utcDate())
		RashidRework.set(player, "catchupTask", day.index)
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Rashid wants " .. RashidRework.wantText(day.key) .. ". Collect them and say report.")
	npcHandler:say("Good. Bring me the goods and say {report}. Ask for your {journal} if you forget.", cid)
end

local function settle(cid, player, day)
	npcHandler.topic[cid] = 0
	local value = ctask(player, day.key)
	if value >= T.REPORTED then
		npcHandler:say(Lines.alreadyDone, cid)
		return
	end
	if value < T.ACCEPTED then
		npcHandler:say("You do not have that task yet. Ask me for it on " .. day.name .. ".", cid)
		return
	end
	local missing = RashidRework.missing(player, day.key)
	if #missing > 0 then
		npcHandler:say("Not yet. I still need " .. table.concat(missing, ", ") .. ".", cid)
		return
	end
	if not RashidRework.takeCollection(player, day.key) then
		npcHandler:say("I could not count your goods. Please try again.", cid)
		return
	end
	cset(player, day.key, T.REPORTED)
	player:saveOnTransfer("quest.rashid")
	finishWith(cid, player, SETTLED_TEXT[day.key])
end

local function report(cid, player)
	local open = {}
	for _, day in ipairs(Days) do
		local value = ctask(player, day.key)
		if value >= T.ACCEPTED and value < T.REPORTED then
			open[#open + 1] = day
		end
	end
	if #open == 0 then
		sayJournal(cid, player)
		return
	end
	-- Settle the one that is ready; if several are, ask which.
	local ready = {}
	for _, day in ipairs(open) do
		if #RashidRework.missing(player, day.key) == 0 then
			ready[#ready + 1] = day
		end
	end
	if #ready == 1 then
		settle(cid, player, ready[1])
	elseif #ready > 1 then
		npcHandler:say(string.format("Which task shall we finish: %s?", braceList(ready)), cid)
		npcHandler.topic[cid] = TOPIC_REPORT
	elseif #open == 1 then
		settle(cid, player, open[1]) -- tells the player what is still missing
	else
		sayJournal(cid, player)
	end
end

local function missedTask(cid, player)
	if not RashidRework.isSunday() then
		npcHandler:say("I give a missed task only on Sunday.", cid)
		return
	end
	if RashidRework.get(player, "catchupDate") == RashidRework.utcDate() then
		npcHandler:say("I already gave you a missed task today. Finish it first.", cid)
		return
	end
	local open, accepted = {}, false
	for _, day in ipairs(Days) do
		local value = ctask(player, day.key)
		if value == T.UNSET then
			open[#open + 1] = day
		elseif value < T.REPORTED then
			accepted = true
		end
	end
	if #open == 0 then
		npcHandler:say("You have every task already. Bring me the goods and say {report}.", cid)
		return
	end
	local lines = {}
	if accepted then
		lines[#lines + 1] = "The tasks you already have can be finished on any day."
	end
	lines[#lines + 1] = string.format("I give you one missed task today. Which day: %s?", braceList(open))
	sayLines(lines, cid)
	npcHandler.topic[cid] = TOPIC_CATCHUP
end

local function dayIn(msg)
	for _, day in ipairs(Days) do
		if msgcontains(msg, day.name:lower()) then
			return day
		end
	end
	return nil
end

local function greetCallback(cid)
	local player = Player(cid)
	if not player then
		return true
	end
	if RashidRework.isTrusted(player) then
		npcHandler:setMessage(MESSAGE_GREET, "Welcome, |PLAYERNAME|. Your name is in my ledger. Say {trade} when you have goods to sell.")
	elseif not RashidRework.isEnrolled(player) then
		npcHandler:setMessage(MESSAGE_GREET, "Welcome to my cabin, |PLAYERNAME|. I live here all week now, and I rarely leave. I left my travelling behind me. If you want me to buy from you, ask me for a {task}.")
	elseif allDone(player) and RashidRework.isSunday() then
		npcHandler:setMessage(MESSAGE_GREET, "Welcome back, |PLAYERNAME|. It is Sunday, and you have done every task. Now say {trade}.")
	elseif allDone(player) then
		npcHandler:setMessage(MESSAGE_GREET, "Welcome back, |PLAYERNAME|. You have done every task. Come on Sunday and say {trade}.")
	else
		npcHandler:setMessage(MESSAGE_GREET, "Welcome back, |PLAYERNAME|. Ask me for today's {task}.")
	end
	return true
end

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	local topic = npcHandler.topic[cid] or 0
	local enrolled = RashidRework.isEnrolled(player)

	-- Answers to an open question come first.
	if topic == TOPIC_ACCEPT then
		if msgcontains(msg, "yes") then
			acceptTask(cid, player)
			return true
		elseif msgcontains(msg, "no") then
			pending[cid] = nil
			npcHandler.topic[cid] = 0
			npcHandler:say("Another time, then. Come back when you are ready.", cid)
			return true
		end
	elseif topic == TOPIC_REPORT or topic == TOPIC_CATCHUP then
		local day = dayIn(msg)
		if day then
			if topic == TOPIC_REPORT then
				settle(cid, player, day)
			else
				npcHandler.topic[cid] = 0
				-- Recompute eligibility on selection.
				if ctask(player, day.key) ~= T.UNSET then
					npcHandler:say("You already have that task. Ask for your {journal}.", cid)
				else
					offerTask(cid, player, day, true)
				end
			end
			return true
		end
	end

	if (msgcontains(msg, "task") or msgcontains(msg, "commission") or msgcontains(msg, "mission")) and not msgcontains(msg, "missed task") then
		if RashidRework.isTrusted(player) then
			npcHandler:say("You have done everything I asked. Say {trade} when you want to sell.", cid)
		elseif not enrolled then
			-- First visit: the welcome speech, then today's task.
			RashidRework.set(player, "enrolled", 1)
			sayLines({
				"Good. But I do not buy from people I do not know. First, prove your worth.",
				"I want to see how many different things you can bring me: hides, scales, stones, beast parts, dragon goods. Each day I give you one task.",
				"Come to me each day and ask for a {task}.",
			}, cid)
			addEvent(function(npcId, playerId)
				local npc, target = Npc(npcId), Player(playerId)
				if npc and target and npcHandler:isFocused(playerId) then
					offerToday(playerId, target)
				end
			end, 9000, Npc():getId(), cid)
		else
			offerToday(cid, player)
		end
		return true
	end

	if not enrolled then
		if msgcontains(msg, "journal") or msgcontains(msg, "report") or msgcontains(msg, "missed task")
			or msgcontains(msg, "unfinished business") then
			npcHandler:say(Lines.noAssignment, cid)
			return true
		end
		return true
	end

	if msgcontains(msg, "journal") then
		sayJournal(cid, player)
	elseif msgcontains(msg, "report") then
		report(cid, player)
	elseif msgcontains(msg, "replacement") then
		npcHandler:say("There is nothing of mine to replace. The goods are for you to find.", cid)
	elseif msgcontains(msg, "missed task") or msgcontains(msg, "unfinished business") then
		missedTask(cid, player)
	else
		local day = dayIn(msg)
		if day then
			-- A weekday by itself offers that task only when it is that day.
			if day == RashidRework.today() and ctask(player, day.key) == T.UNSET and not RashidRework.isTrusted(player) then
				offerTask(cid, player, day, false)
			else
				local lines = RashidRework.journalLines(player)
				npcHandler:say(lines[day.index], cid)
			end
		end
	end
	return true
end

local function onReleaseFocus(cid)
	pending[cid] = nil
end

keywordHandler:addKeyword({"job"}, StdModule.say, {npcHandler = npcHandler, text = "I am a trader. I live in this cabin now. I do not buy everything, and I do not buy from everyone."})
keywordHandler:addKeyword({"name"}, StdModule.say, {npcHandler = npcHandler, text = "I am Rashid, son of the desert."})

npcHandler:setMessage(MESSAGE_GREET, "Welcome to my cabin. I live here all week now. If you want me to buy from you, ask me for a {task}.")
npcHandler:setMessage(MESSAGE_FAREWELL, "Farewell, |PLAYERNAME|!")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Farewell, |PLAYERNAME|!")
npcHandler:setMessage(MESSAGE_SENDTRADE, "Here is what I offer!")

npcHandler:setCallback(CALLBACK_GREET, greetCallback)
npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:setCallback(CALLBACK_ONRELEASEFOCUS, onReleaseFocus)
npcHandler:addModule(FocusModule:new())
