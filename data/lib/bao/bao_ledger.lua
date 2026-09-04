-- Bao's Ledger — the part of the shop that never runs out.
--
-- Every fixed shop eventually empties, and the moment it does Marks stop
-- meaning anything. The Ledger is the answer: a set of permanent, stacking
-- upgrades whose cost grows with every rank bought, so there is always
-- something left to save toward no matter how long someone has played.
--
-- Two rules keep it from becoming a power-creep problem:
--
--   1. Every track has a maxRank. "Infinite" is about the SINK, not the
--      bonus — the cost curve is what runs forever, and a maxed track simply
--      stops being buyable. Cold Trail can never reach 100% or hunts would
--      complete on zero kills.
--
--   2. No track duplicates the Wheel of Destiny or a rarity bonus. Those two
--      already claim every combat number there is -- attack, defence, armour,
--      crit, leech, dodge, resistances, max health, max mana, capacity, every
--      weapon skill, magic level, kill-experience (Grave Tithe) and gold drops
--      (Fortune). Bao takes the axis neither touches: what dying costs, how
--      fast you recover, and how quickly time spent becomes progress. Rates
--      and consequences, never stats. Check any new track against BOTH systems
--      before adding it.
--
-- The cost formula is baseCost * growth^rank, floored. Growth between 1.09
-- and 1.14 means the first few ranks are reachable in a week or two of
-- bounties and the last few take months, which is the shape that keeps a
-- long-term player earning.

BaoLedger = {}

-- The three books, as data rather than as section comments. The client groups
-- rows by these: thirteen identical rows in a flat list reads as a settings
-- page, while three named books with their own progress reads as a tome you
-- are filling in. Each book's subtitle says what it is FOR, because "Deep
-- Pockets" and "Hard to Kill" being in different books is the whole structure.
BaoConfig.LedgerBooks = {
	[1] = { title = "Book I - The Trade",
	        subtitle = "What Bao's own work pays, and how hard he makes you work for it." },
	[2] = { title = "Book II - Coming Home",
	        subtitle = "What dying costs you, and how quickly you get back on your feet." },
	[3] = { title = "Book III - The Long Road",
	        subtitle = "The slow trades. Everything here pays off over months, not evenings." },
}

