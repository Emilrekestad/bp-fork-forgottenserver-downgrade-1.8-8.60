-- Old Man Bao — GM-only debug/admin command.
-- This is plain administrative tooling (not Bao's in-character voice) meant
-- to exercise BaoState before any real client UI exists. Every response goes
-- back to the GM who ran the command, never to the target player.
--
-- Usage:
--   /bao status, PlayerName
--   /bao reputation, PlayerName, amount
--   /bao marks, PlayerName, amount
--   /bao complete, PlayerName, huntId
--   /bao reset, PlayerName, huntId
--
-- Reputation/marks are backed by the real `bao_player` SQL table, so those
-- two subcommands support an offline fallback (direct SQL, mirroring
-- bao_state.lua's own savePlayerRow INSERT ... ON DUPLICATE KEY UPDATE
-- shape). Everything else (active hunts, mastery, hunt completion) lives in
-- the lazily-warmed online-session cache or a player:kv() blob and has no
-- offline equivalent worth building — those subcommands require the target
-- to be online and say so clearly if they aren't.

local BAO_USAGE = "Usage: /bao status, name | /bao reputation, name, amount | /bao marks, name, amount | /bao complete, name, huntId | /bao reset, name, huntId | /bao bounty, name | /bao ladder"

local function rankNameForId(rankId)
	for _, rank in ipairs(BaoConfig.Ranks) do
		if rank.id == rankId then
			return rank.name
		end
	end
	return "Unknown"
end

local function normalizeSub(sub)
	return (sub or ""):lower():gsub("[%s_%-]+", "")
end

-- Looks up a possibly-offline player's persisted reputation/marks straight
-- from `bao_player` via a LEFT JOIN on `players`, so a player who has never
-- been cached in bao_player (row doesn't exist yet) still resolves to 0/0
-- rather than "not found".
local function findOfflineBaoRow(targetName)
	local resultId = db.storeQuery("SELECT p.`id`, p.`name`, COALESCE(bp.`reputation`, 0) AS `reputation`, COALESCE(bp.`marks`, 0) AS `marks` " ..
		"FROM `players` p LEFT JOIN `bao_player` bp ON bp.`player_id` = p.`id` " ..
		"WHERE LOWER(p.`name`) = LOWER(" .. db.escapeString(targetName) .. ") LIMIT 1")
	if resultId == false then
		return nil
	end

	local row = {
		guid = result.getDataInt(resultId, "id"),
		name = result.getDataString(resultId, "name"),
		reputation = result.getDataInt(resultId, "reputation"),
		marks = result.getDataInt(resultId, "marks"),
	}
	result.free(resultId)
	return row
end

-- ─── /bao status ─────────────────────────────────────────────────────────

local function handleStatus(admin, targetName)
	if not targetName or targetName == "" then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, BAO_USAGE)
		return false
	end

	local target = Player(targetName)
	if not target then
		local row = findOfflineBaoRow(targetName)
		if not row then
			admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Player not found.")
			return false
		end

		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
			"%s is offline — showing persisted reputation/marks only.\nReputation: %d | Marks: %d",
			row.name, row.reputation, row.marks
		))
		return false
	end

	local rankId = BaoState.getRankId(target)
	local lines = {
		string.format("Bao status for %s:", target:getName()),
		string.format("Rank: %s (id %d)", rankNameForId(rankId), rankId),
		string.format("Reputation: %d | Marks: %d", BaoState.getReputation(target), BaoState.getMarks(target)),
		string.format("Story chapter: %d | Mastery count: %d", BaoState.getStoryChapter(target), BaoState.getMasteryCount(target)),
	}

	local slots = BaoState.getActiveHunts(target)
	local hasSlots = false
	for slot = 1, BaoState.getMaxSlots(target) do
		local slotData = slots[slot]
		if slotData then
			hasSlots = true
			local hunt = BaoConfig.Hunts[slotData.huntId]
			local displayName = hunt and hunt.displayName or slotData.huntId
			local requiredCount = hunt and hunt.requiredCount or 0
			local stateName = slotData.state == 2 and "completed, unclaimed" or "active"
			lines[#lines + 1] = string.format("Slot %d: %s (%s) — %d/%d [%s]",
				slot, displayName, slotData.huntId, slotData.progress, requiredCount, stateName)
		end
	end
	if not hasSlots then
		lines[#lines + 1] = "No active hunts."
	end

	admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, table.concat(lines, "\n"))
	return false
