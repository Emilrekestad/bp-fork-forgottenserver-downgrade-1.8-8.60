-- One-time correction for "Harding Knight": the Oracle's town-ID table was
-- wrong at the time they ran the vocation flow (thais mapped to town id 2,
-- "Dawnport", instead of the real id 8), so they ended up parked in Dawnport
-- instead of Thais. Fixes town + position to the real Thais temple on next
-- login, then never fires again.

local SETUP_FLAG = 990003
local THAIS_TOWN_ID = 8

local hardingKnightTownFix = CreatureEvent("HardingKnightTownFix")

function hardingKnightTownFix.onLogin(player)
	if player:getName() ~= "Harding Knight" then
		return true
	end

	if player:getStorageValue(SETUP_FLAG) == 1 then
		return true
	end

	local town = Town(THAIS_TOWN_ID)
	if town then
		player:setTown(town)
		player:teleportTo(town:getTemplePosition())
		player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Test fix: corrected your town to Thais (the Oracle sent you to Dawnport by mistake earlier).")
	end

	player:setStorageValue(SETUP_FLAG, 1)

	return true
end

hardingKnightTownFix:register()
