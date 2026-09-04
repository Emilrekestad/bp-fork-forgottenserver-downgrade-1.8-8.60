-- Old Man Bao — hunt/rank/shop configuration.
-- This is the ONLY file that should ever contain hunt/rank data. Everything
-- else (bao_lookup, bao_state, bao_reward, bao_rank, the kill hooks, the
-- protocol handlers) is generic logic that reads from here — adding a new
-- hunt or retuning a threshold should never require touching another file.

BaoConfig = {}

BaoConfig.MaxActiveSlots = 3

-- Minimum share of a monster's max health a player must have contributed to
-- be credited for hunt progress on that kill (damage-participation model).
--
-- Was 0.01, which on a 50 HP troll meant half a point of damage bought a full
-- hunt credit — one character tags, every other character present banks the
-- kill. 0.10 still credits genuine group play (a four-man team all clear it
-- comfortably) while costing a drive-by tag nothing but the tag.
BaoConfig.MinDamageShare = 0.10

-- How many kills of progress may accumulate in memory before the active-hunt
-- row is written back. Progress was previously flushed on EVERY credited kill,
-- which is one INSERT ... ON DUPLICATE KEY UPDATE per player per slot per
-- death — the same mistake data/scripts/network/task_board/bounty_tasks.lua
-- already solves with its own KILL_SAVE_INTERVAL. Completion always flushes
-- immediately regardless of this, and BaoState.flush() runs on logout, so the
-- worst case for a crash is this many kills lost rather than a whole hunt.
BaoConfig.SaveInterval = 5

-- Canonical tier order, low danger to high. Two things need it and neither can
-- derive it: the client colours tier chips by this ranking, and the catalog is
-- sorted by it before being sent.
--
-- Sorting matters more than it looks. The catalog used to be serialized
-- straight out of `pairs(BaoConfig.Hunts)`, and Lua seeds its string hash per
-- process — so the order genuinely differed between server restarts and the
-- card grid visibly reshuffled every time, destroying any spatial memory a
-- player had built up of where a hunt sits.
BaoConfig.TierOrder = {
	["I - Doorstep"] = 1,
	["II - Outskirts"] = 2,
	["III - Far Roads"] = 3,
	["IV - Deep Country"] = 4,
	["V - The Wilds"] = 5,
	["VI - The Frontier"] = 6,
	["VII - World's End"] = 7,
}

BaoConfig.Ranks = {
	-- (!) masteriesRequired must stay BELOW the number of hunts whose minRank
	-- is less than this rank's id — mastery count can only ever be drawn from
	-- hunts you have already unlocked, so a threshold above that number makes
	-- the rank mathematically unreachable and silently kills every tier above
	-- it. The audit found exactly that: rank 5 asked for 45 against 44
	-- reachable hunts, and rank 6 for 65 against 55, which locked away 17
	-- hunts, four story chapters, two shop tiers and both endgame reward
	-- pools. bao_rank.lua asserts this at startup now; if you retune a
	-- threshold or add a tier, read that warning rather than guessing.
	--
	-- The ratios below preserve the original curve's intent (each rank asks
	-- for a progressively larger share of what is available: 43%, 47%, 59%,
	-- 78%, 86%, 95%) while leaving real headroom at the top two.
	{ id = 0, name = "Stray",              repThreshold = 0,       masteriesRequired = 0,  storyChapter = 0 },
	{ id = 1, name = "Tracker",            repThreshold = 2500,    masteriesRequired = 3,  storyChapter = 1 },
	{ id = 2, name = "Hunter",             repThreshold = 15000,   masteriesRequired = 13, storyChapter = 2 },
	{ id = 3, name = "Veteran",            repThreshold = 60000,   masteriesRequired = 27, storyChapter = 3 },
	{ id = 4, name = "Beast Slayer",       repThreshold = 200000,  masteriesRequired = 43, storyChapter = 5 },
	{ id = 5, name = "Master Hunter",      repThreshold = 600000,  masteriesRequired = 61, storyChapter = 6 },
	{ id = 6, name = "Legend of the Hunt", repThreshold = 1500000, masteriesRequired = 76, storyChapter = 8, finalBoss = nil },
}

