-- World Missions — Liberty Bay's 4 levers. Registered by exact map
-- position (Action():position(...)), the same pattern this codebase's own
-- BossLever:register() already uses (data/lib/functions/boss_lever.lua)
-- -- no unique/action ID needed on the placed items at all. The physical
-- lever item itself is created/repainted at boot by
-- WorldMissions.reapplyActivationVisuals() (worldmissions_startup.lua),
-- not placed by hand in RME.
local MISSION_ID = "liberty_bay"

local function registerLever(objectIndex, object)
	local lever = Action()

	function lever.onUse(player, item, fromPosition, target, toPosition, isHotkey)
		if WorldMissions.isObjectActivated(MISSION_ID, objectIndex) then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The lever won't budge any further.")
			return true
		end

		if WorldMissions.activateObject(player, MISSION_ID, objectIndex) then
			item:transform(object.itemOn)
			Game.broadcastMessage("Something shifted..", MESSAGE_EVENT_ORANGE)
		end
		return true
	end

	lever:position(object.pos)
	lever:register()
end

for index, object in ipairs(WorldMissions.Missions[MISSION_ID].objects) do
	registerLever(index, object)
end
