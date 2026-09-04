-- Item Bazaar (db_version 68 -> 69): store each listed item's equipment
-- category, so browsing can be filtered by what an item IS.
--
-- Until now the only way to narrow a browse was rarity tier, a free-text name
-- search, and "buyout only". Searching by name is a poor substitute for a real
-- filter: a player looking for a shield has to already know that "falcon
-- shield" and "sanguine coil" are, respectively, a shield and a wand.
--
-- The value is derived server-side in ItemBazaar::getItemCategory (from the
-- ItemType's weaponType, falling back to slotPosition) rather than supplied by
-- a frontend -- it is filter data, but it is also something a client could
-- otherwise use to mislabel its own listing.
--
-- Existing rows stay at 0 (Unknown) until `/bazaar backfill` fills them in.

function onUpdateDatabase()
	logMigration("Updating database to version 69 (Item Bazaar: store item category)")

	local queries = {
		"ALTER TABLE `bazaar_items` ADD COLUMN `item_category` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `item_class`",
		"ALTER TABLE `bazaar_auctions` ADD COLUMN `item_category` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `item_class`",
		-- Matches the browse query shape: active auctions of one category,
		-- ordered by whichever sort the player picked.
		"ALTER TABLE `bazaar_auctions` ADD INDEX `status_category` (`status`, `item_category`)",
	}

	for _, query in ipairs(queries) do
		if not db.query(query) then
			logMigration("Failed to add item_category columns")
			return false
		end
	end

	return true
end
