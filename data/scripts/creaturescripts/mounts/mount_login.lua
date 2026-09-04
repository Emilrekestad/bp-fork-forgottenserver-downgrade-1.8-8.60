-- Activates the Music Box modal-response CreatureEvent on every logging-in
-- player -- this fork requires explicit per-instance opt-in for
-- CreatureEvents (see rarity_login.lua's own login hook for the same
-- pattern), so without this, MusicBoxModal is defined but never fires.
local mountLogin = CreatureEvent("MountLogin")

function mountLogin.onLogin(player)
	player:registerEvent("MusicBoxModal")
	return true
end

mountLogin:register()
