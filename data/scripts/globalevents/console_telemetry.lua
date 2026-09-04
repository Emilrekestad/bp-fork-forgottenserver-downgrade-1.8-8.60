-- Admin console telemetry: the sampler, the boot markers and crash recovery.
--
-- Deliberately NOT using :type("think"). A GlobalEvent registered as a think
-- event competes with the other think handlers in this folder and has broken
-- two of them before; :interval() is the supported shape for "run me every N
-- milliseconds" and is what every other periodic job here uses.

local SAMPLE_INTERVAL_MS = 60 * 1000

-- ------------------------------------------------------------- startup

local consoleStartup = GlobalEvent("ConsoleTelemetryStartup")

function consoleStartup.onStartup()
	-- Close sessions the last run left open. This runs before any player can
	-- log in, so it can never close a live session by mistake. Without it a
	-- crash leaves rows with no logout, and every playtime average is wrong
	-- in the direction of "everyone plays forever".
	Sessions.recoverOrphans()

	GameEvents.emit("server.start", {
		payload = {world = configManager.getString(configKeys.SERVER_NAME)},
	})

	Metrics.write("server.boot", 1)
	return true
end

consoleStartup:register()

-- ------------------------------------------------------------ shutdown

local consoleShutdown = GlobalEvent("ConsoleTelemetryShutdown")

function consoleShutdown.onShutdown()
	-- A clean stop is what tells the console's crash detector that the next
	-- start was intentional. Sessions are closed as 'server_stop' rather than
	-- 'logout' so a restart does not look like everyone quitting at once.
	--
	-- Everything here is written synchronously. An async query is handed to a
	-- worker thread the process does not wait for, so on shutdown it is simply
	-- lost -- which meant every clean restart was recorded as a crash and woke
	-- the ops channel.
	local players = Game.getPlayers()
	for _, player in ipairs(players) do
		Sessions.close(player, "server_stop", true)
	end
	GameEvents.emit("server.stop", {sync = true, payload = {players_online = #players}})
	return true
end

consoleShutdown:register()

-- -------------------------------------------------------------- sampler

local consoleSampler = GlobalEvent("ConsoleTelemetrySampler")

function consoleSampler.onThink(interval)
	local players = Game.getPlayers()
	Metrics.write("online.total", #players)

	-- Population by vocation and by town, as tagged series. The console's
	-- World view draws both from these rather than scanning `players`, which
	-- would count offline characters.
	local byVocation, byTown = {}, {}
	for _, player in ipairs(players) do
		local vocation = player:getVocation()
		local vocationName = vocation and vocation:getName() or "None"
		byVocation[vocationName] = (byVocation[vocationName] or 0) + 1

		local town = player:getTown()
		local townName = town and town:getName() or "Unknown"
		byTown[townName] = (byTown[townName] or 0) + 1
	end
	for name, count in pairs(byVocation) do
		Metrics.write("online.by_vocation", count, {vocation = name})
	end
	for name, count in pairs(byTown) do
		Metrics.write("online.by_town", count, {town = name})
	end

	Metrics.write("uptime.seconds", os.time() - (Console.bootTime or os.time()))
	return true
end

consoleSampler:interval(SAMPLE_INTERVAL_MS)
consoleSampler:register()

-- Recorded once at load so uptime is measured from this boot rather than from
-- the first sample.
Console.bootTime = os.time()
