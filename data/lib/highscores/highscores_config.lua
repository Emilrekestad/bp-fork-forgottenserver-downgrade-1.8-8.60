-- Highscores — the board catalogue, authored here and nowhere else.
--
-- Three surfaces rank players: the website (system/pages/highscores.php), the
-- in-game window (modules/game_records), and anything that comes later. Before
-- this file the website carried its own PHP list of boards and the client
-- would have needed a second copy — the exact shape of the bug that killed
-- seventeen Bao hunts, where two hand-maintained ladders drifted apart and
-- nothing errored.
--
-- So this is the single authored source. HighscoresDB.publishBoards() projects
-- it into `highscore_boards` at startup, the website renders from that table,
-- and the client receives it over the wire. Nobody keeps a second copy.
--
-- The split of responsibility is worth stating plainly:
--
--   * THIS FILE owns what a board IS — its identity, its label, its column
--     heading, whether it has a vocation axis, and whether this server offers
--     it at all (`enabled`).
--   * The SQL below owns how a board is RANKED. It lives here rather than in
--     the projection because it is server-side machinery; the website has its
--     own Eloquent queries and does not read it.
--
-- (!) `id` is the WIRE id. It is written into packets, so it must never be
-- reused for a different board — retire an id rather than recycling it.

HighscoresConfig = {}

-- Families. The website draws them as position and spacing rather than
-- captions; the client uses them to group its board buttons the same way.
HighscoresConfig.Groups = {
	adventure = { ordering = 1, title = "Adventure" },
	mastery = { ordering = 2, title = "Mastery" },
	dedication = { ordering = 3, title = "Dedication" },
}

-- The skill columns are on `players` directly (TFS 1.0 layout, confirmed
-- against the live schema: skill_fist, skill_fist_tries, ...). The `tries`
-- column is the tie-break, which is what makes two characters at skill 10
-- rank in the order they actually earned it.
local function skillBoard(id, key, label, title, column, ordering)
	return {
		id = id, key = key, group = "mastery", ordering = ordering,
		-- `unit` is the client's value-column heading, so it takes the SHORT
		-- label: "Distance Fighting" over a column of three-digit numbers is a
		-- heading wider than the data under it.
		label = label, title = title, unit = label, vocation = true, enabled = true,
		value = "p.`" .. column .. "`",
		order = "p.`" .. column .. "` DESC, p.`" .. column .. "_tries` DESC",
		extra = "p.`level`", extraLabel = "Level",
	}
end

