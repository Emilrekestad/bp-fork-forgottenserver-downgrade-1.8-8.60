-- (!) This is the login/logout handler that actually runs.
--
-- There was a second copy at data/scripts/creaturescripts/player_login_logout.lua
-- registering CreatureEvents under the same two names. CreatureEvents::registerLuaEvent
-- uses map::emplace, which keeps the entry already present rather than replacing
-- it, so whichever file loaded first won and the other was discarded in silence
-- -- no warning, no error, just a script that never ran. The console telemetry
-- had been added to the copy that lost, which is why `player_sessions` was
-- empty and no session.login event had ever been recorded.
--
-- The stale copy is gone. Before adding a CreatureEvent anywhere, check the
-- name is not already taken.

local loginMessage = CreatureEvent("loginMessage")

function loginMessage.onLogin(player)
    -- Admin console: open a session row and record the login. The session row
    -- is what playtime, retention and rhythm are all computed from; the event
    -- is what the timeline and "who was on today" answer from.
    Sessions.open(player)
    GameEvents.emitForPlayer("session.login", player, {
        level = player:getLevel(),
        vocation = player:getVocation() and player:getVocation():getName() or nil,
        town = player:getTown() and player:getTown():getName() or nil,
    })

    local rewardChest = player:getRewardChest()
    local rewardContainerCount = 0
    for _, item in ipairs(rewardChest:getItems()) do
        if item:getId() == ITEM_REWARD_CONTAINER then
            rewardContainerCount = rewardContainerCount + 1
        end
    end
    if rewardContainerCount > 0 then
        player:sendTextMessage(MESSAGE_STATUS_DEFAULT, string.format("You have %d reward%s in your reward chest.", rewardContainerCount, rewardContainerCount > 1 and "s" or ""))
    end

    local serverName = configManager.getString(configKeys.SERVER_NAME)
    local loginStr = "Welcome to " .. serverName .. "!"
    if player:getLastLoginSaved() <= 0 then
        loginStr = loginStr .. " Please choose your outfit."
        player:sendOutfitWindow()
    else
        loginStr = string.format("Your last visit in %s: %s.", serverName, os.date("%d %b %Y %X", player:getLastLoginSaved()))
    end
    player:sendTextMessage(MESSAGE_STATUS_DEFAULT, loginStr)

    local vocation = player:getVocation()
    if vocation:getId() ~= 0 then
        local promotion = vocation:getPromotion()
        if player:isPremium() then
            local value = player:getStorageValue(PlayerStorageKeys.promotion)
            if value and value == 1 then
                player:setVocation(promotion)
            end
        elseif not promotion then
            player:setVocation(vocation:getDemotion())
        end
    end

    -- Update Experience Rate Stamina
    player:updateStamina()

    player:registerEvent("logoutMessage")

    player:openChannel(10)

	if configManager.getBoolean(RESET_SYSTEM_ENABLED) then
		if ResetBonusConfig then
			ResetBonusConfig.applyBonuses(player)
		end
	end

    if player:isTokenProtected() then
        player:setTokenLocked(true)
        player:popupFYI("=== TOKEN PROTECTION ===\n\nYour account is protected by TOKEN.\n\nYou cannot move or drop items until you unlock.\n\nType: !token <your_password>\n\nto unlock your character.")
        player:sendTextMessage(MESSAGE_STATUS_CONSOLE_RED, "[Token] You are LOCKED! Type !token <password> to unlock.")
    end

    player:sendTextMessage(MESSAGE_STATUS_DEFAULT, "[Mount] Use Ctrl+M to mount or dismount your mount.")

    return true
end
loginMessage:register()

local logoutMessage = CreatureEvent("logoutMessage")
function logoutMessage.onLogout(player)
    -- Closes the row opened above. Recorded before anything else here, because
    -- the level and vocation are read off the player and the rest of this
    -- handler tears session state down.
    Sessions.close(player, "logout")
    GameEvents.emitForPlayer("session.logout", player, {
        level = player:getLevel(),
        vocation = player:getVocation() and player:getVocation():getName() or nil,
    })

    local playerId = player:getId()
    nextUseStaminaTime[playerId] = nil
    WorkbenchSessions.clearOwner(playerId, false)
    ImbuingWindow.close(player)
    return true
end
logoutMessage:register()
