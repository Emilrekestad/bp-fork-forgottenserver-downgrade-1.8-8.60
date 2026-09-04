-- Item Rarity system — rolls rarity on monster loot as it drops, server-wide
-- across all qualifying items (per design decision). Uses this fork's real
-- Monster:onDropLoot event callback (data/events/scripts/monster.lua,
-- backed by Events::eventMonsterOnDropLoot in src/events.cpp) rather than
-- inventing a new loot-creation hook. RarityStats.rollRarity already
-- recurses into containers on its own, so a single call on the corpse
-- handles every item inside it.
--
-- Also home to Fortune (stats[43]) and Adrenaline Rush (stats[46]) --
-- neither is a "roll rarity onto an item" mechanic, but both trigger off
-- the exact same kill moment this file already hooks, so they live here
-- rather than a separate file.
--
-- CONST_ME_LOOT_HIGHLIGHT: a real, native, one-shot magic effect (not a
-- persistent per-tile marker -- unrelated to the corpse's own decay-stage
-- sprite shimmer, which is baked into the item's client sprite and has
-- nothing to do with rarity). Fired once, at drop, only when rollRarity
-- actually landed something (its return value is the rare count across
-- the whole recursive roll) -- a plain kill with no rarity roll stays
-- silent.
--
-- (!) CRITICAL: register() MUST use a triggerIndex later than the default
-- (0) loot-creation handler (data/scripts/eventcallbacks/monster/
-- default_onDropLoot.lua), which is what actually populates the corpse --
-- Monster::dropLoot (src/monster.cpp) does zero native loot population
-- itself, it just fires this same Lua event on an EMPTY corpse. This
-- fork's script loader (src/script.cpp) sorts all of data/scripts/
-- alphabetically before loading, and "creaturescripts/rarity/..." sorts
-- before "eventcallbacks/monster/...", so registering at the default index
-- (as this file originally did) meant rollRarity() ran on an empty corpse
-- every single kill -- a silent no-op, since the "if h > 0" recursion
-- guard in rollRarity() never had anything to recurse into. Found via code
-- audit after the owner asked how rarity loot actually reaches players;
-- every roll verified this session went through the GM /roll command,
-- which rolls directly on an existing ground item and never touches this
-- file at all, so the bug had no chance to surface until now.
--
-- data/scripts/network/party_analyzer/partytracker.lua and
-- data/scripts/network/hunt_analyzer/huntanalyzer.lua both already hit this
-- exact trap and fixed it by registering at index 100 (they need to read
-- the corpse's final contents to report loot value/hunt stats). This
-- registers earlier than both (50) so rarity is rolled before anything
-- else reads/reports the corpse's contents -- loot creation (0) -> rarity
-- roll/Fortune/Adrenaline Rush (50) -> hunt/party reporting (100).

-- Fortune (stats[43]): ring/necklace only. Scales up gold-type currency in
-- the corpse. gold/platinum/crystal coin ids and their real Tibia
-- gold-equivalent conversion rates.
local CURRENCY_GOLD_VALUE = {
	[3031] = 1,     -- gold coin
	[3035] = 100,   -- platinum coin
	[3043] = 10000, -- crystal coin
}
local CURRENCY_STACK_CAP = 100 -- native stackable cap for gold coin

local function applyFortune(corpse, player)
	local fortunePercent = 0
	for _, slot in ipairs({CONST_SLOT_NECKLACE, CONST_SLOT_RING}) do
		local item = player:getSlotItem(slot)
		if item then
			local desc = item:getSpecialDescription()
			local percent = desc and tonumber(string.match(desc, "Fortune: %+(%d+)%%"))
			if percent then
				fortunePercent = fortunePercent + percent
			end
		end
	end
	if fortunePercent <= 0 then
		return
	end

	local totalGoldValue = 0
	local count = corpse:getItemHoldingCount()
	for i = 0, count - 1 do
		local item = corpse:getItem(i)
		if item then
			local goldValue = CURRENCY_GOLD_VALUE[item:getId()]
			if goldValue then
				totalGoldValue = totalGoldValue + (goldValue * item:getCount())
			end
		end
	end
	if totalGoldValue <= 0 then
		return
	end

	local bonusValue = math.floor(totalGoldValue * fortunePercent / 100)
	if bonusValue <= 0 then
		return
	end

	-- Denominate the bonus as crystal/platinum/gold (largest first) instead
	-- of always paying out in pure gold coins. A big Fortune roll on a big
	-- platinum drop was producing a loot line of a dozen-plus repeated
	-- "100 gold coins" entries (confirmed live, 2026-08-26) - same total
	-- value, minimal stacks, matches how the game already denominates large
	-- payouts everywhere else (NPC sells, quest rewards, etc.).
	local function addCurrency(itemId, count)
		while count > 0 do
			local chunk = math.min(count, CURRENCY_STACK_CAP)
			corpse:addItem(itemId, chunk)
			count = count - chunk
		end
	end

	local crystalCount = math.floor(bonusValue / 10000)
	local platinumCount = math.floor((bonusValue % 10000) / 100)
	local goldCount = bonusValue % 100

	addCurrency(3043, crystalCount)
	addCurrency(3035, platinumCount)
	addCurrency(3031, goldCount)
end

-- Adrenaline Rush (stats[46]): boots only, Class 3+, all vocations. Fires a
-- temporary speed boost (real Condition, self-expiring) plus registers a
-- damage-boost window in RarityAdrenaline.active (data/lib/rarity/
-- rarity_adrenaline.lua), read by statChange's attacker-side block in
-- rarity_combat.lua on the killer's next hits.
local function applyAdrenalineRush(player)
	local boots = player:getSlotItem(CONST_SLOT_FEET)
	if not boots then
		return
	end

	local desc = boots:getSpecialDescription()
	local percent = desc and tonumber(string.match(desc, "Adrenaline Rush: %+(%d+)%%"))
	if not percent then
		return
	end

	-- CONDITION_PARAM_SPEED takes an absolute speed-points delta, not a
	-- percent -- confirmed against rarity_combat.lua's existing Ice Damage
	-- paralyze effect (setConditionParam(condition, CONDITION_PARAM_SPEED,
	-- -300)), a magnitude that only makes sense as raw speed points.
	-- Converted from the rolled % against the player's current speed at
	-- trigger time.
	local speedBoost = math.floor(player:getSpeed() * percent / 100)
	local speedCondition = Condition(CONDITION_ATTRIBUTES)
	speedCondition:setParameter(CONDITION_PARAM_SUBID, 1) -- distinct subid so re-killing refreshes rather than stacks
	speedCondition:setParameter(CONDITION_PARAM_TICKS, RarityAdrenaline.DURATION_SECONDS * 1000)
	speedCondition:setParameter(CONDITION_PARAM_SPEED, speedBoost)
	player:addCondition(speedCondition)

	RarityAdrenaline.active[player:getId()] = {
		expiry = os.time() + RarityAdrenaline.DURATION_SECONDS,
		percent = percent,
	}

	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_RED)
