-- Grave Tithe (stats[52]): helmets, rings, necklaces, Class 4+, all
-- vocations. Backlog bonus #1. +% experience from monster kills while
-- worn. Piggybacks on the existing onGainExperience event chain
-- (default_onGainExperience.lua) rather than editing that file -- confirmed
-- multiple handlers can register side by side for the same event (that
-- file itself already registers two, at the default index and math.huge).
--
-- Registered at index 10 so it applies after the base rate multipliers
-- (default index 0 -- stamina/stage/prey/influenced/xp-boost) but before
-- the kill-text/tracker display (math.huge), so the boosted amount is what
-- actually gets shown to the player in the kill message.
local event = Event()

function event.onGainExperience(player, source, exp, rawExp, sendText)
	if not source or source:isPlayer() or exp <= 0 then
		return exp
	end

	local tithePercent = 0
	for _, slot in ipairs({CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_RING}) do
		local item = player:getSlotItem(slot)
		if item then
			local desc = item:getSpecialDescription()
			local percent = desc and tonumber(string.match(desc, "Grave Tithe: %+(%d+)%%"))
			if percent then
				tithePercent = tithePercent + percent
			end
		end
	end
	if tithePercent <= 0 then
		return exp
	end

	return exp + math.floor(exp * tithePercent / 100)
end

event:register(10)
