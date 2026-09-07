-- Global Server Boosts.
--
-- Every boost in this system is SERVER-WIDE, not per-character: one player
-- pays, everybody online benefits. That single fact drives the whole design
-- and is why none of this lives in player storage.
--
-- Three consequences worth stating up front, because they are easy to get
-- wrong when porting a per-player boost into this shape:
--
-- 1. State is one row per boost in `server_boosts`, written through on every
--    change. `Game.setStorageValue` was the obvious candidate and is wrong
--    here: game storage is only flushed to `game_storage` on a server save
--    (Game::saveGameStorageValues), so a crash between saves would silently
--    void boost time real money paid for. A boost is a receipt, so it gets a
--    real table and a synchronous write.
--
--    A RUNNING BOOST MUST NEVER BE LOST, and two independent mechanisms cover
--    that. The daily server save does not restart the process on this server
--    (`serverSaveShutdown = false`, `serverSaveClose = true`), so it only
--    closes the gate, calls saveServer() and reopens -- the Lua state, and
--    therefore `state` below, is never touched, and players who get kicked by
--    the CLOSED gate have their conditions reapplied by boosts_login.lua when
--    they return. For everything that DOES end the process -- a crash, a
--    manual restart, a deploy, or flipping serverSaveShutdown to true --
--    `expiresAt` is stored as an absolute unix timestamp, so
--    GlobalBoosts.load() at startup restores exactly the time that was left,
--    with no heartbeat write needed while the server runs. Never change
--    expiresAt to a remaining-seconds countdown; that is what would make a
--    restart lossy.
--
-- 2. Effects split into two kinds, and they are applied differently.
--    * PULL effects (experience, spawn, loot) are read at the moment the
--      event fires -- nothing is stored on the player, so a player who logs
--      in mid-boost is covered automatically and there is nothing to clean
--      up on expiry.
--    * PUSH effects (speed, regeneration) are engine conditions and must be
--      physically added to every online player on activation, added again on
--      every login while active, and removed from everyone on expiry. Each
--      owns a private CONDITION_PARAM_SUBID (see below) so it stacks
--      alongside -- rather than overwriting -- haste spells, wheel bonuses
--      and the food regeneration condition, all of which live on the same
--      (type, CONDITIONID_DEFAULT) key. Confirmed against
--      Creature::addCondition (src/creature.cpp:1427), which looks an
--      existing condition up by (type, id, subId).
--
-- 3. Purchases EXTEND rather than restart. `expiresAt` is clamped forward by
--    the offer's duration, capped at MAX_STACK_SECONDS. The cap exists so a
--    single whale cannot park a boost for a week: the timer has to be
--    visibly running down for anyone to feel the need to top it up, which is
--    the entire point of the mechanic.

GlobalBoosts = GlobalBoosts or {}

-- Condition subIds. Deliberately in their own block, clear of everything else
-- in this datapack that claims one (rarity=1, mentor=3000, battlepass=43000/
-- 44000, wheel=86061, monster spells=88888).
local SUBID_SPEED = 91001
local SUBID_REGEN = 91002

-- Wire ids. These are part of the client protocol (opcode 0x56) -- the client
-- maps them to an icon and an accent colour. Never renumber an existing one;
-- append instead.
GlobalBoosts.ID = {
	EXPERIENCE = 1,
	SPEED = 2,
	SPAWN = 3,
	REGENERATION = 4,
	LOOT = 5,
	RARE = 6,
}

-- How long a boost can be stacked ahead, in seconds. 12 hours = 24 purchases
-- of the standard 30-minute grant.
--
-- The protocol sends this as a U16 (boosts_protocol.lua), and so is remaining
-- time -- 43200 is comfortably inside 65535, but anything above 18h12m is not.
-- Raising this past that needs a wire change, not just a number here.
GlobalBoosts.MAX_STACK_SECONDS = 12 * 60 * 60

