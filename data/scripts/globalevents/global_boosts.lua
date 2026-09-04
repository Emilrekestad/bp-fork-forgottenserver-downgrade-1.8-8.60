-- Global Server Boosts — startup restore and the one-second clock.
--
-- The clock is what makes the mechanic work: it retires expired boosts,
-- broadcasts the 5-minute and 1-minute warnings that drive re-purchases, and
-- pushes state to clients on every change. It does NOT push on every tick --
-- the client counts down locally between pushes, so a 200-player server sends
-- a handful of packets an hour, not 200 a second.
--
-- It also garbage-collects the Spawn Boost's extra monsters; see
-- eventcallbacks/monster/global_boost_onSpawn.lua for why those exist and why
-- they need collecting at all.

local startup = GlobalEvent("GlobalBoostsStartup")

function startup.onStartup()
	GlobalBoosts.load()

	-- Boot diagnostic, and not a decorative one. This whole system fails
	-- SILENTLY when the network layer is missing: GlobalBoosts.sendState is
	-- set only by scripts/network/boosts/boosts_protocol.lua, and every caller
	-- is nil-guarded, so if that script ever fails to load the server keeps
	-- taking payments, keeps its timers, logs nothing, and no client is ever
	-- told anything. One line at boot turns that into something greppable.
	print(string.format("[GlobalBoosts] network layer: %s",
		GlobalBoosts.sendState and "loaded (opcode 0x56/0x57)" or "MISSING - no client will see boosts"))

	local active = GlobalBoosts.active()
	if #active == 0 then
		return true
	end

	for _, entry in ipairs(active) do
		print(string.format("[GlobalBoosts] Restored %s (%s remaining, last extended by %s)",
			entry.boost.name, GlobalBoosts.formatDuration(entry.remaining),
			entry.contributor ~= "" and entry.contributor or "unknown"))
	end

	-- Nobody is online at startup, so this is only here for the reload case;
	-- the login creaturescript covers the real path.
	GlobalBoosts.syncAllPlayers()
	return true
end

startup:register()

local tick = GlobalEvent("GlobalBoostsTick")

function tick.onThink(interval)
	GlobalBoosts.tick()

	if GlobalBoostsSpawnEcho and GlobalBoostsSpawnEcho.collect then
		GlobalBoostsSpawnEcho.collect()
	end

	return true
end

-- NO `tick:type("think")`. It reads like the right call and it is a trap in
-- this engine: luaglobalevent.cpp:53-54 maps the string "think" to
-- GLOBALEVENT_TIMER, and GlobalEvents::registerLuaEvent then files the event
-- in timerMap instead of thinkMap. timerMap is the once-a-day wall-clock path
-- (globalevent.cpp:104 hardcodes `setNextExecution(now + 86400000)` and
-- ignores getInterval() entirely), so the event fires once and then not again
-- for 24 hours. Caught in a live deploy test: two seeded boosts sat in
-- `server_boosts` for three minutes past their deadline without expiring.
--
-- An interval think event is one that leaves its type at the default
-- GLOBALEVENT_NONE and sets only interval() -- which is exactly what
-- map_cleaner.lua does, and it is the only shape in this datapack that
-- actually ticks.
--
-- Two other files in this directory have the same latent bug and are NOT
-- touched here: guild_war_expire.lua (meant to run every 10 minutes) and
-- worldmissions/worldmissions_presence.lua. Both are running once per day.
tick:interval(1000)
tick:register()
