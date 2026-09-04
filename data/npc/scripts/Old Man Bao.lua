local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()					end

npcHandler:setMessage(MESSAGE_FAREWELL, "Remember: coming home is part of hunt.")
npcHandler:setMessage(MESSAGE_WALKAWAY, "No goodbye today... Something troubles that one.")
npcHandler:setMessage(MESSAGE_SENDTRADE, "Sure. Let me see what you dragged back.")

-- Both gates live in BaoConfig so the Profile can describe them without
-- duplicating the numbers. Two copies of a threshold is how a shop and the
-- screen that advertises it drift apart.
local TRADE_MIN_RANK = BaoConfig.TradeMinRank
-- Rank at which he becomes the one-stop shop: everything Grizzly Adams and
-- Yasir buy, at whichever of the two paid better (see bao_products.lua).
--
-- Beast Slayer (28 masteries) rather than earlier or later, deliberately. By
-- this rank a hunter is working Deep Country and The Wilds and is genuinely
-- drowning in products, so not walking them to Yasir is a real saving. Rank 3
-- is too soon for it to feel earned; rank 5 arrives after the problem has
-- already been solved by habit, and the reward lands on nothing.
local PRODUCTS_MIN_RANK = BaoConfig.ProductsMinRank

-- ─── His voice ──────────────────────────────────────────────────────────
--
-- The greeting is BUILT, not fixed. It reads rank, whether a promotion is
-- waiting, and what the player has left unfinished, so the first thing he says
-- is about them rather than about nothing. This is the cheapest way to make
-- him feel like a person instead of a door to a window.

local RANK_GREETING = {
	[0] = "|PLAYERNAME|. Still walking, I see. Good. That is most of it.",
	[1] = "|PLAYERNAME|. You have learned to follow a trail without losing it. Not nothing.",
	[2] = "|PLAYERNAME|. I knew that was your steps.",
	[3] = "|PLAYERNAME|. You come back quieter than you used to. That is how I know you are learning.",
	[4] = "|PLAYERNAME|. Sit, if you want. You have earned the chair.",
	[5] = "|PLAYERNAME|. There are not many left I would say that name to like that.",
	[6] = "|PLAYERNAME|. Legend of the Hunt. I still see the stray who could not hold a spear.",
}

local function countUnclaimedBounties(player)
	if not BaoBounty then
		return 0
	end
	local ready = 0
	for _, entry in ipairs(BaoBounty.boardFor(player)) do
		if not BaoBounty.isClaimed(player, entry.key)
				and BaoBounty.carriedFor(player, entry.bounty) >= entry.bounty.count then
			ready = ready + 1
		end
	end
	return ready
end

