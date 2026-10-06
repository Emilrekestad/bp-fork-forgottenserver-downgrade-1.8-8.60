-- "The Third Place at the Table" -- the archive shelf and the three door
-- crossings (12-djinn-build-plan.md, D3 and D8).
--
-- Archive (33100,32524,3). The deployed map has bookcase 2436 there; the live
-- runtime stack showed 2437 with two books on top. Either variant is tagged
-- with an action id at boot, so the books on the same tile keep their normal
-- reading and the shelf does nothing special for anyone without quest business.
--
-- Doors. All three boundaries have action id 0 on the map, so the generic
-- quest-door and key-door handlers keep them shut for everybody. Since 2026-10-06 they behave
-- like normal quest doors for the people who may pass: use the door and it opens, walk through,
-- it closes behind you. Registered on the exact position, which the engine consults before the
-- door item's own action; details in the Door crossings block below.

local has = DjinnNeutral.has

local function samePosition(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z
end

local ARCHIVE_TEXT = "The entry is short. What it certifies is shorter still."

local archive = Action()

function archive.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if not samePosition(item:getPosition(), DjinnNeutral.Position.archive) then
		return false
	end

	if has(player, "archiveFound") then
		if DjinnNeutral.token(player, "dispatch_copy") then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You already have the C17 entry and the old undertaking.")
			return true
		end
		if has(player, "evidenceSettled") then
			return false -- the account is settled; the copy is no longer proof of anything
		end
		-- Lost after discovery: one fresh, generation-stamped copy.
		if not DjinnNeutral.give(player, { "dispatch_copy" }) then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You find the C17 entry again, but you have no room to take a copy.")
			return true
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, ARCHIVE_TEXT)
		return true
	end

	if has(player, "archiveAuthorised") then
		if not DjinnNeutral.give(player, { "dispatch_copy" }) then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You find the C17 entry, but you have no room to take a copy.")
			return true
		end
		DjinnNeutral.set(player, "archiveFound")
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, ARCHIVE_TEXT)
		return true
	end

	if has(player, "introduced") then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "These accounts belong to Nah'Bob. Ask which record you may copy.")
		return true
	end
	return false
end

archive:aid(DjinnNeutral.ACTION_ARCHIVE)
archive:register()

local tagArchive = GlobalEvent("DjinnNeutralArchive")

function tagArchive.onStartup()
	local pos = DjinnNeutral.Position.archive
	local tile = Tile(pos)
	if tile then
		for _, tileItem in ipairs(tile:getItems() or {}) do
			if DjinnNeutral.ArchiveBookcases[tileItem:getId()] then
				tileItem:setActionId(DjinnNeutral.ACTION_ARCHIVE)
				print(string.format("[DjinnNeutral] Archive bookcase %d tagged (action id %d).", tileItem:getId(), DjinnNeutral.ACTION_ARCHIVE))
				return true
			end
		end
		local ground = tile:getGround()
		if ground and DjinnNeutral.ArchiveBookcases[ground:getId()] then
			ground:setActionId(DjinnNeutral.ACTION_ARCHIVE)
			print(string.format("[DjinnNeutral] Archive bookcase %d tagged (action id %d).", ground:getId(), DjinnNeutral.ACTION_ARCHIVE))
			return true
		end
	end
	logError(string.format("[DjinnNeutral] No archive bookcase (2436/2437) at %d, %d, %d -- the C17 dispatch record cannot be copied.",
		pos.x, pos.y, pos.z))
	return true
end

tagArchive:register()

-- Door crossings -------------------------------------------------------------

-- Normal quest doors (owner, 2026-10-06). Using the door opens it for a player who may pass and
-- moves them into the doorway, exactly like the generic quest door; it closes the moment they step
-- off, and it never stays open while nobody stands in it. From the private side a player is
-- always let out. The generic closing_door handler also fires on the
-- open quest doors and bounces anyone whose storage[door action id] is -1, so every door carries
-- its pass key as action id and the player who may pass gets that storage set first. A
-- position event decides the same thing for anyone who steps into an open doorway, which is
-- what stops a tailgater on the locked-door pair (1671/1673) that the generic handler ignores.

local function closeDoor(door)
	local tile = Tile(door.pos)
	local open = tile and tile:getItemById(door.openId)
	if open and tile:getCreatureCount() == 0 then
		open:transform(door.closedId)
	end
end

local function tagDoor(door)
	local tile = Tile(door.pos)
	-- a map door that says "It is locked." becomes the ordinary closed door of the same sprite set
	local old = door.replaces and tile and tile:getItemById(door.replaces)
	if old then
		old:transform(door.closedId)
	end
	for _, id in ipairs({ door.closedId, door.openId }) do
		local item = tile and tile:getItemById(id)
		if item and item:getActionId() ~= door.key then
			item:setActionId(door.key)
		end
	end
	closeDoor(door)
end

-- true when `from` is on the public side of the door
local function fromPublicSide(door, from)
	local axis = door.axis
	local side = from[axis] - door.pos[axis]
	local publicSide = door.public[axis] - door.pos[axis]
	return side ~= 0 and (side > 0) == (publicSide > 0)
end

local function registerDoor(door)
	tagDoor(door)

	local action = Action()

	function action.onUse(player, item, fromPosition, target, toPosition, isHotkey)
		local here = player:getPosition()
		if here.z ~= door.pos.z then
			return false
		end
		if item.itemid == door.openId then
			return true -- someone is standing in the doorway; it closes when they step off
		end
		local axis = door.axis
		local side = here[axis] - door.pos[axis]
		if side == 0 then
			-- Beside the wall, not in front of the door.
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, door.deny)
			return true
		end
		if fromPublicSide(door, here) and not door.access(player) then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, door.deny)
			return true
		end
		-- Authorised, or leaving: leaving is always allowed, whatever the player's state.
		player:setStorageValue(door.key, 1)
		item:transform(door.openId)
		-- into the doorway, no teleport effect: the door closes behind them when they step off
		player:teleportTo(door.pos, true, CONST_ME_NONE)
		-- safety net (logout, death, teleport while standing in it): it only closes if nobody is in it
		addEvent(closeDoor, 10000, door)
		return true
	end

	action:position(door.pos)
	action:register()

	-- stepping into the doorway: only the authorised, or someone leaving, may
	local stepIn = MoveEvent()

	function stepIn.onStepIn(creature, item, position, fromPosition)
		local player = creature:getPlayer()
		if not player then
			return true
		end
		if not fromPublicSide(door, fromPosition) or door.access(player) then
			player:setStorageValue(door.key, 1)
			return true
		end
		player:teleportTo(fromPosition, true, CONST_ME_NONE)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, door.deny)
		return false
	end

	stepIn:type("stepin")
	stepIn:position(door.pos)
	stepIn:register()

	local stepOut = MoveEvent()

	function stepOut.onStepOut(creature, item, position, fromPosition)
		addEvent(closeDoor, 100, door)
		return true
	end

	stepOut:type("stepout")
	stepOut:position(door.pos)
	stepOut:register()
end

for _, door in ipairs(DjinnNeutral.Doors) do
	registerDoor(door)
end

local doorsStartup = GlobalEvent("DjinnNeutralDoors")

function doorsStartup.onStartup()
	for _, door in ipairs(DjinnNeutral.Doors) do
		tagDoor(door)
	end
	return true
end

doorsStartup:register()
