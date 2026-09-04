-- Old Man Bao — reward payout. Called exactly once, right after a hunt slot
-- flips to completed (BaoState.addHuntProgress returns justCompleted = true).
-- Grants guaranteed XP/reputation/marks (with the first-mastery multiplier
-- when applicable), rolls a rare-item tier, and returns a summary table for
-- the caller's diagnostic print. Does NOT touch rank-up (bao_rank.lua, wired
-- separately from bao_death.lua) or the active-hunt slot (BaoState.clearSlot,
-- also wired from bao_death.lua) — this file only grants the reward.

BaoReward = {}

-- Weighted-average base XP across a family hunt's targets. A monster name
-- that fails to resolve to a MonsterType (typo in bao_config) is skipped
-- entirely — both its contribution AND its weight are dropped from the
-- average, rather than erroring or treating it as 0 (which would silently
-- drag the average down for a config typo instead of just ignoring it).
local function familyAverageBaseXP(targets)
	local weightedSum = 0
	local totalWeight = 0
	for monsterName, weight in pairs(targets) do
		local monsterType = MonsterType(monsterName)
		if monsterType then
			weightedSum = weightedSum + (monsterType:experience() * weight)
			totalWeight = totalWeight + weight
		else
			print(string.format("[Bao] WARNING: bao_reward could not resolve MonsterType '%s' (check bao_config.lua target name)", monsterName))
		end
	end
	if totalWeight <= 0 then
		return 0
	end
	return weightedSum / totalWeight
end

-- monsterBaseXP is "effective XP per requiredCount point": for a single-
-- target hunt that's just the monster's base experience; for a family hunt
-- requiredCount is already a weighted-point total, so the weighted-average
-- base XP across targets is the right per-point figure to multiply back up.
local function effectiveBaseXP(hunt)
	if hunt.kind == "family" then
		return familyAverageBaseXP(hunt.targets)
	end

	local monsterType = MonsterType(hunt.target)
	if not monsterType then
		print(string.format("[Bao] WARNING: bao_reward could not resolve MonsterType '%s' (check bao_config.lua target name)", tostring(hunt.target)))
		return 0
	end
	return monsterType:experience()
end

-- `xpPercent` is a multiplier on the experience the KILLS themselves paid, so
-- 1.0 means Bao pays the hunt over again: 150 trolls at 20 experience earns
-- 3,000 grinding, and mastering it pays 3,000 more. That is the whole promise,
-- and it is legible without a tooltip -- finish the task, double the hunt.
--
-- It tapers as chapters rise (1.0 down to 0.4) because the deep chapters are
-- already enormous in absolute terms; doubling a 14-million-experience grind
-- would dwarf every other source in the game.
local function computeGuaranteedXP(hunt)
	local baseXP = effectiveBaseXP(hunt)
	local xp = baseXP * hunt.requiredCount * hunt.rewards.guaranteed.xpPercent
	local cap = BaoConfig.TierXPCap[hunt.tier]
	if cap then
		xp = math.min(xp, cap)
	end
	return xp
end

-- Builds the rareTable to roll against for this grant. On a first-mastery
-- completion, rareRollBonus (a fraction of the table's total weight — the
-- starter tables all sum their weights to 1000, so e.g. 0.10 == 100 weight
-- points) is transferred from "normal" onto a single non-normal tier, rather
-- than being split proportionally across every non-normal tier. Splitting it
-- would require picking a split ratio the design doc doesn't specify, and
-- would move each individual tier's odds by an amount too small to notice;
-- a single-tier transfer is both simpler to implement correctly and produces
-- a payout that's actually perceptible. The recipient is chosen as the
-- non-normal tier with the SMALLEST weight (excluding any zero-weight
-- placeholder entries) — i.e. the rarest tier the hunt offers (e.g. "jackpot"
-- for the tiers that have one, "very_rare"/"rare" otherwise) — since a
-- first-mastery completion is the one-time event a player is most likely to
-- want a shot at the best-possible drop, not a bump to the already-common
-- "uncommon" tier.
local function buildRollTable(hunt, isFirstMastery, player)
	local rareTable = hunt.rewards.rareTable

	-- Two sources of bonus weight, and they simply add: the one-off
	-- first-mastery bump, and however many ranks of Hunter's Eye the player has
	-- bought from Bao's Ledger. Both shift weight the same way, so there is one
	-- mechanism rather than two competing ones.
	local bonus = 0
	if isFirstMastery then
		bonus = hunt.rewards.firstMastery.rareRollBonus or 0
	end
	if BaoLedger and player then
		bonus = bonus + BaoLedger.rareRollBonus(player)
	end

	if bonus <= 0 then
		return rareTable
	end

	local totalWeight = 0
	local normalEntry = nil
	local targetEntry = nil
	for _, entry in ipairs(rareTable) do
		totalWeight = totalWeight + entry.weight
		if entry.tier == "normal" then
			normalEntry = entry
		elseif entry.weight > 0 and (not targetEntry or entry.weight < targetEntry.weight) then
			targetEntry = entry
		end
	end

	if not normalEntry or not targetEntry then
		return rareTable
	end

	local shiftAmount = math.min(bonus * totalWeight, normalEntry.weight)
	if shiftAmount <= 0 then
		return rareTable
	end

	local adjusted = {}
	for i, entry in ipairs(rareTable) do
		local weight = entry.weight
		if entry.tier == normalEntry.tier then
			weight = weight - shiftAmount
		elseif entry.tier == targetEntry.tier then
			weight = weight + shiftAmount
		end
		adjusted[i] = { tier = entry.tier, weight = weight, pool = entry.pool }
	end
	return adjusted
