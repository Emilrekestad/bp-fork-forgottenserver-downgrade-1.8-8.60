-- Monster loot tracking (db_version 82 -> 83).
--
-- An exact ledger of what the server put in every corpse, so a configured drop
-- chance can be checked against what actually happens.
--
-- Five decisions, all of which exist to keep this measurement honest rather
-- than merely indicative.
--
-- 1. Two tables, one denominator. `monster_loot_daily` counts drops;
--    `monster_corpses_daily` counts the corpses those drops came out of.
--    A rate needs both, and they are written from one buffer in one flush so
--    a lost flush after a crash loses numerator and denominator together and
--    leaves the ratio unbiased.
--
-- 2. `corpses_plain` is the honest denominator. Every corpse rolled while a
--    loot modifier was active -- the player's drop bonus, a boosted creature,
--    a boosted boss, a global loot boost, prey improved loot or a bounty
--    talisman -- gets extra roll passes and cannot be compared against the
--    configured chance. Those are counted separately in `corpses_boosted`,
--    and `plain_drops` is the matching numerator.
--
-- 3. `corpses_blocked` is stamina. At or below 840 stamina the loot generator
--    rolls nothing at all, so those corpses are empty for a reason that has
--    nothing to do with drop chance. Counting them in the denominator would
--    silently depress every rate on the server.
--
-- 4. `drops` counts corpses that contained the item at least once; `quantity`
--    counts units. A stack of 97 gold is one drop of quantity 97, and
--    conflating the two would make gold look like a 100% drop of one coin.
--
-- 5. Item ids, not names. items.xml here is renumbered and several items share
--    a name; the id is what the engine actually put in the corpse. The console
--    resolves names for display from the same items.xml the server loads.
--
-- Reward bosses are structurally absent: Monster::dropLoot gives them a reward
-- container and never calls onDropLoot, so nothing here can see their loot.
-- The console reports them as unmeasured rather than as zero.

local function run(label, query)
	if db.query(query) then
		return true
	end
	logMigration("Failed to create " .. label)
	return false
end

function onUpdateDatabase()
	logMigration("Updating database to version 83 (monster loot tracking)")

	if not run("monster_loot_daily", [[
		CREATE TABLE IF NOT EXISTS `monster_loot_daily` (
			`day` DATE NOT NULL,
			`monster_name` VARCHAR(64) NOT NULL,
			`item_id` SMALLINT UNSIGNED NOT NULL,
			`drops` INT UNSIGNED NOT NULL DEFAULT 0,
			`quantity` INT UNSIGNED NOT NULL DEFAULT 0,
			`plain_drops` INT UNSIGNED NOT NULL DEFAULT 0,
			`rare_drops` INT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`day`, `monster_name`, `item_id`),
			KEY `idx_loot_item_day` (`item_id`, `day`),
			KEY `idx_loot_monster` (`monster_name`, `item_id`),
			KEY `idx_loot_day` (`day`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	if not run("monster_corpses_daily", [[
		CREATE TABLE IF NOT EXISTS `monster_corpses_daily` (
			`day` DATE NOT NULL,
			`monster_name` VARCHAR(64) NOT NULL,
			`corpses` INT UNSIGNED NOT NULL DEFAULT 0,
			`corpses_plain` INT UNSIGNED NOT NULL DEFAULT 0,
			`corpses_boosted` INT UNSIGNED NOT NULL DEFAULT 0,
			`corpses_blocked` INT UNSIGNED NOT NULL DEFAULT 0,
			`empty_corpses` INT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`day`, `monster_name`),
			KEY `idx_corpses_day` (`day`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	return true
end
