local talkaction = TalkAction("/boosted")

function talkaction.onSay(player, words, param)
	local boosted = Game.getBoostedCreature()
	if boosted == "" then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "No boosted creature today.")
		return false
	end
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE,
		string.format("Today's Boosted Creature: %s (2x XP, 2x Loot, 2x Spawn rate)", boosted))
	return false
end

talkaction:register()
