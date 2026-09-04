-- Item Rarity system — Rebirth shared state/helpers. Lives under data/lib
-- (not data/scripts) specifically so it's guaranteed loaded before ANY
-- data/scripts file runs -- data/scripts/creaturescripts/rarity/
-- rarity_rebirth.lua references RarityRebirth.* at its own top-level load
-- time (event registration happens immediately on file load, not deferred to
-- runtime). Same reasoning as why RarityStats/RarityClass live here instead
-- of in data/scripts.
--
-- v2 note: the original design spawned a physical "corpse" item on the
-- downed player's own tile. Fixed after live testing found it caused an
-- unwanted teleport (see git history / BONUS_BACKLOG.md).
--
-- v3 note: v2 used `player:setGhostMode(true)` for the downed visual. Live
-- testing showed this was the wrong tool -- confirmed against
-- src/luaplayer.cpp:2986, setGhostMode makes the player fully invisible to
-- every other non-staff player (sendRemoveTileThing), not translucent --
-- exactly the opposite of "everyone should be able to see the ghost."
-- Replaced with a real outfit change to White Shade (lookType 560, a genuine
-- ghost-type creature already in this datapack --
-- data/monsters/undeads/white_shade.lua), which every player renders
-- normally, restored to the player's real outfit on revive or real death.
--
-- v4 note: v2/v3 also spawned a real ground item (id 30932 "carpet", later
-- 31269 "ankh mosaic") under each of the 8 ring tiles, with a MoveEvent
-- keyed to that item id detecting the qualifying Druid stepping onto one.
-- Dropped entirely per owner feedback -- the static ground graphic looked
-- like furniture/clashed with the pulsing CONST_ME_DIVINE_EMPOWERMENT glow
-- (see pulseHolyTiles below), which alone already reads as the holy marker.
-- Removing the item also incidentally resolves an open risk flagged after
-- the ankh mosaic swap: its walkability was never confirmed (items.xml has
-- no attribute overrides for it, so nothing here could rule out it being
-- solid, which would have both shoved the downed player off-tile AND made
-- the ring physically unwalkable). No ground item, no such risk. The
-- 8 ring positions are still tracked (per downed state), but the step
-- trigger is now a position check (checkStepTrigger below) polled on a fast
-- interval instead of a real MoveEvent onStepIn -- trades a bounded, small
-- detection delay (STEP_CHECK_INTERVAL_MS) for zero dependency on any
-- particular item's client-side rendering/solidity.

RarityRebirth = RarityRebirth or {}
-- [playerId] = { druidId, ringPositions, originalOutfit }
RarityRebirth.downed = RarityRebirth.downed or {}
-- [playerId] = true while finalizeRealDeath's own finishing blow is in
-- flight -- see finalizeRealDeath for why this exists.
RarityRebirth.resolving = RarityRebirth.resolving or {}

RarityRebirth.WINDOW_SECONDS = 60
RarityRebirth.COOLDOWN_SECONDS = 60 -- TEMPORARY: was 45*60, lowered to 1 min
                                    -- for testing per owner's request --
                                    -- restore to 45*60 once testing is done
RarityRebirth.STEP_CHECK_INTERVAL_MS = 400 -- how often checkStepTrigger polls
                                            -- the qualifying Druid's position
                                            -- against the 8 ring tiles --
                                            -- fast enough to feel effectively
                                            -- instant without a real MoveEvent
RarityRebirth.REBIRTH_PATTERN = "[%[%(]Rebirth[%]%)]"
RarityRebirth.MODAL_WINDOW_ID = 9001
RarityRebirth.MODAL_BUTTON_ACCEPT = 1
RarityRebirth.MODAL_BUTTON_DISCARD = 2
RarityRebirth.REVIVE_HEALTH_PERCENT = 50
RarityRebirth.GHOST_OUTFIT = { lookType = 560, lookHead = 0, lookBody = 0, lookLegs = 0, lookFeet = 0, lookAddons = 0, lookMount = 0 }

