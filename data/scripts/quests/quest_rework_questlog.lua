-- Quest-log entries for the three 2026-09-11 reworks. Registered from Lua rather
-- than data/XML/quests.xml because each entry's text is computed from the same
-- state the NPCs read (Mission:getDescription accepts a function), so the log
-- always names the next NPC, town and objective and can never drift from it.
-- The old "The Postman Missions", "The Travelling Trader Quest", both "Djinn
-- War" factions and "Factions" were removed from quests.xml; their storage
-- values stay on the characters for audit but no longer drive anything.

local function stripBraces(text)
	return (text:gsub("[{}]", ""))
end

Game.createQuest("Return to Sender", {
	storageId = PostmanRework.Storage.stage,
	storageValue = PostmanRework.Stage.ACCEPTED,
	missions = {
		{
			name = "Kevin's Postal Licence",
			storageId = PostmanRework.Storage.stage,
			startValue = PostmanRework.Stage.ACCEPTED,
			endValue = PostmanRework.Stage.LICENSED,
			description = function(player)
				return PostmanRework.logText(player)
			end,
		},
	},
}):register()

Game.createQuest("The Price of a Good Name", {
	storageId = RashidRework.Storage.enrolled,
	storageValue = 1,
	missions = {
		{
			name = "Rashid's Collections",
			-- Keyed on the recognition flag, starting at 0 so it shows from
			-- enrolment and reads "Completed" exactly when Rashid trusts you.
			storageId = RashidRework.Storage.trusted,
			startValue = 0,
			endValue = 1,
			description = function(player)
				if RashidRework.isTrusted(player) then
					return "Rashid has written your name in his ledger. He now buys from you.\n" .. RashidRework.whereaboutsLine()
				end
				local lines = {
					"Rashid lives in his cabin and only buys from people who prove their worth. Ask him for a task each weekday and bring him the goods. When all six tasks are done, come on a Sunday and say trade. Finished work keeps; there is no weekly reset.",
				}
				for _, line in ipairs(RashidRework.journalLines(player)) do
					lines[#lines + 1] = stripBraces(line)
				end
				lines[#lines + 1] = RashidRework.whereaboutsLine()
				return table.concat(lines, "\n")
			end,
		},
	},
}):register()

Game.createQuest("The Third Place at the Table", {
	storageId = DjinnNeutral.Storage.introduced,
	storageValue = 1,
	missions = {
		{
			name = "An Independent Trader",
			storageId = DjinnNeutral.Storage.complete,
			startValue = 0,
			endValue = 1,
			description = function(player)
				return DjinnNeutral.logText(player)
			end,
		},
	},
}):register()
