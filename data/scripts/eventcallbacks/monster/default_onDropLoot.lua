local CHANNEL_LOOT = 10

-- TALKTYPE_CHANNEL_W (native value 8, const.h) is never registered as a Lua
-- enum global in this engine (only _Y/_O/_R1 are, see luascript.cpp) -- the
-- underlying protocol value is fixed either way, so it's defined locally
-- here instead of requiring a C++ rebuild just to expose one more enum name.
local TALKTYPE_CHANNEL_W = 8

-- Always white -- per-item rarity coloring (Rare=blue, Epic=purple,
-- Legendary=orange) is handled inline within the message text itself now
-- (data/lib/core/container.lua's Container:getContentDescription, via the
-- client's native [color=NAME]...[/color] BBCode support), not by escalating
-- this whole line's talktype. Per owner spec 2026-08-25: only the specific
-- rarity item's name should be colored, everything else in the line
-- (currency, plain items) stays standard white.
local function sendLootMessage(player, text, talktype)
	player:sendChannelMessage("", text, talktype or TALKTYPE_CHANNEL_W, CHANNEL_LOOT)
end

local function formatHundredthsPercent(value)
	return string.format("%.2f", (tonumber(value) or 0) / 100):gsub("0+$", ""):gsub("%.$", "")
end

local function addLootRecipient(recipients, player)
	if player then
		recipients[#recipients + 1] = player
	end
end

local function getLootRecipients(player)
	local recipients = {}
	local party = player:getParty()
	if party then
		addLootRecipient(recipients, party:getLeader())
		for _, member in ipairs(party:getMembers()) do
			addLootRecipient(recipients, member)
		end
	else
		addLootRecipient(recipients, player)
	end
	return recipients
end

local function sendUngroupedLootMessage(player, corpse, monsterName, preyLootText, bountyLootText, useColorized, talktype)
	local recipients = getLootRecipients(player)
	if #recipients == 0 then
		return
	end

	local plainText = nil
	local colorizedText = nil
	local needColorized = false

	if useColorized then
		for _, recipient in ipairs(recipients) do
			if recipient.isUsingAstraClient and recipient:isUsingAstraClient() then
				needColorized = true
				break
			end
		end
	end

	local function buildText(colorized)
		return ("Loot of %s: %s%s%s."):format(
			monsterName, corpse:getContentDescription(colorized), preyLootText, bountyLootText)
	end

	for _, recipient in ipairs(recipients) do
		local wantsColorized = needColorized and recipient.isUsingAstraClient and recipient:isUsingAstraClient()
		if wantsColorized then
			colorizedText = colorizedText or buildText(true)
			sendLootMessage(recipient, colorizedText, talktype)
		else
			plainText = plainText or buildText(false)
			sendLootMessage(recipient, plainText, talktype)
		end
	end
end

-- Applies the player's drop bonus (equipped items) to the loot chance.
-- Returns true if the item should be added, false otherwise.
local function rollWithDropBonus(lootChance, player)
	local chance = lootChance
	local rateLoot = configManager.getNumber(configKeys.RATE_LOOT)
	if rateLoot > 0 then
		chance = chance * rateLoot
	end

	if player then
		local bonus = player:getDropBonus()
		if bonus > 0 then
			-- ex: bonus=15 → chance * 1.15
			chance = math.floor(chance * (1 + bonus / 100))
		end
	end
	-- Maximum TFS chance is MAX_LOOTCHANCE (100000)
	return math.random(1, 100000) <= chance
end

local function createGuaranteedLootItem(corpse, lootItem)
	local guaranteedItem = {}
	for key, value in pairs(lootItem) do
		guaranteedItem[key] = value
	end
	guaranteedItem.chance = 100000

	local item = corpse:createLootItem(guaranteedItem)
	if not item then
		print("[Warning] DropLoot:", "Could not add loot item to corpse.")
	end
end

local event = Event()
event.onDropLoot = function(self, corpse)
	if configManager.getNumber(configKeys.RATE_LOOT) == 0 then return end

	local player = Player(corpse:getCorpseOwner())
	local mType = self:getType()
	local mTypeRaceId = mType:raceId()

	local staminaOk = true
	if player and configManager.getBoolean(configKeys.STAMINA_SYSTEM) then
		staminaOk = player:getStamina() > 840
	end

	if not player or staminaOk then
		local monsterLoot = mType:getLoot()
		local rolls = 1

		local boostedCreature = Game.getBoostedCreature()
		if boostedCreature and boostedCreature:lower() == mType:getName():lower() then
			rolls = math.max(1, math.floor(configManager.getFloat(configKeys.BOOSTED_LOOT_MULTIPLIER)))
		end

		-- Boosted Boss loot bonus
		if CustomBosstiary and CustomBosstiary.isBoostedBoss then
			if CustomBosstiary.isBoostedBoss(mTypeRaceId) then
				local boostedBossLootBonus = CustomBosstiary.getBoostedBossLootBonus()
				rolls = math.max(1, math.floor(rolls * (1 + boostedBossLootBonus / 100)))
			end
		end

		for roll = 1, rolls do
			for i = 1, #monsterLoot do
				local lootItem = monsterLoot[i]

				-- Applies the drop bonus.
				if player and lootItem.chance and lootItem.chance < 100000 then
					if rollWithDropBonus(lootItem.chance, player) then
						createGuaranteedLootItem(corpse, lootItem)
					end
				else
					-- Items with a 100% chance or no defined chance.
					local item = corpse:createLootItem(lootItem)
					if not item then
						print("[Warning] DropLoot:", "Could not add loot item to corpse.")
					end
				end
			end
		end

		local preyLootBonus = 0
		if player and PreySystem then
			local bonusType, bonusValue = PreySystem.getBonus(player, self:getName())
			if bonusType == PreySystem.BONUS_LOOT then
				preyLootBonus = bonusValue or 0
				for i = 1, #monsterLoot do
					local lootItem = monsterLoot[i]
					local chance = lootItem.chance or 100000
					if math.random(1, 100) <= bonusValue and (chance >= 100000 or rollWithDropBonus(chance, player)) then
						createGuaranteedLootItem(corpse, lootItem)
					end
				end
			end
		end

		local bountyLootBonus = 0
		if player and TaskBoard and TaskBoard.getBountyTalismanBonus then
			bountyLootBonus = TaskBoard.getBountyTalismanBonus(player, mTypeRaceId, 2)
			if bountyLootBonus > 0 and math.random(1, 10000) <= bountyLootBonus then
				for i = 1, #monsterLoot do
					local lootItem = monsterLoot[i]
					local chance = lootItem.chance or 100000
					if chance >= 100000 or rollWithDropBonus(chance, player) then
						createGuaranteedLootItem(corpse, lootItem)
					end
				end
			end
		end

		if player then
			local lootGroupingEnabled = configManager.getBoolean(configKeys.LOOT_GROUPING_ENABLED)
			if not lootGroupingEnabled then
				local preyLootText = preyLootBonus > 0 and (" (Prey Improved Loot +%d%%)"):format(preyLootBonus) or ""
				local bountyLootText = bountyLootBonus > 0 and
					(" (Bounty More Loot +%s%%)"):format(formatHundredthsPercent(bountyLootBonus)) or ""
				local useColorized = configManager.getBoolean(configKeys.COLORIZED_LOOT_VALUE)
				local monsterName = mType:getNameDescription()
				local playerId = player:getId()
				-- Rarity (data/scripts/creaturescripts/rarity/rarity_loot_drop.lua)
				-- is a SEPARATE Event on the same Monster:onDropLoot hook at
				-- trigger index 50, running strictly after this whole index-0
				-- handler returns -- so sending the message inline here would
				-- build corpse:getContentDescription() (and its per-item
				-- rarity coloring) before any item's actually been rolled. A
				-- short addEvent delay pushes this to the next tick, by which
				-- time every onDropLoot handler for this corpse has already
				-- finished synchronously.
				addEvent(function()
					local recipient = Player(playerId)
					if not recipient then
						return
					end
					sendUngroupedLootMessage(recipient, corpse, monsterName, preyLootText, bountyLootText, useColorized)
				end, 50)
			end
		end
	else
		if not configManager.getBoolean(configKeys.LOOT_GROUPING_ENABLED) then
			local text = ("Loot of %s: nothing (due to low stamina)"):format(
				             mType:getNameDescription())
			local party = player:getParty()
			if party then
				party:broadcastPartyLoot(text)
			else
				sendLootMessage(player, text)
			end
		end
	end
end
event:register()
