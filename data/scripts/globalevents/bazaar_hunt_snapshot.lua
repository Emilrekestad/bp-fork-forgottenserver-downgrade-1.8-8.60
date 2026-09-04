-- Daily snapshot of server-wide bestiary kill totals.
--
-- Feeds the Item Bazaar's "What are people hunting?" board. `player_bestiary_
-- kills` holds running totals with no timestamps, so a window of activity can
-- only be recovered by differencing two snapshots taken at known times.
--
-- Fires just BEFORE server save (which runs at 09:55 and may shut the server
-- down, per SERVER_SAVE_SHUTDOWN in serversave.lua) -- taking it after would
-- mean never taking it at all on a shutdown save. One snapshot a day is
-- exactly what a 24h window needs.
--
-- A catch-up pass also runs hourly: if the newest snapshot is more than a day
-- old -- the server was down at 09:50, or has just been set up -- one is taken
-- immediately rather than leaving the board without a baseline until tomorrow.

local SNAPSHOT_TIME = "09:50:00"
local STALE_AFTER = 25 * 60 * 60   -- seconds before the hourly catch-up steps in
local RETENTION = 8 * 24 * 60 * 60 -- keep just over a week of history

local function newestSnapshot()
	local row = db.storeQuery("SELECT MAX(`taken_at`) AS `newest` FROM `bazaar_hunt_snapshots`")
	if not row then
		return 0
	end
	local newest = result.getNumber(row, "newest") or 0
	result.free(row)
	return newest
end

local function takeSnapshot()
	local now = os.time()
	-- One statement: the totals are read and written inside the database, so
	-- there is no window where a kill landing mid-loop is counted twice or
	-- missed entirely.
	db.query(string.format(
		"INSERT IGNORE INTO `bazaar_hunt_snapshots` (`taken_at`, `raceid`, `kills`) " ..
		"SELECT %d, `raceid`, SUM(`kills`) FROM `player_bestiary_kills` GROUP BY `raceid`", now))
	db.query(string.format("DELETE FROM `bazaar_hunt_snapshots` WHERE `taken_at` < %d", now - RETENTION))
end

local daily = GlobalEvent("BazaarHuntSnapshotDaily")

function daily.onTime(interval)
	takeSnapshot()
	return true
end

daily:time(SNAPSHOT_TIME)
daily:register()

-- Catch-up. Only acts when the daily pass has been missed, so on a healthy
-- server this is one cheap MAX() every five minutes and nothing more.
--
-- Five minutes rather than an hour because a GlobalEvent interval counts from
-- server start: a server restarted more often than the interval would never
-- fire it at all, and so would never take a first snapshot.
local catchup = GlobalEvent("BazaarHuntSnapshotCatchup")

function catchup.onThink(interval)
	local newest = newestSnapshot()
	if newest == 0 or (os.time() - newest) >= STALE_AFTER then
		takeSnapshot()
	end
	return true
end

catchup:interval(5 * 60 * 1000)
catchup:register()
