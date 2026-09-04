-- Opens the Item Bazaar channel automatically on login.
--
-- Without this the channel exists but stays closed until a player finds it via
-- Ctrl+O, and any notification sent meanwhile is dropped by the client with a
-- "message in channel id 11 which is unknown" warning -- so players would
-- silently miss being outbid or told their auction sold.
--
-- Opened on a short delay: at the moment onLogin fires the client has not
-- finished setting up its chat panel, so an immediately-sent openChannel is
-- ignored. The same reason other login-time UI pushes in this datapack defer a
-- tick.
--
-- This is presentation only. Notifications are queued in `bazaar_events` and
-- retried until an account is reachable (see the pump in
-- data/scripts/globalevents/item_bazaar/), so nothing is lost if the channel
-- fails to open or the player closes it.

local CHANNEL_ITEM_BAZAAR = 11
local OPEN_DELAY_MS = 1000

local login = CreatureEvent("ItemBazaarLogin")

function login.onLogin(player)
	local playerId = player:getId()
	addEvent(function()
		local target = Player(playerId)
		if target then
			target:openChannel(CHANNEL_ITEM_BAZAAR)
		end
	end, OPEN_DELAY_MS)
	return true
end

login:register()
