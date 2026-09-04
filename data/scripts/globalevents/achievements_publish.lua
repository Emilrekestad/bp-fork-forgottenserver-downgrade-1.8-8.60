-- Achievements: keep the database projection current.
--
-- Startup does three things in order, and the order matters: the catalogue has
-- to exist before summaries can be totalled from it, and summaries have to be
-- right before rarity is quoted against them.
--
-- The rebuild is unconditional rather than gated on a "needs repair" flag. It
-- is two statements over a table that only grows with real unlocks, and it is
-- what makes the whole mirror self-healing -- any drift, from a crash mid-write
-- to a hand-edited storage, is gone by the next boot.

local achievementsStartup = GlobalEvent("AchievementsStartup")

function achievementsStartup.onStartup()
	AchievementsDB.publishCatalogue()
	AchievementsDB.rebuildAllSummaries()

	local population = AchievementsDB.refreshRarity()
	local totals = AchievementsDB.totals()
	print(string.format(">> Achievements: %d achievements (%d points), rarity across %d characters",
		totals.count, totals.points, population))

	return true
end

achievementsStartup:register()

-- Rarity drifts as people play. Hourly is the right cadence: the figure is a
-- talking point rather than a live counter, and recounting it is a single
-- grouped scan that has no business running more often than that.
local achievementsRarity = GlobalEvent("AchievementsRarity")

function achievementsRarity.onThink(interval)
	AchievementsDB.refreshRarity()
	return true
end

achievementsRarity:interval(60 * 60 * 1000)
achievementsRarity:register()
