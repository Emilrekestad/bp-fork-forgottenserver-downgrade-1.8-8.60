-- Achievements: queryable catalogue and per-character record (db_version 73 -> 74).
--
-- The achievement ENGINE has always worked -- 398 achievements in
-- lib/core/achievements.lua, 188 award sites across the data tree, unlocks
-- written to `player_storage` at key 300000 + id. What has never existed is a
-- way to ASK anything about it.
--
-- Two things block every consumer:
--
--   1. Points are not derivable in SQL. They vary per achievement (2/3/5) and
--      live only inside a Lua file, so neither the website nor a highscore can
--      total them.
--   2. `player_storage`'s primary key is (player_id, key). A query filtered on
--      `key` alone cannot use it, so any cross-player ranking degrades to a
--      full table scan of the busiest table in the schema.
--
-- These tables fix both without touching the engine. `player_storage` remains
-- the runtime source of truth -- every hasAchievement() check, all 188 award
-- sites and the offline path are untouched -- and these are a mirror written
-- alongside it. That is deliberately additive: an achievement system that has
-- been correct for years is not worth re-plumbing to gain a leaderboard.
--
-- No foreign key from `player_achievements` to `achievements`. Retiring or
-- renumbering an achievement in the Lua catalogue must never erase the record
-- of someone having earned it -- the same reasoning `loyalty_claims` uses for
-- not keying to `loyalty_ladder`.

local STORAGE_BASE = 300000
local MAX_ACHIEVEMENT_ID = 1000 -- storages.lua reserves 300000-301000 for these

function onUpdateDatabase()
	logMigration("Updating database to version 74 (achievement catalogue and records)")

	-- Projection of the `achievements` table in lib/core/achievements.lua,
	-- rewritten by the server at startup. The website and the client window
	-- read from here rather than keeping their own copy, so the Lua file stays
	-- the single authored source and the halves cannot drift.
	--
	-- `owners` / `owners_permille` are the recomputed rarity of each
	-- achievement across the server. Permille rather than percent because the
	-- interesting end of this scale is below 1% -- a "0%" achievement tells a
	-- player nothing, "0.3%" tells them to go and get it.
	if not db.query([[
		CREATE TABLE IF NOT EXISTS `achievements` (
			`id` smallint unsigned NOT NULL,
			`name` varchar(64) NOT NULL,
			`grade` tinyint unsigned NOT NULL DEFAULT '1',
			`points` smallint unsigned NOT NULL DEFAULT '0',
			`secret` tinyint unsigned NOT NULL DEFAULT '0',
			`description` text NOT NULL,
			`owners` int unsigned NOT NULL DEFAULT '0',
			`owners_permille` smallint unsigned NOT NULL DEFAULT '0',
			PRIMARY KEY (`id`),
			KEY `by_grade` (`grade`),
			KEY `by_secret` (`secret`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8
	]]) then
		logMigration("Failed to create achievements")
		return false
	end

	-- One row per character per unlock. Written at the moment the achievement
	-- is earned rather than at player save, so the website is live instead of
	-- lagging behind whenever the character last logged out.
	if not db.query([[
		CREATE TABLE IF NOT EXISTS `player_achievements` (
			`player_id` int NOT NULL,
			`achievement_id` smallint unsigned NOT NULL,
			`unlocked_at` int unsigned NOT NULL DEFAULT '0',
			PRIMARY KEY (`player_id`, `achievement_id`),
			KEY `by_achievement` (`achievement_id`),
			FOREIGN KEY (`player_id`) REFERENCES `players`(`id`) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8
	]]) then
		logMigration("Failed to create player_achievements")
		return false
	end

	-- Derived, never authoritative: recomputed wholesale from the two tables
	-- above at every startup. Its only job is to make the highscore an indexed
	-- ORDER BY instead of a join-and-sum across every character on the server.
	if not db.query([[
		CREATE TABLE IF NOT EXISTS `player_achievement_summary` (
			`player_id` int NOT NULL,
			`unlocked` smallint unsigned NOT NULL DEFAULT '0',
			`points` smallint unsigned NOT NULL DEFAULT '0',
			`secrets` smallint unsigned NOT NULL DEFAULT '0',
			`last_unlocked_at` int unsigned NOT NULL DEFAULT '0',
			`updated_at` int unsigned NOT NULL DEFAULT '0',
			PRIMARY KEY (`player_id`),
			KEY `ranking` (`points`),
			FOREIGN KEY (`player_id`) REFERENCES `players`(`id`) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8
	]]) then
		logMigration("Failed to create player_achievement_summary")
		return false
	end

	-- Backfill every unlock already sitting in storage.
	--
	-- `value` is the unlock timestamp written by Player.addAchievement. Rows
	-- predating that (or set by hand) can carry 1, so anything positive counts
	-- as unlocked and only a real timestamp is kept as a date.
	--
	-- The summary is deliberately NOT backfilled here: points require the
	-- catalogue, which the server publishes at startup, after migrations run.
	-- AchievementsDB.rebuildAllSummaries() fills it on that first boot.
	local backfilled = db.query(string.format([[
		INSERT IGNORE INTO `player_achievements` (`player_id`, `achievement_id`, `unlocked_at`)
		SELECT s.`player_id`, s.`key` - %d, IF(s.`value` > 1000000, s.`value`, 0)
		FROM `player_storage` s
		JOIN `players` p ON p.`id` = s.`player_id`
		WHERE s.`key` > %d AND s.`key` <= %d AND s.`value` > 0
	]], STORAGE_BASE, STORAGE_BASE, STORAGE_BASE + MAX_ACHIEVEMENT_ID))

	if not backfilled then
		logMigration("Failed to backfill player_achievements from player_storage")
		return false
	end

	local resultId = db.storeQuery("SELECT COUNT(*) AS `n` FROM `player_achievements`")
	if resultId ~= false then
		logMigration(string.format("Backfilled %d achievement unlocks from player_storage",
			result.getNumber(resultId, "n")))
		result.free(resultId)
	end

	return true
end
