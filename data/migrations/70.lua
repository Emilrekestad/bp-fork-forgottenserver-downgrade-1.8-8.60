-- Discord Hub foundation (db_version 70 -> 71).
--
-- The game server only writes durable, idempotent integration events. A
-- separate worker is responsible for Discord delivery, retries and logging.

function onUpdateDatabase()
	logMigration("Updating database to version 71 (Discord Hub event outbox)")

	if not db.query([[
		CREATE TABLE IF NOT EXISTS `world_first_achievements` (
			`achievement_id` SMALLINT UNSIGNED NOT NULL,
			`achievement_name` VARCHAR(255) NOT NULL DEFAULT '',
			`player_id` INT DEFAULT NULL,
			`player_name` VARCHAR(255) NOT NULL,
			`achieved_at` INT UNSIGNED NOT NULL,
			PRIMARY KEY (`achievement_id`),
			KEY `idx_world_first_player` (`player_id`),
			KEY `idx_world_first_time` (`achieved_at`),
			CONSTRAINT `fk_world_first_player` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE SET NULL
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then
		logMigration("Failed to create world_first_achievements")
		return false
	end

	if not db.query([[
		CREATE TABLE IF NOT EXISTS `integration_events` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`event_key` VARCHAR(128) NOT NULL,
			`event_type` VARCHAR(64) NOT NULL,
			`visibility` VARCHAR(16) NOT NULL DEFAULT 'public',
			`payload` LONGTEXT NOT NULL,
			`status` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`attempts` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`available_at` INT UNSIGNED NOT NULL,
			`created_at` INT UNSIGNED NOT NULL,
			`claimed_at` INT UNSIGNED DEFAULT NULL,
			`delivered_at` INT UNSIGNED DEFAULT NULL,
			`email_delivered_at` INT UNSIGNED DEFAULT NULL,
			`last_error` VARCHAR(512) NOT NULL DEFAULT '',
			`discord_message_id` VARCHAR(32) DEFAULT NULL,
			PRIMARY KEY (`id`),
			UNIQUE KEY `uq_integration_event_key` (`event_key`),
			KEY `idx_integration_delivery` (`status`, `available_at`, `id`),
			KEY `idx_integration_type_created` (`event_type`, `created_at`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then
		logMigration("Failed to create integration_events")
		return false
	end

	if not db.query([[
		CREATE TABLE IF NOT EXISTS `integration_workers` (
			`worker_name` VARCHAR(64) NOT NULL,
			`status` VARCHAR(24) NOT NULL DEFAULT 'unknown',
			`version` VARCHAR(32) NOT NULL DEFAULT '',
			`heartbeat_at` INT UNSIGNED NOT NULL DEFAULT 0,
			`last_error` VARCHAR(512) NOT NULL DEFAULT '',
			PRIMARY KEY (`worker_name`),
			KEY `idx_integration_worker_heartbeat` (`heartbeat_at`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then
		logMigration("Failed to create integration_workers")
		return false
	end

	-- Seed winners from existing achievement timestamps. This deliberately
	-- creates no outbox events: old achievements must not look newly earned.
	if not db.query([[
		INSERT IGNORE INTO `world_first_achievements`
			(`achievement_id`, `achievement_name`, `player_id`, `player_name`, `achieved_at`)
		SELECT
			current_storage.`key` - 300000,
			'',
			current_storage.`player_id`,
			players.`name`,
			current_storage.`value`
		FROM `player_storage` AS current_storage
		INNER JOIN `players` ON `players`.`id` = current_storage.`player_id`
		LEFT JOIN `player_storage` AS earlier_storage
			ON earlier_storage.`key` = current_storage.`key`
			AND earlier_storage.`value` > 0
			AND (
				earlier_storage.`value` < current_storage.`value`
				OR (
					earlier_storage.`value` = current_storage.`value`
					AND earlier_storage.`player_id` < current_storage.`player_id`
				)
			)
		WHERE current_storage.`key` BETWEEN 300001 AND 300398
			AND current_storage.`value` > 0
			AND earlier_storage.`player_id` IS NULL
	]]) then
		logMigration("Failed to backfill world_first_achievements")
		return false
	end

	return true
end
