local gotoInfluenced = TalkAction("/gotoinfluenced")
function gotoInfluenced.onSay(player, words, param)
    if player:getAccountType() < ACCOUNT_TYPE_GAMEMASTER then
        return false
    end

    local influencedList = Game.getInfluencedCreatures()

    if #influencedList == 0 then
        player:sendTextMessage(MESSAGE_EVENT_ORANGE,
            "[GM] There are no active influenced creatures right now.")
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
            "[GM] There are no active influenced creatures right now.")
        return false
    end

    local destPos = closest:getPosition()
    player:teleportTo(destPos)
    destPos:sendMagicEffect(CONST_ME_TELEPORT)

    player:sendTextMessage(MESSAGE_EVENT_ORANGE,
        string.format("[GM] Teleported to %s (level %d).",
            closest:getName(), closest:getInfluencedLevel()))

    return false
end
gotoInfluenced:separator(" ")
-- Security audit 2026-10-05: duplicate of god/navigation/goto_influenced.lua
-- (same words; std::map keeps the first registration, which is that file).
-- Gated here too so load order can never expose an unlogged teleport.
gotoInfluenced:accountType(ACCOUNT_TYPE_GAMEMASTER)
gotoInfluenced:access(true)
gotoInfluenced:register()
