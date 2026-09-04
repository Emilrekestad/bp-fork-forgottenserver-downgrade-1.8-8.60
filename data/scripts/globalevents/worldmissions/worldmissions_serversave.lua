-- World Missions — safety net, not the primary trigger. Originally this
-- WAS how completion applied (deferred to the daily server save) --
-- changed after live testing showed a completed mission producing no
-- visible reaction until the next save felt broken, not deliberate. Every
-- real progress mutation (worldmissions_state.lua's setProgress/
-- addItemProgress) now calls WorldMissions.applyPendingCompletions()
-- directly and instantly. This registration on the real, already-existing
-- daily ServerSave GlobalEvent (data/scripts/globalevents/serversave.lua,
-- 09:55 server time -- a second handler on the same "ServerSave" onTime
-- hook, same multiple-handlers-on-one-event pattern already proven in
-- data/npc/scripts/default_onGainExperience.lua) just re-checks everything
-- once a day in case anything was ever missed (e.g. a direct DB edit) --
-- harmless, since applyPendingCompletions() is a no-op for anything
-- already applied.
local worldMissionsSave = GlobalEvent("WorldMissionsServerSave")

function worldMissionsSave.onTime(interval)
	WorldMissions.applyPendingCompletions()
	return true
end

worldMissionsSave:time("09:55:00")
worldMissionsSave:register()
