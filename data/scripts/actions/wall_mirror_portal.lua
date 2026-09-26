-- The mirror portal (wall mirror 28906, action id 64019).
--
-- Bound by ACTION ID, not by position: the mirror hangs on a wall, so its tile
-- is unwalkable and it can only be clicked, and binding to the aid means the
-- owner can move the mirror in RME without touching this script.
--
-- Level 250 or higher is taken through; anyone else is told they are not
-- worthy yet. Same gate as data/scripts/movements/lost_souls_entrance.lua.

local MIRROR_AID = 64019
local REQUIRED_LEVEL = 250
local DESTINATION = Position(32814, 32754, 9)

local mirror = Action()

function mirror.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if player:getLevel() < REQUIRED_LEVEL then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
			"You see yourself in the reflection and understand.. you are not worthy yet.")
		return true
	end

	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(DESTINATION)
	DESTINATION:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

mirror:aid(MIRROR_AID)
mirror:register()
