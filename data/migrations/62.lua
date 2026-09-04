function onUpdateDatabase()
	logMigration("Updating database to version 63 (add missing Bestiary/Charms tables)")

	local queries = {
		[[CREATE TABLE IF NOT EXISTS `player_bestiary_charms` (
			`player_id` INT NOT NULL,
			`charm_id` TINYINT UNSIGNED NOT NULL,
			`unlocked` TINYINT(1) NOT NULL DEFAULT 0,
			`raceid` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`player_id`, `charm_id`),
			KEY `idx_player_bestiary_charms_race` (`player_id`, `raceid`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8]],
		[[CREATE TABLE IF NOT EXISTS `player_bestiary_resources` (
			`player_id` INT NOT NULL,
			`minor_charm_echoes` INT UNSIGNED NOT NULL DEFAULT 0,
			`max_minor_charm_echoes` INT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`player_id`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8]],
		[[CREATE TABLE IF NOT EXISTS `player_bestiary_tracker` (
			`player_id` INT NOT NULL,
			`raceid` SMALLINT UNSIGNED NOT NULL,
			`slot` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`player_id`, `raceid`),
			KEY `idx_player_bestiary_tracker_slot` (`player_id`, `slot`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8]],
	}

	for _, query in ipairs(queries) do
		if not db.query(query) then
			logMigration("Failed to create Bestiary/Charms tables")
			return false
		end
	end

	return true
end
