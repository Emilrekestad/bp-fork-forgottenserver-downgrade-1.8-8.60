-- Old Man Bao — rank-up evaluation. Called after a reward grant (from
-- bao_death.lua, right after BaoReward.grant), since that's the only place
-- reputation or mastery count change. Per the design, ranking up requires
-- BOTH the reputation threshold AND the mastery-count threshold of a rank to
-- be met simultaneously — reputation alone is not sufficient.

BaoRank = {}

-- Shared with bao_reward.lua (a hunt's storyChapterUnlock field takes this
-- same path) so the narrative beat is announced identically regardless of
-- whether the chapter advanced via rank-up or via a specific hunt.
function BaoRank.announceStoryChapter(player, chapter)
	local entry = BaoConfig.StoryChapters and BaoConfig.StoryChapters[chapter]
	if not entry then
		return
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"Old Man Bao: \"%s\"\n\n%s", entry.title, entry.text
	))
end

-- How many of Bao's story chapters this player has heard, and how many exist.
--
-- (!) storyChapter is a raw KEY, not a position. The defined chapters are
-- 1, 2, 3, 5, 6, 8, 9, 10 — the gaps are deliberate (see bao_story.lua) and
-- the roman numeral in each title is independent flavour. Showing the raw
-- value as "Chapter N" told a Beast Slayer they were on chapter 5 when the one
-- they had just read was titled "Chapter IV". Counting the chapters at or
-- below their key is the honest answer to "how far into his story am I".
function BaoRank.chaptersHeard(player)
	local current = BaoState.getStoryChapter(player)
	local heard, total = 0, 0
	for chapter in pairs(BaoConfig.StoryChapters or {}) do
		total = total + 1
		if chapter <= current then
			heard = heard + 1
		end
	end
	return heard, total
end

-- The highest rank this player currently QUALIFIES for above their own, or
-- nil. Pure: asks nothing of the world and changes nothing, so it is safe to
-- call from a greeting, a packet, or a tick.
function BaoRank.pendingRank(player)
	local currentRankId = BaoState.getRankId(player)
	local reputation = BaoState.getReputation(player)
	local masteryCount = BaoState.getMasteryCount(player)

	local newRank = nil
	for _, rank in ipairs(BaoConfig.Ranks) do
		if rank.id > currentRankId
				and reputation >= rank.repThreshold
				and masteryCount >= rank.masteriesRequired then
			-- Always the HIGHEST qualifying rank, so a burst of reputation from a
			-- single grant can carry several ranks at once rather than making the
			-- player walk back for each one.
			if not newRank or rank.id > newRank.id then
				newRank = rank
			end
		end
	end
	return newRank
end

-- Called wherever reputation or mastery changes. Does NOT promote any more --
-- it only tells the player that Bao has something to say, and only the first
-- time for a given rank so it does not nag on every kill.
--
-- The promotion itself happens in data/npc/scripts/Old Man Bao.lua, in his
-- voice, standing in front of him. That is deliberate: it is the biggest
-- moment the system has, and it used to be spent on a line of text in a
-- hunting ground while the NPC sat unused.
function BaoRank.checkRankUp(player)
	local pending = BaoRank.pendingRank(player)
	if not pending then
		return nil
	end

	local notified = player:kv():scoped("bao"):scoped("rank")
	if notified:get("announced") == pending.id then
		return pending
	end
	notified:set("announced", pending.id)

	-- Says WHERE. Promotions happen in person now, and a player who has never
	-- sought him out has no way to act on "go and see him" alone.
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
		"You have done enough to earn a word with Old Man Bao. He keeps to his home -- go and find him.")
	return pending
end

-- The real promotion. Only ever called from Bao's own dialogue.
--
-- Re-checks eligibility rather than trusting the caller: the NPC decides WHEN
-- to offer, this decides whether it is actually true.
function BaoRank.promote(player)
	local newRank = BaoRank.pendingRank(player)
	if not newRank then
		return nil
	end

	local currentRankId = BaoState.getRankId(player)
	BaoState.setRank(player, newRank.id)
	player:kv():scoped("bao"):scoped("rank"):set("announced", 0)

	-- Walk every chapter between the old rank and the new one rather than
	-- jumping straight to the new rank's. Because pendingRank deliberately
	-- lands on the HIGHEST qualifying rank, a single large grant can skip
	-- ranks — and setStoryChapter only ever moves forward, so any chapter
	-- passed over that way was silently unreachable forever. Bao's storyline
	-- is the payoff the whole system builds toward; losing beats of it to a
	-- lucky grant is the one thing it cannot afford.
	local chapters = {}
	for _, rank in ipairs(BaoConfig.Ranks) do
		if rank.id > currentRankId and rank.id <= newRank.id then
			if BaoState.setStoryChapter(player, rank.storyChapter) then
				chapters[#chapters + 1] = rank.storyChapter
			end
		end
	end

	print(string.format("[Bao] %s promoted to %s", player:getName(), newRank.name))
	return newRank, chapters
end

-- ─── Startup validation ─────────────────────────────────────────────────

-- Mastery count can only ever be drawn from hunts the player has already
-- unlocked, so a rank whose masteriesRequired exceeds the number of hunts
-- available at the rank below it is mathematically unreachable — and takes
-- every tier, story chapter, shop tier and reward pool above it down with it.
--
-- This shipped: rank 5 asked for 45 against 44 reachable hunts and rank 6 for
-- 65 against 55, which locked away 17 hunts and four story chapters. Nothing
-- errored, nothing logged, and it was invisible until someone played far
-- enough to hit the wall. One loop at startup is cheap insurance against
-- repeating that the next time a tier is added or a threshold retuned.
function BaoRank.validateLadder()
	local problems = 0
	for _, rank in ipairs(BaoConfig.Ranks) do
		if rank.id > 0 then
			local available = 0
			for _, hunt in pairs(BaoConfig.Hunts) do
				if (hunt.minRank or 0) <= (rank.id - 1) then
					available = available + 1
				end
			end
			if rank.masteriesRequired > available then
				problems = problems + 1
				print(string.format(
					"[Bao] UNREACHABLE RANK: '%s' (id %d) requires %d masteries but only %d hunts are unlocked below it. " ..
					"Lower masteriesRequired or add hunts at minRank <= %d.",
					rank.name, rank.id, rank.masteriesRequired, available, rank.id - 1))
			end
		end
	end
	return problems
end

BaoRank.validateLadder()
