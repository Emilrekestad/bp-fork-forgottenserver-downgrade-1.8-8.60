-- Loyalty premium ledger (db_version 72 -> 73).
--
-- `accounts.premium_ends_at` is a deadline, not a history: it cannot answer
-- "how many days has this account held premium". These tables record that
-- history going forward, one row per premium account per day.
--
-- Rewards unlock on the COUNT of those rows. There is no points currency and
-- no multiplier -- a day is a day. The streak is tracked as a counter for
-- display only, and gates nothing, so a lapse costs the days missed and
-- nothing that was already earned.
--
-- `loyalty_stamp_days` records which days the stamper actually ran. It is the
-- only way to tell a day nobody held premium from a day the server was down --
-- without it an outage is indistinguishable from mass expiry, every streak
-- breaks because the hardware hiccuped, and there is no way to audit the
-- ledger after the fact.

function onUpdateDatabase()
	logMigration("Updating database to version 73 (loyalty premium ledger)")

	if not db.query([[
		CREATE TABLE IF NOT EXISTS `loyalty_premium_log` (
			`account_id` int NOT NULL,
			`day` date NOT NULL,
			PRIMARY KEY (`account_id`, `day`),
			FOREIGN KEY (`account_id`) REFERENCES `accounts`(`id`) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8
	]]) then
		logMigration("Failed to create loyalty_premium_log")
		return false
	end

	if not db.query([[
		CREATE TABLE IF NOT EXISTS `loyalty_stamp_days` (
			`day` date NOT NULL,
			`stamped_at` int unsigned NOT NULL DEFAULT '0',
			`accounts` int unsigned NOT NULL DEFAULT '0',
			PRIMARY KEY (`day`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8
	]]) then
		logMigration("Failed to create loyalty_stamp_days")
		return false
	end

	-- Derived state. Recomputed from the ledger, never authoritative, so the
	-- reward thresholds can change later without corrupting history.
	if not db.query([[
		CREATE TABLE IF NOT EXISTS `loyalty_account` (
			`account_id` int NOT NULL,
			`premium_days` int unsigned NOT NULL DEFAULT '0',
			`streak_days` int unsigned NOT NULL DEFAULT '0',
			`best_streak` int unsigned NOT NULL DEFAULT '0',
			`primary_player_id` int NOT NULL DEFAULT '0',
			`updated_at` int unsigned NOT NULL DEFAULT '0',
			PRIMARY KEY (`account_id`),
			KEY `ranking` (`premium_days`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8
	]]) then
		logMigration("Failed to create loyalty_account")
		return false
	end

	-- Claim queue. The website NEVER writes items: it inserts a row here and
	-- the server delivers on login. See loyalty_login.lua.
	-- UNIQUE(account_id, reward_id) makes double-claiming a DB error rather
	-- than a race the PHP has to be careful about.
	--
	-- No foreign key to loyalty_ladder on purpose: retiring a reward from the
	-- config must never erase the record of someone having received it.
	if not db.query([[
		CREATE TABLE IF NOT EXISTS `loyalty_claims` (
			`id` int NOT NULL AUTO_INCREMENT,
			`account_id` int NOT NULL,
			`reward_id` varchar(64) NOT NULL,
			`player_id` int NOT NULL,
			`status` enum('pending','delivered','failed') NOT NULL DEFAULT 'pending',
			`created_at` int unsigned NOT NULL DEFAULT '0',
			`delivered_at` int unsigned NOT NULL DEFAULT '0',
			`note` varchar(255) NOT NULL DEFAULT '',
			PRIMARY KEY (`id`),
			UNIQUE KEY `account_reward` (`account_id`, `reward_id`),
			KEY `pending_lookup` (`player_id`, `status`),
			FOREIGN KEY (`account_id`) REFERENCES `accounts`(`id`) ON DELETE CASCADE,
			FOREIGN KEY (`player_id`) REFERENCES `players`(`id`) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8
	]]) then
		logMigration("Failed to create loyalty_claims")
		return false
	end

	-- Projection of LoyaltyConfig, rewritten by the server on every startup.
	-- The website renders the ladder from here rather than keeping its own
	-- copy, so the Lua config stays the single authored source and the two
	-- halves cannot drift into disagreeing about what a reward costs.
	if not db.query([[
		CREATE TABLE IF NOT EXISTS `loyalty_ladder` (
			`reward_id` varchar(64) NOT NULL,
			`days` int unsigned NOT NULL DEFAULT '0',
			`kind` varchar(16) NOT NULL DEFAULT '',
			`name` varchar(64) NOT NULL DEFAULT '',
			`description` varchar(255) NOT NULL DEFAULT '',
			`item_id` int unsigned NOT NULL DEFAULT '0',
			`count` int unsigned NOT NULL DEFAULT '1',
			-- Preview artwork. Items render from local sprite files by item_id;
			-- outfits and mounts render through the site's outfit imager, which
			-- takes a looktype. For a mount that looktype is its CLIENT id from
			-- mounts.xml (Foxmouse is server 218 / client 1632), not its
			-- server id -- the imager knows nothing about server ids.
			`look_type` int unsigned NOT NULL DEFAULT '0',
			`look_addons` tinyint unsigned NOT NULL DEFAULT '0',
			PRIMARY KEY (`reward_id`),
			KEY `by_days` (`days`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8
	]]) then
		logMigration("Failed to create loyalty_ladder")
		return false
	end

	-- Seed today so the ledger starts from the first boot after this migration
	-- rather than from whenever the globalevent first fires.
	local today = os.date("%Y-%m-%d")
	db.query(string.format([[
		INSERT IGNORE INTO `loyalty_premium_log` (`account_id`, `day`)
		SELECT `id`, %s FROM `accounts` WHERE `premium_ends_at` > %d
	]], db.escapeString(today), os.time()))

	db.query(string.format([[
		INSERT INTO `loyalty_stamp_days` (`day`, `stamped_at`, `accounts`)
		VALUES (%s, %d, (SELECT COUNT(*) FROM `loyalty_premium_log` WHERE `day` = %s))
		ON DUPLICATE KEY UPDATE `stamped_at` = VALUES(`stamped_at`), `accounts` = VALUES(`accounts`)
	]], db.escapeString(today), os.time(), db.escapeString(today)))

	logMigration("Loyalty ledger seeded for " .. today)
	return true
end
