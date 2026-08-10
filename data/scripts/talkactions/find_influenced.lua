local findInfluenced = TalkAction("/findinfluenced")

function findInfluenced.onSay(player, words, param)
    local influencedList = Game.getInfluencedCreatures()

    if #influencedList == 0 then
        player:sendTextMessage(MESSAGE_EVENT_ORANGE,
            "Não há criaturas influenciadas ativas no momento.")
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
            "Não há criaturas influenciadas ativas no momento.")
        return false
    end

    local mPos = closest:getPosition()
    local dx = mPos.x - playerPos.x
    local dy = mPos.y - playerPos.y
    local sqmDist = math.max(math.abs(dx), math.abs(dy))

    local direction = ""
    if math.abs(dy) > math.abs(dx) then
        direction = dy < 0 and "Norte" or "Sul"
    elseif math.abs(dx) > math.abs(dy) then
        direction = dx > 0 and "Leste" or "Oeste"
    else
        if dy < 0 then
            direction = dx > 0 and "Nordeste" or "Noroeste"
        else
            direction = dx > 0 and "Sudeste" or "Sudoeste"
        end
    end

    local monsterName = closest:getName()
    local level = closest:getInfluencedLevel()

    player:sendTextMessage(MESSAGE_EVENT_ORANGE,
        string.format(
            "A criatura influenciada mais próxima (%s, nível %d) está ao %s, a aproximadamente %d SQMs de você.",
            monsterName, level, direction, sqmDist))

    return false
end
findInfluenced:separator(" ")
findInfluenced:register()
