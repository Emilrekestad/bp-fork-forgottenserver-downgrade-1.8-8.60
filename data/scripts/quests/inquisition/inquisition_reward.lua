-- The Inquisition reward room (Mission 4 done, Henricus has opened it).
--
-- * The door at 32320,32258,9 is a quest door whose action id is the "reward room open"
--   storage (12198); Henricus sets it when you report. Tagged here at load and at boot.
-- * Ten chests at 32314-32332,32245,9 (unique ids 1300-1309). Take ONE of them: the reward
--   comes Unrevealed. The item for each chest is set below (the map shows it on the shelf
--   above the chest; most of the chests are empty on the map).
local REWARD_ACCESS = 12198 -- 1 = Henricus opened the reward room
local REWARD_CHOICE = 12204 -- 1 = may choose, 2 = has chosen

local DOOR_POSITION = Position(32320, 32258, 9)
local DOOR_ID = 5104

local REWARDS = {
	[1304] = 8023, -- royal crossbow
	[1308] = 8026, -- warsinger bow
	[1301] = 8090, -- spellbook of dark mysteries
	[1307] = 8102, -- emerald sword
	[1305] = 8096, -- hellforged axe
	[1306] = 8100, -- obsidian truncheon
	[1303] = 8060, -- master archer's armor
	[1302] = 8053, -- fireborn giant armor
	[1300] = 8062, -- robe of the underworld
	[1309] = 50261, -- merudri nanbando
}

local chest = Action()

function chest.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local itemId = REWARDS[item.uid]
	if not itemId then
		return false
	end
	if player:getStorageValue(REWARD_ACCESS) < 1 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The chest is locked. Report to Henricus first.")
		return true
	end
	if player:getStorageValue(REWARD_CHOICE) >= 2 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have already made your choice.")
		return true
	end

	local reward = Game.createItem(itemId, 1)
	if not reward then
		return true
	end
	if RarityStats and RarityStats.canRoll(reward) then
		RarityStats.markUnrevealed(reward)
	end
	local name = ItemType(itemId):getName()
	if player:addItemEx(reward) ~= RETURNVALUE_NOERROR then
		player:sendCancelMessage("You have found " .. name .. ", but you have no room or capacity to take it.")
		return true
	end
	player:setStorageValue(REWARD_CHOICE, 2)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have found " .. ItemType(itemId):getArticle() .. " " .. name .. ".")
	return true
end

for uid in pairs(REWARDS) do
	chest:uid(uid)
end
chest:register()

local function tagDoor()
	local tile = Tile(DOOR_POSITION)
	local door = tile and tile:getItemById(DOOR_ID)
	if door and door:getActionId() ~= REWARD_ACCESS then
		door:setActionId(REWARD_ACCESS)
	end
end

-- on a reload the map is already there; at boot the startup event below does it
tagDoor()

local startup = GlobalEvent("InquisitionRewardStartup")

function startup.onStartup()
	tagDoor()
	return true
end

startup:register()
