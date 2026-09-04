-- Old Man Bao — kill-tracking layer. Credits every player who meaningfully
-- damaged a monster relevant to an active Bao hunt (not just the killer),
-- resolving summons to their owner, then advances hunt progress via
-- BaoState. Mirrors the structure of custom_bestiary.lua's CustomBestiaryKill
-- event closely on purpose — same crediting model, same registration idiom.

-- Milestones worth interrupting someone for. Everything else is reported in
-- the ephemeral status line instead.
local MILESTONES = { 0.25, 0.50, 0.75, 0.90 }

local function getPlayerFromKiller(killer)
	if not killer then
		return nil
	end
	if killer:isPlayer() then
		return killer
	end

	local master = killer:getMaster()
	if master and master:isPlayer() then
		return master
	end
	return nil
end

local function addKillPlayer(players, player)
	if player then
		players[player:getGuid()] = player
	end
end

-- Builds the credited-player set for this kill. The killer and
-- mostDamageKiller are always credited (they're already known to have
-- contributed meaningfully). Every other unique attacker in the damage map
-- only gets credited if their contribution meets BaoConfig.MinDamageShare
-- of the monster's max health.
local function getKillPlayers(creature, killer, mostDamageKiller)
	local players = {}
	addKillPlayer(players, getPlayerFromKiller(killer))
	addKillPlayer(players, getPlayerFromKiller(mostDamageKiller))

	if creature and creature.getDamageMap then
		local maxHealth = creature:getMaxHealth()
		local minShare = BaoConfig.MinDamageShare or 0

		for creatureId, entry in pairs(creature:getDamageMap()) do
			local candidate = Player(creatureId)
			if candidate then
				local guid = candidate:getGuid()
				-- Already credited via killer/mostDamageKiller (checked by guid,
				-- not object identity, since separate userdata pushes for the
				-- same player aren't guaranteed to be Lua-== to one another) —
				-- skip the ratio check for those.
				if players[guid] then
					-- no-op, already credited
				elseif maxHealth and maxHealth > 0 then
					local total = entry and entry.total or 0
					if (total / maxHealth) >= minShare then
						addKillPlayer(players, candidate)
					end
				end
			end
		end
	end
	return players
end

-- Did this kill push the hunt across one of the milestone fractions?
-- Compares the two progress values against the thresholds rather than testing
-- equality, so a family hunt advancing several points at once still reports
-- the milestone it stepped over.
local function crossedMilestone(previous, current, required)
	if required <= 0 then
		return nil
	end
	for _, fraction in ipairs(MILESTONES) do
		local mark = math.floor(required * fraction)
		if previous < mark and current >= mark then
			return math.floor(fraction * 100)
		end
	end
	return nil
end

-- The feedback that was missing entirely.
--
-- Before this, bao_death sent NOTHING until a hunt completed — a player killed
-- 4,999 Vexclaw in total silence and could only see a number by opening the
-- journal. A progress bar that moves is most of the reward in a system like
-- this; the payout at the end is the bonus.
--
-- One combined line per player per death rather than one per hunt: with three
-- active slots and a monster that counts toward more than one of them, separate
-- status messages would simply overwrite each other and the player would see
-- whichever happened to land last.
local function reportProgress(player, advanced)
	if #advanced == 0 then
		return
	end

	local parts = {}
	for _, entry in ipairs(advanced) do
		parts[#parts + 1] = string.format("%s %d/%d", entry.name, entry.progress, entry.required)
	end
	-- MESSAGE_STATUS_SMALL is the ephemeral status line, not the console — it
	-- replaces itself rather than accumulating, which is what makes per-kill
	-- reporting reasonable at all. Same choice task_hunting.lua makes.
	player:sendTextMessage(MESSAGE_STATUS_SMALL, table.concat(parts, "   |   "))

	for _, entry in ipairs(advanced) do
		if entry.milestone then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
				"Old Man Bao's hunt \"%s\" is %d%% done - %d of %d.",
				entry.name, entry.milestone, entry.progress, entry.required))
		end
	end
end

local baoDeath = CreatureEvent("BaoDeath")

function baoDeath.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	if not BaoLookup or not BaoState then
		return true
	end

	-- A summon's own corpse should never be treated as a top-level kill —
	-- the owner is credited through the damage map / killer resolution above.
	if creature and creature:getMaster() then
		return true
	end

	local huntIds = BaoLookup.getHuntsFor(creature:getName())
	if not huntIds then
		return true
	end

	local players = getKillPlayers(creature, killer, mostDamageKiller)
	if next(players) == nil then
		return true
	end

	local monsterName = creature:getName()
	for _, player in pairs(players) do
		local advanced = {}

		for _, huntId in ipairs(huntIds) do
			local weight = BaoLookup.getWeight(huntId, monsterName)
			if weight and weight > 0 then
				local result = BaoState.addHuntProgress(player, huntId, weight)
				if result then
					local hunt = BaoConfig.Hunts[huntId]
					local displayName = hunt and hunt.displayName or huntId

					if result.justCompleted then
						local isFirstMastery = BaoState.recordMastery(player, huntId)
						BaoState.bumpCounter(player, "hunts")
						local grant = BaoReward.grant(player, huntId, isFirstMastery)
						BaoRank.checkRankUp(player)
						BaoState.clearSlot(player, result.slot)
						if grant then
							print(string.format("[Bao] %s completed hunt '%s' (first=%s) - xp=%d reputation=%d marks=%d rareTier=%s",
								player:getName(), huntId, tostring(isFirstMastery),
								grant.xp, grant.reputation, grant.marks, tostring(grant.rareTier)))
						end
					else
						advanced[#advanced + 1] = {
							name = displayName,
							progress = result.progress,
							required = result.requiredCount,
							milestone = crossedMilestone(result.previousProgress, result.progress, result.requiredCount),
						}
					end
				end
			end
		end

		reportProgress(player, advanced)
	end
	return true
end

baoDeath:register()
