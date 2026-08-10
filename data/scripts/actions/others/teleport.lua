local action = Action()

local upFloorIds = {1948, 1968, 5542, 20474, 20475, 31262, 34243, 48493, 48494, 50122, 50123}
-- Corrupted map data can send moveUpstairs()'s search (or the plain z+1 fallback)
-- much further away than a normal climb/descend ever should be. teleportTo() always
-- looks like a hard snap on the client no matter the distance, so past this threshold
-- it's better to fail the action than to visibly yank the player across the map.
local MAX_TELEPORT_DISTANCE = 5

function action.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local startPosition = player:getPosition()

	if table.contains(upFloorIds, item.itemid) then
		fromPosition:moveUpstairs()
	else
		fromPosition.z = fromPosition.z + 1
	end

	local destinationTile = Tile(fromPosition)
	if not destinationTile then
		player:sendCancelMessage(RETURNVALUE_NOTPOSSIBLE)
		return true
	end

	if player:isPzLocked() and destinationTile:hasFlag(TILESTATE_PROTECTIONZONE) then
		player:sendCancelMessage(RETURNVALUE_PLAYERISPZLOCKED)
		return true
	end

	if destinationTile:queryAdd(player) ~= RETURNVALUE_NOERROR then
		player:sendCancelMessage(RETURNVALUE_NOTPOSSIBLE)
		return true
	end

	local dx = math.abs(startPosition.x - fromPosition.x)
	local dy = math.abs(startPosition.y - fromPosition.y)
	if math.max(dx, dy) > MAX_TELEPORT_DISTANCE then
		return true
	end

	player:teleportTo(fromPosition, false, CONST_ME_NONE)
	return true
end

action:id(435, 1931, 1948, 1968, 5542, 20474, 20475, 31262, 34243, 48493, 48494, 50122, 50123)
action:register()
