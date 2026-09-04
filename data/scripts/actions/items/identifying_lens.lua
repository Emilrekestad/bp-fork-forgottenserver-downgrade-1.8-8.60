-- Dormant Waker (item 39241, "a dormant waker") -- the portable alternative
-- to a free Dormant Shrine. Use it targeting the dormant item you want
-- identified (crosshair "Use with...", same interaction as a rope/shovel) --
-- deliberately targeted rather than auto-picking one, since a player may be
-- carrying several dormant items and only want to reveal a specific one
-- (e.g. keeping others dormant to sell as-is). Permanent tool, NOT consumed
-- -- one purchase covers every identify forever (owner spec 2026-08-30:
-- meant to be a one-time "everyone buys this" unlock, not a repeat
-- consumable). Requires the target be carried on the player -- not lying on
-- the ground -- so identifying someone else's dropped loot isn't possible.
-- Store-sellable (see data/store/gamestore.xml); temple Dormant Shrines offer
-- the same sleep/wake ritual for free.
--
-- Two binary flags had to be patched for this item to work as a "Use
-- with..." tool at all (2026-08-30), neither controllable from Lua/items.xml:
--   1. Client-side (otclient-src/data/things/860/Tibia.dat): the item's
--      ThingType had no ThingAttrMultiUse flag, so the client never offered
--      "Use with..." in the first place -- ground truth confirmed via a
--      from-scratch .dat parser (matching src/client/thingtype.cpp), patched
--      by inserting the flag byte, full-file round-trip validated before
--      deploying. Original preserved at Tibia.dat.bak-before-multiuse-patch.
--   2. Server-side (data/items/items.otb): TFS's own Actions::useItemEx
--      (src/actions.cpp) requires item->isUseable() (FLAG_USEABLE in the
--      OTB flags bitfield, src/itemloader.h) to be true, or it silently
--      cancels before ever reaching this script -- item 39241's OTB flags
--      were Pickupable+Moveable only. Patched the same way (from-scratch
--      escape-aware OTB parser matching src/fileloader.cpp, full-file
--      round-trip validated). Original preserved at
--      items.otb.bak-before-useable-patch.

local LENS_ID = 39241

local lensAction = Action()

function lensAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if not target or not target:isItem() then
		player:sendTextMessage(MESSAGE_FAILURE, "Use the Dormant Waker on a dormant item.")
		return true
	end

	if target:getTopParent() ~= player then
		player:sendTextMessage(MESSAGE_FAILURE, "You need to be carrying this item.")
		return true
	end

	-- Second use of the same tool: putting an ORDINARY item to sleep. This is
	-- the portable Store alternative to visiting a Dormant Shrine; both paths
	-- share the same helper so their rules cannot drift apart.
	if target:getTier() ~= RarityStats.DORMANT_TIER then
		RarityIdentify.putToSleep(player, target)
		return true
	end

	RarityIdentify.reveal(player, target)
	return true
end

lensAction:id(LENS_ID)
lensAction:allowFarUse(true)
lensAction:register()
