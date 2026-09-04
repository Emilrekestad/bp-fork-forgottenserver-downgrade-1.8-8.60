-- Bug reports (db_version 80 -> 81).
--
-- One table, two intakes. A report filed with `/bug` in Discord and a report
-- filed with the in-game bug key land in the same row shape, differing only
-- in `source` and in how much provenance we have: in-game we know the account
-- and the character for certain, from Discord we know a Discord id and
-- whatever name the reporter typed.
--
-- Three decisions worth stating, because they are easy to undo by accident:
--
-- 1. `external_id` is the Discord interaction id, and it is UNIQUE. Discord
--    retries an interaction it did not see acknowledged, and without this a
--    slow reply would file the same bug two or three times. NULL is exempt
--    (SQL treats NULLs as distinct), which is exactly right for in-game
--    reports that have no external reference.
--
-- 2. `detail` and `summary` are player-written text. They are stored verbatim
--    and are never markup: the console renders them as text, the analyst is
--    told they are untrusted, and nothing downstream interprets them. Storing
--    them raw is deliberate -- sanitising on the way in loses the report's
--    actual words, which are the whole point of a bug report.
--
-- 3. There is no foreign key on `account_id` or `player_id`. A character can
--    be deleted and the bug it described remains true. The console resolves
--    names through a LEFT JOIN, the same way it does for `game_events`.

function onUpdateDatabase()
	logMigration("Updating database to version 81 (bug reports)")

	if not db.query([[
		CREATE TABLE IF NOT EXISTS `bug_reports` (
			`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
			`source` ENUM('discord','ingame','console') NOT NULL DEFAULT 'discord',
			`external_id` VARCHAR(64) DEFAULT NULL,
			`reporter_discord_id` VARCHAR(32) DEFAULT NULL,
			`reporter_name` VARCHAR(64) NOT NULL DEFAULT '',
			`account_id` INT DEFAULT NULL,
			`player_id` INT DEFAULT NULL,
			`character_name` VARCHAR(64) NOT NULL DEFAULT '',
			`severity` ENUM('crash','blocker','annoyance','cosmetic') NOT NULL DEFAULT 'annoyance',
			`area` VARCHAR(48) NOT NULL DEFAULT '',
			`summary` VARCHAR(255) NOT NULL DEFAULT '',
			`detail` TEXT DEFAULT NULL,
			`pos_x` SMALLINT UNSIGNED DEFAULT NULL,
			`pos_y` SMALLINT UNSIGNED DEFAULT NULL,
			`pos_z` TINYINT UNSIGNED DEFAULT NULL,
			`status` ENUM('new','triaged','confirmed','fixed','wontfix','duplicate') NOT NULL DEFAULT 'new',
			`duplicate_of` INT UNSIGNED DEFAULT NULL,
			`notes` TEXT DEFAULT NULL,
			`thread_id` VARCHAR(32) DEFAULT NULL,
			`triaged_by` VARCHAR(32) DEFAULT NULL,
			`created_at` INT UNSIGNED NOT NULL,
			`updated_at` INT UNSIGNED NOT NULL,
			PRIMARY KEY (`id`),
			UNIQUE KEY `uq_bug_external` (`external_id`),
			KEY `idx_bug_status_created` (`status`, `created_at`),
			KEY `idx_bug_created` (`created_at`),
			KEY `idx_bug_severity` (`severity`, `status`),
			KEY `idx_bug_reporter` (`reporter_discord_id`, `created_at`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then
		logMigration("Failed to create bug_reports")
		return false
	end

	return true
end
