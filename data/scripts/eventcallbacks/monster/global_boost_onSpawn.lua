-- Global Spawn Boost.
--
-- WHY THIS IS A LUA ECHO RATHER THAN A REAL RATE CHANGE
--
-- The spawn interval is computed entirely in C++ (Spawn::checkSpawn,
-- src/spawn.cpp:602 -- `sb.interval / currentRate`, where currentRate comes
-- from ConfigManager::RATE_SPAWN times Game::getSpawnRate()). Game.getSpawnRate
-- is exposed to Lua read-only (luagame.cpp:1891) and there is no setter; the
-- value is also a uint8_t, so it could not express 1.5x even if there were
-- one. Making the scheduler itself run 1.5x fast needs a C++ patch and a
-- binary rebuild. This datapack ships script-only deploys, so instead:
--
--   every NATURAL spawn has a 50% chance of being immediately doubled.
--
-- Over time that is exactly 1.5 monsters per spawn event -- the same thing a
-- 1.5x rate delivers -- and it is what players actually perceive as a spawn
-- boost. It differs from a true rate change in one way worth knowing: it
-- raises the population of an idle respawn area rather than shortening the
-- wait for the next one. In a hunted area, where the spawn is constantly
-- empty, the two are indistinguishable.
--
-- THE THREE GUARDS
--
-- 1. `artificial` is false only for Spawn::spawnMonster (spawn.cpp:495);
--    Game.createMonster passes true (luagame.cpp:746). That single flag is
--    what stops the echo echoing itself -- no bookkeeping flag needed.
-- 2. `startup` is true for the world's initial population at boot. Doubling
--    the entire map once at startup is not a 30-minute boost.
-- 3. Bosses, reward bosses, summons, zero-experience creatures and anything
--    named in EXCLUDED below are skipped. A boss is a scripted encounter with
--    its own lever/cooldown machinery, and a second copy is a bug, not a
--    bonus. The zero-experience rule catches the props that are placed
--    through the spawn system but are not creatures anyone hunts -- the
--    Boosted Statue this datapack spawns at the temple is exactly that, and
--    two of it standing on the same tile would be an obvious visual bug.
--
-- Must return true: luagame.cpp:746 treats a false return from onSpawn as
-- "block this creature" unless force is set, so a handler that forgets would
-- stop monsters spawning at all.

local BOOST_ID = GlobalBoosts.ID.SPAWN

-- Echoed monsters belong to no Spawn, so nothing in the engine will ever
-- clean them up the way Spawn::cleanup() clears out its own. Left alone they
-- would accumulate forever. Each is registered here with a deadline and
-- collected by the GlobalBoostsTick globalevent.
GlobalBoostsSpawnEcho = GlobalBoostsSpawnEcho or {}

local ECHO_TTL = 15 * 60          -- seconds a stray echo may live unkilled
local ECHO_GC_RANGE = 12          -- do not despawn under a player's nose
local ECHO_DELAY_MIN = 400        -- ms
local ECHO_DELAY_MAX = 1400       -- ms

-- Operator escape hatch, lowercase monster names. Add anything that turns out
-- to break when there are two of it: a puzzle-room guardian, a creature a
-- quest counts, a spawn that shares a tile with something fragile. Bosses and
-- zero-experience props are already handled by the guards below and do not
-- need listing here.
local EXCLUDED = {
	["boosted statue"] = true,
}

local tracked = {}
local trackedCount = 0

local function track(monsterId)
	if tracked[monsterId] then
		return
	end
	tracked[monsterId] = os.time() + ECHO_TTL
	trackedCount = trackedCount + 1
end

local function untrack(monsterId)
	if tracked[monsterId] then
		tracked[monsterId] = nil
		trackedCount = trackedCount - 1
	end
end

-- Called once a second from scripts/globalevents/global_boosts.lua. Cheap:
-- the table only ever holds echoes that are still alive, and it empties
-- itself as players kill them.
function GlobalBoostsSpawnEcho.collect()
	if trackedCount == 0 then
		return
	end

	local now = os.time()
	for monsterId, deadline in pairs(tracked) do
		local monster = Monster(monsterId)
		if not monster then
			untrack(monsterId)
		elseif now >= deadline then
			local nearby = Game.getSpectators(monster:getPosition(), false, true,
				ECHO_GC_RANGE, ECHO_GC_RANGE, ECHO_GC_RANGE, ECHO_GC_RANGE)
			if #nearby == 0 then
				untrack(monsterId)
				monster:remove()
			else
				-- Someone is hunting here. Leave it and look again later
				-- rather than deleting a monster mid-fight.
				tracked[monsterId] = now + 60
			end
		end
	end
end

function GlobalBoostsSpawnEcho.count()
	return trackedCount
end

local event = Event()

function event.onSpawn(monster, position, startup, artificial)
	if not monster or startup or artificial then
		return true
	end

	local percent = GlobalBoosts.magnitude(BOOST_ID)
	if percent <= 0 then
		return true
	end

	if monster:getMaster() then
		return true
	end

	local mType = monster:getType()
	if not mType or mType:isBoss() or mType:isRewardBoss() then
		return true
	end

	local name = mType:getName()
	if EXCLUDED[tostring(name):lower()] then
		return true
	end

	-- Zero experience means nothing gains from killing it, so nothing gains
	-- from there being two: statues, dummies and other spawn-placed props.
	if (mType:experience() or 0) <= 0 then
		return true
	end

	if math.random(1, 100) > percent then
		return true
	end

	-- Deferred rather than created inline: this callback runs from inside
	-- Spawn::spawnMonster BEFORE the monster it was handed has been placed on
	-- the map, and re-entering Game.createMonster at that point is asking for
	-- trouble. The random delay also makes the pair read as two spawns rather
	-- than one duplicated creature.
	-- `name` was captured above for the exclusion check; the closure needs
	-- primitives, not the userdata, since neither the monster nor its type is
	-- guaranteed to still be valid when the deferred event runs.
	local target = Position(position.x, position.y, position.z)
	local instanceId = position.instanceId or 0

	addEvent(function()
		-- Re-check: the boost may have expired during the delay.
		if GlobalBoosts.magnitude(BOOST_ID) <= 0 then
			return
		end

		local echo = Game.createMonster(name, target, true, false, CONST_ME_NONE, instanceId)
		if echo then
			track(echo:getId())
		end
	end, math.random(ECHO_DELAY_MIN, ECHO_DELAY_MAX))

	return true
end

event:register()
