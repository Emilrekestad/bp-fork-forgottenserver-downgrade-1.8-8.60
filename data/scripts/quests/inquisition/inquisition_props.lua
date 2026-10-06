-- The Inquisition, missions 2 and 3 (see npc/scripts/Henricus.lua for the story).
--
-- Mission 2: the buried coffin at 32779,31979,9 wakes The Count for a recruit who
--   is on the mission and holds a "try" (Storage.TheInquisition.CountTry). Waking him
--   spends the try; Henricus hands out another one when he is asked about the Count.
-- Mission 3: on Eclipse, the holy water goes onto the cauldron (32657,31928,1). That
--   wakes Ungreez at 32656,31934,1. Everyone who helped kill him may open the chest at
--   32649,31932,1 and take the witches' grimoire.
-- Keys are written out here (not read from the Storage lib) so that /reload scripts is enough.
local S = {
	Questline = 12160, Mission01 = 12161, Mission02 = 12162, Mission03 = 12163, Mission04 = 12164,
	EnterTeleport = 12176, CountTry = 12179, UngreezKilled = 12180,
	SealUshuriel = 12190, SealZugurosh = 12191, SealMadareth = 12192, SealVats = 12193,
	SealAnnihilon = 12194, SealHellgorak = 12195, LatrivanKilled = 12196, GolgordanKilled = 12197,
	RewardAccess = 12198, CrystalCaves = 12199, BloodHalls = 12200,
}

local COFFIN = Position(32779, 31979, 9)
local COUNT_SPAWN = Position(32779, 31981, 9)
local COUNT_STAY_MS = 20 * 60 * 1000

local CAULDRON = Position(32657, 31928, 1)
local UNGREEZ_SPAWN = Position(32656, 31934, 1)
local GRIMOIRE_CHEST = Position(32649, 31932, 1)
local HOLY_WATER = 133
local GRIMOIRE = 7874

local awake = {} -- [boss name] = creature id

local function bossAlive(name)
	local id = awake[name]
	if id and Monster(id) then
		return true
	end
	awake[name] = nil
	return false
end

local function wake(name, position, stayMs)
	local monster = Game.createMonster(name, position, true)
	if not monster then
		return nil
	end
	awake[name] = monster:getId()
	position:sendMagicEffect(CONST_ME_MORTAREA)
	if stayMs then
		local id = monster:getId()
		addEvent(function()
			local boss = Monster(id)
			if boss then
				boss:getPosition():sendMagicEffect(CONST_ME_POFF)
				boss:remove()
			end
		end, stayMs)
	end
	return monster
end

-- Mission 2: the coffin
local coffin = Action()

function coffin.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if player:getStorageValue(S.Mission02) ~= 2 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The coffin is sealed. Nothing happens.")
		return true
	end
	if bossAlive("The Count") then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The coffin is open and The Count is already awake.")
		return true
	end
	if player:getStorageValue(S.CountTry) ~= 1 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The coffin stays shut. Talk to Henricus about the Count.")
		return true
	end
	if not wake("The Count", COUNT_SPAWN, COUNT_STAY_MS) then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The coffin shakes, but there is no room for him to rise.")
		return true
	end
	player:setStorageValue(S.CountTry, 0)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The coffin lid slides away. The Count rises!")
	return true
end

coffin:position(COFFIN)
coffin:register()

-- Mission 3: holy water on the cauldron
local holyWater = Action()

function holyWater.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if toPosition.x ~= CAULDRON.x or toPosition.y ~= CAULDRON.y or toPosition.z ~= CAULDRON.z then
		return false
	end
	if player:getStorageValue(S.Mission03) ~= 2 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Nothing happens.")
		return true
	end
	item:remove(1)
	player:setStorageValue(S.Mission03, 3)
	CAULDRON:sendMagicEffect(CONST_ME_HOLYAREA)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The holy water destroys the witches' brew. The ground shakes - something has woken.")
	if not bossAlive("Ungreez") then
		wake("Ungreez", UNGREEZ_SPAWN, nil)
	end
	return true
end

holyWater:id(HOLY_WATER)
holyWater:register()

-- Mission 3: Ungreez dies; everyone who hurt him and holds the mission may take the book
local ungreezDeath = CreatureEvent("InquisitionUngreezDeath")

function ungreezDeath.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	awake["Ungreez"] = nil
	for cid in pairs(creature:getDamageMap()) do
		local player = Player(cid)
		if player and player:getStorageValue(S.Mission03) == 3 then
			player:setStorageValue(S.UngreezKilled, 1)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Ungreez is dead. The way to the witches' grimoire is open.")
		end
	end
	return true
end

ungreezDeath:type("death")
ungreezDeath:register()

-- Mission 3: the grimoire chest
local chest = Action()

function chest.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local stage = player:getStorageValue(S.Mission03)
	if stage ~= 3 and stage ~= 4 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The chest is locked by a witch's seal.")
		return true
	end
	if player:getStorageValue(S.UngreezKilled) ~= 1 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The chest is sealed. Ungreez must die first.")
		return true
	end
	if player:getItemCount(GRIMOIRE) > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The chest is empty.")
		return true
	end
	local book = player:addItem(GRIMOIRE, 1)
	if not book then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have no room to carry the witches' grimoire.")
		return true
	end
	player:setStorageValue(S.Mission03, 4)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have found the witches' grimoire. Take it to Henricus.")
	return true
end

chest:position(GRIMOIRE_CHEST)
chest:register()
