-- Persistence hardening: referential constraints on the player tables (db_version 96 -> 97).
-- docs/security/ audit 2026-10-05, persistence area.
--
-- Nothing here changes what the server writes. Every statement adds a
-- constraint the data already satisfies, so a correct server never notices
-- them; they exist to turn a silent corruption into a loud query error and to
-- make a character deletion take its dependent rows with it.
--
-- 1. `player_items` gets UNIQUE (`player_id`, `sid`). The other four item
--    tables (depot, inbox, store inbox, reward) have had this key since the
--    original schema; the inventory table never did, so a double-written
--    inventory (two rows for one slot) would load as two items. The save
--    path always writes a fresh set of ascending sids inside one transaction
--    (IOLoginData::saveItems), and MyAAC's starter-item copy reuses the sids
--    of a saved sample character, so the key is never violated by correct code.
--
-- 2. ON DELETE CASCADE foreign keys to `players` on the game-data tables that
--    carried a `player_id` without one: bestiary, bosstiary, mounts, autoloot,
--    Bao's Ledger, hunting tasks. Without them `DELETE FROM players` (the
--    startup sweep of characters past their deletion date, and the site's
--    character deletion) leaves rows behind that nothing ever reads again, and
--    a new character that happens to reuse an id would inherit them.
--    All of these columns are INT(11) like `players`.`id`, which InnoDB
--    requires for a foreign key.
--
-- Every step is idempotent (checked against information_schema first) and
-- every step is skipped WITH A LOGGED WARNING when the data would violate it,
-- so this migration can never stop the server from booting on a database
-- that needs a manual clean-up first. A skipped step is reported by
-- tools/security/persistence/consistency-check.sql (section "schema
-- constraints that are still missing"), which is the place to look if a
-- warning is seen at boot.
--
-- Verified 2026-10-05 against a copy of the production database
-- (dump 2026-10-04 04:30 UTC, db_version 96): zero duplicate (player_id, sid)
-- pairs in player_items and zero orphan rows in every table below, so on
-- production every step applies.
--
-- No CHECK constraints are added: every balance, coin and premium column is
-- already UNSIGNED (players.balance, accounts.tibia_coins,
-- accounts.premium_ends_at, guilds.balance, coin_ledger.balance_after), which
-- the server runs in STRICT_TRANS_TABLES mode, so an underflow is already a
-- failed UPDATE rather than a negative number.

local function scalar(query)
	local resultId = db.storeQuery(query)
	if not resultId then
		return nil
	end
	local value = result.getNumber(resultId, "n")
	result.free(resultId)
	return value
end

local function tableExists(tableName)
	return (scalar(string.format(
		"SELECT COUNT(*) AS `n` FROM `information_schema`.`TABLES` " ..
		"WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = %s",
		db.escapeString(tableName))) or 0) > 0
end

local function constraintExists(tableName, constraintName)
	return (scalar(string.format(
		"SELECT COUNT(*) AS `n` FROM `information_schema`.`TABLE_CONSTRAINTS` " ..
		"WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = %s AND `CONSTRAINT_NAME` = %s",
		db.escapeString(tableName), db.escapeString(constraintName))) or 0) > 0
end

local function columnType(tableName, columnName)
	local resultId = db.storeQuery(string.format(
		"SELECT `COLUMN_TYPE` FROM `information_schema`.`COLUMNS` " ..
		"WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = %s AND `COLUMN_NAME` = %s",
		db.escapeString(tableName), db.escapeString(columnName)))
	if not resultId then
		return nil
	end
	local value = result.getString(resultId, "COLUMN_TYPE")
	result.free(resultId)
	return value
end

-- 1. UNIQUE (player_id, sid) on player_items -------------------------------

local function addInventoryUniqueKey()
	if constraintExists("player_items", "player_id_2") then
		return
	end
	local duplicates = scalar(
		"SELECT COUNT(*) AS `n` FROM (SELECT `player_id`, `sid` FROM `player_items` " ..
		"GROUP BY `player_id`, `sid` HAVING COUNT(*) > 1) AS `d`")
	if duplicates == nil then
		logMigration("[96] could not count duplicate (player_id, sid) rows in player_items; skipping the unique key")
		return
	end
	if duplicates > 0 then
		logMigration(string.format(
			"[96] WARNING: player_items has %d duplicate (player_id, sid) pairs; UNIQUE KEY player_id_2 NOT added. " ..
			"Clean the duplicates (see tools/security/persistence/consistency-check.sql) and re-run this step by hand.",
			duplicates))
		return
	end
	if db.query("ALTER TABLE `player_items` ADD UNIQUE KEY `player_id_2` (`player_id`, `sid`)") then
		logMigration("[96] player_items: added UNIQUE KEY player_id_2 (player_id, sid)")
	else
		logMigration("[96] WARNING: failed to add UNIQUE KEY player_id_2 to player_items")
	end
end

-- 2. ON DELETE CASCADE foreign keys to players -----------------------------

local PLAYER_FK_TABLES = {
	"player_mounts",
	"player_bestiary_charms",
	"player_bestiary_resources",
	"player_bestiary_tracker",
	"player_bosstiary",
	"player_bosstiary_tracker",
	"player_autolootconfig",
	"bao_player",
	"bao_active_hunts",
	"player_hunting_tasks",
	"player_hunting_task_points",
}

local function addPlayerForeignKey(tableName)
	if not tableExists(tableName) then
		return
	end
	local constraintName = "fk_" .. tableName .. "_player"
	if constraintExists(tableName, constraintName) then
		return
	end
	local playersIdType = columnType("players", "id")
	local columnTypeHere = columnType(tableName, "player_id")
	if not columnTypeHere or columnTypeHere ~= playersIdType then
		logMigration(string.format(
			"[96] WARNING: %s.player_id is %s but players.id is %s; foreign key NOT added (types must match).",
			tableName, tostring(columnTypeHere), tostring(playersIdType)))
		return
	end
	local orphans = scalar(string.format(
		"SELECT COUNT(*) AS `n` FROM `%s` AS `x` LEFT JOIN `players` AS `p` ON `p`.`id` = `x`.`player_id` " ..
		"WHERE `p`.`id` IS NULL", tableName))
	if orphans == nil then
		logMigration(string.format("[96] could not count orphan rows in %s; skipping its foreign key", tableName))
		return
	end
	if orphans > 0 then
		logMigration(string.format(
			"[96] WARNING: %s has %d rows whose player_id matches no player; foreign key NOT added. " ..
			"Delete them (DELETE x FROM `%s` x LEFT JOIN players p ON p.id = x.player_id WHERE p.id IS NULL) and re-run by hand.",
			tableName, orphans, tableName))
		return
	end
	if db.query(string.format(
		"ALTER TABLE `%s` ADD CONSTRAINT `%s` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE",
		tableName, constraintName)) then
		logMigration(string.format("[96] %s: added %s ON DELETE CASCADE", tableName, constraintName))
	else
		logMigration(string.format("[96] WARNING: failed to add %s to %s", constraintName, tableName))
	end
end

function onUpdateDatabase()
	logMigration("Updating database to version 97 (persistence hardening: player table constraints)")

	addInventoryUniqueKey()
	for _, tableName in ipairs(PLAYER_FK_TABLES) do
		addPlayerForeignKey(tableName)
	end

	return true
end