end

-- ─── /bao reputation, /bao marks ───────────────────────────────────────────

-- Shared implementation for the two stat-adjustment subcommands. `column` is
-- an internal literal ("reputation"/"marks"), never user input, so it's safe
-- to splice into the query.
local function adjustStat(admin, targetName, amountText, statLabel, column, getter, adder)
	if not targetName or targetName == "" or not amountText or amountText == "" then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, BAO_USAGE)
		return false
	end

	local amount = tonumber(amountText)
	if not amount then
		admin:sendCancelMessage("Amount must be a number.")
		return false
	end
	amount = math.floor(amount)
	if amount == 0 then
		admin:sendCancelMessage("Amount must be non-zero.")
		return false
	end

	local target = Player(targetName)
	if target then
		adder(target, amount)
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
			"%s %d %s %s %s. New total: %d.",
			amount >= 0 and "Added" or "Removed", math.abs(amount), statLabel,
			amount >= 0 and "to" or "from", target:getName(), getter(target)
		))
		return false
	end

	-- Offline fallback: direct SQL against bao_player, mirroring bao_state.lua's
	-- own savePlayerRow INSERT ... ON DUPLICATE KEY UPDATE shape. The new row
	-- (INSERT branch) starts from 0, so its clamped value is just the amount;
	-- the UPDATE branch adds to whatever is already persisted, also clamped.
	local resultId = db.storeQuery("SELECT p.`id`, p.`name` FROM `players` p WHERE LOWER(p.`name`) = LOWER(" .. db.escapeString(targetName) .. ") LIMIT 1")
	if resultId == false then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Player not found.")
		return false
	end

	local guid = result.getDataInt(resultId, "id")
	local storedName = result.getDataString(resultId, "name")
	result.free(resultId)

	local ok = db.query(string.format(
		"INSERT INTO `bao_player` (`player_id`, `%s`, `updated_at`) VALUES (%d, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `%s` = GREATEST(0, `%s` + (%d)), `updated_at` = VALUES(`updated_at`)",
		column, guid, math.max(0, amount), os.time(),
		column, column, amount
	))
	if not ok then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Failed to update " .. statLabel .. ".")
		return false
	end

	local newValue = 0
	local totalId = db.storeQuery("SELECT `" .. column .. "` FROM `bao_player` WHERE `player_id` = " .. guid)
	if totalId ~= false then
		newValue = result.getDataInt(totalId, column)
		result.free(totalId)
	end

	admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
		"%s is offline — %s %d %s. New total: %d (persisted).",
		storedName, amount >= 0 and "added" or "removed", math.abs(amount), statLabel, newValue
	))
	return false
end

local function handleReputation(admin, targetName, amountText)
	return adjustStat(admin, targetName, amountText, "reputation", "reputation", BaoState.getReputation, BaoState.addReputation)
end

local function handleMarks(admin, targetName, amountText)
	return adjustStat(admin, targetName, amountText, "marks", "marks", BaoState.getMarks, BaoState.addMarks)
end

-- ─── /bao complete ──────────────────────────────────────────────────────

local function handleComplete(admin, targetName, huntId)
	if not targetName or targetName == "" or not huntId or huntId == "" then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, BAO_USAGE)
		return false
	end

	local target = Player(targetName)
	if not target then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Player must be online to use /bao complete.")
		return false
	end

	local hunt = BaoConfig.Hunts[huntId]
	if not hunt then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Unknown hunt id: " .. huntId)
		return false
	end

	local slot = BaoState.getActiveSlotFor(target, huntId)
	if not slot then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
			"%s does not have hunt '%s' active in any slot; not completing.", target:getName(), huntId
		))
		return false
	end

	local slots = BaoState.getActiveHunts(target)
	if slots[slot] and slots[slot].state == 2 then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
			"Hunt '%s' is already completed for %s and awaiting claim.", huntId, target:getName()
		))
		return false
	end

	local progressResult = BaoState.addHuntProgress(target, huntId, hunt.requiredCount)
	if not progressResult then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Failed to add hunt progress (hunt no longer active?).")
		return false
	end

	if progressResult.justCompleted then
		local isFirst = BaoState.recordMastery(target, huntId)
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
			"Completed hunt '%s' (%s) for %s. Progress: %d/%d.%s",
			huntId, hunt.displayName, target:getName(), progressResult.progress, progressResult.requiredCount,
			isFirst and " First mastery recorded." or ""
		))
	else
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
			"Added progress to hunt '%s' for %s: %d/%d (not yet complete).",
			huntId, target:getName(), progressResult.progress, progressResult.requiredCount
		))
	end
	return false
