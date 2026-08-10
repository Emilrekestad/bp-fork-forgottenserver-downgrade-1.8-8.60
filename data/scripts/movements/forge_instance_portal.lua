local PORTAL_AID = 1001

local INSTANCE_FROM = Position(1037, 958, 7)
local INSTANCE_TO   = Position(1069, 989, 7)

local FORGE_CONTAINER_ID    = 37122
local FORGE_CONTAINER_SLOTS = 2
local FORGE_CONTAINER_POS   = Position(1054, 974, 7)

local instanceCounter = 20000
local returnPositions = {}

local function getInstanceCenter()
    return Position(
        math.floor((INSTANCE_FROM.x + INSTANCE_TO.x) / 2),
        math.floor((INSTANCE_FROM.y + INSTANCE_TO.y) / 2),
        INSTANCE_FROM.z
    )
end

local function isInsideInstanceArea(pos)
    return pos.x >= INSTANCE_FROM.x and pos.x <= INSTANCE_TO.x
       and pos.y >= INSTANCE_FROM.y and pos.y <= INSTANCE_TO.y
       and pos.z >= INSTANCE_FROM.z and pos.z <= INSTANCE_TO.z
end

local function ensureForgeContainerAt(pos)
    local tile = Tile(pos)
    if not tile then return end

    local existing = tile:getItemById(FORGE_CONTAINER_ID)
    if existing then
        local container = Container(existing.uid)
        if not container then
            existing:remove()
            Game.createContainer(FORGE_CONTAINER_ID, FORGE_CONTAINER_SLOTS, pos)
        end
    else
        Game.createContainer(FORGE_CONTAINER_ID, FORGE_CONTAINER_SLOTS, pos)
    end
end

local function createInstanceContent(instanceId)
    if instanceId == 0 then return end

    local tile = Tile(FORGE_CONTAINER_POS)
    if tile then
        local old = tile:getItemById(FORGE_CONTAINER_ID)
        if old then old:remove() end
    end
    Game.createContainer(FORGE_CONTAINER_ID, FORGE_CONTAINER_SLOTS, FORGE_CONTAINER_POS, instanceId)
end

local function cleanupInstanceContent(instanceId)
    if instanceId == 0 then return end

    local tile = Tile(FORGE_CONTAINER_POS)
    if tile then
        local item = tile:getItemById(FORGE_CONTAINER_ID)
        if item then
            item:remove()
        end
    end
    ensureForgeContainerAt(FORGE_CONTAINER_POS)
end

local function cleanupInstanceMonsters(instanceId)
    if instanceId == 0 then return end

    local area = Game.getInstanceArea(instanceId)
    if not area then return end

    local cx = math.floor((area.fromPos.x + area.toPos.x) / 2)
    local cy = math.floor((area.fromPos.y + area.toPos.y) / 2)
    local searchCenter = Position(cx, cy, area.fromPos.z)
    local rangeX = math.floor(math.abs(area.toPos.x - area.fromPos.x) / 2)
    local rangeY = math.floor(math.abs(area.toPos.y - area.fromPos.y) / 2)

    local spectators = Game.getSpectators(searchCenter, false, false, rangeX, rangeX, rangeY, rangeY)
    for _, spec in ipairs(spectators) do
        if spec:isMonster() and spec:getInstanceId() == instanceId then
            local summons = spec:getSummons()
            if summons then
                for _, summon in ipairs(summons) do
                    summon:remove()
                end
            end
            spec:remove()
        end
    end
end
local function cleanupInstance(player)
    local instanceId = player:getInstanceId()
    if instanceId == 0 then return end

    cleanupInstanceMonsters(instanceId)
    cleanupInstanceContent(instanceId)
    Game.unregisterInstanceArea(instanceId)

    player:setInstanceIdRaw(0)
    returnPositions[player:getGuid()] = nil
end


local ENTRY_DEST = Position(1053, 989, 7)

local portalMovement = MoveEvent()
function portalMovement.onStepIn(creature, item, position, fromPosition)
    local player = creature:getPlayer()
    if not player then return true end

    local instanceId = player:getInstanceId()

    if instanceId ~= 0 then
        local returnPos = returnPositions[player:getGuid()]
        cleanupInstance(player)

        if returnPos then
            player:teleportTo(returnPos)
        else
            local temple = player:getTown():getTemplePosition()
            player:teleportTo(temple)
        end
    else
        instanceCounter = instanceCounter + 1
        local newId = instanceCounter

        returnPositions[player:getGuid()] = fromPosition
        player:setInstanceIdRaw(newId)
        Game.registerInstanceArea(newId, INSTANCE_FROM, INSTANCE_TO)

        createInstanceContent(newId)

        player:teleportTo(ENTRY_DEST)
    end

    return true
end
portalMovement:aid(PORTAL_AID)
portalMovement:type("stepin")
portalMovement:register()

local logoutEvent = CreatureEvent("ForgeInstanceLogout")
function logoutEvent.onLogout(player)
    local instanceId = player:getInstanceId()
    if instanceId ~= 0 and isInsideInstanceArea(player:getPosition()) then
        cleanupInstance(player)
        local temple = player:getTown():getTemplePosition()
        player:teleportTo(temple)
    end
    return true
end
logoutEvent:type("logout")
logoutEvent:register()

local loginEvent = CreatureEvent("ForgeInstanceLogin")
function loginEvent.onLogin(player)
    player:registerEvent("ForgeInstanceLogout")

    local pos = player:getPosition()
    if isInsideInstanceArea(pos) then
        player:setInstanceIdRaw(0)
        local temple = player:getTown():getTemplePosition()
        player:teleportTo(temple)
        temple:sendMagicEffect(CONST_ME_TELEPORT)
    end

    return true
end
loginEvent:type("login")
loginEvent:register()
