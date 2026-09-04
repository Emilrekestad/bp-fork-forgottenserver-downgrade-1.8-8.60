-- Item Rarity system — applies/removes a rolled item's passive stat bonus
-- (skills, magic level, max health/mana) when it's equipped or unequipped.
-- Uses this fork's real Player:onUpdateInventory eventcallback (enabled in
-- data/events/events.xml, dispatched via data/events/scripts/player.lua)
-- instead of the original download's commented-out 2000ms polling-loop
-- approach -- fires once per actual inventory change instead of continuously
-- rechecking every equipped slot.
--
-- RarityStats.itemAttributes doesn't need the `equip` flag itself:
-- RarityStats.rollCondition toggles the underlying Condition on/off based on
-- whether it's already applied, so calling this on both directions of
-- onUpdateInventory (equip and unequip) correctly adds it once and removes
-- it once, matching the original download's own design.

local event = Event()

event.onUpdateInventory = function(self, item, slot, equip)
	if item then
		RarityStats.itemAttributes(self, item, slot, equip)
	end
end

event:register()
