-- The Inquisition, mission 4: Face the Inquisition (see npc/scripts/Henricus.lua).
--
-- * Every boss of the realms carries the event "InquisitionBossDeath" (monster files in
--   monsters/quests/the_inquisition). Everyone who damaged the boss and is on the mission
--   gets that seal marked broken (storage 2) in the quest log. Latrivan and Golgordan
--   share one seal: both must die.
-- * Hellgorak is also the last seal. Leaving through the final teleport (33147,31685,12) moves Mission 4 on to "report to Henricus".
-- * Hellgorak, Madareth, Golgordan, Latrivan and Annihilon are kept alive by this file (Lua, not the spawn file),
--   back 30 minutes after he dies.
-- * The teleport at 33192,31691,14 -> 33168,31684,15 only takes people on the mission.
-- * The teleport at 33147,31685,12 (the way out) leads on once Hellgorak is dead, else to the main room.
-- * The two doors at 33190,31684,14 and 33195,31684,14 are level 70+ doors.
-- Keys are written out here (not read from the Storage lib) so that /reload scripts is enough.
local S = {
	Questline = 12160, Mission01 = 12161, Mission02 = 12162, Mission03 = 12163, Mission04 = 12164,
	EnterTeleport = 12176, CountTry = 12179, UngreezKilled = 12180,
	SealUshuriel = 12190, SealZugurosh = 12191, SealMadareth = 12192, SealVats = 12193,
	SealAnnihilon = 12194, SealHellgorak = 12195, LatrivanKilled = 12196, GolgordanKilled = 12197,
	RewardAccess = 12198, CrystalCaves = 12199, BloodHalls = 12200, Vats = 12201, Arcanum = 12202, Hive = 12203,
}

-- the hub every failed or finished route returns to
local USHURIEL_ROOM = Position(33163, 31708, 14)

-- seal storage by boss name
local SEAL_OF = {
	["Ushuriel"] = S.SealUshuriel,
	["Zugurosh"] = S.SealZugurosh,
	["Madareth"] = S.SealMadareth,
	["Annihilon"] = S.SealAnnihilon,
	["Hellgorak"] = S.SealHellgorak,
}
local VATS_FLAG = { ["Latrivan"] = S.LatrivanKilled, ["Golgordan"] = S.GolgordanKilled }

local function onMission(player)
	return player:getStorageValue(S.Mission04) >= 1
end

local function breakSeal(player, key, message)
	if player:getStorageValue(key) >= 2 then
		return
	end
	player:setStorageValue(key, 2)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, message)
end

-- Hellgorak falls: everyone in the Hive is told to run for the portal, and the room burns for a minute
local PORTAL = Position(33147, 31685, 12)
local ALARM_SECONDS = 60
local ALARM_TEXT = "HELLGORAK IS DEAD! THE HIVE IS COLLAPSING! RUN TO THE PORTAL AND LEAVE NOW!"

local function hiveAlarm(centre, secondsLeft)
	if secondsLeft <= 0 then
		return
	end
	for _ = 1, 4 do
		local spot = Position(centre.x + math.random(-7, 7), centre.y + math.random(-7, 7), centre.z)
		spot:sendMagicEffect(({ CONST_ME_FIREAREA, CONST_ME_EXPLOSIONHIT, CONST_ME_GROUNDSHAKER, CONST_ME_MORTAREA })[math.random(4)])
	end
	PORTAL:sendMagicEffect(CONST_ME_TELEPORT)
	PORTAL:sendMagicEffect(CONST_ME_ENERGYAREA)
	if secondsLeft % 5 == 0 then
		Game.sendAnimatedText("RUN!", PORTAL, TEXTCOLOR_ORANGE)
		for _, spectator in ipairs(Game.getSpectators(centre, false, true, 30, 30, 30, 30)) do
			if spectator:getPosition().z == centre.z then
				spectator:sendTextMessage(MESSAGE_STATUS_WARNING, ALARM_TEXT)
			end
		end
	end
	addEvent(hiveAlarm, 1000, centre, secondsLeft - 1)
end

local death = CreatureEvent("InquisitionBossDeath")

function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local name = creature:getName()
	if name == "Hellgorak" then
		hiveAlarm(creature:getPosition(), ALARM_SECONDS)
	end
	local spawned = Inquisition and Inquisition.spawns and Inquisition.spawns[name]
	if spawned then
		spawned.diedAt = os.time()
		spawned.id = nil
	end
	for cid in pairs(creature:getDamageMap()) do
		local player = Player(cid)
		if player and onMission(player) then
			if SEAL_OF[name] then
				breakSeal(player, SEAL_OF[name], "The seal of " .. name .. " is broken.")
				if name == "Hellgorak" then
					player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Hellgorak is dead. The way out is open.")
				end
			elseif VATS_FLAG[name] then
				player:setStorageValue(VATS_FLAG[name], 1)
				if player:getStorageValue(S.LatrivanKilled) == 1 and player:getStorageValue(S.GolgordanKilled) == 1 then
					breakSeal(player, S.SealVats, "The seal of the Vats is broken.")
				else
					player:sendTextMessage(MESSAGE_EVENT_ADVANCE, name .. " is dead. The seal of the Vats holds until his partner dies too.")
				end
			end
		end
	end
	return true
