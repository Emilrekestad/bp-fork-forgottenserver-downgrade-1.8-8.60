-- Old Man Bao — custom protocol. Mirrors data/scripts/network/cyclopedia/
-- ciclopedia.lua's pattern exactly: one raw opcode byte claimed per direction
-- via PacketHandler (receive) / NetworkMessage + :sendToPlayer (send), a
-- sub-type byte inside the payload for message routing, gated on
-- supportsCustomNetwork (player:isUsingOtClient()).
--
-- Mutating actions (accept/abandon/claim/purchase/bounty) all follow the same
-- shape: validate everything server-side against BaoConfig/BaoState (never
-- trust anything from the client beyond an id), then respond with a fresh
-- sendSyncFull() rather than a bespoke delta message — simpler and just as
-- correct, since the client redraws its cache wholesale on every sync anyway.

-- 0x4C/0x4D (76/77 decimal): inside the OTClientV8-reserved custom opcode
-- range (0x40-0x4F / 64-79, see otclient-src/src/client/protocolcodes.h),
-- confirmed free against BOTH the client's ClientOpcodes/GameServerOpcodes
-- enums and the server's native protocolgame.cpp switch. The PREVIOUS choice
-- here, 0x65/0x66, was a serious bug: those are the native hardcoded
-- "walk north" (client->server) and "map row stream" (server->client)
-- opcodes — every Bao action was silently walking the player north instead
-- of reaching this handler, and every Bao push was corrupting the live map
-- stream, desyncing the client's protocol parser. Never reuse 0x65/0x66.
local OPCODE_BAO_REQUEST = 0x4C -- client -> server
local OPCODE_BAO_SEND = 0x4D    -- server -> client

local RESP_SYNC_FULL = 0x01
local RESP_OPEN_WINDOW = 0x02
local RESP_ERROR = 0x03
local RESP_SHOP_DATA = 0x04
local RESP_STATUS = 0x05
local RESP_BOUNTY_DATA = 0x06
local RESP_LEDGER_DATA = 0x07
local RESP_PROFILE_DATA = 0x08

local ACTION_REQUEST_SYNC = 0x01
local ACTION_ACCEPT_HUNT = 0x02
local ACTION_ABANDON_HUNT = 0x03
local ACTION_CLAIM_REWARD = 0x04
local ACTION_PURCHASE_ITEM = 0x05
local ACTION_REQUEST_SHOP = 0x06
local ACTION_REQUEST_BOUNTY = 0x07
local ACTION_TURNIN_BOUNTY = 0x08
local ACTION_REQUEST_LEDGER = 0x0A
local ACTION_BUY_LEDGER = 0x0B
local ACTION_REQUEST_PROFILE = 0x0C
-- 0x09 was ACTION_REROLL_BOUNTY. Dropped when the board went weekly: with nine
-- entries spread across four difficulty bands there is always something
-- reachable, so a reroll was solving a problem that no longer exists — and it
-- interacted badly with partial hand-ins, where rerolling away an order you
-- had half-delivered has no good answer. Left unused rather than reassigned,
-- so an old client pressing the button is ignored instead of misrouted.

-- Longest identifier the client ever legitimately sends. Hunt ids and bounty
-- keys are config table keys; 64 is generous against the longest in either
-- table and cheap to enforce.
local MAX_KEY_LENGTH = 64

-- Per-action cooldown, in milliseconds. Every request answers with a full
-- re-sync, and a sync walks the whole hunt roster — so an unthrottled client
-- can hold that loop open for free. The Item Bazaar guards its packets at the
-- same 400ms; matching it keeps one number to reason about across both
-- systems. Reads are cheaper than writes but throttled alike: the cost here is
-- the response, not the request.
local ACTION_COOLDOWN = 400

local function supportsCustomNetwork(player)
	return player and player.isUsingOtClient and player:isUsingOtClient()
end

