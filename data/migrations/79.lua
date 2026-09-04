-- Admin console foundations (db_version 79 -> 80).
--
-- Creates the tables the console reads and writes: the coin ledger and its
-- rollups, player sessions, metrics, structured logs, incidents, the typed
-- game event stream, the two command tables the server executes on the
-- console's behalf, and the console's own auth/state tables.
--
-- Three things worth knowing before changing anything here:
--
-- 1. `coin_ledger` is append-only and is the only record of why a balance
--    changed. Its unique key on (ref_type, ref_id, kind) is what makes the
--    web payment handlers idempotent: replaying a PayPal IPN inserts nothing.
--    NULL refs are exempt because SQL treats NULLs as distinct, which is
--    exactly right for in-game movements that have no external reference.
--
-- 2. `game_events` is RANGE-partitioned by month. Retention is 90 days, and
--    dropping a partition is instant where deleting a few million rows is
--    not. Partitioned tables cannot carry foreign keys, so it has none by
--    design -- player_id is a plain column and may point at a deleted
--    character. The console resolves names through `players` with a LEFT JOIN.
--    A `pmax` catch-all keeps inserts working if partition maintenance ever
--    stops; the console reorganises it forward every night.
--
-- 3. Nothing here is written by the game server except the event, session,
--    metric and ledger rows. The console service has no write access to
--    `accounts` or `players` at all -- coin grants and every other world
--    change go through `agent_commands`, which the server executes in-process
--    where it can see the online player. That boundary is the whole reason
--    the console can be trusted with an API key.

