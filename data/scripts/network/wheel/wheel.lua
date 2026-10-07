local wheelSystemConfigKey = configKeys and configKeys.WHEEL_SYSTEM_ENABLED or WHEEL_SYSTEM_ENABLED
if wheelSystemConfigKey and not configManager.getBoolean(wheelSystemConfigKey) then
	return
end

-- Wheel of Destiny -- server side.
--
-- Rebuilt 2026-09-11 for the plain-words overhaul (docs/wheel/06-ux-overhaul.md,
-- 07-numbers.md, and P2 of 08-execution-plan.md):
--
--   * Every number lives in data/lib/wheel/wheel_tables.lua (WheelTables).
--     The client's text table is generated from the same file, so the window
--     says what this script does.
--   * Gems left the wheel for their own system (docs/gems/00-design.md). The
--     Gem Atelier storage, the 0xE7 gem actions and the Fragment Workshop are
--     gone, and the window packet always carries zero gems.
--   * The twelve old gem-socket slices are Extra Points slices ("pathboost"):
--     when full they add points toward their own colour's big reward.
--   * The big-reward stars give real damage and healing (STAR_BONUS).
--   * Damage taken is a flat percent per point (MITIGATION_PER_POINT).
--   * A character who cannot use the wheel yet can still LOOK at it: the
--     window opens read-only and says what unlocks it.

if not WheelTables then
	print("[Wheel] WheelTables is missing (data/lib/wheel/wheel_tables.lua) -- the wheel is off")
	return
end
local W = WheelTables

local OPCODE_WHEEL_OPEN = 0x61
local OPCODE_WHEEL_SAVE = 0x62
local OPCODE_WHEEL_WINDOW = 0x5F
local OPCODE_RESOURCE_BALANCE = 0xEE
-- Extended opcode, JSON: the facts the window needs that the native packet has
-- no field for -- the level, Wheel Resets owned, and what still locks the
-- wheel. 145 used to carry a "wheel skills" payload no client module read.
local EXT_OPCODE_WHEEL_INFO = 0x91

local WHEEL_SLOT_COUNT = W.SLOT_COUNT
local WHEEL_REQUIRE_PROMOTION = true
local WHEEL_CONDITION_SUBID = 86061

local RESOURCE_BANK = 0
local RESOURCE_INVENTORY = 1

local PROMOTION_SCROLLS_BY_NAME = {}
for itemId, scroll in pairs(W.PROMOTION_SCROLLS) do
	scroll.itemId = itemId
	PROMOTION_SCROLLS_BY_NAME[scroll.name] = scroll
end

-- Flat damage reduction applied per player, so the teardown undoes exactly
-- what was added. Dropped on logout.
local WHEEL_APPLIED_MITIGATION = {}

local function supportsCustomNetwork(player)
	return player and player.isUsingOtClient and player:isUsingOtClient()
end

local function wheelKV(player)
	return player:kv():scoped("wheel")
end

local function wheelAppliedKV(player)
	return wheelKV(player):scoped("applied")
end

local function getWheelPlayerKey(player)
	if player.getGuid then
		return player:getGuid()
	end
	return player:getId()
end

local function scrollKV(player)
	return wheelKV(player):scoped("scrolls")
end

-- === Wheel Reset ============================================================
--
-- Adding points is free. Taking SAVED points back out costs a Wheel Reset,
-- bought in the store for 200 Bp Coins (owner, 2026-09-09) -- the store's
-- delivery handler writes the token here, this consumes it.
--
-- (!) The offer type and this KV scope are still `respec`: renaming them would
-- orphan every token already bought and unspent.
--
-- The check is deliberately "did any slot go DOWN", not "did the total go
-- down": moving fifty points from one slot to another costs a token even
-- though the total is unchanged, and it is exactly the thing being charged
-- for. One token covers a save that empties every slot at once, which is what
-- makes the same product serve as a full reset.
local function respecKV(player)
	return wheelKV(player):scoped("respec")
end

local function countRespecTokens(player)
	return tonumber(respecKV(player):get("tokens")) or 0
end

