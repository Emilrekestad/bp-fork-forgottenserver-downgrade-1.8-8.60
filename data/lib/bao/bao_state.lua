-- Old Man Bao — the single choke point for all progression persistence.
-- Nothing else touches bao_player / bao_active_hunts / the kv mastery blob
-- directly; every other Bao file goes through BaoState. This is what keeps
-- "add a new hunt" or "retune a threshold" a bao_config-only change.

BaoState = {}

-- In-memory cache keyed by player:getId() (online session id), mirroring the
-- pattern already used by Task Hunting's own taskCache. Loaded lazily on
-- first access so nothing needs to depend on a login hook being wired up yet.
local playerCache = {}

local function emptyPlayerRow()
	return { reputation = 0, marks = 0, rankId = 0, storyChapter = 0, loaded = false }
end

local function loadPlayerRow(player)
	local guid = player:getGuid()
	local resultId = db.storeQuery("SELECT `reputation`, `marks`, `rank_id`, `story_chapter` FROM `bao_player` WHERE `player_id` = " .. guid)
	if resultId ~= false then
		local row = {
			reputation = result.getDataInt(resultId, "reputation"),
			marks = result.getDataInt(resultId, "marks"),
			rankId = result.getDataInt(resultId, "rank_id"),
			storyChapter = result.getDataInt(resultId, "story_chapter"),
			loaded = true,
		}
		result.free(resultId)
		return row
	end

	db.asyncQuery("INSERT INTO `bao_player` (`player_id`, `reputation`, `marks`, `rank_id`, `story_chapter`, `updated_at`) " ..
		"VALUES (" .. guid .. ", 0, 0, 0, 0, " .. os.time() .. ")")
	local row = emptyPlayerRow()
	row.loaded = true
	return row
end

local function loadSlots(player, maxSlots)
	local guid = player:getGuid()
	local slots = {}
	local resultId = db.storeQuery("SELECT `slot`, `hunt_id`, `state`, `progress`, `accepted_at` FROM `bao_active_hunts` WHERE `player_id` = " .. guid)
	if resultId ~= false then
		repeat
			local slot = result.getDataInt(resultId, "slot")
			if slot >= 1 and slot <= maxSlots then
				local huntId = result.getDataString(resultId, "hunt_id")
				-- Defensive: a hunt removed from bao_config is treated as auto-abandoned.
				if BaoConfig.Hunts[huntId] then
					slots[slot] = {
						huntId = huntId,
						state = result.getDataInt(resultId, "state"),
						progress = result.getDataInt(resultId, "progress"),
						acceptedAt = result.getDataLong(resultId, "accepted_at"),
					}
				end
			end
		until not result.next(resultId)
		result.free(resultId)
	end
	return slots
end

local function ensureLoaded(player)
	local id = player:getId()
	local cached = playerCache[id]
	if cached then
		return cached
	end

	local cache = {
		row = loadPlayerRow(player),
		-- Bounded by the player's PURCHASED maximum, not the config base, or a
		-- 4th/5th slot bought from the shop would load as out-of-range and be
		-- silently discarded on every login.
		slots = loadSlots(player, BaoState.getMaxSlots(player)),
		-- Slots whose in-memory progress is ahead of the database. Progress is
		-- only flushed on an interval boundary, on completion, or on logout
		-- (see saveSlotThrottled), so this is what tells flush() which rows
		-- still need writing.
		dirtySlots = {},
		-- getMasteryCount walks the entire hunt roster doing one kv read per
		-- hunt, and it is called both per sync packet and on every rank check.
		-- Mastery only changes through recordMastery, which invalidates this,
		-- so caching it per session is free correctness-wise.
		masteryCount = nil,
	}
	playerCache[id] = cache
	return cache
end

local function savePlayerRow(player, cache)
	local guid = player:getGuid()
	db.asyncQuery(string.format(
		"INSERT INTO `bao_player` (`player_id`, `reputation`, `marks`, `rank_id`, `story_chapter`, `updated_at`) " ..
		"VALUES (%d, %d, %d, %d, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `reputation` = VALUES(`reputation`), `marks` = VALUES(`marks`), " ..
		"`rank_id` = VALUES(`rank_id`), `story_chapter` = VALUES(`story_chapter`), `updated_at` = VALUES(`updated_at`)",
		guid, cache.row.reputation, cache.row.marks, cache.row.rankId, cache.row.storyChapter, os.time()
	))
end

