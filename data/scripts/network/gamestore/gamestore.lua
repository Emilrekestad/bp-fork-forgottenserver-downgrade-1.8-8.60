-- GameStore PacketHandler
-- OTC sends 0xFB to open, 0xFC to buy, 0xFA for history and 0xF8 to transfer coins.
-- Server responds with 0xFD.

local OPCODE_STORE_TRANSFER = 0xF8
local OPCODE_STORE_HISTORY = 0xFA
local OPCODE_STORE_OPEN = 0xFB
local OPCODE_STORE_BUY = 0xFC
local OPCODE_STORE_SEND = 0xFD

-- Response sub-types (0xFD)
local RESP_ERROR = 0x00
local RESP_CATALOG = 0x01
local RESP_SUCCESS = 0x02
local RESP_HISTORY = 0x03

-- ─── Retired offers ────────────────────────────────────────────────────────
--
-- Offers that are still present in data/store/gamestore.xml but must never be
-- shown or sold.
--
-- (!) This list exists because THE XML IS NOT A SAFE PLACE TO DELETE AN OFFER.
-- Something outside this repository syncs/regenerates that file -- it has been
-- observed rewritten in both directions, locally and on the VPS, inside a
-- single session -- so an offer deleted there reappears. Retiring it here
-- survives, because this file is only ever changed by hand.
--
-- Both enforcement points matter and they are separate: sendStoreCatalog stops
-- it being SHOWN, and the 0xFC buy handler stops it being BOUGHT. Filtering
-- only the catalogue would leave a working purchase for anyone who kept an old
-- offer id, since the buy path looks up storeItemsById directly.
--
-- A category that is emptied entirely by this list is dropped from the
-- catalogue too, otherwise it ships as a sub-tab with nothing behind it.
local RETIRED_OFFERS = {
	-- The twelve potion packs. Removed 2026-09-05; this was the whole of the
	-- "Supplies" category, so that category disappears with them.
	[3001] = true, [3002] = true, [3003] = true, [3004] = true,
	[3005] = true, [3006] = true, [3007] = true, [3008] = true,
	[3009] = true, [3010] = true, [3011] = true, [3012] = true,

	-- Loot Boost. The global boost MECHANIC is deliberately left in place
	-- (data/lib/boosts/global_boosts.lua, GlobalBoosts.ID.LOOT): retiring the
	-- offer only removes the way to buy it, and the server_boosts table may
	-- still hold a row for a boost that was running when this shipped.
	[7105] = true,

	-- The plain half of the three duplicate pairs in Convenience. Each pair was
	-- the same fixture twice -- a 150 BPC version and a 200 BPC version that
	-- does the same job and looks better -- so the cheap one was three cards
	-- spent saying nothing. The ornate/gilded/shiny half survives in each case.
	[14308] = true, -- Mailbox            (Ornate Mailbox, 14310, remains)
	[14307] = true, -- Imbuing Shrine     (Gilded Imbuing Shrine, 14306)
	[14303] = true, -- Daily Reward Shrine (Shiny Daily Reward Shrine, 14311)
}

local function isRetiredOffer(offer)
	return offer ~= nil and RETIRED_OFFERS[offer.id] == true
end

local STORE_ACTION_DELAY = 2
local MAX_TARGET_NAME_LENGTH = 50
local MAX_CHARACTER_NAME_LENGTH = 20
local MAX_HIRELING_NAME_LENGTH = 20
local MAX_CHARACTER_NAME_WORDS = 5
local CHANGE_NAME_KICK_DELAY = 3000
local CHANGE_NAME_SUCCESS_MESSAGE = "Your character name has been changed. You will be disconnected in 3 seconds. Please log in again to use your new name."
local STORE_HOME_BANNER_DELAY = 10
local XP_BOOST_PERCENT = 50
local XP_BOOST_DEFAULT_SECONDS = 3600
local STORE_HOME_BANNERS = {
	{image = "/images/store/home/banner_exercisedummies", action = 0, target = 0}
}

local storeCategories = {}
local storeItemsById = {}

local lastBuy = {}
local lastTransfer = {}

local function supportsCustomNetwork(player)
	return player and player.isUsingOtClient and player:isUsingOtClient()
end

local taskBoardOfferTypes = {
	bounty_kill_boost = true,
	weekly_kill_boost = true,
	weekly_reduced_items = true,
	weekly_task_expansion = true,
}

local function isTaskBoardOfferType(offerType)
	return taskBoardOfferTypes[tostring(offerType or ""):lower()] == true
end

local function isTaskBoardOfferEnabled(offerType)
	offerType = tostring(offerType or ""):lower()
	if not configManager.getBoolean(configKeys.TASK_HUNTING_SYSTEM_ENABLED) then
		return false
	end
	if offerType == "bounty_kill_boost" then
		return configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED)
	end
	return configManager.getBoolean(configKeys.WEEKLY_TASKS_ENABLED)
end

local function supportsTaskBoardStore(player, offerType)
	return player and player.isUsingAstraClient and player:isUsingAstraClient() and
		isTaskBoardOfferEnabled(offerType)
end

local function isHirelingOfferType(oftype)
	oftype = tostring(oftype or ""):lower()
	return oftype == "hireling" or oftype == "hireling_skill" or oftype == "hireling_outfit"
end

-- Retired: the lamp is a quest reward handed over by an NPC, and jobs arrive
-- as contract items used on one specific hireling. Neither is sold any more.
--
-- This is enforced HERE rather than by deleting the rows from gamestore.xml,
-- because that file is regenerated/synced by something outside this codebase
-- -- an edit to it does not stay made. Filtering in Lua means a stale or
-- restored catalogue cannot put these offers back in front of players.
-- Dresses (hireling_outfit) are unaffected and still sold.
local function isRetiredHirelingOfferType(oftype)
	oftype = tostring(oftype or ""):lower()
	return oftype == "hireling" or oftype == "hireling_skill"
end

local function isHirelingCategory(category)
	local name = tostring(category and category.name or ""):lower()
	return name == "hirelings" or name == "hireling dresses"
end

local function isTaskBoardCategory(category)
	return tostring(category and category.name or ""):lower() == "task hunt"
end

local function isBattlePassOfferType(offerType)
	return tostring(offerType or ""):lower() == "battlepass"
end

local function isXpBoostOfferType(offerType)
	offerType = tostring(offerType or ""):lower()
	return offerType == "expboost" or offerType == "xpboost"
end

-- Server-wide boosts (lib/boosts/global_boosts.lua). The offer's `value` is
-- the duration in seconds and its `boost` attribute names which one; see the
-- "Server Boosts" category in data/store/gamestore.xml.
local function isGlobalBoostOfferType(offerType)
	return tostring(offerType or ""):lower() == "globalboost"