-- Picks one monster name to render as the card's portrait: the hunt's own
-- target for single-monster hunts, or (since Lua's pairs() order is stable
-- within a run, just not guaranteed across restarts) whichever key comes
-- first for family hunts — it only needs to be a representative face, not a
-- specific one.
local function representativeMonsterName(hunt)
	if hunt.kind == "single" then
		return hunt.target
	elseif hunt.kind == "family" and hunt.targets then
		-- Sorted rather than raw next(): pairs() order shifts between restarts,
		-- and a family hunt's portrait silently changing face is exactly the
		-- kind of churn that makes a window feel unstable.
		local names = {}
		for name in pairs(hunt.targets) do
			names[#names + 1] = name
		end
		table.sort(names)
		return names[1]
	end
	return nil
end

-- Human-readable "who you're actually hunting" line, shown under the hunt's
-- own title on the client (e.g. title "Webs in the Dark", label "Spider").
-- Family hunts list every contributing monster, sorted for a stable order.
local function targetLabel(hunt)
	if hunt.kind == "single" then
		return hunt.target or "?"
	elseif hunt.kind == "family" and hunt.targets then
		local names = {}
		for name in pairs(hunt.targets) do
			names[#names + 1] = name
		end
		table.sort(names)
		return table.concat(names, ", ")
	end
	return "?"
end

local function writeHuntOutfit(out, hunt)
	local monsterType = MonsterType(representativeMonsterName(hunt) or "")
	local outfit = monsterType and monsterType:outfit()
	out:addU16(outfit and outfit.lookType or 0)
	out:addByte(outfit and outfit.lookHead or 0)
	out:addByte(outfit and outfit.lookBody or 0)
	out:addByte(outfit and outfit.lookLegs or 0)
	out:addByte(outfit and outfit.lookFeet or 0)
	out:addByte(outfit and outfit.lookAddons or 0)
end

-- Stable catalog order: tier (by danger), then required count, then hunt id as
-- the final tiebreak. Built once per sync. The id tiebreak is what makes this
-- genuinely total — table.sort is not a stable sort, so two hunts equal on
-- both earlier keys would otherwise still swap places between calls.
local function sortedHuntIds()
	local ids = {}
	for huntId in pairs(BaoConfig.Hunts) do
		ids[#ids + 1] = huntId
	end
	table.sort(ids, function(a, b)
		local ha, hb = BaoConfig.Hunts[a], BaoConfig.Hunts[b]
		local ta = BaoConfig.TierOrder[ha.tier] or 99
		local tb = BaoConfig.TierOrder[hb.tier] or 99
		if ta ~= tb then
			return ta < tb
		end
		if ha.requiredCount ~= hb.requiredCount then
			return ha.requiredCount < hb.requiredCount
		end
		return a < b
	end)
	return ids
end

-- ─── Sends ──────────────────────────────────────────────────────────────

local function sendSyncFull(player)
	if not supportsCustomNetwork(player) then
		return false
	end

	local out = NetworkMessage(player)
	out:addByte(OPCODE_BAO_SEND)
	out:addByte(RESP_SYNC_FULL)

	local rankId = BaoState.getRankId(player)
	local currentRank, nextRank = nil, nil
	for _, rank in ipairs(BaoConfig.Ranks) do
		if rank.id == rankId then
			currentRank = rank
		elseif rank.id == rankId + 1 then
			nextRank = rank
		end
	end

	out:addByte(rankId)
	out:addString(currentRank and currentRank.name or "?")
	out:addU32(BaoState.getReputation(player))
	out:addU32(BaoState.getMarks(player))
	-- Chapters HEARD and total, not the raw storyChapter key -- see
	-- BaoRank.chaptersHeard for why the raw value lies.
	local heard, totalChapters = BaoRank.chaptersHeard(player)
	out:addByte(heard)
	out:addByte(totalChapters)
	-- u16, not a byte: the roster is already 61 hunts and is meant to grow to
	-- 150+. A byte silently wraps past 255 and would report a Legend as a
	-- Stray. Same reasoning for masteriesRequired below.
	out:addU16(BaoState.getMasteryCount(player))
	out:addU32(currentRank and currentRank.repThreshold or 0)

	-- A promotion the player has earned but not yet collected. Sent so the
	-- window can point them at the NPC rather than silently withholding the
	-- rank -- promotions happen in Bao's own voice now, standing in front of
	-- him, so the UI has to say where to go.
	local pending = BaoRank.pendingRank(player)
	out:addByte(pending and 1 or 0)
	if pending then
		out:addString(pending.name)
	end
	if nextRank then
		out:addByte(1)
		out:addString(nextRank.name)
		out:addU32(nextRank.repThreshold)
		out:addU16(nextRank.masteriesRequired)
	else
		out:addByte(0) -- already at max rank
	end

	-- The ladder, for the Chapters tab. Small and fixed-size, so it is cheaper
	-- to send whole on every sync than to add a request type for it.
	--
	-- Each rank carries the chapter it tells, because rank and chapter are the
	-- SAME step under two names — being promoted IS hearing the next chapter.
	-- Ranks 1-6 map exactly onto chapters I-VI. Sending them together is what
	-- lets the client stop presenting one progression as two.
	local currentChapter = BaoState.getStoryChapter(player)
	out:addByte(#BaoConfig.Ranks)
	for _, rank in ipairs(BaoConfig.Ranks) do
		local chapter = BaoConfig.StoryChapters and BaoConfig.StoryChapters[rank.storyChapter]
		out:addByte(rank.id)
		out:addString(rank.name)
		out:addU32(rank.repThreshold)
		out:addU16(rank.masteriesRequired)
		out:addString(chapter and chapter.title or "")
		-- Bao's actual words. Sent ONLY for a chapter the player has heard --
		-- the tab is named after this story and never showed a line of it, but
		-- shipping the unheard ones too would let the client read ahead and
		-- spoil the only reward the Chapters tab has to give.
		local heard = chapter and rank.storyChapter and rank.storyChapter <= currentChapter
		out:addString(heard and chapter.text or "")
	end

	-- Chapters no rank grants. These come from World's End hunts, so they sit
	-- past the end of the ladder as an epilogue rather than inside it — which
	-- is also the honest way to present them, since no amount of ranking up
	-- will ever unlock them.
	local rankChapters = {}
	for _, rank in ipairs(BaoConfig.Ranks) do
		rankChapters[rank.storyChapter] = true
	end
	local epilogue = {}
	for key in pairs(BaoConfig.StoryChapters or {}) do
		if not rankChapters[key] then
			epilogue[#epilogue + 1] = key
		end
	end
	table.sort(epilogue)

	out:addByte(#epilogue)
	for _, key in ipairs(epilogue) do
		local heard = key <= currentChapter
		out:addString(BaoConfig.StoryChapters[key].title)
		out:addByte(heard and 1 or 0)
		out:addString(heard and BaoConfig.StoryChapters[key].text or "")
	end

	local slots = BaoState.getActiveHunts(player)
	local maxSlots = BaoState.getMaxSlots(player)
	out:addByte(maxSlots)
	for slot = 1, maxSlots do
		local slotData = slots[slot]
		if slotData then
			local hunt = BaoConfig.Hunts[slotData.huntId]
			out:addByte(1) -- occupied
			out:addByte(slot)
			out:addString(slotData.huntId)
			out:addString(hunt and hunt.displayName or slotData.huntId)
			out:addString(hunt and targetLabel(hunt) or "?")
			out:addString(hunt and hunt.tier or "")
			out:addByte(slotData.state)
			out:addU32(slotData.progress)
			out:addU32(hunt and BaoState.requiredFor(player, hunt) or 0)
		else
			out:addByte(0) -- empty slot
		end
	end

	-- Full hunt catalog (every configured hunt, not just currently-acceptable
	-- ones) — the client derives BOTH the Available tab (minRank met, not
	-- already active, and either repeatable or not yet mastered) and the
	-- Mastered tab (locked/unlocked/mastered catalogue) from this single
	-- list, rather than the server sending two overlapping lists.
	--
	-- Measured at 5.6 KB for the current 61 hunts against a 65 KB message
	-- ceiling — roughly 700 hunts of headroom, so sending it whole every sync
	-- stays the right call.
	local catalogIds = sortedHuntIds()
	out:addU16(#catalogIds)
	for _, huntId in ipairs(catalogIds) do
		local hunt = BaoConfig.Hunts[huntId]
		local mastery = BaoState.getMastery(player, huntId)
		out:addString(huntId)
		out:addString(hunt.displayName)
		out:addString(targetLabel(hunt))
		out:addString(hunt.tier)
		out:addByte(hunt.minRank)
		out:addU32(BaoState.requiredFor(player, hunt))
		out:addByte(hunt.repeatable and 1 or 0)
		out:addU16(math.min(mastery.timesCompleted, 0xFFFF))
		-- What it pays. Sent for every hunt in the catalog so the card can show
		-- it before the player commits -- previously they accepted blind.
		-- How deep this hunt's rare table goes, as 1-3 "stars": every hunt can
		-- roll a rare, 38 of them reach very rare, 11 reach jackpot. It is the
		-- only thing that meaningfully separates two hunts of the same length,
		-- so the card has to show it.
		local bands = 1
		for _, entry in ipairs(hunt.rewards.rareTable) do
			if entry.weight > 0 then
				if entry.tier == "jackpot" then
					bands = math.max(bands, 3)
				elseif entry.tier == "very_rare" then
					bands = math.max(bands, 2)
				end
			end
		end
		out:addByte(bands)

		local reward = BaoReward.preview(player, hunt)
		out:addU32(reward.xp)
		out:addU32(reward.reputation)
		out:addU32(reward.marks)
		out:addU32(reward.firstXp)
		out:addU32(reward.firstReputation)
		out:addU32(reward.firstMarks)
		writeHuntOutfit(out, hunt)
	end

	return out:sendToPlayer(player)
end

local function sendOpenWindow(player, tab)
	if not supportsCustomNetwork(player) then
		return false
	end

	local out = NetworkMessage(player)
	out:addByte(OPCODE_BAO_SEND)
	out:addByte(RESP_OPEN_WINDOW)
	out:addString(tab or "available")
	return out:sendToPlayer(player)
end

-- Errors and confirmations both land in the window's own status line rather
-- than a modal box. A popup for "not enough marks" steals focus, has to be
-- dismissed, and hides the thing it is talking about — the Item Bazaar moved
-- away from that for the same reason.
local function sendError(player, reason)
	if not supportsCustomNetwork(player) then
		return false
	end

	local out = NetworkMessage(player)
	out:addByte(OPCODE_BAO_SEND)
	out:addByte(RESP_ERROR)
	out:addString(reason)
	return out:sendToPlayer(player)
end

local function sendStatus(player, text)
	if not supportsCustomNetwork(player) then
		return false
	end

	local out = NetworkMessage(player)
	out:addByte(OPCODE_BAO_SEND)
	out:addByte(RESP_STATUS)
	out:addString(text)
	return out:sendToPlayer(player)
end

local function sendShopData(player)
	if not supportsCustomNetwork(player) then
		return false
	end

	local out = NetworkMessage(player)
	out:addByte(OPCODE_BAO_SEND)
	out:addByte(RESP_SHOP_DATA)

	-- Categories first, in their declared order, so the client renders section
	-- headings rather than one flat grid of unrelated things. A shop that sells
	-- rope next to a permanent Wheel unlock needs the separation to be
	-- readable at all.
	out:addByte(#BaoConfig.ShopCategories)
	for _, category in ipairs(BaoConfig.ShopCategories) do
		out:addString(category.key)
		out:addString(category.title)
		out:addString(category.note or "")
	end

	local rankId = BaoState.getRankId(player)
	-- (!) EVERY item is sent, including ones above the player's rank.
	--
	-- Filtering by rank here meant a Stray opened the shop and saw rope, a
	-- shovel, a backpack and two stacks of potions -- while thirteen outfits and
	-- mounts, the Wheel of Destiny, both extra hunt slots and every promotion
	-- scroll stayed invisible. The shop looked like a junk stall instead of the
	-- reason to earn rank, which is exactly backwards for the one screen that is
	-- supposed to make Bao worth grinding.
	--
	-- The client already draws a locked row greyed with its reason, and the
	-- comment below says prerequisites are shown that way "so the ladder is
	-- visible from the bottom". Rank now follows the same rule.
	local keys = {}
	for itemKey in pairs(BaoConfig.ShopItems) do
		keys[#keys + 1] = itemKey
	end
	-- Sorted by rank, then cost, then key so the shop reads as a ladder and
	-- does not reshuffle between restarts, for the same pairs()-ordering reason
	-- the hunt catalog is sorted.
	table.sort(keys, function(a, b)
		local ia, ib = BaoConfig.ShopItems[a], BaoConfig.ShopItems[b]
		if ia.minRank ~= ib.minRank then
			return ia.minRank < ib.minRank
		end
		if ia.cost ~= ib.cost then
			return ia.cost < ib.cost
		end
		return a < b
	end)

	out:addU16(#keys)
	for _, itemKey in ipairs(keys) do
		local item = BaoConfig.ShopItems[itemKey]
		local owned = item.oneTime and BaoState.hasPurchased(player, itemKey)
		-- A prerequisite that has not been bought yet. Shown greyed with the
		-- reason rather than hidden, so the ladder is visible from the bottom.
		local rankLocked = item.minRank > rankId
		local locked = rankLocked or (item.requires and not BaoState.hasPurchased(player, item.requires))
		-- Rank is the more useful thing to name when both apply: a player cannot
		-- act on the prerequisite until the rank is reached anyway.
		local lockReason = ""
		if rankLocked then
			local rank = BaoConfig.Ranks[item.minRank + 1]
			lockReason = rank and rank.name or ("rank " .. item.minRank)
		elseif locked then
			lockReason = BaoConfig.ShopItems[item.requires].displayName
		end
		out:addString(itemKey)
		out:addString(item.displayName)
		out:addString(item.category)
		out:addString(item.description or "")
		out:addU32(item.cost)
		-- 0 for entries that run a grant() instead of handing over an item;
		-- the client draws its category icon rather than an item sprite.
		out:addU16(item.itemId or item.displayItemId or 0)
		-- Preview lookType for entries with no item sprite -- outfits and mounts.
		-- Outfits use the player's own gender so the row previews how it will
		-- actually look on them; mounts have a single look either way.
		local look = item.look or 0
		if look > 0 and item.lookFemale and player:getSex() == PLAYERSEX_FEMALE then
			look = item.lookFemale
		end
		out:addU16(look)
		-- Quantity-scaled entries: the client draws a stepper and multiplies the
		-- price by it. maxUnits is re-checked server-side on purchase.
		out:addByte(item.scalable and 1 or 0)
		out:addU16(item.maxUnits or 1)
		out:addByte(owned and 1 or 0)
		out:addByte(item.oneTime and 1 or 0)
		-- 0 open, 1 locked by RANK, 2 locked by a prerequisite purchase. The
		-- client words the row differently for each; a single boolean left it
		-- saying "Locked" with no reason anywhere the player could see it.
		out:addByte(locked and (rankLocked and 1 or 2) or 0)
		out:addString(lockReason)
	end

	return out:sendToPlayer(player)
end

-- Bounty board. Two different progress numbers travel here on purpose:
-- `delivered` is stored (what has been handed in this week) and `carried` is
-- read live from the player's inventory the moment the packet is built. The
-- card shows both, so "20 delivered, 6 in your bags, 30 wanted" reads at a
-- glance and neither number can drift from reality.
local function sendBountyData(player)
	if not supportsCustomNetwork(player) then
		return false
	end

	local out = NetworkMessage(player)
	out:addByte(OPCODE_BAO_SEND)
	out:addByte(RESP_BOUNTY_DATA)

	out:addU32(BaoBounty.secondsUntilReset())

	-- The player's difficulty band and the level range that produced it. Sent
	-- so the header can say "Hard - levels 130 to 299" rather than leaving the
	-- player to guess why the board changed when they levelled.
	local difficulty, gatedBy = BaoBounty.difficultyFor(player)
	local levelLow, levelHigh = BaoBounty.levelRangeFor(difficulty)
	out:addString(BaoConfig.BountyDifficulty[difficulty].name)
	out:addU16(levelLow)
	out:addU16(levelHigh or 0) -- 0 means "no upper bound"
	-- "level" or "rank": which of the two gates is currently the lower one, so
	-- the board can say why it is offering what it is offering.
	out:addString(gatedBy)

	local board = BaoBounty.boardFor(player)
	out:addByte(#board)
	for _, entry in ipairs(board) do
		local bounty = entry.bounty
		local marks, reputation = BaoBounty.payoutFor(bounty)
		out:addString(entry.key)
		out:addString(bounty.displayName)
		out:addString(bounty.flavor or "")
		out:addU16(bounty.itemId)
		out:addString(ItemType(bounty.itemId):getName())
		out:addU32(bounty.count)
		out:addU32(math.min(BaoBounty.carriedFor(player, bounty), 0xFFFFFFFF))
		out:addByte(BaoBounty.isClaimed(player, entry.key) and 1 or 0)
		out:addU32(marks)
		out:addU32(reputation)
	end

	return out:sendToPlayer(player)
end

-- Bao's Ledger: the permanent, escalating upgrade track. Sent as a whole
-- because it is five rows -- there is nothing to paginate.
local function sendLedgerData(player)
	if not supportsCustomNetwork(player) then
		return false
	end

	local out = NetworkMessage(player)
	out:addByte(OPCODE_BAO_SEND)
	out:addByte(RESP_LEDGER_DATA)

	out:addU16(BaoLedger.totalRanks(player))
	-- The denominator and the sunk cost. Both exist so the tab can show the
	-- SIZE of what is being built, not only the position in it.
	out:addU16(BaoLedger.maxRanks())
	out:addU32(BaoLedger.totalInvested(player))

	local books = BaoConfig.LedgerBooks or {}
	out:addByte(#books)
	for _, book in ipairs(books) do
		out:addString(book.title)
		out:addString(book.subtitle)
	end

	local keys = BaoLedger.orderedKeys()
	out:addByte(#keys)
	for _, key in ipairs(keys) do
		local track = BaoConfig.Ledger[key]
		local rank = BaoLedger.getRank(player, key)
		local cost = BaoLedger.costOf(player, key)
		out:addString(key)
		out:addByte(track.book or 1)
		out:addString(track.displayName)
		out:addString(track.summary)
		-- Formatted server-side so the client never has to know a track's
		-- per-rank arithmetic -- it only draws the sentence it is given.
		out:addString(string.format(track.effect, rank * track.perRank))
		out:addString(string.format(track.effect, (rank + 1) * track.perRank))
		out:addU16(rank)
		out:addU16(track.maxRank)
		out:addU32(cost or 0) -- 0 means maxed out
	end

	return out:sendToPlayer(player)
end

-- The Profile tab: one screen a player can screenshot to show where they got
-- to. Everything here is DERIVED on demand rather than stored -- mastery per
-- tier, trophies owned, unlocks -- so it can never disagree with the systems it
-- summarises. That costs one pass over the roster and the shop, which is
-- nothing at the rate a player opens this.
local function sendProfileData(player)
	if not supportsCustomNetwork(player) then
		return false
	end

	local out = NetworkMessage(player)
	out:addByte(OPCODE_BAO_SEND)
	out:addByte(RESP_PROFILE_DATA)

	local rankId = BaoState.getRankId(player)
	local currentRank
	for _, rank in ipairs(BaoConfig.Ranks) do
		if rank.id == rankId then
			currentRank = rank
		end
	end

	out:addByte(rankId)
	out:addString(currentRank and currentRank.name or "?")
	out:addU32(BaoState.getReputation(player))
	out:addU32(BaoState.getMarks(player))
	out:addU32(BaoState.getCounter(player, "marksEarned"))
	out:addU16(BaoLedger and BaoLedger.totalRanks(player) or 0)
	out:addU32(BaoState.getCounter(player, "hunts"))
	out:addU32(BaoState.getCounter(player, "bounties"))
	out:addByte(BaoState.getMaxSlots(player))
	-- Chapters HEARD and total, not the raw storyChapter key -- see
	-- BaoRank.chaptersHeard for why the raw value lies.
	local heard, totalChapters = BaoRank.chaptersHeard(player)
	out:addByte(heard)
	out:addByte(totalChapters)
	-- The chapter they are actually on, by title. Far more evocative on a brag
	-- screen than a bare count -- and it is the same fact their rank states,
	-- said the other way, which is exactly the point of leading with chapters.
	local nowChapter = BaoConfig.StoryChapters and BaoConfig.StoryChapters[BaoState.getStoryChapter(player)]
	out:addString(nowChapter and nowChapter.title or "")

	-- Trophy and unlock COUNTS rather than the list. The Profile is one screen
	-- a player screenshots; a checklist of every purchase would push the
	-- interesting numbers below the fold, which is the one thing it must not do.
	local outfits, outfitsTotal, mounts, mountsTotal = 0, 0, 0, 0
	for _, trophy in ipairs(BaoConfig.Trophies or {}) do
		local owned = BaoState.hasPurchased(player, trophy.key)
		-- Classified by key prefix, which is how bao_shop.lua names them.
		if trophy.key:sub(1, 7) == "outfit_" then
			outfitsTotal = outfitsTotal + 1
			if owned then outfits = outfits + 1 end
		elseif trophy.key:sub(1, 6) == "mount_" then
			mountsTotal = mountsTotal + 1
			if owned then mounts = mounts + 1 end
		end
	end

	local unlocks, unlocksTotal = 0, 0
	for key, item in pairs(BaoConfig.ShopItems) do
		-- Trophies are counted above; this is the functional unlocks only, so
		-- the two numbers never double-count each other.
		if item.oneTime and item.category ~= "prestige" then
			unlocksTotal = unlocksTotal + 1
			if BaoState.hasPurchased(player, key) then
				unlocks = unlocks + 1
			end
		end
	end

	out:addU16(outfits)
	out:addU16(outfitsTotal)
	out:addU16(mounts)
	out:addU16(mountsTotal)
	out:addU16(unlocks)
	out:addU16(unlocksTotal)

	-- Mastery per Danger tier. The World's End line is the one worth showing
	-- off, and it only reads as an achievement next to the others.
	local mastered, total = {}, {}
	for huntId, hunt in pairs(BaoConfig.Hunts) do
		total[hunt.tier] = (total[hunt.tier] or 0) + 1
		if BaoState.getMastery(player, huntId).timesCompleted > 0 then
			mastered[hunt.tier] = (mastered[hunt.tier] or 0) + 1
		end
	end

	local tiers = {}
	for tier in pairs(total) do
		tiers[#tiers + 1] = tier
	end
	table.sort(tiers, function(a, b)
		return (BaoConfig.TierOrder[a] or 99) < (BaoConfig.TierOrder[b] or 99)
	end)

	out:addByte(#tiers)
	for _, tier in ipairs(tiers) do
		out:addString(tier)
		out:addU16(mastered[tier] or 0)
		out:addU16(total[tier] or 0)
	end

	-- The headline unlocks. Each row says what it is, what it takes, and
	-- whether it is done -- because "0 of 8" told a player nothing about why
	-- they should care about any of it.
	local rankId = BaoState.getRankId(player)
	local rankName = {}
	for _, rank in ipairs(BaoConfig.Ranks) do
		rankName[rank.id] = rank.name
	end

	local milestones = {}
	for _, entry in ipairs(BaoConfig.MilestoneOrder or {}) do
		local label, note, need, done

		if entry.rank then
			-- A gate that opens on rank alone -- his trade lists.
			local needed = BaoConfig[entry.rank]
			label = entry.label
			note = entry.note or ""
			done = rankId >= needed
			need = string.format("Reach %s", rankName[needed] or ("rank " .. needed))
		else
			local item = BaoConfig.ShopItems[entry.key]
			if item then
				label = item.displayName
				note = item.description or ""
				done = BaoState.hasPurchased(player, entry.key)
				-- Rank first, then price: the rank is the part you cannot buy
				-- your way past, so it is the real gate.
				if item.minRank > 0 then
					need = string.format("%s, %d Marks", rankName[item.minRank] or ("rank " .. item.minRank), item.cost)
				else
					need = string.format("%d Marks", item.cost)
				end
			end
		end

		if label then
			milestones[#milestones + 1] = { label = label, note = note, need = need, done = done }
		end
	end

	out:addByte(#milestones)
	for _, m in ipairs(milestones) do
		out:addString(m.label)
		out:addString(m.note)
		out:addString(m.need)
		out:addByte(m.done and 1 or 0)
	end

	return out:sendToPlayer(player)
end

-- ─── Public entry point ─────────────────────────────────────────────────

BaoProtocol = {}

-- Called from Old Man Bao's dialogue — pushes a full state sync, then tells
-- the client to show/raise the journal window on the given tab.
function BaoProtocol.openJournal(player, tab)
	sendSyncFull(player)
	sendOpenWindow(player, tab)
end

-- ─── Request handlers ───────────────────────────────────────────────────
-- Every handler validates fully against BaoConfig/BaoState before mutating
-- anything — the client payload only ever supplies an identifier.

local function handleAcceptHunt(player, msg)
	local huntId = NetworkGuard.readString(msg, MAX_KEY_LENGTH)
	if not huntId then
		return
	end

	local hunt = BaoConfig.Hunts[huntId]
	if not hunt then
		sendError(player, "That hunt no longer exists.")
		return
	end
	if hunt.minRank > BaoState.getRankId(player) then
		sendError(player, "You are not yet ready for this hunt.")
		return
	end
	if not hunt.repeatable and BaoState.getMastery(player, huntId).timesCompleted > 0 then
		sendError(player, "You have already mastered this hunt.")
		return
	end
	if BaoState.getActiveSlotFor(player, huntId) then
		sendError(player, "That hunt is already active.")
		return
	end

	local slot = BaoState.findFreeSlot(player)
	if not slot then
		sendError(player, "All your hunt slots are full.")
		return
	end

	local ok, reason = BaoState.acceptHunt(player, slot, huntId)
	if not ok then
		sendError(player, "Could not accept that hunt (" .. tostring(reason) .. ").")
		return
	end

	sendSyncFull(player)
	sendStatus(player, string.format("Accepted: %s.", hunt.displayName))
end

local function handleAbandonHunt(player, msg)
	local slot = NetworkGuard.readByte(msg)
	if not slot or slot < 1 or slot > BaoState.getMaxSlots(player) then
		sendError(player, "Invalid hunt slot.")
		return
	end

	local slots = BaoState.getActiveHunts(player)
	local slotData = slots[slot]
	local hunt = slotData and BaoConfig.Hunts[slotData.huntId]

	local ok = BaoState.abandonHunt(player, slot)
	if not ok then
		sendError(player, "That slot is already empty.")
		return
	end

	sendSyncFull(player)
	sendStatus(player, string.format("Abandoned: %s.", hunt and hunt.displayName or "hunt"))
end

-- Defensive-only: bao_death.lua already grants the reward and clears the
-- slot synchronously, in the same kill event, the instant a hunt completes,
-- so a slot sitting in "completed, unclaimed" long enough for a player to
-- click a Claim button on it should never actually happen. Handled anyway
-- so nobody gets permanently stuck with an occupied slot if that assumption
-- is ever wrong.
local function handleClaimReward(player, msg)
	local slot = NetworkGuard.readByte(msg)
	if not slot or slot < 1 or slot > BaoState.getMaxSlots(player) then
		sendError(player, "Invalid hunt slot.")
		return
	end

	local slots = BaoState.getActiveHunts(player)
	local slotData = slots[slot]
	if not slotData or slotData.state ~= 2 then
		sendError(player, "Nothing to claim in that slot.")
		return
	end

	local isFirstMastery = BaoState.recordMastery(player, slotData.huntId)
	BaoReward.grant(player, slotData.huntId, isFirstMastery)
	BaoRank.checkRankUp(player)
	BaoState.clearSlot(player, slot)

	sendSyncFull(player)
end

local function handlePurchaseItem(player, msg)
	local itemKey = NetworkGuard.readString(msg, MAX_KEY_LENGTH)
	if not itemKey then
		return
	end
	local amount = msg:getU16()

	local item = BaoConfig.ShopItems[itemKey]
	if not item then
		sendError(player, "That item is not available.")
		return
	end

	-- (!) The stepper is a convenience, never the authority. A crafted packet
	-- can name any amount it likes, so the ceiling is enforced here and a
	-- non-scalable entry is pinned to exactly one regardless of what arrived.
	if item.scalable then
		amount = math.floor(tonumber(amount) or 0)
		if amount < 1 or amount > (item.maxUnits or 1) then
			sendError(player, "Bao will not sell you that many at once.")
			return
		end
	else
		amount = 1
	end
	if item.minRank > BaoState.getRankId(player) then
		sendError(player, "Your rank is not high enough for this.")
		return
	end
	if item.oneTime and BaoState.hasPurchased(player, itemKey) then
		sendError(player, "You already own this.")
		return
	end
	if item.requires and not BaoState.hasPurchased(player, item.requires) then
		sendError(player, string.format("Bao wants you to take "%s" first.",
			BaoConfig.ShopItems[item.requires].displayName))
		return
	end
	local totalCost = item.cost * amount
	if not BaoState.spendMarks(player, totalCost) then
		sendError(player, "Not enough Hunter Marks.")
		return
	end

	-- Two kinds of entry: a plain item grant, or a grant() that does something
	-- else entirely (a storage unlock, blessings, a hunt slot). Either way the
	-- Marks are already spent by this point, so EVERY failure path below has to
	-- refund -- a purchase that takes payment and delivers nothing is the worst
	-- bug this system could have.
	-- (!) Every refund below must return totalCost, not item.cost. On a scalable
	-- entry those differ by up to 200x, and refunding the unit price on a failed
	-- bulk purchase would quietly rob the player of nearly everything they paid.
	if item.grant then
		-- Amount is passed to every grant; the ones that are not scalable simply
		-- ignore the second argument.
		local ok, reason = item.grant(player, amount)
		if not ok then
			BaoState.addMarks(player, totalCost)
			sendError(player, reason or "Bao could not do that for you.")
			return
		end
	else
		local newItem = Game.createItem(item.itemId, (item.count or 1) * amount)
		if not newItem or player:addItemEx(newItem, false) ~= RETURNVALUE_NOERROR then
			BaoState.addMarks(player, totalCost) -- refund, purchase didn't go through
			sendError(player, "Not enough room in your inventory.")
			return
		end
	end

	if item.oneTime then
		BaoState.recordPurchase(player, itemKey)
	end

	sendSyncFull(player)
	sendShopData(player)
	sendStatus(player, amount > 1
		and string.format("Bought %dx %s for %d Marks.", amount, item.displayName, totalCost)
		or string.format("Bought %s for %d Marks.", item.displayName, totalCost))
end

local function handleTurnInBounty(player, msg)
	local key = NetworkGuard.readString(msg, MAX_KEY_LENGTH)
	if not key then
		return
	end

	local ok, resultOrReason = BaoBounty.turnIn(player, key)
	if not ok then
		sendError(player, resultOrReason)
		sendBountyData(player)
		return
	end

	sendSyncFull(player)
	sendBountyData(player)
	sendStatus(player, string.format("Order complete. +%d Marks, +%d Reputation.",
		resultOrReason.marks, resultOrReason.reputation))
end

local function handleBuyLedger(player, msg)
	local key = NetworkGuard.readString(msg, MAX_KEY_LENGTH)
	if not key then
		return
	end

	local ok, resultOrReason = BaoLedger.purchase(player, key)
	if not ok then
		sendError(player, resultOrReason)
		return
	end

	-- (!) Re-apply the native tracks NOW. The C++ side stores nothing, so a
	-- rank bought this second does nothing at all until the next login without
	-- this line.
	if BaoLedger.applyNative then
		BaoLedger.applyNative(player)
	end

	sendSyncFull(player)
	sendLedgerData(player)
	sendStatus(player, string.format("%s is now rank %d. %d Marks spent.",
		BaoConfig.Ledger[key].displayName, resultOrReason.rank, resultOrReason.cost))
end

local requestHandler = PacketHandler(OPCODE_BAO_REQUEST)

function requestHandler.onReceive(player, msg)
	local action = NetworkGuard.readByte(msg)
	if not action then
		return
	end

	-- Keyed per action rather than globally, so opening the shop tab does not
	-- swallow the sync that is about to follow it.
	if not NetworkGuard.cooldown(player, "bao:" .. action, ACTION_COOLDOWN) then
		return
	end

	if action == ACTION_REQUEST_SYNC then
		sendSyncFull(player)
	elseif action == ACTION_ACCEPT_HUNT then
		handleAcceptHunt(player, msg)
	elseif action == ACTION_ABANDON_HUNT then
		handleAbandonHunt(player, msg)
	elseif action == ACTION_CLAIM_REWARD then
		handleClaimReward(player, msg)
	elseif action == ACTION_PURCHASE_ITEM then
		handlePurchaseItem(player, msg)
	elseif action == ACTION_REQUEST_SHOP then
		sendShopData(player)
	elseif action == ACTION_REQUEST_BOUNTY then
		sendBountyData(player)
	elseif action == ACTION_TURNIN_BOUNTY then
		handleTurnInBounty(player, msg)
	elseif action == ACTION_REQUEST_LEDGER then
		sendLedgerData(player)
	elseif action == ACTION_BUY_LEDGER then
		handleBuyLedger(player, msg)
	elseif action == ACTION_REQUEST_PROFILE then
		sendProfileData(player)
	end
end

requestHandler:register()