-- Standard elemental/status damage-over-time conditions -- cleared on a
-- successful revive so coming back doesn't mean immediately dying again to
-- whatever was already ticking.
RarityRebirth.CLEARABLE_CONDITIONS = {
	CONDITION_POISON,
	CONDITION_FIRE,
	CONDITION_ENERGY,
	CONDITION_DROWN,
	CONDITION_FREEZING,
	CONDITION_DAZZLED,
	CONDITION_CURSED,
	CONDITION_BLEEDING,
}

RarityRebirth.RING_OFFSETS = {
	{-1, -1}, {0, -1}, {1, -1},
	{-1,  0},          {1,  0},
	{-1,  1}, {0,  1}, {1,  1},
}

function RarityRebirth.hasRebirthRod(player)
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		if item then
			local desc = item:getSpecialDescription()
			if desc and desc:find(RarityRebirth.REBIRTH_PATTERN) then
				return true
			end
		end
	end
	return false
end

function RarityRebirth.findQualifyingDruid(player)
	for _, member in ipairs(Participants(player, false)) do
		if member and member:isPlayer() and member ~= player and member:getHealth() > 0
				and member:isDruid() and RarityRebirth.hasRebirthRod(member) then
			local cooldownUntil = member:kv():scoped("rarity"):get("rebirth_cooldown_until") or 0
			if cooldownUntil <= os.time() then
				return member
			end
		end
	end
	return nil
end

-- Drops the downed player from every nearby monster's target so aggro
-- redistributes to the rest of the party instead of monsters continuing to
-- swing at a target that can no longer take damage.
function RarityRebirth.dropAggro(creature)
	local spectators = Game.getSpectators(creature:getPosition(), false, false, 8, 8, 8, 8)
	for _, spectator in ipairs(spectators) do
		if spectator:isMonster() and spectator:getTarget() == creature then
			spectator:removeTarget(creature)
			spectator:searchTarget()
		end
	end
end

-- A single dropAggro() call only catches monsters targeting the player at
-- that exact instant -- a monster with no other target can simply re-select
-- the downed player moments later, since they're still a real, physically
-- present Creature in the world (just health-immune). This re-runs dropAggro
-- every second for as long as the player is actually still downed, so any
-- monster that reacquires them gets stripped again almost immediately
-- instead of just once at the start of the window.
function RarityRebirth.startAggroDropLoop(playerId)
	if not RarityRebirth.downed[playerId] then
		return
	end
	local player = Player(playerId)
	if player then
		RarityRebirth.dropAggro(player)
	end
	addEvent(RarityRebirth.startAggroDropLoop, 1000, playerId)
end

-- Layers a recurring divine-empowerment-style glow across the 8 ring
-- positions for as long as the player is downed. CONST_ME_DIVINE_EMPOWERMENT
-- is the exact effect real Tibia's Paladin Wheel-of-Destiny perk of the same
-- name uses, confirmed real and registered in this fork (src/const.h) but
-- unused anywhere else in data/. This is now the *only* visual marking the
-- ring (see v4 note above) -- no ground item underneath it anymore.
RarityRebirth.PULSE_INTERVAL_MS = 1500
function RarityRebirth.pulseHolyTiles(playerId)
	local state = RarityRebirth.downed[playerId]
	if not state then
		return
	end
	for _, ringPos in ipairs(state.ringPositions or {}) do
		ringPos:sendMagicEffect(CONST_ME_DIVINE_EMPOWERMENT)
	end
	addEvent(RarityRebirth.pulseHolyTiles, RarityRebirth.PULSE_INTERVAL_MS, playerId)
end

-- Removes every condition in CLEARABLE_CONDITIONS from a player, if present.
function RarityRebirth.clearNegativeConditions(player)
	for _, conditionType in ipairs(RarityRebirth.CLEARABLE_CONDITIONS) do
		if player:hasCondition(conditionType) then
			player:removeCondition(conditionType)
		end
	end
end