-- `sync` forces a blocking db.query instead of the queued db.asyncQuery. Used
-- only on logout: saves go through the async queue while loads use synchronous
-- db.storeQuery, and there is no ordering guarantee between the two. A player
-- who logs out at 149/150 and straight back in could otherwise be re-read from
-- the database before the queued write landed, and the stale cache would then
-- overwrite the newer row. Writing synchronously on the way out closes that.
local function saveSlot(player, slot, cache, sync)
	local guid = player:getGuid()
	local run = sync and db.query or db.asyncQuery
	local slotData = cache.slots[slot]
	if not slotData then
		run("DELETE FROM `bao_active_hunts` WHERE `player_id` = " .. guid .. " AND `slot` = " .. slot)
		cache.dirtySlots[slot] = nil
		return
	end

	run(string.format(
		"INSERT INTO `bao_active_hunts` (`player_id`, `slot`, `hunt_id`, `state`, `progress`, `accepted_at`) " ..
		"VALUES (%d, %d, %s, %d, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `hunt_id` = VALUES(`hunt_id`), `state` = VALUES(`state`), " ..
		"`progress` = VALUES(`progress`), `accepted_at` = VALUES(`accepted_at`)",
		guid, slot, db.escapeString(slotData.huntId), slotData.state, slotData.progress, slotData.acceptedAt
	))
	cache.dirtySlots[slot] = nil
end

-- Progress-only save. Writing on every credited kill means one INSERT ... ON
-- DUPLICATE KEY UPDATE per player, per slot, per monster death — and with
-- party-wide credit a single death can fan out across everyone who
-- participated. This defers to a BaoConfig.SaveInterval boundary and marks the
-- slot dirty in between, which is the same shape as
-- data/scripts/network/task_board/bounty_tasks.lua's shouldPersistKillProgress.
--
-- Anything that is not routine progress — accepting, abandoning, completing —
-- still calls saveSlot directly and lands immediately.
local function saveSlotThrottled(player, slot, cache, previousProgress, force)
	local slotData = cache.slots[slot]
	if not slotData then
		saveSlot(player, slot, cache)
		return
	end

	local interval = BaoConfig.SaveInterval or 1
	if force or interval <= 1
			or math.floor(previousProgress / interval) ~= math.floor(slotData.progress / interval) then
		saveSlot(player, slot, cache)
		return
	end

	cache.dirtySlots[slot] = true
end

-- ─── Lifetime counters ──────────────────────────────────────────────────
--
-- Totals that never reset, for the Profile tab. Mastery count already answers
-- "how many distinct hunts" -- these answer "how much work", which is the
-- number a player actually wants to show someone. Kept in kv rather than a new
-- table: they are two integers per character and nothing queries across players.

local function counterStore(player)
	return player:kv():scoped("bao"):scoped("totals")
end

function BaoState.getCounter(player, key)
	local value = counterStore(player):get(key)
	return type(value) == "number" and value or 0
end

function BaoState.bumpCounter(player, key, amount)
	local store = counterStore(player)
	local value = BaoState.getCounter(player, key) + (amount or 1)
	store:set(key, value)
	return value
end

-- ─── Hunt slot capacity ─────────────────────────────────────────────────
--
-- BaoConfig.MaxActiveSlots is the BASE every player starts with. Bao's shop
-- sells a fourth and a fifth on top of it, so every loop over slots has to ask
-- this rather than reading the config constant directly — otherwise a
-- purchased slot exists in the database and is invisible everywhere else.

local function slotStore(player)
	return player:kv():scoped("bao"):scoped("slots")
end

function BaoState.getExtraSlots(player)
	local value = slotStore(player):get("extra")
	return type(value) == "number" and value or 0
end

function BaoState.getMaxSlots(player)
	return BaoConfig.MaxActiveSlots + math.min(BaoState.getExtraSlots(player), BaoConfig.MaxPurchasableSlots or 0)
end

-- Sets the extra-slot count to `total` (not +=), so buying the fifth after the
-- fourth lands on 2 rather than depending on purchase order. Returns false if
-- the player already has at least that many, which is what makes the shop's
-- one-time flag and this agree even if the flag is ever cleared.
function BaoState.grantExtraSlot(player, total)
	if BaoState.getExtraSlots(player) >= total then
		return false, "You already hunt that many at once."
	end
	slotStore(player):set("extra", math.min(total, BaoConfig.MaxPurchasableSlots or total))
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"Old Man Bao looks you over once more. \"Fine. %d hunts at a time. Do not make me regret it.\"",
		BaoState.getMaxSlots(player)))
	return true
end

-- ─── Player wipe / disconnect ───────────────────────────────────────────

