-- Loot Chest system -- roll/grant logic. Mirrors data/lib/bao/bao_reward.lua's
-- weighted-tier-then-weighted-pool architecture (rollTier/pickOne), extended
-- with an independent-chance bundle grant for the guaranteed pool so a
-- single pool can bundle several always/sometimes items together.

LootChest = {}

-- forced=true on RarityStats.rollRarity guarantees a tier (uniformly among
-- Scarce/Adept/Superior/Prime) rather than the normal chance-of-nothing odds
-- -- every item a chest hands out should feel like part of the reward, not a
-- lottery on top of a lottery. It's a safe no-op on anything the rarity
-- system doesn't consider eligible (currency, potions, the diamond, etc.),
-- so this can be called unconditionally on every item this system grants.
local function grantItem(player, itemId, count)
	local item = player:addItem(itemId, count)
	if not item then
		local inbox = player:getInbox()
		item = inbox and inbox:addItem(itemId, count)
	end
	if not item then
		return false
	end
	RarityStats.rollRarity(item, true)
	return true
end

local function rollCount(entry)
	if entry.countMin and entry.countMax then
		return math.random(entry.countMin, entry.countMax)
	end
	return entry.count or 1
end

-- Independent-chance bundle: every item in the pool rolls its own `chance`
-- (default 100) and is granted if it hits. Returns the list of {itemId,
-- count} actually granted, for the summary message.
local function grantBundle(player, pool)
	local granted = {}
	if not pool or not pool.items then
		return granted
	end
	for _, entry in ipairs(pool.items) do
		local chance = entry.chance or 100
		if math.random(1, 100) <= chance then
			local count = rollCount(entry)
			if grantItem(player, entry.itemId, count) then
				table.insert(granted, { itemId = entry.itemId, count = count })
			end
		end
	end
	return granted
end

-- Weighted single pick among a pool's items (bao_reward.lua's pickPoolItem).
local function pickOne(pool)
	if not pool or not pool.items or #pool.items == 0 then
		return nil
	end
	local totalWeight = 0
	for _, entry in ipairs(pool.items) do
		totalWeight = totalWeight + (entry.weight or 1)
	end
	local roll = math.random(1, totalWeight)
	local cumulative = 0
	for _, entry in ipairs(pool.items) do
		cumulative = cumulative + (entry.weight or 1)
		if roll <= cumulative then
			return entry
		end
	end
	return pool.items[#pool.items]
end

-- Weighted tier pick (bao_reward.lua's rollTier).
local function rollTier(rollTable)
	local totalWeight = 0
	for _, entry in ipairs(rollTable) do
		totalWeight = totalWeight + entry.weight
	end
	if totalWeight <= 0 then
		return nil
	end
	local roll = math.random(1, totalWeight)
	local cumulative = 0
	for _, entry in ipairs(rollTable) do
		cumulative = cumulative + entry.weight
		if roll <= cumulative then
			return entry
		end
	end
	return rollTable[#rollTable]
end

local function rollRareBonus(rareTable)
	if not rareTable then
		return nil
	end
	local picked = rollTier(rareTable)
	if not picked or not picked.pool then
		return nil
	end
	local pool = LootChestConfig.Pools[picked.pool]
	local itemEntry = pickOne(pool)
	if not itemEntry then
		return nil
	end
	return { tier = picked.tier, itemId = itemEntry.itemId, count = itemEntry.count or 1 }
end

local function announce(player, bundleGranted, rareReward)
	for _, granted in ipairs(bundleGranted) do
		local itemName = ItemType(granted.itemId):getName()
		player:sendTextMessage(MESSAGE_LOOT, string.format("You received %dx %s.", granted.count, itemName))
	end
	if rareReward then
		local itemName = ItemType(rareReward.itemId):getName()
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("A glint catches your eye -- you found %s!", itemName))
		player:getPosition():sendMagicEffect(CONST_ME_HOLYAREA)
	end
end

-- Cooldown check/set, kv-store based (same convention as
-- data/lib/rarity/rarity_rebirth.lua's rebirth_cooldown_until). Scoped per
-- chest table name so different chest tables track their own cooldowns
-- independently even for the same player.
local function cooldownKey(tableName)
	return "lootchest_" .. tableName .. "_cooldown_until"
end

local function cooldownRemaining(player, tableName, cooldownSeconds)
	if not cooldownSeconds or cooldownSeconds <= 0 then
		return 0
	end
	local cooldownUntil = player:kv():scoped("lootchest"):get(cooldownKey(tableName)) or 0
	return math.max(0, cooldownUntil - os.time())
end

local function setCooldown(player, tableName, cooldownSeconds)
	if not cooldownSeconds or cooldownSeconds <= 0 then
		return
	end
	player:kv():scoped("lootchest"):set(cooldownKey(tableName), os.time() + cooldownSeconds)
end

-- Opens a named loot table for a player: checks cooldown, grants the
-- guaranteed bundle, rolls the rare bonus on top, announces both, and starts
-- the cooldown. Returns true on success, false (with no side effects) if the
-- chest is still on cooldown for this player.
function LootChest.open(player, tableName)
	local tableConfig = LootChestConfig.Tables[tableName]
	if not tableConfig then
		print(string.format("[LootChest] WARNING: LootChest.open called for unknown table '%s'", tostring(tableName)))
		return false
	end

	local remaining = cooldownRemaining(player, tableName, tableConfig.cooldownSeconds)
	if remaining > 0 then
		local hours = math.ceil(remaining / 3600)
		player:sendTextMessage(MESSAGE_FAILURE, string.format("This chest is empty. Check back in about %d hour%s.", hours, hours == 1 and "" or "s"))
		return false
	end

	local pool = LootChestConfig.Pools[tableConfig.guaranteedPool]
	local bundleGranted = grantBundle(player, pool)
	local rareReward = rollRareBonus(tableConfig.rareTable)

	announce(player, bundleGranted, rareReward)
	setCooldown(player, tableName, tableConfig.cooldownSeconds)
	return true
end
