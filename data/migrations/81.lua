-- Monster kill counters and boss encounters (db_version 81 -> 82).
--
-- The question this answers is "what is actually being played". Which spawns
-- are hunted, which are dead, how that has moved since the server opened, and
-- for bosses: did anyone actually kill the thing that spawned.
--
-- Four decisions worth stating.
--
-- 1. Counters, not events. A kill per row would put millions of rows a month
--    into `game_events` for something nobody ever reads individually. The
--    server buffers kills in memory and flushes aggregated counts, so a busy
--    hour is a few hundred UPSERTs rather than a few hundred thousand INSERTs.
--
-- 2. Two grains, deliberately. `monster_kills_hourly` is what "the last 24
--    hours" is computed from and is prunable; `monster_kills_daily` is small,
--    permanent, and is what the since-launch progression chart reads. Both are
--    written in the same flush, so they cannot drift.
--
-- 3. `boss` is stored on the counter rows rather than looked up. It comes from
--    monsterType:isBoss() at kill time, so a monster that is reclassified later
--    keeps the classification it had when it was killed -- which is what the
--    history should say.
--
-- 4. `boss_encounters` is one row per boss that appeared, opened on spawn and
--    closed on death. A row with `killed_at` still NULL and a spawn hours old
--    is the interesting case: something spawned and nobody beat it. Names are
--    stored rather than referenced because monsters are Lua files, not rows.

local function run(label, query)
	if db.query(query) then
		return true
	end
	logMigration("Failed to create " .. label)
	return false
end

function onUpdateDatabase()
	logMigration("Updating database to version 82 (monster kill counters)")

	-- `hour_ts` is a unix timestamp aligned to the hour, matching the way
	-- server_metrics aligns to the minute: the writer decides the bucket, so
	-- every reader agrees on the boundary without a timezone argument.
	if not run("monster_kills_hourly", [[
		CREATE TABLE IF NOT EXISTS `monster_kills_hourly` (
			`hour_ts` INT UNSIGNED NOT NULL,
			`monster_name` VARCHAR(64) NOT NULL,
			`kills` INT UNSIGNED NOT NULL DEFAULT 0,
			`boss` TINYINT(1) NOT NULL DEFAULT 0,
			PRIMARY KEY (`hour_ts`, `monster_name`),
			KEY `idx_mkh_name_hour` (`monster_name`, `hour_ts`),
			KEY `idx_mkh_hour` (`hour_ts`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	if not run("monster_kills_daily", [[
		CREATE TABLE IF NOT EXISTS `monster_kills_daily` (
			`day` DATE NOT NULL,
			`monster_name` VARCHAR(64) NOT NULL,
			`kills` INT UNSIGNED NOT NULL DEFAULT 0,
			`boss` TINYINT(1) NOT NULL DEFAULT 0,
			PRIMARY KEY (`day`, `monster_name`),
			KEY `idx_mkd_name_day` (`monster_name`, `day`),
			KEY `idx_mkd_day_kills` (`day`, `kills`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	if not run("boss_encounters", [[
		CREATE TABLE IF NOT EXISTS `boss_encounters` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`monster_name` VARCHAR(64) NOT NULL,
			`spawned_at` INT UNSIGNED NOT NULL,
			`killed_at` INT UNSIGNED DEFAULT NULL,
			`killer_name` VARCHAR(64) DEFAULT NULL,
			`by_player` TINYINT(1) NOT NULL DEFAULT 0,
			`seconds_alive` INT UNSIGNED DEFAULT NULL,
			`source` ENUM('spawn','raid','summon','startup') NOT NULL DEFAULT 'spawn',
			`pos_x` SMALLINT UNSIGNED DEFAULT NULL,
			`pos_y` SMALLINT UNSIGNED DEFAULT NULL,
			`pos_z` TINYINT UNSIGNED DEFAULT NULL,
			PRIMARY KEY (`id`),
			KEY `idx_boss_name_spawn` (`monster_name`, `spawned_at`),
			KEY `idx_boss_open` (`killed_at`, `spawned_at`),
			KEY `idx_boss_spawned` (`spawned_at`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	return true
end
