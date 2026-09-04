-- Loads data/XML/quests.xml into the Lua quest registry (data/lib/core/quests.lua).
-- This is the ONLY thing that populates the quest log -- this fork has no C++
-- quest registry at all, the 0xF0/0xF1 quest-log packets are served entirely
-- from Lua. If this does not run, every player's quest log is silently empty.
local xmlQuest = GlobalEvent("Load XML Quests")

function xmlQuest.onStartup()
	local questDoc = XMLDocument("data/XML/quests.xml")
	if not questDoc then
		logError("[Quests] Could not load data/XML/quests.xml - quest log will be EMPTY.")
		return true
	end

	local quests = questDoc:child("quests")
	if not quests then
		logError("[Quests] data/XML/quests.xml has no <quests> root - quest log will be EMPTY.")
		return true
	end

	local questCount, missionCount, skipped = 0, 0, 0

	for questNode in quests:children() do
		local questName = questNode:attribute("name")
		local questStorageId = tonumber(questNode:attribute("startstorageid"))
		local questStorageValue = tonumber(questNode:attribute("startstoragevalue"))

		-- A quest with no usable start storage can never report isStarted()
		-- correctly, so it would sit invisible in the log forever. Skip it
		-- loudly instead of registering something silently broken.
		if not questName or not questStorageId or not questStorageValue then
			skipped = skipped + 1
			logWarning(string.format(
				"[Quests] Skipping quest '%s': missing/invalid name, startstorageid or startstoragevalue.",
				tostring(questName)))
		else
			local missions = {}
			for missionNode in questNode:children() do
				local storageId = tonumber(missionNode:attribute("storageid"))
				local startValue = tonumber(missionNode:attribute("startvalue"))
				local endValue = tonumber(missionNode:attribute("endvalue"))

				if not storageId or not startValue or not endValue then
					logWarning(string.format(
						"[Quests] Skipping mission '%s' in quest '%s': missing/invalid storageid, startvalue or endvalue.",
						tostring(missionNode:attribute("name")), questName))
				else
					local mission = {
						name = missionNode:attribute("name") or "",
						storageId = storageId,
						startValue = startValue,
						endValue = endValue,
						ignoreEndValue = tobool(missionNode:attribute("ignoreendvalue")),
						description = missionNode:attribute("description")
					}

					if not mission.description then
						local description = {}
						for missionState in missionNode:children() do
							local stateId = tonumber(missionState:attribute("id"))
							if stateId then
								description[stateId] = missionState:attribute("description") or ""
							end
						end

						mission.description = description
					end

					missions[#missions + 1] = mission
					missionCount = missionCount + 1
				end
			end

			local quest = Game.createQuest(questName, {
				storageId = questStorageId,
				storageValue = questStorageValue,
				missions = missions
			})

			if quest then
				quest:register()
				questCount = questCount + 1
			else
				skipped = skipped + 1
				logWarning(string.format("[Quests] Game.createQuest returned nil for '%s'.", questName))
			end
		end
	end

	-- print() rather than logInfo(): this server runs with the console log level
	-- above INFO, so logInfo lines never reach server_run.log.
	print(string.format(">> Quests loaded: %d quests, %d missions%s", questCount, missionCount,
		skipped > 0 and string.format(" (%d skipped)", skipped) or ""))
	return true
end

xmlQuest:register()