end

local rarityLootDrop = Event()

function rarityLootDrop.onDropLoot(monster, corpse)
	if not corpse or not corpse:isContainer() then
		return
	end
	-- Hybrid system (owner spec 2026-08-30): boss kills go through Dormant
	-- (the "hype" reveal-later flow, matching chests/soul bags), normal
	-- monster loot reveals instantly with the classic Scarce/Adept/Superior/
	-- Prime tier text -- e.g. a Hellspawn can drop "Superior Knight Legs"
	-- outright, but Ferumbras drops "Dormant Velvet Mantle". isRewardBoss()
	-- (real Tibia's separate Reward Chest boss flag) counts as a boss here
	-- too, matching the isBoss()-or-isRewardBoss() check already used
	-- elsewhere in this codebase (e.g. data/scripts/globalevents/
	-- influenced_spawn.lua).
	local monsterType = monster:getType()
	local isBossKill = monsterType and (monsterType:isBoss() or monsterType:isRewardBoss())
	local rareCount = RarityStats.rollRarity(corpse, false, not isBossKill)
	if rareCount > 0 then
		corpse:getPosition():sendMagicEffect(CONST_ME_LOOT_HIGHLIGHT)
	end

	local killer = Player(corpse:getCorpseOwner())
	if killer then
		applyFortune(corpse, killer)
		applyAdrenalineRush(killer)
	end
end

rarityLootDrop:register(50)
