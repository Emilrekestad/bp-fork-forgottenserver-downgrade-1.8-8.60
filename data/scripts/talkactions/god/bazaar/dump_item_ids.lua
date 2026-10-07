-- /dumpitemids -- writes a serverId,clientId map to the server's data folder.
--
-- The website serves item images as www/images/items/<SERVER id>.png, but the
-- client exports them keyed by CLIENT id (that is the only id the .dat knows).
-- items.otb holds the mapping, and the game server already has it parsed, so
-- dumping it here is far simpler than re-parsing the otb elsewhere.
--
-- Read by the rename step of the sprite pipeline; safe to re-run at any time.

local dump = TalkAction("/dumpitemids")

function dump.onSay(player, words, param)
	if player:getAccountType() < ACCOUNT_TYPE_GOD then
		return true
	end

	local path = "data/items/itemid_map.csv"
	local file = io.open(path, "w")
	if not file then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE,
			"[Bazaar] Could not open " .. path .. " for writing.")
		return false
	end

	file:write("server_id,client_id\n")
	local written, skipped = 0, 0
	-- 100 is the first real item id; the engine reports the highest through
	-- Game.getItemIdByName-free means, so walk the full id space and let
	-- ItemType tell us what exists.
	for serverId = 100, 65535 do
		local itemType = ItemType(serverId)
		if itemType and itemType:getClientId() and itemType:getClientId() > 0 then
			file:write(serverId .. "," .. itemType:getClientId() .. "\n")
			written = written + 1
		else
			skipped = skipped + 1
		end
	end
	file:close()

	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
		"[Bazaar] Wrote %d id pairs to %s (%d ids had no client id).", written, path, skipped))
	return false
end

dump:separator(" ")
-- Security audit 2026-10-05: writes a file on the server, so the gate is
-- registered here as well (refused and logged by the C++ dispatcher).
dump:accountType(ACCOUNT_TYPE_GOD)
dump:register()