end

death:type("death")
death:register()

-- Bosses this file keeps alive: one of each at a time, back 30 minutes after it dies.
-- (Ushuriel, Zugurosh and the others are not here yet.)
Inquisition = Inquisition or {}
Inquisition.spawns = Inquisition.spawns or {}

local RESPAWN_SECONDS = 30 * 60
local KEPT_BOSSES = {
	{ name = "Hellgorak", pos = Position(33155, 31689, 12) },
	{ name = "Madareth", pos = Position(33360, 31610, 11) },
	{ name = "Golgordan", pos = Position(33267, 31633, 13) },
	{ name = "Latrivan", pos = Position(33328, 31630, 13) },
	{ name = "Annihilon", pos = Position(33134, 31666, 11) },
}

-- Spawns every kept boss that is not out. force = true ignores the 30-minute wait after a
-- death (the /inqbosses command). Returns the names it spawned.
local function spawnKept(force)
	local spawned = {}
	for _, boss in ipairs(KEPT_BOSSES) do
		local state = Inquisition.spawns[boss.name]
		if not state then
			state = {}
			Inquisition.spawns[boss.name] = state
		end
		if not (state.id and Monster(state.id)) then
			state.id = nil
			-- one that a game master spawned by hand counts as the boss too
			for _, spectator in ipairs(Game.getSpectators(boss.pos, false, false, 15, 15, 15, 15)) do
				local other = spectator:getMonster()
				if other and other:getName() == boss.name and other:getPosition().z == boss.pos.z then
					state.id = other:getId()
					state.diedAt = nil
					break
				end
			end
		end
		if not (state.id and Monster(state.id)) then
			state.id = nil
			if force or not state.diedAt or os.time() - state.diedAt >= RESPAWN_SECONDS then
				local monster = Game.createMonster(boss.name, boss.pos, true, true)
				if monster then
					state.id = monster:getId()
					state.diedAt = nil
					spawned[#spawned + 1] = boss.name
				end
			end
		end
	end
	return spawned
end

local tick = GlobalEvent("InquisitionBosses")

function tick.onThink(interval)
	spawnKept(false)
	return true
end

tick:interval(60 * 1000)
tick:register()

-- Teleports. The map teleport at 33147,31685,12 carries a destination, so it is emptied here
-- (a teleport with no destination does nothing) and this script does the moving.
local IN_FROM = Position(33192, 31691, 14)
local IN_TO = Position(33168, 31684, 15)
local OUT_FROM = Position(33147, 31685, 12)
local OUT_TO = Position(33146, 31657, 13)

local function neutralise()
	local tile = Tile(OUT_FROM)
	local item = tile and tile:getItemById(1949)
	local teleport = item and Teleport(item.uid)
	if teleport then
		teleport:setDestination(Position(0, 0, 0))
	end
end

local entry = MoveEvent()

function entry.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	if not onMission(player) and not player:getGroup():getAccess() then
		player:teleportTo(fromPosition, true)
		position:sendMagicEffect(CONST_ME_POFF)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Only those sent by Henricus to face the inquisition may pass.")
		return true
	end
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(IN_TO)
	IN_TO:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

entry:type("stepin")
entry:position(IN_FROM)
entry:register()

local exit = MoveEvent()

function exit.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	local free = player:getStorageValue(S.SealHellgorak) >= 2 or player:getStorageValue(S.Mission04) >= 2
	if not free and not player:getGroup():getAccess() then
		position:sendMagicEffect(CONST_ME_POFF)
		player:teleportTo(USHURIEL_ROOM)
		USHURIEL_ROOM:sendMagicEffect(CONST_ME_TELEPORT)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Hellgorak still lives. You are sent back to the main room.")
		return true
	end
	-- walking out through this teleport is what completes the Inquisition
	if player:getStorageValue(S.Mission04) == 1 and player:getStorageValue(S.SealHellgorak) >= 2 then
		player:setStorageValue(S.Mission04, 3)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have faced the inquisition! Mission complete. Report back to Henricus.")
	end
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(OUT_TO)
	OUT_TO:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

exit:type("stepin")
exit:position(OUT_FROM)
exit:register()

-- Level doors (1000 + level)
local LEVEL_DOORS = { Position(33190, 31684, 14), Position(33195, 31684, 14) }
local LEVEL_DOOR_AID = 1070

local function tagDoors()
	for _, position in ipairs(LEVEL_DOORS) do
		local tile = Tile(position)
		local door = tile and tile:getItemById(5102)
		if door and door:getActionId() ~= LEVEL_DOOR_AID then
			door:setActionId(LEVEL_DOOR_AID)
		end
	end
end

-- on a reload the map is already there; at boot the startup event below does it
neutralise()
tagDoors()

local startup = GlobalEvent("InquisitionStartup")

function startup.onStartup()
	neutralise()
	tagDoors()
	return true
end

startup:register()

-- The Dark Path and the way into the Crystal Caves
--   33230,31633,12 -> 33159,31728,11   always
--   33157,31728,11 -> Crystal Caves 33069,31782,13 if Ushuriel is dead for you, else 33163,31708,14
--     (the first time you arrive in the Crystal Caves they are marked unlocked in the quest log)
--   33169,31705,14 -> Crystal Caves 33069,31782,13, the shortcut from Ushuriel's main room,
--     only once the Crystal Caves are unlocked
local CAVES = Position(33069, 31782, 13)

local function route(from, decide)
	local event = MoveEvent()

	function event.onStepIn(creature, item, position, fromPosition)
		local player = creature:getPlayer()
		if not player then
			return true
		end
		local destination, refusal = decide(player)
		if not destination then
			player:teleportTo(fromPosition, true)
			position:sendMagicEffect(CONST_ME_POFF)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, refusal)
			return true
		end
		position:sendMagicEffect(CONST_ME_TELEPORT)
		player:teleportTo(destination)
		destination:sendMagicEffect(CONST_ME_TELEPORT)
		return true
	end

	event:type("stepin")
	event:position(from)
	event:register()
