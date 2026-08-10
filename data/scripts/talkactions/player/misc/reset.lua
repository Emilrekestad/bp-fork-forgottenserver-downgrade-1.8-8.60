local talk = TalkAction("!reset")

function talk.onSay(player, words, param)
	if not configManager.getBoolean(RESET_SYSTEM_ENABLED) then
		player:sendCancelMessage("The reset system is currently disabled.")
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		return false
	end

	local minLevel = configManager.getNumber(RESET_LEVEL)
	if player:getLevel() < minLevel then
		player:sendCancelMessage("You need level " .. minLevel .. " to reset.")
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		return false
	end

	player:doReset()

	local town = player:getTown()
	if town then
		player:teleportTo(town:getTemplePosition())
	end

	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)

	local reduction = player:getResetExpReduction()
	player:setExperienceRate(ExperienceRateType.STAMINA, reduction * 100)

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have performed a reset! Total resets: " .. player:getResetCount() .. ".")
	return false
end

talk:register()
