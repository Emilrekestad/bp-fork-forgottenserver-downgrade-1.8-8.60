-- Showcased achievement (db_version 74 -> 75).
--
-- One achievement a player nominates in the client to represent them on their
-- public character page. The website used to list every achievement a
-- character held, which on a completed character is 398 rows of table -- it
-- buried the page it was supposed to decorate. A single nominated achievement
-- is the brag; the full catalogue is what the client window is for.
--
-- Lives on the summary rather than in `player_storage` for one reason: storage
-- only reaches the database when the character saves, so a nomination made at
-- 20:00 would not appear on the website until logout. This is written the
-- moment the player picks it.
--
-- Safe against the startup rebuild: rebuildAllSummaries upserts only the
-- counted columns, so this one is carried through untouched. The orphan sweep
-- can delete the row, but only for a character holding no achievements -- who
-- by definition has nothing nominated.

function onUpdateDatabase()
	logMigration("Updating database to version 75 (showcased achievement)")

	if not db.query([[
		ALTER TABLE `player_achievement_summary`
		ADD COLUMN `showcase_id` smallint unsigned NOT NULL DEFAULT '0'
	]]) then
		logMigration("Failed to add player_achievement_summary.showcase_id")
		return false
	end

	return true
end
