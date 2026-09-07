-- Where things happen (db_version 88 -> 89).
--
-- The console can now draw the world map. These two tables give it something
-- to draw on it that no other table has: where people actually stand, and
-- where monsters actually die.
--
-- Both are counters over 8x8-tile buckets per floor per day, flushed with the
-- other buffered counters. A bucket is deliberately coarse. "Players spent
-- 340 samples in the block around the cave mouth" is the fact a designer
-- needs; a trail of exact positions per named character is a surveillance
-- log, is enormous, and answers no question this is asked. Eight tiles is
-- about one screen-quarter, which is the resolution a heat map is read at.
--
-- `player_presence_daily.samples` is minute-samples: one row of 60 means one
-- player stood in that block for an hour, or sixty stood there for a minute.
-- That is the right unit for "where is the game being played".

local function run(label, query)
	if db.query(query) then
		return true
	end
	logMigration("Failed to create " .. label)
	return false
end

function onUpdateDatabase()
	logMigration("Updating database to version 89 (presence and kill positions)")

	if not run("player_presence_daily", [[
		CREATE TABLE IF NOT EXISTS `player_presence_daily` (
			`day` DATE NOT NULL,
			`z` TINYINT UNSIGNED NOT NULL,
			`bx` SMALLINT UNSIGNED NOT NULL,
			`by` SMALLINT UNSIGNED NOT NULL,
			`samples` INT UNSIGNED NOT NULL DEFAULT 0,
			`players` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`day`, `z`, `bx`, `by`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	if not run("monster_kills_pos_daily", [[
		CREATE TABLE IF NOT EXISTS `monster_kills_pos_daily` (
			`day` DATE NOT NULL,
			`z` TINYINT UNSIGNED NOT NULL,
			`bx` SMALLINT UNSIGNED NOT NULL,
			`by` SMALLINT UNSIGNED NOT NULL,
			`kills` INT UNSIGNED NOT NULL DEFAULT 0,
			`boss_kills` INT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`day`, `z`, `bx`, `by`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	return true
end
