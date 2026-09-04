local event = Event()

-- Bug reports filed with the in-game bug key.
--
-- These used to be appended to a text file under data/reports/bugs that nobody
-- read, and only staff could file one at all. They now go to the same
-- `bug_reports` table the Discord `/bug` command writes to, and any player can
-- file one -- a bug tracker that only the people who wrote the bug can post to
-- is not a bug tracker.
--
-- In-game reports carry the best provenance available: the account and the
-- character are known for certain, and so is where the player was standing,
-- which is often the whole answer for a map bug.
--
-- The write is async. A report that fails to store is a lost report; a
-- dispatcher blocked on a database write is a stutter every player feels. The
-- player is thanked either way -- telling somebody their report failed helps
-- nobody and invites them to send it three times.

-- One report per player per minute. Without this the bug key is a way to
-- write to the database as fast as a macro can press it.
local COOLDOWN_SECONDS = 60
local lastReport = {}

event.onReportBug = function(player, message)
	local guid = player:getGuid()
	local now = os.time()

	if lastReport[guid] and now - lastReport[guid] < COOLDOWN_SECONDS then
		player:sendTextMessage(MESSAGE_EVENT_DEFAULT,
		                       "You have just sent a report. Please wait a moment before sending another.")
		return true
	end
	lastReport[guid] = now

	local position = player:getPosition()
	local name = player:getName()

	local summary = message:gsub("[\r\n]+", " "):sub(1, 200)
	if summary == "" then summary = "(no summary)" end

	db.asyncQuery(string.format(
		"INSERT INTO `bug_reports` " ..
		"(`source`, `reporter_name`, `account_id`, `player_id`, `character_name`, " ..
		"`severity`, `area`, `summary`, `detail`, `pos_x`, `pos_y`, `pos_z`, " ..
		"`status`, `created_at`, `updated_at`) " ..
		"VALUES ('ingame', %s, %d, %d, %s, 'annoyance', 'ingame', %s, %s, %d, %d, %d, 'new', %d, %d)",
		db.escapeString(name),
		player:getAccountId(),
		guid,
		db.escapeString(name),
		db.escapeString(summary),
		db.escapeString(message),
		position.x, position.y, position.z,
		now, now
	))

	player:sendTextMessage(MESSAGE_EVENT_DEFAULT,
	                       "Your report has been sent to " .. configManager.getString(configKeys.SERVER_NAME) .. ".")
	return true
end

event:register()
