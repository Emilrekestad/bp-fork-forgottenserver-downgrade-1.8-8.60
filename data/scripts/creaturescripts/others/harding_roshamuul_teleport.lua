-- One-time follow-up: move "Harding" to Roshamuul. Separate from the main
-- Knight test setup (which already ran and consumed its own flag) so it
-- doesn't redo gear/level/vocation.

local TELEPORT_FLAG = 990002

local roshamuulTeleport = CreatureEvent("HardingRoshamuulTeleport")

function roshamuulTeleport.onLogin(player)
	if player:getName() ~= "Harding" then
		return true
	end

	if player:getStorageValue(TELEPORT_FLAG) == 1 then
		return true
	end

	player:teleportTo(Position(33513, 32363, 6))
	player:setStorageValue(TELEPORT_FLAG, 1)
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Moved to Roshamuul.")

	return true
end

roshamuulTeleport:register()