BaoConfig.Ledger = {
	["cold_trail"] = {
		order = 1, book = 1,
		displayName = "Cold Trail",
		summary = "Bao's hunts ask for fewer kills.",
		-- The one that fixes the system's own worst number. A 3,000-kill hunt
		-- at rank 40 becomes 1,800 — the player buys their own difficulty
		-- curve down instead of the config guessing at it for everyone.
		effect = "-%d%% required kills on every hunt",
		perRank = 1, maxRank = 40,
		baseCost = 2000, growth = 1.12,
	},
	["long_road"] = {
		order = 2, book = 1,
		displayName = "The Long Road",
		summary = "Hunt completions pay more experience.",
		effect = "+%d%% experience from hunt rewards",
		perRank = 2, maxRank = 50,
		baseCost = 1500, growth = 1.10,
	},
	["deep_pockets"] = {
		order = 3, book = 1,
		displayName = "Deep Pockets",
		summary = "Bao pays better, everywhere.",
		effect = "+%d%% Marks from hunts and orders",
		perRank = 2, maxRank = 50,
		baseCost = 1800, growth = 1.11,
	},
	["trophy_hunter"] = {
		order = 4, book = 1,
		displayName = "Trophy Hunter",
		summary = "Bao thinks more of what you bring him.",
		effect = "+%d%% Reputation from hunts and orders",
		perRank = 2, maxRank = 50,
		baseCost = 1600, growth = 1.10,
	},
	["hunters_eye"] = {
		order = 5, book = 1,
		displayName = "Hunter's Eye",
		summary = "Better odds on the rare drop a hunt pays out.",
		-- (!) This is NOT a general luck stat. It shifts weight on Bao's own
		-- rareTable (bao_reward.lua) toward the rarer bands, and touches
		-- nothing about ordinary loot or the rarity system. A true
		-- server-wide luck stat is a different, much larger feature.
		effect = "+%d%% chance a hunt's reward rolls a rarer band",
		perRank = 2, maxRank = 25,
		baseCost = 2500, growth = 1.14,
	},

	-- ── Book II: Coming Home ──────────────────────────────────────────
	-- Consequence and recovery. Nothing here is a combat number: the Wheel of
	-- Destiny and the rarity bonuses between them already claim every stat
	-- worth having -- attack, defence, armour, crit, leech, dodge, resistances,
	-- max health, max mana, capacity, every weapon skill, magic level, and even
	-- kill-experience (Grave Tithe) and gold drops (Fortune).
	--
	-- So Bao takes the axis neither of them touches: what dying costs you, and
	-- how fast you recover. That is also exactly who he is -- his farewell is
	-- "coming home is part of hunt". He does not teach you to swing.
	["hard_to_kill"] = {
		order = 6, book = 2,
		displayName = "Hard to Kill",
		summary = "You lose less of yourself when you die.",
		-- Wired through Player::setBaoExperienceLossReduction (src/luaplayer.cpp).
		effect = "-%d%% experience lost on death",
		perRank = 1, maxRank = 20,
		baseCost = 3000, growth = 1.13,
	},
	["travelling_light"] = {
		order = 7, book = 2,
		displayName = "Travelling Light",
		summary = "Your gear is likelier to come home with you.",
		-- Wired through Player::setBaoEquipmentLossReduction, which scales
		-- Player::getEquipmentLossPercent after blessings have applied.
		effect = "-%d%% chance to drop equipment on death",
		perRank = 2, maxRank = 25,
		baseCost = 2800, growth = 1.12,
	},
	["iron_constitution"] = {
		order = 8, book = 2, pending = true,
		displayName = "Iron Constitution",
		summary = "You get your wind back faster between fights.",
		-- A RATE, not a pool. Both other systems grant max health and mana;
		-- neither touches how quickly it comes back.
		-- Gated deliberately. CONDITION_PARAM_HEALTHGAINPERCENT does NOT scale
		-- the vocation's own regeneration -- it adds a flat amount derived from
		-- max health inside a separate ConditionRegeneration, which stacks as an
		-- extra regen source rather than speeding up the existing one. There is
		-- no honest way to deliver "+2% regeneration" with it, and shipping a
		-- number that does not mean what it says is worse than shipping nothing.
		effect = "+%d%% health and mana regeneration out of combat",
		perRank = 2, maxRank = 40,
		baseCost = 2200, growth = 1.11,
	},
	["second_wind"] = {
		order = 9, book = 2,
		displayName = "Second Wind",
		summary = "You can stay out longer before the world makes you rest.",
		effect = "+%d%% stamina recovered while resting",
		perRank = 2, maxRank = 30,
		baseCost = 2400, growth = 1.12,
	},
	["field_medicine"] = {
		order = 10, book = 2,
		displayName = "Field Medicine",
		summary = "You waste less of what you carry.",
		effect = "+%d%% healing from potions",
		perRank = 1, maxRank = 25,
		baseCost = 2600, growth = 1.13,
	},

	-- ── Book III: The Long Road ───────────────────────────────────────
	-- Time and progress. Again nothing either other system grants: they give
	-- skill POINTS, this gives faster TRAINING; they give kill-experience, this
	-- gives Bao's own reward experience.
	["sharp_memory"] = {
		order = 11, book = 3,
		displayName = "Sharp Memory",
		summary = "What you practise sticks sooner.",
		effect = "+%d%% skill and magic advance rate",
		perRank = 1, maxRank = 30,
		baseCost = 3200, growth = 1.13,
	},
	["night_watch"] = {
		order = 12, book = 3,
		displayName = "Night Watch",
		summary = "Even your rest is worth something.",
		-- Wired through Player::setBaoOfflineTrainingBonus, applied to the try
		-- count in Player::applyOfflineTraining before the per-vocation split.
		effect = "+%d%% offline training gained",
		perRank = 2, maxRank = 30,
		baseCost = 2000, growth = 1.11,
	},
	["trackers_instinct"] = {
		order = 13, book = 3,
		displayName = "Tracker's Instinct",
		summary = "You read a creature faster than other hunters do.",
		effect = "+%d%% bestiary progress per kill",
		perRank = 1, maxRank = 30,
		baseCost = 2600, growth = 1.12,
	},
}


