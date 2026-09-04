-- Item Bazaar (db_version 64 -> 65).
--
-- Account-wide auction house for rarity equipment, priced in BP Coins
-- (`accounts`.`tibia_coins`). Deliberately separate from the existing
-- Character Bazaar (`character_auctions`, sells whole characters) and from
-- the Market (`market_offers`, priced in bank gold, quantity-based) -- this
-- one escrows exact single item instances.
--
-- Design notes that the column layout encodes:
--
--  * `bazaar_items` is BOTH the escrow table and the "Bazaar Inventory".
--    One row == one real item instance. `state` says where it currently
--    lives, and `item_uid` (the engine's own per-item snowflake, see
--    Item::generateItemUID in src/item.cpp) is UNIQUE so the same instance
--    can never be escrowed twice -- that unique index is the last line of
--    defence against a duplication bug, not merely a lookup key.
--
--  * `attributes` is the item's serializeAttr() blob, exactly as
--    player_items/player_inboxitems store it. It carries the full rarity
--    payload (tier, article, description, native stat bumps, __uid) with
--    zero loss. `tier`, `itemtype` and `item_name` are denormalised copies
--    purely so browse/filter/search can be indexed -- the blob stays
--    authoritative.
--
--  * Money movement is recorded in `bazaar_ledger` with a UNIQUE
--    `operation_id`, so a replayed or retried operation can never
--    double-credit. Note DBTransaction::executeWithinTransactionRollbackOnFailure
--    retries up to 3x on deadlock, which makes this non-optional.
--
--  * `bazaar_commands` is how backpackot.com performs mutations. The website
--    never writes auction/ledger/item rows itself; it enqueues a command and
--    the game server executes it through the same C++ domain functions the
--    game client uses. `idempotency_key` UNIQUE kills double-submits.

