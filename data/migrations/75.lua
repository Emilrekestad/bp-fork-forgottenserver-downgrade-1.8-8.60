-- Bao's Ledger: queryable projection of the Ledger (db_version 75 -> 76).
--
-- The Ledger has always worked -- thirteen permanent, stacking tracks bought
-- with Marks, ranks written to `player:kv():scoped("bao"):scoped("ledger")`.
-- Nothing outside the game can read a word of it.
--
-- The blocker is not indexing, it is FORMAT. `kv_store.value` is a longblob
-- holding TFS's own serialised ValueWrapper; there is no honest way for PHP to
-- decode it, and no way at all to ORDER BY something inside it. So unlike
-- `player_storage` -- which the achievements mirror could at least backfill
-- from -- there is nothing here to backfill from. These tables start empty and
-- are filled by the game server:
--
--   * `bao_ledger_tracks` at startup, from BaoConfig.Ledger;
--   * `bao_ledger_summary` per character, on login and after every purchase.
--
-- That is not a gap. Ledger ranks can only change while a character is ONLINE
-- (BaoLedger.purchase runs from the shop window), so "written on login and on
-- purchase" means the mirror is never behind -- an offline character's row is
-- as of their last login, which is also as of their last possible change.
--
-- The kv store stays authoritative. Every effect accessor in bao_ledger.lua
-- still reads BaoLedger.getRank, and nothing in the game consults these tables.
--
-- No foreign key from `bao_ledger_summary` to `bao_ledger_tracks`: retiring a
-- track from the Lua config must not erase the record of the Marks someone
-- sank into it, the same reasoning `loyalty_claims` uses against keying to
-- `loyalty_ladder`.

function onUpdateDatabase()
	logMigration("Updating database to version 76 (Bao's Ledger projection)")

	-- Projection of BaoConfig.Ledger, rewritten by the server at startup the
	-- way Loyalty.publishLadder() rewrites `loyalty_ladder`. The website reads
	-- track names and the rank denominator from here rather than keeping a
	-- second copy of the config, so the two cannot drift.
	--
	-- Pending tracks (configured but not yet wired into the game) are NOT
	-- published: they are unbuyable, so counting their ranks in the
	-- denominator would quote players a total they can never reach.
	if not db.query([[
		CREATE TABLE IF NOT EXISTS `bao_ledger_tracks` (
			`track_key` varchar(32) NOT NULL,
			`book` tinyint unsigned NOT NULL DEFAULT '1',
			`ordering` tinyint unsigned NOT NULL DEFAULT '0',
			`name` varchar(48) NOT NULL,
			`summary` varchar(160) NOT NULL DEFAULT '',
			`effect` varchar(96) NOT NULL DEFAULT '',
			`per_rank` smallint unsigned NOT NULL DEFAULT '0',
			`max_rank` smallint unsigned NOT NULL DEFAULT '0',
			PRIMARY KEY (`track_key`),
			KEY `by_book` (`book`, `ordering`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8
	]]) then
		logMigration("Failed to create bao_ledger_tracks")
		return false
	end

	-- One row per character with at least one rank. Denormalised on purpose:
	-- the highscore is an indexed ORDER BY on `ranks`, and the board's detail
	-- line (deepest track, Marks invested) comes from the same row rather than
	-- from a second query per name.
	--
	-- `invested` is bigint: thirteen tracks on a 1.09-1.14 cost curve run to
	-- hundreds of millions of Marks at full rank.
	if not db.query([[
		CREATE TABLE IF NOT EXISTS `bao_ledger_summary` (
			`player_id` int NOT NULL,
			`ranks` smallint unsigned NOT NULL DEFAULT '0',
			`tracks_started` tinyint unsigned NOT NULL DEFAULT '0',
			`tracks_mastered` tinyint unsigned NOT NULL DEFAULT '0',
			`invested` bigint unsigned NOT NULL DEFAULT '0',
			`top_track` varchar(32) NOT NULL DEFAULT '',
			`top_rank` smallint unsigned NOT NULL DEFAULT '0',
			`updated_at` int unsigned NOT NULL DEFAULT '0',
			PRIMARY KEY (`player_id`),
			KEY `ranking` (`ranks`),
			FOREIGN KEY (`player_id`) REFERENCES `players`(`id`) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8
	]]) then
		logMigration("Failed to create bao_ledger_summary")
		return false
	end

	logMigration("Bao's Ledger projection created; the server fills it at startup and on login")
	return true
end
