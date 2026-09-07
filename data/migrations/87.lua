-- Interventions and live tuning (db_version 87 -> 88).
--
-- Two tables, one idea: closing the loop between reading the server and
-- steering it.
--
-- `interventions` is the ledger of things we DID to the world -- a boost run,
-- a raid forced, a broadcast sent, a restart, a rate changed, a note that the
-- website launched. Every chart in the console draws these as marks on its
-- time axis, and every one can be asked "what happened before, during and
-- after". Without it the console can say that Saturday concurrency rose and
-- cannot say that it rose because of the double-loot weekend you ran, and a
-- briefing that cannot tell those apart is a horoscope.
--
-- `server_tuning` is a set of knobs the game server reads live: base rate
-- multipliers, boost magnitudes, the rarity system's testing/live switch, and
-- feature circuit-breakers. They used to be constants in Lua files, which
-- meant "turn the rarity rates down for launch" was a file edit and a restart.
-- The game server keeps an in-memory copy and re-reads on a timer, so a change
-- from the console lands within seconds and survives a restart.
--
-- Changes to tuning are themselves interventions: a rate change is exactly
-- the kind of thing you want a mark on the chart for.

local function run(label, query)
	if db.query(query) then
		return true
	end
	logMigration("Failed to create " .. label)
	return false
end

function onUpdateDatabase()
	logMigration("Updating database to version 88 (interventions, live tuning)")

	if not run("interventions", [[
		CREATE TABLE IF NOT EXISTS `interventions` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`kind` VARCHAR(32) NOT NULL,
			`label` VARCHAR(160) NOT NULL,
			`started_at` INT UNSIGNED NOT NULL,
			`ended_at` INT UNSIGNED DEFAULT NULL,
			`actor` VARCHAR(32) NOT NULL DEFAULT '',
			`source` ENUM('action','tuning','manual','system') NOT NULL DEFAULT 'manual',
			`detail` TEXT DEFAULT NULL,
			`note` TEXT DEFAULT NULL,
			`audit_id` BIGINT UNSIGNED DEFAULT NULL,
			`created_at` INT UNSIGNED NOT NULL,
			PRIMARY KEY (`id`),
			KEY `idx_interventions_time` (`started_at`),
			KEY `idx_interventions_kind` (`kind`, `started_at`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	if not run("server_tuning", [[
		CREATE TABLE IF NOT EXISTS `server_tuning` (
			`key` VARCHAR(48) NOT NULL,
			`value` VARCHAR(64) NOT NULL,
			`updated_at` INT UNSIGNED NOT NULL,
			`updated_by` VARCHAR(32) NOT NULL DEFAULT '',
			PRIMARY KEY (`key`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	return true
end