-- `fade` is the world-flavoured line broadcast when a boost runs out. It is
-- deliberately the ONLY expiry messaging in the system: an earlier version
-- also warned the server at 5 and 1 minutes remaining, which read as a nag
-- and made the HUD countdown redundant. The countdown pill is where urgency
-- belongs; this is the world noticing, after the fact.
GlobalBoosts.Types = {
	[GlobalBoosts.ID.EXPERIENCE] = {
		key = "experience",
		name = "Experience Boost",
		short = "Exp",
		effect = "+50% experience for every player online",
		fade = "The Experience Boost has faded. The world grows harsh again.",
		-- Percent added to all monster experience. Kept deliberately modest:
		-- this stacks on top of stages, stamina, prey and influenced
		-- multipliers, all of which are already multiplicative.
		magnitude = 50,
	},
	[GlobalBoosts.ID.SPEED] = {
		key = "speed",
		name = "Speed Boost",
		short = "Haste",
		effect = "+60 speed for every player online",
		fade = "The Speed Boost has faded. Your feet grow heavy once more.",
		-- CONDITION_PARAM_SPEED is an absolute speed-point delta, not a
		-- percentage (rarity_loot_drop.lua documents the same trap).
		magnitude = 60,
		push = true,
	},
	[GlobalBoosts.ID.SPAWN] = {
		key = "spawn",
		name = "Spawn Boost",
		short = "Spawn",
		effect = "1.5x monster spawns across the world",
		fade = "The Spawn Boost has faded. The wilds fall quiet again.",
		-- Percent chance that a natural spawn is doubled. 50 => 1.5x.
		magnitude = 50,
	},
	[GlobalBoosts.ID.REGENERATION] = {
		key = "regeneration",
		name = "Regeneration Boost",
		short = "Reg",
		effect = "2x health and mana regeneration",
		fade = "The Regeneration Boost has faded. Your wounds close slowly again.",
		-- Multiplier expressed in percent: 100 means "one extra copy of the
		-- vocation's own regeneration", i.e. 2x total.
		magnitude = 100,
		push = true,
	},
	[GlobalBoosts.ID.LOOT] = {
		key = "loot",
		name = "Loot Boost",
		short = "Loot",
		effect = "+25% chance of an extra roll on every drop",
		fade = "The Loot Boost has faded. The dead guard their treasures once more.",
		magnitude = 25,
	},
	[GlobalBoosts.ID.RARE] = {
		key = "rare",
		name = "Rarity Boost",
		short = "Rare",
		effect = "+50% chance for looted equipment to roll a rarity tier",
		fade = "The Rarity Boost has faded. Fortune turns her back once more.",
		-- Percent added to EVERY rarity tier's roll threshold, so Scarce
		-- through Prime all get proportionally likelier rather than the boost
		-- only widening the common end. Applied in RarityStats.rollRarity by
		-- dividing the 1..10000 roll, which is arithmetically identical to
		-- scaling all four thresholds and touches one line instead of four.
		magnitude = 50,
	},
}

GlobalBoosts.ByKey = {}
for id, boost in pairs(GlobalBoosts.Types) do
	boost.id = id
	GlobalBoosts.ByKey[boost.key] = boost
end

-- Live state, keyed by boost id: {expiresAt = unix, contributor = name}.
-- Authoritative in memory; `server_boosts` is the durable mirror, read once at
-- startup and written through on every change.
--
-- Parked on the GlobalBoosts table rather than being a plain file-local for
-- the same reason broadcastState is guarded below: src/signals.cpp:112 can
-- re-run this file without re-running the startup globalevent that calls
-- load(), and a fresh empty local would drop every running boost out of
-- memory while its paid-for row sat in `server_boosts` doing nothing. Cleared
-- IN PLACE by load(), never rebound.
GlobalBoosts._state = GlobalBoosts._state or {}
local state = GlobalBoosts._state

local schemaReady = false

-- ─── Persistence ────────────────────────────────────────────────────────

