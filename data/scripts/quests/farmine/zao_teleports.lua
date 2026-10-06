-- Zao entrance: the two map teleports at 33136,31248,6 and 33136,31249,6 had no destination.
-- They are free for everyone and take you to 33213,31066,9 (next to Chartan).
local DESTINATION = Position(33213, 31066, 9)

local event = MoveEvent()

function event.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(DESTINATION)
	DESTINATION:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

event:type("stepin")
event:position(Position(33136, 31248, 6))
event:position(Position(33136, 31249, 6))
event:register()

-- 33216,31067,9 -> 33078,31219,8, free for everyone
local deeper = MoveEvent()
local DEEPER_DESTINATION = Position(33078, 31219, 8)

function deeper.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(DEEPER_DESTINATION)
	DEEPER_DESTINATION:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

deeper:type("stepin")
deeper:position(Position(33216, 31067, 9))
deeper:register()

-- The way back out: 33211,31067,9 -> 33138,31249,6, free for everyone
local out = MoveEvent()
local OUT_DESTINATION = Position(33138, 31249, 6)

function out.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(OUT_DESTINATION)
	OUT_DESTINATION:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

out:type("stepin")
out:position(Position(33211, 31067, 9))
out:register()

-- Zao lever lifts: pull the lever while standing on the marked tile and you are taken to the
-- other end. Free for everyone.
--   lever 33082,31109,2 (stand 33082,31110,2)   -> 33078,31080,13
--   lever 33078,31079,13 (stand 33078,31080,13) -> 33082,31110,2
local LEVER_LEFT, LEVER_RIGHT = 2772, 2773

local function leverLift(leverPosition, standPosition, destination)
	local lever = Action()

	function lever.onUse(player, item, fromPosition, target, toPosition, isHotkey)
		local at = player:getPosition()
		if at.x ~= standPosition.x or at.y ~= standPosition.y or at.z ~= standPosition.z then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have to stand right in front of the lever.")
			return true
		end
		item:transform(item.itemid == LEVER_LEFT and LEVER_RIGHT or LEVER_LEFT)
		at:sendMagicEffect(CONST_ME_TELEPORT)
		player:teleportTo(destination)
		destination:sendMagicEffect(CONST_ME_TELEPORT)
		return true
	end

	lever:position(leverPosition)
	lever:register()
end

leverLift(Position(33082, 31109, 2), Position(33082, 31110, 2), Position(33078, 31080, 13))
leverLift(Position(33078, 31079, 13), Position(33078, 31080, 13), Position(33082, 31110, 2))

-- Zao, north-west: 33092,31122,12 -> 33083,31215,8, free for everyone.
local down = MoveEvent()
local DOWN_DESTINATION = Position(33083, 31215, 8)

function down.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(DOWN_DESTINATION)
	DOWN_DESTINATION:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

down:type("stepin")
down:position(Position(33092, 31122, 12))
down:register()

-- ... and back: 33084,31213,8 -> 33095,31122,12, but only while a scale of corruption lies on the
-- coal basin at 33086,31214,8. Stepping into the teleport burns that scale to flames, so the next
-- person has to place another. (The map used to have a scale lying on the basin for ever; it is
-- removed at load/startup.)
local BASIN = Position(33086, 31214, 8)
local SCALE_OF_CORRUPTION = 11673
local UP_DESTINATION = Position(33095, 31122, 12)

local function removeStaticScale()
	local tile = Tile(BASIN)
	local scale = tile and tile:getItemById(SCALE_OF_CORRUPTION)
	while scale do
		scale:remove()
		scale = tile:getItemById(SCALE_OF_CORRUPTION)
	end
end
removeStaticScale()

local basinStartup = GlobalEvent("ZaoBasinStartup")
function basinStartup.onStartup()
	removeStaticScale()
	return true
end
basinStartup:register()

local up = MoveEvent()

function up.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	local tile = Tile(BASIN)
	local scale = tile and tile:getItemById(SCALE_OF_CORRUPTION)
	if not scale then
		player:teleportTo(fromPosition, true)
		position:sendMagicEffect(CONST_ME_POFF)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Nothing happens. Place a scale of corruption on the coal basin first.")
		return true
	end
	scale:remove(1)
	BASIN:sendMagicEffect(CONST_ME_FIREAREA)
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(UP_DESTINATION)
	UP_DESTINATION:sendMagicEffect(CONST_ME_TELEPORT)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The scale of corruption bursts into flames on the basin.")
	return true
end

up:type("stepin")
up:position(Position(33084, 31213, 8))
up:register()

-- Zao: 33111,31123,12 -> 33028,31086,13, free for everyone
local deepZao = MoveEvent()
local DEEP_DESTINATION = Position(33028, 31086, 13)

function deepZao.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(DEEP_DESTINATION)
	DEEP_DESTINATION:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

deepZao:type("stepin")
deepZao:position(Position(33111, 31123, 12))
deepZao:register()

-- Zao: 33052,31083,14 -> 33042,31086,15, free for everyone
local lower = MoveEvent()
local LOWER_DESTINATION = Position(33042, 31086, 15)

function lower.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(LOWER_DESTINATION)
	LOWER_DESTINATION:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

lower:type("stepin")
lower:position(Position(33052, 31083, 14))
lower:register()

-- Zao: 33098,31083,14 -> 33092,31085,15, free for everyone
local lowerEast = MoveEvent()
local LOWER_EAST_DESTINATION = Position(33092, 31085, 15)

function lowerEast.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(LOWER_EAST_DESTINATION)
	LOWER_EAST_DESTINATION:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

lowerEast:type("stepin")
lowerEast:position(Position(33098, 31083, 14))
lowerEast:register()

-- Zao: 33101,31118,14 -> 33094,31122,15, free for everyone
local lowerSouth = MoveEvent()
local LOWER_SOUTH_DESTINATION = Position(33094, 31122, 15)

function lowerSouth.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(LOWER_SOUTH_DESTINATION)
	LOWER_SOUTH_DESTINATION:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

lowerSouth:type("stepin")
lowerSouth:position(Position(33101, 31118, 14))
lowerSouth:register()

-- Zao: 33059,31122,14 -> 33038,31119,15, free for everyone
local lowerWest = MoveEvent()
local LOWER_WEST_DESTINATION = Position(33038, 31119, 15)

function lowerWest.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(LOWER_WEST_DESTINATION)
	LOWER_WEST_DESTINATION:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

lowerWest:type("stepin")
lowerWest:position(Position(33059, 31122, 14))
lowerWest:register()

-- Farmine mountain lifts (free for everyone): pull the lever while standing on the marked tile
--   lever 32992,31539,1 (stand 32991,31539,1) -> 32991,31539,4
--   lever 32992,31539,4 (stand 32991,31539,4) -> 32991,31539,1
leverLift(Position(32992, 31539, 1), Position(32991, 31539, 1), Position(32991, 31539, 4))
leverLift(Position(32992, 31539, 4), Position(32991, 31539, 4), Position(32991, 31539, 1))

-- Lizard City, the way out: 33076,31218,8 and 33076,31219,8 -> 33138,31249,6, free for everyone
local cityExit = MoveEvent()
local CITY_EXIT_DESTINATION = Position(33138, 31249, 6)

function cityExit.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(CITY_EXIT_DESTINATION)
	CITY_EXIT_DESTINATION:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

cityExit:type("stepin")
cityExit:position(Position(33076, 31218, 8))
cityExit:position(Position(33076, 31219, 8))
cityExit:register()
