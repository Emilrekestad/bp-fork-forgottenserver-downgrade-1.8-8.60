-- Item Bazaar notification pump.
--
-- The C++ domain (src/item_bazaar.cpp) never talks to the chat system. It
-- appends rows to `bazaar_events` and moves on, so settlement can never block
-- or fail because a player is offline, has the channel closed, or is mid-
-- login. This globalevent drains that outbox into the Item Bazaar channel.
--
-- Delivery rules:
--   * account_id IS NULL  -> public promotional announcement (paid 5 BPC
--     promotion). Broadcast to everyone with the channel open. Marked
--     delivered immediately -- a public shout is not worth retaining.
--   * account_id set      -> personal notification. Delivered to any online
--     character on that account. If nobody from the account is online it is
--     LEFT QUEUED and retried, so a player who was offline when their auction
--     sold still gets told when they next log in.
--
-- Personal events expire after EVENT_TTL_SECONDS so the queue cannot grow
-- without bound for an account that never returns.

local CHANNEL_ITEM_BAZAAR = 11

-- TALKTYPE_CHANNEL_W (native value 8) is not exposed as a Lua global in this
-- engine -- only _Y/_O/_R1 are (see luascript.cpp). Same workaround the loot
-- channel uses in data/scripts/eventcallbacks/monster/default_onDropLoot.lua.
local TALKTYPE_CHANNEL_W = 8

local POLL_INTERVAL_MS = 2000
local MAX_EVENTS_PER_TICK = 40
local EVENT_TTL_SECONDS = 7 * 24 * 60 * 60

-- Mirrors ItemBazaar::EVENT_* in src/item_bazaar.h.
local EVENT = {
	LISTING_CREATED = 1,
	LISTING_PROMOTED = 2,
	BID_ACCEPTED = 3,
	OUTBID = 4,
	AUCTION_WON = 5,
	AUCTION_SOLD = 6,
	BUYOUT_COMPLETE = 7,
	AUCTION_EXPIRED = 8,
	ITEM_RETURNED = 9,
	ITEM_WITHDRAWN = 10,
	AUCTION_CANCELLED = 11,
	BID_RECEIVED = 12,
}

-- Rarity tier -> display name and colour. Tiers mirror
-- data/lib/rarity/rarity_stats.lua (1..4 revealed, 5 = Dormant), and the
-- colours match the loot channel's RARITY_COLOR in data/lib/core/container.lua
-- so an item reads identically wherever a player sees it.
local TIER_NAME = {
	[1] = "Scarce",
	[2] = "Adept",
	[3] = "Superior",
	[4] = "Prime",
	[5] = "Dormant",
}

local TIER_COLOR = {
	[1] = "#9fb86a",
	[2] = "#7cc3e4",
	[3] = "#b98cf0",
	[4] = "#f2554b",
	[5] = "#ffb347",
}

local function comma(value)
	local formatted = tostring(math.floor(tonumber(value) or 0))
	while true do
		local replaced
		formatted, replaced = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return formatted
end

-- Builds the coloured item label. Never exposes anything beyond the tier and
-- the item name: a Dormant item is described only as "Dormant <name>", which
-- is all a Dormant item actually has -- its real stats are not rolled until a
-- Dormant Waker is used, so there is nothing hidden to leak here.
local function itemLabel(tier, name)
	local tierName = TIER_NAME[tier]
	if not tierName then
		return name
	end
	return string.format("[color=%s]%s %s[/color]", TIER_COLOR[tier] or "white", tierName, name)
end

-- Astra clients do not parse [color=...] BBCode (they use their own bracket
-- syntax); the loot channel branches the same way in
-- data/lib/core/container.lua.
local function labelFor(player, tier, name)
	if player.isUsingAstraClient and player:isUsingAstraClient() then
		local tierName = TIER_NAME[tier]
		return tierName and (tierName .. " " .. name) or name
	end
	return itemLabel(tier, name)
end

