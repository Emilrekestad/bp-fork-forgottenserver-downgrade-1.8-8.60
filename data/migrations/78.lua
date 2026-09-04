-- Hireling records, for real this time (db_version 78 -> 79).
--
-- Migration 48 already creates `player_hirelings`. It never runs: schema.sql
-- seeds a fresh database at db_version 72, so every migration below 72 is
-- skipped, and the table is not in schema.sql either. The result is a server
-- that boots with "[Hireling] player_hirelings table is missing" and a
-- hireling system that cannot store anything -- which is exactly what the
-- logs have been saying since August.
--
-- CREATE TABLE IF NOT EXISTS makes this a no-op on any database that did run
-- 48, so it is safe on the live server and correct on a fresh install.
--
-- Jobs and dresses are deliberately NOT columns here. They live in kv, scoped
-- per hireling, because they are a growing list -- one row per unlock beats a
-- schema change per job.

function onUpdateDatabase()
	logMigration("Updating database to version 79 (hireling records)")

	if not db.query([[
		CREATE TABLE IF NOT EXISTS `player_hirelings` (
			`id` INT NOT NULL AUTO_INCREMENT,
			`player_id` INT NOT NULL,
			`name` VARCHAR(32) NOT NULL,
			`active` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`sex` TINYINT UNSIGNED NOT NULL DEFAULT 1,
			`posx` INT NOT NULL DEFAULT 0,
			`posy` INT NOT NULL DEFAULT 0,
			`posz` INT NOT NULL DEFAULT 0,
			`lookbody` INT NOT NULL DEFAULT 34,
			`lookfeet` INT NOT NULL DEFAULT 116,
			`lookhead` INT NOT NULL DEFAULT 97,
			`looklegs` INT NOT NULL DEFAULT 3,
			`looktype` INT NOT NULL DEFAULT 1108,
			PRIMARY KEY (`id`),
			KEY `idx_player_hirelings_player_id` (`player_id`),
			CONSTRAINT `fk_player_hirelings_player_id`
				FOREIGN KEY (`player_id`) REFERENCES `players` (`id`)
				ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARSET=utf8
	]]) then
		logMigration("Failed to create player_hirelings")
		return false
	end

	return true
end
