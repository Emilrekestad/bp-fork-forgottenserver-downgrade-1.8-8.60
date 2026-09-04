-- Item Bazaar fix (db_version 65 -> 66): stop withdrawals from destroying
-- auction history.
--
-- Found during Phase 1 live testing: after listing, cancelling and then
-- withdrawing an item, `bazaar_auctions` was empty. Cause: the auction's
-- `item_id` foreign key was ON DELETE CASCADE, and withdrawItem() deletes the
-- `bazaar_items` row (correct -- the instance leaves the Bazaar, and the
-- UNIQUE index on item_uid has to be freed so the same item can be listed
-- again later). The cascade took the auction, and its bids, with it.
--
-- That wiped sale prices, fees, winners and the whole settlement record --
-- exactly the data the admin/investigation and recovery requirements depend
-- on. Auctions must outlive the item they sold.
--
-- Fix: item_id becomes nullable with ON DELETE SET NULL, and the auction
-- carries its own copy of `item_uid` so an auction still identifies which
-- exact instance it sold after the escrow row is gone.

function onUpdateDatabase()
	logMigration("Updating database to version 66 (Item Bazaar: preserve auction history)")

	local queries = {
		"ALTER TABLE `bazaar_auctions` DROP FOREIGN KEY `fk_bazaar_auctions_item`",
		"ALTER TABLE `bazaar_auctions` MODIFY `item_id` INT UNSIGNED DEFAULT NULL",
		"ALTER TABLE `bazaar_auctions` ADD COLUMN `item_uid` BIGINT UNSIGNED DEFAULT NULL AFTER `item_id`",
		"ALTER TABLE `bazaar_auctions` ADD KEY `idx_bazaar_auctions_item_uid` (`item_uid`)",
		[[ALTER TABLE `bazaar_auctions` ADD CONSTRAINT `fk_bazaar_auctions_item`
			FOREIGN KEY (`item_id`) REFERENCES `bazaar_items` (`id`) ON DELETE SET NULL]],
	}

	for _, query in ipairs(queries) do
		if not db.query(query) then
			logMigration("Failed to alter bazaar_auctions")
			return false
		end
	end

	return true
end
