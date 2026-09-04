-- World events the console's feed is built from, that have no other home.
--
-- Level milestones only. Deaths are emitted from others/playerdeath.lua where
-- the killer is already resolved, achievements from lib/core/achievements.lua
-- where the unlock happens, and broadcasts from the Game.broadcastMessage
-- override -- each next to the code that already knows the answer, rather
-- than re-deriving it here.

-- Every level is stored, but only these are treated as milestones. The feed
-- shows milestones by default and everything else behind a filter, so that
-- "someone hit 100" is not buried under fifty level-23 gains.
local function isMilestone(level)
	if level >= 100 then return level % 50 == 0 end
	if level >= 50 then return level % 25 == 0 end
	return level % 10 == 0
end

local advance = CreatureEvent("ConsoleAdvance")

function advance.onAdvance(player, skill, oldLevel, newLevel)
	-- Skill and magic gains are far more frequent than levels and are not what
	-- the feed is for; the analyst reads skills from `players` directly.
	if skill ~= SKILL_LEVEL then
		return true
	end

	GameEvents.emitForPlayer("player.level", player, {
		from = oldLevel,
		to = newLevel,
		milestone = isMilestone(newLevel),
		vocation = player:getVocation() and player:getVocation():getName() or nil,
	})
	return true
end

advance:register()

local advanceLogin = CreatureEvent("ConsoleAdvanceLogin")

function advanceLogin.onLogin(player)
	player:registerEvent("ConsoleAdvance")
	return true
end

advanceLogin:register()
