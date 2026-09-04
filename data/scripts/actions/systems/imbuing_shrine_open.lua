local function isItem(thing)
	if not thing then
		return false
	end

	local ok, isItem = pcall(function()
		return thing:isItem()
	end)
	return ok and isItem
end

local action = Action()

function action.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if not isItem(target) or target == item then
		player:sendTextMessage(MESSAGE_STATUS_SMALL,
			"Use the Dormant Shrine with equipment you are carrying.")
		return true
	end
	if target:getTopParent() ~= player then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "You need to be carrying that equipment.")
		return true
	end

	if target:getTier() == RarityStats.DORMANT_TIER then
		RarityIdentify.reveal(player, target)
		return true
	end

	RarityIdentify.putToSleep(player, target)
	return true
end

action:id(25060, 25061)
action:register()