end

-- Integer-weighted roll (all configured weights are whole numbers).
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

-- Picks one item entry from a resolved pool's `items` list. A pool with a
-- single entry always returns it; a pool with several is itself a weighted
-- roll (entry.weight, default 1 if omitted) so a pool can lean toward one
-- item without needing a separate tier just for that.
local function pickPoolItem(pool)
	if not pool or not pool.items or #pool.items == 0 then
		return nil
	end
	if #pool.items == 1 then
		return pool.items[1]
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

-- IOLoginData::INBOX_SAVE_LIMIT (src/iologindata.h:24). Kept as a named local
-- so the reason for the number is findable rather than looking like a guess.
local INBOX_SAVE_LIMIT = 100

-- Grants itemId/count to the player, falling back to their inbox if their
-- inventory has no room.
--
-- (!) The inbox fallback MUST check occupancy first. Anything past
-- INBOX_SAVE_LIMIT is silently discarded when the player is saved — the comment
-- on that loop in src/iologindata.cpp says so explicitly and names
-- ItemBazaar::withdrawItem as the system that gets it right. Without this
-- check a jackpot pull (a falcon plate, a sanguine blade) can be "granted",
-- announced to the player, and then deleted at their next logout, leaving
-- nothing but a warning in the server log.
--
-- Refusing is strictly better than that: the item stays ungranted, the caller
-- reports it honestly, and the player is told to clear space.
-- Returns the ITEM on success (still truthy for callers that only test it),
-- because the Dormant path has to roll rarity onto the object it just handed
-- over. Falsy on failure.
local function grantItem(player, itemId, count)
	local item = player:addItem(itemId, count)
	if item then
		return item
	end

	local inbox = player:getInbox()
	if not inbox then
		return false
	end
	if inbox:getSize() >= INBOX_SAVE_LIMIT then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
			"Old Man Bao holds something back. \"Your hands are full, and your mailbox too. Make room, then ask me again.\"")
		return false
	end
	local mailed = inbox:addItem(itemId, count)
	if mailed then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Your reward was sent to your inbox.")
		return mailed
	end
	return false
end

-- Rolls a rare-item tier, then rolls and grants a concrete item from that
-- tier's pool. Returns a table describing what happened (always has `tier`;
-- `itemId`/`count` only when an item was actually resolved and granted) so
-- the caller can report it accurately instead of assuming success.

-- ─── Dormant gear ───────────────────────────────────────────────────────
--
-- A mastery normally pays supplies. A small percentage of the time it pays a
-- piece of equipment instead -- and Bao NEVER hands over a plain item. Whatever
-- comes out of here is rolled Dormant: unrevealed until the player wakes it,
-- which is the loop Bao's own shop sells the Dormancy Rune for.

-- Base vocation ids, matching getVocation():getBase():getId().
local function baseVocationId(player)
	local voc = player:getVocation()
	if not voc then
		return nil
	end
	local base = voc:getBase()
	return base and base:getId() or voc:getId()
end

-- (!) Without this filter a druid who masters a 30-million-experience Chapter
-- VI hunt can be handed a falcon plate they can never wear -- worse than
-- potions. An entry with no `vocs` is open to everyone (rings, shields, boots).
local function usableBy(entry, vocationId)
	if not entry.vocs or #entry.vocs == 0 then
		return true
	end
	for _, id in ipairs(entry.vocs) do
		if id == vocationId then
			return true
		end
	end
	return false
end

