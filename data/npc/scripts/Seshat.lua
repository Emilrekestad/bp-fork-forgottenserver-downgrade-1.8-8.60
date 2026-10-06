-- Seshat, the All Knower: gives and ends the Curse of the Seven.
-- The marks, the poison and the walking speed live in
-- data/scripts/quests/ancient_tombs/curse_of_the_seven.lua (global Tombs).
-- Tone: calm, slow, a little amused; short plain sentences, no dashes.
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

local SAY_INTERVAL = 4000
local function sayLines(message, cid)
	return npcHandler:say(message, cid, false, true, SAY_INTERVAL)
end

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)		end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()				end

local HELMET = 3229

local function plural(n, word)
	return n .. " " .. word .. (n == 1 and "" or "s")
end

local function startQuest(cid, player)
	player:setStorageValue(Tombs.storage.started, 1)
	if player:getStorageValue(Tombs.storage.count) < 0 then
		player:setStorageValue(Tombs.storage.count, 0)
	end
	Tombs.refresh(player)
	sayLines({
		"Good. The road has seven tombs. Go in any order you like.",
		"Fight well, and fight together. A pharaoh marks only those who truly fought him.",
		"The seven are not the end. An eighth waits behind them, Ashmunrah.",
		"Come back to me when he has fallen too.",
	}, cid)
end

local function cleanse(cid, player)
	local helmet = Game.createItem(HELMET, 1)
	if not helmet then
		return
	end
	if RarityStats and RarityStats.canRoll(helmet) then
		RarityStats.markUnrevealed(helmet)
	end
	if player:addItemEx(helmet) ~= RETURNVALUE_NOERROR then
		helmet:remove()
		sayLines("Your hands are full. Make room, then speak to me again.", cid)
		return
	end
	player:setStorageValue(Tombs.storage.finished, 2)
	player:setStorageValue(Tombs.storage.helmet, 1)
	Tombs.refresh(player)
	-- the full Pharaoh outfit (female 955, male 956, both addons) and the achievement
	for _, lookType in ipairs({ 955, 956 }) do
		player:addOutfit(lookType)
		player:addOutfitAddon(lookType, 3)
	end
	player:addAchievement("Curse of the Seven")
	player:getPosition():sendMagicEffect(CONST_ME_HOLYAREA)
	sayLines({
		"Seven marks, and Ashmunrah fell too. You carried it all. Stand still.",
		"There. The marks are gone. Your feet are light, and your blood is clean.",
		"Take the Helmet of the Ancients. Its gem is dark. Use a small ruby on it to wake the gem.",
		"And take the dress of the pharaohs, with both of its parts. You have earned it. Wear it with pride.",
		"The pharaohs know you now. They will not mark you again.",
	}, cid)
end

local function progress(cid, player)
	local S = Tombs.storage
	if player:getStorageValue(S.started) ~= 1 then
		if player:getLevel() < Tombs.cfg.minLevel then
			sayLines("You are too young for the tombs. Come back at level " .. Tombs.cfg.minLevel .. ".", cid)
			return
		end
		sayLines({
			"Seven pharaohs sleep in seven tombs. Each one will mark you when he falls.",
			"A mark is small. It slows your feet and puts a little poison in your blood. Each new mark makes it worse.",
			"The marks never leave you, not even when you die or sleep. Only I can lift them, after the last pharaoh falls. He is Ashmunrah, and he waits behind the seven.",
			"Then I give you the Helmet of the Ancients. Will you walk this road?",
		}, cid)
		npcHandler.topic[cid] = 1
		return
	end

	local finished = player:getStorageValue(S.finished)
	if finished >= 2 then
		sayLines("The road is walked. You know the helmet now. The pharaohs cannot mark you again.", cid)
	elseif finished == 1 then
		cleanse(cid, player)
	else
		local marks = Tombs.marks(player)
		local left = Tombs.remaining(player)
		if marks >= 7 then
			sayLines({
				"You carry all seven marks.",
				"One is left, Ashmunrah. He waits in his tomb under Ankrahmun. You may go there now.",
				"Pull every switch in his room. Bring him down. Then come back to me.",
			}, cid)
			return
		end
		sayLines({
			"You carry " .. plural(marks, "mark") .. ".",
			"Still standing: " .. table.concat(left, ", ") .. ".",
			"Do not go alone. Many hands are better.",
		}, cid)
	end
end

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end

	local player = Player(cid)

	if npcHandler.topic[cid] == 1 then
		npcHandler.topic[cid] = 0
		if msgcontains(msg, "yes") then
			startQuest(cid, player)
		else
			sayLines("Then go. The sand is patient. I will be here.", cid)
		end
		return true
	end

	if msgcontains(msg, "quest") or msgcontains(msg, "mission") or msgcontains(msg, "tomb")
		or msgcontains(msg, "pharaoh") or msgcontains(msg, "help") or msgcontains(msg, "job") then
		progress(cid, player)
	elseif msgcontains(msg, "curse") or msgcontains(msg, "mark") then
		local marks = Tombs.activeMarks(player)
		if marks == 0 then
			sayLines("You carry no marks. Your feet are light.", cid)
		else
			sayLines({
				"You carry " .. plural(marks, "mark") .. ".",
				"Your feet are " .. Tombs.speedPercent(player) .. " percent slower.",
				"Your blood takes " .. Tombs.poisonDamage(player) .. " poison every " .. math.floor(Tombs.cfg.tickMs / 1000) .. " seconds. It cannot kill you.",
			}, cid)
		end
	elseif msgcontains(msg, "helmet") or msgcontains(msg, "ruby") or msgcontains(msg, "gem") or msgcontains(msg, "enchant") then
		sayLines({
			"The Helmet of the Ancients has a dead gem.",
			"Use a small ruby on the helmet. The gem wakes and stays awake for twelve hours. Then it sleeps again.",
		}, cid)
	elseif msgcontains(msg, "name") or msgcontains(msg, "who") then
		sayLines("I am Seshat. I have read every tomb. I know what is in them, and what is not.", cid)
	end
	return true
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())
