-- GM tool: mark every registered quest + mission complete for a player, so the
-- whole quest log can be inspected at once. Data-driven off the live quest
-- registry, so quests added to data/XML/quests.xml later are covered with no
-- change here.
--
--   /completequests            -> applies to yourself
--   /completequests <name>     -> applies to that online player

local talkaction = TalkAction("/completequests")

function talkaction.onSay(player, words, param)
	local target = player
	if param and param ~= "" then
		target = Player(param)
		if not target then
			player:sendCancelMessage("A player with that name is not online.")
			return false
		end
	end

	local changed, incomplete = target:completeAllQuests()

	local questCount = 0
	for _ in pairs(Game.getQuests()) do questCount = questCount + 1 end

	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
		"[completequests] %s: %d storage keys written, %d/%d quests now complete.",
		target:getName(), changed, questCount - #incomplete, questCount))

	if #incomplete > 0 then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE,
			"[completequests] still incomplete: " .. table.concat(incomplete, ", "))
	end

	if target ~= player then
		target:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Your quest log has been completed by a gamemaster.")
	end

	return false
end

talkaction:separator(" ")
talkaction:accountType(6)
talkaction:access(true)
talkaction:register()
