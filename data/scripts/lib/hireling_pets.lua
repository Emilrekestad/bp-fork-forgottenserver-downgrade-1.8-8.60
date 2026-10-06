-- House pets.
--
-- A pet is a named animal that lives in one house: it wanders, it cannot be
-- attacked, and it cannot leave. It belongs to a CHARACTER, not to a hireling
-- -- the hireling window is only where you manage it, the same way the store
-- sells it under the Hireling tab.
--
-- Shape deliberately copied from data/scripts/lib/hireling.lua, because the
-- two solve the same problem: a creature that has to survive a restart while
-- its owner is offline.
--
--   * one row per pet in `player_hireling_pets` (kv cannot be read for an
--     offline player, and the startup sweep runs before anyone logs in);
--   * one NPC TYPE per pet, keyed "Pet <id>", registered once and RENAMED in
--     place, because Game.createNpcType refuses to run outside the Scripts and
--     Npc interfaces -- and the window's packet handler is neither. It runs in
--     the Events interface (data/events/scripts/player.lua dispatches it),
--     which is exactly the trap that made an earlier hireling rename fail.
--     Every type is therefore built at startup or from the basket ACTION;
--     Game.createNpc and NpcType:name() are free to run anywhere afterwards.

HIRELING_PETS = HIRELING_PETS or {}          -- id -> pet
HIRELING_PETS_BY_PLAYER = HIRELING_PETS_BY_PLAYER or {}
HIRELING_PET_TYPES = HIRELING_PET_TYPES or {} -- type name -> NpcType
HIRELING_PET_HOMES = HIRELING_PET_HOMES or {} -- creature id -> Position

HIRELING_PET_BASKET = 23813
HIRELING_PET_MAX_PER_PLAYER = 8
-- Same 100 BPC (owner, 2026-10-04) as renaming the hireling himself, raised from 5 on
-- 2026-09-10: anyone who bought a pet will pay to name it properly.
HIRELING_PET_RENAME_COST = 100

-- Items a pet can climb. These are the ladders and rope-holes that carry you
-- UP: they have no floor-change flag on their tile, so walking onto one does
-- nothing and the climb has to be performed. Everything that goes DOWN is a
-- floor-change tile instead and needs no list -- the pet walks onto it and
-- Tile::queryDestination drops it.
--
-- (!) This is the id list from data/scripts/actions/others/teleport.lua, where
-- it is a local and cannot be reached from here. tools/test_hireling_pets.lua
-- reads both files and fails if the two ever stop agreeing.
HIRELING_PET_CLIMB_IDS = {
	1948, 1968, 5542, 20474, 20475, 31262, 34243, 48493, 48494, 50122, 50123,
}

-- Every lookType below was read from this server's own data/monsters files,
-- not from a wiki. The store card draws the ANIMAL from its looktype rather
-- than some item standing in for it -- see the hireling_pet branch in
-- modules/game_store/game_store.lua -- so there is no art id here to keep in
-- step with anything.
HIRELING_PET_SPECIES = {
	{ key = "cat", name = "Cat", lookType = 276, offer = 5140, price = 350,
	  text = "A house cat. Wanders where it likes, sleeps where it likes, and cannot leave the house or come to harm." },
	{ key = "dog", name = "Dog", lookType = 32, offer = 5141, price = 350,
	  text = "A loyal dog. Wanders the house, cannot be harmed, and answers to whatever you name it." },
	{ key = "rabbit", name = "Rabbit", lookType = 74, offer = 5142, price = 350,
	  text = "A rabbit for the house. Quiet, harmless, and it stays where you put it -- inside." },
	{ key = "penguin", name = "Penguin", lookType = 250, offer = 5143, price = 400,
	  text = "A penguin, a long way from the ice. Wanders the house and cannot come to harm." },
	{ key = "parrot", name = "Parrot", lookType = 217, offer = 5144, price = 400,
	  text = "A parrot for the house. Bright, harmless, and it never leaves the room you let it out in." },
	{ key = "panda", name = "Panda", lookType = 123, offer = 5145, price = 500,
	  text = "A panda in your own house. Slow, harmless, and impossible to ignore." },
	{ key = "flamingo", name = "Flamingo", lookType = 212, offer = 5146, price = 500,
	  text = "A flamingo for the house. Stands about elegantly and cannot come to harm." },
	{ key = "whitedeer", name = "White Deer", lookType = 400, offer = 5147, price = 600,
	  text = "A white deer, kept indoors. The rarest thing in this list, and it knows it." },
}

