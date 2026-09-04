-- Music Box: real Tibia's universal taming item. Using it opens a selection
-- window of every mount it can charm (data/lib/mounts/music_box.lua) that the
-- player doesn't already own; the pick is finalized by
-- creaturescripts/mounts/music_box_modal.lua.
local musicBoxAction = Action()

function musicBoxAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local available = {}
	for _, mount in ipairs(MusicBox.MOUNTS) do
		if not player:ownsMount(mount.id) then
			available[#available + 1] = mount
		end
	end

	if #available == 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have already earned the right to ride every mount this music box could charm.")
		return true
	end

	local window = ModalWindow(MusicBox.MODAL_WINDOW_ID, "Music Box", "The music box may have some charming effects on certain creatures. Which mount do you wish to charm?")
	for _, mount in ipairs(available) do
		window:addChoice(mount.id, mount.name)
	end
	window:addButton(MusicBox.BUTTON_PLAY, "Play")
	window:addButton(MusicBox.BUTTON_CANCEL, "Cancel")
	window:setDefaultEnterButton(MusicBox.BUTTON_PLAY)
	window:setDefaultEscapeButton(MusicBox.BUTTON_CANCEL)
	window:sendToPlayer(player)

	MusicBox.pending[player:getId()] = item:getId()
	return true
end

musicBoxAction:id(MusicBox.ITEM_ID)
musicBoxAction:register()