local function messageFor(player, eventType, payload, auction)
	local tier = auction and auction.tier or 0
	local name = payload ~= "" and payload or (auction and auction.itemName) or "an item"
	local label = labelFor(player, tier, name)
	local bid = auction and auction.currentBid or 0
	local finalPrice = auction and auction.finalPrice or bid

	if eventType == EVENT.BID_ACCEPTED then
		return string.format("Your bid of %s BPC on %s is now the highest bid.", comma(bid), label)
	elseif eventType == EVENT.BID_RECEIVED then
		-- Seller-facing. Deliberately says nothing about who bid: the Bazaar is
		-- anonymous in both directions.
		local suffix = ""
		if auction and auction.endsAt then
			local remaining = auction.endsAt - os.time()
			if remaining > 0 then
				suffix = string.format(" %s remaining.", remaining >= 3600
					and string.format("%dh %dm", remaining // 3600, (remaining % 3600) // 60)
					or string.format("%dm %ds", remaining // 60, remaining % 60))
			end
		end
		return string.format("Your %s auction received a bid of %s BPC.%s", label, comma(bid), suffix)
	elseif eventType == EVENT.OUTBID then
		return string.format("You have been outbid on %s. Current bid: %s BPC.", label, comma(bid))
	elseif eventType == EVENT.AUCTION_WON then
		return string.format("You won %s for %s BPC. The item is waiting in your Bazaar Inventory.", label,
			comma(finalPrice))
	elseif eventType == EVENT.BUYOUT_COMPLETE then
		return string.format("Buyout complete -- %s is yours for %s BPC. It is in your Bazaar Inventory.", label,
			comma(finalPrice))
	elseif eventType == EVENT.AUCTION_SOLD then
		local fee = auction and auction.fee or 0
		return string.format("Your %s sold for %s BPC. Bazaar fee: %s BPC. You received %s BPC.", label,
			comma(finalPrice), comma(fee), comma(finalPrice - fee))
	elseif eventType == EVENT.AUCTION_EXPIRED then
		return string.format("Your %s auction ended without a buyer. The item has returned to your Bazaar Inventory.",
			label)
	elseif eventType == EVENT.AUCTION_CANCELLED then
		return string.format("You cancelled the auction for %s. It is back in your Bazaar Inventory.", label)
	elseif eventType == EVENT.ITEM_WITHDRAWN then
		return string.format("%s has been delivered to your Depot Inbox.", label)
	elseif eventType == EVENT.ITEM_RETURNED then
		return string.format("%s has been returned to your Bazaar Inventory.", label)
	elseif eventType == EVENT.LISTING_CREATED then
		return string.format("%s is now listed on the Item Bazaar.", label)
	end
	return nil
end

-- Public promotion. Deliberately says nothing about who is selling.
local function promotionMessage(player, auction, payload)
	local name = payload ~= "" and payload or (auction and auction.itemName) or "An item"
	local label = labelFor(player, auction and auction.tier or 0, name)
	local text = string.format("%s has entered the Item Bazaar. Starting bid: %s BPC.", label,
		comma(auction and auction.startPrice or 0))
	if auction and auction.buyoutPrice and auction.buyoutPrice > 0 then
		text = text .. string.format(" Buyout: %s BPC.", comma(auction.buyoutPrice))
	end
	return text
end

local function send(player, text)
	player:sendChannelMessage("", text, TALKTYPE_CHANNEL_W, CHANNEL_ITEM_BAZAAR)
end

local pump = GlobalEvent("ItemBazaarEventPump")

function pump.onThink(interval)
	local rows = db.storeQuery(string.format(
		"SELECT `id`, COALESCE(`account_id`, 0) AS `account_id`, COALESCE(`auction_id`, 0) AS `auction_id`, "
		.. "`type`, `payload`, `created_at` FROM `bazaar_events` WHERE `delivered_at` IS NULL "
		.. "ORDER BY `id` ASC LIMIT %d", MAX_EVENTS_PER_TICK))
	if not rows then
		return true
	end

	local online = Game.getPlayers()
	local delivered, expired = {}, {}
	local now = os.time()

	repeat
		local eventId = result.getNumber(rows, "id")
		local accountId = result.getNumber(rows, "account_id")
		local auctionId = result.getNumber(rows, "auction_id")
		local eventType = result.getNumber(rows, "type")
		local payload = result.getString(rows, "payload")
		local createdAt = result.getNumber(rows, "created_at")

		local auction = auctionId > 0 and Game.bazaarGetAuction(auctionId) or nil

		if accountId == 0 then
			-- Public promotional announcement.
			if eventType == EVENT.LISTING_PROMOTED then
				for _, player in ipairs(online) do
					send(player, promotionMessage(player, auction, payload))
				end
			end
			delivered[#delivered + 1] = eventId
		else
			local reached = false
			for _, player in ipairs(online) do
				if player:getAccountId() == accountId then
					local text = messageFor(player, eventType, payload, auction)
					if text then
						send(player, text)
					end
					reached = true
				end
			end

			if reached then
				delivered[#delivered + 1] = eventId
			elseif now - createdAt > EVENT_TTL_SECONDS then
				-- Nobody from this account came back within the retention
				-- window; drop it rather than retrying forever.
				expired[#expired + 1] = eventId
			end
			-- Otherwise: leave queued so it is delivered on next login.
		end
	until not result.next(rows)
	result.free(rows)

	local function markDelivered(ids)
		if #ids > 0 then
			db.query(string.format("UPDATE `bazaar_events` SET `delivered_at` = %d WHERE `id` IN (%s)", now,
				table.concat(ids, ",")))
		end
	end

	markDelivered(delivered)
	markDelivered(expired)
	return true
end

pump:interval(POLL_INTERVAL_MS)
pump:register()