HighscoresConfig.Boards = {
	{
		id = 1, key = "experience", group = "adventure", ordering = 1,
		label = "Experience", title = "Experience", unit = "Level",
		vocation = true, enabled = true,
		value = "p.`level`",
		order = "p.`level` DESC, p.`experience` DESC",
		extra = "p.`experience`", extraLabel = "Experience",
	},
	{
		-- Off, matching the website today. Authored here so turning it on is a
		-- one-word change in one file rather than a MyAAC setting the client
		-- cannot see.
		id = 2, key = "balance", group = "adventure", ordering = 2,
		label = "Balance", title = "Bank Balance", unit = "Balance",
		vocation = true, enabled = false,
		value = "p.`balance`",
		order = "p.`balance` DESC",
		extra = "p.`level`", extraLabel = "Level",
	},
	{
		id = 3, key = "frags", group = "adventure", ordering = 3,
		label = "Frags", title = "Frags", unit = "Frags",
		vocation = true, enabled = false,
		value = "(SELECT COUNT(*) FROM `player_deaths` d WHERE d.`killed_by` = p.`name` AND d.`unjustified` = 1)",
		order = "`value` DESC",
		extra = "p.`level`", extraLabel = "Level",
	},

	{
		id = 4, key = "magic", group = "mastery", ordering = 1,
		label = "Magic Level", title = "Magic Level", unit = "Magic Level",
		vocation = true, enabled = true,
		value = "p.`maglevel`",
		order = "p.`maglevel` DESC, p.`manaspent` DESC",
		extra = "p.`level`", extraLabel = "Level",
	},
	skillBoard(5, "shield", "Shielding", "Shielding", "skill_shielding", 2),
	skillBoard(6, "distance", "Distance", "Distance Fighting", "skill_dist", 3),
	skillBoard(7, "sword", "Sword", "Sword Fighting", "skill_sword", 4),
	skillBoard(8, "axe", "Axe", "Axe Fighting", "skill_axe", 5),
	skillBoard(9, "club", "Club", "Club Fighting", "skill_club", 6),
	skillBoard(10, "fist", "Fist", "Fist Fighting", "skill_fist", 7),
	skillBoard(11, "fishing", "Fishing", "Fishing", "skill_fishing", 8),

	{
		id = 12, key = "achievements", group = "dedication", ordering = 1,
		label = "Achievements", title = "Achievement Points", unit = "Points",
		vocation = true, enabled = true,
		-- (!) COALESCE wraps the SUBQUERY, not the column. A subquery matching
		-- no rows is NULL as a whole, so a COALESCE placed inside it never
		-- runs and every character without achievements ranks as blank rather
		-- than as zero. The website hit exactly this.
		value = "COALESCE((SELECT s.`points` FROM `player_achievement_summary` s WHERE s.`player_id` = p.`id`), 0)",
		order = "`value` DESC, p.`level` DESC",
		extra = "COALESCE((SELECT s.`unlocked` FROM `player_achievement_summary` s WHERE s.`player_id` = p.`id`), 0)",
		extraLabel = "Unlocked",
		requiresTable = "player_achievement_summary",
	},
	{
		id = 13, key = "ledger", group = "dedication", ordering = 2,
		label = "Ledger", title = "Bao's Ledger", unit = "Lessons",
		vocation = true, enabled = true,
		value = "COALESCE((SELECT s.`ranks` FROM `bao_ledger_summary` s WHERE s.`player_id` = p.`id`), 0)",
		order = "`value` DESC, p.`level` DESC",
		extra = "COALESCE((SELECT s.`invested` FROM `bao_ledger_summary` s WHERE s.`player_id` = p.`id`), 0)",
		extraLabel = "Marks invested",
		requiresTable = "bao_ledger_summary",
	},
	{
		-- Account-scoped, so it carries no `value`/`order`: HighscoresDB runs a
		-- separate query for it, the same way the website keeps
		-- loyalty-highscores.php apart from highscores.php. It has no vocation
		-- axis at all.
		id = 14, key = "loyalty", group = "dedication", ordering = 3,
		label = "Loyalty", title = "Loyalty", unit = "Premium days",
		vocation = false, enabled = true,
		accountScoped = true,
		extraLabel = "Streak",
		requiresTable = "loyalty_account",
	},
}

-- Boards in display order: group first, then the board's own ordering. Sorted
-- once here so every consumer -- the projection, the wire, the website -- sees
-- the same order without re-deriving it.
function HighscoresConfig.ordered()
	local list = {}
	for _, board in ipairs(HighscoresConfig.Boards) do
		list[#list + 1] = board
	end

	table.sort(list, function(a, b)
		local ga = HighscoresConfig.Groups[a.group]
		local gb = HighscoresConfig.Groups[b.group]
		local oa = ga and ga.ordering or 99
		local ob = gb and gb.ordering or 99
		if oa ~= ob then
			return oa < ob
		end
		if a.ordering ~= b.ordering then
			return a.ordering < b.ordering
		end
		return a.id < b.id
	end)

	return list
end

function HighscoresConfig.byKey(key)
	for _, board in ipairs(HighscoresConfig.Boards) do
		if board.key == key then
			return board
		end
	end
	return nil
end

function HighscoresConfig.byId(id)
	id = tonumber(id)
	for _, board in ipairs(HighscoresConfig.Boards) do
		if board.id == id then
			return board
		end
	end
	return nil
end

-- Duplicate ids or keys would corrupt the wire and the projection silently, so
-- they are caught at load the way BaoRank.validateLadder catches an
-- unreachable rank. Cheap once, invisible otherwise.
function HighscoresConfig.validate()
	local seenId, seenKey, ok = {}, {}, true

	for _, board in ipairs(HighscoresConfig.Boards) do
		if seenId[board.id] then
			print(string.format(">> [Highscores] DUPLICATE BOARD ID %d (%s and %s)",
				board.id, seenId[board.id], board.key))
			ok = false
		end
		if seenKey[board.key] then
			print(string.format(">> [Highscores] DUPLICATE BOARD KEY '%s'", board.key))
			ok = false
		end
		seenId[board.id] = board.key
		seenKey[board.key] = true
	end

	return ok
end

HighscoresConfig.validate()
