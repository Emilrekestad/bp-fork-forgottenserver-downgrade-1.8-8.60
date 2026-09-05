-- The Desk: actions, cases and the activity fingerprint (db_version 83 -> 84).
--
-- Five tables and two columns, all of which exist so that acting on the server
-- from outside the game leaves a trail a person can audit afterwards.
--
-- 1. `console_audit` is written BEFORE a command is confirmed and updated with
--    the outcome after. That ordering is deliberate: if the game server never
--    picks the command up, or the service dies between confirming and
--    executing, there is still a row saying somebody asked. An audit table
--    that only records successes is not an audit table.
--
-- 2. `player_reports` replaces the flat files in data/reports/players/, which
--    nobody has ever read because reading them means an SSH session. The
--    columns mirror the arguments of Player:onReportRuleViolation exactly, so
--    the handler stores what the engine gave it and interprets nothing.
--
-- 3. `player_activity_hourly` is the botting fingerprint. Four numbers per
--    player-hour -- kills, experience, distinct tiles stood on, lines of chat
--    -- because a bot is not one of those being unusual, it is all four at
--    once. Kept 90 days; it is the only new table with a retention policy,
--    since a fingerprint older than a season answers no question anyone asks.
--
-- 4. `console_dismissals` is what makes the Desk queue emptiable. Without it
--    an incident you have decided to live with reappears every five minutes
--    forever, and a queue that cannot be emptied stops being read.
--
-- 5. `console_users.player_id` exists because account_bans.banned_by is a
--    foreign key to players.id. A console user is not a character, so a ban
--    issued from the console has to name one. Nullable: the service falls
--    back to a configured service character, and refuses the ban if neither
--    resolves rather than inventing an id that would fail the constraint.

local function run(label, query)
	if db.query(query) then
		return true
	end
	logMigration("Failed to create " .. label)
	return false
end

-- ALTER TABLE ... ADD COLUMN has no IF NOT EXISTS on every MariaDB build this
-- schema has been run against, and a migration that fails on a second run is
-- a migration nobody dares re-run. Checking information_schema first is the
-- portable way to make the whole file idempotent.
local function hasColumn(tableName, columnName)
	local resultId = db.storeQuery(string.format(
		"SELECT 1 FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA` = DATABASE() " ..
		"AND `TABLE_NAME` = %s AND `COLUMN_NAME` = %s LIMIT 1",
		db.escapeString(tableName), db.escapeString(columnName)))
	if resultId then
		result.free(resultId)
		return true
	end
	return false
end

local function addColumn(tableName, columnName, definition)
	if hasColumn(tableName, columnName) then
		return true
	end
	if db.query(string.format("ALTER TABLE `%s` ADD COLUMN `%s` %s", tableName, columnName, definition)) then
		return true
	end
	logMigration("Failed to add " .. tableName .. "." .. columnName)
	return false
end