end

route(Position(33230, 31633, 12), function(player)
	return Position(33159, 31728, 11)
end)

route(Position(33157, 31728, 11), function(player)
	if player:getStorageValue(S.SealUshuriel) < 2 then
		return USHURIEL_ROOM
	end
	if player:getStorageValue(S.CrystalCaves) < 1 then
		player:setStorageValue(S.CrystalCaves, 1)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have reached the Crystal Caves. The shortcut in Ushuriel's main room now leads here.")
	end
	return CAVES
end)

route(Position(33169, 31705, 14), function(player)
	if player:getStorageValue(S.CrystalCaves) < 1 then
		return nil, "The shortcut is closed. Defeat Ushuriel and enter the Crystal Caves first."
	end
	return CAVES
end)

-- The Crystal Caves, Zugurosh and the way into the Blood Halls
--   33065,31771,10 -> 33169,31755,13 and back: 33168,31755,13 -> 33065,31773,10
--   33260,31750,13 -> Zugurosh's room 33125,31692,11
--   33123,31692,11 -> Blood Halls 33370,31612,14 if Zugurosh is dead for you (that unlocks the
--     Blood Halls in the quest log), else 33163,31708,14
--   33175,31709,14 -> Blood Halls: the shortcut from the main room, once unlocked
local BLOOD_HALLS = Position(33370, 31612, 14)

route(Position(33065, 31771, 10), function(player)
	return Position(33169, 31755, 13)
end)

route(Position(33168, 31755, 13), function(player)
	return Position(33065, 31773, 10)
end)

route(Position(33260, 31750, 13), function(player)
	return Position(33125, 31692, 11)
end)

route(Position(33123, 31692, 11), function(player)
	if player:getStorageValue(S.SealZugurosh) < 2 then
		return USHURIEL_ROOM
	end
	if player:getStorageValue(S.BloodHalls) < 1 then
		player:setStorageValue(S.BloodHalls, 1)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have reached the Blood Halls. The shortcut in the main room now leads here.")
	end
	return BLOOD_HALLS
end)

route(Position(33175, 31709, 14), function(player)
	if player:getStorageValue(S.BloodHalls) < 1 then
		return nil, "The shortcut is closed. Defeat Zugurosh and enter the Blood Halls first."
	end
	return BLOOD_HALLS
end)

-- The way back out of the Crystal Caves: 33068,31782,13 -> the main room 33163,31708,14
route(Position(33068, 31782, 13), function(player)
	return USHURIEL_ROOM
end)

-- The way back out of the Blood Halls: 33372,31614,14 -> the main room 33163,31708,14
route(Position(33372, 31614, 14), function(player)
	return USHURIEL_ROOM
end)

-- Blood Halls: 33357,31588,12 -> 33356,31590,11
route(Position(33357, 31588, 12), function(player)
	return Position(33356, 31590, 11)
end)