function onUpdateDatabase()
	logMigration("Updating database to version 65 (add Item Bazaar tables)")

	local queries = {
		[[CREATE TABLE IF NOT EXISTS `bazaar_items` (
			`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
			`item_uid` BIGINT UNSIGNED NOT NULL,
			`owner_account_id` INT NOT NULL,
			`origin_world_id` SMALLINT UNSIGNED NOT NULL DEFAULT 1,
			`itemtype` SMALLINT UNSIGNED NOT NULL,
			`count` SMALLINT NOT NULL DEFAULT 1,
			`tier` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`item_name` VARCHAR(255) NOT NULL DEFAULT '',
			`attributes` BLOB NOT NULL,
			`state` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`current_auction_id` INT UNSIGNED DEFAULT NULL,
			`source_player_id` INT DEFAULT NULL,
			`created_at` INT UNSIGNED NOT NULL,
			`updated_at` INT UNSIGNED NOT NULL,
			PRIMARY KEY (`id`),
			UNIQUE KEY `uq_bazaar_items_uid` (`item_uid`),
			KEY `idx_bazaar_items_owner_state` (`owner_account_id`, `state`),
			KEY `idx_bazaar_items_state_created` (`state`, `created_at`),
			KEY `idx_bazaar_items_auction` (`current_auction_id`),
			CONSTRAINT `fk_bazaar_items_owner` FOREIGN KEY (`owner_account_id`)
				REFERENCES `accounts` (`id`) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4]],

		[[CREATE TABLE IF NOT EXISTS `bazaar_auctions` (
			`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
			`item_id` INT UNSIGNED NOT NULL,
			`seller_account_id` INT NOT NULL,
			`origin_world_id` SMALLINT UNSIGNED NOT NULL DEFAULT 1,
			`itemtype` SMALLINT UNSIGNED NOT NULL,
			`tier` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`item_name` VARCHAR(255) NOT NULL DEFAULT '',
			`start_price` INT UNSIGNED NOT NULL,
			`buyout_price` INT UNSIGNED DEFAULT NULL,
			`current_bid` INT UNSIGNED NOT NULL DEFAULT 0,
			`current_bidder_account_id` INT DEFAULT NULL,
			`bid_count` INT UNSIGNED NOT NULL DEFAULT 0,
			`status` TINYINT UNSIGNED NOT NULL DEFAULT 1,
			`promoted` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`created_at` INT UNSIGNED NOT NULL,
			`starts_at` INT UNSIGNED NOT NULL,
			`ends_at` INT UNSIGNED NOT NULL,
			`settled_at` INT UNSIGNED DEFAULT NULL,
			`final_price` INT UNSIGNED DEFAULT NULL,
			`fee` INT UNSIGNED DEFAULT NULL,
			`winner_account_id` INT DEFAULT NULL,
			`settlement_reason` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`id`),
			KEY `idx_bazaar_auctions_status_ends` (`status`, `ends_at`),
			KEY `idx_bazaar_auctions_status_tier` (`status`, `tier`, `ends_at`),
			KEY `idx_bazaar_auctions_status_itemtype` (`status`, `itemtype`, `ends_at`),
			KEY `idx_bazaar_auctions_status_name` (`status`, `item_name`(64)),
			KEY `idx_bazaar_auctions_status_bid` (`status`, `current_bid`),
			KEY `idx_bazaar_auctions_status_buyout` (`status`, `buyout_price`),
			KEY `idx_bazaar_auctions_seller` (`seller_account_id`, `status`),
			KEY `idx_bazaar_auctions_bidder` (`current_bidder_account_id`, `status`),
			KEY `idx_bazaar_auctions_winner` (`winner_account_id`),
			KEY `idx_bazaar_auctions_item` (`item_id`),
			CONSTRAINT `fk_bazaar_auctions_item` FOREIGN KEY (`item_id`)
				REFERENCES `bazaar_items` (`id`) ON DELETE CASCADE,
			CONSTRAINT `fk_bazaar_auctions_seller` FOREIGN KEY (`seller_account_id`)
				REFERENCES `accounts` (`id`) ON DELETE CASCADE,
			CONSTRAINT `fk_bazaar_auctions_bidder` FOREIGN KEY (`current_bidder_account_id`)
				REFERENCES `accounts` (`id`) ON DELETE SET NULL,
			CONSTRAINT `fk_bazaar_auctions_winner` FOREIGN KEY (`winner_account_id`)
				REFERENCES `accounts` (`id`) ON DELETE SET NULL
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4]],

		[[CREATE TABLE IF NOT EXISTS `bazaar_bids` (
			`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
			`auction_id` INT UNSIGNED NOT NULL,
			`bidder_account_id` INT NOT NULL,
			`amount` INT UNSIGNED NOT NULL,
			`created_at` INT UNSIGNED NOT NULL,
			PRIMARY KEY (`id`),
			KEY `idx_bazaar_bids_auction` (`auction_id`, `created_at`),
			KEY `idx_bazaar_bids_bidder` (`bidder_account_id`, `created_at`),
			CONSTRAINT `fk_bazaar_bids_auction` FOREIGN KEY (`auction_id`)
				REFERENCES `bazaar_auctions` (`id`) ON DELETE CASCADE,
			CONSTRAINT `fk_bazaar_bids_bidder` FOREIGN KEY (`bidder_account_id`)
				REFERENCES `accounts` (`id`) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4]],

		-- Signed `amount`: positive credits the account, negative debits it.
		-- Summing this table per account must always explain every BP Coin the
		-- Bazaar ever moved.
		[[CREATE TABLE IF NOT EXISTS `bazaar_ledger` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`account_id` INT DEFAULT NULL,
			`auction_id` INT UNSIGNED DEFAULT NULL,
			`bid_id` INT UNSIGNED DEFAULT NULL,
			`type` TINYINT UNSIGNED NOT NULL,
			`amount` BIGINT NOT NULL,
			`operation_id` VARCHAR(80) NOT NULL,
			`created_at` INT UNSIGNED NOT NULL,
			PRIMARY KEY (`id`),
			UNIQUE KEY `uq_bazaar_ledger_operation` (`operation_id`),
			KEY `idx_bazaar_ledger_account` (`account_id`, `created_at`),
			KEY `idx_bazaar_ledger_auction` (`auction_id`),
			CONSTRAINT `fk_bazaar_ledger_account` FOREIGN KEY (`account_id`)
				REFERENCES `accounts` (`id`) ON DELETE SET NULL
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4]],

		-- Notification outbox. `account_id` NULL == a public announcement
		-- (the paid promotion). Consumed by the Item Bazaar chat channel;
		-- settlement never waits on delivery.
		[[CREATE TABLE IF NOT EXISTS `bazaar_events` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`account_id` INT DEFAULT NULL,
			`auction_id` INT UNSIGNED DEFAULT NULL,
			`type` TINYINT UNSIGNED NOT NULL,
			`payload` VARCHAR(512) NOT NULL DEFAULT '',
			`created_at` INT UNSIGNED NOT NULL,
			`delivered_at` INT UNSIGNED DEFAULT NULL,
			PRIMARY KEY (`id`),
			KEY `idx_bazaar_events_pending` (`delivered_at`, `created_at`),
			KEY `idx_bazaar_events_account` (`account_id`, `created_at`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4]],

		-- The website's only write path. Status: 0=PENDING 1=CLAIMED
		-- 2=DONE 3=FAILED.
		[[CREATE TABLE IF NOT EXISTS `bazaar_commands` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`account_id` INT NOT NULL,
			`action` VARCHAR(32) NOT NULL,
			`params` VARCHAR(1024) NOT NULL DEFAULT '',
			`idempotency_key` VARCHAR(80) NOT NULL,
			`status` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`result_code` TINYINT UNSIGNED NOT NULL DEFAULT 0,
			`result_message` VARCHAR(512) NOT NULL DEFAULT '',
			`created_at` INT UNSIGNED NOT NULL,
			`claimed_at` INT UNSIGNED DEFAULT NULL,
			`completed_at` INT UNSIGNED DEFAULT NULL,
			PRIMARY KEY (`id`),
			UNIQUE KEY `uq_bazaar_commands_idem` (`idempotency_key`),
			KEY `idx_bazaar_commands_pending` (`status`, `created_at`),
			KEY `idx_bazaar_commands_account` (`account_id`, `created_at`),
			CONSTRAINT `fk_bazaar_commands_account` FOREIGN KEY (`account_id`)
				REFERENCES `accounts` (`id`) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4]],

		-- Append-only investigation trail. Mirrors character_auction_history.
		[[CREATE TABLE IF NOT EXISTS `bazaar_audit` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`auction_id` INT UNSIGNED DEFAULT NULL,
			`item_id` INT UNSIGNED DEFAULT NULL,
			`item_uid` BIGINT UNSIGNED DEFAULT NULL,
			`action` VARCHAR(64) NOT NULL,
			`account_id` INT DEFAULT NULL,
			`player_id` INT DEFAULT NULL,
			`amount` BIGINT NOT NULL DEFAULT 0,
			`message` TEXT DEFAULT NULL,
			`created_at` INT UNSIGNED NOT NULL,
			PRIMARY KEY (`id`),
			KEY `idx_bazaar_audit_auction` (`auction_id`, `created_at`),
			KEY `idx_bazaar_audit_item` (`item_id`),
			KEY `idx_bazaar_audit_uid` (`item_uid`),
			KEY `idx_bazaar_audit_account` (`account_id`, `created_at`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4]],
	}

	for _, query in ipairs(queries) do
		if not db.query(query) then
			logMigration("Failed to create Item Bazaar tables")
			return false
		end
	end

	return true
end
