function onUpdateDatabase()
	logMigration("Updating database to version 64 (add Old Man Bao tables)")

	local queries = {
		[[CREATE TABLE IF NOT EXISTS `bao_player` (
			`player_id` INT NOT NULL,
			`reputation` BIGINT UNSIGNED NOT NULL DEFAULT 0,
			`marks` BIGINT UNSIGNED NOT NULL DEFAULT 0,
			`rank_id` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`story_chapter` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`updated_at` BIGINT NOT NULL DEFAULT 0,
			PRIMARY KEY (`player_id`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4]],
		[[CREATE TABLE IF NOT EXISTS `bao_active_hunts` (
			`player_id` INT NOT NULL,
			`slot` TINYINT UNSIGNED NOT NULL,
			`hunt_id` VARCHAR(64) NOT NULL,
			`state` TINYINT UNSIGNED NOT NULL DEFAULT 1,
			`progress` INT UNSIGNED NOT NULL DEFAULT 0,
			`accepted_at` BIGINT NOT NULL DEFAULT 0,
			PRIMARY KEY (`player_id`, `slot`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4]],
	}

	for _, query in ipairs(queries) do
		if not db.query(query) then
			logMigration("Failed to create Old Man Bao tables")
			return false
		end
	end

	return true
end
