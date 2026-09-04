-- Item Rarity system — Rebirth's modal window response ("Accept Death" /
-- "Discard"). Companion to the window sent from
-- data/scripts/creaturescripts/rarity/rarity_rebirth.lua's onPrepareDeath.
-- Discard needs no handling of its own -- clicking any button already
-- closes the window client-side, so it's a pure no-op here; only Accept
-- Death actually does something.

local modalWindow = CreatureEvent("RarityRebirthModal")
function modalWindow.onModalWindow(player, modalWindowId, buttonId, choiceId)
	if modalWindowId ~= RarityRebirth.MODAL_WINDOW_ID or buttonId ~= RarityRebirth.MODAL_BUTTON_ACCEPT then
		return true
	end

	if not RarityRebirth.downed[player:getId()] then
		return true
	end

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You accept your fate.")
	RarityRebirth.finalizeRealDeath(player:getId())
	return true
end
modalWindow:register()