local function monthlyPartitions(count)
	-- Boundaries are "less than" the first second of each month, starting with
	-- the month after the current one, so the current month is always covered.
	local now = os.date("*t")
	local year, month = now.year, now.month
	local parts = {}
	for _ = 1, count do
		month = month + 1
		if month > 12 then
			month = 1
			year = year + 1
		end
		local boundary = os.time({year = year, month = month, day = 1, hour = 0, min = 0, sec = 0})
		parts[#parts + 1] = string.format("PARTITION `p%04d%02d` VALUES LESS THAN (%d)", year, month, boundary)
	end
	parts[#parts + 1] = "PARTITION `pmax` VALUES LESS THAN MAXVALUE"
	return table.concat(parts, ",\n\t\t\t")
end

local function run(label, query)
	if db.query(query) then
		return true
	end
	logMigration("Failed to create " .. label)
	return false
end

function onUpdateDatabase()
	logMigration("Updating database to version 80 (admin console foundations)")

	-- ---------------------------------------------------------------- coins

	if not run("coin_ledger", [[
		CREATE TABLE IF NOT EXISTS `coin_ledger` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`ts` INT UNSIGNED NOT NULL,
			`account_id` INT NOT NULL,
			`player_id` INT DEFAULT NULL,
			`delta` BIGINT NOT NULL,
			`balance_after` BIGINT UNSIGNED DEFAULT NULL,
			`kind` VARCHAR(32) NOT NULL,
			`ref_type` VARCHAR(24) DEFAULT NULL,
			`ref_id` VARCHAR(64) DEFAULT NULL,
			`meta` LONGTEXT DEFAULT NULL,
			`source` ENUM('lua','cpp','web','service') NOT NULL DEFAULT 'lua',
			`reconstructed` TINYINT(1) NOT NULL DEFAULT 0,
			PRIMARY KEY (`id`),
			UNIQUE KEY `uq_coin_ledger_ref` (`ref_type`, `ref_id`, `kind`),
			KEY `idx_coin_ledger_account_ts` (`account_id`, `ts`),
			KEY `idx_coin_ledger_kind_ts` (`kind`, `ts`),
			KEY `idx_coin_ledger_ts` (`ts`),
			KEY `idx_coin_ledger_player` (`player_id`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	if not run("coin_daily", [[
		CREATE TABLE IF NOT EXISTS `coin_daily` (
			`day` DATE NOT NULL,
			`minted_json` LONGTEXT DEFAULT NULL,
			`burned_json` LONGTEXT DEFAULT NULL,
			`transfer_volume` BIGINT NOT NULL DEFAULT 0,
			`purchases` INT NOT NULL DEFAULT 0,
			`buyers` INT NOT NULL DEFAULT 0,
			`fiat_json` LONGTEXT DEFAULT NULL,
			`supply_end` BIGINT NOT NULL DEFAULT 0,
			`active_accounts` INT NOT NULL DEFAULT 0,
			`computed_at` INT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`day`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	if not run("coin_holdings_daily", [[
		CREATE TABLE IF NOT EXISTS `coin_holdings_daily` (
			`day` DATE NOT NULL,
			`account_id` INT NOT NULL,
			`balance` BIGINT UNSIGNED NOT NULL DEFAULT 0,
			`last_movement_ts` INT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`day`, `account_id`),
			KEY `idx_holdings_balance` (`day`, `balance`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	-- ------------------------------------------------------------- activity

	if not run("player_sessions", [[
		CREATE TABLE IF NOT EXISTS `player_sessions` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`account_id` INT NOT NULL,
			`player_id` INT NOT NULL,
			`login_at` INT UNSIGNED NOT NULL,
			`logout_at` INT UNSIGNED DEFAULT NULL,
			`duration` INT UNSIGNED DEFAULT NULL,
			`close_reason` ENUM('logout','kick','crash_recovery','server_stop') DEFAULT NULL,
			`ip_masked` VARCHAR(18) NOT NULL DEFAULT '',
			`client_version` VARCHAR(16) NOT NULL DEFAULT '',
			`level_in` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
			`level_out` SMALLINT UNSIGNED DEFAULT NULL,
			`town_in` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
			`chat_public` INT UNSIGNED NOT NULL DEFAULT 0,
			`chat_private` INT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`id`),
			KEY `idx_sessions_player_login` (`player_id`, `login_at`),
			KEY `idx_sessions_account_login` (`account_id`, `login_at`),
			KEY `idx_sessions_login` (`login_at`),
			KEY `idx_sessions_open` (`logout_at`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	-- ------------------------------------------------------------ telemetry

	-- tags_hash is written by the sampler (MD5 of the canonical tags JSON, or
	-- the empty string) rather than being a generated column: it keeps the
	-- primary key stable across MariaDB versions and lets the writer decide
	-- what "canonical" means for its own tag set.
	if not run("server_metrics", [[
		CREATE TABLE IF NOT EXISTS `server_metrics` (
			`metric` VARCHAR(48) NOT NULL,
			`ts` INT UNSIGNED NOT NULL,
			`tags_hash` CHAR(32) NOT NULL DEFAULT '',
			`value` DOUBLE NOT NULL,
			`tags` LONGTEXT DEFAULT NULL,
			PRIMARY KEY (`metric`, `ts`, `tags_hash`),
			KEY `idx_metrics_ts` (`ts`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	if not run("server_log", [[
		CREATE TABLE IF NOT EXISTS `server_log` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`ts` INT UNSIGNED NOT NULL,
			`ts_ms` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
			`level` ENUM('trace','debug','info','warn','error','critical') NOT NULL DEFAULT 'info',
			`module` VARCHAR(48) NOT NULL DEFAULT '',
			`file` VARCHAR(255) DEFAULT NULL,
			`fingerprint` CHAR(16) NOT NULL DEFAULT '',
			`message` TEXT NOT NULL,
			PRIMARY KEY (`id`),
			KEY `idx_log_ts` (`ts`),
			KEY `idx_log_level_ts` (`level`, `ts`),
			KEY `idx_log_fingerprint_ts` (`fingerprint`, `ts`),
			FULLTEXT KEY `ft_log_message` (`message`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	if not run("server_incidents", [[
		CREATE TABLE IF NOT EXISTS `server_incidents` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`kind` VARCHAR(32) NOT NULL,
			`severity` ENUM('info','warning','critical') NOT NULL DEFAULT 'warning',
			`opened_at` INT UNSIGNED NOT NULL,
			`closed_at` INT UNSIGNED DEFAULT NULL,
			`summary` TEXT DEFAULT NULL,
			`evidence` LONGTEXT DEFAULT NULL,
			`ack_by` VARCHAR(32) DEFAULT NULL,
			`ack_at` INT UNSIGNED DEFAULT NULL,
			PRIMARY KEY (`id`),
			KEY `idx_incidents_open` (`closed_at`, `opened_at`),
			KEY `idx_incidents_kind` (`kind`, `opened_at`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	-- ---------------------------------------------------------- game events

	if not run("game_events", string.format([[
		CREATE TABLE IF NOT EXISTS `game_events` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`ts` INT UNSIGNED NOT NULL,
			`type` VARCHAR(48) NOT NULL,
			`version` TINYINT UNSIGNED NOT NULL DEFAULT 1,
			`account_id` INT DEFAULT NULL,
			`player_id` INT DEFAULT NULL,
			`subject_type` VARCHAR(24) DEFAULT NULL,
			`subject_id` VARCHAR(64) DEFAULT NULL,
			`pos_x` SMALLINT UNSIGNED DEFAULT NULL,
			`pos_y` SMALLINT UNSIGNED DEFAULT NULL,
			`pos_z` TINYINT UNSIGNED DEFAULT NULL,
			`payload` LONGTEXT DEFAULT NULL,
			PRIMARY KEY (`id`, `ts`),
			KEY `idx_events_type_ts` (`type`, `ts`),
			KEY `idx_events_player_ts` (`player_id`, `ts`),
			KEY `idx_events_account_ts` (`account_id`, `ts`),
			KEY `idx_events_ts` (`ts`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
		PARTITION BY RANGE (`ts`) (
			%s
		)
	]], monthlyPartitions(18))) then return false end

	if not run("game_events_daily", [[
		CREATE TABLE IF NOT EXISTS `game_events_daily` (
			`day` DATE NOT NULL,
			`type` VARCHAR(48) NOT NULL,
			`count` INT UNSIGNED NOT NULL DEFAULT 0,
			`sum_json` LONGTEXT DEFAULT NULL,
			PRIMARY KEY (`day`, `type`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	-- ------------------------------------------------- console <-> server

	-- Both follow the bazaar_commands lifecycle: 0 pending, 1 claimed, 2 done,
	-- 3 failed, with the claim guarded on still-pending so a restart mid-tick
	-- can never run the same row twice.
	if not run("agent_queries", [[
		CREATE TABLE IF NOT EXISTS `agent_queries` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`kind` VARCHAR(32) NOT NULL,
			`params` LONGTEXT DEFAULT NULL,
			`status` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`result` LONGTEXT DEFAULT NULL,
			`created_at` INT UNSIGNED NOT NULL,
			`claimed_at` INT UNSIGNED DEFAULT NULL,
			`completed_at` INT UNSIGNED DEFAULT NULL,
			PRIMARY KEY (`id`),
			KEY `idx_agent_queries_pending` (`status`, `created_at`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	-- `confirmed_at` is the gate: the consumer ignores any row without it, so
	-- an agent that decides on its own to grant coins still cannot, because
	-- only a human action through the console or MCP sets that column.
	if not run("agent_commands", [[
		CREATE TABLE IF NOT EXISTS `agent_commands` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`kind` VARCHAR(32) NOT NULL,
			`params` LONGTEXT DEFAULT NULL,
			`requested_by` VARCHAR(32) NOT NULL DEFAULT '',
			`confirmed_at` INT UNSIGNED DEFAULT NULL,
			`status` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`result_code` INT NOT NULL DEFAULT 0,
			`result_message` VARCHAR(512) NOT NULL DEFAULT '',
			`created_at` INT UNSIGNED NOT NULL,
			`claimed_at` INT UNSIGNED DEFAULT NULL,
			`completed_at` INT UNSIGNED DEFAULT NULL,
			PRIMARY KEY (`id`),
			KEY `idx_agent_commands_pending` (`status`, `confirmed_at`, `created_at`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	-- -------------------------------------------------------- console state

	if not run("console_users", [[
		CREATE TABLE IF NOT EXISTS `console_users` (
			`id` INT NOT NULL AUTO_INCREMENT,
			`username` VARCHAR(32) NOT NULL,
			`password_hash` VARCHAR(255) NOT NULL,
			`totp_secret` VARCHAR(64) DEFAULT NULL,
			`role` ENUM('owner','staff') NOT NULL DEFAULT 'staff',
			`created_at` INT UNSIGNED NOT NULL,
			`last_login` INT UNSIGNED DEFAULT NULL,
			PRIMARY KEY (`id`),
			UNIQUE KEY `uq_console_username` (`username`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	if not run("console_confirmations", [[
		CREATE TABLE IF NOT EXISTS `console_confirmations` (
			`id` CHAR(32) NOT NULL,
			`tool` VARCHAR(48) NOT NULL,
			`params` LONGTEXT DEFAULT NULL,
			`summary` VARCHAR(512) NOT NULL DEFAULT '',
			`requested_by` VARCHAR(32) NOT NULL DEFAULT '',
			`created_at` INT UNSIGNED NOT NULL,
			`expires_at` INT UNSIGNED NOT NULL,
			`used_at` INT UNSIGNED DEFAULT NULL,
			PRIMARY KEY (`id`),
			KEY `idx_confirmations_expiry` (`expires_at`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	if not run("console_saved_tiles", [[
		CREATE TABLE IF NOT EXISTS `console_saved_tiles` (
			`id` INT NOT NULL AUTO_INCREMENT,
			`user_id` INT NOT NULL,
			`title` VARCHAR(120) NOT NULL,
			`tile` VARCHAR(64) NOT NULL,
			`params` LONGTEXT DEFAULT NULL,
			`position` INT NOT NULL DEFAULT 0,
			`created_at` INT UNSIGNED NOT NULL,
			PRIMARY KEY (`id`),
			KEY `idx_saved_user` (`user_id`, `position`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	if not run("console_automations", [[
		CREATE TABLE IF NOT EXISTS `console_automations` (
			`id` INT NOT NULL AUTO_INCREMENT,
			`event_type` VARCHAR(48) NOT NULL,
			`channel` VARCHAR(32) NOT NULL,
			`template` VARCHAR(48) NOT NULL,
			`enabled` TINYINT(1) NOT NULL DEFAULT 0,
			`updated_at` INT UNSIGNED NOT NULL,
			PRIMARY KEY (`id`),
			UNIQUE KEY `uq_automation` (`event_type`, `channel`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	return true
end