function onUpdateDatabase()
	logMigration("Updating database to version 84 (console actions, cases and activity)")

	-- ------------------------------------------------------------- auditing

	if not run("console_audit", [[
		CREATE TABLE IF NOT EXISTS `console_audit` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`ts` INT UNSIGNED NOT NULL,
			`actor` VARCHAR(64) NOT NULL,
			`actor_role` VARCHAR(16) NOT NULL DEFAULT '',
			`tool` VARCHAR(48) NOT NULL,
			`params` LONGTEXT DEFAULT NULL,
			`preview` VARCHAR(512) NOT NULL DEFAULT '',
			`tier` TINYINT UNSIGNED NOT NULL DEFAULT 1,
			`target_type` VARCHAR(16) NOT NULL DEFAULT 'none',
			`target_id` INT DEFAULT NULL,
			`target_name` VARCHAR(64) NOT NULL DEFAULT '',
			`path` ENUM('bridge','host','service') NOT NULL DEFAULT 'bridge',
			`command_id` BIGINT UNSIGNED DEFAULT NULL,
			`confirmation_id` CHAR(32) DEFAULT NULL,
			`status` ENUM('requested','executed','failed','timeout') NOT NULL DEFAULT 'requested',
			`result_message` VARCHAR(512) NOT NULL DEFAULT '',
			`ip_masked` VARCHAR(18) NOT NULL DEFAULT '',
			`completed_at` INT UNSIGNED DEFAULT NULL,
			PRIMARY KEY (`id`),
			KEY `idx_audit_ts` (`ts`),
			KEY `idx_audit_actor` (`actor`, `ts`),
			KEY `idx_audit_target` (`target_type`, `target_id`, `ts`),
			KEY `idx_audit_command` (`command_id`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	-- -------------------------------------------------------------- reports

	-- No foreign key on reporter_id or target_id on purpose. A report is
	-- evidence about a moment; deleting a character should not delete the
	-- record of what they reported or of what was reported about them, and
	-- both names are stored alongside the ids for exactly that case.
	if not run("player_reports", [[
		CREATE TABLE IF NOT EXISTS `player_reports` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`ts` INT UNSIGNED NOT NULL,
			`reporter_id` INT NOT NULL DEFAULT 0,
			`reporter_name` VARCHAR(64) NOT NULL DEFAULT '',
			`reporter_x` INT UNSIGNED NOT NULL DEFAULT 0,
			`reporter_y` INT UNSIGNED NOT NULL DEFAULT 0,
			`reporter_z` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`target_name` VARCHAR(64) NOT NULL DEFAULT '',
			`target_id` INT DEFAULT NULL,
			`report_type` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`reason` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`comment` TEXT DEFAULT NULL,
			`translation` TEXT DEFAULT NULL,
			`status` ENUM('new','handled','dismissed') NOT NULL DEFAULT 'new',
			`handled_by` VARCHAR(32) NOT NULL DEFAULT '',
			`handled_at` INT UNSIGNED DEFAULT NULL,
			`notes` TEXT DEFAULT NULL,
			PRIMARY KEY (`id`),
			KEY `idx_reports_status_ts` (`status`, `ts`),
			KEY `idx_reports_target` (`target_name`, `ts`),
			KEY `idx_reports_reporter` (`reporter_id`, `ts`),
			KEY `idx_reports_type` (`report_type`, `ts`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	-- --------------------------------------------------------- fingerprint

	-- `hour` is an epoch second floored to the hour, not a DATETIME, so it
	-- joins against player_sessions and game_events without a conversion and
	-- sorts as an integer.
	--
	-- `tiles_distinct` is written with GREATEST rather than added on flush:
	-- the count is of a set held in memory for the current hour, so a second
	-- flush within the same hour carries a superset, and adding would count
	-- the same tiles twice.
	if not run("player_activity_hourly", [[
		CREATE TABLE IF NOT EXISTS `player_activity_hourly` (
			`hour` INT UNSIGNED NOT NULL,
			`player_id` INT NOT NULL,
			`kills` INT UNSIGNED NOT NULL DEFAULT 0,
			`exp_gained` BIGINT UNSIGNED NOT NULL DEFAULT 0,
			`tiles_distinct` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
			`samples` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
			`chat` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
			`level` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`hour`, `player_id`),
			KEY `idx_activity_player_hour` (`player_id`, `hour`),
			KEY `idx_activity_hour` (`hour`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	-- ------------------------------------------------------------ the queue

	-- `snooze_until` rather than `until`: UNTIL is a MariaDB keyword and an
	-- unquoted use of it is a syntax error in exactly the place a query is
	-- built by string concatenation.
	if not run("console_dismissals", [[
		CREATE TABLE IF NOT EXISTS `console_dismissals` (
			`kind` VARCHAR(16) NOT NULL,
			`ref` VARCHAR(64) NOT NULL,
			`dismissed_by` VARCHAR(32) NOT NULL DEFAULT '',
			`dismissed_at` INT UNSIGNED NOT NULL,
			`snooze_until` INT UNSIGNED DEFAULT NULL,
			`note` VARCHAR(255) NOT NULL DEFAULT '',
			PRIMARY KEY (`kind`, `ref`),
			KEY `idx_dismissals_snooze` (`snooze_until`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	-- ------------------------------------------------------------- columns

	if not addColumn("console_users", "player_id", "INT DEFAULT NULL") then return false end
	if not addColumn("console_automations", "params", "LONGTEXT DEFAULT NULL") then return false end

	-- The Desk needs to know which of a player's characters a session belongs
	-- to when reading the fingerprint back, and player_sessions already has
	-- that. What it lacks is the level the session ended at for the peer band,
	-- which level_out covers -- so nothing is added there.

	return true
end