-- Rolls one piece of Dormant gear, or nil if this mastery pays supplies.
local function rollDormantGear(player, hunt, isFirstMastery)
	local pool = BaoConfig.GearPools and BaoConfig.GearPools[hunt.tier]
	if not pool or not pool.items or #pool.items == 0 then
		return nil
	end

	-- First mastery is worth twice the shot at gear. It is the once-per-hunt
	-- moment, and the same reason its experience payout is the big one.
	local chance = (pool.chance or 0) * (isFirstMastery and 2 or 1)
	if chance <= 0 or math.random() * 100 >= chance then
		return nil
	end

	local vocationId = baseVocationId(player)
	local weights = BaoConfig.GearClassWeight or { 40, 26, 17, 11, 6 }
	local eligible, total = {}, 0
	for _, entry in ipairs(pool.items) do
		if usableBy(entry, vocationId) then
			local w = weights[entry.class] or 1
			eligible[#eligible + 1] = { entry = entry, weight = w }
			total = total + w
		end
	end
	if total <= 0 then
		print(string.format("[Bao] WARNING: no gear in '%s' is usable by vocation %s",
			hunt.tier, tostring(vocationId)))
		return nil
	end

	local roll = math.random(1, total)
	local cumulative = 0
	local picked = eligible[#eligible].entry
	for _, e in ipairs(eligible) do
		cumulative = cumulative + e.weight
		if roll <= cumulative then
			picked = e.entry
			break
		end
	end

	-- Granted first, then woken into a Dormant in place. Doing it in this order
	-- means a failed grant (full inventory AND full inbox) never leaves a rolled
	-- item nowhere, and the player simply gets the supply line instead.
	local item = grantItem(player, picked.id, 1)
	if not item then
		print(string.format("[Bao] WARNING: could not deliver Dormant item %d to %s",
			picked.id, player:getName()))
		return nil
	end

	-- forced = true picks a tier at random; skipDormant left nil is what makes
	-- it Dormant rather than revealing the roll now.
	-- Guarded on getId: addItem is bound to return the Item, but a boolean here
	-- would silently skip the Dormant roll and hand out a PLAIN endgame item,
	-- which is the one outcome this whole path exists to prevent.
	if RarityStats and RarityStats.rollRarity and type(item) == "userdata" and item.getId then
		RarityStats.rollRarity(item, true)
	else
		print(string.format("[Bao] WARNING: granted %d to %s but could not roll it Dormant",
			picked.id, player:getName()))
	end

	return { tier = "dormant", itemId = picked.id, count = 1 }
end

local function rollRareTier(hunt, isFirstMastery, player)
	local rollTable = buildRollTable(hunt, isFirstMastery, player)
	local picked = rollTier(rollTable)
	if not picked then
		return nil
	end

	local pool = BaoConfig.RewardPools[picked.pool]
	local itemEntry = pickPoolItem(pool)
	if not itemEntry then
		print(string.format("[Bao] WARNING: reward pool '%s' has no items configured (tier '%s', hunt '%s')",
			picked.pool, picked.tier, hunt.displayName))
		return { tier = picked.tier }
	end

	local count = itemEntry.count or 1
	if not grantItem(player, itemEntry.itemId, count) then
		print(string.format("[Bao] WARNING: failed to grant item %d x%d to %s (rolled tier '%s', pool '%s')",
			itemEntry.itemId, count, player:getName(), picked.tier, picked.pool))
		return { tier = picked.tier }
	end

	return { tier = picked.tier, itemId = itemEntry.itemId, count = count }
end

-- Old Man Bao's own voice, isolated here so it's the one place his lines for
-- hunt completion live — keep any future edits to his tone confined to this
-- function rather than scattered through the reward math above.
local function announceCompletion(player, hunt, isFirstMastery, reputation, marks, rareReward)
	local line
	if isFirstMastery then
		line = string.format(
			"Old Man Bao: \"Now you have seen %s for what it is. %d Reputation, %d Marks. Do not forget what it taught you.\"",
			hunt.displayName, reputation, marks
		)
	else
		line = string.format(
			"Old Man Bao: \"Good hunt. You return whole - that is the part that matters. %d Reputation, %d Marks.\"",
			reputation, marks
		)
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, line)

	if rareReward and rareReward.itemId then
		local itemName = ItemType(rareReward.itemId):getName()
		-- A Dormant is the rare outcome and reads as one. The generic "you also
		-- found" line undersells the single most exciting thing Bao can hand
		-- over, and a player who has never seen a Dormant needs telling what
		-- to do with it.
		if rareReward.tier == "dormant" then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
				"Old Man Bao turns something over in his hands before giving it to you. \"This one is still asleep. %s. Wake it at a shrine, or with a waker, and see what it wants to be.\"",
				itemName))
		else
			local itemPhrase = rareReward.count > 1 and string.format("%dx %s", rareReward.count, itemName) or itemName
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("You also found: %s.", itemPhrase))
		end
	end
end

