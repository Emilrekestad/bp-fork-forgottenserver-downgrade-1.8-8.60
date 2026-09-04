local config = {
    time = "09:55:00"
}

-- The console records how long each save took. A save whose duration is
-- creeping up is one of the earliest honest warnings a server gives, and
-- until now nothing was measuring it. The emit is deliberately after the
-- game state is back to normal, so nothing here can delay players getting
-- back in.
local function ServerSave()
    if CustomMarket and CustomMarket.updateStatistics then
        CustomMarket.updateStatistics()
    end

    local onlineBefore = #Game.getPlayers()
    local startedAt = os.mtime()
    local shuttingDown = configManager.getBoolean(configKeys.SERVER_SAVE_SHUTDOWN)
    local cleanedMap = false

    if shuttingDown then
        Game.setGameState(GAME_STATE_SHUTDOWN)
    else
        local closeAtServerSave = configManager.getBoolean(configKeys.SERVER_SAVE_CLOSE)
        if closeAtServerSave then
            Game.setGameState(GAME_STATE_CLOSED)
        end

        saveServer()

        if configManager.getBoolean(configKeys.SERVER_SAVE_CLEAN_MAP) then
            cleanMap()
            cleanedMap = true
        end

        if closeAtServerSave then
            Game.setGameState(GAME_STATE_NORMAL)
        end
    end

    local onlineAfter = #Game.getPlayers()
    GameEvents.emit("server.save", {
        -- Synchronous on the shutdown path only: an async query is handed to a
        -- worker thread the process does not wait for, so a save that ends in
        -- a shutdown would never be recorded at all.
        sync = shuttingDown,
        payload = {
            duration_ms = os.mtime() - startedAt,
            players_online = onlineBefore,
            kicked = math.max(0, onlineBefore - onlineAfter),
            cleaned_map = cleanedMap,
            shutdown = shuttingDown,
        },
    })
end

local function ServerSaveWarning(remainingTime)
    local nextWarning = remainingTime - 60000
    
    if nextWarning > 0 and configManager.getBoolean(configKeys.SERVER_SAVE_NOTIFY_MESSAGE) then
        local minutes = math.floor(nextWarning / 60000)
        local message = string.format(
            "Server is %s in %d minute(s). Please logout.",
            configManager.getBoolean(configKeys.SERVER_SAVE_SHUTDOWN) and "shutting down" or "saving game",
            minutes
        )
        Game.broadcastMessage(message, MESSAGE_STATUS_WARNING)
        
        if nextWarning > 60000 then
            addEvent(ServerSaveWarning, 60000, nextWarning)
        else
            addEvent(ServerSave, 60000)
        end
    else
        addEvent(ServerSave, nextWarning > 0 and nextWarning or 1000)
    end
end

local serverSave = GlobalEvent("ServerSave")

function serverSave.onTime(interval)
    local notifyDuration = configManager.getNumber(configKeys.SERVER_SAVE_NOTIFY_DURATION)
    local remainingTime = notifyDuration * 60000
    
    if configManager.getBoolean(configKeys.SERVER_SAVE_NOTIFY_MESSAGE) then
        local message = string.format(
            "Server is %s in %d minute(s). Please logout.",
            configManager.getBoolean(configKeys.SERVER_SAVE_SHUTDOWN) and "shutting down" or "saving game",
            notifyDuration
        )
        Game.broadcastMessage(message, MESSAGE_STATUS_WARNING)
    end
    
    if remainingTime > 60000 then
        addEvent(ServerSaveWarning, 60000, remainingTime)
    else
        addEvent(ServerSave, remainingTime)
    end
    
    return not configManager.getBoolean(configKeys.SERVER_SAVE_SHUTDOWN)
end

serverSave:time(config.time)
serverSave:register()
