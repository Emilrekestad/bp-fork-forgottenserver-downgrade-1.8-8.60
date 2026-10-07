--[[
================================================================================
  dupetest.lua  -  RevScript  (TFS 1.8 / 8.60 downgrade fork)
  Item Duplication Vulnerability Test
  Repository: Mateuzkl/forgottenserver-downgrade-1.8-8.60
================================================================================

  Purpose
  ─────────
  Detects item integrity failures that can be exploited as "dupes":
  situations where the threaded save system (PR #69) leaves items in the database
  after they were removed from memory, or does not reflect the correct state in the DB.

  USAGE (GMs only, getAccess() == true):
    /dupe start   - runs all 8 phases in sequence
    /dupe 1-8     - runs a single phase
    /dupe info    - describes each phase
    /dupe clean   - removes test items from the inventory

  PHASES:
  ┌────┬─────────────────────────────────────────┬──────────────────────────────────┐
  │ Ph │ Dupe Vector                             │ What it detects                  │
  ├────┼─────────────────────────────────────────┼──────────────────────────────────┤
  │  1 │ Ghost item after save flood             │ Old save overwrites new one      │
  │  2 │ SNAPSHOT RACE: add→save→remove→save ★   │ S1 runs after S2 on the worker   │
  │  3 │ Stackable count integrity               │ Extra/missing coins in the DB    │
  │  4 │ N rounds add/remove, save in each       │ Cumulative ghost per round       │
  │  5 │ Concurrent saves burst (addEvent 0)     │ Worker pool race                 │
  │  6 │ Snapshot reversal: [A]→save→swap B→save │ Item A persists after swap       │
  │  7 │ Multi-item partial removal              │ Extra item in the DB             │
  │  8 │ Full simulation: flood w/ and w/o item  │ Real disconnect-dupe scenario    │
  └────┴─────────────────────────────────────────┴──────────────────────────────────┘
  ★ = most critical phase for PR #69

  PREREQUISITE:
    Inventory must not contain items of the types CFG.item_ns and CFG.item_st
    before running. Use /dupe clean to make sure.

  SAFETY:
    • Does not access production tables directly (read-only for verification).
    • All created items are removed at the end of each phase.
    • Requires player:getGroup():getAccess() == true.
================================================================================
--]]

-- ============================================================================
-- CONFIGURATION  –  adjust for your server
-- ============================================================================
-- Test items - use IDs that do not interfere with the real inventory.
-- If the server has QA/debug items, set QA_ITEM_NS and QA_ITEM_ST below.
local QA_ITEM_NS = 3264   -- Sword (cheap non-stackable, safe for QA cleanup)
local QA_ITEM_ST = 3035   -- Platinum Coin (low-value stackable, safe for QA cleanup)

-- Safety: rejects high-value production IDs (Fire Sword=3280, Gold Coin=3031)
if QA_ITEM_NS == 3280 or QA_ITEM_NS == 3031 or QA_ITEM_ST == 3280 or QA_ITEM_ST == 3031 then
    error("BLOCKED: QA item IDs must not be high-value production IDs (3280/3031). Use safe QA-only IDs.")
end

-- Safety: checks in the registry that the items exist (avoids invalid IDs)
do
    local itemType = ItemType(QA_ITEM_NS)
    assert(itemType and itemType:getId() ~= 0,
        "QA_ITEM_NS=" .. QA_ITEM_NS .. " item invalid or nonexistent. Check items.otb and items.xml.")
end
do
    local itemType = ItemType(QA_ITEM_ST)
    assert(itemType and itemType:getId() ~= 0,
        "QA_ITEM_ST=" .. QA_ITEM_ST .. " item invalid or nonexistent. Check items.otb and items.xml.")
end

local CFG = {
    -- Non-stackable test item
    item_ns       = QA_ITEM_NS,

    -- Stackable test item
    item_st       = QA_ITEM_ST,

    -- Number of rapid saves per flood phase
    save_burst    = 8,

    -- Interval between saves in the flood (ms)
    stagger_ms    = 15,

    -- Delay before querying the DB (ms)
    -- Must be longer than the settle time of the PR #69 worker thread.
    -- Increase to 2500-3000 when running on a slow database.
    verify_delay  = 2000,
}

-- ============================================================================
-- UTILITIES
-- ============================================================================
local COLOR_RESET  = "\27[0m"
local COLOR_BLUE   = "\27[94m"
local COLOR_GREEN  = "\27[32m"
local COLOR_YELLOW = "\27[33m"
local COLOR_RED    = "\27[31m"
local COLOR_ORANGE = "\27[38;5;208m"

local MSG_BLUE = MESSAGE_STATUS_CONSOLE_BLUE or MESSAGE_EVENT_ADVANCE or 19
local MSG_RED  = MESSAGE_STATUS_CONSOLE_RED  or MESSAGE_STATUS_WARNING or MSG_BLUE

local activeRuns = {}  -- keyed by player GUID to allow multiple GMs
local phaseFailed = {}  -- keyed by player GUID; logFail sets, /dupe start resets per-GUID

local function colorPhase(msg)
    local out = msg:gsub("(Phase %d+[abc]?:)", COLOR_ORANGE .. "%1" .. COLOR_RESET)
    return out
end

local function log(player, msg)
    print(COLOR_BLUE .. "[DupeTest]" .. COLOR_RESET .. " " .. colorPhase(msg))
    if player and player:isPlayer() then
        player:sendTextMessage(MSG_BLUE, "[DupeTest] " .. msg)
    end
end

local function logFail(player, msg)
    if player and player:isPlayer() then
        phaseFailed[player:getGuid()] = true
    end
    print(COLOR_BLUE .. "[DupeTest]" .. COLOR_RED .. "[FAIL]" .. COLOR_RESET .. " " .. colorPhase(msg))
    if player and player:isPlayer() then
        player:sendTextMessage(MSG_RED, "[DupeTest][FAIL] " .. msg)
    end
end

local function logPass(player, msg)
    print(COLOR_BLUE .. "[DupeTest]" .. COLOR_YELLOW .. "[PASS]" .. COLOR_RESET .. " " .. colorPhase(msg))
    if player and player:isPlayer() then
        player:sendTextMessage(MSG_BLUE, "[DupeTest][PASS] " .. msg)
    end
end

local function logInfo(player, msg)
    print(COLOR_BLUE .. "[DupeTest]" .. COLOR_GREEN .. "[INFO]" .. COLOR_RESET .. " " .. colorPhase(msg))
    if player and player:isPlayer() then
        player:sendTextMessage(MSG_BLUE, "[DupeTest][INFO] " .. msg)
    end
end

local function logHeader(player, msg)
    -- Paints the whole message blue
    print(COLOR_BLUE .. "[DupeTest] " .. msg .. COLOR_RESET)
    if player and player:isPlayer() then
        player:sendTextMessage(MSG_BLUE, "[DupeTest] " .. msg)
    end
end

local function logSummary(player, msg, hasFailed)
    -- If hasFailed is true, shows red; otherwise, blue
    if hasFailed then
        print(COLOR_BLUE .. "[DupeTest]" .. COLOR_RED .. "[FAIL] " .. msg .. COLOR_RESET)
        if player and player:isPlayer() then
            player:sendTextMessage(MSG_RED, "[DupeTest][FAIL] " .. msg)
        end
    else
        print(COLOR_BLUE .. "[DupeTest] " .. msg .. COLOR_RESET)
        if player and player:isPlayer() then
            player:sendTextMessage(MSG_BLUE, "[DupeTest] " .. msg)
        end
    end
end

local function safePlayer(pid, expectedGuid)
    local p = Player(pid)
    if not p then
        print("[DupeTest] Player id=" .. tostring(pid) .. " disconnected during the test.")
        return nil
    end
    if expectedGuid and p:getGuid() ~= expectedGuid then
        print("[DupeTest] Player id=" .. tostring(pid) .. " GUID mismatch (recycled PID?). Ignoring.")
        return nil
    end
    return p
end

-- Counts rows in player_items for this player_guid + itemtype
local function countItemsInDB(playerGuid, itemTypeId)
    local res = db.storeQuery(string.format(
        "SELECT COUNT(*) AS cnt FROM `player_items` WHERE `player_id`=%d AND `itemtype`=%d",
        playerGuid, itemTypeId
    ))
    if not res or res == false then return -1 end
    local cnt = result.getNumber(res, "cnt")
    result.free(res)
    return cnt
end

-- Sums the total stackable count in player_items (Gold Coin, etc.)
local function sumStackInDB(playerGuid, itemTypeId)
    local res = db.storeQuery(string.format(
        "SELECT COALESCE(SUM(`count`), 0) AS total FROM `player_items` WHERE `player_id`=%d AND `itemtype`=%d",
        playerGuid, itemTypeId
    ))
    if not res or res == false then return -1 end
    local total = result.getNumber(res, "total")
    result.free(res)
    return total
end

-- Removes all items of a type from the inventory (safety cleanup)
-- Count items first, then remove only what exists (avoid excessive iteration)
local function safeRemoveAll(player, itemTypeId)
    local count = player:getItemCount(itemTypeId)
    if count > 0 then
        player:removeItem(itemTypeId, count)
    end
end

-- Tries to verify a condition with retries instead of a fixed delay.
--   checkFn: returns true if the check passed, false if it failed
--   onPass(attempt): called when checkFn returns true
--   onFail(finalAttempt): called after maxRetries is exhausted
--   initialDelay: first delay before trying (ms)
--   retryInterval: interval between retries (ms)
--   maxRetries: maximum number of attempts (default 3)
local function verifyWithRetry(checkFn, onPass, onFail, initialDelay, retryInterval, maxRetries)
    maxRetries = maxRetries or 3
    retryInterval = retryInterval or 800
    local attempt = 0

    local function tryVerify()
        attempt = attempt + 1
        if checkFn(attempt) then
            onPass(attempt)
        elseif attempt < maxRetries then
            addEvent(tryVerify, retryInterval)
        else
            onFail(attempt)
        end
    end

    addEvent(tryVerify, initialDelay)
end

-- Checks whether the player already owns items of the test types in the inventory
-- Returns true if there are pre-existing items (risk of mixing) or a DB error
local function hasPreExistingTestItems(player, guid)
    local cntNS = countItemsInDB(guid, QA_ITEM_NS)
    local cntST = sumStackInDB(guid, QA_ITEM_ST)
    if cntNS == -1 or cntST == -1 then
        logFail(player, "hasPreExistingTestItems: DB query error - could not verify inventory.")
        return true  -- blocks for safety (fails closed)
    end
    if cntNS > 0 or cntST > 0 then
        return true
    end
    return false
end

-- ============================================================================
-- PHASE 1  –  Ghost item after save flood
-- ============================================================================
--[[
  Adds 1 non-stackable item, fires N saves in a burst, then removes
  the item and saves one last time. Verifies that the DB does not retain a ghost item.

  FAILURE INDICATES: one of the flood saves (with item) ran on the worker AFTER
  the removal save (without item), overwriting the correct state.
  → The worker queue is not FIFO for player items.
--]]
local function runPhase1(player)
    local guid   = player:getGuid()
    local pid    = player:getId()
    local typeId = CFG.item_ns

    log(player, string.format(
        "Phase 1: Ghost item - add 1 item, %dx save flood (stagger=%dms), remove, verify DB=0...",
        CFG.save_burst, CFG.stagger_ms
    ))

    safeRemoveAll(player, typeId)

    if not player:addItem(typeId, 1, false) then
        logFail(player, "Phase 1: Failed to create item (item_ns=" .. typeId .. "). Adjust CFG.item_ns.")
        return false
    end

    -- Flood of saves WITH the item in memory (async to test PR#69)
    for i = 1, CFG.save_burst do
        addEvent(function(pid2, guid2)
            local p = safePlayer(pid2, guid2)
            if p and not p:saveAsync() then
                logInfo(p, "Phase 1: saveAsync() returned false (flush in progress) - normal during a flood.")
            end
        end, i * CFG.stagger_ms, pid, guid)
    end

    -- Removes the item and does the final save
    local removeAt = CFG.save_burst * CFG.stagger_ms + 100
    addEvent(function(pid2, guid2, tId)
        local p = safePlayer(pid2, guid2)
        if not p then return end
        p:removeItem(tId, 1)
        p:save()
    end, removeAt, pid, guid, typeId)

    -- Check DB
    addEvent(function(pid2, guid2, tId)
        local p = safePlayer(pid2, guid2)
        if not p then return end

        local cnt = countItemsInDB(guid2, tId)
        if cnt == 0 then
            logPass(p, "Phase 1: DB=0 - no ghost item. Save flood ordering preserved.")
        elseif cnt > 0 then
            logFail(p, string.format(
                "Phase 1: DB=%d (expected 0) - GHOST ITEM! Flood save (w/ item) overwrote the removal save.",
                cnt
            ))
            logFail(p, "  -> Worker does not respect FIFO: old save arrived after newer save.")
            safeRemoveAll(p, tId)
            p:save()
        else
            logFail(p, "Phase 1: DB query failed (returned -1). Check player_items and the connection.")
        end
    end, removeAt + CFG.verify_delay, pid, guid, typeId)

    return true
end

-- ============================================================================
-- PHASE 2  –  SNAPSHOT RACE  ★  MOST CRITICAL PHASE
-- ============================================================================
--[[
  Replicates the exact disconnect/trade dupe scenario:

    1. addItem         → item in MEMORY
    2. player:save()   → snapshot S1 queued: { item present }
    3. removeItem      → item removed from MEMORY (no save yet)
    4. player:save()   → snapshot S2 queued: { item absent  }

  Correct FIFO worker:  S1 writes item → S2 deletes item → DB=0 ✓
  Out-of-order worker:  S2 deletes (nothing) → S1 writes item → DB=1 = DUPE!

  Real scenario exploited by players:
    pick up item → drop item/trade/immediate DC → relog
    → item reappears in the inventory from the corrupted DB state.

  FAILURE HERE = DUPE BUG CONFIRMED in flushPlayerSave / pendingFlushes.
--]]
local function runPhase2(player)
    local guid   = player:getGuid()
    local pid    = player:getId()
    local typeId = CFG.item_ns

    log(player, "Phase 2: SNAPSHOT RACE - add->save(S1)->remove->save(S2) | S2 must be the final state.")
    log(player, "Phase 2: if this fails = real dupe bug in the worker thread ordering (PR #69).")

    safeRemoveAll(player, typeId)

    -- 1. Add item (in memory only)
    if not player:addItem(typeId, 1, false) then
        logFail(player, "Phase 2: Failed to create item. Adjust CFG.item_ns.")
        return false
    end

    -- 2. Save S1: snapshot WITH item → queued on the worker (async for a real race)
    local s1 = player:saveAsync()
    if not s1 then
        logFail(player, "Phase 2: saveAsync() S1 returned false - flush not queued. Test may be inconclusive.")
        safeRemoveAll(player, typeId)
        return false
    end

    -- 3. Remove from MEMORY without saving
    player:removeItem(typeId, 1)

    -- 4. Save S2: snapshot WITHOUT item (must be the final state) (async, goes to pendingFlushes)
    local s2 = player:saveAsync()
    if not s2 then
        logFail(player, "Phase 2: saveAsync() S2 returned false - flush not queued. Test may be inconclusive.")
        safeRemoveAll(player, typeId)
        return false
    end

    logInfo(player, string.format(
        "Phase 2: S1=%s S2=%s | Two saves queued. Checking DB with retry...",
        tostring(s1), tostring(s2)
    ))

    verifyWithRetry(
        function()
            local p = safePlayer(pid, guid)
            if not p then return false end
            return countItemsInDB(guid, typeId) == 0
        end,
        function(attempt)
            local p = safePlayer(pid, guid)
            if not p then return end
            logPass(p, string.format(
                "Phase 2: DB=0 (attempt %d) - S2 (without item) was the final state. FIFO ordering OK.",
                attempt
            ))
        end,
        function(attempt)
            local p = safePlayer(pid, guid)
            if not p then return end
            local cnt = countItemsInDB(guid, typeId)
            if cnt > 0 then
                logFail(p, string.format(
                    "Phase 2: DB=%d (expected 0) after %d attempts - ## DUPE BUG CONFIRMED ##", cnt, attempt
                ))
                logFail(p, "  -> S1 {item present} ran AFTER S2 {item removed} on the worker thread.")
                logFail(p, "  -> A player re-logging would get the item back in the inventory = DUPLICATED ITEM!")
                logFail(p, "  -> Fix: guarantee FIFO in SaveManager::onPlayerFlushed + pendingFlushes drain.")
                safeRemoveAll(p, typeId)
                p:save()
            else
                logFail(p, "Phase 2: DB query failed. Check the connection and the player_items table.")
            end
        end,
        CFG.verify_delay, 800, 3
    )

    return true
end

-- ============================================================================
-- PHASE 3  –  Stackable count integrity
-- ============================================================================
--[[
  Tests that the stackable count stays correct after:
    add 200 coins → save → verify SUM=200
    remove 100    → save → verify SUM=100

  A stackable dupe happens if an old snapshot (larger count)
  overwrites a newer snapshot (smaller count), resulting in
  extra coins in the database on the next session.
--]]
local function runPhase3(player)
    local guid   = player:getGuid()
    local pid    = player:getId()
    local typeId = CFG.item_st
    local addQty = 200

    log(player, string.format(
        "Phase 3: Stackable count - add %d, save, check=200, remove 100, save, check=100...",
        addQty
    ))

    safeRemoveAll(player, typeId)

    if not player:addItem(typeId, addQty, false) then
        logFail(player, "Phase 3: Failed to create stackable item. Adjust CFG.item_st.")
        return false
    end

    player:save()

    addEvent(function(pid2, guid2, tId, qty)
        local p = safePlayer(pid2, guid2)
        if not p then return end

        -- 3a: verifies SUM after add+save
        local sumA = sumStackInDB(guid2, tId)
        if sumA ~= qty then
            logFail(p, string.format(
                "Phase 3a: DB sum=%d (expected %d) after add+save. Basic save problem.",
                sumA, qty
            ))
        else
            logPass(p, string.format("Phase 3a: DB sum=%d OK after add+save.", sumA))
        end

        -- Remove half
        local half = math.floor(qty / 2)
        p:removeItem(tId, half)
        p:save()

        addEvent(function(pid3, guid3, tId3, expected, removed)
            local p3 = safePlayer(pid3, guid3)
            if not p3 then return end

            local sumB = sumStackInDB(guid3, tId3)
            if sumB == expected then
                logPass(p3, string.format(
                    "Phase 3b: DB sum=%d OK after removing %d. Count integrity verified.",
                    sumB, removed
                ))
            elseif sumB > expected then
                logFail(p3, string.format(
                    "Phase 3b: DB sum=%d (expected %d) - EXTRA %d coins! Old (larger) snapshot overwrote.",
                    sumB, expected, sumB - expected
                ))
            else
                logFail(p3, string.format(
                    "Phase 3b: DB sum=%d (expected %d) - coins missing. Save did not persist the removal.",
                    sumB, expected
                ))
            end

            safeRemoveAll(p3, tId3)
            p3:save()
        end, CFG.verify_delay, pid2, guid2, tId, qty - half, half)

    end, CFG.verify_delay, pid, guid, typeId, addQty)

    return true
end

-- ============================================================================
-- PHASE 4  –  N rounds of add/remove with a save in each round
-- ============================================================================
--[[
  Repeats N times: addItem → save → removeItem → save.
  Each round inserts two snapshots in the worker queue (with and without item).
  A cumulative ghost would indicate that "with item" saves from earlier rounds
  arrive after the "without item" saves from later rounds.
--]]
local function runPhase4(player)
    local guid   = player:getGuid()
    local pid    = player:getId()
    local typeId = CFG.item_ns
    local rounds = 5
    local roundMs = 300

    log(player, string.format(
        "Phase 4: %d rounds add->save->remove->save (each ~%dms) | final DB must be 0...",
        rounds, roundMs
    ))

    safeRemoveAll(player, typeId)

    for i = 1, rounds do
        local base = (i - 1) * roundMs

        -- addItem + save
        addEvent(function(pid2, guid2, tId)
            local p = safePlayer(pid2, guid2)
            if not p then return end
            p:addItem(tId, 1, false)
            p:save()
        end, base, pid, guid, typeId)

        -- removeItem + save
        addEvent(function(pid2, guid2, tId)
            local p = safePlayer(pid2, guid2)
            if not p then return end
            p:removeItem(tId, 1)
            p:save()
        end, base + 120, pid, guid, typeId)
    end

    local verifyAt = rounds * roundMs + CFG.verify_delay
    addEvent(function(pid2, guid2, tId, n)
        local p = safePlayer(pid2, guid2)
        if not p then return end

        local cnt = countItemsInDB(guid2, tId)
        if cnt == 0 then
            logPass(p, string.format(
                "Phase 4: DB=0 after %d rounds of add/remove. No cumulative ghost.", n
            ))
        elseif cnt > 0 then
            logFail(p, string.format(
                "Phase 4: DB=%d (expected 0) after %d rounds. Ghost item(s) persisted!",
                cnt, n
            ))
            logFail(p, "  -> A {with item} save from one round reached the worker after a {without item} save from a later round.")
            safeRemoveAll(p, tId)
            p:save()
        else
            logFail(p, "Phase 4: DB query failed.")
        end
    end, verifyAt, pid, guid, typeId, rounds)

    return true
end

-- ============================================================================
-- PHASE 5  –  Burst of concurrent saves via addEvent(0)
-- ============================================================================
--[[
  Fires N simultaneous addEvent(0) calls (all call player:save()).
  With PR#69, each save may be queued to a different worker.
  Verifies that the final state (item removed) prevails over the N
  intermediate saves (with item in the queue).

  Similar to Ph5 of stress_db.lua, but testing items instead of storage.
--]]
local function runPhase5(player)
    local guid   = player:getGuid()
    local pid    = player:getId()
    local typeId = CFG.item_ns
    local bursts = 20

    log(player, string.format(
        "Phase 5: %d addEvent(0) concurrent saves (worker pool saturation) | final DB=0...",
        bursts
    ))

    safeRemoveAll(player, typeId)

    if not player:addItem(typeId, 1, false) then
        logFail(player, "Phase 5: Failed to create item. Adjust CFG.item_ns.")
        return false
    end

    -- N simultaneous saves WITH the item in memory (async, saturates worker pool)
    for i = 1, bursts do
        addEvent(function(pid2, guid2)
            local p = safePlayer(pid2, guid2)
            if p and not p:saveAsync() then
                logInfo(p, "Phase 5: saveAsync() returned false (queue full) - expected under saturation.")
            end
        end, 0, pid, guid)
    end

    -- Remove and final save after all bursts have entered the queue
    addEvent(function(pid2, guid2, tId)
        local p = safePlayer(pid2, guid2)
        if not p then return end
        p:removeItem(tId, 1)
        p:save()
    end, 80, pid, guid, typeId)

    addEvent(function(pid2, guid2, tId, n)
        local p = safePlayer(pid2, guid2)
        if not p then return end

        local cnt = countItemsInDB(guid2, tId)
        if cnt == 0 then
            logPass(p, string.format(
                "Phase 5: DB=0 after %d concurrent saves + remove. Worker pool: no race detected.", n
            ))
        elseif cnt > 0 then
            logFail(p, string.format(
                "Phase 5: DB=%d (expected 0) - ghost after %d concurrent saves!",
                cnt, n
            ))
            logFail(p, "  -> One of the burst saves (with item) reached the worker after the removal save.")
            safeRemoveAll(p, tId)
            p:save()
        else
            logFail(p, "Phase 5: DB query failed.")
        end
    end, 80 + CFG.verify_delay, pid, guid, typeId, bursts)

    return true
end

-- ============================================================================
-- PHASE 6  –  Snapshot reversal: [A] → save → swap for B → save
-- ============================================================================
--[[
  Item swap with two snapshots in flight:
    S1 = snapshot with item A (non-stackable), without item B
    S2 = snapshot without item A, with item B (stackable)

  Real scenario: player drops item A, picks up item B, disconnects right after.
  Correct worker (FIFO):    S1 → S2:  DB has B, no A          ✓
  Out-of-order worker:      S2 → S1:  DB has A (ghost!), no B  = DUPE of A

  FAILURE INDICATES: item A (which was dropped/removed) reappears in the database.
--]]
local function runPhase6(player)
    local guid  = player:getGuid()
    local pid   = player:getId()
    local typeA = CFG.item_ns   -- non-stackable
    local typeB = CFG.item_st   -- stackable (different type)

    log(player, "Phase 6: Snapshot reversal - [A]->save(S1)->remove A, add B->save(S2) | DB must have only B...")

    safeRemoveAll(player, typeA)
    safeRemoveAll(player, typeB)

    -- Add A
    if not player:addItem(typeA, 1, false) then
        logFail(player, "Phase 6: Failed to create item A. Adjust CFG.item_ns.")
        return false
    end

    -- S1: { A=1, B=0 } (async — queued on the worker)
    local ok1 = player:saveAsync()
    if not ok1 then
        logFail(player, "Phase 6: saveAsync() S1 returned false - test aborted.")
        safeRemoveAll(player, typeA)
        return false
    end

    -- Swap: remove A, add B (no intermediate save)
    player:removeItem(typeA, 1)

    if not player:addItem(typeB, 1, false) then
        logFail(player, "Phase 6: Failed to create item B. Adjust CFG.item_st.")
        safeRemoveAll(player, typeA)
        player:save()
        return false
    end

    -- S2: { A=0, B=1 } (async — pendingFlushes behind S1)
    local ok2 = player:saveAsync()
    if not ok2 then
        logFail(player, "Phase 6: saveAsync() S2 returned false - test may be inconclusive.")
    end

    logInfo(player, string.format(
        "Phase 6: S1={A} and S2={B} queued. S2 must win. Checking in %dms...",
        CFG.verify_delay
    ))

    addEvent(function(pid2, guid2, tA, tB)
        local p = safePlayer(pid2, guid2)
        if not p then return end

        local cntA = countItemsInDB(guid2, tA)
        local cntB = countItemsInDB(guid2, tB)

        if cntA == 0 and cntB > 0 then
            logPass(p, string.format(
                "Phase 6: DB A=%d (ghost=0 OK) B=%d (present OK). Swap correct, no reversal.",
                cntA, cntB
            ))
        else
            if cntA > 0 then
                logFail(p, string.format(
                    "Phase 6: DB A=%d (expected 0) - GHOST of A! S1 overwrote S2.",
                    cntA
                ))
                logFail(p, "  -> Real scenario: player dropped A, picked up B, re-logged -> has A back = DUPE!")
            end
            if cntB == 0 then
                logFail(p, "Phase 6: DB B=0 - item B vanished. S2 did not persist correctly.")
            end
        end

        safeRemoveAll(p, tA)
        safeRemoveAll(p, tB)
        p:save()
    end, CFG.verify_delay, pid, guid, typeA, typeB)

    return true
end

-- ============================================================================
-- PHASE 7  –  Multi-item: partial removal
-- ============================================================================
--[[
  Adds 3 non-stackable items (different slots), saves, removes 2,
  saves again. The DB must have exactly 1 item remaining.

  Detects whether earlier saves (with 3 items) persist in the database after
  newer saves (with only 1 item), simulating partial inventory removal.
--]]
local function runPhase7(player)
    local guid   = player:getGuid()
    local pid    = player:getId()
    local typeId = CFG.item_ns
    local total  = 3

    log(player, string.format(
        "Phase 7: Multi-item - add %d, save, remove %d, save, verify DB=1...",
        total, total - 1
    ))

    safeRemoveAll(player, typeId)

    local added = 0
    for i = 1, total do
        if player:addItem(typeId, 1, false) then
            added = added + 1
        end
    end

    if added < total then
        logFail(player, string.format(
            "Phase 7: Only %d/%d items added (inventory full?).", added, total
        ))
        safeRemoveAll(player, typeId)
        return false
    end

    -- Save with 3 items (async)
    local ok1 = player:saveAsync()
    if not ok1 then
        logFail(player, "Phase 7: saveAsync() S1 returned false - flush not queued.")
        safeRemoveAll(player, typeId)
        return false
    end

    -- Remove total-1 items
    for i = 1, total - 1 do
        player:removeItem(typeId, 1)
    end

    -- Save with 1 item (async, pendingFlushes)
    local ok2 = player:saveAsync()
    if not ok2 then
        logFail(player, "Phase 7: saveAsync() S2 returned false - test may be inconclusive.")
    end

    addEvent(function(pid2, guid2, tId, expected)
        local p = safePlayer(pid2, guid2)
        if not p then return end

        local cnt = countItemsInDB(guid2, tId)
        if cnt == expected then
            logPass(p, string.format(
                "Phase 7: DB=%d (expected %d). Partial removal saved correctly.", cnt, expected
            ))
        elseif cnt > expected then
            logFail(p, string.format(
                "Phase 7: DB=%d (expected %d) - %d EXTRA item(s) in the database! Ghost from an earlier save.",
                cnt, expected, cnt - expected
            ))
            logFail(p, "  -> {3 items} save reached the worker after {1 item} save. Player gets free items on re-login.")
        else
            logFail(p, string.format(
                "Phase 7: DB=%d (expected %d) - too many items removed in the database. Save did not persist.",
                cnt, expected
            ))
        end

        safeRemoveAll(p, tId)
        p:save()
    end, CFG.verify_delay, pid, guid, typeId, 1)

    return true
end

-- ============================================================================
-- PHASE 8  –  Full disconnect dupe simulation (worst case)
-- ============================================================================
--[[
  Combines all the previous vectors into a single worst-case test:

    1. addItem
    2. Flood A: N saves WITH item  (simulates auto-saves while the item was in the inventory)
    3. removeItem  (no save)
    4. Flood B: M saves WITHOUT item  (simulates saves after drop/disconnect)
    5. Final cleanup save
    6. Check: DB must be 0

  This is the exact scenario of:
    • Player picks up an item, carries it through several autosaves, drops it, disconnects
    • Player is in a trade, saves happen, trade is cancelled, immediate DC
    • Forge: item consumed, pending saves, server restarts before draining

  FAILURE = a real scenario that players would exploit.
--]]
local function runPhase8(player)
    local guid   = player:getGuid()
    local pid    = player:getId()
    local typeId = CFG.item_ns
    local burstA = math.max(1, math.ceil(CFG.save_burst / 2))  -- saves COM item
    local burstB = math.max(1, CFG.save_burst - burstA)         -- saves SEM item

    log(player, string.format(
        "Phase 8: Full simulation - %d saves w/item + remove + %d saves w/o item -> DB=0...",
        burstA, burstB
    ))
    log(player, "Phase 8: Scenario: pick up -> auto-saves -> drop/trade/DC -> verify.")

    safeRemoveAll(player, typeId)

    if not player:addItem(typeId, 1, false) then
        logFail(player, "Phase 8: Failed to create item.")
        return false
    end

    -- Flood A: saves WITH item (async)
    for i = 1, burstA do
        addEvent(function(pid2, guid2)
            local p = safePlayer(pid2, guid2)
            if p and not p:saveAsync() then
                logInfo(p, "Phase 8: saveAsync() flood A returned false - expected under saturation.")
            end
        end, i * CFG.stagger_ms, pid, guid)
    end

    -- Remove item (no save yet)
    local removeAt = burstA * CFG.stagger_ms + 80
    addEvent(function(pid2, guid2, tId)
        local p = safePlayer(pid2, guid2)
        if not p then return end
        p:removeItem(tId, 1)
    end, removeAt, pid, guid, typeId)

    -- Flood B: saves WITHOUT item (async)
    for i = 1, burstB do
        addEvent(function(pid2, guid2)
            local p = safePlayer(pid2, guid2)
            if p and not p:saveAsync() then
                logInfo(p, "Phase 8: saveAsync() flood B returned false - expected under saturation.")
            end
        end, removeAt + 20 + i * CFG.stagger_ms, pid, guid)
    end

    -- Final save (async)
    local finalAt = removeAt + 20 + burstB * CFG.stagger_ms + 80
    addEvent(function(pid2, guid2)
        local p = safePlayer(pid2, guid2)
        if p and not p:saveAsync() then
            logInfo(p, "Phase 8: saveAsync() final returned false.")
        end
    end, finalAt, pid, guid)

    -- Check
    addEvent(function(pid2, guid2, tId, nA, nB)
        local p = safePlayer(pid2, guid2)
        if not p then return end

        local cnt = countItemsInDB(guid2, tId)

        if cnt == 0 then
            logPass(p, string.format(
                "Phase 8: DB=0 - full simulation OK. %d saves w/item + remove + %d saves w/o item correct.",
                nA, nB
            ))
        elseif cnt > 0 then
            logFail(p, string.format(
                "Phase 8: DB=%d (expected 0) - ## DUPE CONFIRMED IN FULL SIMULATION ##",
                cnt
            ))
            logFail(p, string.format(
                "Phase 8: One of the %d saves {with item} reached the worker AFTER one of the %d saves {without item}.",
                nA, nB
            ))
            logFail(p, "  -> THIS IS THE EXACT SCENARIO exploited via trade/drop/quick DC.")
            logFail(p, "  -> Urgent fix: strict FIFO in the pendingFlushes drain.")
            safeRemoveAll(p, tId)
            p:save()
        else
            logFail(p, "Phase 8: DB query failed.")
        end
    end, finalAt + CFG.verify_delay, pid, guid, typeId, burstA, burstB)

    return true
end

-- ============================================================================
-- PHASE 9  –  Login Barrier Test (drainPlayerFlushAsync)
-- ============================================================================
--[[
  Tests the login barrier (PR#78 commits 06-09) directly via
  player:drainAsyncSave(callback).

  Simulated scenario:
    1. addItem → saveAsync(S0)  → snapshot WITH item, queued on the worker
    2. removeItem → saveAsync(S1) → snapshot WITHOUT item (pendingFlushes if S0 is in flight)
    3. drainAsyncSave() → waits for the flush chain to complete (S0 → S1)
    4. callback verifies DB=0

  Difference from Phase 2:
    Phase 2 uses verifyWithRetry (polling) to check the DB.
    Phase 9 uses the REAL login barrier (drainPlayerFlushAsync), which is the
    mechanism used at login in protocolgame.cpp. If the callback never fires,
    the phase fails by timeout (10s).

  FAILURE HERE = the login barrier is not working correctly.
--]]
local function runPhase9(player)
    local guid   = player:getGuid()
    local pid    = player:getId()
    local typeId = CFG.item_ns

    logHeader(player, "Phase 9: Login Barrier Test - drainAsyncSave + callback verification")

    safeRemoveAll(player, typeId)

    if not player:addItem(typeId, 1, false) then
        logFail(player, "Phase 9: Failed to create item. Adjust CFG.item_ns.")
        return false
    end

    -- S0: snapshot WITH item (async)
    local ok0 = player:saveAsync()
    if not ok0 then
        logFail(player, "Phase 9: saveAsync() S0 returned false.")
        safeRemoveAll(player, typeId)
        return false
    end

    -- Remove item (simulates a player dropping an item between autosave and logout)
    player:removeItem(typeId, 1)

    -- S1: snapshot WITHOUT item (async — pendingFlushes if S0 is still in flight)
    local ok1 = player:saveAsync()
    if not ok1 then
        logInfo(player, "Phase 9: saveAsync() S1 returned false (flush in progress) - normal.")
    end

    log(player, "Phase 9: S0 and S1 queued. Calling drainAsyncSave()...")

    -- Safety timeout: if the callback never fires, fail after 12s
    local timedOut = false
    local timeoutEvent = addEvent(function(pid2, guid2)
        local p = safePlayer(pid2, guid2)
        if p then
            logFail(p, "Phase 9: TIMEOUT - drainAsyncSave callback did not fire within 12s.")
            logFail(p, "  -> The login barrier may have a problem in flushChainCallbacks.")
            safeRemoveAll(p, typeId)
            p:save()
        end
        timedOut = true
    end, 12000, pid, guid)

    -- Uses the real login barrier
    player:drainAsyncSave(function(drained)
        if timedOut then
            -- Timeout already handled it, ignore late callback
            return
        end
        stopEvent(timeoutEvent)

        local p = safePlayer(pid, guid)
        if not p then
            logFail(nil, "Phase 9: Player disconnected during drainAsyncSave.")
            return
        end

        if not drained then
            logFail(p, "Phase 9: drainAsyncSave returned false - flush chain failed or internal timeout.")
            safeRemoveAll(p, typeId)
            p:save()
            return
        end

        -- Barrier completed: check DB
        local cnt = countItemsInDB(guid, typeId)
        if cnt == 0 then
            logPass(p, string.format(
                "Phase 9: DB=0 after drainAsyncSave. Login barrier functional! " ..
                "(S0 w/item -> S1 w/o item -> drain -> DB=0)"
            ))
        elseif cnt > 0 then
            logFail(p, string.format(
                "Phase 9: DB=%d (expected 0) - ## LOGIN BARRIER FAILED ##", cnt
            ))
            logFail(p, "  -> drainAsyncSave returned true but the DB still contains the item.")
            logFail(p, "  -> Possible: S1 was not executed, or the flush chain ignored pendingFlushes.")
            safeRemoveAll(p, typeId)
            p:save()
        else
            logFail(p, "Phase 9: DB query failed.")
        end
    end)

    return true
end

-- ============================================================================
-- TALKACTION
-- ============================================================================
local dupeAction = TalkAction("/dupe")
dupeAction:separator(" ")
dupeAction:access(true)

function dupeAction.onSay(player, words, param)
    if not player:getGroup():getAccess() then
        return false
    end

    local cmd = (param or ""):lower():match("^%s*(.-)%s*$")

    -- ── INFO ──────────────────────────────────────────────────────────────────
    if cmd == "info" then
        local lines = {
            "=== DupeTest | 9 phases | item duplication vulnerability scanner ===",
            "Ph1  Ghost item: flood saves -> remove -> verify DB=0",
            "Ph2  * SNAPSHOT RACE: add->save(S1)->remove->save(S2) | S2 must win",
            "Ph3  Stackable count: add 200->save->remove 100->save->verify SUM=100",
            "Ph4  5 rounds: add->save->remove->save | final DB=0",
            "Ph5  20x addEvent(0) simultaneous saves + remove | DB=0",
            "Ph6  Reversal: [A]->save->swap for B->save | only B in the DB",
            "Ph7  Multi-item: add 3->remove 2->save | DB must have 1",
            "Ph8  Full simulation: flood w/item + removal + flood w/o item",
            "Ph9  * LOGIN BARRIER: drainAsyncSave + callback | tests PR#78",
            "Usage: /dupe [start|1-9|info|clean]",
            string.format("CFG: item_ns=%d item_st=%d verify_delay=%dms",
                CFG.item_ns, CFG.item_st, CFG.verify_delay),
        }
        for _, l in ipairs(lines) do
            player:sendTextMessage(MSG_BLUE, l)
        end
        return false
    end

    -- ── CLEAN ─────────────────────────────────────────────────────────────────
    if cmd == "clean" then
        if activeRuns[player:getGuid()] then
            log(player, "Test in progress – wait for it to finish before cleaning.")
            return false
        end
        safeRemoveAll(player, CFG.item_ns)
        safeRemoveAll(player, CFG.item_st)
        player:save()
        log(player, "Test items removed from the inventory and save done.")
        return false
    end

    local phaseMap = {
        [1] = runPhase1, [2] = runPhase2, [3] = runPhase3, [4] = runPhase4,
        [5] = runPhase5, [6] = runPhase6, [7] = runPhase7, [8] = runPhase8,
        [9] = runPhase9,
    }

    -- ── SINGLE PHASE ───────────────────────────────────────────────────────
    local phaseNum = tonumber(cmd)
    if phaseNum then
        if activeRuns[player:getGuid()] then
            log(player, "Test in progress – wait for it to finish before starting a new phase.")
            return false
        end
        if hasPreExistingTestItems(player, player:getGuid()) then
            logFail(player, string.format(
                "Inventory already contains items of types %d and/or %d. Use /dupe clean first.",
                QA_ITEM_NS, QA_ITEM_ST
            ))
            return false
        end
        local fn = phaseMap[phaseNum]
        if fn then
            activeRuns[player:getGuid()] = true
            local ok, err = xpcall(fn, debug.traceback, player)
            if not ok then
                logFail(player, "Phase " .. phaseNum .. " hit an error: " .. tostring(err))
                activeRuns[player:getGuid()] = false
            else
                local maxDuration = math.max(
                    CFG.save_burst * CFG.stagger_ms + 100 + CFG.verify_delay + 500,
                    CFG.verify_delay + 800 * 3 + 500,
                    2 * CFG.verify_delay + 800,
                    5 * 300 + CFG.verify_delay + 500,
                    14000                              -- Ph9: timeout 12s + buffer
                ) + 500
                local guid = player:getGuid()
                addEvent(function(g) activeRuns[g] = false end, maxDuration, guid)
            end
        else
            player:sendTextMessage(MSG_BLUE, "Invalid phase. Use 1-9, start, info or clean.")
        end
        return false
    end

    -- ── START – all phases in sequence ───────────────────────────────────────
    if cmd == "" or cmd == "start" or cmd == "all" then
        if activeRuns[player:getGuid()] then
            log(player, "DupeTest already in progress – wait for it to finish.")
            return false
        end
        if hasPreExistingTestItems(player, player:getGuid()) then
            logFail(player, string.format(
                "Inventory already contains items of types %d and/or %d. Use /dupe clean first.",
                QA_ITEM_NS, QA_ITEM_ST
            ))
            return false
        end
        activeRuns[player:getGuid()] = true

        -- Each phase needs:
        --   Phase 3 has nested 2x verify_delay → slower
        --   Phase 4 has rounds * roundMs + verify_delay
        -- We use a conservative window that covers the worst case (Ph3/Ph4).
        local phaseDuration = math.max(
            5 * 300 + CFG.verify_delay + 500,        -- Ph4: rounds*roundMs + verify + buf
            2 * CFG.verify_delay + 800,              -- Ph3: 2x nested addEvent
            12000 + 2000                             -- Ph9: timeout 12s + buffer
        ) + 500  -- extra buffer between phases

        logHeader(player, string.format(
            "=== DupeTest | 9 phases | item_ns=%d item_st=%d | ~%.0fs total ===",
            CFG.item_ns, CFG.item_st, (9 * phaseDuration) / 1000
        ))

        local pid = player:getId()
        local guid = player:getGuid()

        for i = 1, 9 do
            addEvent(function(pid2, g2, idx)
                local p = safePlayer(pid2, g2)
                if not p then return end
                logHeader(p, string.format("-- Starting Phase %d/9 --", idx))
                local fn = phaseMap[idx]
                if fn then fn(p) end
            end, (i - 1) * phaseDuration, pid, guid, i)
        end
        -- Final summary
        phaseFailed[guid] = nil
        addEvent(function(pid2, g)
            local p = safePlayer(pid2, g)
            if p then
                if phaseFailed[g] then
                    logHeader(p, "=== DupeTest COMPLETE - ONE OR MORE PHASES FAILED ===")
                else
                    logHeader(p, "=== DupeTest COMPLETE - ALL 9 PHASES PASSED ===")
                end
            end
            activeRuns[g] = false
            phaseFailed[g] = nil
        end, 9 * phaseDuration + 1500, pid, guid)

        logHeader(player, string.format(
            "Phases spaced ~%.0fs each | Ph9 uses drainAsyncSave (real barrier) | results appear gradually.",
            phaseDuration / 1000
        ))
        return false
    end

    player:sendTextMessage(MSG_BLUE, "Usage: /dupe [start|1-9|info|clean]")
    return false
end

dupeAction:accountType(6)
dupeAction:register()