-- Writes back anything still held in memory. Safe to call for a player who was
-- never touched by Bao — an unwarmed cache flushes nothing.
--
-- `sync` should be true on logout, where the write must land before the row
-- can be read again.
function BaoState.flush(player, sync)
	local cache = playerCache[player:getId()]
	if not cache then
		return
	end
	for slot in pairs(cache.dirtySlots) do
		saveSlot(player, slot, cache, sync)
	end
	cache.dirtySlots = {}
end

-- (!) Must be called on logout, and must be called AFTER BaoState.flush —
-- clearing first would discard the very progress the flush exists to write.
-- data/scripts/creaturescripts/bao/bao_logout.lua does both in that order.
function BaoState.clearCache(player)
	playerCache[player:getId()] = nil
end

-- ─── Reputation / Marks / Rank / Story chapter ─────────────────────────

function BaoState.getReputation(player)
	return ensureLoaded(player).row.reputation
end

function BaoState.getMarks(player)
	return ensureLoaded(player).row.marks
end

function BaoState.getRankId(player)
	return ensureLoaded(player).row.rankId
end

function BaoState.getStoryChapter(player)
	return ensureLoaded(player).row.storyChapter
end

function BaoState.addReputation(player, amount)
	if amount == 0 then
		return
	end
	local cache = ensureLoaded(player)
	cache.row.reputation = math.max(0, cache.row.reputation + amount)
	savePlayerRow(player, cache)
end

function BaoState.addMarks(player, amount)
	if amount == 0 then
		return
	end
	local cache = ensureLoaded(player)
	cache.row.marks = math.max(0, cache.row.marks + amount)
	savePlayerRow(player, cache)

	-- Lifetime total, for the Profile. Only counts INCOME -- a refund from a
	-- failed purchase comes back through here too, but so did the spend that
	-- preceded it, so the pair nets out. Spending never decrements it, which is
	-- the point: "earned" should keep climbing no matter what you buy.
	if amount > 0 then
		BaoState.bumpCounter(player, "marksEarned", amount)
	end
end

-- Returns false without changing state if the player can't afford it.
function BaoState.spendMarks(player, amount)
	local cache = ensureLoaded(player)
	if cache.row.marks < amount then
		return false
	end
	cache.row.marks = cache.row.marks - amount
	savePlayerRow(player, cache)
	return true
end

function BaoState.setRank(player, rankId)
	local cache = ensureLoaded(player)
	cache.row.rankId = rankId
	savePlayerRow(player, cache)
end

-- Returns true if the chapter actually advanced (never regresses, never
-- re-fires on the same or a lower value) — callers use this to decide
-- whether to show the narrative beat for the new chapter.
function BaoState.setStoryChapter(player, chapter)
	local cache = ensureLoaded(player)
	if chapter <= cache.row.storyChapter then
		return false
	end
	cache.row.storyChapter = chapter
	savePlayerRow(player, cache)
	return true
end

-- ─── Active hunts ────────────────────────────────────────────────────────

-- Returns the raw slots array (1..MaxActiveSlots), entries are nil or
-- { huntId, state, progress, acceptedAt }. state: 1 = active, 2 = completed_unclaimed.
function BaoState.getActiveHunts(player)
	return ensureLoaded(player).slots
end

function BaoState.getActiveSlotFor(player, huntId)
	local slots = ensureLoaded(player).slots
	for slot = 1, BaoState.getMaxSlots(player) do
		if slots[slot] and slots[slot].huntId == huntId then
			return slot
		end
	end
	return nil
end

function BaoState.findFreeSlot(player)
	local slots = ensureLoaded(player).slots
	for slot = 1, BaoState.getMaxSlots(player) do
		if not slots[slot] then
			return slot
		end
	end
	return nil
end

-- Accepts a hunt into a specific slot. Caller (bao_protocol) is responsible
-- for validating rank/repeatable/mastery gates against bao_config first —
-- this function only enforces slot-shape invariants.
function BaoState.acceptHunt(player, slot, huntId)
	if slot < 1 or slot > BaoState.getMaxSlots(player) then
		return false, "invalid_slot"
	end
	local cache = ensureLoaded(player)
	if cache.slots[slot] then
		return false, "slot_occupied"
	end
	if BaoState.getActiveSlotFor(player, huntId) then
		return false, "hunt_already_active"
	end

	cache.slots[slot] = { huntId = huntId, state = 1, progress = 0, acceptedAt = os.time() }
	saveSlot(player, slot, cache)
	return true
end

-- Full reset, per design decision: abandoning wipes progress, no shelving.
function BaoState.abandonHunt(player, slot)
	local cache = ensureLoaded(player)
	if not cache.slots[slot] then
		return false, "slot_empty"
	end
	cache.slots[slot] = nil
	saveSlot(player, slot, cache)
	return true
