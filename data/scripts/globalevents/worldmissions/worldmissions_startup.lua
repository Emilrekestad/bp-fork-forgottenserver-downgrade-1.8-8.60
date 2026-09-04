-- World Missions — boot-time reapply. A live Tile:addItem/remove edit only
-- exists in server memory; there is no Game.saveMap() binding in this
-- fork, so it doesn't survive a restart on its own. Every already-applied
-- mission's onComplete gets silently re-run once here, at real server
-- startup (same "startup" GlobalEvent type already proven in
-- data/scripts/globalevents/#startup.lua) -- a second, separate
-- registration rather than touching that file.
--
-- applyPendingCompletions() runs FIRST, specifically to catch a mission
-- that reached its threshold before this file existed/before completion
-- became instant (e.g. Liberty Bay sitting at 4/4 from before this fix)
-- -- otherwise nothing would ever call it again for that mission, since
-- every one of its levers is already activated and won't fire another
-- progress update. Safe to run every boot regardless -- a no-op for
-- anything already applied.
local worldMissionsStartup = GlobalEvent("WorldMissionsStartup")

function worldMissionsStartup.onStartup()
	WorldMissions.applyPendingCompletions()
	WorldMissions.reapplyActivationVisuals()
	WorldMissions.reapplyOnBoot()
	return true
end

worldMissionsStartup:type("startup")
worldMissionsStartup:register()
