local action = Action()

local annihilatorReward = {2856, 3288, 3319, 3388}

-- Action-id-bound quest chests where the reward/storage isn't the chest's own
-- unique id (e.g. shared/famous chests reused across multiple map spots).
-- Annihilator (aid 2215) is intentionally excluded: it already has its own
-- bespoke handling below via annihilatorReward.
local specialQuests = {
	[2016] = PlayerStorageKeys.DreamersChallenge.Reward,
	[10544] = PlayerStorageKeys.PitsOfInferno.WeaponReward,
	[12513] = PlayerStorageKeys.thievesGuild.Reward,
	[12374] = PlayerStorageKeys.WrathoftheEmperor.mainReward,
	[26300] = PlayerStorageKeys.SvargrondArena.RewardGreenhorn,
	[27300] = PlayerStorageKeys.SvargrondArena.RewardScrapper,
	[28300] = PlayerStorageKeys.SvargrondArena.RewardWarlord
}

local questsExperience = {}

local questLog = {
	[9130] = PlayerStorageKeys.hiddenCityOfBeregar.DefaultStart
}

local tutorialIds = {
	[50080] = 5,
	[50082] = 6,
	[50084] = 10,
	[50086] = 11
}

local hotaQuest = {12102, 12103, 12104, 12105, 12106, 12107}

function action.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	-- Bespoke Annihilator handling (fixed item ids, reward id == chest uid)
	if table.contains(annihilatorReward, item.uid) then
		if player:getStorageValue(PlayerStorageKeys.annihilatorReward) == -1 then
			local itemType = ItemType(item.uid)
			local itemWeight = itemType:getWeight()
			if player:getFreeCapacity() >= itemWeight then
				if item.uid == 2856 then
					player:addItem(2856, 1):addItem(3213, 1)
				else
					player:addItem(item.uid, 1)
				end
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, 'You have found a ' .. itemType:getName() .. '.')
				player:setStorageValue(PlayerStorageKeys.annihilatorReward, 1)
				player:addAchievement("Annihilator")
			else
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
					'You have found a ' .. itemType:getName() .. ' weighing ' .. itemWeight .. ' oz it\'s too heavy.')
			end
		else
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "It is empty.")
		end
		return true
	end

	-- Generic quest chest system: storage key is either an explicit override
	-- (specialQuests, keyed by action id) or the chest's own unique id.
	local storage = specialQuests[item.actionid]
	if not storage then
		storage = item.uid
		if storage <= 0 or storage > 65535 then
			return false
		end
	end

	if player:getStorageValue(storage) > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, 'The ' .. ItemType(item.itemid):getName() .. ' is empty.')
		return true
	end

	local items, reward = {}
	local isContainer = item:isContainer()
	local size = isContainer and item:getSize() or 0

	if isContainer and size == 0 then
		-- This map's convention for empty chests: the chest's own unique id
		-- IS the reward item id directly, not just a storage-tracking number.
		-- Bounded to the original script's range: below 1670 overlaps with
		-- generic scenery/wall item ids, which are never real rewards and
		-- would otherwise be handed out as nonsense loot (e.g. "stone wall").
		if item.uid <= 1669 or item.uid >= 27344 or ItemType(item.uid):getId() == 0 then
			return false
		end
		reward = Game.createItem(item.uid, 1)
	elseif not isContainer then
		reward = item:clone()
	else
		for i = 0, item:getSize() - 1 do
			items[#items + 1] = item:getItem(i):clone()
		end
	end

	size = #items
	if size == 1 then
		reward = items[1]:clone()
	end

	local result = ''
	if reward then
		local ret = ItemType(reward.itemid)
		if ret:isRune() then
			result = ret:getArticle() .. ' ' .. ret:getName() .. ' (' .. reward.type .. ' charges)'
		elseif ret:isStackable() and reward:getCount() > 1 then
			result = reward:getCount() .. ' ' .. ret:getPluralName()
		elseif ret:getArticle() ~= '' then
			result = ret:getArticle() .. ' ' .. ret:getName()
		else
			result = ret:getName()
		end
	else
		if size > 20 then
			reward = Game.createItem(item.itemid, 1)
		elseif size > 8 then
			reward = Game.createItem(1988, 1)
		else
			reward = Game.createItem(ITEM_BAG, 1)
		end

		for i = 1, size do
			local tmp = items[i]
			if reward:addItemEx(tmp) ~= RETURNVALUE_NOERROR then
				print('[Warning] QuestSystem:', 'Could not add quest reward to container')
			end
		end
		local ret = ItemType(reward.itemid)
		result = ret:getArticle() .. ' ' .. ret:getName()
	end

	if player:addItemEx(reward) ~= RETURNVALUE_NOERROR then
		local weight = reward:getWeight()
		if player:getFreeCapacity() < weight then
			player:sendCancelMessage(string.format('You have found %s weighing %.2f oz. You have no capacity.', result, (weight / 100)))
		else
			player:sendCancelMessage('You have found ' .. result .. ', but you have no room to take it.')
		end
		return true
	end

	if questsExperience[storage] then
		player:addExperience(questsExperience[storage], true)
	end

	if questLog[storage] then
		player:setStorageValue(questLog[storage], 1)
	end

	if tutorialIds[storage] then
		player:sendTutorial(tutorialIds[storage])
		if item.uid == 50080 then
			player:setStorageValue(PlayerStorageKeys.RookgaardTutorialIsland.SantiagoNpcGreetStorage, 3)
		end
	end

	if table.contains(hotaQuest, item.uid) then
		if player:getStorageValue(PlayerStorageKeys.TheAncientTombs.DefaultStart) ~= 1 then
			player:setStorageValue(PlayerStorageKeys.TheAncientTombs.DefaultStart, 1)
		end
	end

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, 'You have found ' .. result .. '.')
	player:setStorageValue(storage, 1)
	return true
end

-- Full chest/box/trunk/coffin/treasure-chest item family (2471-2486 in
-- items.xml), not just the 4 originally wired up. A map-data scan (2026-08-25)
-- found 22 quest containers across the map already correctly tagged with a
-- reward unique id but silently inert because their item id (mostly 2473
-- "box", a couple 2478 "treasure chest") was never registered here.
action:id(2471, 2472, 2473, 2474, 2475, 2476, 2477, 2478, 2480, 2481, 2482, 2483, 2484, 2485, 2486)
action:aid(2000, 2016, 10544, 12374, 12513, 26300, 27300, 28300)
action:register()
