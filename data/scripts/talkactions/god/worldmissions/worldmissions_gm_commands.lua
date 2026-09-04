-- World Missions — GM-only debug/admin command. Mirrors
-- data/scripts/talkactions/god/bao/bao_gm_commands.lua's own dispatch
-- shape exactly (comma-split subcommands, accountType(6):access(true)).
--
-- Usage:
--   /worldmission status, missionId
--   /worldmission setprogress, missionId, amount
--   /worldmission forcesave, missionId
--   /worldmission reset, missionId
--
-- Completion is instant now (setprogress alone already triggers it if it
-- reaches threshold) -- forcesave is a harmless leftover safety net for
-- re-checking every mission's state by hand rather than the one true way
-- to apply something, kept mainly for the case where a mission's
-- appliedStorage/progressStorage got poked directly (e.g. bad data,
-- manual DB edit) and needs re-syncing without waiting on a real trigger.

local WORLDMISSION_USAGE = "Usage: /worldmission status, missionId | /worldmission setprogress, missionId, amount | /worldmission forcesave, missionId | /worldmission reset, missionId"

local function normalizeSub(sub)
	return (sub or ""):lower():gsub("[%s_%-]+", "")
end

local function handleStatus(admin, missionId)
	local mission = missionId and WorldMissions.Missions[missionId]
	if not mission then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "No such mission: " .. tostring(missionId))
		return false
	end

	local progressLine
	if mission.type == "composite" then
		progressLine = "requires: " .. table.concat(mission.requiredMissions or {}, ", ")
	else
		progressLine = WorldMissions.getProgress(missionId) .. " / " .. tostring(mission.threshold)
	end

	admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
		"[%s] %s (%s) -- %s -- thresholdMet=%s appliedNow=%s",
		missionId, mission.name or missionId, mission.type, progressLine,
		tostring(WorldMissions.isThresholdMet(missionId)), tostring(WorldMissions.isApplied(missionId))
	))
	return false
end

local function handleSetProgress(admin, missionId, amountStr)
	local mission = missionId and WorldMissions.Missions[missionId]
	if not mission then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "No such mission: " .. tostring(missionId))
		return false
	end
	if mission.type == "composite" then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Composite missions have no progress of their own -- setprogress the missions it requires instead.")
		return false
	end

	local amount = tonumber(amountStr)
	if not amount then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, WORLDMISSION_USAGE)
		return false
	end

	WorldMissions.setProgress(missionId, amount)
	admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, missionId .. " progress set to " .. amount .. ".")
	return false
end

local function handleForceSave(admin, missionId)
	local mission = missionId and WorldMissions.Missions[missionId]
	if not mission then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "No such mission: " .. tostring(missionId))
		return false
	end
	if WorldMissions.isApplied(missionId) then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, missionId .. " is already applied.")
		return false
	end
	if not WorldMissions.isThresholdMet(missionId) then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, missionId .. " hasn't met its threshold yet -- nothing to apply.")
		return false
	end

	WorldMissions.applyPendingCompletions()
	admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Applied pending completions (including " .. missionId .. ").")
	return false
end

local function handleReset(admin, missionId)
	local mission = missionId and WorldMissions.Missions[missionId]
	if not mission then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "No such mission: " .. tostring(missionId))
		return false
	end

	if mission.progressStorage then
		Game.setStorageValue(mission.progressStorage, 0)
	end
	if mission.appliedStorage then
		Game.setStorageValue(mission.appliedStorage, 0)
		if mission.type == "activation" then
			for i = 1, #(mission.objects or {}) do
				Game.setStorageValue(mission.appliedStorage + i, 0)
			end
		end
	end
	Game.saveStorageValues()
	admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, missionId .. " reset (progress and applied state cleared).")
	return false
end

local worldMission = TalkAction("/worldmission")
function worldMission.onSay(player, words, param)
	local split = param:splitTrimmed(",")
	local sub = normalizeSub(split[1])

	if sub == "status" then
		return handleStatus(player, split[2])
	elseif sub == "setprogress" then
		return handleSetProgress(player, split[2], split[3])
	elseif sub == "forcesave" then
		return handleForceSave(player, split[2])
	elseif sub == "reset" then
		return handleReset(player, split[2])
	end

	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, WORLDMISSION_USAGE)
	return false
end
worldMission:separator(" ")
worldMission:accountType(6)
worldMission:access(true)
worldMission:register()
