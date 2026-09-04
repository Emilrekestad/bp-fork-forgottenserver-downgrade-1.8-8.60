-- /globalboost <key> <minutes> — GM control over the server-wide boosts.
--
-- SETS the remaining time outright rather than extending it, and writes no
-- purchase record: this is for testing and for goodwill grants (an apology
-- after downtime, a launch-weekend freebie), not for simulating a sale. Use 0
-- to cut a boost off immediately.
--
-- Deliberately silent server-wide. Announce a goodwill boost yourself, in
-- your own words -- the automatic "<player> has activated" line is written
-- for a purchase and would name the GM as the buyer.

local VALID = {}
for key in pairs(GlobalBoosts.ByKey) do
	VALID[#VALID + 1] = key
end
table.sort(VALID)

local talkaction = TalkAction("/globalboost")

function talkaction.onSay(player, words, param)
	local key, minutes = param:match("^%s*(%S+)%s+(%S+)%s*$")

	if not key then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE,
			"Usage: /globalboost <" .. table.concat(VALID, "|") .. "> <minutes>  (0 to stop)")

		local active = GlobalBoosts.active()
		if #active == 0 then
			player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Nothing is running right now.")
		else
			for _, entry in ipairs(active) do
				player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format("  %s: %s remaining",
					entry.boost.key, GlobalBoosts.formatDuration(entry.remaining)))
			end
		end
		return false
	end

	local boost = GlobalBoosts.ByKey[key:lower()]
	if not boost then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE,
			"Unknown boost. Valid keys: " .. table.concat(VALID, ", "))
		return false
	end

	minutes = tonumber(minutes)
	if not minutes or minutes < 0 then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Minutes must be a number, 0 or greater.")
		return false
	end

	local seconds = math.min(math.floor(minutes * 60), GlobalBoosts.MAX_STACK_SECONDS)
	GlobalBoosts.set(boost.id, seconds, player:getName())

	if seconds == 0 then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, boost.name .. " stopped.")
	else
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE,
			string.format("%s set to %s.", boost.name, GlobalBoosts.formatDuration(seconds)))
	end

	return false
end

talkaction:separator(" ")
talkaction:accountType(6)
talkaction:access(true)
talkaction:register()
