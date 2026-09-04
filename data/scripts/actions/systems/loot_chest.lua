-- Loot Chest system -- item action. Any chest carrying one of the actionids
-- in LootChestConfig.ActionIds rolls that actionid's named table (see
-- data/lib/lootchest/lootchest_config.lua) when used. Add a new chest type
-- by adding a table + actionid there -- no changes needed here.

local chestAction = Action()

function chestAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local tableName = LootChestConfig.ActionIds[item:getActionId()]
	if not tableName then
		return false
	end

	LootChest.open(player, tableName)
	return true
end

for actionId in pairs(LootChestConfig.ActionIds) do
	chestAction:aid(actionId)
end
chestAction:register()
