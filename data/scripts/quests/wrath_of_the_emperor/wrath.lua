-- Wrath of the Emperor, rebuilt (2026-10-04). The story is told by Zlak in Lizard City
-- (npc/scripts/Zlak.lua); this file holds everything the map does.
--
--   Mission 1  Zalamon (npc/scripts/Zalamon.lua) shushes you and sets four Lizard Chosen on you
--   Mission 2  the chest at 33264,31130,7 holds the scriptures
--   Mission 3  50 Draken Spellweavers / Warmasters, counted for everyone who tags them
--   Mission 4  Fury, Wrath, Scorn and Spite of the Emperor in the Draken Castle basement, woken by
--              using the replica of the sceptre on the pillar in their room; the replica also
--              "verifies" each kill on its corpse
--   Mission 5  tower teleport -> the Sleeping Dragon -> the gate -> staging box + lever -> the
--              four-stage fight against Zalamon -> sceptre on the body -> Awareness of the Emperor
--   Mission 6  the reward room: one chest of three, and the wardrobe with the Wayfarer outfit
--
-- Keys are written out here (not read from the Storage lib) so that /reload scripts is enough.
local K = {
	Questline = 13001, M1 = 13002, M2 = 13003, M3 = 13004, M4 = 13005, M5 = 13006,
	DrakenKills = 13007, Fury = 13008, Wrath = 13009, Scorn = 13010, Spite = 13011,
	RewardChest = 13012, Outfit = 13013, M6 = 13014,
}

local REPLICA = 11362 -- replica of the sceptre
local EMPEROR_CORPSE = 11361 -- the four bosses share this corpse
local ZALAMON_CORPSE = 11429
local DRAKENS_NEEDED = 50

local function say(player, text)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
end

local function samePosition(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z
end

-- ---------------------------------------------------------------------------------------
-- Mission 2: the scriptures chest
-- ---------------------------------------------------------------------------------------
local scriptures = Action()

function scriptures.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local state = player:getStorageValue(K.M2)
	if state == 1 then
		player:setStorageValue(K.M2, 2)
		player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
		say(player, "You open the chest and find the old scriptures that Zlak was so badly needing. Take them back to Zlak in Lizard City.")
	elseif state >= 2 then
		say(player, "The chest is empty. You already have the scriptures.")
	else
		say(player, "The chest is locked tight. Whatever is inside is none of your business, yet.")
	end
	return true
end

scriptures:position(Position(33264, 31130, 7))
scriptures:register()

-- ---------------------------------------------------------------------------------------
-- Mission 3: the Draken counter. Everyone who damaged a Spellweaver or Warmaster gets the kill.
-- ---------------------------------------------------------------------------------------
local drakenDeath = CreatureEvent("WrathDrakenKill")

function drakenDeath.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	for cid in pairs(creature:getDamageMap()) do
		local player = Player(cid)
		if player and player:getStorageValue(K.M3) == 1 then
			local kills = math.max(player:getStorageValue(K.DrakenKills), 0) + 1
			player:setStorageValue(K.DrakenKills, kills)
			if kills >= DRAKENS_NEEDED then
				player:setStorageValue(K.M3, 2)
				say(player, string.format("Draken counter: %d / %d. That is enough! Report back to Zlak in Lizard City.", DRAKENS_NEEDED, DRAKENS_NEEDED))
			else
				say(player, string.format("Wrath of the Emperor: %s killed. Draken counter: %d / %d.", creature:getName(), kills, DRAKENS_NEEDED))
			end
		end
	end
	return true
end

drakenDeath:type("death")
drakenDeath:register()

-- ---------------------------------------------------------------------------------------
-- Mission 4: the four bosses in the basement. They leave a corpse stamped with their name;
-- the replica of the sceptre, used on that corpse, verifies the kill.
-- ---------------------------------------------------------------------------------------
local BOSSES = {
	["Fury of the Emperor"] = { flag = K.Fury, short = "Fury" },
	["Wrath of the Emperor"] = { flag = K.Wrath, short = "Wrath" },
	["Scorn of the Emperor"] = { flag = K.Scorn, short = "Scorn" },
	["Spite of the Emperor"] = { flag = K.Spite, short = "Spite" },
}
local MARK = "The remains of "

local bossDeath = CreatureEvent("WrathBossDeath")

function bossDeath.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local name = creature:getName()
	if corpse and BOSSES[name] then
		corpse:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, MARK .. name .. ". A replica of the sceptre could verify this kill.")
	end
	local state = Wrath and Wrath.bossState and Wrath.bossState[name]
	if state then
		state.diedAt = os.time()
		state.id = nil
	end
	return true
