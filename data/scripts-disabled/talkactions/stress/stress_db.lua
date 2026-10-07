--[[
================================================================================
  stress_db_pr69.lua  -  RevScript  (TFS 1.8 / 8.60 downgrade fork)
  Stress test for PR #69 - "Port threaded database login save"
  Repository: Mateuzkl/forgottenserver-downgrade-1.8-8.60
================================================================================

  USAGE (GMs only, with getAccess() == true):
    /stress_db start   - runs all 11 phases in sequence
    /stress_db 1-11    - runs a single phase
    /stress_db diag    - InnoDB diagnostics only (Phase 10, non-destructive)
    /stress_db info    - describes each phase and what it tests
    /stress_db clean   - drops the table stress_pr69

  PHASES AND SQL EXERCISED:
  ┌────┬────────────────────────────────┬────────────────────────────────────────┐
  │ Ph │ Area tested                    │ SQL / API                              │
  ├────┼────────────────────────────────┼────────────────────────────────────────┤
  │  1 │ ConnectionContext lazy         │ INSERT flood + db.escapeString()       │
  │    │ LAST_INSERT_ID / auto-commit   │ SELECT LAST_INSERT_ID()                │
  │  2 │ buildPlayerSave dirty snapshot │ WHERE key IN (...) + result:next()     │
  │  3 │ flushInFlight / pendingFlushes │ player:save() rapid-fire              │
  │  4 │ Deadlock retry ×3             │ SELECT...FOR UPDATE + Innodb_deadlocks │
  │  5 │ Mixed R/W / handle lifecycle   │ addEvent bursts (concurrent workers)   │
  │  6 │ Integrity count/dup/gap        │ EXPLAIN + ANALYZE TABLE                │
  │  7 │ Transaction atomicity           │ START TRANSACTION + COMMIT + ROLLBACK  │
  │  8 │ DELETE + re-INSERT (real save) │ player_storage save pattern complete   │
  │  9 │ Batch INSERT in transaction    │ multi-row VALUES() in a single query   │
  │ 10 │ InnoDB diagnostics             │ SHOW STATUS + SHOW ENGINE INNODB STATUS│
  │ 11 │ UPSERT (ON DUPLICATE KEY)      │ INSERT...ON DUPLICATE KEY UPDATE       │
  └────┴────────────────────────────────┴────────────────────────────────────────┘

  WHAT WAS FIXED/ADDED vs previous version:
    + db.escapeString() on every parameterized string
    + result:next() loop - Ph2 from 60 SELECTs → 1 query with IN(...)
    + START TRANSACTION / COMMIT / ROLLBACK explicit (Ph7)
    + ROLLBACK atomicity verification (Ph7b)
    + SELECT ... FOR UPDATE (Ph4) - correct row locking
    + Innodb_deadlocks delta before/after Phase 4
    + transactional DELETE + re-INSERT (Ph8) - mirrors the player_storage save
    + Batch multi-row INSERT in a single query (Ph9)
    + SHOW STATUS + SHOW ENGINE INNODB STATUS (Ph10)
    + EXPLAIN to verify index usage (Ph6/Ph10)
    + SELECT LAST_INSERT_ID() - verifies getLastInsertId() from the PR (Ph1)
    + ON DUPLICATE KEY UPDATE - real IOLoginData pattern (Ph11)
    + addEvent(0) concurrent burst in Ph5 (previously a synchronous loop)

  SAFETY:
    • Isolated table `stress_pr69` - never touches production tables.
    • Storage keys above STORAGE_BASE (95000) - cleaned up at the end of Ph2/Ph3.
    • run_id unique per run (os.time() % 65535) - runs do not overlap.
    • Requires player:getGroup():getAccess() == true.
================================================================================
--]]

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local STRESS_TABLE = "stress_pr69"
local STORAGE_BASE = 95000   -- change if it collides with your server's storage keys
local REPORT_DELAY = 15000   -- INCREASED TO 15 SECONDS (Required to give the huge queue time to drain)

local CFG = {
    -- Phase 1: Massive flood of loose connections vs a single transaction
    ph1_inserts        = 5000,  -- 5 thousand individual INSERTs opening/closing transactions (auto-commit hammered)
    ph1_tx_batch       = 2000,  -- 2 thousand INSERTs inside a single explicit transaction block

    -- Phase 2: Giant query with an IN (...) clause
    ph2_storage_keys   = 1000,  -- 1,000 keys fetched at once, testing the MySQL query parser

    -- Phase 3: I/O machine gun on the Main Thread (real risk of freezing the game)
    ph3_save_count     = 300,   -- 300 forced player saves in a row
    ph3_stagger_ms     = 0,     -- 0ms or 1ms: no interval! Everything gets queued in the same execution frame

    -- Phase 4: Lock chaos (deadlock war in InnoDB)
    ph4_sentinel_rows  = 30,    -- 30 rows under heavy contention
    ph4_update_bursts  = 600,   -- 600 simultaneous crossed updates trying to lock each other

    -- Phase 5: Maximum saturation of the async worker pool
    ph5_event_bursts   = 1500,  -- 1,500 parallel async tasks thrown into the queue all at once

    -- Phase 7: Redo/Undo log stress test (heavy rollback)
    ph7_commit_rows    = 1500,  -- 1,500 committed rows
    ph7_rollback_rows  = 800,   -- 800 rows written and then undone (severely tests the Undo buffers)

    -- Phase 8: Table fragmentation
    ph8_rows           = 1000,  -- Deletes and re-inserts 1,000 rows simulating a real storage save

    -- Phase 9: MySQL network packet limit test
    ph9_batch_size     = 3500,  -- A single MONSTROUS query string containing 3,500 rows of data

    -- Phase 11: Simultaneous upserts (two operations per row)
    ph11_upsert_rows   = 1000,  -- 1,000 inserts with primary key collision handling
}

-- Message constants may differ between forks.
local MSG_BLUE = MESSAGE_STATUS_CONSOLE_BLUE or MESSAGE_EVENT_ADVANCE or 19
local MSG_RED = MESSAGE_STATUS_CONSOLE_RED or MESSAGE_STATUS_WARNING or MSG_BLUE

local activeRuns = {}  -- Indexed by player GUID to allow multiple GMs
local asyncResults = {}  -- asyncResults[guid][phase] = true/false for phases with an async callback
local asyncPending = {}  -- asyncPending[guid] = count of async callbacks not yet resolved
local settleData = {}    -- settleData[guid] = {pid, guid, runId, wallStart, results} for the final summary

-- ============================================================================
-- UTILITIES
-- ============================================================================

-- ANSI codes for console colors
local COLOR_RESET = "\27[0m"
local COLOR_BLUE = "\27[94m"
local COLOR_GREEN = "\27[32m"
local COLOR_YELLOW = "\27[33m"
local COLOR_RED = "\27[31m"
local COLOR_ORANGE = "\27[38;5;208m"

local function colorPhase(msg)
    local out = msg:gsub("(Phase %d+[abc]? [A-Z]+:)", COLOR_ORANGE .. "%1" .. COLOR_RESET)
    out = out:gsub("(Phase %d+[abc]?:)", COLOR_ORANGE .. "%1" .. COLOR_RESET)
    out = out:gsub("(Ph%d+ [A-Z]+:)", COLOR_ORANGE .. "%1" .. COLOR_RESET)
    out = out:gsub("(Ph%d+:)", COLOR_ORANGE .. "%1" .. COLOR_RESET)
    return out
end

local function log(player, msg)
    print(COLOR_BLUE .. "[StressDB]" .. COLOR_RESET .. " " .. colorPhase(msg))
    if player and player:isPlayer() then
        player:sendTextMessage(MSG_BLUE, "[StressDB] " .. colorPhase(msg))
    end
end

local function logFail(player, msg)
    print(COLOR_BLUE .. "[StressDB]" .. COLOR_RED .. "[FAIL]" .. COLOR_RESET .. " " .. colorPhase(msg))
    if player and player:isPlayer() then
        player:sendTextMessage(MSG_RED, "[StressDB][FAIL] " .. colorPhase(msg))
    end
end

local function logPass(player, msg)
    print(COLOR_BLUE .. "[StressDB]" .. COLOR_YELLOW .. "[PASS]" .. COLOR_RESET .. " " .. colorPhase(msg))
    if player and player:isPlayer() then
        player:sendTextMessage(MSG_BLUE, "[StressDB][PASS] " .. colorPhase(msg))
    end
end

local function logInfo(player, msg)
    print(COLOR_BLUE .. "[StressDB]" .. COLOR_GREEN .. "[INFO]" .. COLOR_RESET .. " " .. colorPhase(msg))
    if player and player:isPlayer() then
        player:sendTextMessage(MSG_BLUE, "[StressDB][INFO] " .. colorPhase(msg))
    end
end

local function safePlayer(pid, expectedGuid)
    local p = Player(pid)
    if not p then
        print("[StressDB] Player id=" .. tostring(pid) .. " disconnected during the test.")
        return nil
    end
    if expectedGuid and p:getGuid() ~= expectedGuid then
        print("[StressDB] Player id=" .. tostring(pid) .. " GUID mismatch (recycled PID?). Ignoring.")
        return nil
    end
    return p
end

-- Compatibility between forks:
-- In regular TFS db.escapeString("abc") already returns 'abc'.
-- In some forks it may return just abc. This function always returns a quoted SQL string.
local function sqlString(value)
    local escaped = db.escapeString(tostring(value or ""))
    if not escaped or escaped == "" then
        return "''"
    end

    local first = escaped:sub(1, 1)
    local last = escaped:sub(-1)
    if first == "'" and last == "'" then
        return escaped
    end
    return "'" .. escaped .. "'"