-- What a hunt WOULD pay, for the card that offers it.
--
-- The Hunts tab used to show only a name, a monster and a kill count, so the
-- one decision the tab exists for -- which of these should I take -- was made
-- completely blind. This runs the same arithmetic BaoReward.grant does, so the
-- preview can never promise something the payout does not deliver.
--
-- `first` is the first-mastery figures: triple reputation, double marks, more
-- experience and better odds on the rare roll. Worth calling out separately
-- because it only ever happens once per hunt, and it is the reason to spread
-- across the roster rather than repeat one hunt.
function BaoReward.preview(player, hunt)
	local full = computeGuaranteedXP(hunt)
	local reputation = hunt.rewards.guaranteed.reputation
	local marks = hunt.rewards.guaranteed.marks

	local firstXp = full * (1 + hunt.rewards.firstMastery.xpPercentBonus)
	local xp = full * (BaoConfig.RepeatXPFactor or 0.30)
	local firstRep = reputation * hunt.rewards.firstMastery.reputationMult
	local firstMarks = marks * hunt.rewards.firstMastery.marksMult

	if BaoLedger and player then
		local x, m, r = BaoLedger.experienceMultiplier(player),
			BaoLedger.marksMultiplier(player), BaoLedger.reputationMultiplier(player)
		xp, marks, reputation = xp * x, marks * m, reputation * r
		firstXp, firstMarks, firstRep = firstXp * x, firstMarks * m, firstRep * r
	end

	return {
		xp = math.floor(xp),
		reputation = math.floor(reputation),
		marks = math.floor(marks),
		firstXp = math.floor(firstXp),
		firstReputation = math.floor(firstRep),
		firstMarks = math.floor(firstMarks),
	}
end

-- Grants the reward for a just-completed hunt slot.
function BaoReward.grant(player, huntId, isFirstMastery)
	local hunt = BaoConfig.Hunts[huntId]
	if not hunt then
		print(string.format("[Bao] WARNING: BaoReward.grant called for unknown huntId '%s'", tostring(huntId)))
		return nil
	end

	local xp = computeGuaranteedXP(hunt)
	local reputation = hunt.rewards.guaranteed.reputation
	local marks = hunt.rewards.guaranteed.marks

	if isFirstMastery then
		xp = xp * (1 + hunt.rewards.firstMastery.xpPercentBonus)
		reputation = reputation * hunt.rewards.firstMastery.reputationMult
		marks = marks * hunt.rewards.firstMastery.marksMult
	else
		-- (!) The big experience payout happens ONCE per hunt, not once per
		-- completion.
		--
		-- Every hunt is repeatable with no cooldown, so a full payout on every
		-- completion would not be a task reward at all -- it would be a
		-- permanent 2x experience rate for anyone who keeps a slot filled,
		-- which is not what rateExp = 1 was set to mean. Paying it once is also
		-- the better design: it moves a player to the next spawn instead of
		-- letting them settle on one.
		--
		-- Reputation and Marks are deliberately NOT reduced here. Experience
		-- rewards breadth; Marks and Reputation reward depth, so grinding a
		-- favourite hunt still feeds the Ledger.
		xp = xp * (BaoConfig.RepeatXPFactor or 0.30)
	end

	-- Bao's Ledger. Applied last so it multiplies the final figure including
	-- the first-mastery bonus, and applied here rather than inside the Ledger
	-- so this function stays the single place a reward number is decided.
	if BaoLedger then
		xp = xp * BaoLedger.experienceMultiplier(player)
		reputation = reputation * BaoLedger.reputationMultiplier(player)
		marks = marks * BaoLedger.marksMultiplier(player)
	end

	xp = math.floor(xp)
	reputation = math.floor(reputation)
	marks = math.floor(marks)

	-- player:addExperience(experience[, sendText = false]) — matches the call
	-- shape used throughout data/npc/**/quests/*.lua and
	-- data/scripts/network/task_board/*.lua for quest/task XP rewards.
	player:addExperience(xp, true)
	BaoState.addReputation(player, reputation)
	BaoState.addMarks(player, marks)

	-- Gear first: on a hit this mastery pays a Dormant instead of the supply
	-- line, which is the whole point of the rare outcome being rare.
	local rareReward = rollDormantGear(player, hunt, isFirstMastery)
		or rollRareTier(hunt, isFirstMastery, player)
	announceCompletion(player, hunt, isFirstMastery, reputation, marks, rareReward)

	-- Some hunts advance Bao's personal storyline directly, independent of
	-- rank-up (e.g. a specific extreme-endgame hunt unlocking a late chapter
	-- that no rank threshold gates on its own). BaoRank.announceStoryChapter
	-- is shared with bao_rank.lua's rank-up path so the beat reads identically
	-- either way.
	if hunt.storyChapterUnlock and BaoState.setStoryChapter(player, hunt.storyChapterUnlock) then
		BaoRank.announceStoryChapter(player, hunt.storyChapterUnlock)
	end

	return {
		xp = xp,
		reputation = reputation,
		marks = marks,
		rareTier = rareReward and rareReward.tier,
		rareItemId = rareReward and rareReward.itemId,
		rareItemCount = rareReward and rareReward.count,
		isFirstMastery = isFirstMastery,
	}
end