function GlobalBoosts.ensureSchema()
	if schemaReady then
		return
	end

	db.query([[
		CREATE TABLE IF NOT EXISTS `server_boosts` (
			`boost` VARCHAR(32) NOT NULL,
			`expires_at` INT UNSIGNED NOT NULL DEFAULT 0,
			`contributor` VARCHAR(64) NOT NULL DEFAULT '',
			`total_seconds` BIGINT UNSIGNED NOT NULL DEFAULT 0,
			`purchases` INT UNSIGNED NOT NULL DEFAULT 0,
			PRIMARY KEY (`boost`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
	]])

	schemaReady = true
end

local function persist(boost, entry, addedSeconds)
	GlobalBoosts.ensureSchema()

	addedSeconds = tonumber(addedSeconds) or 0
	local purchase = addedSeconds > 0 and 1 or 0

	db.query(string.format([[
		INSERT INTO `server_boosts` (`boost`, `expires_at`, `contributor`, `total_seconds`, `purchases`)
		VALUES (%s, %d, %s, %d, %d)
		ON DUPLICATE KEY UPDATE
			`expires_at` = VALUES(`expires_at`),
			`contributor` = VALUES(`contributor`),
			`total_seconds` = `total_seconds` + %d,
			`purchases` = `purchases` + %d
	]],
		db.escapeString(boost.key),
		math.max(0, math.floor(entry.expiresAt or 0)),
		db.escapeString(entry.contributor or ""),
		addedSeconds, purchase,
		addedSeconds, purchase
	))
end

-- Reads `server_boosts` back into memory. Rows whose deadline has already
-- passed while the server was down are dropped rather than resurrected.
function GlobalBoosts.load()
	GlobalBoosts.ensureSchema()

	-- Cleared in place: `state` is an alias for GlobalBoosts._state, and
	-- rebinding it here would leave every other function in this file pointing
	-- at the old table.
	for id in pairs(state) do
		state[id] = nil
	end

	local now = os.time()

	local resultId = db.storeQuery("SELECT `boost`, `expires_at`, `contributor` FROM `server_boosts`")
	if resultId ~= false then
		repeat
			local boost = GlobalBoosts.ByKey[result.getString(resultId, "boost")]
			local expiresAt = result.getNumber(resultId, "expires_at")
			if boost and expiresAt > now then
				state[boost.id] = {
					expiresAt = expiresAt,
					contributor = result.getString(resultId, "contributor"),
				}
			end
		until not result.next(resultId)
		result.free(resultId)
	end

	return state
end

-- ─── Queries ────────────────────────────────────────────────────────────

function GlobalBoosts.remaining(boostId)
	local entry = state[boostId]
	if not entry then
		return 0
	end
	return math.max(0, entry.expiresAt - os.time())
end

function GlobalBoosts.isActive(boostId)
	return GlobalBoosts.remaining(boostId) > 0
end

function GlobalBoosts.contributor(boostId)
	local entry = state[boostId]
	return entry and entry.contributor or ""
end

-- The multiplier/percentage a hook should apply right now, or 0 when the
-- boost is off. Every PULL effect goes through this one accessor so there is
-- a single place where "is it on" is decided.
function GlobalBoosts.magnitude(boostId)
	if not GlobalBoosts.isActive(boostId) then
		return 0
	end
	local boost = GlobalBoosts.Types[boostId]
	if not boost then
		return 0
	end
	-- The console can override what a boost is worth without a restart. The
	-- table above stays the documented default; the knob wins when set.
	if Tuning then
		local override = Tuning.get("boost." .. boost.key .. ".magnitude")
		if override ~= nil then
			return override
		end
	end
	return boost.magnitude
end

-- Every currently-running boost, ordered by id so the client HUD keeps a
-- stable row order instead of reshuffling on each push.
function GlobalBoosts.active()
	local list = {}
	for id, boost in pairs(GlobalBoosts.Types) do
		local remaining = GlobalBoosts.remaining(id)
		if remaining > 0 then
			list[#list + 1] = {
				id = id,
				boost = boost,
				remaining = remaining,
				contributor = GlobalBoosts.contributor(id),
			}
		end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

-- ─── Formatting ─────────────────────────────────────────────────────────

function GlobalBoosts.formatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if hours > 0 then
		if minutes > 0 then
			return string.format("%d hour%s %d minute%s", hours, hours ~= 1 and "s" or "",
				minutes, minutes ~= 1 and "s" or "")
		end
		return string.format("%d hour%s", hours, hours ~= 1 and "s" or "")
	end

	if minutes > 0 then
		return string.format("%d minute%s", minutes, minutes ~= 1 and "s" or "")
	end

	return string.format("%d second%s", seconds, seconds ~= 1 and "s" or "")
end

-- ─── Condition effects (PUSH) ───────────────────────────────────────────

local function speedCondition(magnitude)
	local condition = Condition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT)
	condition:setParameter(CONDITION_PARAM_SUBID, SUBID_SPEED)
	condition:setParameter(CONDITION_PARAM_TICKS, -1)
	condition:setParameter(CONDITION_PARAM_SPEED, magnitude)
	return condition
end

-- Grants one extra copy of the player's OWN vocation regeneration, at the
-- vocation's own interval, as a second CONDITION_REGENERATION on a private
-- subId -- so it genuinely doubles the rate rather than replacing it.
--
-- CONDITION_PARAM_HEALTHGAINPERCENT is NOT used and cannot be: it adds a flat
-- amount derived from max health inside its own regeneration source rather
-- than scaling the existing one, so "+100%" through it would mean something
-- quite different per vocation (this datapack already documents the same trap
-- in lib/bao/bao_ledger.lua's iron_constitution entry).
--
-- Known, accepted over-delivery: the vocation's base regeneration only ticks
-- while the food condition is up, this copy ticks regardless. An unfed player
-- therefore regenerates at 1x instead of 0x while the boost runs. Protection
-- zones still suppress it -- that check is inside the engine's
-- ConditionRegeneration::executeCondition, not here.
local function regenCondition(player, magnitude)
	local vocation = player:getVocation()
	if not vocation then
		return nil
	end

	local scale = magnitude / 100
	local healthGain = math.floor(vocation:getHealthGainAmount() * scale)
	local manaGain = math.floor(vocation:getManaGainAmount() * scale)
	if healthGain <= 0 and manaGain <= 0 then
		return nil
	end

	local condition = Condition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	condition:setParameter(CONDITION_PARAM_SUBID, SUBID_REGEN)
	condition:setParameter(CONDITION_PARAM_TICKS, -1)
	condition:setParameter(CONDITION_PARAM_HEALTHGAIN, healthGain)
	condition:setParameter(CONDITION_PARAM_HEALTHTICKS, vocation:getHealthGainTicks() * 1000)
	condition:setParameter(CONDITION_PARAM_MANAGAIN, manaGain)
	condition:setParameter(CONDITION_PARAM_MANATICKS, vocation:getManaGainTicks() * 1000)
	return condition
end

-- Brings one player's conditions in line with the current global state.
-- Idempotent by construction: every push effect is removed first, then
-- re-added only if its boost is live. Safe to call on login, on activation,
-- on expiry, and on a GM reload.
function GlobalBoosts.syncPlayer(player)
	if not player then
		return
	end

	player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, SUBID_SPEED, true)
	player:removeCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT, SUBID_REGEN, true)

	local speed = GlobalBoosts.magnitude(GlobalBoosts.ID.SPEED)
	if speed > 0 then
		player:addCondition(speedCondition(speed))
	end

	local regen = GlobalBoosts.magnitude(GlobalBoosts.ID.REGENERATION)
	if regen > 0 then
		local condition = regenCondition(player, regen)
		if condition then
			player:addCondition(condition)
		end
	end
