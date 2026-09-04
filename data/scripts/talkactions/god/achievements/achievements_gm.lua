-- Achievements GM tooling.
--
-- Everything here drives the ordinary Player.addAchievement / removeAchievement
-- path rather than writing storage or the mirror tables directly. That is the
-- point: a GM command that took a shortcut would leave storage and the mirror
-- disagreeing, which is the one failure this system is built to make
-- impossible.
--
-- Usage:
--   /achievements                    -- what this character has
--   /achievements all                -- grant every achievement (testing)
--   /achievements clear              -- remove every achievement
--   /achievements grant, <name|id>   -- one achievement
--   /achievements revoke, <name|id>  -- one achievement
--   /achievements reconcile          -- resync the database mirror from storage
--   /achievements rarity             -- recount how rare each achievement is
--
-- All subcommands act on the character running them. Achievements are
-- character-scoped, and a GM granting them to someone else is not a thing this
-- server needs.

local USAGE = "Usage: /achievements | all | clear | grant, <name|id> | revoke, <name|id> | reconcile | rarity"

local function tell(player, text)
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "[Achievements] " .. text)
end

local achievementsCommand = TalkAction("/achievements")

function achievementsCommand.onSay(player, words, param)
	if player:getAccountType() < ACCOUNT_TYPE_GOD then
		return true
	end

	local parts = {}
	for piece in string.gmatch(param or "", "([^,]+)") do
		parts[#parts + 1] = piece:match("^%s*(.-)%s*$")
	end

	local action = string.lower(parts[1] or "status")
	local totals = AchievementsDB.totals()

	if action == "status" then
		local unlocked = player:getAchievements()
		local secretsHeld = 0
		for _, id in ipairs(unlocked) do
			local entry = achievements[id]
			if entry and entry.secret then
				secretsHeld = secretsHeld + 1
			end
		end
		tell(player, string.format("%d / %d unlocked, %d / %d secrets, %d / %d points.",
			#unlocked, totals.count, secretsHeld, totals.secrets,
			player:getAchievementPoints(), totals.points))

	elseif action == "all" then
		player:addAllAchievements(true)
		tell(player, string.format("Granted every achievement: %d / %d points.",
			player:getAchievementPoints(), totals.points))

	elseif action == "clear" then
		player:removeAllAchievements()
		tell(player, "Removed every achievement from this character.")

	elseif action == "grant" or action == "revoke" then
		local target = parts[2]
		if not target or target == "" then
			tell(player, USAGE)
			return false
		end

		local key = tonumber(target) or target
		local entry = tonumber(target) and getAchievementInfoById(key) or getAchievementInfoByName(key)
		if not entry then
			tell(player, "No achievement called '" .. tostring(target) .. "'.")
			return false
		end

		if action == "grant" then
			player:addAchievement(entry.id)
			tell(player, "Granted \"" .. entry.name .. "\".")
		else
			player:removeAchievement(entry.id)
			tell(player, "Revoked \"" .. entry.name .. "\".")
		end

	elseif action == "reconcile" then
		local added, removed = AchievementsDB.reconcilePlayer(player)
		tell(player, string.format("Mirror resynced from storage: +%d / -%d.", added, removed))

	elseif action == "rarity" then
		local population = AchievementsDB.refreshRarity()
		tell(player, string.format("Rarity recounted across %d characters.", population))

	else
		tell(player, USAGE)
	end

	return false
end

achievementsCommand:separator(" ")
achievementsCommand:accountType(6)
achievementsCommand:access(true)
achievementsCommand:register()