end

local function parseOfferItemList(value)
	local items = {}
	for itemId in tostring(value or ""):gmatch("%d+") do
		items[#items + 1] = tonumber(itemId)
	end
	return items
end

local function isBattlePassCategory(category)
	return tostring(category and category.name or ""):lower() == "battle pass"
end

local function supportsBattlePassStore(player)
	return configManager.getBoolean(configKeys.BATTLEPASS_SYSTEM_ENABLED) and
		player and player.isUsingAstraClient and player:isUsingAstraClient()
end

-- The store half of the hireling system needs no custom protocol, so it must
-- not be gated on the AstraClient handshake.
--
-- It used to be, and the handshake is never sent -- protocolgamesend.cpp
-- withholds the marker on purpose, because isAstraClient also switches the
-- item wire format this client cannot parse. The effect was that both hireling
-- categories were filtered out of the catalogue for every player alive, and
-- any purchase came back "The hireling system is not available".
--
-- Dresses are ordinary unlocks written to kv and applied through the
-- hireling's own dialogue, so the system being enabled is the whole
-- requirement.
local function supportsHirelingStore(player)
	return configManager.getBoolean(configKeys.HIRELING_SYSTEM_ENABLED) and player ~= nil
end

local function playerOwnsMount(player, mountId)
	if player.ownsMount then
		local ok, owned = pcall(function()
			return player:ownsMount(mountId)
		end)
		if ok then
			return owned == true
		end
	end

	if player.hasMount then
		local ok, owned = pcall(function()
			return player:hasMount(mountId)
		end)
		if ok then
			return owned == true
		end
	end

	return false
end

local function logInfo(message)
	if logger and logger.info then
		logger.info(message)
	else
		print(message)
	end
end

local function logError(message)
	if logger and logger.error then
		logger.error(message)
	else
		print(message)
	end
end

local deathSearchIndexes = {
	{tableName = "player_deaths", indexName = "idx_pd_killed_by", columnName = "killed_by"},
	{tableName = "player_deaths", indexName = "idx_pd_mostdamage_by", columnName = "mostdamage_by"},
	{tableName = "player_deaths_backup", indexName = "idx_pdb_killed_by", columnName = "killed_by"},
	{tableName = "player_deaths_backup", indexName = "idx_pdb_mostdamage_by", columnName = "mostdamage_by"}
}

local function deathColumnHasIndex(tableName, columnName)
	local resultId = db.storeQuery(
		"SELECT `INDEX_NAME` FROM `information_schema`.`STATISTICS` WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = " ..
			db.escapeString(tableName) ..
			" AND `COLUMN_NAME` = " ..
			db.escapeString(columnName) ..
			" AND `SEQ_IN_INDEX` = 1 LIMIT 1"
	)
	if resultId ~= false then
		result.free(resultId)
		return true
	end

	return false
end

local function ensureDeathSearchIndexes()
	for _, index in ipairs(deathSearchIndexes) do
		if (not db.tableExists or db.tableExists(index.tableName)) and not deathColumnHasIndex(index.tableName, index.columnName) then
			db.query(string.format("ALTER TABLE `%s` ADD INDEX `%s` (`%s`(64))", index.tableName, index.indexName, index.columnName))
		end
	end
end

local function scheduleChangeNameKick(player)
	local playerId = player:getId()
	local playerName = player:getName()
	player:sendTextMessage(MESSAGE_INFO_DESCR, CHANGE_NAME_SUCCESS_MESSAGE)

	addEvent(function(id, expectedName)
		local onlinePlayer = Player(id)
		if onlinePlayer and onlinePlayer:getName() == expectedName then
			onlinePlayer:remove()
		end
	end, CHANGE_NAME_KICK_DELAY, playerId, playerName)
end

local forbiddenNameWords = {
	gm = true,
	adm = true,
	tutor = true,
	god = true,
	cm = true,
	admin = true,
	owner = true,
	administrator = true,
	senior = true,
	xangel = true,
	["x-angel"] = true
}

local function trim(value)
	return ((value or ""):gsub("^%s*(.-)%s*$", "%1"))
end

local function formatCharacterName(name)
	name = trim(name:lower())
	return (name:gsub("(%a)([%w']*)", function(first, rest)
		return first:upper() .. rest:lower()
	end))
end

local function wordCount(value)
	local count = 0
	for _ in value:gmatch("%a+") do
		count = count + 1
	end
	return count
end

local function isValidCharacterName(name)
	if name == "" or #name < 2 or #name > MAX_CHARACTER_NAME_LENGTH then
		return false
	end

	if name:find("  ", 1, true) or wordCount(name) > MAX_CHARACTER_NAME_WORDS then
		return false
	end

	local lowered = name:lower()
	if lowered == "g m" or lowered == "g o d" or lowered == "a d m" or lowered == "c m" then
		return false
	end

	for i = 1, #name do
		local char = name:sub(i, i)
		if not char:match("[A-Za-z ]") then
			return false
		end
	end

	for word in name:gmatch("%a+") do
		if forbiddenNameWords[word:lower()] then
			return false
		end
	end

	return true
end

local function characterNameExists(name)
	local resultId = db.storeQuery("SELECT `id` FROM `players` WHERE LOWER(`name`) = LOWER(" .. db.escapeString(name) .. ") LIMIT 1")
	if resultId ~= false then
		result.free(resultId)
		return true
	end

	return false
end

local function isOnCooldown(cache, playerId)
	local now = os.time()
	if cache[playerId] and now - cache[playerId] < STORE_ACTION_DELAY then
		return true
	end

	cache[playerId] = now
	return false
end

local function sendStoreError(player, message)
	if not supportsCustomNetwork(player) then
		return false
	end

	local out = NetworkMessage(player)
	out:addByte(OPCODE_STORE_SEND)
	out:addByte(RESP_ERROR)
	out:addString(message)
	return out:sendToPlayer(player)
end

local function sendStoreSuccess(player, offerId, message)
	if not supportsCustomNetwork(player) then
		return false
	end

	local out = NetworkMessage(player)
	out:addByte(OPCODE_STORE_SEND)
	out:addByte(RESP_SUCCESS)
	out:addU32(offerId)
	out:addString(message)
	out:addU32(player:getTibiaCoins())
	return out:sendToPlayer(player)
end

local _shopHistoryCache = nil
local function shopHistoryExists()
	if _shopHistoryCache ~= nil then
		return _shopHistoryCache
	end

	if db.tableExists then
		_shopHistoryCache = db.tableExists("shop_history")
	else
		_shopHistoryCache = true
	end

	return _shopHistoryCache
end

local function addStoreHistory(accountId, playerGuid, title, price, count, target)
	if not shopHistoryExists() then
		return
	end

	title = tostring(title or "Store Purchase"):sub(1, 100)
	price = tonumber(price) or 0
	count = tonumber(count) or 0

	local targetSql = "NULL"
	if target and target ~= "" then
		targetSql = db.escapeString(target)
	end

	db.query("INSERT INTO `shop_history` (`account`, `player`, `date`, `title`, `price`, `costSecond`, `count`, `target`) VALUES (" ..
		accountId .. ", " ..
		playerGuid .. ", NOW(), " ..
		db.escapeString(title) .. ", " ..
		price .. ", 0, " ..
		count .. ", " ..
		targetSql .. ")")
end

local function sendStoreHistory(player)
	if not supportsCustomNetwork(player) then
		return false
	end

	local out = NetworkMessage(player)
	out:addByte(OPCODE_STORE_SEND)
	out:addByte(RESP_HISTORY)

	local history = {}
	if shopHistoryExists() then
		local resultId = db.storeQuery("SELECT `date`, `price`, `costSecond`, `title`, `count` FROM `shop_history` WHERE `account` = " .. player:getAccountId() .. " ORDER BY `id` DESC LIMIT 100")
		if resultId ~= false then
			repeat
				table.insert(history, {
					date = result.getDataString(resultId, "date"),
					price = result.getDataInt(resultId, "price"),
					costSecond = result.getDataInt(resultId, "costSecond"),
					title = result.getDataString(resultId, "title"),
					count = result.getDataInt(resultId, "count"),
				})
			until not result.next(resultId)
			result.free(resultId)
		end
	end

	out:addU16(#history)
	for _, entry in ipairs(history) do
		local price = entry.price or 0
		out:addString(entry.date or "")
		out:addU32(math.abs(price))
		out:addByte(price >= 0 and 1 or 0)
		out:addByte(entry.costSecond == 1 and 1 or 0)
		out:addString(entry.title or "")
		out:addU16(math.max(entry.count or 0, 0))
	end

	return out:sendToPlayer(player)
end

local function loadStoreXML()
	storeCategories = {}
	storeItemsById = {}

	local xmlDoc = XMLDocument("data/store/gamestore.xml")
	if not xmlDoc then
		logError("[GameStore] Error: could not find data/store/gamestore.xml")
		return
	end

	local root = xmlDoc:child("store")
	if not root then
		return
	end

	for category in root:children() do
		if category:name() == "category" then
			local catName = category:attribute("name") or "?"
			local catIcon = category:attribute("icon") or ""
			local catParent = category:attribute("parent") or ""
			local catDescription = category:attribute("description") or ""
			local offers = {}

			for offer in category:children() do
				if offer:name() == "offer" then
					local item = {
						id = tonumber(offer:attribute("id")) or 0,
						name = offer:attribute("name") or "Unknown",
						icon = offer:attribute("icon") or "",
						price = tonumber(offer:attribute("price")) or 0,
						eid = tonumber(offer:attribute("eid")) or 0,
						itemid = tonumber(offer:attribute("itemid")) or 0,
						items = parseOfferItemList(offer:attribute("items")),
						count = tonumber(offer:attribute("count")) or 1,
						description = offer:attribute("description") or "",
						oftype = offer:attribute("type") or "item",
						boost = offer:attribute("boost") or "",
						value = tonumber(offer:attribute("value")) or 0,
						-- Charges to stamp on a delivered item (Loot Seller). 0 leaves
						-- the item at whatever Game.createItem gives it.
						charges = tonumber(offer:attribute("charges")) or 0,
						-- "backpack" delivers into the player instead of the store
						-- inbox, for items meant to be used the moment they are
						-- bought. Server-side only -- it is deliberately NOT sent on
						-- the wire, since the catalog packet layout is fixed by the
						-- clients already in the wild.
						delivery = offer:attribute("delivery") or "",
						femalevalue = tonumber(offer:attribute("femalevalue")) or 0,
						addon = tonumber(offer:attribute("addon")) or 0,
					}
					table.insert(offers, item)
					storeItemsById[item.id] = item
				end
			end

			table.insert(storeCategories, {
				name = catName,
				icon = catIcon,
				parent = catParent,
				description = catDescription,
				offers = offers
			})
		end
	end
end

loadStoreXML()

-- ─── Catalogue overlay ─────────────────────────────────────────────────────
--
-- Structural edits applied to whatever loadStoreXML() just read: categories
-- renamed, copy rewritten, offers moved between categories, and categories
-- (with their offers) that data/store/gamestore.xml has never contained.
--
-- (!) This lives here for exactly the reason RETIRED_OFFERS does. That XML is
-- regenerated/synced by something outside this repository, so a category added
-- or renamed THERE does not stay added or renamed. Re-applied after every
-- load, the overlay survives a restored catalogue -- and the two mechanisms
-- compose: retire an offer to take it away, overlay one to move or re-word it.
--
-- Applied in a fixed order, because the steps feed each other: renames first
-- (a category's children carry its name in `parent`, and every table below is
-- keyed on the NEW name), then additions, then copy, then moves -- moves last
-- so an offer can be moved into a category the overlay itself just added.

local RENAMED_CATEGORIES = {
	-- "Equipment" was three exercise dummies, two weapons and a backpack. The
	-- backpack has a tab of its own now, and what is left is training gear.
	["Equipment"] = "Training & Gear",
	-- "Services" reads like account services. These two act on exactly ONE
	-- character -- the one that buys them -- and that is the single thing
	-- players get wrong about them.
	["Services"] = "Character Services",
}

-- The overlay owns offer ids 5100-5199. 5001 (the Feedbag) is the only other
-- id the XML uses in the 5xxx range.
local COSMETIC_BACKPACK_FIRST_ID = 5101
local COSMETIC_BACKPACK_PRICE = 75
local COSMETIC_BACKPACK_TEXT =
	"Twenty slots and one imbuement slot -- identical to a plain backpack, so " ..
	"this buys the look and nothing else. Delivered to your Store Inbox."

-- Every one of these is mechanically IDENTICAL to a plain backpack in
-- data/items/items.xml: containersize 20, one imbuement slot, the same
-- moveevent. Checked item by item, and it is why the range is priced flat --
-- there is nothing here to price a difference on. Candidates that differed
-- were left out rather than quietly sold as equals: the war backpack has no
-- imbuement slot, the jewelled one holds 22 and the anniversary one holds 15.
--
-- None of the ten drops from a monster on this server, so the store is not
-- undercutting a hunt.
local COSMETIC_BACKPACKS = {
	{item = 9604,  name = "Moon Backpack"},
	{item = 9605,  name = "Crown Backpack"},
	{item = 9601,  name = "Demon Backpack"},
	{item = 10326, name = "Dragon Backpack"},
	{item = 16100, name = "Crystal Backpack"},
	{item = 10202, name = "Heart Backpack"},
	{item = 5926,  name = "Pirate Backpack"},
	{item = 10324, name = "Expedition Backpack"},
	{item = 22084, name = "Wolf Backpack"},
	{item = 10327, name = "Minotaur Backpack"},
}

-- Fills an offer out to the exact shape loadStoreXML() produces. Every field
-- matters: deliverOffer and the catalogue writer both read this table straight,
-- and a missing `count` or `oftype` is a nil arithmetic three layers away from
-- the row that omitted it.
local function makeOffer(fields)
	local offer = {
		id = 0, name = "Unknown", icon = "", price = 0, eid = 0, itemid = 0,
		items = {}, count = 1, description = "", oftype = "item", boost = "",
		value = 0, charges = 0, delivery = "", femalevalue = 0, addon = 0,
	}
	for key, value in pairs(fields) do
		offer[key] = value
	end
	return offer
end

local function cosmeticBackpackOffers()
	local offers = {}
	for index, entry in ipairs(COSMETIC_BACKPACKS) do
		offers[#offers + 1] = makeOffer({
			id = COSMETIC_BACKPACK_FIRST_ID + index - 1,
			name = entry.name,
			price = COSMETIC_BACKPACK_PRICE,
			eid = entry.item,
			itemid = entry.item,
			description = COSMETIC_BACKPACK_TEXT,
		})
	end
	return offers
end

-- `after` names the category this one is inserted behind, because the array
-- order IS the tab order and the section order -- the client walks it as it
-- comes off the wire. Backpacks lands between Quality of Life's last child and
-- House; its own two children follow it, the way every other parent's do.
local ADDED_CATEGORIES = {
	{
		name = "Backpacks", icon = "store_backpacks", parent = "",
		after = "Task Hunt",
		description = "Containers, and what they look like. Every backpack " ..
			"here is delivered to your Store Inbox.",
	},
	{
		name = "Utility", icon = "store_backpacks", parent = "Backpacks",
		after = "Backpacks",
		description = "Backpacks that change what you can carry.",
	},
	{
		name = "Cosmetic", icon = "store_cosmetics", parent = "Backpacks",
		after = "Utility",
		description = "Ten backpacks that hold exactly what a plain one " ..
			"holds. Bought for the look.",
		offers = cosmeticBackpackOffers(),
	},
}

local MOVED_OFFERS = {
	[5001] = "Utility", -- the Feedbag, out of the old Equipment category
}

local CATEGORY_TEXT = {
	-- Was "Premium Time, the Battle Pass and character services". The Battle
	-- Pass is disabled on this server and its category is filtered out of the
	-- catalogue entirely, so the description named a tab that is not there.
	["Account"] = "Premium Time for the whole account, and one-off services " ..
		"that act on the character you are playing.",
	-- Was "convenience tools, supplies, blessings, training gear and task hunt
	-- upgrades". Supplies were the twelve potion packs, retired 2026-09-05.
	["Quality of Life"] = "Convenience tools, blessings, training gear and " ..
		"task upgrades. Bought once and kept, unless the offer says otherwise.",
	["Character Services"] = "Applied to the character that buys them. Both " ..
		"need you out of combat and standing in a protection zone.",
	["Training & Gear"] = "Exercise dummies arrive as kits in your Store " ..
		"Inbox to unwrap inside your house. The weapons go straight to your " ..
		"character.",
}

-- Rewritten offer copy.
--
-- The two character services say what deliverOffer() actually enforces -- the
-- protection-zone and combat checks, the outfit reset, the disconnect -- rather
-- than describing the feature in the abstract, because those are the terms
-- someone spending 100 BPC is agreeing to.
--
-- (!) A store tile holds about 200 characters (StoreOfferTile in the client's
-- game_store.otui: four lines in a 330px column). Past that a description
-- clips mid-sentence, which reads as a broken tile rather than as a long one.
-- Measured, not guessed: 205 characters clipped its last word on screen and
-- 196 did not. The Loot Seller's original 365 is why this table exists at all.
-- Write to the ceiling; do not let the tile find it.
local OFFER_TEXT = {
	[8001] = "Renames this character. Items, house, guild, level and skills " ..
		"all stay -- they belong to the character, not the name. Out of " ..
		"combat, in a protection zone; you are disconnected three seconds " ..
		"later.",
	[8002] = "Switches this character between male and female. Unlocked " ..
		"outfits and mounts stay unlocked, but the outfit you are wearing " ..
		"resets to the basic citizen look. Out of combat and in a protection " ..
		"zone.",
	[4701] = "100 charges, delivered into your backpack. Use one on a piece " ..
		"of loot equipment and it crumbles to dust, paying you half the shop " ..
		"price on the spot -- anything a shop would buy for up to 1,000 gold.",
	-- Had no description at all, so the tile fell back to its category's --
	-- which said nothing about wildcards. The numbers are prey_system.lua's:
	-- PREY_AUTO_BONUS_COST 1, PREY_LOCK_COST 5, PREY_MAX_WILDCARDS 53.
	[4002] = "Five Prey Wildcards, added to your character straight away. One " ..
		"rerolls a slot's bonus; five let you pick your prey from a list. You " ..
		"can hold 53 at a time.",
}

-- The four Premium Time tiers are ONE product at four sizes, so they get one
-- sentence with the day count swapped in rather than four inventions. "Adds"
-- and not "gives you": deliverOffer calls player:addPremiumDays(), so the time
-- stacks on whatever the account already has, and that is worth being exact
-- about on a 3,000 BPC offer. The benefits are the ones the Premium Time
-- category has always claimed.
for days, id in pairs({[30] = 1001, [90] = 1002, [180] = 1003, [360] = 1004}) do
	OFFER_TEXT[id] = string.format(
		"Adds %d days of Premium Time to the account. Premium opens the " ..
		"premium areas, faster travel, extra spells, house rental, guild " ..
		"creation, offline training and a larger depot.", days)
end

local function findCategoryIndex(name)
	for index, category in ipairs(storeCategories) do
		if category.name == name then
			return index
		end
	end
	return nil
end

local function applyCatalogOverlay()
	for from, to in pairs(RENAMED_CATEGORIES) do
		for _, category in ipairs(storeCategories) do
			if category.name == from then
				category.name = to
			end
			if category.parent == from then
				category.parent = to
			end
		end
	end

	for _, entry in ipairs(ADDED_CATEGORIES) do
		-- A name the XML has taken back is not something to merge into
		-- silently: the overlay would be adding a second category the client
		-- keys by the same title. Say so and skip.
		if findCategoryIndex(entry.name) then
			logError(string.format(
				"[GameStore] overlay: category '%s' already exists in gamestore.xml, not added",
				entry.name))
		else
			local offers = entry.offers or {}
			for _, offer in ipairs(offers) do
				if storeItemsById[offer.id] then
					logError(string.format(
						"[GameStore] overlay: offer id %d is already in gamestore.xml", offer.id))
				end
				storeItemsById[offer.id] = offer
			end

			local category = {
				name = entry.name,
				icon = entry.icon or "",
				parent = entry.parent or "",
				description = entry.description or "",
				offers = offers,
			}

			local anchor = entry.after and findCategoryIndex(entry.after)
			table.insert(storeCategories, anchor and (anchor + 1) or (#storeCategories + 1), category)
		end
	end

	for _, category in ipairs(storeCategories) do
		local text = CATEGORY_TEXT[category.name]
		if text then
			category.description = text
		end
	end

	for id, text in pairs(OFFER_TEXT) do
		local offer = storeItemsById[id]
		if offer then
			offer.description = text
		else
			logError(string.format("[GameStore] overlay: no offer %d to re-word", id))
		end
	end

	-- Lifted out of every category first and appended afterwards, so a move
	-- does not depend on which category the walk reaches first, and moving an
	-- offer into a category the overlay just added works the same as any other.
	local arriving = {}
	for id, target in pairs(MOVED_OFFERS) do
		local moving = nil
		for _, category in ipairs(storeCategories) do
			for index = #category.offers, 1, -1 do
				if category.offers[index].id == id then
					moving = table.remove(category.offers, index)
				end
			end
		end

		if not moving then
			logError(string.format("[GameStore] overlay: no offer %d to move to '%s'", id, target))
		else
			arriving[target] = arriving[target] or {}
			table.insert(arriving[target], moving)
		end
	end

	for target, offers in pairs(arriving) do
		local index = findCategoryIndex(target)
		if not index then
			logError(string.format("[GameStore] overlay: no category '%s' to move offers into", target))
		else
			for _, offer in ipairs(offers) do
				table.insert(storeCategories[index].offers, offer)
			end
		end
	end
end

applyCatalogOverlay()

ensureDeathSearchIndexes()

local function sendStoreCatalog(player)
	if not supportsCustomNetwork(player) then
		return false
	end

	local visibleCategories = {}
	for _, cat in ipairs(storeCategories) do
		local visibleOffers = {}
		for _, offer in ipairs(cat.offers) do
			local taskBoardVisible = not isTaskBoardOfferType(offer.oftype) or
				supportsTaskBoardStore(player, offer.oftype)
			local hirelingVisible = not isRetiredHirelingOfferType(offer.oftype) and
				(not isHirelingOfferType(offer.oftype) or supportsHirelingStore(player))
			local battlePassVisible = not isBattlePassOfferType(offer.oftype) or supportsBattlePassStore(player)
			if taskBoardVisible and hirelingVisible and battlePassVisible and not isRetiredOffer(offer) then
				visibleOffers[#visibleOffers + 1] = offer
			end
		end

		-- A category that HAD offers and now shows none has been emptied by the
		-- filters above, and an empty sub-tab is worse than no sub-tab. One that
		-- never had offers of its own is a parent shell (Quality of Life,
		-- House, Account) and must survive, or its whole tab disappears.
		local emptied = #cat.offers > 0 and #visibleOffers == 0

		if not emptied and (#visibleOffers > 0 or
			(not isHirelingCategory(cat) and not isTaskBoardCategory(cat) and not isBattlePassCategory(cat))) then
			visibleCategories[#visibleCategories + 1] = {
				name = cat.name,
				icon = cat.icon,
				parent = cat.parent,
				description = cat.description,
				offers = visibleOffers
			}
		end
	end

	local out = NetworkMessage(player)
	out:addByte(OPCODE_STORE_SEND)
	out:addByte(RESP_CATALOG)

	out:addU32(player:getTibiaCoins())
	out:addU16(#visibleCategories)

	for _, cat in ipairs(visibleCategories) do
		out:addString(cat.name)
		out:addString(cat.icon)
		out:addString(cat.parent)
		out:addString(cat.description)
		out:addU16(#cat.offers)

		for _, offer in ipairs(cat.offers) do
			local displayId = offer.eid
			if offer.oftype == "outfit" and player:getSex() == PLAYERSEX_FEMALE and offer.femalevalue > 0 then
				displayId = offer.femalevalue
			end

			out:addU32(offer.id)
			out:addString(offer.name)
			out:addString(offer.icon)
			out:addU32(offer.price)
			out:addU16(displayId)
			out:addU16(offer.count)
			out:addString(offer.description)
			out:addString(offer.oftype)
		end
	end

	out:addByte(#STORE_HOME_BANNERS)
	for _, banner in ipairs(STORE_HOME_BANNERS) do
		out:addString(banner.image)
		out:addByte(banner.action)
		out:addU32(banner.target)
	end
	out:addByte(STORE_HOME_BANNER_DELAY)

	return out:sendToPlayer(player)
end

local function deliverOffer(player, offer, extra)
	if isTaskBoardOfferType(offer.oftype) and not supportsTaskBoardStore(player, offer.oftype) then
		return "This Task Hunt offer is not available."
	end
	if isBattlePassOfferType(offer.oftype) and not supportsBattlePassStore(player) then
		return "Battle Pass system is not available."
	end

	if offer.oftype == "bounty_kill_boost" then
		if not TaskBoard.activateTimedBoost(player, TaskBoard.Storage.BOUNTY_KILL_BOOST_UNTIL, offer.value) then
			return "Failed to activate the bounty kill boost."
		end
		return nil
	end

	if offer.oftype == "weekly_kill_boost" then
		if not TaskBoard.activateTimedBoost(player, TaskBoard.Storage.WEEKLY_KILL_BOOST_UNTIL, offer.value) then
			return "Failed to activate the weekly kill boost."
		end
		return nil
	end

	if offer.oftype == "weekly_reduced_items" then
		if not TaskBoard.activateTimedBoost(player, TaskBoard.Storage.WEEKLY_REDUCED_ITEMS_UNTIL, offer.value) then
			return "Failed to activate reduced weekly item amounts."
		end
		if _TASK_BOARD_WEEKLY_MODULE and _TASK_BOARD_WEEKLY_MODULE.applyReducedItems then
			_TASK_BOARD_WEEKLY_MODULE.applyReducedItems(player)
		end
		return nil
	end

	if offer.oftype == "weekly_task_expansion" then
		if player:hasWeeklyExpansion() then
			return "You already have the Permanent Weekly Task Expansion."
		end
		player:setWeeklyExpansion(true)
		if _TASK_BOARD_WEEKLY_MODULE and _TASK_BOARD_WEEKLY_MODULE.applyExpansion then
			_TASK_BOARD_WEEKLY_MODULE.applyExpansion(player)
		end
		return nil
	end

	if offer.oftype == "premium" then
		if offer.value <= 0 then
			return "Invalid premium amount."
		end
		player:addPremiumDays(offer.value)
		return nil
	end

	if offer.oftype == "battlepass" then
		if not BattlePassSystem or not BattlePassSystem.purchasePremium then
			return "Battle Pass system is not available."
		end

		return BattlePassSystem.purchasePremium(player, true)
	end

	-- Server-wide boost. Unlike every other offer here this delivers nothing
	-- to the buyer specifically -- it extends a global timer that everyone
	-- online benefits from, and announces who paid for it. GlobalBoosts.extend
	-- refuses (and this returns its message) when the boost is already stacked
	-- to the cap, which is the only way this purchase can fail; the caller
	-- takes no coins when a delivery error comes back.
	if isGlobalBoostOfferType(offer.oftype) then
		if not GlobalBoosts then
			return "Server boosts are not available."
		end

		local boost = GlobalBoosts.ByKey[tostring(offer.boost or ""):lower()]
		if not boost then
			logError("[GameStore] Offer " .. tostring(offer.id) ..
				" is type globalboost but names no valid boost (boost=\"" .. tostring(offer.boost) .. "\").")
			return "This boost is not available."
		end

		local duration = offer.value > 0 and offer.value or 1800
		local ok, reason = GlobalBoosts.extend(boost.id, duration, player:getName())
		if not ok then
			return reason
		end

		return nil
	end

	if isXpBoostOfferType(offer.oftype) then
		if not player.getXpBoostTime or not player.setXpBoostTime or not player.setXpBoostPercent then
			return "XP Boost is not available."
		end

		if player:getXpBoostTime() > 0 then
			return "You already have an active XP boost."
		end

		local duration = offer.value > 0 and offer.value or XP_BOOST_DEFAULT_SECONDS
		player:setXpBoostPercent(XP_BOOST_PERCENT)
		player:setXpBoostTime(math.min(65535, duration))
		return nil
	end

	if offer.oftype == "blessing" or offer.oftype == "bless" then
		if offer.value == -1 then
			local added = false
			for blessing = 1, 5 do
				if not player:hasBlessing(blessing) then
					player:addBlessing(blessing)
					added = true
				end
			end

			if not added then
				return "You already have all regular blessings."
			end
			return nil
		end

		if offer.value >= 1 and offer.value <= 5 then
			if player:hasBlessing(offer.value) then
				return "You already have this blessing."
			end

			player:addBlessing(offer.value)
			return nil
		end

		return "Invalid blessing."
	end

	if offer.oftype == "outfit" then
		local outfitValues = {offer.value}
		if offer.femalevalue > 0 and offer.femalevalue ~= offer.value then
			table.insert(outfitValues, offer.femalevalue)
		end

		local added = false
		for _, lookType in ipairs(outfitValues) do
			if lookType > 0 and not player:hasOutfit(lookType, offer.addon) then
				player:addOutfit(lookType)
				if offer.addon > 0 then
					player:addOutfitAddon(lookType, offer.addon)
				end
				added = true
			end
		end

		if not added then
			return "You already have this outfit."
		end
		return nil
	end

	if offer.oftype == "mount" then
		if playerOwnsMount(player, offer.value) then
			return "You already have this mount."
		end

		if not player:addMount(offer.value) then
			return "Failed to deliver mount."
		end
		return nil
	end

	if offer.oftype == "prey_wildcard" then
		if not PreySystem or not PreySystem.addWildcards then
			return "Prey System is not available."
		end

		if offer.value <= 0 then
			return "Invalid Prey Wildcard amount."
		end

		PreySystem.addWildcards(player, offer.value)
		return nil
	end

	if offer.oftype == "house" then
		local inbox = player:getStoreInbox()
		if not inbox then
			return "Your store inbox is not available."
		end

		local deliveryIds = offer.items or {}
		if #deliveryIds == 0 and offer.itemid > 0 then
			deliveryIds = {offer.itemid}
		end
		if #deliveryIds == 0 then
			return "Invalid house item."
		end

		local createdItems = {}
		local function removeCreatedItems()
			for _, created in ipairs(createdItems) do
				created:remove()
			end
		end

		for _, itemId in ipairs(deliveryIds) do
			local itemType = ItemType(itemId)
			if not itemType or itemType:getId() == 0 then
				removeCreatedItems()
				return "Invalid house item."
			end

			local kit = Game.createItem(ITEM_DECORATION_KIT, 1)
			if not kit then
				removeCreatedItems()
				return "Failed to create item."
			end

			kit:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "You bought this item in the Store.\nUnwrap it in your own house to create a <" .. itemType:getName() .. ">.")
			kit:setAttribute(ITEM_ATTRIBUTE_WRAPID, itemId)
			createdItems[#createdItems + 1] = kit
		end

		for _, item in ipairs(createdItems) do
			if inbox:addItemEx(item) ~= RETURNVALUE_NOERROR then
				removeCreatedItems()
				return "Your store inbox is full."
			end
		end

		player:sendTextMessage(MESSAGE_STATUS_SMALL, "Your house item was sent to your store inbox.")
		return nil
	end

	if offer.oftype == "item" and offer.itemid > 0 then
		-- delivery="backpack" hands the item to the character instead of the
		-- store inbox, so a consumable is usable the moment it is bought
		-- rather than after a trip to a depot. The client already labels every
		-- "item" offer as going to "Your backpack" (OFFER_KINDS in
		-- modules/game_store/game_store.lua), so this is the one case where
		-- that label is literally true.
		local toBackpack = offer.delivery == "backpack"

		local inbox = nil
		if not toBackpack then
			inbox = player:getStoreInbox()
			if not inbox then
				return "Your store inbox is not available."
			end
		end

		-- For an item whose ItemType carries charges, Item::setSubType reads
		-- the create count AS the charge count (src/item.cpp), so a plain
		-- count of 1 would hand over a one-charge item. offer.charges is the
		-- explicit subtype for those; count stays the number of items, so the
		-- purchase history still reads as one purchase.
		local subType = offer.charges > 0 and offer.charges or offer.count
		local item = Game.createItem(offer.itemid, subType)
		if not item then
			return "Failed to create item."
		end

		if toBackpack then
			if player:addItemEx(item) ~= RETURNVALUE_NOERROR then
				item:remove()
				return "You have no room to carry this. Free some space and try again."
			end
			player:sendTextMessage(MESSAGE_STATUS_SMALL, "Your item was placed in your backpack.")
			return nil
		end

		if inbox:addItemEx(item) ~= RETURNVALUE_NOERROR then
			item:remove()
			return "Your store inbox is full."
		end
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "Your item was sent to your store inbox.")
		return nil
	end

	if offer.oftype == "changename" then
		local newName = formatCharacterName(extra and extra.name or "")
		if not isValidCharacterName(newName) then
			return "You cannot use this character name."
		end

		if characterNameExists(newName) then
			return "Character name already taken."
		end

		if player:getCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT) or player:getCondition(CONDITION_INFIGHT, CONDITIONID_COMBAT) then
			return "You cannot do this during a fight."
		end

		local tile = player:getTile()
		if not tile or not tile:hasFlag(TILESTATE_PROTECTIONZONE) then
			return "You need to be in a protection zone."
		end

		local oldName = player:getName()
		db.query("UPDATE `players` SET `name` = " .. db.escapeString(newName) .. " WHERE `id` = " .. player:getGuid())
		db.query("UPDATE `player_deaths` SET `killed_by` = " .. db.escapeString(newName) .. ", `mostdamage_by` = " .. db.escapeString(newName) .. " WHERE `killed_by` = " .. db.escapeString(oldName) .. " OR `mostdamage_by` = " .. db.escapeString(oldName))
		db.query("UPDATE `player_deaths_backup` SET `killed_by` = " .. db.escapeString(newName) .. ", `mostdamage_by` = " .. db.escapeString(newName) .. " WHERE `killed_by` = " .. db.escapeString(oldName) .. " OR `mostdamage_by` = " .. db.escapeString(oldName))

		if db.tableExists and db.tableExists("change_name_history") then
			db.query("INSERT INTO `change_name_history` (`player_id`, `last_name`, `current_name`, `changed_name_in`) VALUES (" .. player:getGuid() .. ", " .. db.escapeString(oldName) .. ", " .. db.escapeString(newName) .. ", " .. os.time() .. ")")
		end

		return nil
	end

	if offer.oftype == "sexchange" then
		if player:getCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT) or player:getCondition(CONDITION_INFIGHT, CONDITIONID_COMBAT) then
			return "You cannot do this during a fight."
		end

		local tile = player:getTile()
		if not tile or not tile:hasFlag(TILESTATE_PROTECTIONZONE) then
			return "You need to be in a protection zone."
		end

		player:setSex(player:getSex() == PLAYERSEX_FEMALE and PLAYERSEX_MALE or PLAYERSEX_FEMALE)

		local outfit = player:getOutfit()
		if player:getSex() == PLAYERSEX_MALE then
			outfit.lookType = 128
		else
			outfit.lookType = 136
		end
		player:setOutfit(outfit)
		return nil
	end

	-- "hireling" (the lamp) and "hireling_skill" (the jobs) are deliberately
	-- NOT sold here any more. The lamp is a quest reward handed over by an NPC,
	-- and jobs arrive as contract items used on one specific hireling. Both
	-- offer types are removed from gamestore.xml; these branches are gone so a
	-- stale offer row cannot quietly resurrect a second source of truth.
	if offer.oftype == "hireling" or offer.oftype == "hireling_skill" then
		return "This is no longer sold in the store."
	end

	if offer.oftype == "hireling_outfit" then
		if not supportsHirelingStore(player) then
			return "The hireling system is not available."
		end

		local outfitName = GetHirelingOutfitNameById(offer.value > 0 and offer.value or offer.eid)
		if not outfitName then
			return "Invalid hireling dress."
		end

		if player:hasHirelingOutfit(outfitName) then
			return "You already have this hireling dress."
		end

		player:enableHirelingOutfit(outfitName)
		return nil
	end

	return "Invalid offer type."
end

-- ============================================================
-- Handler: OTC asks to open the store (opcode 0xFB)
-- ============================================================
local openHandler = PacketHandler(OPCODE_STORE_OPEN)

function openHandler.onReceive(player, msg)
	sendStoreCatalog(player)
end

openHandler:register()

-- ============================================================
-- Handler: OTC asks for purchase history (opcode 0xFA)
-- ============================================================
local historyHandler = PacketHandler(OPCODE_STORE_HISTORY)

function historyHandler.onReceive(player, msg)
	sendStoreHistory(player)
end

historyHandler:register()

-- ============================================================
-- Handler: OTC buys an offer (opcode 0xFC)
-- ============================================================
local buyHandler = PacketHandler(OPCODE_STORE_BUY)

function buyHandler.onReceive(player, msg)
	if msg:len() - msg:tell() < 4 then
		return
	end

	local pid = player:getId()
	if isOnCooldown(lastBuy, pid) then
		sendStoreError(player, "Please wait before buying again.")
		return
	end

	-- Circuit breaker, thrown from the console. Refuses before the offer is
	-- even read, so a tripped store cannot be talked into anything.
	if Tuning and not Tuning.enabled("feature.store") then
		sendStoreError(player, "The store is closed for maintenance. Please try again later.")
		return
	end

	local offerId = NetworkGuard.readU32(msg)
	if not offerId then
		return
	end

	local offer = storeItemsById[offerId]
	if not offer then
		sendStoreError(player, "Offer not found.")
		return
	end
	-- Same message as an unknown id: a retired offer is not "unavailable to
	-- you", it is gone, and saying so invites asking when it comes back.
	if isRetiredOffer(offer) then
		sendStoreError(player, "Offer not found.")
		return
	end
	if isTaskBoardOfferType(offer.oftype) and not supportsTaskBoardStore(player, offer.oftype) then
		sendStoreError(player, "This Task Hunt offer is not available.")
		return
	end
	if isHirelingOfferType(offer.oftype) and not supportsHirelingStore(player) then
		sendStoreError(player, "The hireling system is not available.")
		return
	end
	if isBattlePassOfferType(offer.oftype) and not supportsBattlePassStore(player) then
		sendStoreError(player, "Battle Pass system is not available.")
		return
	end

	local extra = {}
	if offer.oftype == "changename" then
		extra.name = NetworkGuard.readString(msg, MAX_CHARACTER_NAME_LENGTH)
		if not extra.name then
			sendStoreError(player, "You need to choose a new character name.")
			return
		end
	elseif offer.oftype == "hireling" then
		extra.name = NetworkGuard.readString(msg, MAX_HIRELING_NAME_LENGTH)
		if not extra.name then
			sendStoreError(player, "You need to choose a hireling name.")
			return
		end

		extra.sex = NetworkGuard.readByte(msg)
		if extra.sex == nil then
			sendStoreError(player, "You need to choose a hireling sex.")
			return
		end
	end

	-- Charge first, then deliver. The old order delivered and only then wrote
	-- the balance, so a failed write handed out a free purchase. Charging
	-- first means the worst case is a reversal, which the ledger shows as two
	-- rows rather than as a purchase that never happened.
	local ledgerMeta = {
		offer_id = offerId,
		offer_name = offer.name,
		category = offer.category,
		oftype = offer.oftype,
		channel = "game",
	}

	local charged, chargeError = Coins.spend(player, offer.price, "spend.store", nil, ledgerMeta)
	if not charged then
		sendStoreError(player, chargeError == "insufficient coins"
			and "Not enough Bp Coins."
			or "Could not complete the purchase.")
		return
	end

	local deliveryError = deliverOffer(player, offer, extra)
	if deliveryError then
		ledgerMeta.reversal = true
		ledgerMeta.reason = deliveryError
		Coins.grant(player, offer.price, "spend.store", nil, ledgerMeta)
		sendStoreError(player, deliveryError)
		return
	end

	local historyCount = offer.oftype == "item" and offer.count or (offer.oftype == "house" and math.max(#(offer.items or {}), offer.count or 1) or (offer.oftype == "prey_wildcard" and offer.value or 1))
	addStoreHistory(player:getAccountId(), player:getGuid(), offer.name, -offer.price, historyCount, nil)

	-- Recorded only once delivery succeeded, so a reversed purchase never
	-- appears in the feed as a sale. The coin ledger keeps both rows because
	-- money moved twice; this stream is about what happened, not about cash.
	GameEvents.emitForPlayer("store.purchase", player, {
		offer = offer.name,
		offer_id = offerId,
		category = offer.category,
		oftype = offer.oftype,
		coins = offer.price,
		count = historyCount,
	}, "offer", tostring(offerId))

	if isGlobalBoostOfferType(offer.oftype) then
		-- The broadcast has already gone out from GlobalBoosts.extend; this
		-- is the buyer's own confirmation, and it reports the new total rather
		-- than what they just added, since the total is what the HUD shows.
		local boost = GlobalBoosts and GlobalBoosts.ByKey[tostring(offer.boost or ""):lower()]
		if boost then
			sendStoreSuccess(player, offerId, string.format("%s is now running for %s.",
				boost.name, GlobalBoosts.formatDuration(GlobalBoosts.remaining(boost.id))))
		else
			sendStoreSuccess(player, offerId, "Purchase complete: " .. offer.name)
		end
	elseif isXpBoostOfferType(offer.oftype) then
		player:sendStats()
		sendStoreSuccess(player, offerId, "Your XP Boost is now active.")
	elseif offer.oftype == "changename" then
		sendStoreSuccess(player, offerId, CHANGE_NAME_SUCCESS_MESSAGE)
		scheduleChangeNameKick(player)
	else
		sendStoreSuccess(player, offerId, "Purchase complete: " .. offer.name)
	end
end

buyHandler:register()

-- ============================================================
-- Handler: OTC transfers Bp Coins to another player (opcode 0xF8)
-- Payload: String(targetName) + U32(amount)
-- ============================================================
local transferHandler = PacketHandler(OPCODE_STORE_TRANSFER)

function transferHandler.onReceive(player, msg)
	if msg:len() - msg:tell() < 6 then
		return
	end

	local pid = player:getId()
	if isOnCooldown(lastTransfer, pid) then
		sendStoreError(player, "Please wait before transferring again.")
		return
	end

	local targetName = NetworkGuard.readString(msg, MAX_TARGET_NAME_LENGTH)
	if not targetName or not NetworkGuard.canRead(msg, 4) then
		sendStoreError(player, "Target player not found.")
		return
	end

	targetName = trim(targetName)
	local amount = NetworkGuard.readU32(msg)
	if not amount then
		sendStoreError(player, "Invalid amount.")
		return
	end

	if targetName == "" or #targetName > MAX_TARGET_NAME_LENGTH then
		sendStoreError(player, "Target player not found.")
		return
	end

	if amount <= 0 then
		sendStoreError(player, "Invalid amount.")
		return
	end

	if targetName:lower() == player:getName():lower() then
		sendStoreError(player, "You cannot transfer coins to yourself.")
		return
	end

	local targetGuid = 0
	local targetAccountId = 0
	local storedTargetName = ""
	local targetCoins = 0
	local resultId = db.storeQuery("SELECT p.`id`, p.`account_id`, p.`name`, a.`tibia_coins` FROM `players` p JOIN `accounts` a ON a.`id` = p.`account_id` WHERE p.`name` = " .. db.escapeString(targetName) .. " LIMIT 1")
	if resultId ~= false then
		targetGuid = result.getDataInt(resultId, "id")
		targetAccountId = result.getDataInt(resultId, "account_id")
		storedTargetName = result.getDataString(resultId, "name")
		targetCoins = result.getDataInt(resultId, "tibia_coins")
		result.free(resultId)
	end

	if targetAccountId == 0 then
		sendStoreError(player, "Target player not found.")
		return
	end

	if targetAccountId == player:getAccountId() then
		sendStoreError(player, "You cannot transfer coins to your own account.")
		return
	end

	local accountId = player:getAccountId()
	local targetPlayer = Player(storedTargetName)

	-- One transaction for both legs. This used to be two absolute SETs built
	-- from balances read further up, which two simultaneous transfers could
	-- clobber, and which left the sender debited if the credit failed. There
	-- is no in-memory coin cache in the engine, so writing the accounts rows
	-- is immediately visible to an online recipient with no extra sync.
	local transferred, transferError = Coins.transfer(accountId, targetAccountId, amount, {
		from_name = player:getName(),
		to_name = storedTargetName,
		to_account = targetAccountId,
		channel = "game",
	}, player:getGuid())

	if not transferred then
		sendStoreError(player, transferError == "insufficient coins"
			and "Not enough Bp Coins."
			or "Transfer failed, please try again.")
		return
	end

	addStoreHistory(accountId, player:getGuid(), "Coin Transfer to " .. storedTargetName, -amount, 1, storedTargetName)
	addStoreHistory(targetAccountId, targetGuid, "Coin Transfer from " .. player:getName(), amount, 1, player:getName())

	sendStoreSuccess(player, 0, "You sent " .. amount .. " Bp Coins to " .. storedTargetName .. ".")
	sendStoreHistory(player)

	if targetPlayer and targetPlayer:isUsingOtcV8() then
		sendStoreCatalog(targetPlayer)
		sendStoreHistory(targetPlayer)
	end
end

transferHandler:register()

local storeSessionCleanup = CreatureEvent("StoreSessionCleanup")
function storeSessionCleanup.onLogout(player)
	local pid = player:getId()
	lastBuy[pid] = nil
	lastTransfer[pid] = nil
	return true
end

storeSessionCleanup:register()

local storeSessionInit = CreatureEvent("StoreSessionInit")
function storeSessionInit.onLogin(player)
	player:registerEvent("StoreSessionCleanup")
	return true
end

storeSessionInit:register()
