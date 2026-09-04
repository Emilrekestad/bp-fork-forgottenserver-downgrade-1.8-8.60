-- Bender Shun -- Old Man Bao's estranged brother, the face of server-wide
-- "World Missions" progression (locked regions, collective objectives,
-- permanent world changes). The engine and the first three real missions
-- (Liberty Bay, Oramond, Roshamuul) live in data/lib/worldmissions/ --
-- this file is Shun's own dialogue layer on top of it: "tithe" for
-- Delivery hand-ins, "missions"/"world"/"progress" for a status readout
-- that respects succession (a mission with an unmet prerequisite never
-- appears here), plus mission-specific hint keywords like "liberty".

local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()					end

npcHandler:setMessage(MESSAGE_GREET, "Ah. Another creature wanting something from my world. Speak.")
npcHandler:setMessage(MESSAGE_FAREWELL, "Run along. The world and I have matters to discuss.")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Hm. Even Bao's rats linger longer than you.")
npcHandler:setMessage(MESSAGE_SENDTRADE, "Sure.")

keywordHandler:addKeyword({ "job" }, StdModule.say, { npcHandler = npcHandler, text = "Job? Hah. Bao has a job. Kings have jobs. Gravediggers have jobs... I have leverage." })
keywordHandler:addKeyword({ "bao" }, StdModule.say, { npcHandler = npcHandler, text = "Bao, brother... I fear his simplicity will ruin him. Creatures... creatures come and go. Mountains remain. I love my brother, but kill every creature in a forest and Bao will applaud you. Move the forest... then you have my attention." })
keywordHandler:addKeyword({ "brother" }, StdModule.say, { npcHandler = npcHandler, text = "Brother..? Blood is merely the first chain placed around a man. Bao chose to understand the world. I chose to make it understand me." })

