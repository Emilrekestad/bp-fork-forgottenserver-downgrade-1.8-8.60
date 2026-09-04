-- Global Experience Boost.
--
-- Trigger index 50 puts this strictly AFTER default_onGainExperience (index 0,
-- which applies stages, stamina, the per-character XP boost, prey and
-- influenced multipliers) and strictly BEFORE weapon_proficiency (100) and
-- the exp-message aggregator (math.huge). So the server boost multiplies the
-- fully-resolved number, and weapon proficiency plus the "You gained N
-- experience points" line both see the boosted value -- which is what players
-- expect when the HUD says a boost is running.
--
-- Must ALWAYS return a number: scripts/lib/event_callbacks.lua feeds each
-- handler's return straight back into argument 3 for the next one
-- (updateableParameters), so returning nil silently blanks the experience for
-- everything downstream.

local BOOST_ID = GlobalBoosts.ID.EXPERIENCE

local event = Event()

function event.onGainExperience(player, source, exp, rawExp, sendText)
	if not source or source:isPlayer() then
		return exp
	end

	local percent = GlobalBoosts.magnitude(BOOST_ID)
	if percent <= 0 then
		return exp
	end

	return exp * (100 + percent) / 100
end

event:register(50)
