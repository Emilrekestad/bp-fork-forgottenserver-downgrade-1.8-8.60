-- GM diagnostic for the quest log system. Reports how many quests/missions the
-- XML loader actually registered at startup, and how many of them the calling
-- player currently has started/completed -- the quest log is entirely
-- Lua-driven (no C++ quest registry), so this is the only way to see whether
-- data/XML/quests.xml really made it into memory.

local talkaction = TalkAction("/questdebug")

function talkaction.onSay(player, words, param)
	local quests = Game.getQuests()
	local missions = Game.getMissions()

	local questCount, missionCount = 0, 0
	for _ in pairs(quests) do questCount = questCount + 1 end
	for _ in pairs(missions) do missionCount = missionCount + 1 end

	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE,
		string.format("[questdebug] registered: %d quests, %d missions.", questCount, missionCount))

	local started, completed = 0, 0
	for _, quest in pairs(quests) do
		if quest:isStarted(player) then
			started = started + 1
			if quest:isCompleted(player) then completed = completed + 1 end
		end
	end

	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE,
		string.format("[questdebug] %s: %d started, %d completed (quest log shows the %d started).",
			player:getName(), started, completed, started))

	if param and param ~= "" then
		local needle = param:lower()
		for _, quest in pairs(quests) do
			if quest.name and quest.name:lower():find(needle, 1, true) then
				player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
					"[questdebug] '%s' id=%s storage=%s value=%s started=%s completed=%s missions=%d",
					tostring(quest.name), tostring(quest.id), tostring(quest.storageId),
					tostring(quest.storageValue), tostring(quest:isStarted(player)),
					tostring(quest:isCompleted(player)), #quest.missions))
			end
		end
	end

	return false
end

talkaction:separator(" ")
talkaction:accountType(6)
talkaction:access(true)
talkaction:register()
