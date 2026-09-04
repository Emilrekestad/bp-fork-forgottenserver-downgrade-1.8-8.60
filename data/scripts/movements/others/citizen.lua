local moveevent = MoveEvent()
function moveevent.onStepIn(creature, item, position, fromPosition)
	if item.actionid >= actionIds.levelDoor and item.actionid < actionIds.citizenship then
		if creature:isPlayer() and creature:getLevel() < item.actionid - actionIds.levelDoor then
			creature:teleportTo(fromPosition, false, CONST_ME_NONE)
			position:sendMagicEffect(CONST_ME_MAGIC_BLUE)
			creature:sendTextMessage(MESSAGE_EVENT_ADVANCE,
			                         "The tile seems to be protected against unwanted intruders.")
		end
		return true
	end

	if item.actionid > actionIds.citizenship and item.actionid <
		actionIds.citizenshipLast then
		if not creature:isPlayer() then return false end
		local town = Town(item.actionid - actionIds.citizenship)
		if not town then return false end
		creature:setTown(town)
		creature:sendTextMessage(MESSAGE_EVENT_ADVANCE,
		                         "You are now a citizen of " .. town:getName() .. ".")
	end
	return true
end
moveevent:type("stepin")
moveevent:id(1949)
moveevent:register()
