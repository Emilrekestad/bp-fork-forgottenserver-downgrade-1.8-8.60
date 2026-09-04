-- Levers (item 2772/2773). Plain levers just flip their sprite.
-- Levers whose Action ID is listed below also raise/lower a linked "bridge"
-- (a strip of water tiles that transforms into solid ground while open).
local BridgeLevers = {
	[50239] = { -- Rookgaard dock bridge
		waterId = 4597, -- shallow water
		bridgeId = 352, -- dirt floor
		tiles = {
			{x = 32100, y = 32204, z = 8}
		}
	}
}

local lever = Action()

function lever.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local openId = item:getId() == 2772 and 2773 or 2772
	item:transform(openId)

	local bridge = BridgeLevers[item.actionid]
	if bridge then
		local opened = openId == 2773
		for _, pos in ipairs(bridge.tiles) do
			local position = Position(pos.x, pos.y, pos.z)
			local tile = Tile(position)
			if tile then
				if opened then
					local water = tile:getItemById(bridge.waterId)
					if water then water:transform(bridge.bridgeId) end
				else
					local plank = tile:getItemById(bridge.bridgeId)
					if plank then plank:transform(bridge.waterId) end
				end
				position:sendMagicEffect(CONST_ME_POFF)
			end
		end
	end

	return true
end

lever:id(2772, 2773)
lever:register()