end

function GlobalBoosts.syncAllPlayers()
	for _, player in ipairs(Game.getPlayers()) do
		GlobalBoosts.syncPlayer(player)
	end
end

-- ─── Mutation ───────────────────────────────────────────────────────────

-- Extends (or starts) a boost. Returns true plus "activated"/"extended" and
-- the new remaining time, or false plus a player-facing reason.
--
-- The caller takes payment only after this returns true.
function GlobalBoosts.extend(boostId, seconds, contributorName)
	local boost = GlobalBoosts.Types[boostId]
	if not boost then
		return false, "Unknown boost."
	end

	seconds = math.floor(tonumber(seconds) or 0)
	if seconds <= 0 then
		return false, "Invalid boost duration."
	end

	local now = os.time()
	local entry = state[boostId]
	local wasActive = entry ~= nil and entry.expiresAt > now
	local base = wasActive and entry.expiresAt or now

	if base + seconds > now + GlobalBoosts.MAX_STACK_SECONDS then
		-- "maximum of 12 hours", not "its 12 hours maximum" -- formatDuration
		-- pluralises, so it can only sit in a noun slot, never an adjectival one.
		return false, string.format(
			"The %s is already stacked to its maximum of %s. Wait for it to run down before extending it again.",
			boost.name, GlobalBoosts.formatDuration(GlobalBoosts.MAX_STACK_SECONDS))
	end

	if not wasActive then
		entry = {}
		state[boostId] = entry
	end

	entry.expiresAt = base + seconds
	entry.contributor = tostring(contributorName or "")

	local remaining = entry.expiresAt - now

	persist(boost, entry, seconds)

	if boost.push then
		GlobalBoosts.syncAllPlayers()
	end

	local verb = wasActive and "extended" or "activated"
	Game.broadcastMessage(string.format("%s has %s the %s. %s remaining.",
		entry.contributor ~= "" and entry.contributor or "Someone",
		verb, boost.name, GlobalBoosts.formatDuration(remaining)), MESSAGE_EVENT_ADVANCE)

	GlobalBoosts.broadcastState()

	return true, verb, remaining