end

bossDeath:type("death")
bossDeath:register()

-- ---------------------------------------------------------------------------------------
-- The sceptre: verifies a boss kill (mission 4) or ends Zalamon (mission 5)
-- ---------------------------------------------------------------------------------------
Wrath = Wrath or {}
Wrath.bossState = Wrath.bossState or {}
Wrath.arena = Wrath.arena or { generation = 0 }

local ARENA_ENTRY = Position(33365, 31412, 10)
local ARENA_EXIT = Position(33359, 31397, 9)
local ARENA = { x1 = 33356, x2 = 33375, y1 = 31403, y2 = 31421, z = 10 }
local AWARENESS_ROOM = Position(33065, 31153, 15)

local function inArena(position)
	return position.z == ARENA.z and position.x >= ARENA.x1 and position.x <= ARENA.x2
		and position.y >= ARENA.y1 and position.y <= ARENA.y2
end

-- The four bosses of the basement are not on a timer: they wake when someone uses the replica of
-- the sceptre on the pillar in the middle of their room. Each boss can be woken once every 10
-- minutes (and not while it is still alive), so nobody can spam them.
local PILLARS = {
	{ name = "Fury of the Emperor", pos = Position(33049, 31089, 15) },
	{ name = "Wrath of the Emperor", pos = Position(33095, 31091, 15) },
	{ name = "Scorn of the Emperor", pos = Position(33096, 31114, 15) },
	{ name = "Spite of the Emperor", pos = Position(33049, 31115, 15) },
}
local BOSS_COOLDOWN_SECONDS = 10 * 60

local function pillarAt(position)
	for _, pillar in ipairs(PILLARS) do
		if samePosition(pillar.pos, position) then
			return pillar
		end
	end
	return nil
end

-- returns true when the boss was woken, or false and a reason
local function wakeBoss(pillar, force)
	local state = Wrath.bossState[pillar.name]
	if not state then
		state = {}
		Wrath.bossState[pillar.name] = state
	end
	if state.id and Monster(state.id) then
		return false, pillar.name .. " is already awake."
	end
	state.id = nil
	if not force and state.wokeAt and os.time() - state.wokeAt < BOSS_COOLDOWN_SECONDS then
		local minutes = math.ceil((BOSS_COOLDOWN_SECONDS - (os.time() - state.wokeAt)) / 60)
		return false, string.format("The pillar is still cooling down. %s can be woken again in about %d minute%s.", pillar.name, minutes, minutes == 1 and "" or "s")
	end
	local monster = Game.createMonster(pillar.name, pillar.pos, true, true)
	if not monster then
		return false, "The pillar flickers, but there is no room for " .. pillar.name .. " to appear."
	end
	state.id = monster:getId()
	-- a GM wake (/wrathbosses) never starts the player cooldown
	state.wokeAt = force and nil or os.time()
	pillar.pos:sendMagicEffect(CONST_ME_MORTAREA)
	monster:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

local sceptre = Action()

function sceptre.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if not target or not target:isItem() then
		say(player, "Use the replica of the sceptre on the corpse of a fallen boss.")
		return true
	end

	-- a pillar in the middle of one of the four boss rooms
	local pillar = pillarAt(target:getPosition())
	if pillar then
		if player:getStorageValue(K.M4) == -1 and not player:getGroup():getAccess() then
			say(player, "The pillar does not answer. Zlak has not sent you to the basement.")
			return true
		end
		local woke, reason = wakeBoss(pillar, false)
		if woke then
			say(player, "You hold the replica of the sceptre against the pillar. The stone cracks and " .. pillar.name .. " rises!")
		else
			say(player, reason)
		end
		return true
	end

	-- Zalamon's body
	if target.itemid == ZALAMON_CORPSE then
		if player:getStorageValue(K.M5) ~= 2 or not inArena(player:getPosition()) then
			say(player, "The sceptre stays dull. This body has nothing to say to you.")
			return true
		end
		player:setStorageValue(K.M5, 3)
		player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
		say(player, "You hold the sceptre over Zalamon's body. A green light swallows you, and the world falls away...")
		player:teleportTo(AWARENESS_ROOM)
		AWARENESS_ROOM:sendMagicEffect(CONST_ME_TELEPORT)
		return true
	end

	-- one of the four bosses
	if target.itemid == EMPEROR_CORPSE then
		local text = target:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION)
		local bossName
		if type(text) == "string" then
			for name in pairs(BOSSES) do
				if text:find(name, 1, true) then
					bossName = name
					break
				end
			end
		end
		if not bossName then
			say(player, "The sceptre stays dull. This is not the body of one of the four.")
			return true
		end
		if player:getStorageValue(K.M4) ~= 1 then
			say(player, "The sceptre stays dull. You are not on Zlak's mission.")
			return true
		end
		local boss = BOSSES[bossName]
		if player:getStorageValue(boss.flag) >= 1 then
			say(player, "You have already verified the death of " .. bossName .. ".")
			return true
		end
		player:setStorageValue(boss.flag, 1)
		player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
		target:getPosition():sendMagicEffect(CONST_ME_MORTAREA)
		local done = 0
		for _, entry in pairs(BOSSES) do
			if player:getStorageValue(entry.flag) >= 1 then
				done = done + 1
			end
		end
		if done >= 4 then
			player:setStorageValue(K.M4, 2)
			say(player, "The sceptre glows. " .. bossName .. " is verified dead. That is all four! Leave the basement and report to Zlak in Lizard City.")
		else
			say(player, string.format("The sceptre glows. The death of %s is verified. (%d / 4)", bossName, done))
		end
		return true
	end

	say(player, "The sceptre stays dull.")
	return true
