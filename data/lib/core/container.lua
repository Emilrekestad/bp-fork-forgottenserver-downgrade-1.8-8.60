function Container:isContainer() return true end

function getLootRandom()
	return math.random(0, MAX_LOOTCHANCE) / configManager.getNumber(configKeys.RATE_LOOT)
end

function Container:createLootItem(lootItem)
	if self:getEmptySlots() == 0 then return true end

	local itemCount = 0
	local randvalue = getLootRandom()
	local itemType = ItemType(lootItem.itemId)
	local corpseInstanceId = self:getInstanceId()

	if randvalue < lootItem.chance then
		if itemType:isStackable() then
			local max = math.floor(randvalue % lootItem.maxCount) + 1
			local min = lootItem.minCount ~= 0 and math.floor(randvalue % lootItem.minCount) + 1 or max
			if min > max then min, max = max, min end
			itemCount = math.random(min, max)
		else
			itemCount = 1
		end
	end

	while itemCount > 0 do
		local count = math.min(itemType:getStackSize(), itemCount)

		local subType = count
		if itemType:isFluidContainer() then subType = math.max(0, lootItem.subType) end

		local tmpItem = Game.createItem(lootItem.itemId, subType)
		if not tmpItem then return false end
		
		if corpseInstanceId and corpseInstanceId ~= 0 then
			tmpItem:setInstanceId(corpseInstanceId)
		end

		local tmpContainer = tmpItem:getContainer()
		if tmpContainer then
			for i = 1, #lootItem.childLoot do
				if not tmpContainer:createLootItem(lootItem.childLoot[i]) then
					tmpContainer:remove()
					return false
				end
			end

			if #lootItem.childLoot > 0 and tmpContainer:getSize() == 0 then
				tmpItem:remove()
				return true
			end
		end

		if lootItem.subType ~= -1 then tmpItem:setAttribute(ITEM_ATTRIBUTE_CHARGES, lootItem.subType) end

		if lootItem.actionId ~= -1 then tmpItem:setActionId(lootItem.actionId) end

		if lootItem.text and lootItem.text ~= "" then tmpItem:setText(lootItem.text) end

		local ret = self:addItemEx(tmpItem)
		if ret ~= RETURNVALUE_NOERROR then tmpItem:remove() end

		itemCount = itemCount - count
	end
	return true
end

local function getLootItemValue(item)
	local itemType = item and ItemType(item:getId())
	if not itemType or itemType:getId() == 0 then
		return 0
	end

	local value = itemType.getDefaultPrice and itemType:getDefaultPrice() or itemType:getWorth()
	local count = itemType:isStackable() and math.max(1, item:getCount()) or 1
	return (tonumber(value) or 0) * count
end