end

-- Force-sets a boost's remaining time with no broadcast and no purchase
-- record. GM tooling only (talkactions/god/globalboost.lua).
function GlobalBoosts.set(boostId, seconds, contributorName)
	local boost = GlobalBoosts.Types[boostId]
	if not boost then
		return false
	end

	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	if seconds == 0 then
		state[boostId] = nil
		GlobalBoosts.ensureSchema()
		db.query("UPDATE `server_boosts` SET `expires_at` = 0 WHERE `boost` = " .. db.escapeString(boost.key))
	else
		local entry = {expiresAt = os.time() + seconds, contributor = tostring(contributorName or "")}
		state[boostId] = entry
		persist(boost, entry, 0)
	end

	GlobalBoosts.syncAllPlayers()
	GlobalBoosts.broadcastState()
	return true
end

-- Retires everything that has run out. Called once a second by the
-- GlobalBoostsTick globalevent; returns true when anything changed.
function GlobalBoosts.tick()
	local now = os.time()
	local changed = false
	local needsSync = false

	for id, entry in pairs(state) do
		local boost = GlobalBoosts.Types[id]
		if not boost then
			state[id] = nil
			changed = true
		elseif entry.expiresAt <= now then
			state[id] = nil
			changed = true
			needsSync = needsSync or boost.push == true

			GlobalBoosts.ensureSchema()
			db.query("UPDATE `server_boosts` SET `expires_at` = 0 WHERE `boost` = " .. db.escapeString(boost.key))

			Game.broadcastMessage(boost.fade or string.format("The %s has faded.", boost.name),
				MESSAGE_EVENT_ADVANCE)
		end
	end

	if needsSync then
		GlobalBoosts.syncAllPlayers()
	end

	if changed then
		GlobalBoosts.broadcastState()
	end

	return changed
end

-- Replaced by the network layer (scripts/network/boosts/boosts_protocol.lua)
-- once it loads. Defined here as a no-op so this lib stays usable -- and
-- testable -- with no client attached.
--
-- `or` rather than a plain assignment, and this matters: at boot the order is
-- lib.lua (scriptmanager.cpp:89) then data/scripts (otserv.cpp:591), so a
-- plain assignment is fine. But src/signals.cpp:112 re-runs `loadFile
-- ("data/lib/lib.lua")` on a reload signal WITHOUT re-running data/scripts --
-- which would silently reinstate this no-op over the real sender and leave
-- every client's HUD frozen with no error anywhere. Guarding the definition
-- makes a lib reload harmless.
GlobalBoosts.broadcastState = GlobalBoosts.broadcastState or function() end
