local gotoInfluenced = TalkAction("/gotoinfluenced")
function gotoInfluenced.onSay(player, words, param)
    if player:getAccountType() < ACCOUNT_TYPE_GAMEMASTER then
        return false
    end

    local influencedList = Game.getInfluencedCreatures()

    if #influencedList == 0 then
        player:sendTextMessage(MESSAGE_EVENT_ORANGE,
            "[GM] Não há criaturas influenciadas ativas no momento.")
        return false
    end

    local playerPos = player:getPosition()
    local closest = nil
    local closestDist = math.huge

    for _, monster in ipairs(influencedList) do
        local mPos = monster:getPosition()
        local dist = math.abs(playerPos.x - mPos.x) + math.abs(playerPos.y - mPos.y)
                   + math.abs(playerPos.z - mPos.z) * 10
        if dist < closestDist then
            closestDist = dist
            closest = monster
        end
    end

    if not closest then
        player:sendTextMessage(MESSAGE_EVENT_ORANGE,
            "[GM] Não há criaturas influenciadas ativas no momento.")
        return false
    end

    local destPos = closest:getPosition()
    player:teleportTo(destPos)
    destPos:sendMagicEffect(CONST_ME_TELEPORT)

    player:sendTextMessage(MESSAGE_EVENT_ORANGE,
        string.format("[GM] Teleportado para %s (nível %d).",
            closest:getName(), closest:getInfluencedLevel()))

    return false
end
gotoInfluenced:separator(" ")
gotoInfluenced:register()
