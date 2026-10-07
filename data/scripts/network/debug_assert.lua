local debugAssert = PacketHandler(0xE8)

-- (!) Security audit 2026-10-05: hasDebugAssertSent() is never set to true
-- anywhere in the C++ (ProtocolGame::debugAssertSent has no writer), so the
-- guard below never fired and a hand-built client could INSERT a row of up
-- to four 64 KB strings 25 times a second, for as long as it liked, into a
-- table nothing ever prunes -- on a disk that is 92% full. One report per
-- session is all a real client ever sends; everything past that is dropped,
-- and each field is capped at what the column can usefully hold.
local MAX_FIELD_LENGTH = 255
local ONE_PER_SESSION_MS = 6 * 60 * 60 * 1000

function debugAssert.onReceive(player, msg)
	if player:hasDebugAssertSent() then return end
	if not NetworkGuard.cooldown(player, "debug-assert", ONE_PER_SESSION_MS) then return end

	local assertLine = NetworkGuard.readString(msg, MAX_FIELD_LENGTH)
	local date = NetworkGuard.readString(msg, MAX_FIELD_LENGTH)
	local description = NetworkGuard.readString(msg, MAX_FIELD_LENGTH)
	local comment = NetworkGuard.readString(msg, MAX_FIELD_LENGTH)
	if not assertLine or not date or not description or not comment then
		return
	end

	local query = string.format(
		"INSERT INTO `player_debugasserts` (`player_id`, `assert_line`, `date`, `description`, `comment`) VALUES(%d, %s, %s, %s, %s)",
		player:getGuid(),
		db.escapeString(assertLine),
		db.escapeString(date),
		db.escapeString(description),
		db.escapeString(comment)
	)
	
	db.asyncQuery(query)
end

debugAssert:register()