-- Ordered list, for sending and display. Sorted by `order` then key so the
-- track list never reshuffles between restarts the way a raw pairs() would.
-- `includePending` lists tracks whose effect is configured but not yet wired
-- into the game. They are EXCLUDED by default so the shop can never sell a
-- bonus that does nothing -- a purchased no-op is worse than a missing feature,
-- because the player has no way to tell it is not working.
function BaoLedger.orderedKeys(includePending)
	local keys = {}
	for key, track in pairs(BaoConfig.Ledger) do
		if includePending or not track.pending then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys, function(a, b)
		local ta, tb = BaoConfig.Ledger[a], BaoConfig.Ledger[b]
		if ta.order ~= tb.order then
			return ta.order < tb.order
		end
		return a < b
	end)
	return keys
end

-- ─── State ───────────────────────────────────────────────────────────────

local function ledgerStore(player)
	return player:kv():scoped("bao"):scoped("ledger")
end

function BaoLedger.getRank(player, key)
	local value = ledgerStore(player):get(key)
	return type(value) == "number" and value or 0
end

-- Total ranks across every track. A single prestige number — cheap to compute,
-- and the natural thing to put next to a name on a leaderboard.
function BaoLedger.totalRanks(player)
	local total = 0
	for key in pairs(BaoConfig.Ledger) do
		total = total + BaoLedger.getRank(player, key)
	end
	return total
end

-- Every rank the Ledger could ever hold. The denominator that turns a bare
-- "12 lessons learned" into "12 of 508" -- a number that shows the size of
-- what is being built rather than just how far along it is.
function BaoLedger.maxRanks()
	local total = 0
	for _, track in pairs(BaoConfig.Ledger) do
		if not track.pending then
			total = total + track.maxRank
		end
	end
	return total
end

-- Marks sunk into the Ledger so far. Costs are floored per rank, so this is
-- summed rather than solved as a geometric series -- 13 tracks of at most 50
-- ranks is nothing, and it stays exact if the cost curve is ever changed.
function BaoLedger.totalInvested(player)
	local total = 0
	for key, track in pairs(BaoConfig.Ledger) do
		local rank = BaoLedger.getRank(player, key)
		for i = 0, rank - 1 do
			total = total + math.floor(track.baseCost * (track.growth ^ i))
		end
	end
	return total
end

-- Cost of the NEXT rank, or nil if the track is maxed.
function BaoLedger.costOf(player, key)
	local track = BaoConfig.Ledger[key]
	if not track then
		return nil
	end
	local rank = BaoLedger.getRank(player, key)
	if rank >= track.maxRank then
		return nil
	end
	return math.floor(track.baseCost * (track.growth ^ rank))
end

-- Buys one rank. Returns ok, reasonOrSummary.
--
-- Marks are spent through BaoState.spendMarks, which refuses rather than
-- going negative, and the rank is only written if that succeeded — so a
-- failed spend can never hand out a free rank.
function BaoLedger.purchase(player, key)
	local track = BaoConfig.Ledger[key]
	if not track then
		return false, "Bao has no such lesson."
	end

	if track.pending then
		return false, "Bao knows that one, but he is not ready to teach it yet."
	end

	local rank = BaoLedger.getRank(player, key)
	if rank >= track.maxRank then
		return false, "You have learned all he can teach of that."
	end

	local cost = BaoLedger.costOf(player, key)
	if not BaoState.spendMarks(player, cost) then
		return false, string.format("You need %d Marks for that.", cost)
	end

	ledgerStore(player):set(key, rank + 1)

	-- Mirror the whole Ledger to SQL here rather than at the protocol layer,
	-- so the website is current the moment a rank is bought and any future
	-- caller of purchase() gets it for free. Guarded because the mirror is a
	-- website feature: a server booted without it must still sell ranks.
	if BaoLedgerDB then
		BaoLedgerDB.refreshSummary(player)
	end

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"Old Man Bao marks something in his ledger. \"%s, %d. %s\"",
		track.displayName, rank + 1, track.summary))
	return true, { rank = rank + 1, cost = cost }
end

-- ─── Effects ─────────────────────────────────────────────────────────────
--
-- Each of these is the ONLY place its track is applied, so a track can be
-- retuned or removed without hunting through the codebase for its effects.

-- Multiplier form, e.g. 1.24 for 12 ranks of a 2%-per-rank track.
local function multiplier(player, key)
	local track = BaoConfig.Ledger[key]
	if not track then
		return 1.0
	end
	return 1.0 + (BaoLedger.getRank(player, key) * track.perRank / 100)
end

