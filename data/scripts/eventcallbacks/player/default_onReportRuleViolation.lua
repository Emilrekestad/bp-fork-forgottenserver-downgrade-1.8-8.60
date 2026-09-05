-- Player reports, into the database rather than into a file nobody opens.
--
-- This used to write data/reports/players/<reporter>-<target>-<type>.txt. On
-- the live server that directory has been empty since it was created, because
-- reading it means an SSH session, and a report nobody reads is a report that
-- was never filed. The rows go to the console's Desk instead, where a bot
-- report arrives next to the reported player's own activity fingerprint.
--
-- targetName arrives straight off the network packet (src/protocolgame.cpp)
-- with no server-side validation before this event fires. The path-traversal
-- risk it used to carry is gone with the filesystem, but the validation
-- stays: a crafted report packet is still the one place a player controls a
-- string that ends up in an operator's console, and rejecting a bad name is
-- better than storing one. Real Tibia names are letters and spaces, with the
-- occasional apostrophe or hyphen for legacy imports.
local function isSafeReportName(name)
	return type(name) == "string" and #name > 0 and #name <= 32
		and name:match("^[%a][%a%s'%-]*$") ~= nil
end

-- One report per reporter per target per ten minutes. Without this, one
-- annoyed player can fill the queue faster than anyone can read it, and the
-- limit is per pair rather than per reporter so that somebody being harassed
-- by several people can still report all of them.
local REPORT_COOLDOWN_SECONDS = 600

local function cooldownKey(targetName)
	-- Per player, keyed on the target's name hashed into the 1000-key block
	-- reserved at PlayerStorageKeys.consoleReportCooldown. A collision costs
	-- one delayed report, which is a better trade than keeping a table of
	-- name strings in memory for the life of the process.
	local hash = 0
	for index = 1, #targetName do
		hash = (hash * 31 + targetName:byte(index)) % 1000
	end
	return PlayerStorageKeys.consoleReportCooldown + hash
end

local reportTypeNames = {
	[REPORT_TYPE_NAME] = "Name report",
	[REPORT_TYPE_STATEMENT] = "Statement report",
	[REPORT_TYPE_BOT] = "Player behavior report"
}

local reportReasonNames = {
	[REPORT_REASON_NAMEINAPPROPRIATE] = "Inappropriate name",
	[REPORT_REASON_NAMEPOORFORMATTED] = "Invalid name format",
	[REPORT_REASON_NAMEADVERTISING] = "Advertising in name",
	[REPORT_REASON_NAMEUNFITTING] = "Unsuitable name",
	[REPORT_REASON_NAMERULEVIOLATION] = "Name inciting rule violation",
	[REPORT_REASON_INSULTINGSTATEMENT] = "Offensive statement",
	[REPORT_REASON_SPAMMING] = "Spamming",
	[REPORT_REASON_ADVERTISINGSTATEMENT] = "Advertising statement",
	[REPORT_REASON_UNFITTINGSTATEMENT] = "Off-topic statement",
	[REPORT_REASON_LANGUAGESTATEMENT] = "Language violation",
	[REPORT_REASON_DISCLOSURE] = "Private data disclosure",
	[REPORT_REASON_RULEVIOLATION] = "Rule violation or abusive behavior",
	[REPORT_REASON_STATEMENT_BUGABUSE] = "Bug abuse",
	[REPORT_REASON_UNOFFICIALSOFTWARE] = "Unofficial software, bot or hack",
	[REPORT_REASON_PRETENDING] = "Pretending to influence rule enforcement",
	[REPORT_REASON_HARASSINGOWNERS] = "Threatening staff",
	[REPORT_REASON_FALSEINFO] = "False information or false report",
	[REPORT_REASON_ACCOUNTSHARING] = "Account sharing or trading",
	[REPORT_REASON_STEALINGDATA] = "Attempt to steal data",
	[REPORT_REASON_SERVICEATTACKING] = "Service attack",
	[REPORT_REASON_SERVICEAGREEMENT] = "Service agreement violation"
}

