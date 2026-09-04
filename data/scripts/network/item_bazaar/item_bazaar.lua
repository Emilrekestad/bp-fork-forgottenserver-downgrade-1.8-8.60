-- Item Bazaar network layer (client <-> server).
--
-- This file is PRESENTATION ONLY. It parses client requests, runs read
-- queries, and serialises responses. It contains no economic rules: every
-- mutation goes through the Game.bazaar* bindings into src/item_bazaar.cpp,
-- which is the single authority for eligibility, escrow, coin movement, fees,
-- anti-sniping and settlement. The website's command queue reaches the exact
-- same functions. If a rule appears to be missing here, that is deliberate --
-- it lives in the domain.
--
-- Protocol: one inbound opcode and one outbound opcode, with a sub-type byte
-- for routing, matching the house style (see game_bao / market). Opcode choice
-- is documented in src/item_bazaar.h -- notably 0x2A was rejected because it
-- collides with GameServerSpecialContainer client-side.

local OPCODE_REQUEST = 0x4E -- client -> server
local OPCODE_SEND = 0x4F    -- server -> client

-- client -> server actions
local ACTION_SYNC = 0x01
local ACTION_BROWSE = 0x02
local ACTION_DETAIL = 0x03
local ACTION_CREATE = 0x04
local ACTION_BID = 0x05
local ACTION_BUYOUT = 0x06
local ACTION_CANCEL = 0x07
local ACTION_RELIST = 0x08
local ACTION_WITHDRAW = 0x09
local ACTION_SELLABLE = 0x0A
local ACTION_HOME = 0x0B

-- server -> client responses
local RESP_CONFIG = 0x01
local RESP_BROWSE = 0x02
local RESP_DETAIL = 0x03
local RESP_MY_AUCTIONS = 0x04
local RESP_INVENTORY = 0x05
local RESP_SELLABLE = 0x06
local RESP_RESULT = 0x07
local RESP_HOME = 0x08

local AUCTION_ACTIVE = 1
local PAGE_SIZE = 25
-- Highest ItemCategory value in src/item_bazaar.h (CATEGORY_RING). Browse
-- requests are clamped to it so an out-of-range byte cannot reach the query.
local MAX_ITEM_CATEGORY = 15

-- How many entries each landing-screen section carries. Small on purpose:
-- the landing screen is a shop window, not a second browse tab.
local HOME_SECTION_LIMIT = 4
-- Featured carries its own, larger limit. Someone who has just PAID to promote
-- expects to see their item there, and with a shared limit of 4 ordered by
-- soonest-ending a fresh promotion was simply cut off by four older ones.
local HOME_PROMOTED_LIMIT = 8
local HOME_SOLD_LIMIT = 5
local HOME_HUNT_LIMIT = 10

-- Equipment a vocation can actually use, by ItemCategory. Promoted vocations
-- share their base vocation's row (5->1, 6->2, ...) via baseVocation below,
-- so recommendations do not silently stop working at the promotion.
--
-- Worn slots are appended to every set rather than repeated in each: a
-- helmet is worth recommending to anyone.
local VOCATION_WEAPONS = {
	[1] = {6},           -- Sorcerer: wand / rod
	[2] = {6},           -- Druid:    wand / rod
	[3] = {4, 9, 7},     -- Paladin:  distance, quiver, ammunition
	[4] = {1, 2, 3, 5},  -- Knight:   sword, club, axe, shield
	[9] = {8},           -- Monk:     fist
}
local UNIVERSAL_CATEGORIES = {10, 11, 12, 13, 14, 15}

local function baseVocation(vocationId)
	if vocationId >= 5 and vocationId <= 8 then
		return vocationId - 4
	end
	if vocationId == 10 then
		return 9
	end
	return vocationId
end

