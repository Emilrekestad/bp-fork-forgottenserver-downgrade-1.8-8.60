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
-- Colors (also revised twice same day): Scarce=grey, Adept=lightblue,
-- Superior=lightgreen, Prime=lightred. "grey" isn't one of the client's
-- named hexColorStrings (checked -- only light/dark variants of green/teal/
-- red/purple/orange/yellow/blue exist there), so it's a literal hex code --
-- the [color=...] tag accepts either a name from that table or a raw
-- #RRGGBB directly, confirmed in getBBColorData's regex.
local RARITY_COLOR = {
	scarce = "#AAAAAA",
	adept = "lightblue",
	superior = "lightgreen",
	prime = "lightred",
	-- Dormant (owner spec 2026-08-30): now the prominent, common-case
	-- loot-channel color, since virtually every real rarity roll surfaces
	-- as Dormant first -- scarce/adept/superior/prime only show up here
	-- anymore via the GM /roll <tier> testing bypass. Orange, matching the
	-- client's Dormant sparkle color exactly (src/client/uiitem.cpp /
	-- item.cpp).
	dormant = "orange",
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
