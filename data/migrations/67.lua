-- Item Bazaar (db_version 67 -> 68): store each listed item's Class.
--
-- Class is the item's power bracket (RarityClass.getItemClass in
-- data/lib/rarity/rarity_class.lua, derived from its level requirement or
-- fallback stats). It is what tells a buyer the scale of what they are looking
-- at -- "Class 7" means something very different from "Class 2" even at the
-- same rarity tier -- and neither the website nor the client could show it.
--
-- Captured at listing time rather than re-derived on each frontend on purpose:
-- the thresholds live in one Lua function, and duplicating them in PHP and in
-- the client is how they silently drift apart.

function onUpdateDatabase()
	logMigration("Updating database to version 68 (Item Bazaar: store item class)")

	local queries = {
		"ALTER TABLE `bazaar_items` ADD COLUMN `item_class` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `tier`",
		"ALTER TABLE `bazaar_auctions` ADD COLUMN `item_class` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `tier`",
	}

	for _, query in ipairs(queries) do
		if not db.query(query) then
			logMigration("Failed to add item_class columns")
			return false
		end
	end

	return true
end