-- Polls the specific Druid recorded at downing-time (not just any qualifying
-- Druid -- matches the original MoveEvent design, which only ever checked
-- findDownedStateFor(druid) against that one recorded druidId) against the
-- 8 ring positions. Re-checks the rod/cooldown at trigger time (not just at
-- downing-time), since either can change during the 60s window. Replaces the
-- old MoveEvent onStepIn -- see v4 note at the top of this file.
function RarityRebirth.checkStepTrigger(playerId)
	local state = RarityRebirth.downed[playerId]
	if not state then
		return
	end

	local druid = Player(state.druidId)
	if druid and RarityRebirth.hasRebirthRod(druid) then
		local cooldownUntil = druid:kv():scoped("rarity"):get("rebirth_cooldown_until") or 0
		if cooldownUntil <= os.time() then
			local druidPos = druid:getPosition()
			for _, ringPos in ipairs(state.ringPositions) do
				if druidPos.x == ringPos.x and druidPos.y == ringPos.y and druidPos.z == ringPos.z then
					RarityRebirth.reviveDownedPlayer(playerId, druid)
					return
				end
			end
		end
	end

	addEvent(RarityRebirth.checkStepTrigger, RarityRebirth.STEP_CHECK_INTERVAL_MS, playerId)
end

-- The actual revive: clears the downed state, restores movement/icon/outfit,
-- clears negative conditions, heals to REVIVE_HEALTH_PERCENT, starts the
-- Druid's cooldown, and messages both players. Called only from
-- checkStepTrigger, which has already re-validated the rod/cooldown.
function RarityRebirth.reviveDownedPlayer(playerId, druid)
	local state = RarityRebirth.downed[playerId]
	if not state then
		return
	end

	local downedPlayer = Player(playerId)
	if not downedPlayer then
		RarityRebirth.downed[playerId] = nil
		return
	end

	RarityRebirth.downed[playerId] = nil

	downedPlayer:setMovementBlocked(false)
	downedPlayer:removeIcon("rarity-downed")
	if state.originalOutfit then
		downedPlayer:setOutfit(state.originalOutfit)
	end
	RarityRebirth.clearNegativeConditions(downedPlayer)
	downedPlayer:setHealth(math.max(1, math.floor(downedPlayer:getMaxHealth() * RarityRebirth.REVIVE_HEALTH_PERCENT / 100)))
	downedPlayer:getPosition():sendMagicEffect(CONST_ME_HOLYAREA)

	druid:kv():scoped("rarity"):set("rebirth_cooldown_until", os.time() + RarityRebirth.COOLDOWN_SECONDS)
	druid:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You channel Rebirth and revive " .. downedPlayer:getName() .. "! Be careful, they're at " .. RarityRebirth.REVIVE_HEALTH_PERCENT .. "% health.")
	downedPlayer:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have been revived by " .. druid:getName() .. "! Be alert -- you're at " .. RarityRebirth.REVIVE_HEALTH_PERCENT .. "% health.")
end

-- Clears the downed state and lets the deferred lethal blow finally land for
-- real. Called either by the 60s expiry timer, the downed player's !accept
-- talkaction, or the "Accept Death" button on their Rebirth modal window.
function RarityRebirth.finalizeRealDeath(playerId)
	local state = RarityRebirth.downed[playerId]
	if not state then
		return
	end
	RarityRebirth.downed[playerId] = nil

	local player = Player(playerId)
	if not player or not player:isPlayer() then
		return
	end

	player:setMovementBlocked(false)
	player:removeIcon("rarity-downed")
	if state.originalOutfit then
		player:setOutfit(state.originalOutfit)
	end

	-- This finishing blow goes through the exact same combat pipeline as any
	-- other hit, which means it fires onPrepareDeath again -- and by this
	-- point RarityRebirth.downed[playerId] is already nil, so without this
	-- guard the handler would fall through to findQualifyingDruid and could
	-- re-trigger Rebirth on its own finishing blow (new tiles, ghost outfit
	-- reapplied, death never actually completing). resolving[] short-
	-- circuits onPrepareDeath unconditionally for this one hit.
	RarityRebirth.resolving[playerId] = true
	player:addHealth(-(player:getHealth() + 1))
	RarityRebirth.resolving[playerId] = nil
end
