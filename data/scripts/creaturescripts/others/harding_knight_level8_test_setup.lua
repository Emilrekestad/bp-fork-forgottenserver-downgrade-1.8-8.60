-- One-time GM test setup for "Harding Knight": levels the character to 8 on
-- next login via the live addExperience() path (same one the engine already
-- uses for real XP gains), so health/mana/cap scaling and the level-up
-- full-heal are all correct automatically. Fires once, then never again.

local SETUP_FLAG = 990002

local hardingKnightLevel8 = CreatureEvent("HardingKnightLevel8TestSetup")

function hardingKnightLevel8.onLogin(player)
	if player:getName() ~= "Harding Knight" then
		return true
	end

	if player:getStorageValue(SETUP_FLAG) == 1 then
		return true
	end

	local targetExp = Game.getExperienceForLevel(8)
	local delta = targetExp - player:getExperience()
	if delta > 0 then
		player:addExperience(delta, false)
	end

	player:setStorageValue(SETUP_FLAG, 1)
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Test setup complete: leveled to 8.")

	return true
end

hardingKnightLevel8:register()
