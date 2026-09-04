-- Highscore board catalogue (db_version 77 -> 78).
--
-- The website carried its own hand-written PHP list of boards, and the
-- in-game window would have needed a second copy of the same list. Two
-- hand-maintained ladders drifting apart is precisely the failure that killed
-- seventeen Bao hunts with nothing in the log to say so.
--
-- So the catalogue moves to Lua (data/lib/highscores/highscores_config.lua)
-- and is projected here at every startup. The website reads this table; the
-- client receives the same rows over the wire. Neither keeps a copy.
--
-- `enabled` lives here rather than in MyAAC's settings for the same reason:
-- the game client cannot read a MyAAC setting, so "does this server offer the
-- Balance board" had to become a fact the server states once, in one place.
-- The values published on first boot deliberately match what the site was
-- already showing -- Balance and Frags off, everything else on -- so this
-- migration changes no visible behaviour on its own.

function onUpdateDatabase()
	logMigration("Updating database to version 78 (highscore board catalogue)")

	-- `id` is the WIRE id, written into packets, so it is the primary key
	-- rather than an auto-increment: retiring a board must never let its
	-- number be handed to a different one.
	if not db.query([[
		CREATE TABLE IF NOT EXISTS `highscore_boards` (
			`id` tinyint unsigned NOT NULL,
			`board_key` varchar(32) NOT NULL,
			`group_key` varchar(24) NOT NULL DEFAULT '',
			`group_ordering` tinyint unsigned NOT NULL DEFAULT '0',
			`ordering` tinyint unsigned NOT NULL DEFAULT '0',
			`label` varchar(32) NOT NULL,
			`title` varchar(48) NOT NULL,
			`unit` varchar(32) NOT NULL DEFAULT '',
			`extra_label` varchar(32) NOT NULL DEFAULT '',
			`has_vocation` tinyint unsigned NOT NULL DEFAULT '1',
			`enabled` tinyint unsigned NOT NULL DEFAULT '1',
			PRIMARY KEY (`id`),
			UNIQUE KEY `by_key` (`board_key`),
			KEY `display_order` (`group_ordering`, `ordering`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8
	]]) then
		logMigration("Failed to create highscore_boards")
		return false
	end

	logMigration("Highscore board catalogue created; the server publishes into it at startup")
	return true
end
