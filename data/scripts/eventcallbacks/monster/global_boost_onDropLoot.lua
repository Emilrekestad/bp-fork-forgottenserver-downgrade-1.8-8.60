-- Global Loot Boost.
--
-- Monster::dropLoot (src/monster.cpp:2995) calls the Lua onDropLoot callback
-- and does nothing else -- ALL loot generation lives in
-- eventcallbacks/monster/default_onDropLoot.lua. So an extra roll pass here
-- is the whole implementation; there is no engine-side loot table to nudge.
--
-- Trigger index 10 puts this after the default generator (index 0) and before
-- the rarity system (50). Order matters for the loot message: the default
-- handler defers its "Loot of X: ..." line by 50ms precisely so every other
-- onDropLoot handler has finished writing into the corpse first, which means
-- items added here are named in that message without any extra work.
--
-- Shape copied from the Prey improved-loot bonus in the default handler:
-- roll a percentage per loot entry, and on a hit re-roll that entry's own
-- drop chance. That keeps rare items rare -- the boost improves your odds of
-- a second attempt, it does not hand out guaranteed drops.

local BOOST_ID = GlobalBoosts.ID.LOOT

-- rollWithDropBonus and createGuaranteedLootItem are file-locals in
-- default_onDropLoot.lua, so the two are reproduced here rather than exported
-- -- editing that file to widen their scope would put a second reason to
-- touch it into every future loot change. Keep in step with it if the drop
-- bonus formula ever changes.
local function rollWithDropBonus(lootChance, player)
	local chance = lootChance
	local rateLoot = configManager.getNumber(configKeys.RATE_LOOT)
	if rateLoot > 0 then
		chance = chance * rateLoot
	end

	if player then
		local bonus = player:getDropBonus()
		if bonus > 0 then
			chance = math.floor(chance * (1 + bonus / 100))
		end
	end

	-- MAX_LOOTCHANCE
	return math.random(1, 100000) <= chance
end

local function createGuaranteedLootItem(corpse, lootItem)
	local guaranteedItem = {}
	for key, value in pairs(lootItem) do
		guaranteedItem[key] = value
	end
	guaranteedItem.chance = 100000
	corpse:createLootItem(guaranteedItem)
end

local event = Event()

function event.onDropLoot(monster, corpse)
	-- Boost plus the console's base loot knob, so a server run on "+25% loot"
	-- is a setting on the Balance view rather than a number in this file.
	local percent = GlobalBoosts.magnitude(BOOST_ID) + (Tuning and Tuning.percent("rate.loot") or 0)
	if percent <= 0 or not corpse then
		return
	end

	if configManager.getNumber(configKeys.RATE_LOOT) == 0 then
		return
	end

	local player = Player(corpse:getCorpseOwner())

	-- Same stamina gate the default generator applies. Without it the boost
	-- would quietly restore loot to characters the stamina system has
	-- deliberately cut off.
	if player and configManager.getBoolean(configKeys.STAMINA_SYSTEM) and player:getStamina() <= 840 then
		return
	end

	local mType = monster:getType()
	if not mType then
		return
	end

	for _, lootItem in ipairs(mType:getLoot()) do
		if math.random(1, 100) <= percent then
			local chance = lootItem.chance or 100000
			if chance >= 100000 or rollWithDropBonus(chance, player) then
				createGuaranteedLootItem(corpse, lootItem)
			end
		end
	end
end

event:register(10)