local function getReportTypeName(reportType)
	return reportTypeNames[reportType] or string.format("Unknown report type (%d)", reportType)
end

local function getReportReasonName(reportReason)
	return reportReasonNames[reportReason] or string.format("Unknown report reason (%d)", reportReason)
end

local event = Event()

event.onReportRuleViolation = function(self, targetName, reportType,
                                       reportReason, comment, translation)
	local name = self:getName()
	if not isSafeReportName(targetName) then
		self:sendTextMessage(MESSAGE_EVENT_ADVANCE, "That player name is not valid.")
		return
	end

	local key = cooldownKey(targetName)
	local readyAt = self:getStorageValue(key)
	if readyAt > os.time() then
		self:sendTextMessage(MESSAGE_EVENT_ADVANCE,
		                     "You have already reported that player. Your report is being processed.")
		return
	end
	self:setStorageValue(key, os.time() + REPORT_COOLDOWN_SECONDS)

	-- Resolved here rather than in the console, so the row records who the
	-- name meant at the moment of the report. A character renamed afterwards
	-- would otherwise make an old report unreadable.
	local targetId = "NULL"
	local resultId = db.storeQuery(string.format(
		"SELECT `id` FROM `players` WHERE LOWER(`name`) = LOWER(%s) LIMIT 1",
		db.escapeString(targetName)))
	if resultId then
		targetId = tostring(result.getNumber(resultId, "id"))
		result.free(resultId)
	end

	local position = self:getPosition()

	-- Async: a report is worth recording, but never worth making the reporter
	-- wait on a database round trip in the middle of play.
	db.asyncQuery(string.format(
		"INSERT INTO `player_reports` (`ts`, `reporter_id`, `reporter_name`, `reporter_x`, " ..
		"`reporter_y`, `reporter_z`, `target_name`, `target_id`, `report_type`, `reason`, " ..
		"`comment`, `translation`) VALUES (%d, %d, %s, %d, %d, %d, %s, %s, %d, %d, %s, %s)",
		os.time(), self:getGuid(), db.escapeString(name),
		position.x, position.y, position.z,
		db.escapeString(targetName), targetId,
		reportType, reportReason,
		db.escapeString(tostring(comment or ""):sub(1, 2000)),
		db.escapeString(tostring(translation or ""):sub(1, 2000))))

	-- A bot report is the one kind worth waking somebody for, because the
	-- evidence it points at -- an unbroken session, a kill rate, a player who
	-- has not moved -- is perishable. The others wait for the queue.
	if reportType == REPORT_TYPE_BOT then
		local key = string.format("ops.report:%s:%d", targetName, os.time())
		db.asyncQuery(string.format(
			"INSERT IGNORE INTO `integration_events` (`event_key`, `event_type`, `visibility`, " ..
			"`payload`, `available_at`, `created_at`) VALUES (%s, 'ops.alert', 'staff', %s, %d, %d)",
			db.escapeString(key),
			db.escapeString(json.encode({
				eventVersion = 1,
				severity = "warning",
				source = "player-report",
				title = "player reported for botting",
				-- The reporter's free text is deliberately NOT included. It is
				-- untrusted, it is about to be rendered in a Discord embed,
				-- and the console shows it in full to whoever opens the case.
				summary = string.format(
					"%s was reported by %s for %s.",
					targetName, name, getReportReasonName(reportReason)),
				diagnosis = string.format("Report type: %s", getReportTypeName(reportType)),
				recommendedAction = "Open the Desk and run Investigate on that character.",
				occurredAt = os.time(),
				reference = "report:" .. targetName,
			})),
			os.time(), os.time()))
	end

	self:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		                     "Thank you for reporting %s. Your report will be processed by %s team as soon as possible.",
		                     targetName,
		                     configManager.getString(configKeys.SERVER_NAME)))
end

event:register()
