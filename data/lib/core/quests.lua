local quests = {}
local missions = {}

Quest = {}
Quest.__index = Quest

function Quest:register()
	self.id = #quests + 1
	for _, mission in pairs(self.missions) do
		mission.id = #missions + 1
		mission.questId = self.id
		missions[mission.id] = setmetatable(mission, Mission)
	end

	quests[self.id] = self
	return true
end

function Quest:isStarted(player)
	return player:getStorageValue(self.storageId, 0) >= self.storageValue
end

function Quest:isCompleted(player)
	for _, mission in pairs(self.missions) do
		if not mission:isCompleted(player) then return false end
	end
	return true
end

function Quest:getMissions(player)
	local playerMissions = {}
	for _, mission in pairs(self.missions) do
		if mission:isStarted(player) then playerMissions[#playerMissions + 1] = mission end
	end
	return playerMissions
end

Mission = {}
Mission.__index = Mission

function Mission:isStarted(player)
	local value = player:getStorageValue(self.storageId, 0)
	if value >= self.startValue then
		if self.ignoreEndValue or value <= self.endValue then return true end
	end
	return false
end

function Mission:isCompleted(player)
	if self.ignoreEndValue then
		return player:getStorageValue(self.storageId, 0) >= self.endValue
	end
	return player:getStorageValue(self.storageId, 0) == self.endValue
end

function Mission:getName(player)
	if self:isCompleted(player) then return string.format("%s (Completed)", self.name) end
	return self.name
end

function Mission:getDescription(player)
	local descriptionType = type(self.description)
	if descriptionType == "function" then return self.description(player) end

	local value = player:getStorageValue(self.storageId, 0)
	if descriptionType == "string" then
		-- NOTE: the second gsub used to read from self.description again, which
		-- silently threw away the |STATE| substitution done on the line above --
		-- every counter-style mission ("|STATE| / 5") rendered the literal text
		-- "|STATE|" instead of the player's progress. Chain off `description`.
		local description = self.description:gsub("|STATE|", value)
		description = description:gsub("\\n", "\n")
		return description
	end

	if descriptionType == "table" then
		if self.ignoreEndValue then
			for current = self.endValue, self.startValue, -1 do
				if value >= current then return self.description[current] end
			end
		else
			for current = self.endValue, self.startValue, -1 do
				if value == current then return self.description[current] end
			end
		end
	end

	return "An error has occurred, please contact a gamemaster."
end

function Game.getQuests() return quests end
function Game.getMissions() return missions end

function Game.getQuestById(id) return quests[id] end
function Game.getMissionById(id) return missions[id] end

function Game.clearQuests()
	quests = {}
	missions = {}
	return true
end

function Game.createQuest(name, quest)
	if not isScriptsInterface() then return end

	if type(quest) == "table" then
		setmetatable(quest, Quest)
		quest.id = -1
		quest.name = name
		if type(quest.missions) ~= "table" then quest.missions = {} end

		return quest
	end

	quest = setmetatable({}, Quest)
	quest.id = -1
	quest.name = name
	quest.storageId = 0
	quest.storageValue = 0
	quest.missions = {}
	return quest
end

function Game.isQuestStorage(key, value, oldValue)
	key = tonumber(key)
	value = tonumber(value)
	oldValue = tonumber(oldValue) or -1

	if not key or not value then
		return false
	end

	for _, quest in pairs(quests) do
		local questStorageId = tonumber(quest.storageId)
		local questStorageValue = tonumber(quest.storageValue)

		if questStorageId == key and questStorageValue == value and oldValue ~= value then return true end
	end

	for _, mission in pairs(missions) do
		local storageId = tonumber(mission.storageId)
		local startValue = tonumber(mission.startValue)
		local endValue = tonumber(mission.endValue)

		if storageId == key and startValue and endValue and value >= startValue and value <=
			endValue then
			return oldValue ~= value
		end
	end
	return false
end

function Player:getQuests()
	local playerQuests = {}
	for _, quest in pairs(quests) do
		if quest:isStarted(self) then playerQuests[#playerQuests + 1] = quest end
	end
	return playerQuests
end

-- Marks every registered quest + mission as completed for this player.
--
-- Ordering matters: some quests reuse their own first mission's storage key as
-- the quest start key (e.g. "The Travelling Trader Quest" uses 101 for both the
-- quest start and "Mission 1: Trophy"). Writing missions first and quest-starts
-- second would knock those missions back out of the completed state, so all
-- quest-start keys are written in one pass and every mission key after it --
-- mission endValues are >= their quest's startstoragevalue, so the quest stays
-- "started" while the mission reads "completed".
--
-- Idempotent: only writes keys whose value differs, so re-running it is cheap
-- and newly added quests are picked up automatically on the next run.
-- Returns changedCount, plus a list of any quests that still do not report
-- isCompleted() afterwards (storage-key collisions between different quests
-- would show up here rather than silently looking fine).
function Player:completeAllQuests()
	local quests = Game.getQuests()
	local changed = 0

	for _, quest in pairs(quests) do
		if quest.storageId and quest.storageValue
			and self:getStorageValue(quest.storageId, 0) < quest.storageValue then
			self:setStorageValue(quest.storageId, quest.storageValue)
			changed = changed + 1
		end
	end

	-- Some quests are rank ladders: several missions share ONE storage key with
	-- non-overlapping tiers (Paw and Fur key 2500 -> Member 0-10, Ranger 11-20,
	-- ... Elite Hunter 71-100). Only one tier is ever in range at a time, so the
	-- target for a shared key is the HIGHEST endValue = top rank reached.
	-- Collapsing to a max first also makes this deterministic; writing them in
	-- pairs() order would leave whichever tier happened to be last.
	local targets = {}
	for _, quest in pairs(quests) do
		for _, mission in pairs(quest.missions) do
			if mission.storageId and mission.endValue then
				local current = targets[mission.storageId]
				if not current or mission.endValue > current then
					targets[mission.storageId] = mission.endValue
				end
			end
		end
	end

	for storageId, endValue in pairs(targets) do
		if self:getStorageValue(storageId, 0) ~= endValue then
			self:setStorageValue(storageId, endValue)
			changed = changed + 1
		end
	end

	local incomplete = {}
	for _, quest in pairs(quests) do
		if not (quest:isStarted(self) and quest:isCompleted(self)) then
			incomplete[#incomplete + 1] = quest.name
		end
	end

	return changed, incomplete
end

function Player:sendQuestLog()
	if not self:isUsingOtClient() then
		return false
	end

	local msg<close> = NetworkMessage()
	msg:addByte(0xF0)
	local quests = self:getQuests()
	msg:addU16(#quests)

	for _, quest in pairs(quests) do
		msg:addU16(quest.id)
		msg:addString(quest.name)
		msg:addByte(quest:isCompleted(self) and 1 or 0)
	end

	msg:sendToPlayer(self)
	return true
end

function Player:sendQuestLine(quest)
	if not self:isUsingOtClient() then
		return false
	end

	local msg<close> = NetworkMessage()
	msg:addByte(0xF1)
	msg:addU16(quest.id)
	local missions = quest:getMissions(self)
	msg:addByte(#missions)

	for _, mission in pairs(missions) do
		msg:addString(mission:getName(self))
		msg:addString(mission:getDescription(self))
	end

	msg:sendToPlayer(self)
	return true
end
