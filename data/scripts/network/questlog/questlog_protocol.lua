-- Quest Log — custom protocol.
--
-- Replaces the native quest-log packets (client opcodes GameServerQuestLog /
-- GameServerQuestLine, src/client/protocolgameparse.cpp) with the same
-- pattern game_achievements / game_bao / game_bazaar already use: one raw
-- opcode byte per direction via PacketHandler (receive) / NetworkMessage +
-- :sendToPlayer (send), a sub-type byte inside the payload for routing.
--
-- Why: the native mission-level packet (parseQuestLine) has NO completed
-- flag and no progress value at all — the only signal the stock client ever
-- had for "is this mission done" was a literal " (Completed)" suffix baked
-- into the name string (see the OLD Mission:getName in data/lib/core/
-- quests.lua). That's a hard limit of the compiled client's C++ parser, not
-- something fixable from Lua on the native path. This custom protocol is
-- fully Lua-defined on both ends (same as the three systems above), so it
-- can just send real fields instead: a completed byte per mission, and a
-- computed 0-100 progress percent for counter-style ("|STATE|") missions,
-- so the client never has to string-parse anything to know quest state.
--
-- The Quest/Mission registry itself (data/lib/core/quests.lua) is untouched —
-- this file is transport only. Player:sendQuestLog()/sendQuestLine() (the
-- native-packet senders) and data/scripts/network/quests/quests.lua (the old
-- PacketHandler for the native 0xF0/0xF1 opcodes) are dead code now that the
-- client module no longer calls g_game.requestQuestLog()/requestQuestLine();
-- deleted here rather than left as a second, silently-diverging quest log
-- implementation.

-- 0x54/0x55 (84/85 decimal): confirmed free against the client's
-- ClientOpcodes/GameServerOpcodes enums (otclient-src/src/client/
-- protocolcodes.h), the server's native protocolgame.cpp switch, AND every
-- other custom opcode already claimed in this codebase (0x28-0x3F, 0x4A-0x4F
-- achievements/bao/item bazaar, 0x53 task board, 0x5A-0x5C, 0x5F, 0x61-0x62,
-- 0x73, and the high 0x9xx-0xFx native/custom range) — see bao_protocol.lua's
-- header comment for why this checklist matters: reusing a native opcode by
-- accident here previously made every Bao action silently walk the player
-- north instead of reaching its handler.
local OPCODE_QUESTLOG_REQUEST = 0x54 -- client -> server
local OPCODE_QUESTLOG_SEND = 0x55    -- server -> client

local RESP_LOG = 0x01
local RESP_LINE = 0x02

local ACTION_REQUEST_LOG = 0x01
local ACTION_REQUEST_LINE = 0x02

-- Matches Bao/Achievements/Bazaar's throttle shape and magnitude.
local ACTION_COOLDOWN = 400

local function supportsCustomNetwork(player)
	return player and player.isUsingOtClient and player:isUsingOtClient()
end

-- A mission counts as "has a meaningful progress bar" only when its
-- description is the string form AND actually uses |STATE| -- that is
-- exactly the set of counter-style missions in this datapack today (the 8
-- "Daily Minor/Major" entries in Bigfoot's Burden). A plain two-state mission
-- (not-done / done) has nothing a bar would usefully show.
local function missionHasProgress(mission)
	return type(mission.description) == "string" and mission.description:find("|STATE|", 1, true) ~= nil
end

local function missionProgressPercent(player, mission)
	local value = player:getStorageValue(mission.storageId, 0)
	local span = mission.endValue - mission.startValue
	if span <= 0 then
		return 100
	end
	local progressed = value - mission.startValue
	if progressed < 0 then
		progressed = 0
	elseif progressed > span then
		progressed = span
	end
	return math.floor((progressed / span) * 100)
end

local function sendQuestLog(player)
	if not supportsCustomNetwork(player) then
		return false
	end

	local quests = player:getQuests()

	local out = NetworkMessage(player)
	out:addByte(OPCODE_QUESTLOG_SEND)
	out:addByte(RESP_LOG)
	out:addU16(#quests)

	for _, quest in ipairs(quests) do
		local total = #quest.missions
		local completedCount = 0
		for _, mission in ipairs(quest.missions) do
			if mission:isCompleted(player) then
				completedCount = completedCount + 1
			end
		end

		out:addU16(quest.id)
		out:addString(quest.name)
		out:addByte(quest:isCompleted(player) and 1 or 0)
		out:addByte(math.min(completedCount, 255))
		out:addByte(math.min(total, 255))
	end

	return out:sendToPlayer(player)
end

local function sendQuestLine(player, questId)
	if not supportsCustomNetwork(player) then
		return false
	end

	local quest = Game.getQuestById(questId)
	if not quest then
		return false
	end

	-- Same "started" gate the old sendQuestLine used: missions not yet
	-- reached are never sent at all, so the client never has to invent a
	-- "locked/sealed" state for content it can't describe yet.
	local missions = quest:getMissions(player)

	local out = NetworkMessage(player)
	out:addByte(OPCODE_QUESTLOG_SEND)
	out:addByte(RESP_LINE)
	out:addU16(quest.id)
	out:addString(quest.name)
	out:addByte(math.min(#missions, 255))

	for _, mission in ipairs(missions) do
		local completed = mission:isCompleted(player)
		local hasProgress = (not completed) and missionHasProgress(mission)

		out:addString(mission.name)
		out:addString(mission:getDescription(player))
		out:addByte(completed and 1 or 0)
		out:addByte(hasProgress and 1 or 0)
		out:addByte(hasProgress and missionProgressPercent(player, mission) or 0)
	end

	return out:sendToPlayer(player)
end

local requestHandler = PacketHandler(OPCODE_QUESTLOG_REQUEST)

function requestHandler.onReceive(player, msg)
	local action = NetworkGuard.readByte(msg)
	if not action then
		return
	end

	if not NetworkGuard.cooldown(player, "questlog:" .. action, ACTION_COOLDOWN) then
		return
	end

	if action == ACTION_REQUEST_LOG then
		sendQuestLog(player)
	elseif action == ACTION_REQUEST_LINE then
		local questId = NetworkGuard.readU16(msg)
		if questId then
			sendQuestLine(player, questId)
		end
	end
end

requestHandler:register()