local function consumeRespecToken(player)
	local tokens = countRespecTokens(player)
	if tokens <= 0 then
		return false
	end
	respecKV(player):set("tokens", tokens - 1)
	respecKV(player):set("usedAt", os.time())
	return true
end

local function lowersAnySlot(stored, points)
	for slot = 1, WHEEL_SLOT_COUNT do
		if (points[slot] or 0) < (stored[slot] or 0) then
			return true
		end
	end
	return false
end

local function clampU16(value)
	value = math.floor(tonumber(value) or 0)
	if value < 0 then
		return 0
	end
	if value > 0xFFFF then
		return 0xFFFF
	end
	return value
end

-- === Bao's promotion scrolls =================================================

local function getUnlockedScrolls(player)
	local store = scrollKV(player)
	local unlocked = {}
	for itemId, scroll in pairs(W.PROMOTION_SCROLLS) do
		if store:get(scroll.name) == true then
			unlocked[#unlocked + 1] = {
				itemId = itemId,
				name = scroll.name,
				points = scroll.points,
			}
		end
	end

	table.sort(unlocked, function(a, b)
		return a.itemId < b.itemId
	end)
	return unlocked
end

local function unlockWheelScroll(player, scrollName)
	local scroll = PROMOTION_SCROLLS_BY_NAME[scrollName]
	if not scroll then
		return false
	end

	local store = scrollKV(player)
	if store:get(scroll.name) == true then
		return false
	end

	store:set(scroll.name, true)
	return true
end

function Player.wheelUnlockScroll(self, scrollName)
	return unlockWheelScroll(self, scrollName)
end

-- === Points and the unlock ===================================================

local function getWheelVocation(player)
	local vocation = player:getVocation()
	local clientId = vocation and vocation:getClientId() or 0
	if clientId == 1 or clientId == 11 then
		return 1
	elseif clientId == 2 or clientId == 12 then
		return 2
	elseif clientId == 3 or clientId == 13 then
		return 3
	elseif clientId == 4 or clientId == 14 then
		return 4
	elseif clientId == 5 or clientId == 15 then
		return 5
	end
	return 0
end

local function getWheelPoints(player)
	return clampU16(math.min(W.MAX_ALLOCATABLE_POINTS, W.levelPoints(player:getLevel())))
end

local function getWheelExtraPoints(player)
	local total = 0
	for _, scroll in ipairs(getUnlockedScrolls(player)) do
		total = total + scroll.points
	end
	return clampU16(math.min(total, math.max(0, W.MAX_ALLOCATABLE_POINTS - getWheelPoints(player))))
end

local function getWheelTotalPoints(player)
	return clampU16(math.min(W.MAX_ALLOCATABLE_POINTS, getWheelPoints(player) + getWheelExtraPoints(player)))
end

local function hasWheelPremium(player)
	return not player.isPremium or player:isPremium()
end

local function isWheelPromoted(player)
	if not WHEEL_REQUIRE_PROMOTION then
		return true
	end

	if not player.isPromoted then
		return false
	end

	local ok, promoted = pcall(function()
		return player:isPromoted()
	end)
	return ok and promoted == true
end

-- Old Man Bao sells access to the Wheel (BaoConfig.ShopItems.wheel_access,
-- data/lib/bao/bao_shop.lua), writing this storage key.
--
-- Fails OPEN if Bao is not loaded at all, so a server running without the Bao
-- system does not silently lose the Wheel along with it.
local BAO_WHEEL_ACCESS_KEY = 990601

local function hasBaoWheelAccess(player)
	if not BaoConfig then
		return true
	end
	return player:getStorageValue(BAO_WHEEL_ACCESS_KEY) == 1
end

