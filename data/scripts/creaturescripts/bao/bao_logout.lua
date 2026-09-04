-- Old Man Bao — logout hook.
--
-- Two jobs, and the order between them is not optional.
--
-- 1. Flush. Hunt progress is only written to the database on a
--    BaoConfig.SaveInterval boundary, so up to that many kills are sitting in
--    memory at any moment. Without this they are lost on logout.
--
--    The flush is SYNCHRONOUS. Ordinary saves go through db.asyncQuery (a
--    queue drained by another thread) while loads use db.storeQuery (blocking,
--    on the game thread), and nothing orders the two against each other. A
--    fast relog could otherwise re-read the row before the queued write
--    landed, hand the player their old progress, and then overwrite the newer
--    row from that stale cache.
--
-- 2. Clear the session cache. It is keyed by player:getId(), which is never
--    reused within an uptime, so a stale entry is not a correctness problem —
--    but it is never freed either, and it accumulates one entry per player who
--    logs in for as long as the server stays up. BaoState.clearCache existed
--    for exactly this and was simply never wired to anything.
--
-- NetworkGuard's per-player cooldown table is keyed the same way and has the
-- same leak, so it is cleared here too.

local baoLogout = CreatureEvent("BaoLogout")

function baoLogout.onLogout(player)
	if BaoState then
		BaoState.flush(player, true)
		BaoState.clearCache(player)
	end
	if NetworkGuard and NetworkGuard.clearPlayer then
		NetworkGuard.clearPlayer(player)
	end
	return true
end

baoLogout:register()

-- CreatureEvents of type logout have to be registered against each player
-- individually; a login hook is the standard place to do it in this datapack
-- (see data/scripts/creaturescripts/player_login_logout.lua).
local baoLogin = CreatureEvent("BaoLogin")

function baoLogin.onLogin(player)
	player:registerEvent("BaoLogout")
	return true
end

baoLogin:register()
