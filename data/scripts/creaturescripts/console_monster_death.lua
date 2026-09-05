-- Admin console: count what is being killed.
--
-- Registered on every monster by eventcallbacks/monster/console_monster_spawn.lua.
-- The handler is deliberately tiny -- it runs on every monster death on the
-- server, and everything expensive (aggregation, the database) happens in the
-- flush on a timer instead.

local FLUSH_INTERVAL_MS = 30 * 1000

local function killerName(killer)
	if not killer then
		return nil, false
	end
	if killer:isPlayer() then
		return killer:getName(), true
	end
	-- A summon's kill belongs to whoever owns it: "killed by a fire elemental"
	-- is true but useless when a mage is standing behind it.
	local master = killer:getMaster()
	if master and master ~= killer and master:isPlayer() then
		return master:getName(), true
	end
	return killer:getName(), false
end

local monsterDeath = CreatureEvent("ConsoleMonsterDeath")

function monsterDeath.onDeath(monster, corpse, killer, mostDamageKiller)
	if not monster then
		return true
	end

	-- Summons again: excluded on the way in, so exclude them on the way out.
	if monster:getMaster() then
		return true
	end

	local mType = monster:getType()
	local isBoss = mType and (mType:isBoss() or mType:isRewardBoss()) or false

	Kills.record(monster:getName(), isBoss)

	if isBoss then
		local name, byPlayer = killerName(killer or mostDamageKiller)
		Bosses.killed(monster, name, byPlayer)
	end

	return true
end

monsterDeath:register()

-- The flush lives here rather than in console_telemetry.lua so that the
-- counter and the thing that drains it are one file. :interval() rather than
-- :type("think") -- a think-registered GlobalEvent competes with the other
-- think handlers and has broken two of them before.
local killFlush = GlobalEvent("ConsoleKillFlush")

function killFlush.onThink(interval)
	local written = Kills.flush()
	-- Flushed in the same pass as the kills, deliberately: drops and the
	-- corpses they came from must be written together or a lost flush would
	-- bias every drop rate upward.
	local looted = Loot.flush()
	-- Only when something was actually written. This is the one observable
	-- proof that the timer is running at all: with no metric and no rows, a
	-- flush that never fires and a server where nothing died look identical.
	if written > 0 then
		Metrics.write("kills.flushed", written)
	end
	-- Separate from kills.flushed on purpose: the loot tracker hangs off a
	-- different hook at a different point in the death path, and if it ever
	-- stops firing while kills keep counting, two metrics say so where one
	-- would not.
	if looted > 0 then
		Metrics.write("loot.flushed", looted)
	end
	return true
end

killFlush:interval(FLUSH_INTERVAL_MS)
killFlush:register()

-- On the way down, write synchronously. An async query is handed to a worker
-- thread the process does not wait for, so anything still buffered at shutdown
-- would simply be lost -- the same trap that made every clean restart look like
-- a crash before server.stop was made synchronous.
local killShutdown = GlobalEvent("ConsoleKillShutdown")

function killShutdown.onShutdown()
	Kills.flush(true)
	Loot.flush(true)
	return true
end

killShutdown:register()
