-- Achievements on login: bring the database mirror in line with storage.
--
-- Player.addAchievement writes both sides, so in normal play this finds
-- nothing and costs one indexed SELECT. It exists for everything that is not
-- normal play: unlocks earned before the mirror existed, a GM setting a
-- storage by hand, a script that wrote storage directly instead of going
-- through addAchievement, and any row lost to a crash mid-write.
--
-- Running per character rather than per account is correct here -- achievements
-- are character-scoped, unlike loyalty rewards.

local achievementsLogin = CreatureEvent("AchievementsLogin")

function achievementsLogin.onLogin(player)
	local added, removed = AchievementsDB.reconcilePlayer(player)
	if added > 0 or removed > 0 then
		print(string.format("[Achievements] Reconciled %s: +%d / -%d",
			player:getName(), added, removed))
	end
	return true
end

achievementsLogin:register()
