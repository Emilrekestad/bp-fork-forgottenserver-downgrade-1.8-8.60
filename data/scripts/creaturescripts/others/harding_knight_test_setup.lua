-- One-time GM test setup for "Harding": login validates against the character's
-- stored position (kept at the Thais temple in the DB, since that's what made
-- login succeed), then this script teleports them on to Roshamuul post-login,
-- promotes to Elite Knight, sets level 3000, equips top-tier Knight gear, and
-- fills a Backpack of Holding with high-level sword/axe/club weapons.
-- Fires once on next login, then never again.

local SETUP_FLAG = 990001
local ELITE_KNIGHT_VOCATION = 8

local GEAR = {
	{ id = 28715, slot = CONST_SLOT_HEAD },      -- Falcon Coif
	{ id = 28719, slot = CONST_SLOT_ARMOR },     -- Falcon Plate
	{ id = 28720, slot = CONST_SLOT_LEGS },      -- Falcon Greaves
	{ id = 10323, slot = CONST_SLOT_FEET },      -- Guardian Boots
	{ id = 28725, slot = CONST_SLOT_RIGHT },     -- Falcon Mace
	{ id = 28721, slot = CONST_SLOT_LEFT },      -- Falcon Shield
	{ id = 13990, slot = CONST_SLOT_NECKLACE },  -- Necklace of the Deep
	{ id = 32636, slot = CONST_SLOT_RING },      -- Ring of Souls
}

local BACKPACK_OF_HOLDING = 3253

local SHOWCASE_WEAPONS = {
	3280,  -- fire sword
	7390,  -- justice seeker
	3297,  -- serpent sword
	16160, -- crystalline sword
	3320,  -- fire axe
	3331,  -- ravager's axe
	7412,  -- butcher's axe
	7436,  -- angelic axe
	3279,  -- war hammer
	3332,  -- hammer of wrath
	7421,  -- onyx flail
	27449, -- blade of destruction
}

local hardingSetup = CreatureEvent("HardingKnightTestSetup")

function hardingSetup.onLogin(player)
	if player:getName() ~= "Harding" then
		return true
	end

	if player:getStorageValue(SETUP_FLAG) == 1 then
		return true
	end

	player:teleportTo(Position(33513, 32363, 6))
	player:setVocation(ELITE_KNIGHT_VOCATION)

	local targetExp = Game.getExperienceForLevel(3000)
	local delta = targetExp - player:getExperience()
	if delta > 0 then
		player:addExperience(delta, false)
	end

	for _, piece in ipairs(GEAR) do
		local existing = player:getSlotItem(piece.slot)
		if existing then
			existing:remove()
		end
		player:addItem(piece.id, 1, false, 1, piece.slot)
	end

	local existingBackpack = player:getSlotItem(CONST_SLOT_BACKPACK)
	if existingBackpack then
		existingBackpack:remove()
	end
	local holdingBag = player:addItem(BACKPACK_OF_HOLDING, 1, false, 1, CONST_SLOT_BACKPACK)
	if holdingBag then
		local container = Container(holdingBag)
		if container then
			for _, weaponId in ipairs(SHOWCASE_WEAPONS) do
				container:addItem(weaponId, 1)
			end
		end
	end

	player:setStorageValue(SETUP_FLAG, 1)
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Test setup complete: teleported to Roshamuul, Elite Knight, level 3000, full Knight gear, backpack of holding stocked with sword/axe/club weapons.")

	return true
end

hardingSetup:register()