end

-- Wrapper for db.storeQuery that returns a compatible Result object
-- Reads a MySQL STATUS variable as a number (0 if not found)
local function readStatusVar(varName)
    local res = db.storeQuery("SHOW STATUS LIKE " .. sqlString(varName))
    if not res or res == false or res == nil then return 0 end
    local v = tonumber(result.getString(res, "Value")) or 0
    result.free(res)
    return v
end

-- Callback table to avoid upvalue capture (TFS closures lose forward references)
local PhaseCallbacks = {}

-- Marks an async phase as complete. When all finish, schedules finalization via PhaseCallbacks.
local function completeAsyncPhase(guid, phase, ok)
    if not asyncResults[guid] or not asyncPending[guid] then return end
    asyncResults[guid][phase] = ok
    asyncPending[guid] = asyncPending[guid] - 1
    if asyncPending[guid] <= 0 and settleData[guid] then
        if PhaseCallbacks.finalize then
            addEvent(PhaseCallbacks.finalize, 1, guid)
        end
    end
end

-- ============================================================================
-- SETUP / TEARDOWN
-- ============================================================================
local function setupTable()
    -- Uses CREATE TABLE IF NOT EXISTS so it does not destroy the table of another GM running in parallel
    return db.query(string.format([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id`      INT UNSIGNED      NOT NULL AUTO_INCREMENT,
            `run_id`  SMALLINT UNSIGNED NOT NULL DEFAULT 0,
            `phase`   TINYINT UNSIGNED  NOT NULL DEFAULT 0,
            `seq`     INT UNSIGNED      NOT NULL DEFAULT 0,
            `label`   VARCHAR(128)      NOT NULL DEFAULT '',
            `counter` INT               NOT NULL DEFAULT 0,
            `ts`      BIGINT            NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uq_run_phase_seq` (`run_id`, `phase`, `seq`),
            KEY `idx_run_phase` (`run_id`, `phase`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], STRESS_TABLE))
end

-- ============================================================================
-- PHASE 1 - INSERT flood + db.escapeString + LAST_INSERT_ID
-- ============================================================================
--[[
  Tests the PR's thread_local ConnectionContext (dispatcher thread).
  Ensures the connection is created lazily and stays open between queries.
  NEW vs previous version:
    • db.escapeString() on ALL string values - prevents SQL injection
      even in a test script and confirms the API works correctly.
    • Sub-test with explicit transaction: START TRANSACTION + ph1_tx_batch
      INSERTs + COMMIT - compares throughput with/without auto-commit.
    • SELECT LAST_INSERT_ID() after INSERT - tests Database::getLastInsertId()
      which the PR keeps per ConnectionContext (connection affinity).
  EXPECTED FAILURE IF: db.escapeString() returns nil, LAST_INSERT_ID is 0,
  or transaction throughput is lower than auto-commit (indicates overhead).
--]]
local function runPhase1(player, runId)
    local n  = CFG.ph1_inserts
    local nb = CFG.ph1_tx_batch

    log(player, string.format("Phase 1: INSERT flood - %d auto-commit + %d in transaction...", n, nb))

    -- ── 1a: individual auto-commit ──────────────────────────────────────────
    local t0 = os.clock()
    local ok, fail = 0, 0

    for i = 1, n do
        -- db.escapeString() on every parameterized string
        local safeLabel = sqlString("ph1_ac_" .. i)
        local q = string.format(
            "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`ts`) VALUES (%d,1,%d,%s,%d)",
            STRESS_TABLE, runId, i, safeLabel, os.time()
        )
        if db.query(q) then ok = ok + 1 else fail = fail + 1 end
    end

    local elapsedAC = (os.clock() - t0)
    local qpsAC = ok / (elapsedAC + 1e-9)

    -- ── 1b: inside an explicit transaction ────────────────────────────────────
    -- Mirrors what flushPlayerSave does: opens TX, replays N queries, COMMIT
    local t1 = os.clock()
    local txOk = true

    db.query("START TRANSACTION")
    for i = 1, nb do
        local safeLabel = sqlString("ph1_tx_" .. i)
        local q = string.format(
            "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`ts`) VALUES (%d,1,%d,%s,%d)",
            STRESS_TABLE, runId, n + i, safeLabel, os.time()
        )
        if not db.query(q) then txOk = false end
    end
    if txOk then db.query("COMMIT") else db.query("ROLLBACK") end

    local elapsedTX = (os.clock() - t1)
    local qpsTX = nb / (elapsedTX + 1e-9)

    -- ── 1c: LAST_INSERT_ID - verifies connection affinity (worker thread) ──
    -- Runs on scheduler thread via addEvent to exercise per-thread ConnectionContext
    local playerId = player:getId()
    local playerGuid = player:getGuid()
    local runIdC = runId
    local failC = fail
    local txOkC = txOk
    local elapsedACC = elapsedAC
    local elapsedTXC = elapsedTX
    local qpsACC = qpsAC
    local qpsTXC = qpsTX
    local nC = n
    local nbC = nb

    addEvent(function(pId, guid, rId, nVal, nbVal, failVal, txOkVal, elapsedAC, elapsedTX, qpsAC, qpsTX)
        local p = safePlayer(pId, guid)
        if not p then
            completeAsyncPhase(guid, 1, false)
            return
        end

        local safeLabel2 = sqlString("ph1_lastid_probe")
        db.query(string.format(
            "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`ts`) VALUES (%d,1,%d,%s,%d)",
            STRESS_TABLE, rId, nVal + nbVal + 1, safeLabel2, os.time()
        ))
        local lastId = db.lastInsertId()

        local ph1cOk = (failVal == 0 and txOkVal and lastId > 0)

        if ph1cOk then
            logPass(p, string.format(
                "Phase 1: AC=%d/%d (%.0f q/s | %.1fms) | TX=%d (%.0f q/s | %.1fms) | LAST_INSERT_ID=%d",
                nVal, nVal, qpsAC, elapsedAC * 1000,
                nbVal, qpsTX, elapsedTX * 1000,
                lastId
            ))
        else
            if failVal > 0 then
                logFail(p, string.format("Phase 1: %d INSERTs failed - check ConnectionContext.", failVal))
            end
            if not txOkVal then
                logFail(p, "Phase 1: INSERT inside a transaction failed - problem with START TRANSACTION/COMMIT.")
            end
            if lastId == 0 then
                logFail(p, "Phase 1: LAST_INSERT_ID=0 - getLastInsertId() may be returning from the wrong connection!")
            end
        end

        completeAsyncPhase(guid, 1, ph1cOk)
    end, 1, playerId, playerGuid, runIdC, nC, nbC, failC, txOkC, elapsedACC, elapsedTXC, qpsACC, qpsTXC)

    -- Phase 1c runs async; return early (pass/fail reported via callback above)

    -- ── Result (Phases 1a + 1b) ────────────────────────────────────────────
    if fail == 0 and txOk then
        logInfo(player, string.format(
            "Phase 1a-b: AC=%d/%d (%.0f q/s | %.1fms) | TX=%d (%.0f q/s | %.1fms) | Phase 1c async...",
            ok, n, qpsAC, elapsedAC * 1000,
            nb, qpsTX, elapsedTX * 1000
        ))
    else
        if fail > 0 then
            logFail(player, string.format("Phase 1: %d INSERTs failed - check ConnectionContext.", fail))
        end
        if not txOk then
            logFail(player, "Phase 1: INSERT inside a transaction failed - problem with START TRANSACTION/COMMIT.")
        end
    end

    return fail == 0 and txOk
end

-- ============================================================================
-- PHASE 2 - Storage dirty snapshot  (buildPlayerSave + flushPlayerSave)
-- ============================================================================
--[[
  Tests that buildPlayerSave() captures the correct snapshot of
  modifiedStorageKeys and removedStorageKeys, and that flushPlayerSave()
  replays the SQL in a transaction on the worker.
  NEW vs previous version:
    • Check rewritten with ONE query using WHERE key IN (...) +
      result:next() loop - it used to be 60 individual SELECTs (1 per key).
      This also tests that result:next() works correctly for
      multi-row results and that result:free() does not leak handles.
  EXPECTED FAILURE IF: snapshot omitted keys (missing in the database), removed keys
  still show up, result:next() stops too early, or a value is wrong.
--]]
local function runPhase2(player, runId)
    local n    = CFG.ph2_storage_keys
    local base = STORAGE_BASE + 2000  -- Phase 2 uses +2000 (range: 97001-98000) | Phase 3 uses +4000 (99000) - no collision

    log(player, string.format("Phase 2: Storage dirty snapshot - %d keys (check with IN + next())...", n))

    -- Sets all keys; removes the even ones
    local t0 = os.clock()
    for i = 1, n do
        player:setStorageValue(base + i, i * 7)
    end
    for i = 1, n do
        if i % 2 == 0 then
            player:setStorageValue(base + i, -1)  -- -1 = removes in TFS
        end
    end
    log(player, string.format(
        "Phase 2: %d set | %d for removal | %.1fms | triggering save...",
        n, math.floor(n / 2), (os.clock() - t0) * 1000
    ))

    local saved = player:save()
    if not saved then
        logFail(player, "Phase 2: player:save() returned false!")
        return false
    end

    local pid  = player:getId()
    local guid = player:getGuid()

    addEvent(function(playerId, playerGuid, nKeys, keyBase)
        local p = safePlayer(playerId, playerGuid)
        if not p then
            completeAsyncPhase(playerGuid, 2, false)
            return
        end

        -- Builds the IN(key1, key2, ...) list of all expected odd keys
        local presentKeys = {}
        for i = 1, nKeys do
            if i % 2 ~= 0 then
                presentKeys[#presentKeys + 1] = tostring(keyBase + i)
            end
        end
        local inList = table.concat(presentKeys, ",")

        -- A single query fetches all keys expected to be present
        local found = {}  -- found[key] = value
        local res = db.storeQuery(string.format(
            "SELECT `key`, `value` FROM `player_storage` WHERE `player_id`=%d AND `key` IN (%s)",
            playerGuid, inList
        ))
        if res and res ~= false and res ~= nil then
            repeat
                local k = result.getNumber(res, "key")
                local v = result.getNumber(res, "value")
                found[k] = v
            until not result.next(res)  -- ← result:next() iterates multi-row
            result.free(res)
        end

        -- Checks odd keys (must be present with value i*7)
        local missingPresent, wrongValue = 0, 0
        for i = 1, nKeys do
            if i % 2 ~= 0 then
                local key = keyBase + i
                local v   = found[key]
                if v == nil then
                    missingPresent = missingPresent + 1
                elseif v ~= i * 7 then
                    wrongValue = wrongValue + 1
                end
            end
        end

        -- Checks even keys (must NOT be in the database)
        local wronglyPresent = 0
        local evenKeys = {}
        for i = 1, nKeys do
            if i % 2 == 0 then
                evenKeys[#evenKeys + 1] = tostring(keyBase + i)
            end
        end
        local res2 = db.storeQuery(string.format(
            "SELECT COUNT(*) AS cnt FROM `player_storage` WHERE `player_id`=%d AND `key` IN (%s)",
            playerGuid, table.concat(evenKeys, ",")
        ))
        if res2 and res2 ~= false and res2 ~= nil then
            wronglyPresent = result.getNumber(res2, "cnt")
            result.free(res2)
        end

        local expPresent = math.ceil(nKeys / 2)
        local expAbsent  = math.floor(nKeys / 2)
        local total = missingPresent + wrongValue + wronglyPresent

        if total == 0 then
            logPass(p, string.format(
                "Phase 2: %d present OK | %d absent OK | result:next() iterated %d rows correctly",
                expPresent, expAbsent, #presentKeys
            ))
        else
            logFail(p, string.format(
                "Phase 2: %d missing | %d wrong value | %d not removed from the database",
                missingPresent, wrongValue, wronglyPresent
            ))
            logFail(p, "  -> Check buildPlayerSave snapshot + result:next() of storeQuery.")
        end

        completeAsyncPhase(playerGuid, 2, total == 0)

        -- Cleanup
        for i = 1, nKeys do
            p:setStorageValue(keyBase + i, -1)
        end
        p:save()

    end, REPORT_DELAY + 800, pid, guid, n, base)

    return true
end

-- ============================================================================
-- PHASE 3 - Save flood  (flushInFlight + pendingFlushes ordering)
-- ============================================================================
--[[
  (no structural changes - logic was already correct)
  Schedules N saves with a stagger_ms interval. Each save writes a
  different value to the same storage key. The LAST value must persist.
--]]
local function runPhase3(player, runId)
    local n       = CFG.ph3_save_count
    local stagger = CFG.ph3_stagger_ms
    local key     = STORAGE_BASE + 4000  -- Changed +3000 to +4000 to avoid collision with Phase 2 (97001-98000)
    local pid     = player:getId()
    local guid    = player:getGuid()

    log(player, string.format(
        "Phase 3: Save flood - %d saves | stagger=%dms | key=%d...",
        n, stagger, key
    ))

    for i = 1, n do
        addEvent(function(playerId, playerGuid, iteration, storageKey)
            local p = safePlayer(playerId, playerGuid)
            if not p then return end
            p:setStorageValue(storageKey, iteration * 99)
            p:save()
        end, i * stagger, pid, guid, i, key)
    end

    local verifyDelay = (n * stagger) + REPORT_DELAY + 1000

    addEvent(function(playerId, playerGuid, storageKey, expectedVal, totalSaves)
        local p = safePlayer(playerId, playerGuid)
        if not p then
            completeAsyncPhase(playerGuid, 3, false)
            return
        end

        local res = db.storeQuery(string.format(
            "SELECT `value` FROM `player_storage` WHERE `player_id`=%d AND `key`=%d",
            playerGuid, storageKey
        ))
        local ph3ok = false

        if res and res ~= false and res ~= nil then
            local dbVal = result.getNumber(res, "value")
            result.free(res)
            ph3ok = (dbVal == expectedVal)
            if ph3ok then
                logPass(p, string.format(
                    "Phase 3: DB=%d (expected %d) - flush ordering OK (%d saves)",
                    dbVal, expectedVal, totalSaves
                ))
            else
                logFail(p, string.format(
                    "Phase 3: DB=%d expected=%d - ORDERING BUG in pendingFlushes!",
                    dbVal, expectedVal
                ))
                logFail(p, "  -> Check SaveManager::onPlayerFlushed + pendingFlushes drain.")
            end
        else
            logFail(p, string.format(
                "Phase 3: key %d not found in the database - save DISCARDED!", storageKey
            ))
        end

        p:setStorageValue(storageKey, -1)
        p:save()

        completeAsyncPhase(playerGuid, 3, ph3ok)

    end, verifyDelay, pid, guid, key, n * 99, n)

    log(player, string.format("Phase 3: %d saves scheduled | result in ~%dms", n, verifyDelay))
    return true
end

-- ============================================================================
-- PHASE 4 - Lock contention + SELECT...FOR UPDATE + Innodb_deadlocks delta
-- ============================================================================
--[[
  Tests DBTransaction::executeWithinTransactionRollbackOnFailure (retry ×3).

  NEW vs previous version:
    • SELECT ... FOR UPDATE before the UPDATE - explicit row lock,
      the correct pattern to generate a deadlock/lock-wait in InnoDB.
      Without it, auto-commit UPDATEs rarely produce a real deadlock.
    • Reads SHOW STATUS LIKE 'Innodb_deadlocks' BEFORE and AFTER the bursts.
      Prints the real deadlock delta that InnoDB recorded.
      This confirms whether the retry path was actually triggered.
    • Reads 'Innodb_row_lock_waits' and 'Innodb_row_lock_time_avg' to
      show contention latency.

  EXPECTED FAILURE IF: counter < expected (update lost without retry),
  or delta_deadlocks == 0 (no real deadlock generated - trivial test).
--]]
local function runPhase4(player, runId)
    local rows  = CFG.ph4_sentinel_rows
    local burst = CFG.ph4_update_bursts
    local pid   = player:getId()
    local guid  = player:getGuid()

    log(player, string.format(
        "Phase 4: Lock contention + FOR UPDATE - %d rows x %d bursts...",
        rows, burst
    ))

    -- Reads InnoDB counters BEFORE the bursts
    local deadlocksBefore  = readStatusVar("Innodb_deadlocks")
    local lockWaitsBefore  = readStatusVar("Innodb_row_lock_waits")

    -- Inserts sentinel rows with counter=0
    local inserted = 0
    for r = 1, rows do
        local safeLabel = sqlString("sentinel_" .. r)
        if db.query(string.format(
            "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`counter`,`ts`) VALUES (%d,4,%d,%s,0,%d)",
            STRESS_TABLE, runId, r, safeLabel, os.time()
        )) then
            inserted = inserted + 1
        end
    end

    if inserted == 0 then
        logFail(player, "Phase 4: Failed to insert sentinels. Aborting.")
        return false
    end

    if inserted ~= rows then
        logFail(player, string.format(
            "Phase 4: Inconsistency - inserted=%d != rows=%d. Aborting.", inserted, rows
        ))
        return false
    end

    -- Computes the expected total and fires UPDATE bursts with FOR UPDATE
    -- NOTE: each UPDATE affects 2 rows (seq IN (first, second)), except when seqA == seqB (rows=1: touches only 1 row)
    local totalExpected = 0
    for b = 1, burst do
        local inc = (b % 2 == 0) and 2 or 1
        -- Each burst × inserted rows, but each UPDATE touches 2 rows (or 1 if rows=1)
        local rowsPerUpdate = (rows == 1) and 1 or 2
        totalExpected = totalExpected + (inc * inserted * rowsPerUpdate)

        for r = 1, rows do
            local seqA = r
            local seqB = (r % rows) + 1
            addEvent(function(tbl, rId, a, b, increment)
                -- SELECT ... FOR UPDATE on two rows with opposite lock order
                -- to generate a real deadlock between concurrent workers.
                local first = increment % 2 == 1 and a or b
                local second = increment % 2 == 1 and b or a
                db.query("START TRANSACTION")
                local lockRes1 = db.storeQuery(string.format(
                    "SELECT `counter` FROM `%s` WHERE `run_id`=%d AND `phase`=4 AND `seq`=%d FOR UPDATE",
                    tbl, rId, first
                ))
                local lockRes2 = db.storeQuery(string.format(
                    "SELECT `counter` FROM `%s` WHERE `run_id`=%d AND `phase`=4 AND `seq`=%d FOR UPDATE",
                    tbl, rId, second
                ))
                if lockRes1 and lockRes1 ~= false
                   and lockRes2 and lockRes2 ~= false then
                    result.free(lockRes1)
                    result.free(lockRes2)
                    db.query(string.format(
                        "UPDATE `%s` SET `counter`=`counter`+%d, `ts`=%d WHERE `run_id`=%d AND `phase`=4 AND `seq` IN (%d,%d)",
                        tbl, increment, os.time(), rId, first, second
                    ))
                    db.query("COMMIT")
                else
                    if lockRes1 and lockRes1 ~= false then result.free(lockRes1) end
                    if lockRes2 and lockRes2 ~= false then result.free(lockRes2) end
                    db.query("ROLLBACK")
                end
            end, 0, STRESS_TABLE, runId, seqA, seqB, inc)
        end
    end

    local verifyDelay = REPORT_DELAY + 2000

    addEvent(function(playerId, playerGuid, rId, nRows, expected, dlBefore, lwBefore)
        local p = safePlayer(playerId, playerGuid)
        if not p then
            completeAsyncPhase(playerGuid, 4, false)
            return
        end

        local actualTotal = 0
        local rowsFound   = 0

        for r = 1, nRows do
            local res = db.storeQuery(string.format(
                "SELECT `counter` FROM `%s` WHERE `run_id`=%d AND `phase`=4 AND `seq`=%d",
                STRESS_TABLE, rId, r
            ))
            if res and res ~= false and res ~= nil then
                actualTotal = actualTotal + result.getNumber(res, "counter")
                rowsFound   = rowsFound + 1
                result.free(res)
            end
        end

        -- Reads InnoDB counters AFTER
        local deadlocksAfter = readStatusVar("Innodb_deadlocks")
        local lockWaitsAfter = readStatusVar("Innodb_row_lock_waits")
        local dlDelta  = deadlocksAfter  - dlBefore
        local lwDelta  = lockWaitsAfter  - lwBefore
        local lockAvg  = readStatusVar("Innodb_row_lock_time_avg")

        logInfo(p, string.format(
            "Phase 4 InnoDB: deadlocks delta=%d | lock_waits delta=%d | lock_time_avg=%dms",
            dlDelta, lwDelta, lockAvg
        ))

        if dlDelta == 0 and lwDelta == 0 then
            logInfo(p, "  -> No deadlock/wait detected - the test may not have generated real contention.")
            logInfo(p, "     Increase ph4_update_bursts or ph4_sentinel_rows for more pressure.")
        end

        if rowsFound == nRows and actualTotal == expected then
            logPass(p, string.format(
                "Phase 4: %d rows | counter=%d/%d - all UPDATEs committed (retry OK)",
                rowsFound, actualTotal, expected
            ))
        elseif rowsFound == nRows then
            logFail(p, string.format(
                "Phase 4: counter=%d expected=%d - %d UPDATEs lost!",
                actualTotal, expected, expected - actualTotal
            ))
            logFail(p, "  -> Check executeWithinTransactionRollbackOnFailure + lastQueryWasDeadlock().")
        else
            logFail(p, string.format("Phase 4: Only %d/%d rows found.", rowsFound, nRows))
        end

        completeAsyncPhase(playerGuid, 4, rowsFound == nRows and actualTotal == expected)

    end, verifyDelay, pid, guid, runId, rows, totalExpected, deadlocksBefore, lockWaitsBefore)

    log(player, string.format(
        "Phase 4: %d UPDATEs (with FOR UPDATE) | expected counter=%d | result in ~%dms",
        burst * rows, totalExpected, verifyDelay
    ))
    return true
end

-- ============================================================================
-- PHASE 5 - Concurrent addEvent(0) burst (worker pool saturation)
-- ============================================================================
--[[
  NEW vs previous version: it used to be a synchronous loop on the dispatcher -
  all db.query() calls ran sequentially on the dispatcher thread.
  Now it fires N addEvent(0) calls that land in the scheduler and are processed
  by DatabaseTasks workers with their own ConnectionContexts (PR#69).
  This really exercises multiple simultaneous ConnectionContexts.

  Interleaves SELECTs and INSERTs to:
    • Verify that different workers do not interfere with each other's connections.
    • Confirm that result handles created in workers are released correctly.
    • Measure real throughput under concurrency (vs. the dispatcher's sequential run).
--]]
local function runPhase5(player, runId)
    local n    = CFG.ph5_event_bursts
    local pid  = player:getId()
    local guid = player:getGuid()

    log(player, string.format("Phase 5: %d addEvent(0) concurrent bursts...", n))

    local t0 = os.clock()

    for i = 1, n do
        local isWrite = (i % 2 == 0)
        addEvent(function(tbl, rId, seq, write)
            if write then
                local safeLabel = sqlString("burst_" .. seq)
                db.query(string.format(
                    "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`ts`) VALUES (%d,5,%d,%s,%d)",
                    tbl, rId, seq, safeLabel, os.time()
                ))
            else
                -- SELECT + result:next() in a worker - tests handle lifecycle outside the dispatcher
                local res = db.storeQuery(string.format(
                    "SELECT `seq`,`label` FROM `%s` WHERE `run_id`=%d AND `phase`=1 LIMIT 3",
                    tbl, rId
                ))
                if res and res ~= false and res ~= nil then
                    repeat
                        local _ = result.getNumber(res, "seq")
                    until not result.next(res)
                    result.free(res)
                end
            end
        end, 0, STRESS_TABLE, runId, i, isWrite)
    end

    -- Checks after settling
    local verifyDelay = REPORT_DELAY + 500

    addEvent(function(playerId, playerGuid, rId, expectedWrites, wallStart)
        local p = safePlayer(playerId, playerGuid)
        if not p then
            completeAsyncPhase(playerGuid, 5, false)
            return
        end

        local res = db.storeQuery(string.format(
            "SELECT COUNT(*) AS cnt FROM `%s` WHERE `run_id`=%d AND `phase`=5",
            STRESS_TABLE, rId
        ))
        local cnt = 0
        if res and res ~= false and res ~= nil then
            cnt = result.getNumber(res, "cnt")
            result.free(res)
        end

        local elapsed = (os.clock() - wallStart) * 1000

        if cnt == expectedWrites then
            logPass(p, string.format(
                "Phase 5: %d/%d writes arrived | %.0fms wall | workers concorrentes OK",
                cnt, expectedWrites, elapsed
            ))
        else
            logFail(p, string.format(
                "Phase 5: Only %d/%d writes - %d lost in concurrent workers!",
                cnt, expectedWrites, expectedWrites - cnt
            ))
        end

        completeAsyncPhase(playerGuid, 5, cnt == expectedWrites)

    end, verifyDelay, pid, guid, runId, math.floor(n / 2), t0)

    log(player, string.format(
        "Phase 5: %d events fired | result in ~%dms", n, verifyDelay
    ))
    return true
end

-- ============================================================================
-- PHASE 6 - Integrity: count + dup + gap + EXPLAIN + ANALYZE TABLE
-- ============================================================================
--[[
  NEW vs previous version:
    • EXPLAIN SELECT on the table index - verifies that `idx_run_phase`
      is being used. If key=NULL, the query is doing a full scan.
    • ANALYZE TABLE - forces an update of the index statistics.
    • Now covers ALL phases (1-5, 7, 8, 9, 11) by run_id.
--]]
local function runPhase6(player, runId)
    log(player, "Phase 6: Integrity + EXPLAIN + ANALYZE TABLE...")
    local t0 = os.clock()

    -- ANALYZE TABLE before any SELECT so statistics are up to date
    db.query("ANALYZE TABLE `" .. STRESS_TABLE .. "`")

    local function countPhase(phase)
        local res = db.storeQuery(string.format(
            "SELECT COUNT(*) AS cnt FROM `%s` WHERE `run_id`=%d AND `phase`=%d",
            STRESS_TABLE, runId, phase
        ))
        if not res or res == false or res == nil then return -1 end
        local c = result.getNumber(res, "cnt")
        result.free(res)
        return c
    end

    local function hasDups(phase)
        local res = db.storeQuery(string.format(
            [[SELECT COUNT(*) AS dups FROM (
                SELECT `seq` FROM `%s`
                WHERE `run_id`=%d AND `phase`=%d
                GROUP BY `seq` HAVING COUNT(*) > 1
            ) AS t]],
            STRESS_TABLE, runId, phase
        ))
        if not res or res == false or res == nil then return -1 end
        local d = result.getNumber(res, "dups")
        result.free(res)
        return d
    end

    local function gapCount()
        local res = db.storeQuery(string.format(
            "SELECT MAX(`seq`) AS mx, COUNT(*) AS tot FROM `%s` WHERE `run_id`=%d AND `phase`=1",
            STRESS_TABLE, runId
        ))
        if not res or res == false or res == nil then return -1 end
        local mx  = result.getNumber(res, "mx")
        local tot = result.getNumber(res, "tot")
        result.free(res)
        return mx - tot  -- 0 = no gaps
    end

    -- EXPLAIN to verify use of the index idx_run_phase
    local function checkIndexUsed()
        local res = db.storeQuery(string.format(
            "EXPLAIN SELECT * FROM `%s` WHERE `run_id`=%d AND `phase`=1 LIMIT 1",
            STRESS_TABLE, runId
        ))
        if not res or res == false or res == nil then return "N/A" end
        local keyUsed = result.getString(res, "key")
        local rows    = result.getNumber(res, "rows")
        result.free(res)
        if keyUsed and keyUsed ~= "" then
            return string.format("%s (%d rows estimated)", keyUsed, rows)
        else
            return "NONE (full scan!)"
        end
    end

    -- Expected counts
    local expPh1 = CFG.ph1_inserts + CFG.ph1_tx_batch + 1  -- auto-commit + tx + probe
    local expPh5 = math.floor(CFG.ph5_event_bursts / 2)
    local expPh7 = CFG.ph7_commit_rows + 1 -- COMMIT rows + 1 row before the SAVEPOINT; rollback rows must NOT appear
    local expPh8 = CFG.ph8_rows          -- only v2 rows (v1 deleted)
    local expPh9 = CFG.ph9_batch_size
    local expPh11 = CFG.ph11_upsert_rows -- ON DUPLICATE = no duplicates

    local cPh1  = countPhase(1)
    local cPh5  = countPhase(5)
    local cPh7  = countPhase(7)
    local cPh8  = countPhase(8)
    local cPh9  = countPhase(9)
    local cPh11 = countPhase(11)
    local dPh1  = hasDups(1)
    local dPh9  = hasDups(9)
    local dPh11 = hasDups(11)
    local gaps  = gapCount()
    local idxInfo = checkIndexUsed()

    local elapsed = (os.clock() - t0) * 1000

    logInfo(player, string.format("Phase 6: EXPLAIN idx = %s", idxInfo))
    logInfo(player, string.format(
        "Phase 6: Ph1=%d/%d | Ph5=%d/%d | Ph7=%d/%d | Ph8=%d/%d | Ph9=%d/%d | Ph11=%d/%d",
        cPh1, expPh1, cPh5, expPh5, cPh7, expPh7, cPh8, expPh8, cPh9, expPh9, cPh11, expPh11
    ))

    local allOk = (cPh1 == expPh1) and (cPh5 == expPh5)
               and (cPh7 == expPh7) and (cPh8 == expPh8)
               and (cPh9 == expPh9) and (cPh11 == expPh11)
               and (dPh1 == 0) and (dPh9 == 0) and (dPh11 == 0)
               and (gaps == 0)
               and (not idxInfo:find("NONE"))

    if allOk then
        logPass(player, string.format(
            "Phase 6: ALL OK | dup1=%d | dup9=%d | dup11=%d | gaps=%d | %.1fms",
            dPh1, dPh9, dPh11, gaps, elapsed
        ))
    else
        logFail(player, string.format(
            "Phase 6: dup1=%d | dup9=%d | dup11=%d | gaps=%d | %.1fms",
            dPh1, dPh9, dPh11, gaps, elapsed
        ))
        if idxInfo:find("NONE") then
            logFail(player, "  -> EXPLAIN: index not used - full table scan! Review the UNIQUE KEY.")
        end
        if cPh7 ~= expPh7 then
            logFail(player, string.format(
                "  -> Ph7: %d/%d rows - ROLLBACK not atomic or COMMIT failed!", cPh7, expPh7
            ))
        end
        if cPh8 ~= expPh8 then
            logFail(player, string.format(
                "  -> Ph8: %d/%d rows after DELETE+re-INSERT - player_storage pattern corrupted!", cPh8, expPh8
            ))
        end
        if dPh11 > 0 then
            logFail(player, string.format(
                "  -> Ph11: %d duplicates! ON DUPLICATE KEY UPDATE did not work correctly.", dPh11
            ))
        end
        if gaps > 0 then
            logFail(player, string.format("  -> %d gaps in the Ph1 seq - lost writes!", gaps))
        end
    end

    return allOk
end

-- ============================================================================
-- PHASE 7 - Atomicity: START TRANSACTION / COMMIT / ROLLBACK
-- ============================================================================
--[[
  Explicitly tests the PR's transaction model.
  flushPlayerSave() opens a transaction, replays all captured SQLs and
  commits (or does rollback+retry on deadlock). This is the core of the PR.

  Sub-tests:
    7a (COMMIT): START TRANSACTION + ph7_commit_rows INSERTs + COMMIT
        → verifies that EXACTLY commit_rows are in the database.
    7b (ROLLBACK): START TRANSACTION + ph7_rollback_rows INSERTs + ROLLBACK
        → verifies that ZERO rollback rows were persisted.
        → if any row appears, atomicity is broken.
    7c (Savepoint): START TRANSACTION + SAVEPOINT + INSERT + ROLLBACK TO SAVEPOINT
        → advanced: confirms partial rollback granularity.
  EXPECTED FAILURE IF: ROLLBACK rows appear in the database (catastrophic
  atomicity failure), or COMMIT rows do not appear (silent commit failure).
--]]
local function runPhase7(player, runId)
    local nc = CFG.ph7_commit_rows
    local nr = CFG.ph7_rollback_rows

    log(player, string.format(
        "Phase 7: Atomicity - COMMIT(%d rows) + ROLLBACK(%d rows) + SAVEPOINT...",
        nc, nr
    ))

    -- ── 7a: COMMIT path ───────────────────────────────────────────────────────
    local t0 = os.clock()
    local commitOk = true

    db.query("START TRANSACTION")
    for i = 1, nc do
        local safeLabel = sqlString("ph7_commit_" .. i)
        if not db.query(string.format(
            "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`ts`) VALUES (%d,7,%d,%s,%d)",
            STRESS_TABLE, runId, i, safeLabel, os.time()
        )) then
            commitOk = false
        end
    end
    if commitOk then
        db.query("COMMIT")
    else
        db.query("ROLLBACK")
    end
    local elapsedCommit = (os.clock() - t0) * 1000

    -- ── 7b: ROLLBACK path ─────────────────────────────────────────────────────
    -- Uses seq offset nc+1000 to tell it apart from 7a even without a separate phase
    local rollbackSeqBase = nc + 1000
    db.query("START TRANSACTION")
    for i = 1, nr do
        local safeLabel = sqlString("ph7_rollback_" .. i)
        db.query(string.format(
            "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`ts`) VALUES (%d,7,%d,%s,%d)",
            STRESS_TABLE, runId, rollbackSeqBase + i, safeLabel, os.time()
        ))
    end
    db.query("ROLLBACK")  -- None of this should persist

    -- ── 7c: SAVEPOINT ─────────────────────────────────────────────────────────
    local savepointSeq = rollbackSeqBase + nr + 500
    db.query("START TRANSACTION")
    local safeLabel3 = sqlString("ph7_before_savepoint")
    db.query(string.format(
        "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`ts`) VALUES (%d,7,%d,%s,%d)",
        STRESS_TABLE, runId, savepointSeq, safeLabel3, os.time()
    ))
    db.query("SAVEPOINT sp_ph7")
    local safeLabel4 = sqlString("ph7_after_savepoint_rolled")
    db.query(string.format(
        "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`ts`) VALUES (%d,7,%d,%s,%d)",
        STRESS_TABLE, runId, savepointSeq + 1, safeLabel4, os.time()
    ))
    db.query("ROLLBACK TO SAVEPOINT sp_ph7")  -- only the second INSERT is undone
    db.query("COMMIT")

    -- ── Checks ──────────────────────────────────────────────────────────

    -- 7a: commit_rows must be present
    local res7a = db.storeQuery(string.format(
        "SELECT COUNT(*) AS cnt FROM `%s` WHERE `run_id`=%d AND `phase`=7 AND `seq` <= %d",
        STRESS_TABLE, runId, nc
    ))
    local cnt7a = -1
    if res7a and res7a ~= false and res7a ~= nil then 
        cnt7a = result.getNumber(res7a, "cnt")
        result.free(res7a)
    end

    -- 7b: rollback_rows must NOT be present
    local res7b = db.storeQuery(string.format(
        "SELECT COUNT(*) AS cnt FROM `%s` WHERE `run_id`=%d AND `phase`=7 AND `seq` > %d AND `seq` <= %d",
        STRESS_TABLE, runId, rollbackSeqBase, rollbackSeqBase + nr
    ))
    local cnt7b = -1
    if res7b and res7b ~= false and res7b ~= nil then
        cnt7b = result.getNumber(res7b, "cnt")
        result.free(res7b)
    end

    -- 7c: only "before_savepoint" (seq=savepointSeq) should exist; "after" should not
    local res7c = db.storeQuery(string.format(
        "SELECT COUNT(*) AS cnt FROM `%s` WHERE `run_id`=%d AND `phase`=7 AND `seq` >= %d",
        STRESS_TABLE, runId, savepointSeq
    ))
    local cnt7c = -1
    if res7c and res7c ~= false and res7c ~= nil then
        cnt7c = result.getNumber(res7c, "cnt")
        result.free(res7c)
    end

    local ok7a = commitOk and (cnt7a == nc)
    local ok7b = (cnt7b == 0)   -- ROLLBACK: zero rows should have persisted
    local ok7c = (cnt7c == 1)   -- only the row before the SAVEPOINT

    if ok7a then
        logPass(player, string.format(
            "Phase 7a COMMIT: %d/%d rows | %.1fms", cnt7a, nc, elapsedCommit
        ))
    else
        logFail(player, string.format(
            "Phase 7a COMMIT: %d/%d rows - COMMIT did not persist all the data!", cnt7a, nc
        ))
    end

    if ok7b then
        logPass(player, string.format(
            "Phase 7b ROLLBACK: 0 rows persisted (expected) - atomicity OK"
        ))
    else
        logFail(player, string.format(
            "Phase 7b ROLLBACK: %d rows persisted! - ROLLBACK was not atomic!", cnt7b
        ))
        logFail(player, "  -> Catastrophic failure: flushPlayerSave may be committing partially.")
    end

    if ok7c then
        logPass(player, "Phase 7c SAVEPOINT: 1 row after partial rollback - granularity OK")
    else
        logFail(player, string.format(
            "Phase 7c SAVEPOINT: %d rows (expected 1) - problem with ROLLBACK TO SAVEPOINT.", cnt7c
        ))
    end

    return ok7a and ok7b and ok7c
end

-- ============================================================================
-- PHASE 8 - transactional DELETE + re-INSERT (mirror of the player_storage save)
-- ============================================================================
--[[
  Exactly replicates the pattern IOLoginData::savePlayerQueries() uses:
    DELETE FROM player_storage WHERE player_id = ?
    INSERT INTO player_storage (player_id, key, value) VALUES (...) [× N]

  This whole pattern runs inside a single transaction in flushPlayerSave.
  If the COMMIT fails midway, the transaction is retried. The database state
  must always be either "full v1" or "full v2" - never a hybrid.
  Test:
    1. Inserts ph8_rows rows with label='v1_X' (simulates a previous save)
    2. START TRANSACTION + DELETE + re-INSERT with label='v2_X' + COMMIT
    3. Checks: COUNT = ph8_rows, ALL labels start with 'v2_', ZERO 'v1_'

  EXPECTED FAILURE IF: 'v1_' rows are left over (DELETE did not run),
  total != ph8_rows (partial INSERT or duplicate),
  or a mix of 'v1_' and 'v2_' (partial commit - atomicity failure).
--]]
local function runPhase8(player, runId)
    local n = CFG.ph8_rows
    log(player, string.format("Phase 8: DELETE + re-INSERT (player_storage pattern) - %d rows...", n))

    -- ── Inserts v1 (initial state, simulates a previous save) ─────────────────────
    db.query("START TRANSACTION")
    for i = 1, n do
        local safeLabel = sqlString("v1_" .. i)
        db.query(string.format(
            "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`ts`) VALUES (%d,8,%d,%s,%d)",
            STRESS_TABLE, runId, i, safeLabel, os.time()
        ))
    end
    db.query("COMMIT")

    -- ── Re-save: DELETE + INSERT v2 (inside a transaction) ───────────────────
    local t0 = os.clock()
    db.query("START TRANSACTION")
    db.query(string.format(
        "DELETE FROM `%s` WHERE `run_id`=%d AND `phase`=8",
        STRESS_TABLE, runId
    ))
    for i = 1, n do
        local safeLabel = sqlString("v2_" .. i)
        db.query(string.format(
            "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`ts`) VALUES (%d,8,%d,%s,%d)",
            STRESS_TABLE, runId, i, safeLabel, os.time()
        ))
    end
    db.query("COMMIT")
    local elapsed = (os.clock() - t0) * 1000

    -- ── Verify ──────────────────────────────────────────────────────────────
    local resCount = db.storeQuery(string.format(
        "SELECT COUNT(*) AS total FROM `%s` WHERE `run_id`=%d AND `phase`=8",
        STRESS_TABLE, runId
    ))
    local total = -1
    if resCount and resCount ~= false and resCount ~= nil then
        total = result.getNumber(resCount, "total")
        result.free(resCount)
    end

    -- Counts how many are v1 (must not exist) and v2 (must be all of them)
    local resV1 = db.storeQuery(string.format(
        "SELECT COUNT(*) AS cnt FROM `%s` WHERE `run_id`=%d AND `phase`=8 AND `label` LIKE 'v1%%'",
        STRESS_TABLE, runId
    ))
    local v1count = -1
    if resV1 and resV1 ~= false and resV1 ~= nil then
        v1count = result.getNumber(resV1, "cnt")
        result.free(resV1)
    end

    local resV2 = db.storeQuery(string.format(
        "SELECT COUNT(*) AS cnt FROM `%s` WHERE `run_id`=%d AND `phase`=8 AND `label` LIKE 'v2%%'",
        STRESS_TABLE, runId
    ))
    local v2count = -1
    if resV2 and resV2 ~= false and resV2 ~= nil then
        v2count = result.getNumber(resV2, "cnt")
        result.free(resV2)
    end

    if total == n and v1count == 0 and v2count == n then
        logPass(player, string.format(
            "Phase 8: %d/%d rows | 0 v1 (deleted) | %d v2 (current) | %.1fms - player_storage OK",
            total, n, v2count, elapsed
        ))
    else
        logFail(player, string.format(
            "Phase 8: total=%d/%d | v1=%d (should be 0!) | v2=%d | %.1fms",
            total, n, v1count, v2count, elapsed
        ))
        if v1count > 0 then
            logFail(player, "  -> DELETE did not remove v1 rows - transaction was not atomic!")
        end
        if total ~= n then
            logFail(player, string.format(
                "  -> Wrong count: expected %d, found %d - partial INSERT?", n, total
            ))
        end
    end

    return (total == n and v1count == 0 and v2count == n)
end

-- ============================================================================
-- PHASE 9 - Batch multi-row INSERT in a single transaction
-- ============================================================================
--[[
  flushPlayerSave() captures N queries in buildPlayerSave and replays them all
  in sequence inside a transaction. This phase tests the extreme case:
  a single INSERT with ph9_batch_size rows in VALUES() - the most efficient way
  of batch INSERT that MySQL supports. Compares:
    • ph9_batch_size individual INSERTs in auto-commit (baseline)
    • 1 multi-row INSERT with ph9_batch_size rows in a transaction

  EXPECTED FAILURE IF: multi-row INSERT inserts duplicates, fails midway
  (atomicity), or the query exceeds max_allowed_packet (increase it if needed).
  The multi-row vs individual speedup should be significant (usually 5-20×).
--]]
local function runPhase9(player, runId)
    local n = CFG.ph9_batch_size
    log(player, string.format("Phase 9: Batch multi-row INSERT - %d rows in one query...", n))

    -- ── Baseline: N individual INSERTs in auto-commit ────────────────────────
    -- Uses seq 90001+ so it does not collide with the batch
    local t0 = os.clock()
    local baselineOk = 0
    for i = 1, n do
        local safeLabel = sqlString("ph9_individual_" .. i)
        if db.query(string.format(
            "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`ts`) VALUES (%d,9,%d,%s,%d)",
            STRESS_TABLE, runId, 90000 + i, safeLabel, os.time()
        )) then
            baselineOk = baselineOk + 1
        end
    end
    local elapsedIndividual = (os.clock() - t0) * 1000

    -- Removes the individual rows before the batch (same run_id+phase)
    db.query(string.format(
        "DELETE FROM `%s` WHERE `run_id`=%d AND `phase`=9 AND `seq` >= 90001",
        STRESS_TABLE, runId
    ))

    -- ── Batch: 1 multi-row INSERT inside a transaction ─────────────────────────
    local parts = {}
    for i = 1, n do
        local safeLabel = sqlString("ph9_batch_" .. i)
        parts[i] = string.format(
            "(%d,9,%d,%s,0,%d)",
            runId, i, safeLabel, os.time()
        )
    end
    local batchSQL = string.format(
        "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`counter`,`ts`) VALUES %s",
        STRESS_TABLE, table.concat(parts, ",")
    )

    local t1 = os.clock()
    db.query("START TRANSACTION")
    local batchOk = db.query(batchSQL)
    if batchOk then db.query("COMMIT") else db.query("ROLLBACK") end
    local elapsedBatch = (os.clock() - t1) * 1000

    -- ── Checks count after the batch ───────────────────────────────────────────
    local res = db.storeQuery(string.format(
        "SELECT COUNT(*) AS cnt FROM `%s` WHERE `run_id`=%d AND `phase`=9 AND `seq` <= %d",
        STRESS_TABLE, runId, n
    ))
    local cnt = -1
    if res and res ~= false and res ~= nil then
        cnt = result.getNumber(res, "cnt")
        result.free(res)
    end

    local speedup = elapsedIndividual / (elapsedBatch + 1e-9)

    if batchOk and cnt == n then
        logPass(player, string.format(
            "Phase 9: %d/%d rows OK | individual=%.1fms | batch=%.1fms | speedup=%.1fx",
            cnt, n, elapsedIndividual, elapsedBatch, speedup
        ))
    else
        logFail(player, string.format(
            "Phase 9: %d/%d rows | batchOk=%s | individual=%.1fms | batch=%.1fms",
            cnt, n, tostring(batchOk), elapsedIndividual, elapsedBatch
        ))
        if not batchOk then
            logFail(player, "  -> Multi-row INSERT failed - check max_allowed_packet or syntax.")
        end
        if cnt ~= n then
            logFail(player, string.format("  -> Wrong count: expected %d, found %d.", n, cnt))
        end
    end

    return batchOk and (cnt == n)
end

-- ============================================================================
-- PHASE 10 - InnoDB & INFORMATION_SCHEMA diagnostics
-- ============================================================================
--[[
  Pure read phase - does not write data. Collects MySQL metrics that
  reveal the real state of the database layer after the stress:

    • SHOW STATUS: InnoDB variables (deadlocks, lock_waits, buffer hits) and
      global ones (connections, threads, queries). Uses result:next() to
      iterate all returned rows - verifies the loop works.
    • SHOW ENGINE INNODB STATUS: full InnoDB status text. The PR uses a worker/dispatcher flow - if a transaction is open
      unexpectedly, it shows up here in "TRANSACTIONS".
    • SHOW VARIABLES: checks configuration relevant to the PR
      (innodb_lock_wait_timeout, max_connections, thread_stack).
    • SHOW FULL PROCESSLIST: lists active threads - verifies that workers
      of the PR closed their connections correctly after the flushes.
  EXPECTED FAILURE IF: open threads are left over from the workers (connection leak),
  innodb_lock_wait_timeout is too low (would explain failures in Phase 4),
  or buffer pool hit ratio < 90% (excessive I/O pressure).
--]]
local function runPhase10(player, runId)
    log(player, "Phase 10: InnoDB + INFORMATION_SCHEMA diagnostics...")

    -- ── SHOW STATUS: selected variables ───────────────────────────────────
    local statusVars = {
        "Innodb_deadlocks",
        "Innodb_row_lock_waits",
        "Innodb_row_lock_time_avg",
        "Innodb_buffer_pool_reads",
        "Innodb_buffer_pool_read_requests",
        "Threads_connected",
        "Threads_running",
        "Com_insert",
        "Com_select",
        "Com_update",
        "Com_delete",
        "Com_commit",
        "Com_rollback",
    }

    -- Builds IN(list) with db.escapeString
    local inList = {}
    for _, v in ipairs(statusVars) do
        inList[#inList + 1] = sqlString(v)
    end

    local statusRes = db.storeQuery(
        "SHOW STATUS WHERE `Variable_name` IN (" .. table.concat(inList, ",") .. ")"
    )

    local statusMap = {}
    if statusRes and statusRes ~= false and statusRes ~= nil then
        repeat
            local name  = result.getString(statusRes, "Variable_name")
            local value = result.getString(statusRes, "Value")
            statusMap[name] = value
        until not result.next(statusRes)  -- ← result.next() iterates the 13 variables
        result.free(statusRes)
    end

    -- Buffer pool hit ratio
    local bpReads    = tonumber(statusMap["Innodb_buffer_pool_reads"]) or 0
    local bpRequests = tonumber(statusMap["Innodb_buffer_pool_read_requests"]) or 1
    local hitRatio   = 100.0 * (1 - bpReads / bpRequests)

    logInfo(player, string.format(
        "Ph10 STATUS: deadlocks=%s | lock_waits=%s | lock_time_avg=%sms",
        statusMap["Innodb_deadlocks"] or "N/A",
        statusMap["Innodb_row_lock_waits"] or "N/A",
        statusMap["Innodb_row_lock_time_avg"] or "N/A"
    ))
    logInfo(player, string.format(
        "Ph10 STATUS: threads_conn=%s | threads_run=%s | buffer_hit=%.1f%%",
        statusMap["Threads_connected"] or "N/A",
        statusMap["Threads_running"]   or "N/A",
        hitRatio
    ))
    logInfo(player, string.format(
        "Ph10 STATUS: Com_insert=%s | Com_select=%s | Com_update=%s | Com_delete=%s | commit=%s | rollback=%s",
        statusMap["Com_insert"]   or "0",
        statusMap["Com_select"]   or "0",
        statusMap["Com_update"]   or "0",
        statusMap["Com_delete"]   or "0",
        statusMap["Com_commit"]   or "0",
        statusMap["Com_rollback"] or "0"
    ))

    -- ── SHOW VARIABLES relevant to the PR ───────────────────────────────────────
    local varRes = db.storeQuery([[
        SHOW VARIABLES WHERE `Variable_name` IN (
            'innodb_lock_wait_timeout',
            'max_connections',
            'thread_stack',
            'innodb_deadlock_detect',
            'transaction_isolation'
        )
    ]])
    if varRes and varRes ~= false and varRes ~= nil then
        local varMap = {}
        repeat
            local name  = result.getString(varRes, "Variable_name")
            local value = result.getString(varRes, "Value")
            varMap[name] = value
        until not result.next(varRes)
        result.free(varRes)

        logInfo(player, string.format(
            "Ph10 VARS: lock_wait_timeout=%ss | max_conn=%s | isolation=%s | deadlock_detect=%s",
            varMap["innodb_lock_wait_timeout"] or "?",
            varMap["max_connections"] or "?",
            varMap["transaction_isolation"] or "?",
            varMap["innodb_deadlock_detect"] or "?"
        ))

        local lockTimeout = tonumber(varMap["innodb_lock_wait_timeout"]) or 50
        if lockTimeout < 5 then
            logFail(player, string.format(
                "Ph10: innodb_lock_wait_timeout=%ds is too low - Phase 4 may have false negatives!", lockTimeout
            ))
        end
    end

    -- ── SHOW FULL PROCESSLIST: checks open worker connections ────────────
    local procRes = db.storeQuery("SHOW FULL PROCESSLIST")
    local workerConns = 0
    if procRes and procRes ~= false and procRes ~= nil then
        repeat
            local cmd   = result.getString(procRes, "Command")
            local state = result.getString(procRes, "State")
            -- TFS worker connections appear as "Sleep" or "Query"
            if cmd == "Sleep" or cmd == "Query" then
                workerConns = workerConns + 1
            end
        until not result.next(procRes)
        result.free(procRes)
    end
    logInfo(player, string.format(
        "Ph10 PROCESSLIST: %d active connections (workers + dispatcher)", workerConns
    ))

    -- ── Buffer pool hit ratio: warning if low ────────────────────────────────
    local diag_ok = true
    if hitRatio < 90 then
        logFail(player, string.format(
            "Ph10: Buffer pool hit=%.1f%% - high I/O pressure! Check innodb_buffer_pool_size.", hitRatio
        ))
        diag_ok = false
    else
        logPass(player, string.format("Ph10: Buffer pool hit=%.1f%% - OK", hitRatio))
    end

    return diag_ok
end

-- ============================================================================
-- PHASE 11 - ON DUPLICATE KEY UPDATE (upsert, real IOLoginData pattern)
-- ============================================================================
--[[
  IOLoginData::savePlayerQueries() uses extensively:
    INSERT INTO player_storage (player_id, key, value)
    VALUES (X, Y, Z)
    ON DUPLICATE KEY UPDATE value = VALUES(value)

  This phase replicates that pattern on the stress table:
    1. INSERT ph11_upsert_rows rows with counter=0
    2. Re-INSERT of the SAME rows with counter=99 + ON DUPLICATE KEY UPDATE
    3. Checks: COUNT must be EXACTLY ph11_upsert_rows (no duplicates),
       all counters must be 99 (UPDATE ran, not a duplicate INSERT).

  EXPECTED FAILURE IF: count == ph11_upsert_rows * 2 (UNIQUE KEY ignored),
  or counter != 99 (UPDATE did not run - INSERT created a new row).
--]]
local function runPhase11(player, runId)
    local n = CFG.ph11_upsert_rows
    log(player, string.format("Phase 11: ON DUPLICATE KEY UPDATE - %d upserts...", n))

    -- ── Initial INSERT with counter=0 ──────────────────────────────────────────
    local t0 = os.clock()
    db.query("START TRANSACTION")
    for i = 1, n do
        local safeLabel = sqlString("upsert_" .. i)
        db.query(string.format(
            "INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`counter`,`ts`) VALUES (%d,11,%d,%s,0,%d)",
            STRESS_TABLE, runId, i, safeLabel, os.time()
        ))
    end
    db.query("COMMIT")

    -- ── Re-INSERT with ON DUPLICATE KEY UPDATE counter=99 ─────────────────────
    local t1 = os.clock()
    db.query("START TRANSACTION")
    for i = 1, n do
        local safeLabel = sqlString("upsert_" .. i)
        db.query(string.format(
            [[INSERT INTO `%s` (`run_id`,`phase`,`seq`,`label`,`counter`,`ts`)
              VALUES (%d,11,%d,%s,99,%d)
              ON DUPLICATE KEY UPDATE `counter`=VALUES(`counter`), `ts`=VALUES(`ts`)]],
            STRESS_TABLE, runId, i, safeLabel, os.time()
        ))
    end
    db.query("COMMIT")
    local elapsed = (os.clock() - t1) * 1000

    -- ── Verification ───────────────────────────────────────────────────────────
    local resCount = db.storeQuery(string.format(
        "SELECT COUNT(*) AS cnt, SUM(`counter`) AS total_counter FROM `%s` WHERE `run_id`=%d AND `phase`=11",
        STRESS_TABLE, runId
    ))
    local cnt          = -1
    local totalCounter = -1
    if resCount and resCount ~= false and resCount ~= nil then
        cnt          = result.getNumber(resCount, "cnt")
        totalCounter = result.getNumber(resCount, "total_counter")
        result.free(resCount)
    end

    local expectedCounter = n * 99

    if cnt == n and totalCounter == expectedCounter then
        logPass(player, string.format(
            "Phase 11: %d/%d rows (no duplicates) | counter_sum=%d/%d | %.1fms - upsert OK",
            cnt, n, totalCounter, expectedCounter, elapsed
        ))
    else
        if cnt ~= n then
            logFail(player, string.format(
                "Phase 11: %d/%d rows - ON DUPLICATE KEY produced duplicates (expected %d)!",
                cnt, n, n
            ))
        end
        if totalCounter ~= expectedCounter then
            logFail(player, string.format(
                "Phase 11: counter_sum=%d expected=%d - UPDATE did not run on %d rows!",
                totalCounter, expectedCounter, math.max(0, n - math.floor((totalCounter or 0) / 99))
            ))
        end
    end

    return (cnt == n and totalCounter == expectedCounter)
end

-- ============================================================================
-- ASYNC SETTLE FINALIZER  (assigned to PhaseCallbacks.finalize after runPhase6)
-- ============================================================================
PhaseCallbacks.finalize = function(guid)
    local sd = settleData[guid]
    if not sd then return end
    settleData[guid] = nil
    local p = safePlayer(sd.pid, sd.guid)
    if not p then
        activeRuns[sd.guid] = false
        asyncResults[sd.guid] = nil
        asyncPending[sd.guid] = nil
        return
    end
    sd.results[6] = runPhase6(p, sd.runId)
    local ar = asyncResults[sd.guid] or {}
    local total, passed = 0, 0
    for i = 1, 5 do
        total = total + 1
        if ar[i] ~= false then passed = passed + 1 end
    end
    for i = 6, 11 do
        if sd.results[i] ~= nil then
            total = total + 1
            if sd.results[i] == true then passed = passed + 1 end
        end
    end
    local wall = (os.clock() - sd.wallStart) * 1000
    if passed == total then
        print(COLOR_BLUE .. "[StressDB]" .. COLOR_GREEN .. "[INFO]" .. COLOR_RESET .. " " ..
              COLOR_BLUE .. string.format("=== STRESS COMPLETE: ALL PASS | wall ~%.0fms ===", wall) .. COLOR_RESET)
        p:sendTextMessage(MSG_BLUE, string.format("[StressDB][PASS] === STRESS COMPLETE: ALL PASS | wall ~%.0fms ===", wall))
    else
        logFail(p, string.format("=== STRESS COMPLETE: %d/%d PASS | wall ~%.0fms - review the FAILs! ===", passed, total, wall))
    end
    activeRuns[sd.guid] = false
    asyncResults[sd.guid] = nil
    asyncPending[sd.guid] = nil
end

-- ============================================================================
-- REVSCRIPT - TalkAction
-- ============================================================================
local stressTalkAction = TalkAction("/stress_db")
stressTalkAction:separator(" ")
stressTalkAction:access(true)

function stressTalkAction.onSay(player, words, param)
    if not player:getGroup():getAccess() then
        return false
    end

    local cmd = (param or ""):lower():match("^%s*(.-)%s*$")

    -- ── INFO ─────────────────────────────────────────────────────────────────
    if cmd == "info" then
        local lines = {
            "=== Stress DB PR#69 | 11 phases ===",
            "Ph1  INSERT flood + escapeString + LAST_INSERT_ID + TX",
            "Ph2  Dirty snapshot: IN(...) + result:next() loop",
            "Ph3  Save flood: flushInFlight + pendingFlushes ordering",
            "Ph4  FOR UPDATE + deadlock retry + Innodb_deadlocks delta",
            "Ph5  addEvent(0) concurrent bursts (worker pool)",
            "Ph6  Integridade: ANALYZE + EXPLAIN + count/dup/gap",
            "Ph7  COMMIT + ROLLBACK + SAVEPOINT atomicity",
            "Ph8  DELETE + re-INSERT transacional (player_storage pattern)",
            "Ph9  Batch multi-row INSERT - throughput comparison",
            "Ph10 SHOW STATUS + PROCESSLIST + SHOW VARIABLES (diagnostics)",
            "Ph11 ON DUPLICATE KEY UPDATE (upsert IOLoginData pattern)",
            "Usage: /stress_db [start|diag|1-11|clean|info]",
        }
        for _, l in ipairs(lines) do
            player:sendTextMessage(MSG_BLUE, l)
        end
        return false
    end

	-- ── CLEAN ────────────────────────────────────────────────────────────────
	if cmd == "clean" then
		if activeRuns[player:getGuid()] then
			log(player, "Stress run in progress - wait for it to finish before cleaning.")
			return false
		end
		if db.query(string.format("DELETE FROM `%s` WHERE 1=1", STRESS_TABLE)) then
            log(player, "Table stress_pr69 emptied.")
        else
            logFail(player, "Failed to clean the table (maybe it no longer exists).")
        end
        return false
    end

    -- ── DIAG (Phase 10 only, non-destructive) ────────────────────────────────
    if cmd == "diag" then
        runPhase10(player, 0)
        return false
    end

	local runId = os.time() % 65535

	-- ── SINGLE PHASE ───────────────────────────────────────────────────────
	local args = {}
	for w in (param or ""):gmatch("%S+") do args[#args + 1] = w end
	local phaseNum = tonumber(args[1])
	local explicitRunId = tonumber(args[2])
	if explicitRunId then runId = explicitRunId end
	if phaseNum then
		if activeRuns[player:getGuid()] then
			log(player, "Stress run in progress - wait for it to finish before starting a new phase.")
			return false
		end
		if phaseNum ~= 6 and phaseNum ~= 10 then
            if not setupTable() then
                logFail(player, "Failed to create the stress table. Aborting.")
                activeRuns[player:getGuid()] = false
                return false
            end
        end
        if     phaseNum == 1  then runPhase1(player, runId)
        elseif phaseNum == 2  then runPhase2(player, runId)
        elseif phaseNum == 3  then runPhase3(player, runId)
        elseif phaseNum == 4  then runPhase4(player, runId)
        elseif phaseNum == 5  then runPhase5(player, runId)
        elseif phaseNum == 6  then runPhase6(player, runId)
        elseif phaseNum == 7  then runPhase7(player, runId)
        elseif phaseNum == 8  then runPhase8(player, runId)
        elseif phaseNum == 9  then runPhase9(player, runId)
        elseif phaseNum == 10 then runPhase10(player, runId)
        elseif phaseNum == 11 then runPhase11(player, runId)
        else
            player:sendTextMessage(MSG_BLUE,
                "Invalid phase. Use 1-11, start, diag, clean or info.")
        end
        return false
    end

    -- ── START - all phases ────────────────────────────────────────────────
	if cmd == "" or cmd == "start" or cmd == "all" then
		if activeRuns[player:getGuid()] then
			log(player, "Stress run already in progress - wait for it to finish.")
			return false
		end
		activeRuns[player:getGuid()] = true

		print(COLOR_BLUE .. "[StressDB]" .. COLOR_GREEN .. "[INFO]" .. COLOR_RESET .. " " .. 
			  COLOR_BLUE .. string.format("=== Stress DB PR#69 | run_id=%d | 11 phases | starting ===", runId) .. COLOR_RESET)
		player:sendTextMessage(MSG_BLUE, string.format(
            "[StressDB] === Stress DB PR#69 | run_id=%d | 11 phases | starting ===", runId
        ))

        if not setupTable() then
            activeRuns[player:getGuid()] = false
            logFail(player, "Failed to create the stress table. Aborting.")
            return false
        end

		print(COLOR_BLUE .. "[StressDB]" .. COLOR_GREEN .. "[INFO]" .. COLOR_RESET .. " " .. 
			  COLOR_BLUE .. "Table stress_pr69 created." .. COLOR_RESET)
		player:sendTextMessage(MSG_BLUE, "[StressDB] Table stress_pr69 created.")

        local wallStart = os.clock()
        local results   = {}

        -- Synchronous phases (dispatcher)
        results[1]  = runPhase1(player, runId)
        results[2]  = runPhase2(player, runId)
        results[3]  = runPhase3(player, runId)
        results[4]  = runPhase4(player, runId)
        results[5]  = runPhase5(player, runId)
        results[7]  = runPhase7(player, runId)
        results[8]  = runPhase8(player, runId)
        results[9]  = runPhase9(player, runId)
        results[10] = runPhase10(player, runId)
        results[11] = runPhase11(player, runId)

        -- Async tracking: phases 1c, 2, 3, 4, 5 report results via callbacks.
        -- Initializes tracking with default=pass; callbacks mark false if they fail.
        -- The final summary fires when all 5 async phases complete (or on timeout).
        local stressGuid = player:getGuid()
        asyncResults[stressGuid] = {[1] = true, [2] = true, [3] = true, [4] = true, [5] = true}
        asyncPending[stressGuid] = 5

        settleData[stressGuid] = {
            pid = player:getId(),
            guid = stressGuid,
            runId = runId,
            wallStart = wallStart,
            results = results,
        }

        -- Safety timeout: if a callback never fires, forces the summary after settleTime + buffer
        local settleTime = math.max(
            (CFG.ph3_save_count * CFG.ph3_stagger_ms) + REPORT_DELAY + 1200,
            REPORT_DELAY + 2200
        ) + 800
        addEvent(function(g)
            if settleData[g] and asyncPending[g] and asyncPending[g] > 0 then
                asyncPending[g] = 0
                if asyncResults[g] then
                    for ph = 1, 5 do
                        if asyncResults[g][ph] == nil then
                            asyncResults[g][ph] = false
                        end
                    end
                end
                local sd = settleData[g]
                if sd then
                    local p = safePlayer(sd.pid, sd.guid)
                    if p then
                        logFail(p, "Timeout: some async phases did not complete. Summary forced.")
                    end
                end
                PhaseCallbacks.finalize(g)
            end
            asyncResults[g] = nil
            asyncPending[g] = nil
        end, settleTime + 5000, stressGuid)

        local execMsg = string.format(
            "Phases 1-11 running | async results feed the final summary (timeout=~%.0fms)", settleTime + 5000
        )
        print(COLOR_BLUE .. "[StressDB]" .. COLOR_RESET .. " " ..
              COLOR_ORANGE .. "Phases 1-11 running" .. COLOR_RESET ..
              string.format(" | async results feed the final summary (timeout=~%.0fms)", settleTime + 5000))
        player:sendTextMessage(MSG_BLUE, "[StressDB] " .. execMsg)
        return false
    end

    player:sendTextMessage(MSG_BLUE,
        "Usage: /stress_db [start|diag|1-11|clean|info]")
    return false
end

stressTalkAction:accountType(6)
stressTalkAction:register()
