-- The Desk: per-operator pinned tiles (db_version 86 -> 87).
--
-- Every other view in the console is composed by us: we decided what belongs
-- on Players and in what order, and that decision is the same for everybody.
-- The Desk is the one board the operator composes themselves -- pin any tile
-- from any view, drag it where you want it, size it to how much of it you
-- actually read.
--
-- Stored server-side rather than in the browser, deliberately. A layout in
-- localStorage is gone the moment you open the console on the laptop instead
-- of the desktop, or clear site data, and a board you have arranged by hand is
-- exactly the kind of thing that is annoying to lose and impossible to
-- reconstruct from memory. It is small, and it belongs to the person, not the
-- machine they happened to arrange it on.
--
-- Keyed on username rather than a user id because that is what the session
-- carries through to the tools; `console_users.username` is unique, and a
-- rename would drop a layout, which is the right failure for something this
-- cheap to rebuild.
--
-- `pin_id` is "<view>:<slug of the tile's title>", so a pin survives a tile
-- moving between views only if we say it does -- and breaks loudly (the tile
-- simply does not appear) rather than silently showing the wrong thing, if a
-- title is ever rewritten.

local function run(label, query)
	if db.query(query) then
		return true
	end
	logMigration("Failed to create " .. label)
	return false
end

function onUpdateDatabase()
	logMigration("Updating database to version 87 (desk pins)")

	if not run("console_pins", [[
		CREATE TABLE IF NOT EXISTS `console_pins` (
			`username` VARCHAR(32) NOT NULL,
			`pin_id` VARCHAR(96) NOT NULL,
			`position` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
			`span` TINYINT UNSIGNED NOT NULL DEFAULT 4,
			`added_at` INT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`username`, `pin_id`),
			KEY `idx_pins_order` (`username`, `position`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	return true
end
