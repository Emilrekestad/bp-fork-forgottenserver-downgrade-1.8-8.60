-- Achievements window — custom protocol.
--
-- Mirrors bao_protocol.lua exactly: one raw opcode byte per direction claimed
-- through PacketHandler / NetworkMessage, a sub-type byte inside the payload
-- for routing, gated on supportsCustomNetwork.
--
-- 0x4A/0x4B (74/75 decimal): inside the OTClientV8-reserved custom opcode
-- range (0x40-0x4F), confirmed free against the client's ClientOpcodes /
-- GameServerOpcodes enums, the server's native protocolgame.cpp switch, and
-- the two neighbours already spoken for in this codebase — 0x4C/0x4D (Bao)
-- and 0x4F (Item Bazaar).
local OPCODE_ACHIEVEMENTS_REQUEST = 0x4A -- client -> server
local OPCODE_ACHIEVEMENTS_SEND = 0x4B    -- server -> client

local RESP_SYNC = 0x01
local RESP_SECRETS = 0x02
local RESP_HIGHSCORES = 0x03

local ACTION_REQUEST_SYNC = 0x01
local ACTION_SET_SHOWCASE = 0x02
local ACTION_REQUEST_HIGHSCORES = 0x03

-- (!) HIGHSCORES RIDES THIS OPCODE PAIR RATHER THAN CLAIMING ITS OWN.
--
-- The OTClientV8 custom range is 0x40-0x4F and it is nearly spent: 0x4A/0x4B
-- here, 0x4C/0x4D Bao, 0x4F Item Bazaar. Highscores and achievements now share
-- one window with two tabs, so they are one feature from the player's side and
-- there is no reason for them to be two from the wire's.
--
-- The sub-type byte already routes everything, so this costs one more constant
-- in each direction and nothing else.

-- Matches Bao and the Item Bazaar. A sync walks the player's unlock list and
-- the rarity column, so an unthrottled client can hold that loop open for free.
local ACTION_COOLDOWN = 400

-- (!) Why the catalogue is not sent.
--
-- The full catalogue is 71.7 KB of name and description text (43.2 KB across
-- the 242 public achievements, 28.5 KB across the 156 secrets) against a
-- NETWORKMESSAGE_MAXSIZE of 65,500 (src/const.h) — so it cannot be sent whole
-- at all. Even the public half, which would fit, has no business crossing the
-- wire: it is identical for every player and changes only when the server is
-- rebuilt. So the client ships the public catalogue as a generated data file
-- (tools/gen_achievement_catalogue.js) and the server sends only what is
-- personal: which are unlocked, when, how rare each one is, and the full text
-- of any SECRET the player has actually earned.
--
-- Secrets are the one thing that cannot be shipped — their names and text are
-- the reward for finding them, so they arrive over the wire once earned. They
-- are paged rather than sent in one message: 28.5 KB fits today, but that is a
-- figure that grows every time a secret is added, and a ceiling reached later
-- would truncate silently.
local SECRET_PAGE_BUDGET = 24000

local function supportsCustomNetwork(player)
	return player and player.isUsingOtClient and player:isUsingOtClient()
end