local function buildGreeting(player)
	local lines = { RANK_GREETING[BaoState.getRankId(player)] or RANK_GREETING[0] }

	-- Ordered by what he would actually raise first. A promotion outranks
	-- everything; a full bag outranks a reminder about hunts.
	local pending = BaoRank.pendingRank(player)
	if pending then
		lines[#lines + 1] = string.format(
			"Before anything else -- you have done enough to be called %s. Ask me about your {promotion} when you are ready.",
			pending.name)
	end

	local ready = countUnclaimedBounties(player)
	if ready > 0 then
		lines[#lines + 1] = string.format(
			"You are carrying enough for %d of my {orders}. Hand them over before you lose them.", ready)
	end

	if not pending and ready == 0 then
		local slots = BaoState.getActiveHunts(player)
		local active = 0
		for slot = 1, BaoState.getMaxSlots(player) do
			if slots[slot] then
				active = active + 1
			end
		end
		if active == 0 then
			lines[#lines + 1] = "You carry no hunt at all right now. Ask about {hunts} and I will find you one."
		end
	end

	lines[#lines + 1] = "Say {help} if you have forgotten what I do here."
	return table.concat(lines, " ")
end

local function greetCallback(cid)
	local player = Player(cid)
	if player and BaoState then
		npcHandler:setMessage(MESSAGE_GREET, buildGreeting(player))
	end
	return true
end

npcHandler:setCallback(CALLBACK_GREET, greetCallback)

-- ─── Opening the journal ────────────────────────────────────────────────
--
-- The window is for VOLUME -- sixty hunts, nine orders, a shop, a ledger.
-- Nobody wants to read those in dialogue. What belongs to him in person is the
-- moments: the promotion, the hand-in, the sale.

local function openJournalCallback(cid, message, keywords, parameters, node)
	npcHandler:say(parameters.text, cid)
	local player = Player(cid)
	if player and BaoProtocol and BaoProtocol.openJournal then
		BaoProtocol.openJournal(player, parameters.tab)
	end
	return true
end

-- Tab names must match the ids selectTab() switches on in
-- otclient-src/modules/game_bao/bao.lua. selectTab falls back to the Hunts tab
-- for anything it does not recognise, so an old name degrades rather than breaks.
keywordHandler:addKeyword({ "task" }, openJournalCallback, { npcHandler = npcHandler, text = "You seek another hunt? Good. Let us find one that teaches you something.", tab = "hunts" })
keywordHandler:addKeyword({ "hunts" }, openJournalCallback, { npcHandler = npcHandler, text = "Ah. Let us see what requires attention today.", tab = "hunts" })
keywordHandler:addKeyword({ "bounty" }, openJournalCallback, { npcHandler = npcHandler, text = "Small work, but honest. I need things brought to me, and I pay in standing.", tab = "bounties" })
keywordHandler:addKeyword({ "bounties" }, openJournalCallback, { npcHandler = npcHandler, text = "Nine orders. They change when the world turns over. Take what you can carry.", tab = "bounties" })
keywordHandler:addKeyword({ "rank" }, openJournalCallback, { npcHandler = npcHandler, text = "You want to know what I think of you? Look. It is written plain.", tab = "ranks" })
keywordHandler:addKeyword({ "marks" }, openJournalCallback, { npcHandler = npcHandler, text = "Marks are not coin. Coin buys bread. Marks buy my attention.", tab = "rewards" })
keywordHandler:addKeyword({ "lessons" }, openJournalCallback, { npcHandler = npcHandler, text = "What I know, I can teach. It will cost you, and it will cost more each time.", tab = "ledger" })
keywordHandler:addKeyword({ "teach" }, openJournalCallback, { npcHandler = npcHandler, text = "Sit. Listen. Pay. In that order.", tab = "ledger" })

-- ─── Promotion ──────────────────────────────────────────────────────────
--
-- The single biggest moment in the system, and it used to happen silently in a
-- hunting ground the instant a number ticked over. Now it happens here, out
-- loud, with the story beat attached.

local function promotionCallback(cid, message, keywords, parameters, node)
	local player = Player(cid)
	if not player then
		return true
	end

	local pending = BaoRank.pendingRank(player)
	if not pending then
		local rankId = BaoState.getRankId(player)
		local nextRank = nil
		for _, rank in ipairs(BaoConfig.Ranks) do
			if rank.id == rankId + 1 then
				nextRank = rank
			end
		end
		if not nextRank then
			npcHandler:say("There is nothing above where you stand. I checked. Twice.", cid)
			return true
		end

		-- Tell them what is actually missing, in his voice, rather than
		-- refusing and leaving them to work it out from the window.
		local repShort = math.max(0, nextRank.repThreshold - BaoState.getReputation(player))
		local masteryShort = math.max(0, nextRank.masteriesRequired - BaoState.getMasteryCount(player))
		local parts = {}
		if repShort > 0 then
			parts[#parts + 1] = string.format("%d more standing", repShort)
		end
		if masteryShort > 0 then
			parts[#parts + 1] = string.format("%d more hunts seen through to the end", masteryShort)
		end
		npcHandler:say(string.format("Not yet. For %s you need %s. Come back then.",
			nextRank.name, table.concat(parts, " and ")), cid)
		return true
	end

	local newRank, chapters = BaoRank.promote(player)
	if not newRank then
		npcHandler:say("Something is wrong with my books. Ask me again.", cid)
		return true
	end

	npcHandler:say(string.format(
		"Then it is done. %s. There is always bigger monster -- but today, you have earned this.",
		newRank.name), cid)

	-- The story beats land after the promotion line, in order, so a player who
	-- jumped two ranks hears both chapters rather than only the last.
	for _, chapter in ipairs(chapters or {}) do
		BaoRank.announceStoryChapter(player, chapter)
	end

	if BaoProtocol and BaoProtocol.openJournal then
		BaoProtocol.openJournal(player, "ranks")
	end
	return true
end

keywordHandler:addKeyword({ "promotion" }, promotionCallback, {})
keywordHandler:addKeyword({ "promote" }, promotionCallback, {})

-- ─── Handing in orders ──────────────────────────────────────────────────
--
-- The window can do this too, but doing it here is the point: you walk back
-- with a full bag and he takes it off you himself.

local function handInCallback(cid, message, keywords, parameters, node)
	local player = Player(cid)
	if not player or not BaoBounty then
		return true
	end

	local handed, marks, reputation = 0, 0, 0
	for _, entry in ipairs(BaoBounty.boardFor(player)) do
		if not BaoBounty.isClaimed(player, entry.key)
				and BaoBounty.carriedFor(player, entry.bounty) >= entry.bounty.count then
			local ok, result = BaoBounty.turnIn(player, entry.key)
			if ok then
				handed = handed + 1
				marks = marks + result.marks
				reputation = reputation + result.reputation
			end
		end
	end

	if handed == 0 then
		npcHandler:say("You are not carrying a full order for anything I asked. Look at the board again.", cid)
		if BaoProtocol and BaoProtocol.openJournal then
			BaoProtocol.openJournal(player, "bounties")
		end
		return true
	end

	npcHandler:say(string.format(
		"%d order%s, counted once and put away. %d Marks, %d standing. Keep bringing them.",
		handed, handed == 1 and "" or "s", marks, reputation), cid)
	return true
end

keywordHandler:addKeyword({ "orders" }, handInCallback, {})
keywordHandler:addKeyword({ "hand in" }, handInCallback, {})
keywordHandler:addKeyword({ "deliver" }, handInCallback, {})

-- ─── Selling ────────────────────────────────────────────────────────────

-- His own short list, before he trusts you with the real one.
local function getStarterSellTable()
	return {
		{ name = "antlers", id = 10297, buy = 0, sell = 50 },
		{ name = "bloody pincers", id = 9633, buy = 0, sell = 100 },
		{ name = "crab pincers", id = 10272, buy = 0, sell = 35 },
		{ name = "cyclops toe", id = 9657, buy = 0, sell = 55 },
		{ name = "frosty ear of a troll", id = 9648, buy = 0, sell = 30 },
		{ name = "hydra head", id = 10282, buy = 0, sell = 600 },
		{ name = "lancer beetle shell", id = 10455, buy = 0, sell = 80 },
		{ name = "mutated bat ear", id = 9662, buy = 0, sell = 420 },
		{ name = "sabretooth", id = 10311, buy = 0, sell = 400 },
		{ name = "sandcrawler shell", id = 10456, buy = 0, sell = 20 },
		{ name = "scarab pincers", id = 9631, buy = 0, sell = 280 },
		{ name = "terramite legs", id = 10454, buy = 0, sell = 60 },
		{ name = "terramite shell", id = 10452, buy = 0, sell = 170 },
		{ name = "terrorbird beak", id = 10273, buy = 0, sell = 95 },
	}
end

-- The full list at Beast Slayer: everything Grizzly Adams and Yasir buy that
-- actually drops off a monster, at whichever of the two paid better.
local function getFullSellTable()
	local list = {}
	for _, entry in ipairs(BaoConfig.Products or {}) do
		list[#list + 1] = { name = entry.name, id = entry.id, buy = 0, sell = entry.sell }
	end
	return list
end

local function sellTableFor(player)
	if BaoState.getRankId(player) >= PRODUCTS_MIN_RANK and BaoConfig.Products then
		return getFullSellTable()
	end
	return getStarterSellTable()
end

local function setNewTradeTable(list)
	local items = {}
	for i = 1, #list do
		local entry = list[i]
		items[entry.id] = { itemId = entry.id, buyPrice = entry.buy, sellPrice = entry.sell, subType = 0, realName = entry.name }
	end
	return items
end

local function onSell(cid, item, subType, amount, ignoreEquipped)
	local player = Player(cid)
	local items = setNewTradeTable(sellTableFor(player))
	local entry = items[item]
	if not entry or not entry.sellPrice then
		return true
	end

	if player:removeItem(entry.itemId, amount, -1, ignoreEquipped) then
		player:addMoney(entry.sellPrice * amount)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format(
			"Sold %dx %s for %d gold.", amount, entry.realName, entry.sellPrice * amount
		))
	end
	return true
end

local function onBuy(cid, item, subType, amount, ignoreCap, inBackpacks)
	-- Nothing is buyable here -- sell-only shop. Defensive no-op, should be
	-- unreachable since no entry carries a buyPrice.
	return true
end

local function tradeCallback(cid, message, keywords, parameters, node)
	local player = Player(cid)
	if not player then
		return true
	end

	local rankId = BaoState.getRankId(player)
	if rankId < TRADE_MIN_RANK then
		npcHandler:say("Not yet, hunter. Prove more first. Then I show you what I've collected.", cid)
		return true
	end

	if rankId >= PRODUCTS_MIN_RANK then
		npcHandler:say("Everything. Claws, hide, teeth, whatever is still dripping. I pay what the others pay, and you do not have to walk.", cid)
	else
		npcHandler:say("Ah. Now you've earned a look. A few things, for now. Bring me more ranks and I will take more off you.", cid)
	end

	openShopWindow(cid, sellTableFor(player), onBuy, onSell)
	return true
end

keywordHandler:addKeyword({ "trade" }, tradeCallback, {})
keywordHandler:addKeyword({ "sell" }, tradeCallback, {})

-- ─── Guidance ───────────────────────────────────────────────────────────

local function helpCallback(cid, message, keywords, parameters, node)
	local player = Player(cid)
	if not player then
		return true
	end

	local rankId = BaoState.getRankId(player)
	local lines = {
		"I keep the {hunts}, and the weekly {orders}. Finish either and I pay in standing and {marks}.",
		"When you have earned it, ask about your {promotion}. I will not offer twice.",
	}
	if rankId >= TRADE_MIN_RANK then
		if rankId >= PRODUCTS_MIN_RANK then
			lines[#lines + 1] = "Say {trade} and I will buy anything you cut off a monster."
		else
			lines[#lines + 1] = "Say {trade} and I will buy a few things off you. More, later."
		end
	end
	lines[#lines + 1] = "What I know, I can {teach}. It costs Marks, and it costs more each time."
	npcHandler:say(table.concat(lines, " "), cid)
	return true
end

keywordHandler:addKeyword({ "help" }, helpCallback, {})
keywordHandler:addKeyword({ "offer" }, helpCallback, {})

keywordHandler:addKeyword({ "job" }, StdModule.say, { npcHandler = npcHandler, text = "Some call me taskmaster. I prefer... man who points brave people toward terrible things." })
keywordHandler:addKeyword({ "Bao" }, StdModule.say, { npcHandler = npcHandler, text = "Strong name. Old weak fighter." })

local voices = {
	{ text = "This creature's kind carries greater promise today. Why? Hmm. World has its moods." },
	{ text = "A wise hunter studies tracks. A foolish hunter becomes one." },
	{ text = "The strongest hunter I ever knew died showing someone how strong he was." },
}

npcHandler:addModule(VoiceModule:new(voices))
npcHandler:addModule(FocusModule:new())
