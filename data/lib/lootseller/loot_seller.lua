-- Loot Seller (item 27446) -- a Store consumable that turns a piece of loot
-- equipment into gold on the spot, at half of what a shop would pay, without
-- the walk back to town.
--
-- Item 27446 was "gold dust": present in items.xml, absent from every loot
-- table, NPC shop, script and from world.otbm, so it was free to rename
-- rather than grow items.otb by an entry. Its OTB flags already carry
-- FLAG_USEABLE and its client ThingType already carries ThingAttrMultiUse --
-- in the SHIPPED client too, not just otclient-src -- which is what makes
-- "Use with..." work. The Dormant Waker (item 39241) needed both of those
-- patched in by hand; this one needed neither, so no client update ships
-- with this feature.
--
-- This file owns the rules. The Action (data/scripts/actions/items/
-- loot_seller.lua) only wires them to a use.

LootSeller = LootSeller or {}

LootSeller.ITEM_ID = 27446

-- Charges per purchased Loot Seller.
LootSeller.CHARGES = 100

-- Fraction of the shop price the player is paid. 0.5 => a brass armor a shop
-- buys for 150 pays 75.
LootSeller.PAYOUT_RATE = 0.5

-- Hard ceiling on the SHOP price of an eligible item, not on the payout: an
-- item a shop would pay more than this for is worth the trip to town, and
-- letting rares be dusted for half price would be a permanent, silent way to
-- destroy value. At 1000 the largest possible payout is 500 gold.
--
-- Rarity-rolled and Dormant items (lib/rarity) are NOT exempt -- owner call,
-- 2026-09-04: anything whose base type stays under this cap is low-tier
-- enough that the roll is not worth protecting. They pay out on the base
-- type like everything else, since a rolled item has no separate shop price.
LootSeller.MAX_ITEM_VALUE = 1000

-- Slots that make something "equipment" for this tool.
--
-- Note this items.xml barely uses slotType (224 items out of ~55k). The slot
-- an item really occupies comes from its moveevent sub-attribute --
--     <attribute key="script" value="moveevent">
--         <attribute key="slot" value="armor" />
-- -- which Items::parseScriptAttribute ASSIGNS straight into
-- ItemType::slotPosition for the equip event (src/items.cpp:2355), replacing
-- the default rather than OR-ing into it. So getSlotPosition() is accurate at
-- runtime for armor, helmets, legs, boots, amulets and rings even though the
-- XML never says "slotType".
--
-- SLOTP_LEFT/RIGHT are deliberately absent from the mask: slotPosition
-- DEFAULTS to SLOTP_HAND for every item (src/items.h), so testing the hand
-- bits would classify gold coins and mana potions as equipment. Weapons and
-- shields carry slot="hand"/"shield" (also just the hand bits) and are caught
-- by their weaponType instead, which is only ever set on real weapons.
local EQUIPMENT_SLOTS = SLOTP_HEAD | SLOTP_NECKLACE | SLOTP_ARMOR |
	SLOTP_LEGS | SLOTP_FEET | SLOTP_RING | SLOTP_AMMO | SLOTP_TWO_HAND

-- What a shop would pay the player for one of these. NPC shop parameters and
-- Lua shop lists both funnel into ItemType::sellPrice (merged by max, see
-- npc/lib/npcsystem/modules.lua registerItemShopPrice) and into
-- ItemPriceRegistry; both are read so an NPC that registered through only one
-- of the two paths still counts. Deliberately NOT getDefaultPrice(), which
-- falls back to buyPrice/worth -- an item no NPC buys has no shop price, and
-- must not be dusted for a share of what an NPC would CHARGE for it.
function LootSeller.getShopPrice(itemId)
	itemId = tonumber(itemId) or 0
	if itemId <= 0 then
		return 0
	end

	local itemType = ItemType(itemId)
	local price = (itemType and itemType:getId() ~= 0 and itemType:getSellPrice()) or 0

	if ItemPriceRegistry and ItemPriceRegistry.getDefaultSellPrice then
		price = math.max(price, ItemPriceRegistry.getDefaultSellPrice(itemId) or 0)
	end

	return price
end

function LootSeller.getPayout(itemId)
	local price = LootSeller.getShopPrice(itemId)
	if price <= 0 or price > LootSeller.MAX_ITEM_VALUE then
		return 0
	end
	-- Floor, so a 1 gold item pays 0 and is rejected below rather than
	-- rounding itself up into free money.
	return math.floor(price * LootSeller.PAYOUT_RATE)
end

-- Returns payout, or nil plus the reason the item cannot be dusted. Every
-- rejection ends up in front of the player, so each reason says which rule
-- was hit rather than one catch-all string.
function LootSeller.evaluate(player, item)
	if not item or not item:isItem() then
		return nil, "Use the Loot Seller on a piece of equipment you are carrying."
	end

	if item:getId() == LootSeller.ITEM_ID then
		return nil, "The dust has no interest in itself."
	end

	-- Must be on the player: no dusting loot lying on the floor, and none of
	-- someone else's.
	if item:getTopParent() ~= player then
		return nil, "You need to be carrying that item to sell it."
	end

	-- Equipped gear is excluded outright. Everything else here is a judgement
	-- about value; this one is about a misclick costing someone the armor
	-- they are standing in.
	if item:getParent() == player then
		return nil, "Take it off first. The Loot Seller only takes items out of your bags."
	end

	local itemType = ItemType(item:getId())
	if not itemType or itemType:getId() == 0 then
		return nil, LootSeller.requirementsText()
	end

	if itemType:isContainer() then
		return nil, "Containers cannot be sold this way -- empty it and sell what was inside."
	end

	local isEquipment = (itemType:getSlotPosition() & EQUIPMENT_SLOTS) ~= 0 or
		itemType:getWeaponType() ~= WEAPON_NONE
	if not isEquipment then
		return nil, LootSeller.requirementsText()
	end

	-- Stackables (arrows, bolts, throwing weapons) are excluded: a use would
	-- either destroy a whole stack for one item's price or need a split, and
	-- neither is what someone clearing a backpack after a hunt expects.
	if itemType:isStackable() then
		return nil, LootSeller.requirementsText()
	end

	local price = LootSeller.getShopPrice(item:getId())
	if price <= 0 then
		return nil, LootSeller.requirementsText()
	end

	if price > LootSeller.MAX_ITEM_VALUE then
		return nil, string.format(
			"That is worth %d gold to a shop, over the Loot Seller's %d gold limit. Sell it properly.",
			price, LootSeller.MAX_ITEM_VALUE)
	end

	local payout = LootSeller.getPayout(item:getId())
	if payout <= 0 then
		return nil, LootSeller.requirementsText()
	end

	return payout
end

function LootSeller.requirementsText()
	return string.format(
		"That item does not fit the Loot Seller's requirements. It takes equipment a shop would buy -- armor, helmets, legs, boots, shields, weapons, amulets and rings -- worth up to %d gold, and pays %d%% of the shop price.",
		LootSeller.MAX_ITEM_VALUE, math.floor(LootSeller.PAYOUT_RATE * 100))
end
