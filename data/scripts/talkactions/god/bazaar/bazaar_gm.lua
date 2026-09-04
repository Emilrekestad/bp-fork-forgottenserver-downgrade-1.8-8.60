-- Item Bazaar GM tooling.
--
-- Phase 1 of the Bazaar ships with no UI on purpose: everything below drives
-- the real C++ domain (src/item_bazaar.cpp) through the Game.bazaar* bindings,
-- so the economy can be exercised and audited before any client or website
-- code is layered on top. These are also the permanent support/investigation
-- commands -- see /bazaar help.
--
-- Nothing here re-implements a rule. Every command is a thin call into the
-- domain plus formatting; the wording players would see comes back from the
-- server so GM output and player output can never drift apart.

-- Account type required for the INVESTIGATION subcommands (settle, expire,
-- reconcile, player, ledger, audit, item). The player-facing actions
-- (sell/bid/buyout/cancel/relist/withdraw/list/auctions/config) are
-- deliberately open to everyone: they are the same operations the client UI
-- will expose in Phase 2, and every one of them is authorised server-side by
-- ItemBazaar itself (account ownership, seller-cannot-bid, escrow state), so
-- gating them here would only hide functionality that is already safe.
local ADMIN_ACCOUNT_TYPE = 6

local ADMIN_COMMANDS = {
	settle = true,
	expire = true,
	reconcile = true,
	backfill = true,
	player = true,
	ledger = true,
	audit = true,
	item = true,
}

-- Rarity tiers, mirroring data/lib/rarity/rarity_stats.lua (1..4 revealed,
-- 5 = Dormant). Shown by name rather than a raw number so GM output reads the
-- same as the loot channel and the client UI.
local TIER_NAMES = {
	[1] = "Scarce",
	[2] = "Adept",
	[3] = "Superior",
	[4] = "Prime",
	[5] = "Dormant",
}

local function tierName(tier)
	return TIER_NAMES[tier] or ("t" .. tostring(tier))
end

local STATUS_NAMES = {
	[1] = "ACTIVE",
	[2] = "SETTLING",
	[3] = "SETTLED",
	[4] = "EXPIRED",
	[5] = "CANCELLED",
}

local ITEM_STATE_NAMES = {
	[0] = "PENDING_ESCROW",
	[1] = "INVENTORY",
	[2] = "ESCROWED",
}

local LEDGER_NAMES = {
	[1] = "BID_ESCROW",
	[2] = "BID_RELEASE",
	[3] = "BUYOUT_ESCROW",
	[4] = "SELLER_PAYOUT",
	[5] = "SALE_FEE",
	[6] = "PROMOTION_FEE",
	[7] = "REFUND",
}

local function reply(player, text)
	player:sendTextMessage(MESSAGE_INFO_DESCR, text)
end

local function usage(player)
	reply(player, "[Bazaar] Commands:")
	reply(player, "  /bazaar config                      - show live configuration")
	reply(player, "  /bazaar sell <start>,<buyout>,<hrs>[,promote] - list the item in your right hand")
	reply(player, "  /bazaar list                        - your Bazaar Inventory")
	reply(player, "  /bazaar auctions                    - active auctions")
	reply(player, "  /bazaar <id>                        - full auction dump")
	reply(player, "  /bazaar bid <id>,<amount>           - bid as yourself")
	reply(player, "  /bazaar buyout <id>                 - buy out as yourself")
	reply(player, "  /bazaar cancel <id>                 - cancel your own auction")
	reply(player, "  /bazaar relist <itemId>,<start>,<buyout>,<hrs>")
	reply(player, "  /bazaar withdraw <itemId>,<charName>")
	reply(player, "  /bazaar settle <id>                 - force settlement now")
	reply(player, "  /bazaar expire <id>                 - rewind deadline to now")
	reply(player, "  /bazaar item <uid>                  - locate an item instance")
	reply(player, "  /bazaar player <name>               - account's Bazaar footprint")
	reply(player, "  /bazaar ledger [id]                 - ledger, optionally per auction")
	reply(player, "  /bazaar audit <id>                  - audit trail for an auction")
	reply(player, "  /bazaar reconcile                   - resolve stranded escrow rows")
end

