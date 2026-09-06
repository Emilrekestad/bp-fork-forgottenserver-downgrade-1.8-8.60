-- Rarity roll telemetry (db_version 84 -> 85).
--
-- One table, and it exists because the bonus system is currently the only
-- major system on this server whose real behaviour cannot be observed at all.
-- Every tier threshold, slot count and magnitude range is written down in
-- data/lib/rarity/rarity_stats.lua, but nothing anywhere records what those
-- numbers actually produce, so "is the drop rate right" has never been a
-- question with an answer -- only an intention.
--
-- The grain is deliberately coarse: one row per day, per stage, per tier, per
-- item class, per boosted-or-not. A busy day is a few hundred rows, which is
-- nothing, and it still answers every balance question worth asking -- what
-- share of eligible drops roll at all, whether the Rarity Boost moves that
-- share by the amount it claims, and whether high-class items are pulling
-- their weight.
--
-- Two stages, because the system rolls twice and they mean different things:
--
--   'drop'     the roll on a corpse. Decides ONLY whether an item becomes
--              Dormant -- tier 0 is a miss, tier 1 means it qualified. The
--              tier the drop computes is thrown away by design.
--   'identify' the roll when a Dormant item is woken. This is where the
--              player-visible tier is actually decided, and it is a uniform
--              pick across the four tiers rather than a weighted one.
--
-- Recording tier 0 is the whole point. A table of successes has no
-- denominator, and a drop rate without a denominator is not a rate.

local function run(label, query)
	if db.query(query) then
		return true
	end
	logMigration("Failed to create " .. label)
	return false
end

function onUpdateDatabase()
	logMigration("Updating database to version 85 (rarity roll telemetry)")

	-- `item_class` is RarityClass 1-7, or 0 when the roll never got far
	-- enough to classify the item. `boosted` records whether a Rarity Boost
	-- was running, so the boost's real effect is measurable rather than
	-- assumed -- the two populations have to be separable or the boost just
	-- silently biases the baseline.
	if not run("rarity_rolls_daily", [[
		CREATE TABLE IF NOT EXISTS `rarity_rolls_daily` (
			`day` DATE NOT NULL,
			`stage` VARCHAR(8) NOT NULL,
			`tier` TINYINT UNSIGNED NOT NULL,
			`item_class` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`boosted` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`rolls` INT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`day`, `stage`, `tier`, `item_class`, `boosted`),
			KEY `idx_rarity_day` (`day`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	return true
end