-- How many kills this hunt actually asks THIS player for. Never returns less
-- than 1: a hunt that needs zero kills would complete on acceptance.
function BaoLedger.requiredFor(player, hunt)
	local track = BaoConfig.Ledger["cold_trail"]
	local rank = BaoLedger.getRank(player, "cold_trail")
	if rank <= 0 then
		return hunt.requiredCount
	end
	local reduction = math.min(rank * track.perRank, track.maxRank * track.perRank) / 100
	return math.max(1, math.floor(hunt.requiredCount * (1 - reduction)))
end

-- Book II/III accessors. Each is the ONLY place its track is applied, so a
-- track can be retuned or removed without hunting the codebase for its
-- effects. All return 1.0 when the player has bought nothing, so a caller can
-- multiply unconditionally.

-- Stamina regained while offline (data/scripts/creaturescripts/others/regeneratestamina.lua).
function BaoLedger.staminaMultiplier(player)
	return multiplier(player, "second_wind")
end

-- Healing from potions (data/scripts/actions/other[s]/potions.lua).
function BaoLedger.potionMultiplier(player)
	return multiplier(player, "field_medicine")
end

-- Skill tries and mana spent, i.e. how fast training advances -- NOT the skill
-- level itself, which is what the Wheel and the rarity bonuses grant.
function BaoLedger.skillTriesMultiplier(player)
	return multiplier(player, "sharp_memory")
end

-- Bestiary kill credit (data/scripts/creaturescripts/others/custom_bestiary.lua).
function BaoLedger.bestiaryMultiplier(player)
	return multiplier(player, "trackers_instinct")
end

function BaoLedger.experienceMultiplier(player)
	return multiplier(player, "long_road")
end

function BaoLedger.marksMultiplier(player)
	return multiplier(player, "deep_pockets")
end

function BaoLedger.reputationMultiplier(player)
	return multiplier(player, "trophy_hunter")
end

-- Extra weight, as a fraction of the rare table's total, shifted out of the
-- "normal" band and onto the rarest band the hunt offers. Same mechanism
-- bao_reward.lua's first-mastery bonus already uses, so the two simply add.
function BaoLedger.rareRollBonus(player)
	local track = BaoConfig.Ledger["hunters_eye"]
	return BaoLedger.getRank(player, "hunters_eye") * track.perRank / 100
end

-- ─── Native (C++) tracks ────────────────────────────────────────────────
--
-- Three tracks have no Lua hook: what a death costs in experience, what it
-- costs in equipment, and what offline training is worth. All three are decided
-- inside Player, so small bindings were added (Player::setBao*, see
-- src/luaplayer.cpp) and this pushes the current rank down into them.
--
-- (!) The C++ side stores nothing. These MUST be re-applied on login
-- (data/scripts/creaturescripts/bao/bao_ledger_apply.lua) and immediately after
-- a purchase, or a rank the player just paid for does nothing until they relog.
function BaoLedger.applyNative(player)
	if not player.setBaoExperienceLossReduction then
		return false -- server built before the bindings existed
	end

	local function percentOf(key)
		local track = BaoConfig.Ledger[key]
		if not track then
			return 0
		end
		return BaoLedger.getRank(player, key) * track.perRank
	end

	player:setBaoExperienceLossReduction(percentOf("hard_to_kill"))
	player:setBaoEquipmentLossReduction(percentOf("travelling_light"))
	player:setBaoOfflineTrainingBonus(percentOf("night_watch"))
	return true
end

-- ─── Startup validation ─────────────────────────────────────────────────

-- A track whose bonus can reach 100% would zero out whatever it scales.
-- Cold Trail is the dangerous one -- at 100% a hunt needs no kills at all.
function BaoLedger.validate()
	local problems = 0
	for key, track in pairs(BaoConfig.Ledger) do
		local total = track.perRank * track.maxRank
		if key == "cold_trail" and total >= 100 then
			problems = problems + 1
			print(string.format(
				"[Bao] Ledger track '%s' reaches %d%% reduction - at 100%% hunts would need no kills.",
				track.displayName, total))
		end
		if track.growth <= 1.0 then
			problems = problems + 1
			print(string.format(
				"[Bao] Ledger track '%s' has growth %.2f - the cost must rise per rank or the sink is not infinite.",
				track.displayName, track.growth))
		end
	end
	return problems
end

BaoLedger.validate()