HIRELING_PET_BY_KEY = {}
for _, species in ipairs(HIRELING_PET_SPECIES) do
	HIRELING_PET_BY_KEY[species.key] = species
end

function GetHirelingPetSpecies(key)
	return HIRELING_PET_BY_KEY[tostring(key or "")]
end

function GetHirelingPetSpeciesByOffer(offerId)
	for _, species in ipairs(HIRELING_PET_SPECIES) do
		if species.offer == offerId then
			return species
		end
	end
	return nil
end

HirelingPets = HirelingPets or {}

local function petsEnabled()
	return configManager and configKeys and configKeys.HIRELING_SYSTEM_ENABLED and
		configManager.getBoolean(configKeys.HIRELING_SYSTEM_ENABLED)
end

local function logWarning(message)
	if logger and logger.warn then
		logger.warn(message)
	else
		print(message)
	end
end

-- (!) Same rule as hireling names: this is shown over a creature's head and
-- stored in a VARCHAR(32), so it is checked here rather than trusted from the
-- wire. Letters and single spaces, three to twenty characters.
function HirelingPets.isValidName(name)
	name = tostring(name or "")
	if #name < 3 or #name > 20 then
		return false
	end
	if name:match("^%s") or name:match("%s$") or name:match("%s%s") then
		return false
	end
	return name:match("^[%a ]+$") ~= nil
end

-- ─────────────────────────── the NPC type ───────────────────────────

local function ensurePetType(typeName, displayName, lookType)
	if HIRELING_PET_TYPES[typeName] then
		return HIRELING_PET_TYPES[typeName]
	end

	-- createHirelingPetType lives in the NPC file, which the Npc interface
	-- loads into ITS OWN Lua state. dofile pulls it into this one; the same
	-- dance data/scripts/lib/hireling.lua does for createHirelingType.
	if not createHirelingPetType then
		local ok, err = pcall(dofile, "data/npc/crystalserver/pets/hireling_pet.lua")
		if not ok then
			logWarning("[HirelingPet] Failed to load the pet NPC file: " .. tostring(err))
			return nil
		end
	end

	if not createHirelingPetType then
		logWarning("[HirelingPet] createHirelingPetType is not available.")
		return nil
	end

	local ok, npcType = pcall(createHirelingPetType, typeName, displayName, lookType)
	if not ok or not npcType then
		logWarning("[HirelingPet] Failed to register " .. typeName .. ": " .. tostring(npcType))
		return nil
	end

	HIRELING_PET_TYPES[typeName] = npcType
	return npcType
end

-- ─────────────────────────── a pet ───────────────────────────

HirelingPet = HirelingPet or {}
HirelingPet.__index = HirelingPet

function HirelingPet:new(row)
	local pet = setmetatable(row or {}, HirelingPet)
	pet.cid = pet.cid or -1
	return pet
end

function HirelingPet:getTypeName()
	return "Pet " .. tostring(self.id)
end

function HirelingPet:getSpecies()
	return GetHirelingPetSpecies(self.species)
end

function HirelingPet:getName()
	if self.name and self.name ~= "" then
		return self.name
	end
	local species = self:getSpecies()
	return species and species.name or "Pet"
end

function HirelingPet:getPosition()
	return Position(self.posx, self.posy, self.posz)
end

function HirelingPet:save()
	db.query(string.format(
		"UPDATE `player_hireling_pets` SET `name` = %s, `placed` = %d, `posx` = %d, `posy` = %d, `posz` = %d WHERE `id` = %d",
		db.escapeString(self.name or ""), self.placed and 1 or 0,
		self.posx or 0, self.posy or 0, self.posz or 0, self.id))
end

-- The house the pet is standing in must belong to its owner. Checked on every
-- placement AND on every startup, because a house changes hands while its
-- owner is offline and a pet left behind in someone else's living room is
-- exactly the sort of thing nobody would notice for a month.
local function houseAllows(ownerGuid, position)
	local tile = position and position:getTile()
	local house = tile and tile:getHouse()
	if not house then
		return false, "You may only do this inside a house."
	end
	if house:getOwnerGuid() ~= ownerGuid then
		return false, "You may only do this inside your own house."
	end
	if house:getDoorIdByPosition(position) then
		return false, "Not in the doorway."
	end
	return true
end

