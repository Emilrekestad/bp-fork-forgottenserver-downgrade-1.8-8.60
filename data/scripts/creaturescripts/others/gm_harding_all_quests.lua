-- Keeps "GM Harding" holding every quest in the log, so the full quest content
-- can be inspected in-game at any time.
--
-- Deliberately has NO one-time storage flag (unlike the other one-off Harding
-- test-setup scripts): it re-runs on every login and is idempotent, writing
-- only the storage keys whose value actually differs. That way quests added to
-- data/XML/quests.xml later are picked up automatically on the next login
-- instead of needing this script touched again.

local GM_CHARACTER = "GM Harding"

local gmHardingAllQuests = CreatureEvent("GMHardingAllQuests")

function gmHardingAllQuests.onLogin(player)
	if player:getName() ~= GM_CHARACTER then
		return true
	end

	local changed, incomplete = player:completeAllQuests()

	if changed > 0 then
		local questCount = 0
		for _ in pairs(Game.getQuests()) do questCount = questCount + 1 end

		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
			"[Quest log] Completed %d/%d quests (%d storage keys written). Open the quest log to browse them.",
			questCount - #incomplete, questCount, changed))

		if #incomplete > 0 then
			player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE,
				"[Quest log] Still incomplete: " .. table.concat(incomplete, ", "))
		end
	end

	return true
end

gmHardingAllQuests:register()