-- Rarity items get their own display name colored in-line, everything else
-- in the same loot line stays whatever the message's base talktype is
-- (white). This rides a real client feature independent of Astra's
-- value-based {id:value|text} bracket format above: this fork's OTClient
-- console (modules/game_console/console.lua, getBBColorData/checkBBData)
-- parses a [color=NAME]text[/color] BBCode-style tag on ANY channel message
-- by default, matching named colors from its own hexColorStrings table
-- (blue/purple/yellow/orange all present) -- no client changes needed.
-- Per owner spec 2026-08-25: tiers renamed (Rare->Scarce, Epic->Adept,
-- Legendary->Superior) and Prime added as a new top tier above Superior.
--
-- Ladder recoloured 2026-09-07 to green/blue/purple/crimson -- the step order
-- players import from every major loot game. What it replaced (grey, lightblue,
-- lightgreen, lightred) got two things wrong on first contact: grey is the
-- universal "no rarity at all" colour, so the entry tier looked like vendor
-- trash, and blue sat BELOW green, inverting the one ordering nobody has to be
-- taught. Prime is crimson rather than gold because gold means money and
-- nothing else across this client (docs/client-ui-guide.md sec.4). Dormant is
-- not a rank on that ladder at all -- it is a STATE -- and it stays warm yellow
-- to match its in-world identity, the gold sparkle in src/client/uiitem.cpp and
-- item.cpp (owner call 2026-09-07). The sparkle is deliberately unchanged.
--
-- These are all literal hex now rather than names from the client's
-- hexColorStrings table: none of the named entries land on these values, and
-- the [color=...] tag accepts a name or a raw #RRGGBB interchangeably (the
-- "[#%w]+" class in getBBColorData's pattern, console.lua). Values are the
-- dark-ground half of the ladder -- the console is dark -- and are kept in
-- lockstep with TIER_COLOR in modules/game_bazaar/bazaar.lua and the corner
-- marker in src/client/uiitem.cpp.
local RARITY_COLOR = {
	-- Moss, not a true green: side by side, a straight green sat on top of the
	-- positive/gain green the client prints in the same rows. The yellow shift
	-- keeps it the green step of the ladder without reading as "a gain".
	scarce = "#9fb86a",
	adept = "#7cc3e4",
	superior = "#b98cf0",
	prime = "#f2554b",
	-- Dormant (owner spec 2026-08-30) is the prominent, common-case
	-- loot-channel color, since virtually every real rarity roll surfaces
	-- as Dormant first -- scarce/adept/superior/prime only show up here
	-- anymore via the GM /roll <tier> testing bypass. Warm yellow, matching
	-- the sparkle it wears in the world. It is NOT the old #f0c674 though:
	-- that was the money gold exactly, and rendered side by side the two were
	-- indistinguishable. Nudged orange far enough to separate from money while
	-- staying the same warm family as the sparkle (255,195,100).
	dormant = "#ffb347",
}

-- Bag you Desire (34109) / Bag you Covet (43895): boss loot, not equipment,
-- so they never go through RarityStats.rollRarity and never get an article
-- containing a tier name - always shown in Prime's color regardless, per
-- owner spec 2026-08-26.
local ALWAYS_PRIME_ITEM_IDS = {
	[34109] = true, -- bag you desire
	[43895] = true, -- bag you covet
}

local function wrapRarityColor(description, item)
	if ALWAYS_PRIME_ITEM_IDS[item:getId()] then
		return ("[color=%s]%s[/color]"):format(RARITY_COLOR.prime, description)
	end

	local article = item:getAttribute(ITEM_ATTRIBUTE_ARTICLE)
	if not article or article == "" then
		return description
	end

	-- Checked highest tier first since e.g. "superior" doesn't substring-
	-- match "prime" or vice versa, but keeping the same highest-wins order
	-- as the old rare/epic/legendary check for consistency. "dormant" never
	-- collides with any of the real tier names, so its position in this
	-- chain doesn't matter.
	local tier = (article:find("prime") and "prime")
		or (article:find("superior") and "superior")
		or (article:find("adept") and "adept")
		or (article:find("scarce") and "scarce")
		or (article:find("dormant") and "dormant")
		or nil
	if not tier then
		return description
	end

	return ("[color=%s]%s[/color]"):format(RARITY_COLOR[tier], description)
end

function Container:getContentDescription(colorizedLootValue)
	local items = self:getItems()
	if items and #items > 0 then
		local loot = {}
		for _, lootItem in ipairs(items) do
			local description = lootItem:getNameDescription(lootItem:getSubType(), true)
			if colorizedLootValue then
				-- Astra's own value-based coloring -- left untouched, [color]
				-- tags aren't mixed in here since Astra's bracket parser is a
				-- separate, not-fully-documented system on our end.
				description = ("{%d:%d|%s}"):format(lootItem:getId(), getLootItemValue(lootItem), description)
			else
				description = wrapRarityColor(description, lootItem)
			end
			loot[#loot + 1] = description
		end

		return table.concat(loot, ", ")
	end

	return "nothing"
end

function Container:getListOfContainerItems(container)
    if not container:isContainer() then
        return false
    end
    
    local containers, items = {}, {}
    table.insert(containers, container)
    while #containers > 0 do
        for i = 0, containers[1]:getSize() - 1 do  
            local item = containers[1]:getItem(i)
            table.insert(items, item)
            if item:isContainer() then
                table.insert(containers, item)
            end
        end
        table.remove(containers, 1)
    end
    
    return items
end