function HirelingPet:despawn()
	if self.cid and self.cid > 0 then
		local npc = Npc(self.cid)
		if npc then
			npc:getPosition():sendMagicEffect(CONST_ME_POFF)
			npc:remove()
		end
		HIRELING_PET_HOMES[self.cid] = nil
		-- The walker keeps its own two tables keyed by creature id. Creature
		-- ids are not reused quickly, but a server that never forgets one
		-- grows a little on every place/put-away cycle.
		if forgetHirelingPetWalker then
			forgetHirelingPetWalker(self.cid)
		end
	end
	self.cid = -1
end

function HirelingPet:spawn()
	if not petsEnabled() then
		return false
	end

	local ok = houseAllows(self.player_id, self:getPosition())
	if not ok then
		-- Put it away rather than dropping it into a house that is no longer
		-- its owner's. The owner can place it again from the window.
		self.placed = false
		self:save()
		return false
	end

	local typeName = self:getTypeName()
	local species = self:getSpecies()
	if not species then
		logWarning("[HirelingPet] pet " .. tostring(self.id) .. " has unknown species " .. tostring(self.species))
		return false
	end

	local npcType = ensurePetType(typeName, self:getName(), species.lookType)
	if not npcType then
		return false
	end
	if npcType:name() ~= self:getName() then
		npcType:name(self:getName())
	end

	local npc = Game.createNpc(typeName, self:getPosition(), false, true, CONST_ME_NONE)
	if not npc then
		return false
	end

	npc:setOutfit({ lookType = species.lookType, lookHead = 0, lookBody = 0, lookLegs = 0, lookFeet = 0, lookAddons = 0 })

	-- Recorded, though nothing walks by it: the engine's random walk is off
	-- (walkRadius 0) because it cannot work inside a house at all, and the
	-- pet is stepped from Lua instead. See the long note at the top of
	-- data/npc/crystalserver/pets/hireling_pet.lua for why.
	npc:setMasterPos(self:getPosition(), 0)
	npc:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	self.cid = npc:getId()
	HIRELING_PET_HOMES[self.cid] = self:getPosition()
	self.placed = true
	self:save()
	return true
end

-- ─────────────────────────── the collection ───────────────────────────

function HirelingPets.homeOf(cid)
	return HIRELING_PET_HOMES[cid]
end

function HirelingPets.byId(id)
	return HIRELING_PETS[tonumber(id) or -1]
end

function HirelingPets.forPlayer(guid)
	return HIRELING_PETS_BY_PLAYER[guid] or {}
end

function HirelingPets.countFor(guid)
	return #HirelingPets.forPlayer(guid)
end

local function remember(pet)
	HIRELING_PETS[pet.id] = pet
	HIRELING_PETS_BY_PLAYER[pet.player_id] = HIRELING_PETS_BY_PLAYER[pet.player_id] or {}
	table.insert(HIRELING_PETS_BY_PLAYER[pet.player_id], pet)
end

-- Called when a pet basket is used. Creates the row, registers the type and
-- places the animal in one step: the basket IS the pet until it is opened.
function HirelingPets.create(ownerGuid, speciesKey, position)
	local species = GetHirelingPetSpecies(speciesKey)
	if not species then
		return nil, "That basket is empty."
	end
	if HirelingPets.countFor(ownerGuid) >= HIRELING_PET_MAX_PER_PLAYER then
		return nil, "You already keep as many pets as one house can hold."
	end

	local ok, err = houseAllows(ownerGuid, position)
	if not ok then
		return nil, err
	end

	if not db.query(string.format(
		"INSERT INTO `player_hireling_pets` (`player_id`, `species`, `name`, `placed`, `posx`, `posy`, `posz`) VALUES (%d, %s, %s, 1, %d, %d, %d)",
		ownerGuid, db.escapeString(species.key), db.escapeString(species.name),
		position.x, position.y, position.z)) then
		return nil, "The pet could not be settled in. Please try again."
	end

	local id = db.lastInsertId()
	local pet = HirelingPet:new({
		id = id, player_id = ownerGuid, species = species.key, name = species.name,
		placed = true, posx = position.x, posy = position.y, posz = position.z,
	})

	if not pet:spawn() then
		-- Never leave a row behind for an animal that is not there: the owner
		-- would own a pet with no way to reach it.
		db.query("DELETE FROM `player_hireling_pets` WHERE `id` = " .. id)
		return nil, "The pet could not be settled in. Please try again."
	end

	remember(pet)
	return pet
end

