-- !boosts — what is running server-wide right now, in text.
--
-- The HUD (client module game_boosts) is the primary surface, but it only
-- exists on OTClient. This is the fallback for every other client, and the
-- place people will look when they want the exact remaining time rather than
-- a glance at a countdown pill.

local talkaction = TalkAction("!boosts", "!boost")

function talkaction.onSay(player, words, param)
	local active = GlobalBoosts.active()

	if #active == 0 then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE,
			"No server boosts are active. Any player can start one from the Store.")
		return false
	end

	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Active server boosts:")

	for _, entry in ipairs(active) do
		local line = string.format("  %s (%s) -- %s remaining",
			entry.boost.name, entry.boost.effect, GlobalBoosts.formatDuration(entry.remaining))
		if entry.contributor ~= "" then
			line = line .. ", last extended by " .. entry.contributor
		end
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, line)
	end

	-- Returning false suppresses the default "say" broadcast, so the command
	-- word itself is not spoken out loud to everyone nearby.
	return false
end

talkaction:separator(" ")
talkaction:register()
