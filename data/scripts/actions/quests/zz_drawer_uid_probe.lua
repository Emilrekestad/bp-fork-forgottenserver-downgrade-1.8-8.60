-- Temporary diagnostic: logs uid/position for any drawer opened, without
-- changing behavior (returns false so the normal container-open still happens).
-- Delete this file once the Thieves Guild drawer uids are known.
local probe = Action()

function probe.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local pos = item:getPosition()
	io.write(string.format("[DRAWER PROBE] itemid=%d uid=%d aid=%d pos=(%d,%d,%d)\n",
		item.itemid, item.uid, item.actionid, pos.x, pos.y, pos.z))
	return false
end

probe:id(2431, 2432, 2433, 2434)
probe:register()
