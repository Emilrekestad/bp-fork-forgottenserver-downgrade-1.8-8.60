-- Reward handlers for the action ids that
-- data/scripts/globalevents/startup_quest_map_repair.lua tags onto its
-- runtime-created/repaired chests (see that file for why action id instead
-- of unique id). Kept as a separate small action rather than reusing
-- quests.lua/system_orts.lua's uid-keyed dispatch, since these items will
-- never carry a real map unique id.

local action = Action()

local ROOKGAARD_CHAIN_ARMOR_ACTIONID = 60201
local ROOKGAARD_DOUBLET_ACTIONID = 60202
-- 60301/60302 (Black Knight crown armor/shield) retired 2026-08-26: those
-- are real map trees now (uid 9270/9277), wired directly in
-- system_orts.lua instead of this synthetic-item fallback.
local BLACK_KNIGHT_TREE_KEY_ACTIONID = 60303

local rewards = {
	[ROOKGAARD_CHAIN_ARMOR_ACTIONID] = {
		storage = PlayerStorageKeys.QuestChests.ChainArmorQuest,
		itemId = 3358 -- chain armor
	},
	[ROOKGAARD_DOUBLET_ACTIONID] = {
		storage = PlayerStorageKeys.QuestChests.DoubletQuest,
		itemId = 3379 -- doublet
	},
	[BLACK_KNIGHT_TREE_KEY_ACTIONID] = {
		storage = PlayerStorageKeys.QuestChests.BlackKnightTreeKey,
		itemId = 2968, -- wooden key (keysID-listed, generic key-door system)
		keyActionId = 5010
	}
}

function action.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local reward = rewards[item.actionid]
	if not reward then
		return false
	end

	if player:getStorageValue(reward.storage) > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, 'The ' .. ItemType(item.itemid):getName() .. ' is empty.')
		return true
	end

	local rewardItem = Game.createItem(reward.itemId, 1)
	if reward.keyActionId then
		rewardItem:setActionId(reward.keyActionId)
	end

	if player:addItemEx(rewardItem) ~= RETURNVALUE_NOERROR then
		local weight = rewardItem:getWeight()
		if player:getFreeCapacity() < weight then
			player:sendCancelMessage(string.format('You have found %s weighing %.2f oz. You have no capacity.',
				ItemType(reward.itemId):getName(), (weight / 100)))
		else
			player:sendCancelMessage('You have found ' .. ItemType(reward.itemId):getName() .. ', but you have no room to take it.')
		end
		return true
	end

	local itemType = ItemType(reward.itemId)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, 'You have found ' .. itemType:getArticle() .. ' ' .. itemType:getName() .. '.')
	player:setStorageValue(reward.storage, 1)
	return true
end

action:aid(60201, 60202, 60303)
action:register()
