-- Global Server Boosts on login.
--
-- Two jobs, both required and neither optional:
--
-- 1. Apply the PUSH effects (speed, regeneration). Those are engine
--    conditions living on the character, so a player who logs in halfway
--    through a Speed Boost has none of it until something puts the condition
--    on them. GlobalBoosts.syncPlayer is idempotent -- it strips its own two
--    subIds first -- so it is also the correct thing to run when no boost is
--    active, clearing anything a crash or a stale save left behind.
--
-- 2. Push the HUD state. The client asks for it too (opcode 0x57 on module
--    load), but a login lands well after that request for anyone who was
--    already at the character list, so the server pushing here is what
--    actually populates the HUD in the common case.
--
-- The push is deferred one tick: sendState writes to the player's protocol,
-- and at onLogin time the client has not finished entering the game.

local boostsLogin = CreatureEvent("GlobalBoostsLogin")

function boostsLogin.onLogin(player)
	GlobalBoosts.syncPlayer(player)

	local playerId = player:getId()
	addEvent(function()
		local onlinePlayer = Player(playerId)
		if onlinePlayer and GlobalBoosts.sendState then
			GlobalBoosts.sendState(onlinePlayer)
		end
	end, 500)

	return true
end

boostsLogin:register()
