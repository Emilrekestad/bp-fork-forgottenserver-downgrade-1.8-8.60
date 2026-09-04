-- Item Bazaar (db_version 69 -> 70): daily hunting snapshots.
--
-- `player_bestiary_kills` is a running total per player+race with NO timestamp,
-- so "what did people kill in the last 24 hours" cannot be derived from it
-- directly. This table stores periodic snapshots of the server-wide total per
-- race; the difference between two snapshots is the kills in that window.
--
-- Snapshots are taken by data/scripts/globalevents/bazaar_hunt_snapshot.lua,
-- which runs hourly and records one only when the newest is 12h old. Doing it
-- on an interval-since-boot instead would drift every time the server
-- restarts, and a server that restarts often would never take one at all.

function onUpdateDatabase()
	logMigration("Updating database to version 70 (Item Bazaar: hunting snapshots)")

	if not db.query([[
		CREATE TABLE IF NOT EXISTS `bazaar_hunt_snapshots` (
			`taken_at` INT UNSIGNED NOT NULL,
			`raceid` SMALLINT UNSIGNED NOT NULL,
			`kills` INT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`taken_at`, `raceid`),
			KEY `idx_bazaar_hunt_taken` (`taken_at`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8
	]]) then
		logMigration("Failed to create bazaar_hunt_snapshots")
		return false
	end

	return true
end
