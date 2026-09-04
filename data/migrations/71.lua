-- Discord Hub notification policy (db_version 71 -> 72).
-- Critical escalation is Discord-only; remove the unused email delivery state.

function onUpdateDatabase()
	logMigration("Updating database to version 72 (Discord-only ops escalation)")

	if not db.query([[
		ALTER TABLE `integration_events`
		DROP COLUMN IF EXISTS `email_delivered_at`
	]]) then
		logMigration("Failed to remove integration_events.email_delivered_at")
		return false
	end

	return true
end
