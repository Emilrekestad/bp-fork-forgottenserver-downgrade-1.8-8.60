-- Outfit Statue system.
-- Statues are keyed by map position (not itemid), so the same statue sprite
-- can be placed at multiple positions, each granting a different outfit.
-- Adding a new statue only needs a new entry here (plus a matching
-- PlayerStorageKeys.OutfitStatues key) and placing the item on the map with
-- actionIds.outfitStatue set -- no new script.
local OutfitStatues = {
	["32452,32066,4"] = {
		name = "Citizen",
		lookType = {128, 136}, -- male, female -- granted together so the addon works regardless of the player's sex
		addon = 3, -- 0 = base outfit only, 1/2/3 = addon bitmask
		storage = PlayerStorageKeys.OutfitStatues.CitizenStatue
	},

	["31977,32062,13"] = {
		name = "Forest Warden",
		lookType = {1415, 1416}, -- male, female
		addon = 3, -- 0 = base outfit only, 1/2/3 = addon bitmask
		storage = PlayerStorageKeys.OutfitStatues.ForestWardenStatue
	},

	-- ["x,y,z"] = {
	-- 	name = "Knight",
	-- 	lookType = 143, -- number, or a {male, female} table like above
	-- 	addon = 3, -- 0 = base outfit only, 1/2/3 = addon bitmask
	-- 	storage = PlayerStorageKeys.OutfitStatues.KnightStatue
	-- },
}

-- Builds e.g. "the first and second Citizen addons" / "the second Citizen addon" / "the Citizen outfit"
local function describeReward(name, addon)
	if addon == 3 then
		return "the first and second " .. name .. " addons"
	elseif addon == 2 then
		return "the second " .. name .. " addon"
	elseif addon == 1 then
		return "the first " .. name .. " addon"
	else
		return "the " .. name .. " outfit"
	end
end

local outfitStatue = Action()

function outfitStatue.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local pos = item:getPosition()
	local config = OutfitStatues[("%d,%d,%d"):format(pos.x, pos.y, pos.z)]
	if not config then
		return false
	end

	local lookTypes = type(config.lookType) == "table" and config.lookType or {config.lookType}
	local addon = config.addon or 0
	local reward = describeReward(config.name, addon)

	local alreadyHas = player:getStorageValue(config.storage) >= 1
	if not alreadyHas then
		alreadyHas = true
		for _, lookType in ipairs(lookTypes) do
			if not player:hasOutfit(lookType, addon) then
				alreadyHas = false
				break
			end
		end
	end

	if alreadyHas then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You already possess " .. reward .. ". Explore the lands for others.")
		return true
	end

	for _, lookType in ipairs(lookTypes) do
		player:addOutfit(lookType)
		if addon > 0 then
			player:addOutfitAddon(lookType, addon)
		end
	end
	player:setStorageValue(config.storage, 1)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have been granted " .. reward .. "!")
	return true
end

outfitStatue:aid(actionIds.outfitStatue)
outfitStatue:register()
