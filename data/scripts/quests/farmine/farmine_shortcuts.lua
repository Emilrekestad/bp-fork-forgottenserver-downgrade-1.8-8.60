-- Farmine shortcuts: the two teleports at 33004,31540,0 and 33005,31540,0 are free for
-- everyone (no quest) and both land at 33197,31347,6. The map gave them destinations one
-- square apart, so both are set to the same tile here at load and at boot.
local LANDING = Position(33197, 31347, 6)
local SHORTCUTS = { Position(33004, 31540, 0), Position(33005, 31540, 0) }

local function setDestinations()
	for _, position in ipairs(SHORTCUTS) do
		local tile = Tile(position)
		local item = tile and tile:getItemById(1949)
		local teleport = item and Teleport(item.uid)
		if teleport then
			teleport:setDestination(LANDING)
		end
	end
end

-- on a reload the map is already there; at boot the startup event below does it
setDestinations()

local startup = GlobalEvent("FarmineShortcutsStartup")

function startup.onStartup()
	setDestinations()
	return true
end

startup:register()
