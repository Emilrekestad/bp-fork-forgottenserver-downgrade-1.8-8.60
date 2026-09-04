-- Item Rarity system — Rebirth. Ultra-rare Legendary-only bonus on Class 5+
-- Druid rods (see stats[36] in rarity_stats.lua) that lets a party's Druid
-- save a dying member instead of letting the killing blow land. Shared
-- state/helpers live in data/lib/rarity/rarity_rebirth.lua (RarityRebirth) --
-- this file is just the CreatureEvent wiring.
--
-- Uses this fork's native CREATURE_EVENT_PREPAREDEATH hook (confirmed real:
-- src/creatureevent.h:21, fired from src/game.cpp:6993-6998 right before a
-- lethal hit's damage would apply). Returning false from onPrepareDeath
-- vetoes that hit entirely -- the damage never lands, so there is no real
-- death and no way to "hold open" a native death penalty afterward (TFS
-- applies skill/XP loss and the temple teleport natively, non-deferrable
-- from Lua once real death starts). Everything here is therefore a
-- *simulated* downed state, not a real corpse-and-revive.

local prepareDeath = CreatureEvent("RarityRebirthDeath")
function prepareDeath.onPrepareDeath(creature, killer)
	if not creature:isPlayer() then
		return true
	end

	local playerId = creature:getId()
	if RarityRebirth.resolving[playerId] then
		-- finalizeRealDeath's own finishing blow -- let it through
		-- unconditionally, never re-evaluate Rebirth for it.
		return true
	end

	if RarityRebirth.downed[playerId] then
		-- Already downed and the window hasn't resolved yet -- at 1 HP,
		-- almost any further hit re-qualifies as "lethal" and re-fires this
		-- same handler, so simply re-vetoing here is what keeps the player
		-- fully protected until revived, accepted, or the window times out.
		return false
	end

	local druid = RarityRebirth.findQualifyingDruid(creature)
	if not druid then
		return true
	end

	local originalOutfit = creature:getOutfit()

	creature:setHealth(1)
	creature:setMovementBlocked(true)
	creature:setIcon("rarity-downed", 0, CreatureIconQuests_RedCross, 1)
	creature:setOutfit(RarityRebirth.GHOST_OUTFIT)

	-- No ground item spawned for the ring anymore (see v4 note in
	-- rarity_rebirth.lua) -- just the 8 positions, walked by
	-- checkStepTrigger and lit up by pulseHolyTiles.
	local position = creature:getPosition()
	local ringPositions = {}
	for _, offset in ipairs(RarityRebirth.RING_OFFSETS) do
		local tilePos = Position(position.x + offset[1], position.y + offset[2], position.z)
		if Tile(tilePos) then
			table.insert(ringPositions, tilePos)
		end
	end
	position:sendMagicEffect(CONST_ME_HOLYAREA)

	RarityRebirth.downed[playerId] = {
		druidId = druid:getId(),
		ringPositions = ringPositions,
		originalOutfit = originalOutfit,
	}
	RarityRebirth.startAggroDropLoop(playerId)
	RarityRebirth.pulseHolyTiles(playerId)
	RarityRebirth.checkStepTrigger(playerId)

	local window = ModalWindow(RarityRebirth.MODAL_WINDOW_ID, "Rebirth",
		"You still got a chance! " .. druid:getName() .. " might be on their way!\n\n" ..
		"You have 60 seconds. If nobody reaches you in time, or you'd rather not wait, you can accept your fate now. " ..
		"Discard just closes this window without deciding anything.")
	window:addButton(RarityRebirth.MODAL_BUTTON_ACCEPT, "Accept Death")
	window:addButton(RarityRebirth.MODAL_BUTTON_DISCARD, "Discard")
	-- Both Enter and Escape default to Discard, not Accept Death -- an
	-- irreversible action should never be the accidental keypress.
	window:setDefaultEnterButton(RarityRebirth.MODAL_BUTTON_DISCARD)
	window:setDefaultEscapeButton(RarityRebirth.MODAL_BUTTON_DISCARD)
	window:sendToPlayer(creature)

	druid:sendTextMessage(MESSAGE_EVENT_ADVANCE, creature:getName() .. " has fallen. Step onto the holy ground to revive them before it fades.")

	addEvent(RarityRebirth.finalizeRealDeath, RarityRebirth.WINDOW_SECONDS * 1000, playerId)

	return false
end
prepareDeath:register()