end

-- ─── /bao reset ─────────────────────────────────────────────────────────

local function handleReset(admin, targetName, huntId)
	if not targetName or targetName == "" or not huntId or huntId == "" then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, BAO_USAGE)
		return false
	end

	local target = Player(targetName)
	if not target then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Player must be online to use /bao reset.")
		return false
	end

	local slot = BaoState.getActiveSlotFor(target, huntId)
	if not slot then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
			"%s does not have hunt '%s' active in any slot; nothing to reset.", target:getName(), huntId
		))
		return false
	end

	local ok = BaoState.abandonHunt(target, slot)
	if ok then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
			"Abandoned hunt '%s' (slot %d) for %s. Note: this only clears the active attempt — mastery/completion history is untouched.",
			huntId, slot, target:getName()
		))
	else
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Failed to abandon hunt.")
	end
	return false
end

-- ─── /bao bounty ────────────────────────────────────────────────────────

-- Prints the target's current board with live carried counts. The board is
-- derived rather than stored, so this is also the quickest way to confirm the
-- rotation and the deterministic picker are behaving without waiting a day.
local function handleBounty(admin, targetName)
	if not targetName or targetName == "" then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, BAO_USAGE)
		return false
	end

	local target = Player(targetName)
	if not target then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
			"'%s' must be online to inspect their bounty board.", targetName))
		return false
	end

	local board = BaoBounty.boardFor(target, BaoBounty.currentOffset(target))
	admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
		"Bounties for %s — rotation %d, %s until it turns over, %d reroll(s) left:",
		target:getName(), BaoBounty.rotationIndex(),
		os.date("!%Hh %Mm", BaoBounty.secondsUntilRotation()), BaoBounty.rerollsRemaining(target)))

	if #board == 0 then
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "  (no bounties eligible at their rank)")
		return false
	end

	for slot, entry in ipairs(board) do
		local bounty = entry.bounty
		admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
			"  %d. %s — %s %d/%d — %d marks, %d rep%s",
			slot, bounty.displayName, ItemType(bounty.itemId):getName(),
			BaoBounty.progressFor(target, bounty), bounty.count,
			bounty.rewards.marks or 0, bounty.rewards.reputation or 0,
			BaoBounty.isClaimed(target, entry.key) and " [HANDED IN]" or ""))
	end
	return false
end

-- ─── /bao ladder ────────────────────────────────────────────────────────

-- Re-runs the startup reachability check on demand and reports it in-game, so
-- the answer to "can this rank actually be earned" does not require reading
-- the server log. See BaoRank.validateLadder for why this check exists.
local function handleLadder(admin)
	for _, rank in ipairs(BaoConfig.Ranks) do
		if rank.id > 0 then
			local available = 0
			for _, hunt in pairs(BaoConfig.Hunts) do
				if (hunt.minRank or 0) <= (rank.id - 1) then
					available = available + 1
				end
			end
			admin:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
				"  %d %s — needs %d masteries, %d hunts unlocked below it — %s",
				rank.id, rank.name, rank.masteriesRequired, available,
				available >= rank.masteriesRequired
					and string.format("reachable (%d spare)", available - rank.masteriesRequired)
					or string.format("UNREACHABLE, short by %d", rank.masteriesRequired - available)))
		end
	end
	return false
end

-- ─── Dispatch ───────────────────────────────────────────────────────────

local bao = TalkAction("/bao")
function bao.onSay(player, words, param)
	local split = param:splitTrimmed(",")
	local sub = normalizeSub(split[1])

	if sub == "status" then
		return handleStatus(player, split[2])
	elseif sub == "reputation" or sub == "rep" then
		return handleReputation(player, split[2], split[3])
	elseif sub == "marks" then
		return handleMarks(player, split[2], split[3])
	elseif sub == "complete" then
		return handleComplete(player, split[2], split[3])
	elseif sub == "reset" then
		return handleReset(player, split[2], split[3])
	elseif sub == "bounty" or sub == "bounties" then
		return handleBounty(player, split[2])
	elseif sub == "ladder" then
		return handleLadder(player)
	end

	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, BAO_USAGE)
	return false
end
bao:separator(" ")
bao:accountType(6)
bao:access(true)
bao:register()
