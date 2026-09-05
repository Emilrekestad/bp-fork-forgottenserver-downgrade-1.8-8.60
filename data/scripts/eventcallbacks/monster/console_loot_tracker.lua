-- Admin console: an exact ledger of what the server put in each corpse.
--
-- (!) TRIGGER INDEX 60 IS LOAD-BEARING. The onDropLoot callbacks run in
-- ascending index order and each writes into the same corpse:
--
--   0  default_onDropLoot.lua     -- the loot table itself
--   10 global_boost_onDropLoot.lua -- the global loot boost's extra pass
--   50 rarity_loot_drop.lua        -- rolls rarity onto what is already there
--   60 this file                   -- reads the finished corpse
--
-- Registering any earlier would count a corpse before the boost and rarity
-- passes had added to it, which is precisely the loot most worth measuring.
--
-- Reading here is also what makes the count exact rather than approximate:
-- Creature::dropCorpse calls dropLoot() and only afterwards hands the corpse
-- to autoloot and quick loot (src/creature.cpp), so nothing has removed an
-- item yet. What is in the container now is what the server generated.
--
-- Structurally invisible: reward bosses. Monster::dropLoot gives them a reward
-- container and never calls onDropLoot at all, so no handler at any index can
-- see their loot. The console reports them as unmeasured rather than as zero.

-- The rarity system stamps its tier into the item's ARTICLE
-- (data/lib/rarity/rarity_stats.lua), so "a superior knight legs". Matching
-- the tier words is how a rare drop is recognised without reaching into that
-- system's internals.
local RARITY_WORDS = {"scarce", "adept", "superior", "prime", "dormant"}

local function isRare(item)
	local article = item:getAttribute(ITEM_ATTRIBUTE_ARTICLE)
	if not article or article == "" then
		return false
	end
	article = tostring(article):lower()
	for _, word in ipairs(RARITY_WORDS) do
		if article:find(word, 1, true) then
			return true
		end
	end
	return false
end

--- Was this corpse rolled under conditions comparable to the configured
--- chance, or did something give it extra passes?
---
--- Deliberately conservative: anything that *could* have added a pass makes
--- the corpse non-plain, even where the extra pass is itself a random proc
--- (prey and bounty both roll again before granting). Being conservative
--- shrinks the comparable sample; guessing the other way would quietly
--- inflate every observed rate.
local function corpseState(monster, mType, player)
	if configManager.getNumber(configKeys.RATE_LOOT) == 0 then
		return "blocked"
	end

	-- Stamina at or below 840 means the generator rolls nothing at all. Those
	-- corpses are empty for a reason unrelated to drop chance, and counting
	-- them would depress every rate on the server.
	if player and configManager.getBoolean(configKeys.STAMINA_SYSTEM) and player:getStamina() <= 840 then
		return "blocked"
	end

	if GlobalBoosts and GlobalBoosts.magnitude and GlobalBoosts.ID and GlobalBoosts.ID.LOOT then
		if (GlobalBoosts.magnitude(GlobalBoosts.ID.LOOT) or 0) > 0 then
			return "boosted"
		end
	end

	local name = mType and mType:getName() or monster:getName()
	local boosted = Game.getBoostedCreature and Game.getBoostedCreature()
	if boosted and tostring(boosted):lower() == tostring(name):lower() then
		return "boosted"
	end

	local raceId = mType and mType:raceId() or 0
	if CustomBosstiary and CustomBosstiary.isBoostedBoss and raceId > 0 then
		if CustomBosstiary.isBoostedBoss(raceId) then
			return "boosted"
		end
	end

	-- Everything below needs a player; an unowned corpse cannot carry a
	-- per-player modifier, which makes it the purest sample there is.
	if not player then
		return "plain"
	end

	if player:getDropBonus() and player:getDropBonus() > 0 then
		return "boosted"
	end

	if PreySystem and PreySystem.getBonus then
		local bonusType = PreySystem.getBonus(player, name)
		if bonusType == PreySystem.BONUS_LOOT then
			return "boosted"
		end
	end

	if TaskBoard and TaskBoard.getBountyTalismanBonus and raceId > 0 then
		if (TaskBoard.getBountyTalismanBonus(player, raceId, 2) or 0) > 0 then
			return "boosted"
		end
	end

	return "plain"
end

local event = Event()

function event.onDropLoot(monster, corpse)
	if not monster or not corpse or not corpse:isContainer() then
		return
	end

	-- Summons are excluded here for the same reason they are excluded from the
	-- kill counter: a conjured creature's corpse is a spell's side effect, not
	-- content anyone hunted.
	if monster:getMaster() then
		return
	end

	local mType = monster:getType()
	local player = Player(corpse:getCorpseOwner())
	local state = corpseState(monster, mType, player)

	local items = {}
	for _, item in ipairs(corpse:getItems()) do
		items[#items + 1] = {
			id = item:getId(),
			count = item:getCount() or 1,
			rare = isRare(item),
		}
	end

	Loot.record(mType and mType:getName() or monster:getName(), items, state)
end

event:register(60)
