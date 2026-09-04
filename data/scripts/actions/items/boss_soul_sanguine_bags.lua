-- Bag you Desire (34109) / Bag you Covet (43895): boss loot bags. Using one
-- consumes it and generates a random item from its own dedicated set - Desire
-- rolls Soul (Soul War), Covet rolls Sanguine (per owner spec 2026-08-26,
-- correcting an earlier "either pool, forced Prime" assumption) - with a
-- normal rarity roll across the full scarce->prime range, not forced. Only
-- the loot-list coloring for the bags themselves is fixed to Prime/light
-- red, in data/lib/core/container.lua.
local action = Action()

-- Real weapon/armor ids from the Soul set, verified against items.xml
-- (excludes 11679 "souleater trophy" and 47689 "souleater soul core" -
-- decorations/currency, not equippable gear).
local SOUL_ITEMS = {
	34082, 34083, 34084, 34085, 34086, 34087, 34088, 34089, 34090, 34091,
	34092, 34093, 34094, 34095, 34096, 34099, 50159, 50240, 50254, 32618,
}

-- Real weapon/armor ids from the Sanguine set, verified against items.xml.
local SANGUINE_ITEMS = {
	43864, 43866, 43868, 43870, 43872, 43874, 43876, 43877, 43879, 43881,
	43882, 43885, 43887, 50157,
}

local BAG_POOLS = {
	[34109] = SOUL_ITEMS,     -- bag you desire
	[43895] = SANGUINE_ITEMS, -- bag you covet
}

function action.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local pool = BAG_POOLS[item.itemid]
	if not pool then
		return false
	end
	local itemId = pool[math.random(#pool)]

	local newItem = Game.createItem(itemId, 1)
	if not newItem then
		return true
	end

	RarityStats.rollRarity(newItem, true) -- true = random tier, scarce..prime

	if player:addItemEx(newItem) ~= RETURNVALUE_NOERROR then
		newItem:remove()
		player:sendCancelMessage("You don't have enough room to open this.")
		return true
	end

	local itemType = ItemType(itemId)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You open the bag and find " .. itemType:getArticle() .. " " .. itemType:getName() .. ".")
	item:remove(1)
	return true
end

action:id(34109, 43895)
action:register()