-- Splits "a,b,c" into trimmed parts.
local function args(param)
	local parts = {}
	for piece in param:gmatch("[^,]+") do
		parts[#parts + 1] = piece:match("^%s*(.-)%s*$")
	end
	return parts
end

-- Pulls an optional trailing "promote" keyword off the argument string,
-- accepting it after either a comma or a space ("...,1,promote" and
-- "...,1 promote" both work). Returns the remaining text plus the flag.
local function extractPromote(rest)
	local lowered = rest:lower()
	if not lowered:find("promote", 1, true) then
		return rest, false
	end
	local cleaned = lowered:gsub("promote", ""):gsub(",%s*$", ""):gsub("%s+$", "")
	return cleaned, true
end

-- Strict numeric parse: returns nil for anything that is not a whole number,
-- so a malformed argument is reported instead of silently falling back to a
-- default (which is how a mistyped duration previously became 24h without
-- anyone noticing).
local function number(value)
	if not value then
		return nil
	end
	local trimmed = value:match("^%s*(.-)%s*$")
	if trimmed == "" or trimmed:match("%D") then
		return nil
	end
	return tonumber(trimmed)
end

local function describeAuction(player, auctionId)
	local auction = Game.bazaarGetAuction(auctionId)
	if not auction then
		reply(player, string.format("[Bazaar] Auction #%d does not exist.", auctionId))
		return
	end

	reply(player, string.format("[Bazaar] Auction #%d - %s (type %d, tier %d)", auction.id, auction.itemName,
		auction.itemType, auction.tier))
	reply(player, string.format("  status=%s  seller_account=%d  bazaar_item=%d  promoted=%s",
		STATUS_NAMES[auction.status] or auction.status, auction.sellerAccountId, auction.itemId,
		auction.promoted == 1 and "yes" or "no"))
	reply(player, string.format("  start=%d  buyout=%s  current_bid=%d  bidder_account=%s  bids=%d",
		auction.startPrice, auction.buyoutPrice > 0 and auction.buyoutPrice or "none", auction.currentBid,
		auction.currentBidderAccountId > 0 and auction.currentBidderAccountId or "none", auction.bidCount))
	reply(player, string.format("  min_next_bid=%d  ends_at=%s (%ds from now)", auction.minimumNextBid,
		os.date("%Y-%m-%d %H:%M:%S", auction.endsAt), auction.endsAt - os.time()))

	local bids = db.storeQuery(string.format(
		"SELECT `bidder_account_id`, `amount`, `created_at` FROM `bazaar_bids` WHERE `auction_id` = %d "
		.. "ORDER BY `id` DESC LIMIT 10", auctionId))
	if bids then
		reply(player, "  Recent bids (newest first):")
		repeat
			reply(player, string.format("    account %d  %d BPC  %s", result.getNumber(bids, "bidder_account_id"),
				result.getNumber(bids, "amount"), os.date("%H:%M:%S", result.getNumber(bids, "created_at"))))
		until not result.next(bids)
		result.free(bids)
	end
end

local function showLedger(player, auctionId)
	local query = auctionId
		and string.format("SELECT * FROM `bazaar_ledger` WHERE `auction_id` = %d ORDER BY `id` ASC LIMIT 40", auctionId)
		or "SELECT * FROM `bazaar_ledger` ORDER BY `id` DESC LIMIT 25"

	local rows = db.storeQuery(query)
	if not rows then
		reply(player, "[Bazaar] No ledger entries.")
		return
	end

	local net = 0
	reply(player, auctionId and string.format("[Bazaar] Ledger for auction #%d:", auctionId) or "[Bazaar] Recent ledger:")
	repeat
		local amount = result.getNumber(rows, "amount")
		net = net + amount
		reply(player, string.format("  #%d  %s  account=%s  %+d BPC  op=%s", result.getNumber(rows, "id"),
			LEDGER_NAMES[result.getNumber(rows, "type")] or result.getNumber(rows, "type"),
			result.getNumber(rows, "account_id"), amount, result.getString(rows, "operation_id")))
	until not result.next(rows)
	result.free(rows)

	-- For a settled auction this must come out at zero: every coin the buyer
	-- paid is accounted for as seller payout plus fee.
	reply(player, string.format("  Net across shown rows: %+d BPC %s", net,
		auctionId and (net == 0 and "(balanced)" or "(!! UNBALANCED !!)") or ""))
end

local talkaction = TalkAction("/bazaar")

function talkaction.onSay(player, words, param)
	param = param:match("^%s*(.-)%s*$")
	if param == "" or param == "help" then
		usage(player)
		return false
	end

	local command, rest = param:match("^(%S+)%s*(.*)$")
	command = command:lower()

	if ADMIN_COMMANDS[command] and player:getAccountType() < ADMIN_ACCOUNT_TYPE then
		reply(player, "[Bazaar] That subcommand is staff-only.")
		return false
	end

	if command == "config" then
		local config = Game.bazaarGetConfig()
		reply(player, string.format("[Bazaar] enabled=%s  world=%d  maxActive=%d", config.enabled == 1 and "yes" or "no",
			config.worldId, config.maxActiveAuctions))
		reply(player, string.format("  duration: min=%dh default=%dh max=%dh", config.minHours, config.defaultHours,
			config.maxHours))
		reply(player, string.format("  fees: sale=%d%% (min %d BPC)  promotion=%d BPC", config.saleFeePercent,
			config.minSaleFee, config.promotionFee))
		reply(player, string.format("  anti-snipe: within %ds -> reset to %ds", config.antiSnipeThreshold,
			config.antiSnipeReset))
		return false
	end

	if command == "sell" then
		local cleaned, promote = extractPromote(rest)
		local parts = args(cleaned)
		local item = player:getSlotItem(CONST_SLOT_RIGHT)
		if not item then
			reply(player, "[Bazaar] Hold the item in your right hand first.")
			return false
		end

		local startPrice, buyout, hours = number(parts[1]), number(parts[2] or "0"), number(parts[3])
		if not startPrice or not buyout or not hours then
			reply(player, "[Bazaar] Usage: /bazaar sell <start>,<buyout>,<hours>[,promote]")
			reply(player, "[Bazaar] Use 0 for buyout to list without one. Numbers only.")
			return false
		end

		local success, info = Game.bazaarCreateAuction(player, item:getItemUID(), startPrice, buyout, hours, promote,
			RarityClass.getItemClass(item:getId()))
		if success then
			reply(player, string.format("[Bazaar] Listed as auction #%d (%dh%s).", info, hours,
				promote and string.format(", promoted for %d BPC", Game.bazaarGetConfig().promotionFee) or ""))
		else
			reply(player, string.format("[Bazaar] Failed: %s", info))
		end
		return false
	end

	if command == "bid" then
		local parts = args(rest)
		local auctionId, amount = tonumber(parts[1]), tonumber(parts[2])
		if not auctionId or not amount then
			reply(player, "[Bazaar] Usage: /bazaar bid <id>,<amount>")
			return false
		end
		-- A fresh operation id each time: GM bids are manual, so they should
		-- never collide with the ledger's replay protection.
		local success, reason = Game.bazaarPlaceBid(player:getAccountId(), auctionId, amount,
			string.format("gm:%d:%d:%d", player:getAccountId(), auctionId, os.time()))
		reply(player, success and string.format("[Bazaar] Bid of %d BPC accepted.", amount)
			or string.format("[Bazaar] Rejected: %s", reason))
		return false
	end

	if command == "buyout" then
		local auctionId = tonumber(rest)
		if not auctionId then
			reply(player, "[Bazaar] Usage: /bazaar buyout <id>")
			return false
		end
		local success, reason = Game.bazaarBuyout(player:getAccountId(), auctionId,
			string.format("gm:buyout:%d:%d", auctionId, os.time()))
		reply(player, success and "[Bazaar] Buyout complete." or string.format("[Bazaar] Rejected: %s", reason))
		return false
	end

	if command == "cancel" then
		local auctionId = tonumber(rest)
		if not auctionId then
			reply(player, "[Bazaar] Usage: /bazaar cancel <id>")
			return false
		end
		local success, reason = Game.bazaarCancelAuction(player:getAccountId(), auctionId)
		reply(player, success and "[Bazaar] Auction cancelled." or string.format("[Bazaar] Rejected: %s", reason))
		return false
	end

	if command == "relist" then
		local cleaned, promote = extractPromote(rest)
		local parts = args(cleaned)
		local itemId, startPrice, buyout, hours =
			number(parts[1]), number(parts[2]), number(parts[3] or "0"), number(parts[4])
		if not itemId or not startPrice or not buyout or not hours then
			reply(player, "[Bazaar] Usage: /bazaar relist <bazaarItemId>,<start>,<buyout>,<hours>[,promote]")
			return false
		end

		local success, info = Game.bazaarRelistItem(player:getAccountId(), itemId, startPrice, buyout, hours, promote)
		reply(player, success and string.format("[Bazaar] Relisted as auction #%d.", info)
			or string.format("[Bazaar] Failed: %s", info))
		return false
	end

	if command == "withdraw" then
		local parts = args(rest)
		local bazaarItemId = tonumber(parts[1])
		local targetName = parts[2] or player:getName()
		if not bazaarItemId then
			reply(player, "[Bazaar] Usage: /bazaar withdraw <bazaarItemId>,<characterName>")
			return false
		end
		local row = db.storeQuery(string.format("SELECT `id` FROM `players` WHERE `name` = %s",
			db.escapeString(targetName)))
		if not row then
			reply(player, string.format("[Bazaar] No character named '%s'.", targetName))
			return false
		end
		local targetId = result.getNumber(row, "id")
		result.free(row)

		local success, reason = Game.bazaarWithdrawItem(player:getAccountId(), bazaarItemId, targetId)
		reply(player, success and string.format("[Bazaar] Delivered to %s's Depot Inbox.", targetName)
			or string.format("[Bazaar] Failed: %s", reason))
		return false
	end

	if command == "settle" then
		local auctionId = tonumber(rest)
		if not auctionId then
			reply(player, "[Bazaar] Usage: /bazaar settle <id>")
			return false
		end
		reply(player, Game.bazaarSettleAuction(auctionId) and "[Bazaar] Settlement pass completed."
			or "[Bazaar] Settlement FAILED - check server log.")
		return false
	end

	-- Testing aid: rewind an auction's deadline so the 60s settlement sweep
	-- picks it up immediately, instead of waiting out a real duration.
	if command == "expire" then
		local auctionId = tonumber(rest)
		if not auctionId then
			reply(player, "[Bazaar] Usage: /bazaar expire <id>")
			return false
		end
		db.query(string.format("UPDATE `bazaar_auctions` SET `ends_at` = %d WHERE `id` = %d AND `status` = 1",
			os.time() - 1, auctionId))
		reply(player, string.format("[Bazaar] Auction #%d deadline moved to the past; it will settle within 60s "
			.. "(or use /bazaar settle %d).", auctionId, auctionId))
		return false
	end

	-- One-off repair for rows escrowed before `item_description` existed
	-- (db_version 67). Rebuilds each item from its stored attributes blob just
	-- long enough to read the rarity description off it, then throws the
	-- temporary instance away. Safe to re-run: it only touches rows whose
	-- description is still NULL.
	if command == "backfill" then
		-- Covers every retro-fitted column: item_description (db 67), item_class
		-- (db 68) and item_category (db 69). A row needs repair if any is unset.
		local rows = db.storeQuery(
			"SELECT `id`, `itemtype`, `count`, `attributes` FROM `bazaar_items` "
			.. "WHERE `item_description` IS NULL OR `item_class` = 0 OR `item_category` = 0 LIMIT 500")
		if not rows then
			reply(player, "[Bazaar] Nothing to backfill.")
			return false
		end

		local pending = {}
		repeat
			pending[#pending + 1] = {
				id = result.getNumber(rows, "id"),
				itemtype = result.getNumber(rows, "itemtype"),
				count = math.max(1, result.getNumber(rows, "count")),
				attributes = result.getString(rows, "attributes"),
			}
		until not result.next(rows)
		result.free(rows)

		-- Counted per column, not just per row: an earlier run reported success
		-- while filling nothing but descriptions, because the summary only ever
		-- mentioned descriptions. Each column now reports its own total, and
		-- anything left unresolved is called out explicitly.
		local repaired, skipped = 0, 0
		local classSet, categorySet, categoryUnknown = 0, 0, 0
		for _, row in ipairs(pending) do
			local description = ""
			if row.attributes and row.attributes ~= "" then
				local temp = Game.createItem(row.itemtype, row.count)
				if temp and temp.unserializeAttributes and temp:unserializeAttributes(row.attributes) then
					description = temp:getSpecialDescription() or ""
				end
				if temp then
					temp:remove()
				end
			end

			-- Class is a pure function of the item type, so it can be recovered
			-- even when the blob carries no description at all.
			local itemClass = RarityClass.getItemClass(row.itemtype) or 0
			-- Same derivation new listings go through
			-- (ItemBazaar::getItemCategory), called through the engine rather
			-- than reimplemented here so the two cannot drift apart.
			local itemCategory = Game.bazaarGetItemCategory(row.itemtype) or 0

			-- Description is written even when empty, so a genuinely
			-- description-less item is not re-examined on every future run.
			db.query(string.format(
				"UPDATE `bazaar_items` SET `item_description` = %s, `item_class` = %d, "
				.. "`item_category` = %d WHERE `id` = %d",
				db.escapeString(description), itemClass, itemCategory, row.id))
			db.query(string.format(
				"UPDATE `bazaar_auctions` SET `item_description` = %s, `item_class` = %d, "
				.. "`item_category` = %d WHERE `item_id` = %d",
				db.escapeString(description), itemClass, itemCategory, row.id))

			if description ~= "" then
				repaired = repaired + 1
			else
				skipped = skipped + 1
			end
			if itemClass > 0 then
				classSet = classSet + 1
			end
			if itemCategory > 0 then
				categorySet = categorySet + 1
			else
				categoryUnknown = categoryUnknown + 1
			end
		end

		reply(player, string.format("[Bazaar] Backfill: %d rows -- %d described, %d without, %d classed, %d categorised.",
			#pending, repaired, skipped, classSet, categorySet))
		if categoryUnknown > 0 then
			-- Category comes from the ItemType's weaponType/slotPosition, so a
			-- zero here means the item is genuinely neither a weapon nor worn
			-- in a recognised slot -- worth knowing, since it will never match
			-- an item-type filter.
			reply(player, string.format("[Bazaar] %d item(s) fit no known category and stay unfiltered.", categoryUnknown))
		end
		return false
	end

	if command == "reconcile" then
		Game.bazaarReconcile()
		reply(player, "[Bazaar] Reconciliation pass completed.")
		return false
	end

	if command == "list" then
		local rows = db.storeQuery(string.format(
			"SELECT `id`, `item_uid`, `itemtype`, `tier`, `item_name`, `state` FROM `bazaar_items` "
			.. "WHERE `owner_account_id` = %d ORDER BY `id` DESC LIMIT 30", player:getAccountId()))
		if not rows then
			reply(player, "[Bazaar] Your Bazaar Inventory is empty.")
			return false
		end
		reply(player, "[Bazaar] Your Bazaar items:")
		repeat
			reply(player, string.format("  item #%d  %s %s  state=%s  uid=%s", result.getNumber(rows, "id"),
				tierName(result.getNumber(rows, "tier")), result.getString(rows, "item_name"),
				ITEM_STATE_NAMES[result.getNumber(rows, "state")] or result.getNumber(rows, "state"),
				result.getString(rows, "item_uid")))
		until not result.next(rows)
		result.free(rows)
		return false
	end

	if command == "auctions" then
		local rows = db.storeQuery(
			"SELECT `id`, `item_name`, `tier`, `start_price`, `current_bid`, `bid_count`, `ends_at` "
			.. "FROM `bazaar_auctions` WHERE `status` = 1 ORDER BY `ends_at` ASC LIMIT 25")
		if not rows then
			reply(player, "[Bazaar] No active auctions.")
			return false
		end
		reply(player, "[Bazaar] Active auctions (ending soonest):")
		repeat
			reply(player, string.format("  #%d  %s %s  bid=%d  start=%d  bids=%d  ends in %ds",
				result.getNumber(rows, "id"), tierName(result.getNumber(rows, "tier")), result.getString(rows, "item_name"),
				result.getNumber(rows, "current_bid"), result.getNumber(rows, "start_price"),
				result.getNumber(rows, "bid_count"), result.getNumber(rows, "ends_at") - os.time()))
		until not result.next(rows)
		result.free(rows)
		return false
	end

	if command == "item" then
		local uid = rest:match("%d+")
		if not uid then
			reply(player, "[Bazaar] Usage: /bazaar item <uid>")
			return false
		end
		local rows = db.storeQuery(string.format(
			"SELECT `id`, `owner_account_id`, `item_name`, `state`, `current_auction_id` FROM `bazaar_items` "
			.. "WHERE `item_uid` = %s", uid))
		if not rows then
			reply(player, string.format("[Bazaar] Instance %s is not held by the Bazaar.", uid))
			return false
		end
		reply(player, string.format("[Bazaar] Instance %s -> bazaar_item #%d (%s), owner account %d, state %s, auction %s",
			uid, result.getNumber(rows, "id"), result.getString(rows, "item_name"),
			result.getNumber(rows, "owner_account_id"),
			ITEM_STATE_NAMES[result.getNumber(rows, "state")] or result.getNumber(rows, "state"),
			result.getNumber(rows, "current_auction_id")))
		result.free(rows)
		return false
	end

	if command == "player" then
		local row = db.storeQuery(string.format("SELECT `account_id` FROM `players` WHERE `name` = %s",
			db.escapeString(rest)))
		if not row then
			reply(player, string.format("[Bazaar] No character named '%s'.", rest))
			return false
		end
		local accountId = result.getNumber(row, "account_id")
		result.free(row)

		local function count(query)
			local r = db.storeQuery(query)
			if not r then return 0 end
			local total = result.getNumber(r, "total")
			result.free(r)
			return total
		end

		reply(player, string.format("[Bazaar] Account %d (%s):", accountId, rest))
		reply(player, string.format("  active auctions: %d / %d", count(string.format(
			"SELECT COUNT(*) AS `total` FROM `bazaar_auctions` WHERE `seller_account_id` = %d AND `status` = 1",
			accountId)), Game.bazaarGetConfig().maxActiveAuctions))
		reply(player, string.format("  bazaar inventory: %d", count(string.format(
			"SELECT COUNT(*) AS `total` FROM `bazaar_items` WHERE `owner_account_id` = %d AND `state` = 1", accountId))))
		reply(player, string.format("  escrowed items: %d", count(string.format(
			"SELECT COUNT(*) AS `total` FROM `bazaar_items` WHERE `owner_account_id` = %d AND `state` = 2", accountId))))
		reply(player, string.format("  leading bids: %d", count(string.format(
			"SELECT COUNT(*) AS `total` FROM `bazaar_auctions` WHERE `current_bidder_account_id` = %d AND `status` = 1",
			accountId))))

		local ledger = db.storeQuery(string.format(
			"SELECT COALESCE(SUM(`amount`), 0) AS `total` FROM `bazaar_ledger` WHERE `account_id` = %d", accountId))
		if ledger then
			reply(player, string.format("  net Bazaar coin movement: %+d BPC", result.getNumber(ledger, "total")))
			result.free(ledger)
		end
		return false
	end

	if command == "ledger" then
		showLedger(player, tonumber(rest))
		return false
	end

	if command == "audit" then
		local auctionId = tonumber(rest)
		if not auctionId then
			reply(player, "[Bazaar] Usage: /bazaar audit <id>")
			return false
		end
		local rows = db.storeQuery(string.format(
			"SELECT `action`, `account_id`, `amount`, `message`, `created_at` FROM `bazaar_audit` "
			.. "WHERE `auction_id` = %d ORDER BY `id` ASC LIMIT 30", auctionId))
		if not rows then
			reply(player, string.format("[Bazaar] No audit entries for auction #%d.", auctionId))
			return false
		end
		reply(player, string.format("[Bazaar] Audit trail for auction #%d:", auctionId))
		repeat
			reply(player, string.format("  %s  %s  account=%s  %s",
				os.date("%H:%M:%S", result.getNumber(rows, "created_at")), result.getString(rows, "action"),
				result.getNumber(rows, "account_id"), result.getString(rows, "message")))
		until not result.next(rows)
		result.free(rows)
		return false
	end

	local auctionId = tonumber(command)
	if auctionId then
		describeAuction(player, auctionId)
		return false
	end

	usage(player)
	return false
end

talkaction:separator(" ")
-- No accountType()/access() gate here on purpose. Those checks
-- (talkaction.cpp) reject the command outright and let it fall through to
-- normal chat, which is what blocked non-staff characters from using the
-- Bazaar at all. Authorisation happens per-subcommand above and, for anything
-- that touches items or coins, inside ItemBazaar.
talkaction:register()