-- What still stops this character from CHANGING their wheel, in the order the
-- window lists them. Empty means nothing does. Looking is never locked for a
-- character with a vocation.
local function wheelLocks(player)
	local locks = {}
	if player:getLevel() < W.MIN_LEVEL then
		locks[#locks + 1] = "level"
	end
	if not isWheelPromoted(player) then
		locks[#locks + 1] = "promotion"
	end
	if not hasWheelPremium(player) then
		locks[#locks + 1] = "premium"
	end
	if not hasBaoWheelAccess(player) then
		locks[#locks + 1] = "bao"
	end
	return locks
end

-- Every entry point that CHANGES the wheel funnels through this, so Bao's
-- access purchase, the level gate and Premium cannot be walked around.
local function canOpenWheel(player)
	return getWheelVocation(player) > 0 and #wheelLocks(player) == 0
end

local function emptyPoints()
	local points = {}
	for slot = 1, WHEEL_SLOT_COUNT do
		points[slot] = 0
	end
	return points
end

local function normalizePointTable(points)
	local normalized = emptyPoints()
	if type(points) ~= "table" then
		return normalized
	end

	for slot = 1, WHEEL_SLOT_COUNT do
		normalized[slot] = clampU16(points[slot])
	end
	return normalized
end

-- === Colours, Extra Points and the big rewards ==============================

local function calculateDomainPoints(points)
	local domains = { 0, 0, 0, 0 }
	for slot = 1, WHEEL_SLOT_COUNT do
		local domain = W.SLOT_DOMAINS[slot]
		domains[domain] = domains[domain] + (points[slot] or 0)
	end
	return domains
end

local function buildRevelationStages(domainPoints)
	local stages = {}
	for name, domain in pairs(W.REVELATION_DOMAIN) do
		stages[name] = W.stageOf(domainPoints[domain] or 0)
	end
	return stages
end

-- A colour's total, the Extra Points inside it, and the big-reward stages that
-- follow. A FULL pathboost slice adds its `boost` to its own colour -- the
-- same machinery the old Revelation Mastery gem used, now fed by the wheel.
local function computeStages(points)
	local domainPoints = calculateDomainPoints(points)
	local boosts = { 0, 0, 0, 0 }
	for slot = 1, WHEEL_SLOT_COUNT do
		local bonus = W.SLOT_BONUSES[slot]
		if bonus and bonus.conviction == "pathboost" and (points[slot] or 0) >= W.SLOT_MAX_POINTS[slot] then
			local domain = W.SLOT_DOMAINS[slot]
			boosts[domain] = boosts[domain] + (bonus.boost or 0)
		end
	end
	for domain = 1, 4 do
		domainPoints[domain] = domainPoints[domain] + boosts[domain]
	end
	return domainPoints, buildRevelationStages(domainPoints), boosts
end

-- The stars' damage-and-healing percent: STAR_BONUS[stage] per colour, summed.
local function starPercent(domainPoints)
	local total = 0
	for domain = 1, 4 do
		total = total + (W.STAR_BONUS[W.stageOf(domainPoints[domain] or 0)] or 0)
	end
	return total
end

local function loadProfile(player)
	return {
		points = normalizePointTable(wheelKV(player):get("points")),
	}
end

-- Writes the profile and the stages the C++ Player:revelationStageWOD reads.
-- applyWheelBonuses runs straight afterwards and rewrites the same two keys,
-- so the pair is idempotent in either order.
local function saveProfile(player, points)
	local domainPoints, stages = computeStages(points)
	local usedPoints = 0
	for slot = 1, WHEEL_SLOT_COUNT do
		usedPoints = usedPoints + (points[slot] or 0)
	end

	local store = wheelKV(player)
	store:set("version", 2)
	store:set("points", points)
	store:set("domainPoints", domainPoints)
	store:set("revelationStages", stages)
	store:set("usedPoints", usedPoints)
	store:set("vocation", getWheelVocation(player))
	store:set("conditionSubId", WHEEL_CONDITION_SUBID)
	store:set("savedAt", os.time())
end

-- === What the wheel gives ====================================================

local function addBonus(bonuses, key, value)
	if value and value ~= 0 then
		bonuses[key] = (bonuses[key] or 0) + value
	end
end

local function addWheelSpellGrade(bonuses, conviction)
	bonuses.spellGrades[conviction] = (bonuses.spellGrades[conviction] or 0) + 1
end

-- Adds one grade ladder's augments, up to `grade`. Handles both shapes: a
-- numeric AUGMENT_TYPE the engine understands, and a `key = "..."` entry that
-- only the Lua side channel can act on.
local function addSpellGrades(bonuses, spellName, grades, grade)
	local reached = math.min(grade, #grades)
	bonuses.spellGradesByName[spellName] = reached

	for index = 1, reached do
		for _, augment in ipairs(grades[index]) do
			bonuses.spellAugments[#bonuses.spellAugments + 1] = {
				spellName = spellName,
				augmentType = augment[1],
				augmentKey = augment.key,
				value = augment.key and augment.value or augment[2],
			}
		end
	end
end

local function buildWheelSpellAugments(bonuses, vocationId)
	local customSpells = W.CUSTOM_SPELL_BONUSES[vocationId] or {}
	for conviction, grade in pairs(bonuses.spellGrades) do
		for _, custom in ipairs(customSpells[conviction] or {}) do
			addSpellGrades(bonuses, custom.name, custom.grades, grade)
		end
	end

	local vocationSpells = W.SPELL_BONUSES[vocationId] or {}
	for conviction, grade in pairs(bonuses.spellGrades) do
		local spell = vocationSpells[conviction]
		if spell then
			-- Keyed by NAME as well as by conviction: the conviction key is
			-- meaningless to a spell script, which knows only what it is
			-- called.
			for _, spellName in ipairs(spell.names) do
				addSpellGrades(bonuses, spellName, spell.grades, grade)
			end
		end
	end
end

local function calculateWheelBonuses(player, points)
	local vocationId = getWheelVocation(player)
	local bonuses = {
		health = 0,
		mana = 0,
		capacity = 0,
		magic = 0,
		melee = 0,
		distance = 0,
		fist = 0,
		lifeLeech = 0,
		manaLeech = 0,
		mitigation = 0,
		spellGrades = {},
		spellGradesByName = {},
		spellAugments = {},
		-- Which of the two vocation-special slices (slot 1 and slot 36) are
		-- complete. The perks themselves live in wheel_perks.lua.
		specials = {},
		-- Counters for the two shared rewards: the rarity crossover wants all
		-- four 50-point starter slices, Hunter's Discipline all four skill
		-- slices.
		starterSlices = 0,
		skillConvictions = 0,
	}

	if vocationId == 0 then
		return bonuses
	end

	for slot = 1, WHEEL_SLOT_COUNT do
		local invested = points[slot] or 0
		local slotBonus = W.SLOT_BONUSES[slot]
		if invested > 0 and slotBonus then
			local dedication = slotBonus.dedication
			if dedication == "health" then
				addBonus(bonuses, "health", invested * (W.DEDICATION_VALUES.health[vocationId] or 0))
			elseif dedication == "mana" then
				addBonus(bonuses, "mana", invested * (W.DEDICATION_VALUES.mana[vocationId] or 0))
			elseif dedication == "capacity" then
				addBonus(bonuses, "capacity", invested * (W.DEDICATION_VALUES.capacity[vocationId] or 0))
			elseif dedication == "lifemana" then
				addBonus(bonuses, "health", invested * (W.DEDICATION_VALUES.lifemana.health[vocationId] or 0))
				addBonus(bonuses, "mana", invested * (W.DEDICATION_VALUES.lifemana.mana[vocationId] or 0))
			elseif dedication == "mitigation" then
				bonuses.mitigation = bonuses.mitigation + invested * W.MITIGATION_PER_POINT
			end
		end

		if invested >= (W.SLOT_MAX_POINTS[slot] or 0) and slotBonus then
			local conviction = slotBonus.conviction

			-- The four cheapest slices on the wheel, one per colour.
			if (W.SLOT_MAX_POINTS[slot] or 0) == 50 then
				bonuses.starterSlices = bonuses.starterSlices + 1
			end

			if conviction == "lifeleech" then
				addBonus(bonuses, "lifeLeech", W.CONVICTION_VALUES.lifeleech)
			elseif conviction == "manaleech" then
				addBonus(bonuses, "manaLeech", W.CONVICTION_VALUES.manaleech)
			elseif conviction == "skill" then
				bonuses.skillConvictions = bonuses.skillConvictions + 1
				if vocationId == 1 then
					addBonus(bonuses, "melee", W.CONVICTION_VALUES.skill)
				elseif vocationId == 2 then
					addBonus(bonuses, "distance", W.CONVICTION_VALUES.skill)
				elseif vocationId == 3 or vocationId == 4 then
					addBonus(bonuses, "magic", W.CONVICTION_VALUES.skill)
				elseif vocationId == 5 then
					addBonus(bonuses, "fist", W.CONVICTION_VALUES.skill)
				end
			elseif conviction == "special_1" or conviction == "special_2" then
				-- Recorded, not applied: every special rides the perk tick in
				-- wheel_perks.lua.
				bonuses.specials[conviction] = true
			elseif conviction == "pathboost" then
				-- Counted by computeStages, toward the colour's big reward.
			elseif W.SPELL_BONUSES[vocationId] and W.SPELL_BONUSES[vocationId][conviction] then
				addWheelSpellGrade(bonuses, conviction)
			end
		end
	end

	buildWheelSpellAugments(bonuses, vocationId)
	return bonuses
end

-- Damage taken, FLAT (07-numbers.md §4B). The number the window shows is the
-- number added -- the old multiplier path needed a binary that was never
-- installed, so the two only agreed by accident.
local function removeAppliedMitigation(player)
	local key = getWheelPlayerKey(player)
	local applied = WHEEL_APPLIED_MITIGATION[key]
	if applied and applied ~= 0 and player.addMitigation then
		player:addMitigation(-applied)
	end
	WHEEL_APPLIED_MITIGATION[key] = nil
end

local function removeWheelBonuses(player)
	player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, WHEEL_CONDITION_SUBID, true)
	if player.clearWheelSpellAugments then
		player:clearWheelSpellAugments()
	end
	removeAppliedMitigation(player)

	local appliedStore = wheelAppliedKV(player)
	appliedStore:set("conditionSubId", WHEEL_CONDITION_SUBID)
	appliedStore:set("conditionApplied", false)
	appliedStore:set("mitigation", 0)
	appliedStore:set("updatedAt", os.time())
end

local function setConditionBonus(condition, parameter, value)
	if value and value ~= 0 then
		condition:setParameter(parameter, value)
		return true
	end
	return false
end

-- === The window ==============================================================

-- The extra facts the window needs, as JSON on the extended opcode. Sent after
-- every window packet.
local function sendWheelInfo(player)
	if not supportsCustomNetwork(player) or not player.sendExtendedOpcode then
		return false
	end

	local locks = wheelLocks(player)
	return player:sendExtendedOpcode(EXT_OPCODE_WHEEL_INFO, json.encode({
		type = "info",
		level = player:getLevel(),
		minLevel = W.MIN_LEVEL,
		pointsPerLevel = W.POINTS_PER_LEVEL,
		levelPoints = getWheelPoints(player),
		scrollPoints = getWheelExtraPoints(player),
		resets = countRespecTokens(player),
		locks = table.concat(locks, ","),
		canEdit = #locks == 0 and getWheelVocation(player) > 0,
	}))
end

-- Kept for its two callers (the inventory-update callback and the proficiency
-- window). The "wheel skills" payload it used to send was never read by any
-- client module, and resending wheel facts on every inventory change would be
-- pure traffic, so this does nothing now.
function Player.wheelSendSkillStats(self)
	return false
end

local function applyWheelBonuses(player)
	removeWheelBonuses(player)

	local profile = loadProfile(player)
	local vocationId = getWheelVocation(player)
	local bonuses = calculateWheelBonuses(player, profile.points)

	-- Rewritten on every apply, not only on save: the tables can change under
	-- a saved build (a new STAGE_AT, a moved boost), and the C++
	-- Player:revelationStageWOD reads this key.
	local domainPoints, stages = computeStages(profile.points)
	local store = wheelKV(player)
	store:set("domainPoints", domainPoints)
	store:set("revelationStages", stages)

	local spellGrades = bonuses.spellGrades
	local spellGradesByName = bonuses.spellGradesByName
	local spellAugments = bonuses.spellAugments
	bonuses.spellGrades = nil
	bonuses.spellGradesByName = nil
	bonuses.spellAugments = nil
	-- (!) The KV map type only accepts STRING keys; a numeric one makes the
	-- whole set() fail and return false rather than raising. The three tables
	-- above carry numeric keys, hence the strip before the write.
	store:set("bonusStats", bonuses)
	bonuses.spellGrades = spellGrades
	bonuses.spellGradesByName = spellGradesByName
	bonuses.spellAugments = spellAugments

	local condition = Condition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT)
	condition:setParameter(CONDITION_PARAM_SUBID, WHEEL_CONDITION_SUBID)
	condition:setParameter(CONDITION_PARAM_TICKS, -1)

	local hasConditionBonus = false
	hasConditionBonus = setConditionBonus(condition, CONDITION_PARAM_STAT_MAXHITPOINTS, bonuses.health) or hasConditionBonus
	hasConditionBonus = setConditionBonus(condition, CONDITION_PARAM_STAT_MAXMANAPOINTS, bonuses.mana) or hasConditionBonus
	hasConditionBonus = setConditionBonus(condition, CONDITION_PARAM_STAT_CAPACITY, bonuses.capacity) or hasConditionBonus
	hasConditionBonus = setConditionBonus(condition, CONDITION_PARAM_STAT_MAGICPOINTS, bonuses.magic) or hasConditionBonus
	hasConditionBonus = setConditionBonus(condition, CONDITION_PARAM_SKILL_MELEE, bonuses.melee) or hasConditionBonus
	hasConditionBonus = setConditionBonus(condition, CONDITION_PARAM_SKILL_DISTANCE, bonuses.distance) or hasConditionBonus
	hasConditionBonus = setConditionBonus(condition, CONDITION_PARAM_SKILL_FIST, bonuses.fist) or hasConditionBonus
	hasConditionBonus = setConditionBonus(condition, CONDITION_PARAM_SPECIALSKILL_LIFELEECHAMOUNT, bonuses.lifeLeech) or hasConditionBonus
	hasConditionBonus = setConditionBonus(condition, CONDITION_PARAM_SPECIALSKILL_MANALEECHAMOUNT, bonuses.manaLeech) or hasConditionBonus

	if hasConditionBonus then
		player:addCondition(condition)
	end

	if player.addWheelSpellAugment then
		for _, augment in ipairs(bonuses.spellAugments) do
			-- Only the numeric AUGMENT_TYPE entries mean anything to C++.
			-- Custom `key = "..."` augments are Lua-only; they still go into
			-- the side channel below.
			if augment.augmentType then
				player:addWheelSpellAugment(augment.spellName, augment.augmentType, augment.value)
			end
		end
	end

	local key = getWheelPlayerKey(player)

	-- The same list again, into the Lua mirror. C++ takes what it understands;
	-- this is what spell scripts read for the rest. See wheel_spell_bonus.lua.
	WheelSpellBonus.set(key, bonuses.spellAugments, bonuses.spellGradesByName)

	-- The permanent rewards: the rarity crossover (all four centre slices),
	-- Hunter's Discipline (all four skill slices) and the big-reward stars'
	-- damage and healing.
	local permanent = {}
	if bonuses.starterSlices >= #WheelPerks.STARTER_SLICES then
		for bonusKey, value in pairs(WheelPerks.STARTER_BONUS[vocationId] or {}) do
			permanent[bonusKey] = value
		end
	end
	if bonuses.skillConvictions >= 4 then
		permanent.bountyLoot = WheelPerks.HUNTERS_DISCIPLINE_BONUS
	end
	local stars = starPercent(domainPoints)
	if stars > 0 then
		permanent.starPercent = stars
	end
	-- Keyed by creature id, not guid: every WheelPerks table is, because the
	-- combat hooks that read them only ever have a Creature in hand.
	WheelPerks.setPermanent(player:getId(), permanent)

	-- Vocation specials and big-reward perks. applySpecials tears down whatever
	-- was running first, so this is safe on every apply -- which is what makes
	-- a save that REMOVES a perk actually turn it off.
	WheelPerks.applySpecials(player, vocationId, bonuses.specials, stages)

	if bonuses.mitigation ~= 0 and player.addMitigation then
		player:addMitigation(bonuses.mitigation)
		WHEEL_APPLIED_MITIGATION[key] = bonuses.mitigation
	end

	local appliedStore = wheelAppliedKV(player)
	appliedStore:set("conditionSubId", WHEEL_CONDITION_SUBID)
	appliedStore:set("conditionApplied", hasConditionBonus)
	appliedStore:set("mitigation", bonuses.mitigation or 0)
	appliedStore:set("starPercent", stars)
	appliedStore:set("updatedAt", os.time())

	player:reloadData()
	return bonuses
end

function Player.wheelApplyBonuses(self)
	return applyWheelBonuses(self)
end

-- Player-facing text follows docs/plain-english.md.
local function validatePoints(player, points)
	local total = 0
	for slot = 1, WHEEL_SLOT_COUNT do
		local value = points[slot] or 0
		if value > W.SLOT_MAX_POINTS[slot] then
			return false, "This build is not valid. Nothing was saved."
		end
		total = total + value
	end

	if total > getWheelTotalPoints(player) then
		return false, "You do not have enough points. Nothing was saved."
	end

	for slot = 1, WHEEL_SLOT_COUNT do
		local value = points[slot] or 0
		if value > 0 and W.SLOT_MAX_POINTS[slot] ~= 50 then
			local prerequisites = W.SLOT_PREREQUISITES[slot]
			if prerequisites and #prerequisites > 0 then
				local unlocked = false
				for _, prerequisite in ipairs(prerequisites) do
					if (points[prerequisite] or 0) >= W.SLOT_MAX_POINTS[prerequisite] then
						unlocked = true
						break
					end
				end
				if not unlocked then
					return false, "A slice is not open. Nothing was saved."
				end
			end
		end
	end

	return true
end

local function sendResourceBalance(player, resourceType, value)
	if not supportsCustomNetwork(player) then
		return false
	end

	local out = NetworkMessage(player)
	out:addByte(OPCODE_RESOURCE_BALANCE)
	out:addByte(resourceType)
	out:addU64(math.max(0, tonumber(value) or 0))
	return out:sendToPlayer(player)
end

local function sendWheelWindow(player, ownerId)
	if not supportsCustomNetwork(player) then
		return false
	end

	ownerId = tonumber(ownerId) or player:getId()
	local vocationId = getWheelVocation(player)
	-- Anyone with a vocation may LOOK. Changing is a separate question,
	-- answered by changeState below and enforced again at save.
	local canView = vocationId > 0
	sendResourceBalance(player, RESOURCE_BANK, player:getBankBalance())
	sendResourceBalance(player, RESOURCE_INVENTORY, player:getMoney())

	local out = NetworkMessage(player)
	out:addByte(OPCODE_WHEEL_WINDOW)
	out:addU32(ownerId)
	out:addByte(canView and 1 or 0)
	if not canView then
		return out:sendToPlayer(player)
	end

	local profile = loadProfile(player)
	local unlockedScrolls = getUnlockedScrolls(player)
	local canEdit = ownerId == player:getId() and canOpenWheel(player)
	out:addByte(canEdit and 1 or 0)
	out:addByte(vocationId)
	out:addU16(getWheelPoints(player))
	out:addU16(getWheelExtraPoints(player))

	for slot = 1, WHEEL_SLOT_COUNT do
		out:addU16(profile.points[slot] or 0)
	end

	out:addU16(#unlockedScrolls)
	for _, scroll in ipairs(unlockedScrolls) do
		out:addU16(scroll.itemId)
	end

	-- The rest of the layout is fixed by the client's own
	-- ProtocolGame::parseOpenWheelWindow (protocolgameparse.cpp:2895). Gems
	-- left the wheel, so it is always: four empty sockets, no gems, and two
	-- empty upgrade ledgers.
	out:addByte(4)
	for _ = 1, 4 do
		out:addU16(0)
	end
	out:addU16(0)
	out:addByte(0)
	out:addByte(0)

	local sent = out:sendToPlayer(player)
	sendWheelInfo(player)
	return sent
end

-- The save packet still ends with four gem flags (sendApplyWheelPoints,
-- protocolgamesend.cpp:1262). Read past them; gems are not the wheel's any
-- more. Returns false only for a packet cut short in the middle of one.
local function skipSaveGems(msg)
	for _ = 1, 4 do
		if msg:len() - msg:tell() < 1 then
			return true
		end
		if msg:getByte() ~= 0 then
			if msg:len() - msg:tell() < 2 then
				return false
			end
			msg:getU16()
		end
	end
	return true
end

local openHandler = PacketHandler(OPCODE_WHEEL_OPEN)

function openHandler.onReceive(player, msg)
	if not NetworkGuard.cooldown(player, "wheel-open", 300) then
		return
	end
	if msg:len() - msg:tell() < 4 then
		return
	end

	sendWheelWindow(player, msg:getU32())
end

openHandler:register()

local saveHandler = PacketHandler(OPCODE_WHEEL_SAVE)

function saveHandler.onReceive(player, msg)
	-- A save rewrites eight KV keys and rebuilds every wheel condition on the
	-- player; throttled so a crafted client cannot do that 25 times a second
	-- (security audit 2026-10-05).
	if not NetworkGuard.cooldown(player, "wheel-save", 500) then
		return
	end
	if msg:len() - msg:tell() < WHEEL_SLOT_COUNT * 2 then
		return
	end

	if not canOpenWheel(player) then
		sendWheelWindow(player, player:getId())
		return
	end

	local points = {}
	for slot = 1, WHEEL_SLOT_COUNT do
		points[slot] = msg:getU16()
	end

	if not skipSaveGems(msg) then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "Something went wrong. Nothing was saved.")
		sendWheelWindow(player, player:getId())
		return
	end

	local valid, reason = validatePoints(player, points)
	if not valid then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, reason)
		sendWheelWindow(player, player:getId())
		return
	end

	-- Wheel Reset gate. Compared against what is actually stored, so a client
	-- that re-sends the same layout never spends a token.
	local stored = normalizePointTable(wheelKV(player):get("points"))
	if lowersAnySlot(stored, points) and not consumeRespecToken(player) then
		player:sendTextMessage(MESSAGE_STATUS_SMALL,
			"You need a Talent Compass Reset to remove saved points. Buy one in the Store.")
		sendWheelWindow(player, player:getId())
		return
	end

	saveProfile(player, points)
	applyWheelBonuses(player)
	sendWheelWindow(player, player:getId())
end

saveHandler:register()

local wheelLoginEvent = CreatureEvent("WheelOfDestinyLogin")

function wheelLoginEvent.onLogin(player)
	player:registerEvent("WheelOfDestinyLogout")
	-- Marked Prey's kill payout. The two health-change events the wheel owns
	-- (Gift of Life, Unbreakable) are deliberately NOT registered here -- they
	-- have to run after the rarity pass, so rarity_login.lua registers them in
	-- the one place that order is guaranteed.
	player:registerEvent("WheelMarkedPrey")
	applyWheelBonuses(player)
	return true
end

wheelLoginEvent:register()

local wheelLogoutEvent = CreatureEvent("WheelOfDestinyLogout")

function wheelLogoutEvent.onLogout(player)
	local key = getWheelPlayerKey(player)
	WHEEL_APPLIED_MITIGATION[key] = nil
	WheelSpellBonus.clear(key)
	-- Perk state is keyed by creature id, not guid, and the tick loop must be
	-- stopped explicitly or it keeps firing against a dead Player() handle
	-- once per second forever.
	WheelPerks.removeSpecials(player)
	WheelPerks.onLogout(player)
	WheelPerks.clearCreature(player:getId())
	return true
end

wheelLogoutEvent:register()
