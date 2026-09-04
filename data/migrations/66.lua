-- Item Bazaar (db_version 66 -> 67): snapshot each escrowed item's rarity
-- description so buyers can see what they are bidding on.
--
-- Until now the Bazaar stored only `item_name` and the serialized attributes
-- blob. The blob carries the full instance (including every rarity bonus),
-- but nothing outside the game server can read it -- so the website and the
-- client could show "Superior sanguine claws" and the auction state, and
-- nothing else. Buyers had no way to see the bonuses that make a rarity item
-- worth bidding on, which defeats the point of the marketplace.
--
-- `item_description` holds ITEM_ATTRIBUTE_DESCRIPTION as captured at listing
-- time -- the same text a player sees when looking at the item, which is
-- where data/lib/rarity/rarity_stats.lua writes its bracketed bonus lines.
-- Denormalised deliberately, exactly like `item_name` and `tier`: the blob
-- stays authoritative for the item itself, this is presentation data.
--
-- Dormant items are safe to expose here: their description is only the
-- "pulses with dormant power" flavour text. A Dormant item genuinely has no
-- rolled stats yet (the roll happens live when a Dormant Waker is used), so
-- there is nothing hidden to leak.

function onUpdateDatabase()
	logMigration("Updating database to version 67 (Item Bazaar: store item descriptions)")

	local queries = {
		"ALTER TABLE `bazaar_items` ADD COLUMN `item_description` TEXT DEFAULT NULL AFTER `item_name`",
		"ALTER TABLE `bazaar_auctions` ADD COLUMN `item_description` TEXT DEFAULT NULL AFTER `item_name`",
	}

	for _, query in ipairs(queries) do
		if not db.query(query) then
			logMigration("Failed to add item_description columns")
			return false
		end
	end

	return true
end