-- Madareth's room and the way into the Vats
--   33365,31613,11 -> Vats 33154,31782,12 if Madareth is dead for you (that unlocks the Vats
--     in the quest log), else the main room 33163,31708,14
--   33175,31713,14 -> Vats: the shortcut from the main room, once unlocked
local VATS = Position(33154, 31782, 12)

route(Position(33365, 31613, 11), function(player)
	if player:getStorageValue(S.SealMadareth) < 2 then
		return USHURIEL_ROOM
	end
	if player:getStorageValue(S.Vats) < 1 then
		player:setStorageValue(S.Vats, 1)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have reached the Vats. The shortcut in the main room now leads here.")
	end
	return VATS
end)

route(Position(33175, 31713, 14), function(player)
	if player:getStorageValue(S.Vats) < 1 then
		return nil, "The shortcut is closed. Defeat Madareth and enter the Vats first."
	end
	return VATS
end)

-- The way back out of the Vats: 33152,31782,12 -> the main room 33163,31708,14
route(Position(33152, 31782, 12), function(player)
	return USHURIEL_ROOM
end)

-- The Vats: 33234,31758,12 -> 33252,31632,13
route(Position(33234, 31758, 12), function(player)
	return Position(33252, 31632, 13)
end)

-- The Vats: 33249,31632,13 -> 33232,31758,12 (back)
route(Position(33249, 31632, 13), function(player)
	return Position(33232, 31758, 12)
end)

local ARCANUM = Position(33038, 31754, 15)

-- The Vats' boss rooms: 33339,31632,13 -> 33038,31754,15 if both Latrivan and Golgordan are dead for you, else the main room
route(Position(33339, 31632, 13), function(player)
	if player:getStorageValue(S.SealVats) < 2 then
		return USHURIEL_ROOM
	end
	if player:getStorageValue(S.Arcanum) < 1 then
		player:setStorageValue(S.Arcanum, 1)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have reached the Arcanum. The shortcut in the main room now leads here.")
	end
	return ARCANUM
end)

-- the shortcut from the main room, 33170,31719,14 -> the Arcanum, once unlocked
route(Position(33170, 31719, 14), function(player)
	if player:getStorageValue(S.SealVats) < 2 and player:getStorageValue(S.Arcanum) < 1 then
		return nil, "The shortcut is closed. Defeat both Latrivan and Golgordan first."
	end
	if player:getStorageValue(S.Arcanum) < 1 then
		player:setStorageValue(S.Arcanum, 1)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The Arcanum is unlocked.")
	end
	return ARCANUM
end)

-- GM command: /inqbosses puts every kept boss that is dead (or not out) back at its spot
local command = TalkAction("/inqbosses")

function command.onSay(player, words, param)
	local spawned = spawnKept(true)
	if #spawned == 0 then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Every Inquisition boss is already out.")
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Spawned: " .. table.concat(spawned, ", "))
	end
	return false
end

command:separator(" ")
command:accountType(6)
command:register()

-- The way back out of the Arcanum: 33038,31752,15 -> the main room 33163,31708,14
route(Position(33038, 31752, 15), function(player)
	return USHURIEL_ROOM
end)

-- 33187,31759,15 -> 33094,31575,11 and back: 33093,31574,11 -> 33184,31759,15
route(Position(33187, 31759, 15), function(player)
	return Position(33094, 31575, 11)
end)

route(Position(33093, 31574, 11), function(player)
	return Position(33184, 31759, 15)
end)

-- Annihilon's room and the way into the Hive
--   33137,31671,11 -> Hive 33199,31685,12 if Annihilon is dead for you (that unlocks the Hive
--     in the quest log), else the main room 33163,31708,14
--   33199,31687,12 -> the main room (the way out of the Hive)
--   33165,31719,14 -> Hive: the shortcut from the main room, once unlocked
local HIVE = Position(33199, 31685, 12)

route(Position(33137, 31671, 11), function(player)
	if player:getStorageValue(S.SealAnnihilon) < 2 then
		return USHURIEL_ROOM
	end
	if player:getStorageValue(S.Hive) < 1 then
		player:setStorageValue(S.Hive, 1)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have reached the Hive. The shortcut in the main room now leads here.")
	end
	return HIVE
end)

route(Position(33199, 31687, 12), function(player)
	return USHURIEL_ROOM
end)

route(Position(33165, 31719, 14), function(player)
	if player:getStorageValue(S.Hive) < 1 then
		return nil, "The shortcut is closed. Defeat Annihilon and enter the Hive first."
	end
	return HIVE
end)

-- The Ward of Hellgorak: 33225,31607,9 -> 33110,31684,12 and back: 33110,31681,12 -> the main room 33163,31708,14
route(Position(33225, 31607, 9), function(player)
	return Position(33110, 31684, 12)
end)

route(Position(33110, 31681, 12), function(player)
	return USHURIEL_ROOM
end)
