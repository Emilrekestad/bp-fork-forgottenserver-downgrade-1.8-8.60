-- Highscores: publish the board catalogue to the database.
--
-- A GlobalEvent rather than a call at the bottom of the lib, for the same
-- reason loyalty_stamp.lua and bao_ledger_publish.lua are: lib files load
-- before the database connection is guaranteed, and a publish that silently
-- fails at load time leaves the website rendering an empty board list with
-- nothing in the log to say why.

local publish = GlobalEvent("HighscoresPublish")

function publish.onStartup()
	if not HighscoresDB then
		return true
	end

	local published = HighscoresDB.publishBoards()
	local offered = #HighscoresDB.availableBoards()

	-- Published rows against what is actually offerable. They differ whenever a
	-- board is disabled or its mirror table has not been created yet, which is
	-- worth saying out loud rather than leaving someone to wonder why the site
	-- shows eleven boards and the config lists fourteen.
	print(string.format(">> Highscores: %d boards published, %d offered", published, offered))
	return true
end

publish:register()