local function recommendedCategories(vocationId)
	local categories = {}
	for _, id in ipairs(VOCATION_WEAPONS[baseVocation(vocationId)] or {}) do
		categories[#categories + 1] = id
	end
	for _, id in ipairs(UNIVERSAL_CATEGORIES) do
		categories[#categories + 1] = id
	end
	return categories
end

local ACTION_COOLDOWN_MS = 400

-- Sort modes offered in the Browse tab. Kept server-side so the client cannot
-- inject arbitrary SQL through an ORDER BY.
local SORT_CLAUSES = {
	[0] = "`ends_at` ASC",                              -- ending soon
	[1] = "`created_at` DESC",                          -- newest
	[2] = "GREATEST(`current_bid`, `start_price`) ASC", -- price low -> high
	[3] = "GREATEST(`current_bid`, `start_price`) DESC",-- price high -> low
	[4] = "`buyout_price` IS NULL, `buyout_price` ASC", -- buyout first, cheapest
	[5] = "`tier` DESC, `ends_at` ASC",                 -- rarity
	-- Equipment type: groups swords with swords, shields with shields, so a
	-- browse of everything still reads as an organised shop rather than a
	-- jumble. Ties break on rarity then urgency.
	[6] = "`item_category` ASC, `tier` DESC, `ends_at` ASC",
}

-- Equipment slots worth scanning for listable items. Backpack is included so
-- the walk descends into carried containers; store inbox is not, since items
-- there are not tradeable.
local INVENTORY_SLOTS = {
	CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_BACKPACK, CONST_SLOT_ARMOR,
	CONST_SLOT_RIGHT, CONST_SLOT_LEFT, CONST_SLOT_LEGS, CONST_SLOT_FEET,
	CONST_SLOT_RING, CONST_SLOT_AMMO,
}

-- Finds a carried item by its engine uid. Only needed to read the item's type
-- so the class can be computed before it is handed to the domain; the domain
-- locates the instance itself and never trusts anything derived here.
local function findCarriedItemByUid(player, uid)
	local function scan(item)
		if not item then return nil end
		if item.getItemUID and item:getItemUID() == uid then return item end
		if item:isContainer() then
			for _, child in ipairs(item:getItems()) do
				local found = scan(child)
				if found then return found end
			end
		end
		return nil
	end

	for _, slot in ipairs(INVENTORY_SLOTS) do
		local found = scan(player:getSlotItem(slot))
		if found then return found end
	end
	return nil
end

local function supportsCustomNetwork(player)
	if not player then
		return false
	end
	if player.isUsingOtClient and player:isUsingOtClient() then
		return true
	end
	return player.isUsingAstraClient and player:isUsingAstraClient()
end

local function send(player, build)
	if not supportsCustomNetwork(player) then
		return
	end
	-- <close> so the message is released even if `build` raises; matches
	-- data/scripts/globalevents/server_time_sync.lua.
	local msg <close> = NetworkMessage()
	msg:addByte(OPCODE_SEND)
	build(msg)
	msg:sendToPlayer(player)
end

local function sendResult(player, success, text)
	send(player, function(msg)
		msg:addByte(RESP_RESULT)
		msg:addByte(success and 1 or 0)
		msg:addString(text or "")
		-- Echo the authoritative balance so the client never has to guess or
		-- track it locally (same contract the store uses).
		msg:addU32(math.min(player:getTibiaCoins(), 4294967295))
	end)
end

local function sendConfig(player)
	local config = Game.bazaarGetConfig()
	send(player, function(msg)
		msg:addByte(RESP_CONFIG)
		msg:addByte(config.enabled)
		msg:addU16(config.maxActiveAuctions)
		msg:addU16(config.minHours)
		msg:addU16(config.maxHours)
		msg:addU16(config.defaultHours)
		msg:addByte(config.saleFeePercent)
		msg:addU32(config.minSaleFee)
		msg:addU32(config.promotionFee)
		msg:addU16(config.antiSnipeThreshold)
		msg:addU32(math.min(player:getTibiaCoins(), 4294967295))
	end)
end

-- Writes one auction summary row. Deliberately carries NO seller or bidder
-- identity -- the Bazaar is anonymous, and the client is never given data it
-- must be trusted to hide.
local function writeAuctionRow(msg, row)
	msg:addU32(row.id)
	msg:addU16(row.itemtype)
	msg:addByte(row.tier)
	msg:addByte(row.itemClass or 0)
	msg:addString(row.name)
	msg:addString(row.description or "")
	msg:addU32(row.startPrice)
	msg:addU32(row.currentBid)
	msg:addU32(row.buyout)
	msg:addU16(math.min(row.bids, 65535))
	msg:addU32(math.max(0, row.endsAt - os.time()))
	msg:addByte(row.promoted)
end

local AUCTION_COLUMNS =
	"`id`, `itemtype`, `tier`, `item_class`, `item_name`, COALESCE(`item_description`, '') AS `item_description`, " ..
	"`start_price`, `current_bid`, " ..
	"COALESCE(`buyout_price`, 0) AS `buyout_price`, `bid_count`, `ends_at`, `promoted`"

-- Writes one landing-screen entry. Deliberately narrower than a browse row:
-- the landing screen is for orienting, and anything a buyer must weigh up
-- properly belongs on a real card in Browse.
local function writeHomeEntry(msg, row)
	msg:addU32(row.id)
	msg:addU16(row.itemtype)
	msg:addByte(row.tier)
	msg:addByte(row.itemClass or 0)
	msg:addString(row.name)
	-- ITEM_ATTRIBUTE_DESCRIPTION as captured at listing time; the client pulls
	-- the bracketed bonus fragments out of it exactly as the browse cards do.
	msg:addString(row.description or "")
	msg:addU32(row.price)
	msg:addU32(row.seconds)
	msg:addU16(math.min(row.bids or 0, 65535))
end

local function collectHome(query)
	local entries = {}
	local rows = db.storeQuery(query)
	if not rows then
		return entries
	end
	repeat
		entries[#entries + 1] = {
			id = result.getNumber(rows, "id"),
			itemtype = result.getNumber(rows, "itemtype"),
			tier = result.getNumber(rows, "tier"),
			itemClass = result.getNumber(rows, "item_class"),
			name = result.getString(rows, "item_name"),
			description = result.getString(rows, "item_description"),
			price = result.getNumber(rows, "price"),
			seconds = math.max(0, result.getNumber(rows, "seconds")),
			bids = result.getNumber(rows, "bids"),
		}
	until not result.next(rows)
	result.free(rows)
	return entries
end

-- "What are people hunting?" -- the top races killed server-wide in the last
-- ~24h, from the snapshot table (see bazaar_hunt_snapshot.lua).
--
-- Returns a list of {name, kills} plus a flag saying whether the numbers are a
-- real 24h window or the all-time fallback. That distinction is surfaced in the
-- UI rather than hidden: presenting all-time totals as "last 24h" would be a
-- lie the moment the server had not been up long enough to have two snapshots.
local function collectHunted()
	local entries = {}
	local windowed = false

	-- Kills since the last snapshot, and snapshots are taken just before each
	-- server save. That is the window players actually think in -- "what has
	-- the server been killing today" -- it resets on the save, and it moves
	-- live as people hunt rather than only once a day.
	--
	-- Differencing the CURRENT totals against one stored snapshot also means a
	-- single snapshot is enough to be useful. The earlier version compared two
	-- snapshots against each other and so showed nothing but all-time totals
	-- until a second day had gone by.
	local baseline = 0
	local row = db.storeQuery("SELECT MAX(`taken_at`) AS `t` FROM `bazaar_hunt_snapshots`")
	if row then
		baseline = result.getNumber(row, "t") or 0
		result.free(row)
	end

	local query
	if baseline > 0 then
		windowed = true
		-- Totals are aggregated in a subquery BEFORE the join. Joining first
		-- would match the snapshot row once per player who killed that race and
		-- multiply the baseline accordingly.
		query = string.format(
			"SELECT t.`raceid` AS `raceid`, (t.`total` - COALESCE(s.`kills`, 0)) AS `kills` " ..
			"FROM (SELECT `raceid`, SUM(`kills`) AS `total` FROM `player_bestiary_kills` " ..
			"GROUP BY `raceid`) t " ..
			"LEFT JOIN `bazaar_hunt_snapshots` s ON s.`raceid` = t.`raceid` AND s.`taken_at` = %d " ..
			"HAVING `kills` > 0 ORDER BY `kills` DESC LIMIT %d",
			baseline, HOME_HUNT_LIMIT)
	else
		-- No snapshot yet (fresh install, or the table was cleared). All-time
		-- totals, flagged so the heading does not claim a window the server
		-- cannot actually back up.
		query = string.format(
			"SELECT `raceid`, SUM(`kills`) AS `kills` FROM `player_bestiary_kills` " ..
			"GROUP BY `raceid` ORDER BY `kills` DESC LIMIT %d", HOME_HUNT_LIMIT)
	end

	-- Run the window first; if nobody has killed anything since the save the
	-- result is empty, and an empty leaderboard reads as broken rather than as
	-- quiet. Fall back to all-time in that case and let the heading say so.
	local rows = db.storeQuery(query)
	if windowed and not rows then
		windowed = false
		rows = db.storeQuery(string.format(
			"SELECT `raceid`, SUM(`kills`) AS `kills` FROM `player_bestiary_kills` " ..
			"GROUP BY `raceid` ORDER BY `kills` DESC LIMIT %d", HOME_HUNT_LIMIT))
	end
	if rows then
		repeat
			local raceid = result.getNumber(rows, "raceid")
			-- MonsterType accepts a raceId directly. A race with no matching
			-- monster (removed from the server since the kill was recorded) is
			-- skipped rather than shown as a blank row.
			local monsterType = MonsterType(raceid)
			local name = monsterType and monsterType:name() or nil
			if name and name ~= "" then
				entries[#entries + 1] = {name = name, kills = result.getNumber(rows, "kills")}
			end
		until not result.next(rows)
		result.free(rows)
	end

	return entries, windowed
end

-- Landing screen: what is being pushed, what suits this character, and what
-- the market has actually been paying. Three short lists rather than one long
-- one, because they answer three different questions.
local function sendHome(player)
	local now = os.time()
	local accountId = player:getAccountId()
	local live = string.format("`status` = %d AND `ends_at` > %d", AUCTION_ACTIVE, now)
	local head = "SELECT `id`, `itemtype`, `tier`, `item_class`, `item_name`, " ..
		"COALESCE(`item_description`, '') AS `item_description`, "
	local priceExpr = "GREATEST(`current_bid`, `start_price`) AS `price`, "
	local tailExpr = string.format("(`ends_at` - %d) AS `seconds`, `bid_count` AS `bids` ", now)

	local promoted = collectHome(string.format(
		head .. priceExpr .. tailExpr ..
		"FROM `bazaar_auctions` WHERE %s AND `promoted` = 1 ORDER BY `created_at` DESC LIMIT %d",
		live, HOME_PROMOTED_LIMIT))

	-- The category list is built from a fixed server-side table, never from
	-- client input, so interpolating it into the IN clause is safe.
	local categories = recommendedCategories(player:getVocation():getId())
	local recommended = {}
	if #categories > 0 then
		recommended = collectHome(string.format(
			head .. priceExpr .. tailExpr ..
			"FROM `bazaar_auctions` WHERE %s AND `item_category` IN (%s) " ..
			"AND `seller_account_id` <> %d ORDER BY `tier` DESC, `ends_at` ASC LIMIT %d",
			live, table.concat(categories, ","), accountId, HOME_SECTION_LIMIT))
	end

	-- Sold prices are public market data and carry no identity: the winner and
	-- seller columns are deliberately not selected.
	local sold = collectHome(string.format(
		head .. "COALESCE(`final_price`, 0) AS `price`, " ..
		"(%d - COALESCE(`settled_at`, %d)) AS `seconds`, `bid_count` AS `bids` " ..
		"FROM `bazaar_auctions` WHERE `status` = 3 AND `final_price` > 0 " ..
		"ORDER BY `settled_at` DESC LIMIT %d", now, now, HOME_SOLD_LIMIT))

	local hunted, huntWindowed = collectHunted()

	send(player, function(msg)
		msg:addByte(RESP_HOME)
		msg:addString(player:getVocation():getName())
		for _, section in ipairs({promoted, recommended, sold}) do
			msg:addU16(#section)
			for _, row in ipairs(section) do
				writeHomeEntry(msg, row)
			end
		end
		-- Hunting board. Flagged so the client can label all-time totals
		-- honestly instead of calling them a 24h window.
		msg:addByte(huntWindowed and 1 or 0)
		msg:addU16(#hunted)
		for _, row in ipairs(hunted) do
			msg:addString(row.name)
			msg:addU32(row.kills)
		end
	end)
end

local function sendBrowse(player, page, sortMode, tierFilter, buyoutOnly, categoryFilter)
	local clauses = {string.format("`status` = %d", AUCTION_ACTIVE), string.format("`ends_at` > %d", os.time())}

	if tierFilter > 0 then
		clauses[#clauses + 1] = string.format("`tier` = %d", tierFilter)
	end
	if buyoutOnly then
		clauses[#clauses + 1] = "`buyout_price` IS NOT NULL"
	end
	-- Equipment category (ItemCategory in src/item_bazaar.h), derived from the
	-- ItemType and stored at listing time. This replaced a free-text name
	-- search: someone looking for a shield should not have to already know
	-- which item names happen to be shields. Numeric and range-clamped by the
	-- caller, so it cannot carry anything into the query.
	if categoryFilter > 0 then
		clauses[#clauses + 1] = string.format("`item_category` = %d", categoryFilter)
	end

	local where = table.concat(clauses, " AND ")
	local order = SORT_CLAUSES[sortMode] or SORT_CLAUSES[0]
	local offset = page * PAGE_SIZE

	local total = 0
	local countRow = db.storeQuery(string.format("SELECT COUNT(*) AS `total` FROM `bazaar_auctions` WHERE %s", where))
	if countRow then
		total = result.getNumber(countRow, "total")
		result.free(countRow)
	end

	-- Read the page into plain tables in a single pass. A result handle is a
	-- forward-only cursor, so it cannot be stashed and re-walked later.
	local entries = {}
	local rows = db.storeQuery(string.format(
		"SELECT %s FROM `bazaar_auctions` WHERE %s ORDER BY %s LIMIT %d OFFSET %d",
		AUCTION_COLUMNS, where, order, PAGE_SIZE, offset))
	if rows then
		repeat
			entries[#entries + 1] = {
				id = result.getNumber(rows, "id"),
				itemtype = result.getNumber(rows, "itemtype"),
				tier = result.getNumber(rows, "tier"),
				itemClass = result.getNumber(rows, "item_class"),
				name = result.getString(rows, "item_name"),
				description = result.getString(rows, "item_description"),
				startPrice = result.getNumber(rows, "start_price"),
				currentBid = result.getNumber(rows, "current_bid"),
				buyout = result.getNumber(rows, "buyout_price"),
				bids = result.getNumber(rows, "bid_count"),
				endsAt = result.getNumber(rows, "ends_at"),
				promoted = result.getNumber(rows, "promoted"),
			}
		until not result.next(rows)
		result.free(rows)
	end

	send(player, function(msg)
		msg:addByte(RESP_BROWSE)
		msg:addU16(page)
		msg:addU32(total)
		msg:addU16(#entries)
		for _, row in ipairs(entries) do
			writeAuctionRow(msg, row)
		end
	end)
end

local function sendDetail(player, auctionId)
	local auction = Game.bazaarGetAuction(auctionId)
	if not auction then
		sendResult(player, false, "That auction no longer exists.")
		return
	end

	-- Public bid history: amounts and timestamps only, never bidder identity.
	local history = {}
	local rows = db.storeQuery(string.format(
		"SELECT `amount`, `created_at` FROM `bazaar_bids` WHERE `auction_id` = %d ORDER BY `id` DESC LIMIT 10",
		auctionId))
	if rows then
		repeat
			history[#history + 1] = {
				amount = result.getNumber(rows, "amount"),
				at = result.getNumber(rows, "created_at"),
			}
		until not result.next(rows)
		result.free(rows)
	end

	local isSeller = auction.sellerAccountId == player:getAccountId()

	send(player, function(msg)
		msg:addByte(RESP_DETAIL)
		msg:addU32(auction.id)
		msg:addU16(auction.itemType)
		msg:addByte(auction.tier)
		msg:addString(auction.itemName)
		msg:addU32(auction.startPrice)
		msg:addU32(auction.currentBid)
		msg:addU32(auction.buyoutPrice)
		msg:addU32(auction.minimumNextBid)
		msg:addU16(math.min(auction.bidCount, 65535))
		msg:addU32(math.max(0, auction.endsAt - os.time()))
		msg:addByte(auction.status)
		msg:addByte(auction.promoted)
		-- Flags the client uses purely to enable/disable buttons; the server
		-- re-checks all of this on the actual action.
		msg:addByte(isSeller and 1 or 0)
		msg:addByte(auction.currentBidderAccountId == player:getAccountId() and 1 or 0)
		msg:addU32(Game.bazaarCalculateFee(auction.buyoutPrice > 0 and auction.buyoutPrice or auction.currentBid))
		msg:addU16(#history)
		for _, entry in ipairs(history) do
			msg:addU32(entry.amount)
			msg:addU32(math.max(0, os.time() - entry.at))
		end
	end)
end

local function sendMyAuctions(player)
	local accountId = player:getAccountId()
	local rows = db.storeQuery(string.format(
		"SELECT %s, `status`, COALESCE(`final_price`, 0) AS `final_price`, COALESCE(`fee`, 0) AS `fee` " ..
		"FROM `bazaar_auctions` WHERE `seller_account_id` = %d ORDER BY " ..
		"FIELD(`status`, 1, 2, 3, 4, 5), `ends_at` DESC LIMIT 100", AUCTION_COLUMNS, accountId))

	send(player, function(msg)
		msg:addByte(RESP_MY_AUCTIONS)
		if not rows then
			msg:addU16(0)
			return
		end
		local count = 0
		local collected = {}
		repeat
			collected[#collected + 1] = {
				id = result.getNumber(rows, "id"),
				itemtype = result.getNumber(rows, "itemtype"),
				tier = result.getNumber(rows, "tier"),
				name = result.getString(rows, "item_name"),
				startPrice = result.getNumber(rows, "start_price"),
				currentBid = result.getNumber(rows, "current_bid"),
				buyout = result.getNumber(rows, "buyout_price"),
				bids = result.getNumber(rows, "bid_count"),
				endsAt = result.getNumber(rows, "ends_at"),
				status = result.getNumber(rows, "status"),
				finalPrice = result.getNumber(rows, "final_price"),
				fee = result.getNumber(rows, "fee"),
			}
			count = count + 1
		until not result.next(rows)
		result.free(rows)

		msg:addU16(count)
		for _, row in ipairs(collected) do
			msg:addU32(row.id)
			msg:addU16(row.itemtype)
			msg:addByte(row.tier)
			msg:addString(row.name)
			msg:addU32(row.startPrice)
			msg:addU32(row.currentBid)
			msg:addU32(row.buyout)
			msg:addU16(math.min(row.bids, 65535))
			msg:addU32(math.max(0, row.endsAt - os.time()))
			msg:addByte(row.status)
			msg:addU32(row.finalPrice)
			msg:addU32(row.fee)
		end
	end)
end

local function sendInventory(player)
	local accountId = player:getAccountId()
	local collected = {}
	local rows = db.storeQuery(string.format(
		"SELECT `id`, `itemtype`, `tier`, `item_name` FROM `bazaar_items` " ..
		"WHERE `owner_account_id` = %d AND `state` = 1 ORDER BY `id` DESC LIMIT 200", accountId))
	if rows then
		repeat
			collected[#collected + 1] = {
				id = result.getNumber(rows, "id"),
				itemtype = result.getNumber(rows, "itemtype"),
				tier = result.getNumber(rows, "tier"),
				name = result.getString(rows, "item_name"),
			}
		until not result.next(rows)
		result.free(rows)
	end

	-- Characters this account may withdraw to. Resolved server-side so the
	-- client cannot offer (or submit) a character from another account.
	local characters = {}
	local charRows = db.storeQuery(string.format(
		"SELECT `id`, `name` FROM `players` WHERE `account_id` = %d ORDER BY `name` ASC LIMIT 20", accountId))
	if charRows then
		repeat
			characters[#characters + 1] = {
				id = result.getNumber(charRows, "id"),
				name = result.getString(charRows, "name"),
			}
		until not result.next(charRows)
		result.free(charRows)
	end

	send(player, function(msg)
		msg:addByte(RESP_INVENTORY)
		msg:addU16(#collected)
		for _, row in ipairs(collected) do
			msg:addU32(row.id)
			msg:addU16(row.itemtype)
			msg:addByte(row.tier)
			msg:addString(row.name)
		end
		msg:addU16(#characters)
		for _, character in ipairs(characters) do
			msg:addU32(character.id)
			msg:addString(character.name)
		end
	end)
end

-- Everything in the player's inventory the Bazaar would accept. Uses the
-- domain's own eligibility check indirectly: we only surface rarity-tiered,
-- non-stackable, UID-bearing items, and createAuction re-validates properly.
local function sendSellable(player)
	local offers = {}

	local function consider(item)
		if not item then
			return
		end
		local tier = item:getTier()
		if tier < 1 or tier > 5 then
			return
		end
		if not item.hasItemUID or not item:hasItemUID() then
			return
		end
		if item:isContainer() then
			return
		end
		offers[#offers + 1] = {
			uid = item:getItemUID(),
			itemtype = item:getId(),
			tier = tier,
			name = item:getName(),
		}
	end

	-- Explicit list: CONST_SLOT_FIRST/_LAST exist in C++ but are NOT exported
	-- to Lua (only the individual slots are, see registerEnum in
	-- src/luascript.cpp), so iterating a numeric range errors out.
	-- data/scripts/talkactions/god/items/check_item_uid.lua enumerates the
	-- same way.
	for _, slot in ipairs(INVENTORY_SLOTS) do
		local item = player:getSlotItem(slot)
		if item then
			consider(item)
			local container = item:isContainer() and item or nil
			if container then
				local queue = {container}
				local index = 1
				while index <= #queue and #offers < 200 do
					for _, child in ipairs(queue[index]:getItems()) do
						consider(child)
						if child:isContainer() then
							queue[#queue + 1] = child
						end
					end
					index = index + 1
				end
			end
		end
	end

	send(player, function(msg)
		msg:addByte(RESP_SELLABLE)
		msg:addU16(#offers)
		for _, offer in ipairs(offers) do
			msg:addString(offer.uid) -- 63-bit snowflake, sent as a string to survive Lua number precision
			msg:addU16(offer.itemtype)
			msg:addByte(offer.tier)
			msg:addString(offer.name)
		end
	end)
end

local function refresh(player)
	sendMyAuctions(player)
	sendInventory(player)
end

local handler = PacketHandler(OPCODE_REQUEST)

function handler.onReceive(player, msg)
	if not supportsCustomNetwork(player) then
		return
	end

	local action = NetworkGuard.readByte(msg)
	if not action then
		return
	end

	-- Cheap per-player throttle on every Bazaar packet. The domain is safe
	-- against duplicate submissions on its own (row locks + guarded updates),
	-- so this exists to blunt packet spam, not to enforce correctness.
	if not NetworkGuard.cooldown(player, "item_bazaar", ACTION_COOLDOWN_MS) then
		return
	end

	if action == ACTION_SYNC then
		-- One packet in, everything the window needs back out. This matters
		-- because of the cooldown below: a client that answered SYNC and then
		-- immediately asked for the landing screen would have that second
		-- request silently throttled away.
		sendConfig(player)
		sendBrowse(player, 0, 0, 0, false, 0)
		sendHome(player)
		refresh(player)
		return
	end

	if action == ACTION_HOME then
		sendHome(player)
		return
	end

	if action == ACTION_BROWSE then
		local page = NetworkGuard.readU16(msg)
		local sortMode = NetworkGuard.readByte(msg)
		local tierFilter = NetworkGuard.readByte(msg)
		local buyoutOnly = NetworkGuard.readByte(msg)
		local categoryFilter = NetworkGuard.readByte(msg)
		if not page or not sortMode or not tierFilter or not buyoutOnly or not categoryFilter then
			return
		end
		sendBrowse(player, math.min(page, 1000), sortMode, math.min(tierFilter, 5), buyoutOnly ~= 0,
			math.min(categoryFilter, MAX_ITEM_CATEGORY))
		return
	end

	if action == ACTION_DETAIL then
		local auctionId = NetworkGuard.readU32(msg)
		if auctionId then
			sendDetail(player, auctionId)
		end
		return
	end

	if action == ACTION_CREATE then
		local uid = NetworkGuard.readString(msg, 32)
		local startPrice = NetworkGuard.readU32(msg)
		local buyout = NetworkGuard.readU32(msg)
		local hours = NetworkGuard.readU16(msg)
		local promote = NetworkGuard.readByte(msg)
		if not uid or not startPrice or not buyout or not hours or not promote then
			return
		end
		-- Class comes from RarityClass (data/lib/rarity/rarity_class.lua), the
		-- single definition of the thresholds; it is captured at listing time
		-- rather than re-derived per frontend.
		local listed = findCarriedItemByUid(player, uid)
		local itemClass = listed and RarityClass.getItemClass(listed:getId()) or 0
		local success, info = Game.bazaarCreateAuction(player, uid, startPrice, buyout, hours, promote ~= 0, itemClass)
		sendResult(player, success, success and string.format("Auction #%d created.", info) or info)
		if success then
			refresh(player)
			sendSellable(player)
		end
		return
	end

	if action == ACTION_BID then
		local auctionId = NetworkGuard.readU32(msg)
		local amount = NetworkGuard.readU32(msg)
		if not auctionId or not amount then
			return
		end
		local success, reason = Game.bazaarPlaceBid(player:getAccountId(), auctionId, amount,
			string.format("client:%d:%d:%d", player:getAccountId(), auctionId, os.time()))
		sendResult(player, success, success and "Bid placed." or reason)
		sendDetail(player, auctionId)
		return
	end

	if action == ACTION_BUYOUT then
		local auctionId = NetworkGuard.readU32(msg)
		if not auctionId then
			return
		end
		local success, reason = Game.bazaarBuyout(player:getAccountId(), auctionId,
			string.format("client:buyout:%d:%d", auctionId, os.time()))
		sendResult(player, success, success and "Buyout complete." or reason)
		if success then
			refresh(player)
		end
		return
	end

	if action == ACTION_CANCEL then
		local auctionId = NetworkGuard.readU32(msg)
		if not auctionId then
			return
		end
		local success, reason = Game.bazaarCancelAuction(player:getAccountId(), auctionId)
		sendResult(player, success, success and "Auction cancelled." or reason)
		if success then
			refresh(player)
		end
		return
	end

	if action == ACTION_RELIST then
		local itemId = NetworkGuard.readU32(msg)
		local startPrice = NetworkGuard.readU32(msg)
		local buyout = NetworkGuard.readU32(msg)
		local hours = NetworkGuard.readU16(msg)
		local promote = NetworkGuard.readByte(msg)
		if not itemId or not startPrice or not buyout or not hours or not promote then
			return
		end
		local success, info = Game.bazaarRelistItem(player:getAccountId(), itemId, startPrice, buyout, hours,
			promote ~= 0)
		sendResult(player, success, success and string.format("Auction #%d created.", info) or info)
		if success then
			refresh(player)
		end
		return
	end

	if action == ACTION_WITHDRAW then
		local itemId = NetworkGuard.readU32(msg)
		local characterId = NetworkGuard.readU32(msg)
		if not itemId or not characterId then
			return
		end
		local success, reason = Game.bazaarWithdrawItem(player:getAccountId(), itemId, characterId)
		sendResult(player, success, success and "Delivered to that character's Depot Inbox." or reason)
		if success then
			refresh(player)
		end
		return
	end

	if action == ACTION_SELLABLE then
		sendSellable(player)
		return
	end
end

handler:register()
