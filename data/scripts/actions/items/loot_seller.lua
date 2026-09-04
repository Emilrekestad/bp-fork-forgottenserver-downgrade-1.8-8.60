-- Loot Seller (item 27446, "a loot seller") -- Store consumable, 100 charges.
-- Use it targeting a piece of loot equipment ("Use with...", the same
-- crosshair interaction as a rope or the Dormant Waker) and the item crumbles
-- to dust, paying half of what a shop would give you straight into your
-- character. One charge per sale; the dust is gone when the last one goes.
--
-- The rules -- what counts as equipment, where the price comes from, the
-- 1000 gold ceiling -- all live in lib/lootseller/loot_seller.lua so the
-- Store description, the item description and this script cannot drift apart.
-- Sold in the Store under Consumables (data/store/gamestore.xml, offer 4701),
-- delivered into the backpack rather than the store inbox so it is usable the
-- moment it is bought.

local lootSeller = Action()

function lootSeller.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local charges = item:getAttribute(ITEM_ATTRIBUTE_CHARGES) or 0
	if charges <= 0 then
		-- Should be unreachable: the last charge removes the item below.
		item:remove(1)
		player:sendTextMessage(MESSAGE_FAILURE, "This Loot Seller is spent.")
		return true
	end

	local payout, reason = LootSeller.evaluate(player, target)
	if not payout then
		-- No charge is spent on a refusal.
		player:sendTextMessage(MESSAGE_FAILURE, reason)
		return true
	end

	-- Read the name before the item is gone; getNameDescription is what the
	-- look text uses, so the message names the item the way the player saw it.
	local soldName = target:getNameDescription(target:getSubType(), true)

	target:remove()
	player:addMoney(payout)

	local position = player:getPosition()
	position:sendMagicEffect(CONST_ME_POFF)
	local playerId = player:getId()
	addEvent(function()
		local receiver = Player(playerId)
		if receiver then
			receiver:getPosition():sendMagicEffect(CONST_ME_YELLOW_RINGS)
		end
	end, 200)

	charges = charges - 1
	if charges <= 0 then
		item:remove(1)
	else
		item:setAttribute(ITEM_ATTRIBUTE_CHARGES, charges)
	end

	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format(
		"%s crumbles to dust and leaves %d gold behind. %s",
		soldName:gsub("^%l", string.upper), payout,
		charges > 0
			and string.format("%d charge%s left.", charges, charges ~= 1 and "s" or "")
			or "That was the last of the dust."))

	return true
end

lootSeller:id(LootSeller.ITEM_ID)
lootSeller:allowFarUse(true)
lootSeller:register()