function HirelingPets.place(player, pet)
	if not player or pet.player_id ~= player:getGuid() then
		return false, "That is not your pet."
	end
	if pet.cid and pet.cid > 0 then
		return false, pet:getName() .. " is already out."
	end

	local position = player:getPosition()
	local ok, err = houseAllows(player:getGuid(), position)
	if not ok then
		return false, err
	end

	pet.posx, pet.posy, pet.posz = position.x, position.y, position.z
	if not pet:spawn() then
		return false, "There is no room for " .. pet:getName() .. " here."
	end
	return true
end

function HirelingPets.putAway(player, pet)
	if not player or pet.player_id ~= player:getGuid() then
		return false, "That is not your pet."
	end
	if not pet.cid or pet.cid <= 0 then
		return false, pet:getName() .. " is already put away."
	end
	pet:despawn()
	pet.placed = false
	pet:save()
	return true
end

function HirelingPets.rename(player, pet, name)
	if not player or pet.player_id ~= player:getGuid() then
		return false, "That is not your pet."
	end
	if not HirelingPets.isValidName(name) then
		return false, "Three to twenty letters, single spaces between words."
	end
	if name == pet.name then
		return false, "That is already its name. No coins were spent."
	end

	-- Coins go through the LEDGER, never through a bare balance write: the
	-- charge and the row update commit together or not at all. The kind is
	-- the hireling one on purpose -- this is the same product from the
	-- account's point of view, and Coins.KINDS is a closed list whose entries
	-- the admin console charts. `ref.type` is what tells the two apart.
	local ok = Coins.move(player:getAccountId(), -HIRELING_PET_RENAME_COST, "spend.hireling_name",
		{ type = "hireling_pet", id = pet.id }, { oldName = pet.name, newName = name },
		player:getGuid(), function()
			if not db.query("UPDATE `player_hireling_pets` SET `name` = " .. db.escapeString(name) ..
				" WHERE `id` = " .. pet.id .. " AND `player_id` = " .. player:getGuid()) or db.affectedRows() ~= 1 then
				error("Pet name update failed")
			end
		end)
	if not ok then
		return false, string.format(
			"Renaming costs %d BPC. The payment could not be completed; no name change was made.",
			HIRELING_PET_RENAME_COST)
	end

	pet.name = name

	-- The creature copies its TYPE's name, so the type is what gets renamed --
	-- and a standing pet has to be replaced to pick the new one up. Same rule
	-- as a hireling rename, and the reason a type is per pet rather than per
	-- species.
	local npcType = HIRELING_PET_TYPES[pet:getTypeName()]
	if npcType then
		npcType:name(name)
	end
	if pet.cid and pet.cid > 0 then
		local position = pet:getPosition()
		pet:despawn()
		pet.posx, pet.posy, pet.posz = position.x, position.y, position.z
		pet:spawn()
	end
	return true
end

function HirelingPets.init()
	if not petsEnabled() then
		return true
	end
	if db.tableExists and not db.tableExists("player_hireling_pets") then
		logWarning("[HirelingPet] player_hireling_pets table is missing.")
		return false
	end

	HIRELING_PETS = {}
	HIRELING_PETS_BY_PLAYER = {}
	HIRELING_PET_HOMES = {}

	local rows = db.storeQuery("SELECT * FROM `player_hireling_pets`")
	if rows then
		repeat
			local pet = HirelingPet:new({
				id = result.getNumber(rows, "id"),
				player_id = result.getNumber(rows, "player_id"),
				species = result.getString(rows, "species"),
				name = result.getString(rows, "name"),
				placed = result.getNumber(rows, "placed") == 1,
				posx = result.getNumber(rows, "posx"),
				posy = result.getNumber(rows, "posy"),
				posz = result.getNumber(rows, "posz"),
			})
			remember(pet)
		until not result.next(rows)
		result.free(rows)
	end

	-- (!) A type is registered for EVERY pet, not only the ones standing in a
	-- house. Placing a pet again goes through the window's packet handler,
	-- which runs in the Events interface where Game.createNpcType is refused
	-- -- so a pet that was put away before a restart would have no type to
	-- come back as. This startup pass is the only chance to build it.
	local species
	for _, pet in pairs(HIRELING_PETS) do
		species = pet:getSpecies()
		if species then
			ensurePetType(pet:getTypeName(), pet:getName(), species.lookType)
		else
			logWarning("[HirelingPet] pet " .. tostring(pet.id) ..
				" has unknown species " .. tostring(pet.species))
		end
	end

	for _, pet in pairs(HIRELING_PETS) do
		if pet.placed then
			pet:spawn()
		end
	end
	return true
end