-- Starter hunt set — one representative hunt per tier, real audited monsters
-- (populated loot, live spawns, not rewardBoss uniques). Phase 10 expands
-- this to the full 100-150+ set; the schema below is final, only the number
-- of entries grows.
BaoConfig.Hunts = {

	-- ── I - Doorstep · rank 0 · 24 hunts ──────────────────
	["wolf_stray"] = {
		tier = "I - Doorstep", displayName = "First Blood",
		kind = "single", target = "Wolf", requiredCount = 150,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 30, marks = 10 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["troll_stray"] = {
		tier = "I - Doorstep", displayName = "Trouble in the Hills",
		kind = "single", target = "Troll", requiredCount = 150,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 60, marks = 20 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["orc_stray"] = {
		tier = "I - Doorstep", displayName = "The Warband Grows",
		kind = "single", target = "Orc", requiredCount = 150,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 85, marks = 30 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["skeleton_stray"] = {
		tier = "I - Doorstep", displayName = "They Do Not Stay Buried",
		kind = "single", target = "Skeleton", requiredCount = 150,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 60, marks = 20 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["dworc_venomsniper_stray"] = {
		tier = "I - Doorstep", displayName = "Poison from the Dark",
		kind = "single", target = "Dworc Venomsniper", requiredCount = 150,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["crocodile_stray"] = {
		tier = "I - Doorstep", displayName = "Teeth in the Shallows",
		kind = "single", target = "Crocodile", requiredCount = 110,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 90, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["rotworm_stray"] = {
		tier = "I - Doorstep", displayName = "Work Beneath the Fields",
		kind = "single", target = "Rotworm", requiredCount = 150,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 75, marks = 30 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["dworc_fleshhunter_stray"] = {
		tier = "I - Doorstep", displayName = "The Small Cruel Ones",
		kind = "single", target = "Dworc Fleshhunter", requiredCount = 140,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["marsh_stalker_stray"] = {
		tier = "I - Doorstep", displayName = "Patience in the Reeds",
		kind = "single", target = "Marsh Stalker", requiredCount = 120,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["minotaur_stray"] = {
		tier = "I - Doorstep", displayName = "Bulls of the Labyrinth",
		kind = "single", target = "Minotaur", requiredCount = 120,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["dworc_voodoomaster_stray"] = {
		tier = "I - Doorstep", displayName = "Charms and Bad Intentions",
		kind = "single", target = "Dworc Voodoomaster", requiredCount = 150,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["toad_stray"] = {
		tier = "I - Doorstep", displayName = "Wet Work",
		kind = "single", target = "Toad", requiredCount = 90,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["nomad_stray"] = {
		tier = "I - Doorstep", displayName = "Nobody Owns the Desert",
		kind = "single", target = "Nomad", requiredCount = 80,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["gnarlhound_stray"] = {
		tier = "I - Doorstep", displayName = "The Pack at the Treeline",
		kind = "single", target = "Gnarlhound", requiredCount = 60,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["minotaur_archer_stray"] = {
		tier = "I - Doorstep", displayName = "Arrows in the Maze",
		kind = "single", target = "Minotaur Archer", requiredCount = 120,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["ghoul_stray"] = {
		tier = "I - Doorstep", displayName = "What Walks in the Graveyard",
		kind = "single", target = "Ghoul", requiredCount = 120,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["kongra_stray"] = {
		tier = "I - Doorstep", displayName = "Fury of the Ape King's Kin",
		kind = "single", target = "Kongra", requiredCount = 40,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["tarantula_stray"] = {
		tier = "I - Doorstep", displayName = "Eight Legs, No Mercy",
		kind = "single", target = "Tarantula", requiredCount = 50,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 90, marks = 30 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["cyclops_stray"] = {
		tier = "I - Doorstep", displayName = "One Eye, One Purpose",
		kind = "single", target = "Cyclops", requiredCount = 50,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["gargoyle_stray"] = {
		tier = "I - Doorstep", displayName = "Stone That Moves",
		kind = "single", target = "Gargoyle", requiredCount = 50,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["mummy_stray"] = {
		tier = "I - Doorstep", displayName = "Wrapped and Still Angry",
		kind = "single", target = "Mummy", requiredCount = 50,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["mutated_human_stray"] = {
		tier = "I - Doorstep", displayName = "They Were People Once",
		kind = "single", target = "Mutated Human", requiredCount = 50,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["terramite_stray"] = {
		tier = "I - Doorstep", displayName = "Under the Sand",
		kind = "single", target = "Terramite", requiredCount = 40,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},
	["mammoth_stray"] = {
		tier = "I - Doorstep", displayName = "The Old Giants of the Ice",
		kind = "single", target = "Mammoth", requiredCount = 40,
		repeatable = true, minRank = 0,
		rewards = {
			guaranteed = { xpPercent = 1, reputation = 95, marks = 35 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "very_early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "very_early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "very_early_rare_pool" },
			},
		},
	},

	-- ── II - Outskirts · rank 1 · 18 hunts ──────────────────
	["quara_mantassin_scout_tracker"] = {
		tier = "II - Outskirts", displayName = "Scouts in the Shallows",
		kind = "single", target = "Quara Mantassin Scout", requiredCount = 200,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 170, marks = 60 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["minotaur_mage_tracker"] = {
		tier = "II - Outskirts", displayName = "Horns and Sorcery",
		kind = "single", target = "Minotaur Mage", requiredCount = 200,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 120, marks = 40 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["gozzler_tracker"] = {
		tier = "II - Outskirts", displayName = "Greedy Little Things",
		kind = "single", target = "Gozzler", requiredCount = 200,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 185, marks = 65 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["quara_constrictor_scout_tracker"] = {
		tier = "II - Outskirts", displayName = "Coils in the Current",
		kind = "single", target = "Quara Constrictor Scout", requiredCount = 140,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 240, marks = 80 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["cyclops_smith_tracker"] = {
		tier = "II - Outskirts", displayName = "The Forge in the Cave",
		kind = "single", target = "Cyclops Smith", requiredCount = 150,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 250, marks = 85 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["orc_leader_tracker"] = {
		tier = "II - Outskirts", displayName = "Cut the Head Off",
		kind = "single", target = "Orc Leader", requiredCount = 140,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 240, marks = 80 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["elder_bonelord_tracker"] = {
		tier = "II - Outskirts", displayName = "Too Many Eyes",
		kind = "single", target = "Elder Bonelord", requiredCount = 130,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 250, marks = 85 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["ice_golem_tracker"] = {
		tier = "II - Outskirts", displayName = "Cold That Walks",
		kind = "single", target = "Ice Golem", requiredCount = 170,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 250, marks = 85 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["acolyte_of_the_cult_tracker"] = {
		tier = "II - Outskirts", displayName = "Faith in the Wrong Thing",
		kind = "single", target = "Acolyte of the Cult", requiredCount = 170,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 250, marks = 85 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["quara_predator_scout_tracker"] = {
		tier = "II - Outskirts", displayName = "Hunters of the Deep Shelf",
		kind = "single", target = "Quara Predator Scout", requiredCount = 70,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 240, marks = 80 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["mutated_rat_tracker"] = {
		tier = "II - Outskirts", displayName = "The Sewers Changed Them",
		kind = "single", target = "Mutated Rat", requiredCount = 120,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 250, marks = 85 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["necromancer_tracker"] = {
		tier = "II - Outskirts", displayName = "Stop Him Raising More",
		kind = "single", target = "Necromancer", requiredCount = 110,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 245, marks = 85 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["bonebeast_tracker"] = {
		tier = "II - Outskirts", displayName = "Held Together By Spite",
		kind = "single", target = "Bonebeast", requiredCount = 130,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 250, marks = 85 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["quara_pincher_scout_tracker"] = {
		tier = "II - Outskirts", displayName = "Claws Below the Waterline",
		kind = "single", target = "Quara Pincher Scout", requiredCount = 80,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 240, marks = 80 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["dragon_tracker"] = {
		tier = "II - Outskirts", displayName = "Your First Dragon",
		kind = "single", target = "Dragon", requiredCount = 70,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 250, marks = 85 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["ancient_scarab_tracker"] = {
		tier = "II - Outskirts", displayName = "Older Than the Tombs",
		kind = "single", target = "Ancient Scarab", requiredCount = 70,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 250, marks = 85 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["quara_hydromancer_scout_tracker"] = {
		tier = "II - Outskirts", displayName = "They Call the Water",
		kind = "single", target = "Quara Hydromancer Scout", requiredCount = 60,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 250, marks = 85 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},
	["crystal_spider_tracker"] = {
		tier = "II - Outskirts", displayName = "Webs of Glass",
		kind = "single", target = "Crystal Spider", requiredCount = 50,
		repeatable = true, minRank = 1,
		rewards = {
			guaranteed = { xpPercent = 0.9, reputation = 240, marks = 80 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 800, pool = "early_normal_pool" },
				{ tier = "uncommon", weight = 180, pool = "early_uncommon_pool" },
				{ tier = "rare", weight = 20, pool = "early_rare_pool" },
			},
		},
	},

	-- ── III - Far Roads · rank 2 · 22 hunts ──────────────────
	["mutated_bat_hunter"] = {
		tier = "III - Far Roads", displayName = "Wings from the Rot",
		kind = "single", target = "Mutated Bat", requiredCount = 300,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 495, marks = 160 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["askarak_demon_hunter"] = {
		tier = "III - Far Roads", displayName = "Small Demons, Real Ones",
		kind = "single", target = "Askarak Demon", requiredCount = 225,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 615, marks = 205 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["blood_priest_hunter"] = {
		tier = "III - Far Roads", displayName = "Their Altars Run Red",
		kind = "single", target = "Blood Priest", requiredCount = 300,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 450, marks = 150 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["brimstone_bug_hunter"] = {
		tier = "III - Far Roads", displayName = "They Bite Through Stone",
		kind = "single", target = "Brimstone Bug", requiredCount = 275,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 640, marks = 210 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["giant_spider_hunter"] = {
		tier = "III - Far Roads", displayName = "The Web Across the Road",
		kind = "single", target = "Giant Spider", requiredCount = 275,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 640, marks = 210 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["quara_hydromancer_hunter"] = {
		tier = "III - Far Roads", displayName = "Masters of the Tide",
		kind = "single", target = "Quara Hydromancer", requiredCount = 300,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 605, marks = 200 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["massive_energy_elemental_hunter"] = {
		tier = "III - Far Roads", displayName = "Lightning With a Shape",
		kind = "single", target = "Massive Energy Elemental", requiredCount = 300,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 605, marks = 200 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["boogy_hunter"] = {
		tier = "III - Far Roads", displayName = "What the Fey Sent",
		kind = "single", target = "Boogy", requiredCount = 275,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 640, marks = 210 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["ogre_savage_hunter"] = {
		tier = "III - Far Roads", displayName = "No Words, Only Clubs",
		kind = "single", target = "Ogre Savage", requiredCount = 250,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 640, marks = 210 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["minotaur_cult_follower_hunter"] = {
		tier = "III - Far Roads", displayName = "The Horned Faithful",
		kind = "single", target = "Minotaur Cult Follower", requiredCount = 225,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 640, marks = 210 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["braindeath_hunter"] = {
		tier = "III - Far Roads", displayName = "It Thinks. Do Not Let It.",
		kind = "single", target = "Braindeath", requiredCount = 275,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 615, marks = 200 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["lizard_legionnaire_hunter"] = {
		tier = "III - Far Roads", displayName = "The Zaoan Line",
		kind = "single", target = "Lizard Legionnaire", requiredCount = 250,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 640, marks = 210 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["souleater_hunter"] = {
		tier = "III - Far Roads", displayName = "It Takes More Than Your Life",
		kind = "single", target = "Souleater", requiredCount = 300,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 605, marks = 200 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["lizard_dragon_priest_hunter"] = {
		tier = "III - Far Roads", displayName = "They Pray to Dragons",
		kind = "single", target = "Lizard Dragon Priest", requiredCount = 250,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 640, marks = 210 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["nightmare_scion_hunter"] = {
		tier = "III - Far Roads", displayName = "Born of Bad Sleep",
		kind = "single", target = "Nightmare Scion", requiredCount = 250,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 640, marks = 210 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["lizard_high_guard_hunter"] = {
		tier = "III - Far Roads", displayName = "The Emperor's Wall",
		kind = "single", target = "Lizard High Guard", requiredCount = 190,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 625, marks = 205 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["werebadger_hunter"] = {
		tier = "III - Far Roads", displayName = "Small, Furious, Cursed",
		kind = "single", target = "Werebadger", requiredCount = 200,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 620, marks = 205 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["lizard_zaogun_hunter"] = {
		tier = "III - Far Roads", displayName = "Officers of the Scale",
		kind = "single", target = "Lizard Zaogun", requiredCount = 120,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 640, marks = 210 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["werewolf_hunter"] = {
		tier = "III - Far Roads", displayName = "Under a Full Moon",
		kind = "single", target = "Werewolf", requiredCount = 180,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 640, marks = 210 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["lizard_magistratus_hunter"] = {
		tier = "III - Far Roads", displayName = "They Pass Judgement",
		kind = "single", target = "Lizard Magistratus", requiredCount = 80,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 640, marks = 210 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["lizard_noble_hunter"] = {
		tier = "III - Far Roads", displayName = "Blood of the Scaled Court",
		kind = "single", target = "Lizard Noble", requiredCount = 80,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 640, marks = 210 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},
	["lizard_chosen_hunter"] = {
		tier = "III - Far Roads", displayName = "Chosen For What, They Never Say",
		kind = "single", target = "Lizard Chosen", requiredCount = 110,
		repeatable = true, minRank = 2,
		rewards = {
			guaranteed = { xpPercent = 0.75, reputation = 615, marks = 200 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "established_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "established_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "established_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "established_very_rare_pool" },
			},
		},
	},

	-- ── IV - Deep Country · rank 3 · 18 hunts ──────────────────
	["nightmare_veteran"] = {
		tier = "IV - Deep Country", displayName = "Ride Them Down",
		kind = "single", target = "Nightmare", requiredCount = 500,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1395, marks = 450 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["hydra_veteran"] = {
		tier = "IV - Deep Country", displayName = "Cut One, Two Return",
		kind = "single", target = "Hydra", requiredCount = 500,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1215, marks = 390 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["werelioness_veteran"] = {
		tier = "IV - Deep Country", displayName = "The Pride Hunts Back",
		kind = "single", target = "Werelioness", requiredCount = 500,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1550, marks = 500 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["white_lion_veteran"] = {
		tier = "IV - Deep Country", displayName = "Snow and Teeth",
		kind = "single", target = "White Lion", requiredCount = 500,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1395, marks = 450 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["destroyer_veteran"] = {
		tier = "IV - Deep Country", displayName = "Engines of Ruin",
		kind = "single", target = "Destroyer", requiredCount = 400,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1530, marks = 495 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["behemoth_veteran"] = {
		tier = "IV - Deep Country", displayName = "Big, Slow, Unbothered",
		kind = "single", target = "Behemoth", requiredCount = 375,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1550, marks = 500 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["hellspawn_veteran"] = {
		tier = "IV - Deep Country", displayName = "Spawn of the Lower Pits",
		kind = "single", target = "Hellspawn", requiredCount = 425,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1535, marks = 495 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["pirat_artillerist_veteran"] = {
		tier = "IV - Deep Country", displayName = "They Brought Cannons",
		kind = "single", target = "Pirat Artillerist", requiredCount = 500,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1395, marks = 450 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["stone_devourer_veteran"] = {
		tier = "IV - Deep Country", displayName = "It Eats the Mountain",
		kind = "single", target = "Stone Devourer", requiredCount = 350,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1520, marks = 490 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["deepling_elite_veteran"] = {
		tier = "IV - Deep Country", displayName = "The Deep Sends Its Best",
		kind = "single", target = "Deepling Elite", requiredCount = 475,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1550, marks = 500 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["serpent_spawn_veteran"] = {
		tier = "IV - Deep Country", displayName = "Coils in the Old Forest",
		kind = "single", target = "Serpent Spawn", requiredCount = 500,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1550, marks = 500 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["draken_spellweaver_veteran"] = {
		tier = "IV - Deep Country", displayName = "Scales and Spellwork",
		kind = "single", target = "Draken Spellweaver", requiredCount = 300,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1550, marks = 500 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["warlock_veteran"] = {
		tier = "IV - Deep Country", displayName = "They Studied Too Long",
		kind = "single", target = "Warlock", requiredCount = 425,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1535, marks = 495 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["infernalist_veteran"] = {
		tier = "IV - Deep Country", displayName = "He Opened the Wrong Door",
		kind = "single", target = "Infernalist", requiredCount = 400,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1510, marks = 485 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["medusa_veteran"] = {
		tier = "IV - Deep Country", displayName = "Do Not Meet Her Eyes",
		kind = "single", target = "Medusa", requiredCount = 325,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1510, marks = 490 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["ghastly_dragon_veteran"] = {
		tier = "IV - Deep Country", displayName = "The Ghastly Roads",
		kind = "single", target = "Ghastly Dragon", requiredCount = 190,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1530, marks = 495 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["demon_veteran"] = {
		tier = "IV - Deep Country", displayName = "A Real Demon, Finally",
		kind = "single", target = "Demon", requiredCount = 180,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1525, marks = 490 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},
	["undead_dragon_veteran"] = {
		tier = "IV - Deep Country", displayName = "It Died and Kept Flying",
		kind = "single", target = "Undead Dragon", requiredCount = 180,
		repeatable = true, minRank = 3,
		rewards = {
			guaranteed = { xpPercent = 0.6, reputation = 1550, marks = 500 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "midgame_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "midgame_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "midgame_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "midgame_very_rare_pool" },
			},
		},
	},

	-- ── V - The Wilds · rank 4 · 19 hunts ──────────────────
	["ripper_spectre_beastslayer"] = {
		tier = "V - The Wilds", displayName = "It Tears Without Hands",
		kind = "single", target = "Ripper Spectre", requiredCount = 900,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 2225, marks = 730 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["retching_horror_beastslayer"] = {
		tier = "V - The Wilds", displayName = "Do Not Look Too Long",
		kind = "single", target = "Retching Horror", requiredCount = 900,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 3100, marks = 1020 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["arachnophobica_beastslayer"] = {
		tier = "V - The Wilds", displayName = "Every Fear at Once",
		kind = "single", target = "Arachnophobica", requiredCount = 900,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 2925, marks = 965 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["crazed_summer_rearguard_beastslayer"] = {
		tier = "V - The Wilds", displayName = "The Summer Court Broke",
		kind = "single", target = "Crazed Summer Rearguard", requiredCount = 900,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 3100, marks = 1020 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["crazed_winter_rearguard_beastslayer"] = {
		tier = "V - The Wilds", displayName = "The Winter Court Followed",
		kind = "single", target = "Crazed Winter Rearguard", requiredCount = 900,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 3040, marks = 1000 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["mitmah_seer_beastslayer"] = {
		tier = "V - The Wilds", displayName = "They See You Coming",
		kind = "single", target = "Mitmah Seer", requiredCount = 900,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 2705, marks = 890 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["feral_werecrocodile_beastslayer"] = {
		tier = "V - The Wilds", displayName = "Jaws of the Swamp",
		kind = "single", target = "Feral Werecrocodile", requiredCount = 775,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 3225, marks = 1060 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["ogre_sage_beastslayer"] = {
		tier = "V - The Wilds", displayName = "Old Ogres Are Worse",
		kind = "single", target = "Ogre Sage", requiredCount = 900,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 2810, marks = 925 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["grim_reaper_beastslayer"] = {
		tier = "V - The Wilds", displayName = "He Has Come For Someone",
		kind = "single", target = "Grim Reaper", requiredCount = 900,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 2280, marks = 750 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["hateful_soul_beastslayer"] = {
		tier = "V - The Wilds", displayName = "It Remembers Being Wronged",
		kind = "single", target = "Hateful Soul", requiredCount = 250,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 3250, marks = 1070 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["makara_beastslayer"] = {
		tier = "V - The Wilds", displayName = "The Thing in the Delta",
		kind = "single", target = "Makara", requiredCount = 900,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 2955, marks = 975 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["orewalker_beastslayer"] = {
		tier = "V - The Wilds", displayName = "Iron That Walks",
		kind = "single", target = "Orewalker", requiredCount = 700,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 3250, marks = 1070 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["burster_spectre_beastslayer"] = {
		tier = "V - The Wilds", displayName = "It Comes Apart Loudly",
		kind = "single", target = "Burster Spectre", requiredCount = 775,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 3250, marks = 1070 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["young_goanna_beastslayer"] = {
		tier = "V - The Wilds", displayName = "The Sunlands Bite",
		kind = "single", target = "Young Goanna", requiredCount = 800,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 3225, marks = 1060 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["vexclaw_beastslayer"] = {
		tier = "V - The Wilds", displayName = "Claws in the Dark",
		kind = "single", target = "Vexclaw", requiredCount = 600,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 3250, marks = 1070 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["thanatursus_beastslayer"] = {
		tier = "V - The Wilds", displayName = "Bear-Shaped Nightmare",
		kind = "single", target = "Thanatursus", requiredCount = 700,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 3250, marks = 1070 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["deathling_spellsinger_beastslayer"] = {
		tier = "V - The Wilds", displayName = "Hymns of the Drowned Choir",
		kind = "single", target = "Deathling Spellsinger", requiredCount = 700,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 3250, marks = 1070 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["priestess_of_the_wild_sun_beastslayer"] = {
		tier = "V - The Wilds", displayName = "Their Sun Is Not Ours",
		kind = "single", target = "Priestess of the Wild Sun", requiredCount = 600,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 3250, marks = 1070 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},
	["cliff_strider_beastslayer"] = {
		tier = "V - The Wilds", displayName = "It Steps Over Mountains",
		kind = "single", target = "Cliff Strider", requiredCount = 525,
		repeatable = true, minRank = 4,
		rewards = {
			guaranteed = { xpPercent = 0.5, reputation = 3210, marks = 1055 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 700, pool = "highlevel_normal_pool" },
				{ tier = "uncommon", weight = 220, pool = "highlevel_uncommon_pool" },
				{ tier = "rare", weight = 70, pool = "highlevel_rare_pool" },
				{ tier = "very_rare", weight = 10, pool = "highlevel_very_rare_pool" },
			},
		},
	},

	-- ── VI - The Frontier · rank 5 · 14 hunts ──────────────────
	["quara_plunderer_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "The Deep Comes Raiding",
		kind = "single", target = "Quara Plunderer", requiredCount = 1400,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 6015, marks = 1975 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
	["sulphur_spouter_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "It Breathes the Pit",
		kind = "single", target = "Sulphur Spouter", requiredCount = 1150,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 6950, marks = 2285 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
	["hellflayer_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "Flayers of the Infernal Gate",
		kind = "single", target = "Hellflayer", requiredCount = 1400,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 6235, marks = 2050 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
	["headpecker_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "Aim For the Legs",
		kind = "single", target = "Headpecker", requiredCount = 1350,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 7000, marks = 2300 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
	["hulking_prehemoth_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "Older Than the Mountains",
		kind = "single", target = "Hulking Prehemoth", requiredCount = 1050,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 6915, marks = 2270 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
	["gorerilla_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "The Canopy Screams",
		kind = "single", target = "Gorerilla", requiredCount = 1300,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 6970, marks = 2290 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
	["cursed_book_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "Do Not Read It",
		kind = "single", target = "Cursed Book", requiredCount = 1100,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 7000, marks = 2300 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
	["shrieking_cry_stal_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "The Sound Comes First",
		kind = "single", target = "Shrieking Cry-Stal", requiredCount = 1050,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 6900, marks = 2265 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
	["brachiodemon_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "The Many-Limbed Horror",
		kind = "single", target = "Brachiodemon", requiredCount = 875,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 6960, marks = 2285 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
	["infernal_demon_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "Herald of the Soul War",
		kind = "single", target = "Infernal Demon", requiredCount = 700,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 7000, marks = 2300 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
	["elite_pirat_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "The Best They Have",
		kind = "single", target = "Elite Pirat", requiredCount = 1100,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 7000, marks = 2300 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
	["many_faces_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "The Thousand Masks",
		kind = "single", target = "Many Faces", requiredCount = 725,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 6920, marks = 2275 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
	["distorted_phantom_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "Echoes That Should Not Be",
		kind = "single", target = "Distorted Phantom", requiredCount = 850,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 7000, marks = 2300 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
	["bony_sea_devil_masterhunter"] = {
		tier = "VI - The Frontier", displayName = "Bones of the Drowned Court",
		kind = "single", target = "Bony Sea Devil", requiredCount = 925,
		repeatable = true, minRank = 5,
		rewards = {
			guaranteed = { xpPercent = 0.4, reputation = 7000, marks = 2300 },
			firstMastery = { xpPercentBonus = 0.30, reputationMult = 3.0, marksMult = 2.0, rareRollBonus = 0.10 },
			rareTable = {
				{ tier = "normal", weight = 650, pool = "endgame_normal_pool" },
				{ tier = "uncommon", weight = 250, pool = "endgame_uncommon_pool" },
				{ tier = "rare", weight = 90, pool = "endgame_rare_pool" },
				{ tier = "very_rare", weight = 9, pool = "endgame_very_rare_pool" },
				{ tier = "jackpot", weight = 1, pool = "endgame_jackpot_pool" },
			},
		},
	},
}

-- Each pool's `items` list is what rollRareTier (bao_reward.lua) actually
-- rolls against and grants — a pool with several entries is itself a
-- weighted pick (entry.weight, default 1). `category` is kept as a human-
-- readable label only; nothing reads it at runtime. All item ids below are
-- real, verified against data/items/items.xml (equipment) or against this
-- project's own earlier potion-range audit (data/lib/gamelib item survey
-- done for the hotkey-blocking work) — never invented. Pools are shared
-- across every hunt in a tier (see rareTable.pool on BaoConfig.Hunts above),
-- so a pool's contents apply to all hunts of that tier, not just one.
BaoConfig.RewardPools = {
	-- Home Range (troll/rat/spider/... tier) — no very_rare/jackpot band.
	very_early_normal_pool = { category = "supplies_basic", items = {
		{ itemId = 7876, count = 5 },  -- small health potion
		{ itemId = 266, count = 3 },   -- health potion
	} },
	very_early_uncommon_pool = { category = "supplies_basic", items = {
		{ itemId = 266, count = 8 },   -- health potion
		{ itemId = 268, count = 8 },   -- mana potion
	} },
	very_early_rare_pool = { category = "equipment_common", items = {
		{ itemId = 3552, count = 1 },  -- leather boots
		{ itemId = 3355, count = 1 },  -- leather helmet
		{ itemId = 3412, count = 1 },  -- wooden shield
		{ itemId = 3268, count = 1 },  -- hand axe
	} },

	-- Near Trails (amazon/orc/minotaur bruiser tier) — no very_rare/jackpot band.
	early_normal_pool = { category = "supplies_basic", items = {
		{ itemId = 266, count = 8 },   -- health potion
		{ itemId = 268, count = 8 },   -- mana potion
	} },
	early_uncommon_pool = { category = "equipment_common", items = {
		{ itemId = 3267, count = 1 },  -- dagger
		{ itemId = 3354, count = 1 },  -- brass helmet
		{ itemId = 3378, count = 1 },  -- studded armor
	} },
	early_rare_pool = { category = "equipment_uncommon", items = {
		{ itemId = 3273, count = 1, weight = 35 }, -- sabre
		{ itemId = 3286, count = 1, weight = 35 }, -- mace
		{ itemId = 3410, count = 1, weight = 20 }, -- plate shield
		{ itemId = 3264, count = 1, weight = 10 }, -- sword
	} },

	-- Old Roads (dragon lord hatchling/hero/frost dragon/sea serpent tier).
	established_normal_pool = { category = "supplies_mid", items = {
		{ itemId = 266, count = 12 },  -- health potion
		{ itemId = 268, count = 12 },  -- mana potion
	} },
	established_uncommon_pool = { category = "equipment_uncommon", items = {
		{ itemId = 3382, count = 1 },  -- crown legs
		{ itemId = 3557, count = 1 },  -- plate legs
		{ itemId = 3297, count = 1 },  -- serpent sword
	} },
	established_rare_pool = { category = "equipment_rare", items = {
		{ itemId = 3265, count = 1, weight = 30 }, -- two handed sword
		{ itemId = 3386, count = 1, weight = 25 }, -- dragon scale mail
		{ itemId = 3280, count = 1, weight = 20 }, -- fire sword
		{ itemId = 3279, count = 1, weight = 15 }, -- war hammer
		{ itemId = 3428, count = 1, weight = 10 }, -- tower shield
	} },
	established_very_rare_pool = { category = "equipment_very_rare", items = {
		{ itemId = 3284, count = 1, weight = 35 }, -- ice rapier
		{ itemId = 3051, count = 1, weight = 30 }, -- energy ring
		{ itemId = 3049, count = 1, weight = 25 }, -- stealth ring
		{ itemId = 3048, count = 1, weight = 10 }, -- might ring
	} },

	-- Deep Country (hellhound/destroyer/werecrocodile tier).
	midgame_normal_pool = { category = "supplies_mid", items = {
		{ itemId = 266, count = 20 },  -- health potion
		{ itemId = 268, count = 20 },  -- mana potion
	} },
	midgame_uncommon_pool = { category = "equipment_rare", items = {
		{ itemId = 3556, count = 1 },  -- crocodile boots
		{ itemId = 818, count = 1 },   -- magma boots
		{ itemId = 3357, count = 1 },  -- plate armor
		{ itemId = 3383, count = 1 },  -- dark armor
	} },
	midgame_rare_pool = { category = "equipment_rare", items = {
		{ itemId = 3318, count = 1, weight = 25 }, -- knight axe
		{ itemId = 6553, count = 1, weight = 25 }, -- ruthless axe
		{ itemId = 7419, count = 1, weight = 20 }, -- dreaded cleaver
		{ itemId = 7421, count = 1, weight = 20 }, -- onyx flail
		{ itemId = 821, count = 1, weight = 10 },  -- magma legs
	} },
	midgame_very_rare_pool = { category = "equipment_very_rare", items = {
		{ itemId = 7427, count = 1, weight = 30 }, -- chaos mace
		{ itemId = 7428, count = 1, weight = 30 }, -- bonebreaker
		{ itemId = 826, count = 1, weight = 25 },  -- magma coat
		{ itemId = 817, count = 1, weight = 15 },  -- magma amulet
	} },

	-- Far Wilds (ghastly dragon/knowledge elemental/day-night harpy tier).
	highlevel_normal_pool = { category = "supplies_high", items = {
		{ itemId = 266, count = 25 },  -- health potion
		{ itemId = 268, count = 25 },  -- mana potion
	} },
	highlevel_uncommon_pool = { category = "equipment_rare", items = {
		{ itemId = 10386, count = 1 }, -- Zaoan shoes
		{ itemId = 813, count = 1 },   -- terra boots
		{ itemId = 10387, count = 1 }, -- Zaoan legs
		{ itemId = 812, count = 1 },   -- terra legs
	} },
	highlevel_rare_pool = { category = "equipment_very_rare", items = {
		{ itemId = 10385, count = 1, weight = 30 }, -- Zaoan helmet
		{ itemId = 10384, count = 1, weight = 25 }, -- Zaoan armor
		{ itemId = 10438, count = 1, weight = 25 }, -- spellweaver's robe
		{ itemId = 10323, count = 1, weight = 20 }, -- guardian boots
	} },
	highlevel_very_rare_pool = { category = "equipment_mythic", items = {
		{ itemId = 10390, count = 1, weight = 40 }, -- Zaoan sword
		{ itemId = 10388, count = 1, weight = 35 }, -- drakinata
		{ itemId = 8083, count = 1, weight = 25 },  -- wand of cosmic energy
	} },

	-- Black Frontier (vexclaw/grimeleech/hellflayer/juggernaut tier).
	endgame_normal_pool = { category = "supplies_high", items = {
		{ itemId = 266, count = 40 },  -- health potion
		{ itemId = 268, count = 40 },  -- mana potion
	} },
	endgame_uncommon_pool = { category = "equipment_very_rare", items = {
		{ itemId = 3356, count = 1 },  -- devil helmet
		{ itemId = 3364, count = 1 },  -- golden legs
		{ itemId = 3370, count = 1 },  -- knight armor
		{ itemId = 22726, count = 1 }, -- rift shield
	} },
	endgame_rare_pool = { category = "equipment_very_rare", items = {
		{ itemId = 3360, count = 1, weight = 25 },  -- golden armor
		{ itemId = 3366, count = 1, weight = 25 },  -- magic plate armor
		{ itemId = 3414, count = 1, weight = 20 },  -- mastermind shield
		{ itemId = 3420, count = 1, weight = 20 },  -- demon shield
		{ itemId = 8074, count = 1, weight = 10 },  -- spellbook of mind control
	} },
	endgame_very_rare_pool = { category = "equipment_mythic", items = {
		{ itemId = 22866, count = 1, weight = 25 }, -- rift bow
		{ itemId = 22867, count = 1, weight = 25 }, -- rift crossbow
		{ itemId = 22727, count = 1, weight = 20 }, -- rift lance
		{ itemId = 7413, count = 1, weight = 20 },  -- titan axe
		{ itemId = 3342, count = 1, weight = 10 },  -- war axe
	} },
	endgame_jackpot_pool = { category = "legendary", items = {
		{ itemId = 8061, count = 1, weight = 40 },  -- skullcracker armor
		{ itemId = 7382, count = 1, weight = 20 },  -- demonrage sword
	} },

	-- World's End pools — added in the Phase 10 content-population pass
	-- alongside the tier's first real hunts. Reachability caveat: the most
	-- powerful real items in this datapack are gated at level 270-600
	-- (norcferatu/falcon/sanguine sets), likely far beyond what's reachable
	-- at this server's flat exp rate — those are reserved for the jackpot
	-- pool only, as aspirational trophy pulls, not an expectation every
	-- puller can equip immediately. Lower bands use strong-but-reachable
	-- endgame gear (level 100-150) plus Ferumbras' Hat, a real no-level-gate
	-- trophy item, so every band has at least one immediately usable pull.
	extreme_endgame_normal_pool = { category = "supplies_apex", items = {
		{ itemId = 266, count = 60 },  -- health potion
		{ itemId = 268, count = 60 },  -- mana potion
	} },
	extreme_endgame_uncommon_pool = { category = "equipment_mythic", items = {
		{ itemId = 37610, count = 1 }, -- green demon slippers
		{ itemId = 37609, count = 1 }, -- green demon helmet
	} },
	extreme_endgame_rare_pool = { category = "equipment_mythic", items = {
		{ itemId = 37607, count = 1, weight = 35 }, -- green demon legs
		{ itemId = 37608, count = 1, weight = 35 }, -- green demon armor
		{ itemId = 5903, count = 1, weight = 30 },  -- Ferumbras' Hat (no level gate)
	} },
	extreme_endgame_very_rare_pool = { category = "equipment_legendary", items = {
		{ itemId = 3309, count = 1, weight = 25 },  -- thunder hammer
		{ itemId = 7450, count = 1, weight = 20 },  -- hammer of prophecy
		{ itemId = 8054, count = 1, weight = 20 },  -- earthborn titan armor
		{ itemId = 8099, count = 1, weight = 20 },  -- dark trinity mace
		{ itemId = 22757, count = 1, weight = 15 }, -- shroud of despair
	} },
	extreme_endgame_jackpot_pool = { category = "legendary_apex", items = {
		{ itemId = 51262, count = 1 }, -- norcferatu tuskplate (level 270)
		{ itemId = 28719, count = 1 }, -- falcon plate (level 300)
		{ itemId = 28723, count = 1 }, -- falcon longsword (level 300)
		{ itemId = 43864, count = 1 }, -- sanguine blade (level 600)
		{ itemId = 43881, count = 1 }, -- sanguine greaves (level 500)
	} },
}

-- Per-tier ceiling on the guaranteed-XP formula in bao_reward.lua:
--   xp = min(monsterBaseXP * hunt.requiredCount * hunt.rewards.guaranteed.xpPercent, TierXPCap[hunt.tier])
-- These are a guardrail against a future misconfigured hunt (e.g. a typo'd
-- requiredCount or xpPercent), not a lever that's meant to ever bind on the
-- starter hunts above. Sized by computing what each starter hunt actually
-- produces unclamped (including the first-mastery xpPercentBonus, the larger
-- of the two cases) using real monster:experience() values, then rounding up
-- to a comfortably higher headroom:
--   Home Range   (troll_stray):                  540 guaranteed /    702 first-mastery
--   Near Trails        (amazon_tracker):              2880 guaranteed /   3744 first-mastery
--   Old Roads  (dragon_lord_hatchling_hunter): 67725 guaranteed /  89397 first-mastery
--   Deep Country      (hellhound_veteran):         1060800 guaranteed / 1379040 first-mastery
--   Far Wilds   (ghastly_dragon_beastslayer): 1380000 guaranteed / 1766400 first-mastery
--   Black Frontier      (vexclaw_masterhunter):       1999360 guaranteed / 2499200 first-mastery
--   Black Frontier      (infernal_family_masterhunter, weighted-avg base XP 8316): 4989600 guaranteed / 6486480 first-mastery
-- "VII - World's End" has no starter hunt yet (Phase 10 content), so its cap is
-- an estimate extrapolated from the Black Frontier -> World's End growth curve
-- implied by the rank table, not a measured value — revisit once real
-- World's End hunts exist.
-- Share of a hunt's experience paid on a REPEAT completion. The first mastery
-- pays in full (and then some, via firstMastery.xpPercentBonus); every
-- completion after that pays this fraction.
--
-- (!) This is the one number standing between "a task reward" and "a permanent
-- experience multiplier". Every hunt is repeatable with no cooldown, so at 1.0
-- a player who keeps three slots filled is simply playing on double rates.
-- Dormant gear granted by hunt masteries.
--
-- (!) Bao never grants a plain item. Anything that comes out of this table is
-- rolled DORMANT (RarityStats.rollRarity(item, true)) -- unrevealed until the
-- player wakes it at a Dormant Shrine or with a Dormant Waker, and Bao already
-- sells the Dormancy Rune in his own shop. The hunt pays the Dormant, the shop
-- sells the way to open it, and the rarity system decides what it becomes.
--
-- `chance` is the percent of masteries that pay gear instead of supplies,
-- doubled on a first mastery. `vocs` is the list of BASE vocation ids that may
-- use the item (1 sorcerer, 2 druid, 3 paladin, 4 knight); empty means anyone.
-- The grant filters to the player's own vocation plus the open entries, so a
-- druid can never be handed a falcon plate.
--
-- `class` 1-5 is how hard the item is to get within its chapter (1 common,
-- 5 the chapter prize) and sets the draw weight. GENERATED by
-- scratchpad/build_gear.js -- re-run it rather than hand-editing.
BaoConfig.GearClassWeight = { 40, 26, 17, 11, 6 }

BaoConfig.GearPools = {
	["I - Doorstep"] = { chance = 4, items = {
		{ id = 3391, class = 1, vocs = {} }, -- crusader helmet
		{ id = 3385, class = 1, vocs = {} }, -- crown helmet
		{ id = 3382, class = 1, vocs = {4, 3} }, -- crown legs
		{ id = 3370, class = 2, vocs = {4, 3} }, -- knight armor
		{ id = 7438, class = 2, vocs = {} }, -- elvish bow
		{ id = 3271, class = 3, vocs = {} }, -- spike sword
		{ id = 3434, class = 3, vocs = {} }, -- vampire shield
		{ id = 3323, class = 4, vocs = {} }, -- dwarven axe (lvl 20)
		{ id = 3322, class = 4, vocs = {} }, -- dragon hammer (lvl 25)
		{ id = 3416, class = 5, vocs = {} }, -- dragon shield
		{ id = 3079, class = 5, vocs = {} }, -- boots of haste
		{ id = 3280, class = 5, vocs = {} }, -- fire sword (lvl 30)
	} },
	["II - Outskirts"] = { chance = 4.5, items = {
		{ id = 8063, class = 1, vocs = {3} }, -- paladin armor
		{ id = 8043, class = 1, vocs = {1, 2} }, -- focus cape
		{ id = 3295, class = 1, vocs = {} }, -- bright sword (lvl 30)
		{ id = 7407, class = 2, vocs = {4} }, -- haunted blade (lvl 30)
		{ id = 3067, class = 2, vocs = {2} }, -- hailstorm rod (lvl 33)
		{ id = 7456, class = 2, vocs = {} }, -- noble axe (lvl 35)
		{ id = 14040, class = 3, vocs = {} }, -- warrior's axe (lvl 40)
		{ id = 8029, class = 3, vocs = {3} }, -- silkweaver bow (lvl 40)
		{ id = 8094, class = 3, vocs = {1} }, -- wand of voodoo (lvl 42)
		{ id = 3312, class = 4, vocs = {} }, -- silver mace (lvl 45)
		{ id = 9103, class = 4, vocs = {1, 2} }, -- batwing hat (lvl 50)
		{ id = 3392, class = 5, vocs = {} }, -- royal helmet
		{ id = 3420, class = 5, vocs = {} }, -- demon shield
	} },
	["III - Far Roads"] = { chance = 5, items = {
		{ id = 10387, class = 1, vocs = {} }, -- Zaoan legs
		{ id = 10385, class = 1, vocs = {4, 3} }, -- Zaoan helmet
		{ id = 10384, class = 1, vocs = {4, 3} }, -- Zaoan armor (lvl 50)
		{ id = 7382, class = 2, vocs = {4} }, -- demonrage sword (lvl 60)
		{ id = 3340, class = 2, vocs = {} }, -- heavy mace (lvl 70)
		{ id = 6527, class = 2, vocs = {4} }, -- avenger (lvl 75)
		{ id = 8864, class = 3, vocs = {1, 2} }, -- yalahari mask (lvl 80)
		{ id = 8026, class = 3, vocs = {3} }, -- warsinger bow (lvl 80)
		{ id = 16163, class = 3, vocs = {3} }, -- crystal crossbow (lvl 90)
		{ id = 3303, class = 4, vocs = {4} }, -- great axe (lvl 95)
		{ id = 11689, class = 4, vocs = {3} }, -- elite draken helmet (lvl 100)
		{ id = 8060, class = 4, vocs = {3} }, -- master archer's armor (lvl 100)
		{ id = 3387, class = 5, vocs = {} }, -- demon helmet
		{ id = 3414, class = 5, vocs = {} }, -- mastermind shield
		{ id = 3366, class = 5, vocs = {4, 3} }, -- magic plate armor
	} },
	["IV - Deep Country"] = { chance = 5.5, items = {
		{ id = 23474, class = 1, vocs = {1, 2} }, -- tiara of power (lvl 100)
		{ id = 16162, class = 1, vocs = {} }, -- mycological mace (lvl 120)
		{ id = 16161, class = 1, vocs = {} }, -- crystalline axe (lvl 120)
		{ id = 16110, class = 1, vocs = {4, 3} }, -- prismatic armor (lvl 120)
		{ id = 22866, class = 2, vocs = {3} }, -- rift bow (lvl 120)
		{ id = 14000, class = 2, vocs = {4} }, -- ornate shield (lvl 130)
		{ id = 8023, class = 2, vocs = {3} }, -- royal crossbow (lvl 130)
		{ id = 22755, class = 2, vocs = {1, 2} }, -- book of lies (lvl 150)
		{ id = 16104, class = 3, vocs = {1, 2} }, -- gill gugel (lvl 150)
		{ id = 16105, class = 3, vocs = {1, 2} }, -- gill coat (lvl 150)
		{ id = 16106, class = 3, vocs = {1, 2} }, -- gill legs (lvl 150)
		{ id = 13997, class = 3, vocs = {4} }, -- depth calcei (lvl 150)
		{ id = 16109, class = 4, vocs = {4} }, -- prismatic helmet (lvl 150)
		{ id = 16111, class = 4, vocs = {3} }, -- prismatic legs (lvl 150)
		{ id = 16112, class = 4, vocs = {3} }, -- prismatic boots (lvl 150)
		{ id = 14768, class = 4, vocs = {3} }, -- thorn spitter (lvl 150)
	} },
	["V - The Wilds"] = { chance = 6, items = {
		{ id = 29427, class = 1, vocs = {3} }, -- dark whispers (lvl 180)
		{ id = 29428, class = 1, vocs = {3} }, -- sleep shawl (lvl 180)
		{ id = 29429, class = 1, vocs = {3} }, -- pendulet (lvl 180)
		{ id = 29423, class = 1, vocs = {1, 2} }, -- dream shroud (lvl 180)
		{ id = 29424, class = 1, vocs = {1, 2} }, -- pair of dreamwalkers (lvl 180)
		{ id = 29431, class = 1, vocs = {1, 2} }, -- spirit guide (lvl 180)
		{ id = 32618, class = 1, vocs = {1, 2} }, -- soulful legs (lvl 180)
		{ id = 13999, class = 2, vocs = {4} }, -- ornate legs (lvl 185)
		{ id = 27647, class = 2, vocs = {1, 2} }, -- gnome helmet (lvl 200)
		{ id = 27455, class = 2, vocs = {3} }, -- bow of destruction (lvl 200)
		{ id = 27456, class = 2, vocs = {3} }, -- crossbow of destruction (lvl 200)
		{ id = 27451, class = 2, vocs = {4} }, -- axe of destruction (lvl 200)
		{ id = 27649, class = 2, vocs = {1, 2} }, -- gnome legs (lvl 200)
		{ id = 27650, class = 3, vocs = {4, 3} }, -- gnome shield (lvl 200)
		{ id = 27450, class = 3, vocs = {4} }, -- slayer of destruction (lvl 200)
		{ id = 27453, class = 3, vocs = {4} }, -- mace of destruction (lvl 200)
		{ id = 29422, class = 3, vocs = {4} }, -- winterblade (lvl 200)
		{ id = 29421, class = 3, vocs = {4} }, -- summerblade (lvl 200)
		{ id = 27458, class = 3, vocs = {2} }, -- rod of destruction (lvl 200)
		{ id = 27457, class = 3, vocs = {1} }, -- wand of destruction (lvl 200)
		{ id = 31582, class = 4, vocs = {1} }, -- galea mortis (lvl 220)
		{ id = 30400, class = 4, vocs = {2} }, -- cobra rod (lvl 220)
		{ id = 34153, class = 4, vocs = {1, 2} }, -- lion spellbook (lvl 220)
		{ id = 32617, class = 4, vocs = {4, 3} }, -- fabulous legs (lvl 225)
		{ id = 31577, class = 4, vocs = {4} }, -- terra helmet (lvl 230)
		{ id = 34156, class = 4, vocs = {3} }, -- lion spangenhelm (lvl 230)
	} },
	["VI - The Frontier"] = { chance = 7, items = {
		{ id = 30396, class = 1, vocs = {4} }, -- cobra axe (lvl 220)
		{ id = 30398, class = 1, vocs = {4} }, -- cobra sword (lvl 220)
		{ id = 30395, class = 1, vocs = {4} }, -- cobra club (lvl 220)
		{ id = 34153, class = 1, vocs = {1, 2} }, -- lion spellbook (lvl 220)
		{ id = 36670, class = 1, vocs = {1} }, -- eldritch cowl (lvl 250)
		{ id = 36667, class = 1, vocs = {3} }, -- eldritch breeches (lvl 250)
		{ id = 31581, class = 1, vocs = {3} }, -- bow of cataclysm (lvl 250)
		{ id = 36664, class = 1, vocs = {3} }, -- eldritch bow (lvl 250)
		{ id = 39163, class = 2, vocs = {2} }, -- naga rod (lvl 250)
		{ id = 39162, class = 2, vocs = {1} }, -- naga wand (lvl 250)
		{ id = 36671, class = 2, vocs = {2} }, -- eldritch hood (lvl 250)
		{ id = 20072, class = 2, vocs = {4} }, -- umbral master axe (lvl 250)
		{ id = 20084, class = 2, vocs = {3} }, -- umbral master bow (lvl 250)
		{ id = 20087, class = 2, vocs = {3} }, -- umbral master crossbow (lvl 250)
		{ id = 36666, class = 2, vocs = {3} }, -- eldritch quiver (lvl 250)
		{ id = 39160, class = 2, vocs = {3} }, -- naga quiver (lvl 250)
		{ id = 20078, class = 3, vocs = {4} }, -- umbral master mace (lvl 250)
		{ id = 20066, class = 3, vocs = {4} }, -- umbral masterblade (lvl 250)
		{ id = 30397, class = 3, vocs = {4} }, -- cobra hood (lvl 270)
		{ id = 30399, class = 3, vocs = {1} }, -- cobra wand (lvl 270)
		{ id = 34157, class = 3, vocs = {4} }, -- lion plate (lvl 270)
		{ id = 34155, class = 3, vocs = {4} }, -- lion longsword (lvl 270)
		{ id = 34150, class = 3, vocs = {3} }, -- lion longbow (lvl 270)
		{ id = 28724, class = 3, vocs = {4} }, -- falcon battleaxe (lvl 300)
		{ id = 28715, class = 4, vocs = {4, 3} }, -- falcon coif (lvl 300)
		{ id = 28714, class = 4, vocs = {1, 2} }, -- falcon circlet (lvl 300)
		{ id = 28718, class = 4, vocs = {3} }, -- falcon bow (lvl 300)
		{ id = 28717, class = 4, vocs = {1} }, -- falcon wand (lvl 300)
		{ id = 28716, class = 4, vocs = {2} }, -- falcon rod (lvl 300)
		{ id = 28723, class = 4, vocs = {4} }, -- falcon longsword (lvl 300)
		{ id = 28719, class = 4, vocs = {4} }, -- falcon plate (lvl 300)
	} },
	["VII - World's End"] = { chance = 8, items = {
		{ id = 39149, class = 1, vocs = {3} }, -- alicorn headguard (lvl 400)
		{ id = 39153, class = 1, vocs = {2} }, -- arboreal crown (lvl 400)
		{ id = 39154, class = 1, vocs = {2} }, -- arboreal tome (lvl 400)
		{ id = 39151, class = 1, vocs = {1} }, -- arcanomancer regalia (lvl 400)
		{ id = 39152, class = 1, vocs = {1} }, -- arcanomancer folio (lvl 400)
		{ id = 39185, class = 1, vocs = {1} }, -- arcanomancer sigil (lvl 400)
		{ id = 34095, class = 2, vocs = {1} }, -- soulmantle (lvl 400)
		{ id = 34088, class = 2, vocs = {3} }, -- soulbleeder (lvl 400)
		{ id = 34091, class = 2, vocs = {2} }, -- soulhexer (lvl 400)
		{ id = 34087, class = 2, vocs = {4} }, -- soulmaimer (lvl 400)
		{ id = 34092, class = 2, vocs = {1} }, -- soulshanks (lvl 400)
		{ id = 34094, class = 3, vocs = {3} }, -- soulshell (lvl 400)
		{ id = 34096, class = 3, vocs = {2} }, -- soulshroud (lvl 400)
		{ id = 34083, class = 3, vocs = {4} }, -- soulshredder (lvl 400)
		{ id = 39147, class = 3, vocs = {4} }, -- spiritthorn armor (lvl 400)
		{ id = 39148, class = 3, vocs = {4} }, -- spiritthorn helmet (lvl 400)
		{ id = 34090, class = 3, vocs = {1} }, -- soultainter (lvl 400)
		{ id = 43881, class = 4, vocs = {3} }, -- sanguine greaves (lvl 500)
		{ id = 43884, class = 4, vocs = {1} }, -- sanguine boots (lvl 500)
		{ id = 43864, class = 4, vocs = {4} }, -- sanguine blade (lvl 600)
		{ id = 43882, class = 4, vocs = {1} }, -- sanguine coil (lvl 600)
		{ id = 43870, class = 4, vocs = {4} }, -- sanguine razor (lvl 600)
	} },
}

BaoConfig.RepeatXPFactor = 0.30

BaoConfig.TierXPCap = {
	["I - Doorstep"] = 20000,
	["II - Outskirts"] = 70000,
	["III - Far Roads"] = 350000,
	["IV - Deep Country"] = 1500000,
	["V - The Wilds"] = 5000000,
	["VI - The Frontier"] = 15000000,
	["VII - World's End"] = 40000000,
}
