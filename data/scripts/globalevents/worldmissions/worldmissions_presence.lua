-- World Missions — Presence tracking. Unlike Cull/Delivery/Activation,
-- there's no single trigger moment for "N players standing in a Zone at
-- once" -- it's a live occupancy check, so it needs a poll rather than an
-- event. Same GlobalEvent onThink/:interval() shape already proven in
-- this codebase (data/scripts/globalevents/guild_war_expire.lua).
--
-- Not additive like the other types -- getProgress just gets set straight
-- to the mission's own threshold the instant enough players are
-- simultaneously present, since a partial headcount isn't meaningful
-- progress for a coordination check.
local WORLDMISSIONS_PRESENCE_POLL_MS = 5000

local presencePoll = GlobalEvent("WorldMissionsPresencePoll")

function presencePoll.onThink(interval)
	for missionId, mission in pairs(WorldMissions.Missions) do
		if mission.type == "presence" and not WorldMissions.isApplied(missionId)
				and WorldMissions.getProgress(missionId) < mission.threshold then
			local zone = Zone(mission.zone)
			if zone:countPlayers() >= mission.threshold then
				WorldMissions.setProgress(missionId, mission.threshold)
			end
		end
	end
	return true
end

presencePoll:type("think")
presencePoll:interval(WORLDMISSIONS_PRESENCE_POLL_MS)
presencePoll:register()
