local login = CreatureEvent("StaminaRegen")
function login.onLogin(player)
    if not configManager.getBoolean(configKeys.STAMINA_SYSTEM) then
        return true
    end

    local lastLogout = player:getLastLogout()
    local offlineTime = lastLogout ~= 0 and math.min(os.time() - lastLogout, 86400 * 21) or 0
    offlineTime = offlineTime - 600

    if offlineTime < 180 then
        return true
    end

    local staminaMinutes = player:getStamina()
    local maxNormalStaminaRegen = 2400 - math.min(2400, staminaMinutes)

    local regainStaminaMinutes = offlineTime / 180
    if regainStaminaMinutes > maxNormalStaminaRegen then
        local happyHourStaminaRegen = (offlineTime - (maxNormalStaminaRegen * 180)) / 600
        staminaMinutes = math.min(2520, math.max(2400, staminaMinutes) + happyHourStaminaRegen)
    else
        staminaMinutes = staminaMinutes + regainStaminaMinutes
    end

    -- Bao's Ledger "Second Wind" scales what the rest was worth. Applied to
    -- the GAIN rather than the total, so it cannot inflate stamina a player
    -- already had, and clamped by the same bounds as before.
    if BaoLedger then
        local gained = staminaMinutes - player:getStamina()
        if gained > 0 then
            staminaMinutes = player:getStamina() + (gained * BaoLedger.staminaMultiplier(player))
        end
    end

    player:setStamina(math.floor(math.max(0, math.min(2520, staminaMinutes))))
    return true
end
login:register()