end

sceptre:id(REPLICA)
sceptre:register()


-- ---------------------------------------------------------------------------------------
-- Mission 5: the tower teleport, the gate, the staging box, the lever, the four-stage fight
-- ---------------------------------------------------------------------------------------
local function gate(name, from, destination, allowed, refusal)
	local event = MoveEvent()

	function event.onStepIn(creature, item, position, fromPosition)
		local player = creature:getPlayer()
		if not player then
			return true
		end
		if not allowed(player) and not player:getGroup():getAccess() then
			player:teleportTo(fromPosition, true)
			position:sendMagicEffect(CONST_ME_POFF)
			say(player, refusal)
			return true
		end
		position:sendMagicEffect(CONST_ME_TELEPORT)
		player:teleportTo(destination)
		destination:sendMagicEffect(CONST_ME_TELEPORT)
		return true
	end

	event:type("stepin")
	for _, position in ipairs(from) do
		event:position(position)
	end
	event:register()
end

-- tower -> the Sleeping Dragon's room, for those Zlak has sent
gate("tower", { Position(33066, 31104, 2) }, Position(33242, 31233, 10), function(player)
	return player:getStorageValue(K.M5) >= 1
end, "Nothing happens. The tower's old magic does not know you yet. Zlak must send you first.")

-- the strip at the north end of the staging area (33359-33360,31395,9) -> back to the tower top, free for everyone
gate("strip back to the tower", { Position(33359, 31395, 9), Position(33360, 31395, 9) }, Position(33066, 31106, 2), function()
	return true
end, "")

