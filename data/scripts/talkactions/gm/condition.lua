local talk = TalkAction("/condition")

function talk.onSay(player, words, param)
	if param == "" then
		player:sendTextMessage(MESSAGE_ADMIN, "Usage: /condition root|fear|agony|bleed,seconds,[name]")
		return false
	end

	-- Manual split by comma
	local condName = nil
	local seconds = nil
	local targetName = nil

	if param:find(",") then
		local comma1 = param:find(",")
		condName = param:sub(1, comma1 - 1):match("^%s*(.-)%s*$")
		local rest = param:sub(comma1 + 1)
		if rest:find(",") then
			local comma2 = rest:find(",")
			seconds = tonumber(rest:sub(1, comma2 - 1):match("^%s*(.-)%s*$"))
			targetName = rest:sub(comma2 + 1):match("^%s*(.-)%s*$")
		else
			seconds = tonumber(rest:match("^%s*(.-)%s*$"))
		end
	else
		condName = param:match("^%s*(.-)%s*$")
		seconds = 10
	end

	if not condName then
		player:sendTextMessage(MESSAGE_ADMIN, "Usage: /condition root|fear|agony|bleed,seconds,[name]")
		return false
	end

	condName = condName:lower()
	seconds = seconds or 10
	local target = targetName and Player(targetName) or player

	if not target then
		player:sendTextMessage(MESSAGE_ADMIN, "Player not found.")
		return false
	end

	local conditionType
	if condName == "root" or condName == "rooted" then
		conditionType = CONDITION_ROOTED
	elseif condName == "fear" or condName == "feared" then
		conditionType = CONDITION_FEARED
	elseif condName == "agony" then
		conditionType = CONDITION_AGONY
	elseif condName == "bleed" or condName == "bleeding" then
		conditionType = CONDITION_BLEEDING
	else
		player:sendTextMessage(MESSAGE_ADMIN, "Unknown condition: " .. condName)
		return false
	end

	-- Security audit 2026-10-05: bound the duration. An unbounded value would
	-- overflow the tick counter or root a player for hours.
	seconds = math.max(1, math.min(math.floor(seconds), 3600))
	local ticks = seconds * 1000
	local condition = Condition(conditionType, CONDITIONID_DEFAULT)
	if not condition then
		player:sendTextMessage(MESSAGE_ADMIN, "Failed to create condition!")
		return false
	end

	condition:setParameter(CONDITION_PARAM_TICKS, ticks)
	local ok = target:addCondition(condition)
	player:sendTextMessage(MESSAGE_ADMIN, string.format("Applied %s to %s for %ds", condName, target:getName(), seconds))
	return false
end

talk:separator(" ")
-- Security audit 2026-10-05: this command had no access gate at all, so any
-- player could root, fear or bleed any online player by name. Gamemaster
-- account type AND a staff group are now required; the C++ dispatcher logs
-- every use as a gm.command event because of these two lines.
talk:accountType(ACCOUNT_TYPE_GAMEMASTER)
talk:access(true)
talk:register()
