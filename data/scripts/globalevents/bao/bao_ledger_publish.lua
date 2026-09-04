-- Bao's Ledger: publish the track catalogue to the database.
--
-- A GlobalEvent rather than a call at the bottom of bao_ledger_db.lua, for the
-- same reason loyalty_stamp.lua publishes its ladder here: lib files are loaded
-- before the database connection is guaranteed, and a publish that silently
-- fails at load time leaves the website rendering an empty Ledger with nothing
-- in the log to say why.
--
-- There is no summary rebuild to run alongside it. Ranks live in the kv store,
-- which is only reachable through a Player, so every character's row is written
-- on their next login instead -- see the note at the top of bao_ledger_db.lua.

local ledgerPublish = GlobalEvent("BaoLedgerPublish")

function ledgerPublish.onStartup()
	if not BaoLedgerDB then
		return true
	end

	BaoLedgerDB.publishTracks()

	-- Published rows against the config's own denominator. These agree unless
	-- the publish wrote nothing, which is exactly the failure that would
	-- otherwise show up as a website quoting "12 of 0".
	local tracked, denominator, expected = BaoLedgerDB.totals()
	if denominator ~= expected then
		print(string.format(
			">> [Bao] LEDGER PUBLISH MISMATCH -- %d ranks published, %d expected. The website denominator is wrong.",
			denominator, expected))
	else
		print(string.format(">> Bao's Ledger: %d tracks published (%d ranks total)", tracked, denominator))
	end

	return true
end

ledgerPublish:register()
