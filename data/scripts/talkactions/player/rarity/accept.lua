-- Item Rarity system — Rebirth's opt-out. A downed player can skip waiting
-- out the window (or hoping a Druid reaches them) and just let the deferred
-- death resolve immediately. See
-- data/scripts/creaturescripts/rarity/rarity_rebirth.lua for the full
-- mechanic.

local accept = TalkAction("!accept")

function accept.onSay(player, words, param)
	if not RarityRebirth.downed[player:getId()] then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You are not currently downed.")
		return false
	end

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You accept your fate.")
	RarityRebirth.finalizeRealDeath(player:getId())
	return false
end

accept:register()
