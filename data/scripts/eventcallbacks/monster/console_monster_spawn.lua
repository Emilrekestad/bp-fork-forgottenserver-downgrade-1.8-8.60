-- Admin console: attach the kill counter to every monster that appears.
--
-- CREATURE_EVENT_DEATH only fires for creatures that have registered the event,
-- and monsters are created by the engine rather than declared one by one, so
-- this is the only place a death handler can be attached to all of them
-- without editing 1,767 monster files.
--
-- Must return true. luagame.cpp treats a false return from onSpawn as "block
-- this creature", so a handler that forgets stops monsters spawning at all.

local event = Event()

function event.onSpawn(monster, position, startup, artificial)
	if not monster then
		return true
	end

	monster:registerEvent("ConsoleMonsterDeath")

	-- Summons are not content being played, they are a spell's side effect.
	-- Counting them would put "fire elemental" at the top of every board on a
	-- server with active mages.
	if monster:getMaster() then
		return true
	end

	local mType = monster:getType()
	if not mType or not (mType:isBoss() or mType:isRewardBoss()) then
		return true
	end

	-- A boss appearing is rare and individually interesting, so unlike ordinary
	-- monsters it gets a row of its own. `startup` is the world's initial
	-- population at boot: those are recorded too, but marked, because a boss
	-- standing since the last restart is not the same event as one that just
	-- spawned and it should not read as one.
	Bosses.opened(monster, startup and "startup" or (artificial and "raid" or "spawn"), position)
	return true
end

event:register()