-- the gate north of the dragon -> the staging area, once she has spoken to you
local gateTiles = {}
for x = 33239, 33245 do
	gateTiles[#gateTiles + 1] = Position(x, 31209, 10)
end
gate("dragon gate", gateTiles, Position(33359, 31397, 9), function(player)
	return player:getStorageValue(K.M5) >= 2
end, "The gate does not open. Hear what the Sleeping Dragon has to say first.")

-- the lever: everyone standing in the staging box is carried into the arena
local BOX = { x1 = 33356, x2 = 33363, y1 = 31403, y2 = 31409, z1 = 9, z2 = 11 }
local STAGES = {
	["Snake God Essence"] = "Snake Thing",
	["Snake Thing"] = "Lizard Abomination",
	["Lizard Abomination"] = "Mutated Zalamon",
}
local STAGE_SPAWN = Position(33360, 31406, 10) -- on the carpet, where the owner pointed
local FIGHT_SECONDS = 30 * 60
local AFTER_KILL_SECONDS = 10 * 60

local function arenaPlayers()
	local players = {}
	for x = ARENA.x1, ARENA.x2 do
		for y = ARENA.y1, ARENA.y2 do
			local tile = Tile(Position(x, y, ARENA.z))
			if tile then
				for _, creature in ipairs(tile:getCreatures() or {}) do
					local player = creature:getPlayer()
					if player then
						players[#players + 1] = player
					end
				end
			end
		end
	end
	return players
end

local FIGHT_NAMES = { ["Snake God Essence"] = true, ["Snake Thing"] = true, ["Lizard Abomination"] = true, ["Mutated Zalamon"] = true }

local function arenaStageAlive()
	for _, spectator in ipairs(Game.getSpectators(STAGE_SPAWN, false, false, 14, 14, 14, 14)) do
		local monster = spectator:getMonster()
		if monster and FIGHT_NAMES[monster:getName()] and inArena(monster:getPosition()) then
			return true
		end
	end
	return false
end

local function removeStages()
	for _, spectator in ipairs(Game.getSpectators(STAGE_SPAWN, false, false, 14, 14, 14, 14)) do
		local monster = spectator:getMonster()
		if monster and FIGHT_NAMES[monster:getName()] and inArena(monster:getPosition()) then
			monster:remove()
		end
	end
end

local function clearArena(generation)
	if generation ~= Wrath.arena.generation then
		return
	end
	for _, spectator in ipairs(Game.getSpectators(STAGE_SPAWN, false, false, 14, 14, 14, 14)) do
		local monster = spectator:getMonster()
		if monster and inArena(monster:getPosition()) then
			monster:remove()
		end
	end
	for _, player in ipairs(arenaPlayers()) do
		player:teleportTo(ARENA_EXIT)
		ARENA_EXIT:sendMagicEffect(CONST_ME_TELEPORT)
		say(player, "The chamber collapses into shadow and throws you back out.")
	end
end

local function freeArenaSquare(index)
	local ring = { {0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, -1}, {2, 0}, {-2, 0}, {0, 2}, {0, -2}, {2, 1}, {-2, 1}, {2, -1}, {-2, -1} }
	for i = 0, #ring - 1 do
		local offset = ring[((index - 1 + i) % #ring) + 1]
		local position = Position(ARENA_ENTRY.x + offset[1], ARENA_ENTRY.y + offset[2], ARENA_ENTRY.z)
		local tile = Tile(position)
		if tile and tile:getGround() and not tile:hasProperty(CONST_PROP_BLOCKSOLID) and tile:getCreatureCount() == 0 then
			return position
		end
	end
	return ARENA_ENTRY
end

local lever = Action()

function lever.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	-- nobody inside but a stage still standing (the party left or died): clear it so the fight can restart
	if #arenaPlayers() == 0 and arenaStageAlive() then
		Wrath.arena.generation = Wrath.arena.generation + 1
		removeStages()
	end
	if #arenaPlayers() > 0 or arenaStageAlive() then
		say(player, "Someone is already fighting Zalamon in the chamber beyond. Wait for them to finish.")
		return true
	end

	local team = {}
	for x = BOX.x1, BOX.x2 do
		for y = BOX.y1, BOX.y2 do
			for z = BOX.z1, BOX.z2 do
				local tile = Tile(Position(x, y, z))
				if tile then
					for _, creature in ipairs(tile:getCreatures() or {}) do
						local member = creature:getPlayer()
						if member and member:getStorageValue(K.M5) == 2 then
							team[#team + 1] = member
						end
					end
				end
			end
		end
	end
	if #team == 0 then
		say(player, "The lever does not move. Only those who have heard the Sleeping Dragon, and stand inside the marked area, may enter.")
		return true
	end

	Wrath.arena.generation = Wrath.arena.generation + 1
	local generation = Wrath.arena.generation
	for index, member in ipairs(team) do
		member:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		local square = freeArenaSquare(index)
		member:teleportTo(square)
		square:sendMagicEffect(CONST_ME_TELEPORT)
		say(member, "The lever drops. The floor gives way and you are dragged into the chamber of Zalamon. Use the replica of the sceptre on his body when he falls.")
	end
	addEvent(function()
		local first = Game.createMonster("Snake God Essence", STAGE_SPAWN, true, true)
		if first then
			STAGE_SPAWN:sendMagicEffect(CONST_ME_MORTAREA)
		end
	end, 4000)
	addEvent(clearArena, FIGHT_SECONDS * 1000, generation)
	return true
end

lever:position(Position(33361, 31410, 9))
lever:register()

-- each stage falls into the next; the last one leaves a body for the sceptre
local stageDeath = CreatureEvent("WrathZalamonStage")

function stageDeath.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local position = creature:getPosition()
	if not inArena(position) then
		return true -- a Snake God Essence out in the world, not Zalamon
	end
	local name = creature:getName()
	local nextName = STAGES[name]
	if nextName then
		addEvent(function()
			local nextStage = Game.createMonster(nextName, position, true, true)
			if nextStage then
				position:sendMagicEffect(CONST_ME_MORTAREA)
				for _, player in ipairs(arenaPlayers()) do
					say(player, name .. " falls, and what is left of it twists into a " .. nextName .. "!")
				end
			end
		end, 1500)
	elseif name == "Mutated Zalamon" then
		local effects = { CONST_ME_FIREWORK_YELLOW, CONST_ME_FIREWORK_RED, CONST_ME_FIREWORK_BLUE }
		for i = 1, 9 do
			addEvent(function()
				local spot = Position(position.x + math.random(-3, 3), position.y + math.random(-3, 3), position.z)
				spot:sendMagicEffect(effects[(i % #effects) + 1])
			end, i * 250)
		end
		position:sendMagicEffect(CONST_ME_HOLYAREA)
		for _, player in ipairs(arenaPlayers()) do
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have slain every form of Zalamon: the Snake God Essence, the Snake Thing, the Lizard Abomination and Mutated Zalamon himself. The Emperor's curse is broken and Zao is free at last!")
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Hold your replica of the sceptre over Zalamon's body to lay the Sleeping Dragon to rest.")
			player:say("Zao is free!", TALKTYPE_MONSTER_SAY)
		end
		Wrath.arena.generation = Wrath.arena.generation + 1
		addEvent(clearArena, AFTER_KILL_SECONDS * 1000, Wrath.arena.generation)
	end
	return true
end

stageDeath:type("death")
stageDeath:register()

-- ---------------------------------------------------------------------------------------
-- Awareness of the Emperor stands in his room (the NPC itself talks in npc/scripts/)
-- ---------------------------------------------------------------------------------------
local AWARENESS_POS = Position(33065, 31151, 15)

local function placeAwareness()
	if not Tile(AWARENESS_POS) then
		return
	end
	for _, spectator in ipairs(Game.getSpectators(AWARENESS_POS, false, false, 8, 8, 8, 8)) do
		local npc = spectator:getNpc()
		if npc and npc:getName() == "Awareness Of The Emperor" then
			return
		end
	end
	Game.createNpc("Awareness Of The Emperor", AWARENESS_POS)
end

placeAwareness()

-- the Sleeping Dragon belongs at her head (33242,31213,10); the old spawn put her 11 squares south.
-- The spawn file is fixed too (takes effect at restart); this moves her now.
local DRAGON_POS = Position(33242, 31213, 10)
local function placeDragon()
	local here = Tile(DRAGON_POS)
	if here then
		for _, c in ipairs(here:getCreatures() or {}) do
			if c:isNpc() and c:getName() == "A Sleeping Dragon" then
				return
			end
		end
	end
	local old = Tile(Position(33239, 31224, 10))
	for _, c in ipairs(old and old:getCreatures() or {}) do
		if c:isNpc() and c:getName() == "A Sleeping Dragon" then
			c:teleportTo(DRAGON_POS, true)
			return
		end
	end
	Game.createNpc("A Sleeping Dragon", DRAGON_POS)
end
placeDragon()

local startup = GlobalEvent("WrathStartup")

function startup.onStartup()
	placeAwareness()
	placeDragon()
	return true
end

startup:register()

-- ---------------------------------------------------------------------------------------
-- Lizard City doors. They are quest doors: the action id is the storage key, and a door opens
-- once that key is set (-1 = never started). So these doors open when Zlak gives you mission 3,
-- and the doors at 33090,31190,7 and 33080,31164,8 when he gives you mission 4.
-- ---------------------------------------------------------------------------------------
local QUEST_DOORS = {
	{ pos = Position(33080, 31215, 7), itemId = 11248, aid = K.M3 },
	{ pos = Position(33086, 31199, 7), itemId = 11248, aid = K.M3 },
	{ pos = Position(33073, 31170, 7), itemId = 11239, aid = K.M3 }, -- the two doors of the same gate, found by
	{ pos = Position(33074, 31170, 7), itemId = 11239, aid = K.M3 }, -- scanning the box 33073-33090, 31170-31190
	{ pos = Position(33090, 31190, 7), itemId = 11239, aid = K.M4 },
	{ pos = Position(33080, 31164, 8), itemId = 11239, aid = K.M4 },
}

local function tagDoors()
	for _, door in ipairs(QUEST_DOORS) do
		local tile = Tile(door.pos)
		local item = tile and tile:getItemById(door.itemId)
		if item and item:getActionId() ~= door.aid then
			item:setActionId(door.aid)
		end
	end
end

tagDoors()

local doorStartup = GlobalEvent("WrathDoorsStartup")

function doorStartup.onStartup()
	tagDoors()
	return true
end

doorStartup:register()

-- Four more doors from mission 4 on (floor 12, the way to the Draken Castle). Their item (11141 /
-- 11142) is in no door table, so nothing opened them. Here: using one opens it for anyone who has
-- been given mission 4, and it closes again when the walker has stepped off.
local M4_DOORS = { Position(33093, 31111, 12), Position(33094, 31111, 12), Position(33108, 31111, 12), Position(33109, 31111, 12) }
local DOOR_CLOSED, DOOR_OPEN = 11141, 11142

local m4Door = Action()

function m4Door.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if item.itemid ~= DOOR_CLOSED then
		return false
	end
	if player:getStorageValue(K.M4) == -1 and not player:getGroup():getAccess() then
		say(player, "The door seems to be sealed against unwanted intruders.")
		return true
	end
	item:transform(DOOR_OPEN)
	local position = item:getPosition()
	addEvent(function()
		local tile = Tile(position)
		local open = tile and tile:getItemById(DOOR_OPEN)
		if open and tile:getCreatureCount() == 0 then
			open:transform(DOOR_CLOSED)
		end
	end, 8000)
	return true
end

for _, position in ipairs(M4_DOORS) do
	m4Door:position(position)
end
m4Door:register()

local m4DoorClose = MoveEvent()

function m4DoorClose.onStepOut(creature, item, position, fromPosition)
	if item.itemid == DOOR_OPEN then
		addEvent(function()
			local tile = Tile(position)
			local open = tile and tile:getItemById(DOOR_OPEN)
			if open and tile:getCreatureCount() == 0 then
				open:transform(DOOR_CLOSED)
			end
		end, 500)
	end
	return true
end

m4DoorClose:type("stepout")
m4DoorClose:id(DOOR_OPEN)
m4DoorClose:register()

-- Two quest doors share one handler (closed 11239 / open 11240):
--   33083,31216,8  next to the coal basin: opens once all four bosses are verified (mission 4 state 2+)
--   33076,31176,8  reward room: opens once you hold mission 6 "Just Rewards"
-- The generic closing_door handler also fires on these doors and bounces anyone whose storage
-- [door action id] is -1, so each door carries a pass key and walkers that qualify get it set first.
local DOOR_CLOSED_ID, DOOR_OPEN_ID = 11239, 11240
local QUEST_DOORS_2 = {
	{
		position = Position(33083, 31216, 8), key = 13016,
		allowed = function(player) return player:getStorageValue(K.M4) >= 2 end,
		refusal = "The door is sealed. Only one who has verified the death of all four guardians may pass.",
	},
	{
		position = Position(33076, 31176, 8), key = 13017,
		allowed = function(player) return player:getStorageValue(K.M6) >= 1 end,
		refusal = "The door is sealed. Only one who has earned the Emperor's rewards may pass.",
	},
}

local function doorAt(position)
	for _, door in ipairs(QUEST_DOORS_2) do
		if door.position == position then
			return door
		end
	end
end

local function closeDoorAt(position)
	local tile = Tile(position)
	local open = tile and tile:getItemById(DOOR_OPEN_ID)
	if open and tile:getCreatureCount() == 0 then
		open:transform(DOOR_CLOSED_ID)
	end
end

local function tagDoors()
	for _, door in ipairs(QUEST_DOORS_2) do
		local tile = Tile(door.position)
		for _, id in ipairs({ DOOR_CLOSED_ID, DOOR_OPEN_ID }) do
			local item = tile and tile:getItemById(id)
			if item and item:getActionId() ~= door.key then
				item:setActionId(door.key)
			end
		end
		closeDoorAt(door.position)
	end
end
tagDoors()

local questDoorAction = Action()

function questDoorAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if item.itemid ~= DOOR_CLOSED_ID then
		return true
	end
	local door = doorAt(item:getPosition())
	if not door then
		return false
	end
	if not door.allowed(player) and not player:getGroup():getAccess() then
		say(player, door.refusal)
		return true
	end
	player:setStorageValue(door.key, 1)
	item:transform(DOOR_OPEN_ID)
	local position = item:getPosition()
	player:teleportTo(position, true, CONST_ME_NONE)
	addEvent(closeDoorAt, 8000, position)
	return true
end

for _, door in ipairs(QUEST_DOORS_2) do
	questDoorAction:position(door.position)
end
questDoorAction:register()

local questDoorStepOut = MoveEvent()

function questDoorStepOut.onStepOut(creature, item, position, fromPosition)
	if item.itemid == DOOR_OPEN_ID then
		addEvent(closeDoorAt, 500, position)
	end
	return true
end

questDoorStepOut:type("stepout")
for _, door in ipairs(QUEST_DOORS_2) do
	questDoorStepOut:position(door.position)
end
questDoorStepOut:register()

-- walking onto an open door: this position event decides, since the generic handler would bounce everyone
local questDoorStepIn = MoveEvent()

function questDoorStepIn.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	local door = doorAt(position)
	if not door then
		return true
	end
	if door.allowed(player) or player:getGroup():getAccess() then
		player:setStorageValue(door.key, 1)
		return true
	end
	say(player, door.refusal)
	player:teleportTo(fromPosition, true)
	return false
end

questDoorStepIn:type("stepin")
for _, door in ipairs(QUEST_DOORS_2) do
	questDoorStepIn:position(door.position)
end
questDoorStepIn:register()

local doorsStartup = GlobalEvent("WrathDoorsStartup")
function doorsStartup.onStartup()
	tagDoors()
	return true
end
doorsStartup:register()

-- ---------------------------------------------------------------------------------------
-- Mission 6: the reward room
-- ---------------------------------------------------------------------------------------
-- the reward chests and basins (33076-33080,31170,8) cannot be walked on, so nobody can stand on them
-- and lift the rewards out of the basins
local blockRow = MoveEvent()

function blockRow.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if player then
		player:teleportTo(fromPosition, true, CONST_ME_NONE)
		player:sendCancelMessage("You cannot walk here.")
	end
	return false
end

blockRow:type("stepin")
for x = 33076, 33080 do
	blockRow:position(Position(x, 31170, 8))
end
blockRow:register()

local REWARD_CHESTS = {
	[4022] = 11687, -- royal scale robe
	[4023] = 11686, -- royal draken mail
	[4024] = 11689, -- elite draken helmet
}

local function finishRewards(player)
	if player:getStorageValue(K.RewardChest) >= 1 and player:getStorageValue(K.Outfit) >= 1 and player:getStorageValue(K.M6) < 2 then
		player:setStorageValue(K.M6, 2)
		say(player, "You have claimed everything the Emperor's fall earned you. The Wrath of the Emperor is over.")
	end
end

local rewardChest = Action()

function rewardChest.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local itemId = REWARD_CHESTS[item.uid]
	if not itemId then
		return false
	end
	if player:getStorageValue(K.M5) < 4 then
		say(player, "The chest is locked. Awareness of the Emperor has not granted you the reward.")
		return true
	end
	if player:getStorageValue(K.RewardChest) >= 1 then
		say(player, "You have already made your choice.")
		return true
	end
	local reward = Game.createItem(itemId, 1)
	if not reward then
		return true
	end
	if RarityStats and RarityStats.canRoll(reward) then
		RarityStats.markUnrevealed(reward)
	end
	local itemType = ItemType(itemId)
	if player:addItemEx(reward) ~= RETURNVALUE_NOERROR then
		player:sendCancelMessage("You have found " .. itemType:getArticle() .. " " .. itemType:getName() .. ", but you have no room or capacity to take it.")
		return true
	end
	player:setStorageValue(K.RewardChest, 1)
	say(player, "You have found " .. itemType:getArticle() .. " " .. itemType:getName() .. ".")
	finishRewards(player)
	return true
end

for uid in pairs(REWARD_CHESTS) do
	rewardChest:uid(uid)
end
rewardChest:register()

local WAYFARER = { 366, 367 } -- female, male
local wardrobe = Action()

function wardrobe.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if player:getStorageValue(K.M5) < 4 then
		say(player, "The wardrobe is locked.")
		return true
	end
	if player:getStorageValue(K.Outfit) >= 1 then
		say(player, "The wardrobe is empty. You already took the Wayfarer outfit.")
		return true
	end
	for _, lookType in ipairs(WAYFARER) do
		player:addOutfit(lookType)
		player:addOutfitAddon(lookType, 1)
		player:addOutfitAddon(lookType, 2)
	end
	player:setStorageValue(K.Outfit, 1)
	player:getPosition():sendMagicEffect(CONST_ME_GIANTICE)
	say(player, "You find a full Wayfarer outfit with all its addons in the wardrobe.")
	finishRewards(player)
	return true
end

wardrobe:position(Position(33073, 31172, 8))
wardrobe:position(Position(33073, 31173, 8))
wardrobe:register()

-- ---------------------------------------------------------------------------------------
-- GM test commands
--   /wrathreset            wipes your Wrath of the Emperor progress
--   /wrathstep <1-7>       puts you at the start of that mission (7 = finished)
--   /wrathbosses           wakes every basement boss at its pillar (ignores the 10-minute wait)
-- ---------------------------------------------------------------------------------------
local reset = TalkAction("/wrathreset")

function reset.onSay(player, words, param)
	for key = 13001, 13014 do
		player:setStorageValue(key, -1)
	end
	say(player, "Your Wrath of the Emperor progress is reset.")
	return false
end

reset:separator(" ")
reset:accountType(6)
reset:register()

local step = TalkAction("/wrathstep")

function step.onSay(player, words, param)
	local n = tonumber(param)
	if not n or n < 1 or n > 7 then
		say(player, "Use: /wrathstep 1 to 7 (1 = start of mission 1 ... 6 = reward room, 7 = finished)")
		return false
	end
	for key = 13001, 13014 do
		player:setStorageValue(key, -1)
	end
	player:setStorageValue(K.Questline, 1)
	local missions = { K.M1, K.M2, K.M3, K.M4, K.M5, K.M6 }
	local finished = { 3, 3, 3, 3, 4, 2 }
	for i, key in ipairs(missions) do
		if i < n then
			player:setStorageValue(key, finished[i])
		elseif i == n then
			player:setStorageValue(key, 1)
		end
	end
	if n >= 4 then
		player:setStorageValue(K.DrakenKills, DRAKENS_NEEDED)
	end
	if n >= 5 then
		for _, key in ipairs({ K.Fury, K.Wrath, K.Scorn, K.Spite }) do
			player:setStorageValue(key, 1)
		end
	end
	if n >= 4 and player:getItemCount(REPLICA) < 1 then
		player:addItem(REPLICA, 1)
	end
	say(player, "Wrath of the Emperor set to mission " .. n .. ".")
	return false
end

step:separator(" ")
step:accountType(6)
step:register()

local bosses = TalkAction("/wrathbosses")

function bosses.onSay(player, words, param)
	local spawned = {}
	for _, pillar in ipairs(PILLARS) do
		if wakeBoss(pillar, true) then
			spawned[#spawned + 1] = pillar.name
		end
	end
	say(player, #spawned == 0 and "Every basement boss is already awake." or ("Woke: " .. table.concat(spawned, ", ")))
	return false
end

bosses:separator(" ")
bosses:accountType(6)
bosses:register()

-- /wrathcool clears the 10-minute pillar wait so the sceptre works on the pillars again
local cool = TalkAction("/wrathcool")

function cool.onSay(player, words, param)
	for _, pillar in ipairs(PILLARS) do
		local state = Wrath.bossState[pillar.name]
		if state then
			local monster = state.id and Monster(state.id)
			if monster then
				monster:remove()
			end
			state.id = nil
			state.wokeAt = nil
		end
	end
	say(player, "Every awake basement boss is removed and the pillar cooldown is cleared. Use the sceptre on a pillar to wake one.")
	return false
end

cool:separator(" ")
cool:accountType(6)
cool:register()

-- /wratharena           removes every Zalamon stage in the chamber and starts the fight over with a fresh
--                       Snake God Essence on the carpet (you stay where you are)
-- /wratharena clear     only removes the stages
local arenaCmd = TalkAction("/wratharena")

function arenaCmd.onSay(player, words, param)
	Wrath.arena.generation = Wrath.arena.generation + 1
	local generation = Wrath.arena.generation
	local removed = 0
	for _, spectator in ipairs(Game.getSpectators(STAGE_SPAWN, false, false, 14, 14, 14, 14)) do
		local monster = spectator:getMonster()
		if monster and FIGHT_NAMES[monster:getName()] and inArena(monster:getPosition()) then
			monster:remove()
			removed = removed + 1
		end
	end
	if param and param:lower():find("clear") then
		say(player, string.format("Removed %d Zalamon stage(s). The arena is empty.", removed))
		return false
	end
	local first = Game.createMonster("Snake God Essence", STAGE_SPAWN, true, true)
	if first then
		STAGE_SPAWN:sendMagicEffect(CONST_ME_MORTAREA)
	end
	addEvent(clearArena, FIGHT_SECONDS * 1000, generation)
	say(player, string.format("Removed %d stage(s) and %s.", removed, first and "spawned a fresh Snake God Essence on the carpet" or "FAILED to spawn the Snake God Essence"))
	return false
end

arenaCmd:separator(" ")
arenaCmd:accountType(6)
arenaCmd:register()

-- the way out of the chamber: teleport 33365,31415,10 -> 33359,31397,9 (it has no destination on the map)
local arenaExit = MoveEvent()

function arenaExit.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	position:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(ARENA_EXIT)
	ARENA_EXIT:sendMagicEffect(CONST_ME_TELEPORT)
	-- the last one out ends the fight
	if #arenaPlayers() == 0 then
		Wrath.arena.generation = Wrath.arena.generation + 1
		removeStages()
	end
	return true
end

arenaExit:type("stepin")
arenaExit:position(Position(33365, 31415, 10))
arenaExit:register()