-- "tithe" -- the generic World Missions Delivery entry point (see
-- data/lib/worldmissions/worldmissions_state.lua's deliverItem). Not
-- hardcoded to any specific mission -- checks every REVEALED, still-open
-- delivery mission for any item in its `items` list the player happens to
-- be carrying, and can hand in several different items across several
-- missions in one call (loops until nothing more matches). Caps each
-- hand-in at exactly what that item still needs, so carrying more than
-- required doesn't lose the surplus in one go.
local function titheCallback(cid, message, keywords, parameters, node)
	local player = Player(cid)
	if not player then
		return true
	end

	local deliveredAny = false
	for missionId, mission in pairs(WorldMissions.Missions) do
		if mission.type == "delivery" and WorldMissions.isRevealed(missionId) and not WorldMissions.isApplied(missionId) then
			for _, entry in ipairs(mission.items or {}) do
				local held = player:getItemCount(entry.itemId)
				if held > 0 then
					local stillNeeded = math.max(0, entry.threshold - WorldMissions.getItemProgress(missionId, entry.itemId))
					local delivering = math.min(held, stillNeeded)
					if delivering > 0 and WorldMissions.deliverItem(player, missionId, entry.itemId, delivering) then
						deliveredAny = true
						npcHandler:say(string.format(
							"%d %s accepted, toward %s. %d of %d now.",
							delivering, entry.name or ("item " .. entry.itemId), mission.name or missionId,
							WorldMissions.getItemProgress(missionId, entry.itemId), entry.threshold
						), cid)
					end
				end
			end
		end
	end

	if not deliveredAny then
		npcHandler:say("Nothing needs tithing right now. Come back when the world asks for something.", cid)
	end
	return true
end

keywordHandler:addKeyword({ "tithe" }, titheCallback, {})

-- "missions"/"world"/"progress" -- lists every REVEALED, still-open
-- mission with its current status. Succession per owner's spec: an
-- unrevealed mission (prerequisite not yet applied) never appears here at
-- all -- "you can only see X world missions until Y has been completed."
-- statusMessage, when a mission defines one (Roshamuul), replaces the
-- generic numeric readout entirely -- some missions get a plain tally,
-- some get Shun's own reaction instead.
local function missionsStatusText()
	local lines = {}
	for _, missionId in ipairs({"liberty_bay", "oramond", "roshamuul"}) do
		local mission = WorldMissions.Missions[missionId]
		if mission and WorldMissions.isRevealed(missionId) and not WorldMissions.isApplied(missionId) then
			if mission.statusMessage then
				table.insert(lines, mission.name .. ": " .. mission.statusMessage)
			elseif mission.type == "activation" then
				local activated = 0
				for index in ipairs(mission.objects) do
					if WorldMissions.isObjectActivated(missionId, index) then
						activated = activated + 1
					end
				end
				table.insert(lines, string.format("%s: %d of %d.", mission.name, activated, mission.threshold))
			elseif mission.type == "delivery" then
				local parts = {}
				for _, entry in ipairs(mission.items) do
					table.insert(parts, string.format("%s %d/%d", entry.name, WorldMissions.getItemProgress(missionId, entry.itemId), entry.threshold))
				end
				table.insert(lines, mission.name .. ": " .. table.concat(parts, ", "))
			else
				table.insert(lines, string.format("%s: %d of %d.", mission.name, WorldMissions.getProgress(missionId), mission.threshold))
			end
		end
	end
	return lines
end

local function missionsCallback(cid, message, keywords, parameters, node)
	local lines = missionsStatusText()
	if #lines == 0 then
		npcHandler:say("The world holds still for now. I have nothing that needs your hands.", cid)
		return true
	end
	for _, line in ipairs(lines) do
		npcHandler:say(line, cid)
	end
	return true
end

keywordHandler:addKeyword({ "missions" }, missionsCallback, {})
keywordHandler:addKeyword({ "world" }, missionsCallback, {})
keywordHandler:addKeyword({ "progress" }, missionsCallback, {})

-- Per-mission dialogue -- each keyword is state-aware (not just static
-- flavor text), same three-state shape every time: not yet revealed
-- (prerequisite unmet -- Shun refuses to even discuss it, staying
-- consistent with the succession rule instead of leaking a mission early
-- through a lucky guess of its name), still open (the actual hint --
-- necessary player-facing information: roughly where/what/how many,
-- without literal coordinates or exact numbers, "loosely" per the
-- owner's brief), and applied (a short past-tense acknowledgment, so a
-- player who already finished it doesn't get told to do it again).
local function libertyCallback(cid, message, keywords, parameters, node)
	if WorldMissions.isApplied("liberty_bay") then
		npcHandler:say("Liberty Bay's door doesn't need me anymore. Four hands did that, not one. Go see for yourself.", cid)
	else
		npcHandler:say("Liberty Bay? A door, closed a long time ago. Four levers hold it shut -- scattered across the mainland, and one across the water, by Edron. Pull all four, and the door stops caring why. Ask me of 'missions' if you want to know how far you've gotten.", cid)
	end
	return true
end
keywordHandler:addKeyword({ "liberty" }, libertyCallback, {})

local function oramondCallback(cid, message, keywords, parameters, node)
	if not WorldMissions.isRevealed("oramond") then
		npcHandler:say("Oramond? You have a door to open first. Come back when the bay breathes again.", cid)
	elseif WorldMissions.isApplied("oramond") then
		npcHandler:say("Oramond stopped waiting on you. The furnaces have what they wanted. Go see what you helped feed.", cid)
	else
		npcHandler:say("Oramond hungers for numbers, not names. Every creature that falls, anywhere in this world, feeds it -- five hundred thousand, and the gates remember why they were built. Ask me of 'missions' for how close you've come.", cid)
	end
	return true
end
keywordHandler:addKeyword({ "oramond" }, oramondCallback, {})

local function roshamuulCallback(cid, message, keywords, parameters, node)
	if not WorldMissions.isRevealed("roshamuul") then
		npcHandler:say("Roshamuul can wait. It has waited longer than you've been alive. So can I.", cid)
	elseif WorldMissions.isApplied("roshamuul") then
		npcHandler:say("Roshamuul stands built. The mountain didn't need your hands in the end -- but it took them anyway. Fitting.", cid)
	else
		npcHandler:say("HAH! Roshamuul? I don't need your pity supplies -- stones move because I tell them to. But if it amuses you: iron ore, demonic essence, rope belts, silencer claws. Bring what you can carry. Ask me of 'missions' to see what the mountain still wants.", cid)
	end
	return true
end
keywordHandler:addKeyword({ "roshamuul" }, roshamuulCallback, {})

-- Ambient voice lines -- calm, philosophical, arrogant, sinister without
-- threatening, contrasting temporary things (creatures, kings, gold) against
-- permanent ones (mountains, stone, the world itself). Same tone as the
-- signature dialogue in the owner's brief, extrapolated to fill out the
-- VoiceModule rotation.
--
-- The Liberty Bay/Oramond/Roshamuul lines below are deliberately NOT
-- gated by mission state (VoiceModule just picks a random static line,
-- no per-line condition support -- see data/npc/lib/npcsystem/
-- modules.lua) -- reads fine in character anyway, since Shun talks about
-- all three as inevitabilities he's already seen coming, not things he's
-- reacting to in the moment. The keyword dialogue above is where the
-- real, state-aware information lives.
local voices = {
	{ text = "Creatures die. Kings die. Civilizations disappear. Mountains remain." },
	{ text = "I am no magician. Stone, fire and old, patient things simply have rules. I have only troubled myself to learn them." },
	{ text = "Somewhere past a gate you cannot open, something waits that strength alone will never earn." },
	{ text = "Gold rusts. Empires fall. The mountain does not notice either." },
	{ text = "My brother collects trophies from things that die in a season. I keep leverage over things that do not." },
	{ text = "You are proud of what you have slain. I am curious what still refuses to move." },
	{ text = "A wall is not stubborn. A wall has simply not yet been convinced." },
	{ text = "Adventurers conquer a thousand monsters, then meet a gate strength cannot open. That is when they find me." },
	{ text = "Four small things, forgotten by everyone but me. Pull one, and see how loudly silence can announce itself." },
	{ text = "The bay does not know it is closed. Only the door remembers, and doors do not get to vote." },
	{ text = "Boats cross to Edron every day, full of people who will never once look down at the lever beneath them." },
	{ text = "Beneath Oramond, machinery waits on nothing but a number. It does not care whose hand fed it, only that enough hands did." },
	{ text = "Every corpse is a coin, to a furnace patient enough to wait for five hundred thousand of them." },
	{ text = "Iron. Rope. Essence. Claws. Bring me enough of the world's refuse, and I will show you what refuse becomes." },
	{ text = "Roshamuul does not need your pity. It needs your patience, and your pockets emptied into mine." },
	{ text = "Stones move because I tell them to. I have simply not yet told all of them." },
}

npcHandler:addModule(VoiceModule:new(voices))
npcHandler:addModule(FocusModule:new())
