-- Companion to actions/items/music_box.lua's selection window: finalizes the
-- player's chosen mount on "Play", consuming one Music Box. Cancel/closing
-- the window needs no handling -- the client already closes it either way.
local modalWindow = CreatureEvent("MusicBoxModal")

function modalWindow.onModalWindow(player, modalWindowId, buttonId, choiceId)
	if modalWindowId ~= MusicBox.MODAL_WINDOW_ID then
		return true
	end

	local playerId = player:getId()
	if not MusicBox.pending[playerId] then
		return true
	end
	MusicBox.pending[playerId] = nil

	if buttonId ~= MusicBox.BUTTON_PLAY then
		return true
	end

	local chosen
	for _, mount in ipairs(MusicBox.MOUNTS) do
		if mount.id == choiceId then
			chosen = mount
			break
		end
	end

	if not chosen or player:ownsMount(chosen.id) then
		return true
	end

	if not player:removeItem(MusicBox.ITEM_ID, 1) then
		return true
	end

	player:addMount(chosen.id)
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have earned the right to ride the " .. chosen.name .. ".")
	return true
end

modalWindow:register()