-- Sends every secret this player has revealed, in pages that stay well inside
-- the message ceiling.
--
-- (!) The page is assembled in Lua first and only then written, rather than
-- reserving a header and seeking back to patch the count in. NetworkMessage::add
-- increments `info.length` unconditionally (src/networkmessage.h:112), so
-- rewriting an earlier byte does not overwrite it in the eyes of the buffer --
-- it counts as extra content and the message goes out longer than it really
-- is, with garbage on the end. Never back-patch a NetworkMessage.
--
-- The budget is measured from the actual string lengths, so the bound holds
-- regardless of how the buffer accounts for a partially written packet.
local function sendSecrets(player, secretIds)
	local index = 1
	local total = #secretIds

	repeat
		local page, budget = {}, 0
		while index <= total and budget < SECRET_PAGE_BUDGET do
			local id = secretIds[index]
			local entry = achievements[id]
			if entry then
				local name = entry.name or ""
				local description = entry.description or ""
				page[#page + 1] = {
					id = id,
					grade = math.min(tonumber(entry.grade) or 1, 0xFF),
					points = math.min(tonumber(entry.points) or 0, 0xFFFF),
					name = name,
					description = description,
				}
				budget = budget + 9 + #name + #description
			end
			index = index + 1
		end

		local out = NetworkMessage(player)
		out:addByte(OPCODE_ACHIEVEMENTS_SEND)
		out:addByte(RESP_SECRETS)
		out:addByte(index > total and 1 or 0)
		out:addU16(#page)

		for _, secret in ipairs(page) do
			out:addU16(secret.id)
			out:addByte(secret.grade)
			out:addU16(secret.points)
			out:addString(secret.name)
			out:addString(secret.description)
		end

		out:sendToPlayer(player)
	until index > total
end

local function sendSync(player)
	local unlocked = player:getAchievements()
	table.sort(unlocked)

	local totals = AchievementsDB.totals()
	local rarity = AchievementsDB.rarityTable()

	local secretIds = {}
	local unlockedSet = {}
	local unlockedByGrade = {}
	for _, id in ipairs(unlocked) do
		unlockedSet[id] = true
		local entry = achievements[id]
		if entry then
			local grade = tonumber(entry.grade) or 1
			unlockedByGrade[grade] = (unlockedByGrade[grade] or 0) + 1
			if entry.secret then
				secretIds[#secretIds + 1] = id
			end
		end
	end

	-- Sorted so the client can lay the difficulty meters out in the order it
	-- receives them, without needing to know what grades exist.
	local grades = {}
	for grade in pairs(totals.byGrade) do
		grades[#grades + 1] = grade
	end
	table.sort(grades)

	local out = NetworkMessage(player)
	out:addByte(OPCODE_ACHIEVEMENTS_SEND)
	out:addByte(RESP_SYNC)

	out:addU32(AchievementsDB.catalogueChecksum())
	out:addU16(math.min(player:getAchievementPoints(), 0xFFFF))
	out:addU16(math.min(totals.points, 0xFFFF))
	out:addU16(math.min(#unlocked, 0xFFFF))
	out:addU16(math.min(totals.count, 0xFFFF))
	out:addU16(math.min(#secretIds, 0xFFFF))
	out:addU16(math.min(totals.secrets, 0xFFFF))
	out:addU16(math.min(AchievementsDB.population, 0xFFFF))
	out:addU16(math.min(AchievementsDB.getShowcase(player:getGuid()), 0xFFFF))

	out:addByte(math.min(#grades, 0xFF))
	for index = 1, math.min(#grades, 0xFF) do
		local grade = grades[index]
		out:addByte(math.min(grade, 0xFF))
		out:addU16(math.min(unlockedByGrade[grade] or 0, 0xFFFF))
		out:addU16(math.min(totals.byGrade[grade] or 0, 0xFFFF))
	end

	out:addU16(math.min(#unlocked, 0xFFFF))
	for index = 1, math.min(#unlocked, 0xFFFF) do
		local id = unlocked[index]
		local unlockedAt = tonumber(player:getStorageValue(PlayerStorageKeys.achievementsBase + id)) or 0
		out:addU16(id)
		-- A 1 here means "unlocked, date unknown" — rows written before the
		-- timestamp existed, or set by hand. Sent as 0 so the client shows no
		-- date rather than 1970.
		out:addU32(unlockedAt > 1000000 and math.min(unlockedAt, 0xFFFFFFFF) or 0)
	end

	-- Rarity for the public catalogue plus this player's own revealed secrets.
	-- Sending it for every secret would leak how many secrets exist at each
	-- rarity, and by elimination which ones the player is missing.
	local rarityRows = {}
	for id = 1, #achievements do
		local entry = achievements[id]
		if entry and (not entry.secret or unlockedSet[id]) then
			rarityRows[#rarityRows + 1] = id
		end
	end

	out:addU16(math.min(#rarityRows, 0xFFFF))
	for index = 1, math.min(#rarityRows, 0xFFFF) do
		local id = rarityRows[index]
		out:addU16(id)
		out:addU16(math.min(rarity[id] or 0, 0xFFFF))
	end

	if not out:sendToPlayer(player) then
		return
	end

	if #secretIds > 0 then
		sendSecrets(player, secretIds)
	end
end

-- ─── Highscores ─────────────────────────────────────────────────────────
--
-- One page of one board, plus everything the window needs to draw its own
-- chrome: the board list, the vocation list, the leader, and where this
-- character stands. Sent whole on every request rather than split across a
-- catalogue message and a data message — the entire payload is a couple of
-- kilobytes, and a stateless response cannot get out of order with itself.
--
-- Nothing here approaches NETWORKMESSAGE_MAXSIZE (65,500): 25 rows of roughly
-- 40 bytes is 1 KB, which is why this needs none of the paging the 71.7 KB
-- achievement catalogue forced on sendSecrets above.
local function sendHighscores(player, boardId, vocationId, page)
	local data = HighscoresDB.fetch(boardId, vocationId, page)
	if not data then
		return
	end

	local boards = HighscoresDB.availableBoards()
	local out = NetworkMessage(player)
	out:addByte(OPCODE_ACHIEVEMENTS_SEND)
	out:addByte(RESP_HIGHSCORES)

	-- The catalogue, from the same Lua config the website's table is published
	-- from. The client never ships its own copy of this list.
	out:addByte(math.min(#boards, 0xFF))
	for index = 1, math.min(#boards, 0xFF) do
		local board = boards[index]
		out:addByte(board.id)
		out:addString(board.label)
		out:addString(board.title)
		out:addString(board.unit or board.title)
		out:addString(board.extraLabel or "")
		-- The group is what tells the client which boards are keys along the
		-- top and which collapse into the Skills chooser. Sent rather than
		-- inferred: the split is a property of the catalogue, and the client
		-- guessing it would be a second copy of the same decision.
		out:addString(board.group)
		out:addByte(board.vocation and 1 or 0)
	end

	out:addByte(data.board.id)
	out:addByte(data.vocation)
	out:addByte(data.page)

	-- Vocations, resolved server-side so the client never has to know what
	-- this server's vocation table looks like.
	local vocations = {}
	if data.board.vocation then
		for id = 1, 4 do
			local voc = Vocation(id)
			if voc then
				vocations[#vocations + 1] = { id = id, name = voc:getName() }
			end
		end
	end
	out:addByte(#vocations)
	for _, voc in ipairs(vocations) do
		out:addByte(voc.id)
		out:addString(voc.name)
	end

	-- (!) VALUES CROSS AS FORMATTED STRINGS, NOT NUMBERS.
	--
	-- They were U32 and it broke in public on the first look: a level-5,000
	-- character's experience is far past 4,294,967,295, so `math.min` clamped
	-- it and the window showed every high-level character with the identical
	-- fake total 4,294,967,295. Bank balance would do the same.
	--
	-- Strings also put the formatting on the side that knows what each board
	-- means, so the client never has to decide whether a column is Marks,
	-- experience or days.
	out:addByte(math.min(#data.rows, 0xFF))
	for index = 1, math.min(#data.rows, 0xFF) do
		local row = data.rows[index]
		out:addU16(math.min(row.rank, 0xFFFF))
		out:addString(row.name)
		out:addU16(math.min(row.level, 0xFFFF))
		out:addString(row.vocation)
		out:addString(HighscoresDB.formatNumber(row.value))
		out:addString(HighscoresDB.formatNumber(row.extra or 0))
	end

	-- The leader, and only when there genuinely is one. A board where nobody
	-- has scored ranks everyone at zero and every row ties at 1; crowning an
	-- arbitrary one of them would be inventing a champion the data does not
	-- name. The website enforces the identical rule.
	local first, second = data.rows[1], data.rows[2]
	local hasLeader = page == 1 and first and first.value > 0
		and (not second or second.value < first.value)

	out:addByte(hasLeader and 1 or 0)
	if hasLeader then
		out:addString(first.name)
		out:addU16(math.min(first.level, 0xFFFF))
		out:addString(first.vocation)
		out:addString(HighscoresDB.formatNumber(first.value))
		out:addU16(first.outfit.type or 0)
		out:addByte(first.outfit.head or 0)
		out:addByte(first.outfit.body or 0)
		out:addByte(first.outfit.legs or 0)
		out:addByte(first.outfit.feet or 0)
		out:addByte(first.outfit.addons or 0)
	end

	-- Where the viewer stands. The one thing this window can say that the
	-- website cannot, because it knows who is looking.
	local mine = HighscoresDB.rankOf(player, data.board.id, data.vocation)
	out:addByte(mine and 1 or 0)
	if mine then
		out:addU16(math.min(mine.rank, 0xFFFF))
		out:addString(HighscoresDB.formatNumber(mine.value))
	end

	out:sendToPlayer(player)
end

local requestHandler = PacketHandler(OPCODE_ACHIEVEMENTS_REQUEST)

function requestHandler.onReceive(player, msg)
	if not supportsCustomNetwork(player) then
		return
	end

	local action = NetworkGuard.readByte(msg)
	if not action then
		return
	end

	if not NetworkGuard.cooldown(player, "achievements:" .. action, ACTION_COOLDOWN) then
		return
	end

	if action == ACTION_REQUEST_SYNC then
		sendSync(player)
	elseif action == ACTION_SET_SHOWCASE then
		local achievementId = NetworkGuard.readU16(msg)
		if achievementId == nil then
			return
		end

		-- Answer with a full re-sync rather than a bespoke acknowledgement:
		-- the client redraws from its cache wholesale anyway, and this way a
		-- rejected nomination silently corrects the client's view instead of
		-- leaving it showing something the server never accepted.
		AchievementsDB.setShowcase(player, achievementId)
		sendSync(player)
	elseif action == ACTION_REQUEST_HIGHSCORES then
		local boardId = NetworkGuard.readByte(msg)
		local vocationId = NetworkGuard.readByte(msg)
		local page = NetworkGuard.readByte(msg)
		if boardId == nil or vocationId == nil or page == nil then
			return
		end

		-- Guarded because the highscores lib is a separate feature: a server
		-- booted without it must still serve the achievements tab.
		if HighscoresDB then
			sendHighscores(player, boardId, vocationId, page)
		end
	end
end

requestHandler:register()
