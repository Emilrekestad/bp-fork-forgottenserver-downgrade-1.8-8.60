-- World Missions — read/write layer. Mirrors bao_state.lua's split from
-- bao_config.lua, except the persistence layer underneath is deliberately
-- different: Bao's rank/mastery state is per-player
-- (player:kv():scoped("bao")), World Missions state is server-wide
-- (Game.getStorageValue/setStorageValue), since nobody "owns" a World
-- Mission the way a player owns their own hunt progress.

-- Succession: a mission with a `prerequisite` doesn't exist to players (or
-- accumulate progress) until that prerequisite mission is applied --
-- "Oramond starts when Liberty Bay is unlocked," per the owner's spec.
-- Every progress-contributing hook (Cull's kill listener, Delivery's
-- deliverItem, Activation's activateObject, the Presence poller) and
-- Bender Shun's own dialogue both check this before doing anything, so a
-- kill/delivery/lever-pull that happens to match a not-yet-revealed
-- mission is silently ignored rather than banked early.
function WorldMissions.isRevealed(missionId)
	local mission = WorldMissions.Missions[missionId]
	if not mission then
		return false
	end
	return mission.prerequisite == nil or WorldMissions.isApplied(mission.prerequisite)
end

-- Every non-delivery, non-composite type's progress collapses to one
-- number compared against threshold -- Cull/Activation add to it
-- incrementally as kills/objects come in, Presence's poller
-- (worldmissions_presence.lua) jumps it straight to threshold the moment
-- enough players are simultaneously in the Zone, since there's no
-- meaningful "partial progress" for a coordination check. Delivery tracks
-- progress per-item instead (see getItemProgress below) since a mission
-- can require several different items at once. Composite doesn't use
-- either -- see isThresholdMet below.
function WorldMissions.getProgress(missionId)
	local mission = WorldMissions.Missions[missionId]
	if not mission or not mission.progressStorage then
		return 0
	end
	return math.max(0, Game.getStorageValue(mission.progressStorage) or 0)
end

-- Every real mutation in this file (setProgress, addItemProgress,
-- activateObject) ends with a call to applyPendingCompletions() (defined
-- below) -- completion is checked and applied THE INSTANT a threshold is
-- crossed, not deferred to the next scheduled server save (per owner's
-- explicit call -- see that function's own comment for the reasoning and
-- history). That same call also handles persistence: Game.setStorageValue()
-- only ever touches an in-memory map (src/game.cpp:8854);
-- Game.saveStorageValues() is a SEPARATE call that flushes it to the
-- `game_storage` DB table, and boot only ever reads FROM that table
-- (src/game.cpp:8815 loadGameStorageValues, called once at startup) --
-- without an explicit save after every mutation, any progress made since
-- the last save would be silently lost on the next server restart, a real
-- risk given how often this project's server gets restarted for routine
-- deploys. applyPendingCompletions() already does that save unconditionally
-- at its end, so calling it after every mutation solves both problems with
-- one call.
function WorldMissions.setProgress(missionId, value)
	local mission = WorldMissions.Missions[missionId]
	if not mission or not mission.progressStorage then
		return
	end
	Game.setStorageValue(mission.progressStorage, value)
	WorldMissions.applyPendingCompletions()
end

function WorldMissions.addProgress(missionId, amount)
	if not amount or amount == 0 then
		return
	end
	WorldMissions.setProgress(missionId, WorldMissions.getProgress(missionId) + amount)
end

-- Delivery only: per-item progress, since a single delivery mission (e.g.
-- Roshamuul) can require several different materials at once, each with
-- its own threshold and its own progressStorage cell (see
-- worldmissions_config.lua's `items` list on that mission).
function WorldMissions.getItemProgress(missionId, itemId)
	local mission = WorldMissions.Missions[missionId]
	if not mission or not mission.items then
		return 0
	end
	for _, entry in ipairs(mission.items) do
		if entry.itemId == itemId then
			return math.max(0, Game.getStorageValue(entry.progressStorage) or 0)
		end
	end
	return 0
end

function WorldMissions.addItemProgress(missionId, itemId, amount)
	local mission = WorldMissions.Missions[missionId]
	if not mission or not mission.items or not amount or amount == 0 then
		return
	end
	for _, entry in ipairs(mission.items) do
		if entry.itemId == itemId then
			Game.setStorageValue(entry.progressStorage, WorldMissions.getItemProgress(missionId, itemId) + amount)
			WorldMissions.applyPendingCompletions()
			return
		end
	end
end

-- Has this mission's onComplete actually fired -- distinct from
-- threshold-met, kept as two separate steps (rather than collapsing them
-- into one) purely so onComplete can never double-fire even though it's
-- now triggered instantly (see applyPendingCompletions below) rather than
-- on a schedule. A locked gate checks THIS, never isThresholdMet directly.
function WorldMissions.isApplied(missionId)
	local mission = WorldMissions.Missions[missionId]
	if not mission or not mission.appliedStorage then
		return false
	end
	return (Game.getStorageValue(mission.appliedStorage) or 0) > 0
end

function WorldMissions.isThresholdMet(missionId)
	local mission = WorldMissions.Missions[missionId]
	if not mission then
		return false
	end

	if mission.type == "composite" then
		for _, subId in ipairs(mission.requiredMissions or {}) do
			if not WorldMissions.isApplied(subId) then
				return false
			end
		end
		return true
	end

	if mission.type == "delivery" then
		for _, entry in ipairs(mission.items or {}) do
			if WorldMissions.getItemProgress(missionId, entry.itemId) < entry.threshold then
				return false
			end
		end
		return true
	end

	return WorldMissions.getProgress(missionId) >= (mission.threshold or math.huge)
end

-- Activation only: has this SPECIFIC object already been triggered.
-- Keyed by missionId + its index in the mission's objects list, so
-- re-pressing an already-activated lever/statue is a harmless no-op
-- instead of inflating the count. Reuses the same appliedStorage-style
-- numeric flag convention, offset from the mission's own appliedStorage
-- by the object's index.
function WorldMissions.isObjectActivated(missionId, objectIndex)
	local mission = WorldMissions.Missions[missionId]
	if not mission or not mission.appliedStorage then
		return false
	end
	return (Game.getStorageValue(mission.appliedStorage + objectIndex) or 0) > 0
end

function WorldMissions.activateObject(player, missionId, objectIndex)
	local mission = WorldMissions.Missions[missionId]
	if not mission or mission.type ~= "activation" or not WorldMissions.isRevealed(missionId) then
		return false
	end
	if WorldMissions.isApplied(missionId) or WorldMissions.isObjectActivated(missionId, objectIndex) then
		return false
	end

	Game.setStorageValue(mission.appliedStorage + objectIndex, 1)
	WorldMissions.addProgress(missionId, 1)
	if player then
		player:getPosition():sendMagicEffect(CONST_ME_HOLYAREA)
	end
	return true
end

-- Delivery only: hands in `count` of `itemId` from the player's inventory
-- toward `missionId`, if that mission is a delivery type still accepting
-- it. Generic -- not tied to Shun specifically, any NPC/Action can call
-- this the same way Shun's own "tithe" keyword does
-- (data/npc/scripts/Bender Shun.lua).
function WorldMissions.deliverItem(player, missionId, itemId, count)
	local mission = WorldMissions.Missions[missionId]
	if not mission or mission.type ~= "delivery" or not WorldMissions.isRevealed(missionId) then
		return false
	end
	if WorldMissions.isApplied(missionId) then
		return false
	end

	local matched = false
	for _, entry in ipairs(mission.items or {}) do
		if entry.itemId == itemId then
			matched = true
			break
		end
	end
	if not matched then
		return false
	end

	count = count or 1
	if not player:removeItem(itemId, count) then
		return false
	end

	WorldMissions.addItemProgress(missionId, itemId, count)
	return true
end

-- The actual completion check. Originally designed to only run at the
-- real daily ServerSave GlobalEvent (data/scripts/globalevents/
-- serversave.lua, 09:55 server time) -- changed after live testing:
-- pulling Liberty Bay's 4th lever produced no visible reaction until the
-- next save, which read as "broken" rather than "deliberately delayed."
-- Per owner's explicit correction, completion now fires instantly --
-- every mutation in this file (setProgress/addItemProgress above) calls
-- this function directly the moment it changes anything, rather than
-- waiting to be picked up on a schedule. The ServerSave/startup
-- GlobalEvent calls to this function (worldmissions_serversave.lua,
-- worldmissions_startup.lua) are now a harmless redundant safety net,
-- not the primary trigger. onComplete only ever runs from here or
-- reapplyOnBoot below, never directly from a progress update, so it can
-- never double-fire.
function WorldMissions.applyPendingCompletions()
	for missionId, mission in pairs(WorldMissions.Missions) do
		if WorldMissions.isRevealed(missionId) and not WorldMissions.isApplied(missionId) and WorldMissions.isThresholdMet(missionId) then
			if mission.onComplete then
				mission.onComplete()
			end
			Game.setStorageValue(mission.appliedStorage, 1)
			Game.broadcastMessage(
				mission.completeMessage or ("A world mission has been completed: " .. (mission.name or missionId) .. "."),
				MESSAGE_EVENT_ORANGE
			)
		end
	end
	Game.saveStorageValues()
end

-- Called once from worldmissions_startup.lua (a real "startup" GlobalEvent
-- type, same shape as data/scripts/globalevents/#startup.lua). Re-runs
-- onComplete for every ALREADY-applied mission, silently, no broadcast --
-- a live Tile:addItem/remove edit only exists in server memory and does
-- not survive a restart on its own (no Game.saveMap() binding in this
-- fork), so anything already complete needs repainting on every boot.
function WorldMissions.reapplyOnBoot()
	for missionId, mission in pairs(WorldMissions.Missions) do
		if WorldMissions.isApplied(missionId) and mission.onComplete then
			mission.onComplete()
		end
	end
end

-- Activation-specific boot repaint: places (or corrects) each object's
-- physical item at its exact position, every boot, regardless of whether
-- the overall mission is applied yet -- distinct from reapplyOnBoot above,
-- which only concerns itself with a mission's final onComplete payoff.
-- A lever that's already been pulled needs to keep SHOWING pulled
-- (itemOn) across a restart even while the mission overall is still
-- pending; a lever never placed at all (first boot ever) needs creating
-- from nothing. Game.createItem/Item:transform are both real, confirmed
-- bindings (src/luagame.cpp, src/luaitem.cpp).
function WorldMissions.reapplyActivationVisuals()
	for missionId, mission in pairs(WorldMissions.Missions) do
		if mission.type == "activation" and WorldMissions.isRevealed(missionId) then
			for index, object in ipairs(mission.objects or {}) do
				local activated = WorldMissions.isObjectActivated(missionId, index)
				local wantId = activated and object.itemOn or object.itemOff
				local tile = Tile(object.pos)
				if tile then
					local existing = tile:getItemById(object.itemOff) or tile:getItemById(object.itemOn)
					if existing then
						if existing:getId() ~= wantId then
							existing:transform(wantId)
						end
					else
						Game.createItem(wantId, 1, object.pos)
					end
				end
			end
		end
	end
end
