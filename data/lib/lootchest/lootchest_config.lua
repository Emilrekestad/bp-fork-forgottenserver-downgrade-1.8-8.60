-- Loot Chest system -- config. Named pools (what can be granted) and named
-- tables (which pool(s) a chest actionid rolls against, plus its reuse
-- behavior). Mirrors data/lib/bao/bao_config.lua's data-only role: this file
-- holds no logic, only the numbers/items an owner would want to tune.

LootChestConfig = {}

-- Pools: a list of items. Each item has its own independent `chance` (0-100,
-- default 100 = always included) of being granted whenever this pool fires --
-- NOT a single weighted pick among them (that's what `pickOne` pools are
-- for, see rare_upgrade below). This is what lets one pool bundle "always
-- give tokens, always give coins, sometimes throw in a bonus extra" without
-- needing a separate tier per item.
LootChestConfig.Pools = {
	common_bundle = {
		items = {
			{ itemId = 22516, countMin = 3, countMax = 6 },             -- silver token, always
			{ itemId = 3035, countMin = 8, countMax = 20 },              -- platinum coin, always
			{ itemId = 239, countMin = 2, countMax = 4, chance = 40 },   -- great health potion, ~40% -- PLACEHOLDER for "some other stuff", swap freely
			{ itemId = 3028, countMin = 1, countMax = 1, chance = 15 },  -- small diamond, ~15% -- PLACEHOLDER
		},
	},

	-- `pickOne` pools work like bao_reward.lua's reward pools: a single
	-- weighted choice among the listed items, rather than each item rolling
	-- independently. Use this shape for a tier that should hand out exactly
	-- one prize even if it later grows to offer a choice of several
	-- different rare items (just add more entries with their own weight).
	rare_upgrade = {
		pickOne = true,
		items = {
			{ itemId = 28720, count = 1, weight = 1 }, -- falcon greaves -- PLACEHOLDER, add more rare items here to widen the jackpot pool
		},
	},
}

-- Tables: what a chest actionid actually rolls. `guaranteedPool` is granted
-- every single time the chest is opened (each item inside still rolls its
-- own `chance`). `rareTable` is a SEPARATE roll on top, bao_reward.lua-style
-- -- most of its weight should sit on a `pool = nil` "nothing extra" entry,
-- with the rest split across whichever bonus pools should occasionally fire.
-- `cooldownSeconds` gates re-opening the SAME table by the SAME player --
-- 0/nil means no cooldown at all (unlimited reuse).
LootChestConfig.Tables = {
	dungeon_standard = {
		cooldownSeconds = 24 * 60 * 60, -- 24h, per player per chest table
		guaranteedPool = "common_bundle",
		rareTable = {
			{ tier = "none", weight = 950 },
			{ tier = "rare", weight = 50, pool = "rare_upgrade" }, -- ~5% chance of a bonus rare item
		},
	},
}

-- actionid -> table name. Set this actionid on a chest in RME to wire it to
-- the named table above. Add more entries here as more chest types are
-- designed (e.g. a rarer daily-dungeon-boss chest with its own actionid and
-- its own LootChestConfig.Tables entry) -- the action script itself never
-- needs to change.
LootChestConfig.ActionIds = {
	[50100] = "dungeon_standard",
}