end

-- Frees a slot without touching progress semantics — used after a claimed
-- reward removes a completed hunt from the active list.
function BaoState.clearSlot(player, slot)
	local cache = ensureLoaded(player)
	cache.slots[slot] = nil
	saveSlot(player, slot, cache)
end

-- How many kills this hunt asks THIS player for, after Bao's Ledger. The
-- single place that answer is produced, so the completion check, the packet
-- and any future caller cannot disagree about it.
function BaoState.requiredFor(player, hunt)
	if BaoLedger and BaoLedger.requiredFor then
		return BaoLedger.requiredFor(player, hunt)
	end
	return hunt.requiredCount
end

-- Adds weighted progress to whichever active slot is running this huntId.
-- Returns nil if the hunt isn't currently active for this player, otherwise
-- { slot, progress, requiredCount, justCompleted }.
function BaoState.addHuntProgress(player, huntId, amount)
	local slot = BaoState.getActiveSlotFor(player, huntId)
	if not slot then
		return nil
	end
	local cache = ensureLoaded(player)
	local slotData = cache.slots[slot]
	if slotData.state ~= 1 then
		return nil -- already completed, waiting on claim
	end

	local hunt = BaoConfig.Hunts[huntId]
	if not hunt then
		return nil
	end

	-- Bao's Ledger "Cold Trail" shortens hunts for the player who bought it.
	-- Both the clamp and the completion test have to use the same effective
	-- number or a shortened hunt would never register as finished.
	local required = BaoState.requiredFor(player, hunt)

	local previousProgress = slotData.progress
	slotData.progress = math.min(required, slotData.progress + amount)
	local justCompleted = false
	if slotData.progress >= required then
		slotData.state = 2
		justCompleted = true
	end
	-- Completion forces an immediate write; ordinary progress rides the
	-- interval. A hunt is never left "finished in memory only".
	saveSlotThrottled(player, slot, cache, previousProgress, justCompleted)

	return {
		slot = slot,
		progress = slotData.progress,
		previousProgress = previousProgress,
		requiredCount = required,
		justCompleted = justCompleted,
	}
end

-- ─── Hunt Mastery (kv_store-scoped blob) ────────────────────────────────

local function masteryStore(player)
	return player:kv():scoped("bao"):scoped("mastery")
end

-- Returns { timesCompleted = N, firstCompletedAt = timestamp } — both 0/nil
-- if the player has never completed this hunt.
function BaoState.getMastery(player, huntId)
	local entry = masteryStore(player):get(huntId)
	if type(entry) ~= "table" then
		return { timesCompleted = 0, firstCompletedAt = 0 }
	end
	return entry
end

function BaoState.getMasteryCount(player)
	-- Counts hunts with at least 1 completion. Iterates BaoConfig.Hunts, not
	-- the whole kv blob, so it stays correct even if a hunt is later removed
	-- from config (its mastery entry becomes unreachable/irrelevant).
	--
	-- Cached per session: this is one kv read per hunt in the roster, and it
	-- used to run once per sync packet AND again on every rank check, on top
	-- of the per-hunt read the catalog already does. Only recordMastery can
	-- change the answer, and it invalidates.
	local cache = ensureLoaded(player)
	if cache.masteryCount then
		return cache.masteryCount
	end

	local count = 0
	for huntId, _ in pairs(BaoConfig.Hunts) do
		if BaoState.getMastery(player, huntId).timesCompleted > 0 then
			count = count + 1
		end
	end
	cache.masteryCount = count
	return count
end

-- Records a completion. Returns true if this was the FIRST completion of
-- this hunt (the caller uses this to decide whether to apply the
-- first-mastery reward multiplier).
function BaoState.recordMastery(player, huntId)
	local store = masteryStore(player)
	local entry = store:get(huntId)
	local isFirst = type(entry) ~= "table"

	if isFirst then
		entry = { timesCompleted = 1, firstCompletedAt = os.time() }
	else
		entry.timesCompleted = (entry.timesCompleted or 0) + 1
	end

	store:set(huntId, entry)

	-- The only thing that can change the mastery count, so it is the only
	-- place that has to invalidate it.
	if isFirst then
		ensureLoaded(player).masteryCount = nil
	end
	return isFirst
end

-- ─── Bao Shop purchase tracking (kv_store-scoped blob, separate from mastery) ───

local function shopStore(player)
	return player:kv():scoped("bao"):scoped("shop")
end

function BaoState.hasPurchased(player, itemKey)
	return shopStore(player):get(itemKey) == true
end

function BaoState.recordPurchase(player, itemKey)
	shopStore(player):set(itemKey, true)
end
