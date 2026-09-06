-- Stored briefings (db_version 85 -> 86).
--
-- The console's Trends view ends in a written assessment: what the numbers
-- say about the state of the server, and what could be done about it. It is
-- produced by the model from the same tools everything else on the view uses.
--
-- It is stored rather than regenerated on every page load for two reasons,
-- and the second is the important one.
--
-- 1. Each run costs real money and takes the better part of a minute. A page
--    that quietly bills the owner every time it is opened is a page nobody
--    should have built.
--
-- 2. **A briefing is only useful next to the one before it.** "Activity is
--    down" means little; "activity is down, and it was flat when we last
--    looked a week ago, and the action we took in between was X" is the thing
--    that actually steers a server. Keeping the history is what makes the
--    assessment a series rather than a horoscope.
--
-- `window_days` is stored because a fourteen-day briefing and a ninety-day
-- briefing are not comparable, and reading two of them side by side without
-- knowing which was which would be worse than reading neither.

local function run(label, query)
	if db.query(query) then
		return true
	end
	logMigration("Failed to create " .. label)
	return false
end

function onUpdateDatabase()
	logMigration("Updating database to version 86 (stored briefings)")

	if not run("console_briefings", [[
		CREATE TABLE IF NOT EXISTS `console_briefings` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`generated_at` INT UNSIGNED NOT NULL,
			`generated_by` VARCHAR(32) NOT NULL DEFAULT '',
			`window_days` SMALLINT UNSIGNED NOT NULL DEFAULT 14,
			`model` VARCHAR(64) NOT NULL DEFAULT '',
			`markdown` MEDIUMTEXT NOT NULL,
			`input_tokens` INT UNSIGNED NOT NULL DEFAULT 0,
			`output_tokens` INT UNSIGNED NOT NULL DEFAULT 0,
			`tool_calls` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`id`),
			KEY `idx_briefings_time` (`generated_at`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]]) then return false end

	return true
end
