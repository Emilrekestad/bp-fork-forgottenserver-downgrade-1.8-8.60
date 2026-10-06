if staminaEvents == nil then
    staminaEvents = {}
end

ExerciseWeaponsTable = {
	[28540] = { skill = SKILL_SWORD },
	[28552] = { skill = SKILL_SWORD },
	[35279] = { skill = SKILL_SWORD },
	[35285] = { skill = SKILL_SWORD },
	[28553] = { skill = SKILL_AXE },
	[28541] = { skill = SKILL_AXE },
	[35280] = { skill = SKILL_AXE },
	[35286] = { skill = SKILL_AXE },
	[28554] = { skill = SKILL_CLUB },
	[28542] = { skill = SKILL_CLUB },
	[35281] = { skill = SKILL_CLUB },
	[35287] = { skill = SKILL_CLUB },
	[44064] = { skill = SKILL_SHIELD },
	[44065] = { skill = SKILL_SHIELD },
	[44066] = { skill = SKILL_SHIELD },
	[44067] = { skill = SKILL_SHIELD },
	-- ROD
	[28544] = { skill = SKILL_MAGLEVEL, effect = CONST_ANI_SMALLICE, allowFarUse = true },
	[28556] = { skill = SKILL_MAGLEVEL, effect = CONST_ANI_SMALLICE, allowFarUse = true },
	[35283] = { skill = SKILL_MAGLEVEL, effect = CONST_ANI_SMALLICE, allowFarUse = true },
	[35289] = { skill = SKILL_MAGLEVEL, effect = CONST_ANI_SMALLICE, allowFarUse = true },
	-- RANGE
	[28543] = { skill = SKILL_DISTANCE, effect = CONST_ANI_SIMPLEARROW, allowFarUse = true },
	[28555] = { skill = SKILL_DISTANCE, effect = CONST_ANI_SIMPLEARROW, allowFarUse = true },
	[35282] = { skill = SKILL_DISTANCE, effect = CONST_ANI_SIMPLEARROW, allowFarUse = true },
	[35288] = { skill = SKILL_DISTANCE, effect = CONST_ANI_SIMPLEARROW, allowFarUse = true },
	-- WAND
	[28545] = { skill = SKILL_MAGLEVEL, effect = CONST_ANI_FIRE, allowFarUse = true },
	[28557] = { skill = SKILL_MAGLEVEL, effect = CONST_ANI_FIRE, allowFarUse = true },
	[35284] = { skill = SKILL_MAGLEVEL, effect = CONST_ANI_FIRE, allowFarUse = true },
	[35290] = { skill = SKILL_MAGLEVEL, effect = CONST_ANI_FIRE, allowFarUse = true },
	-- FIST
	[50292] = { skill = SKILL_FIST, effect = CONST_ANI_WHIRLWINDAXE },
	[50293] = { skill = SKILL_FIST, effect = CONST_ANI_WHIRLWINDAXE },
	[50294] = { skill = SKILL_FIST, effect = CONST_ANI_WHIRLWINDAXE },
	[50295] = { skill = SKILL_FIST, effect = CONST_ANI_WHIRLWINDAXE },
}

FreeDummies = {5787, 5788, 28558, 28559, 28560, 28561, 28562, 28563, 28564, 28565}
HouseDummies = {5787, 5788, 28558, 28559, 28560, 28561, 28562, 28563, 28564, 28565}
MaxAllowedOnADummy = configManager.getNumber(configKeys.MAX_ALLOWED_ON_A_DUMMY)

-- The three dummies the Store sells -- Demon, Ferumbras and Monk -- plus the
-- twin id each one becomes when a player rotates it (items.xml `rotateto`:
-- 28559<->28560, 28561<->28562, 28563<->28564). Both ids of a pair belong
-- here, or turning a dummy around would quietly cost its bonus.
--
-- Everything else trains at the city rate, including the public dummies
-- (28558, 28565, 5787, 5788) placed around the towns.
StoreDummies = {28559, 28560, 28561, 28562, 28563, 28564}

-- What one training tick is worth.
--
-- (!) These are per-tick TOTALS, not multipliers, because addSkillTries and
-- addManaSpent take integers: the old `7 * 1.5` was 10.5 and was cast down to
-- 10 on every tick, so a 5% edge expressed as a multiplier would have landed
-- on 11 -- a 10% buff, not 5%. The city numbers below are exactly what every
-- dummy gives today (10 tries, 750 mana) and the Store's three sit 5% above
-- them. ExerciseEvent carries the fraction between ticks instead of losing it.
DummySkillTriesCity = 10
DummySkillTriesStore = 10.5
DummyManaSpentCity = 750
DummyManaSpentStore = 787.5

local magicLevelRate = configManager.getNumber(configKeys.RATE_MAGIC)
local skillLevelRate = configManager.getNumber(configKeys.RATE_SKILL)

local function isItemOwnedByPlayer(item, player)
	local parent = item:getParent()
	while parent do
		if parent.isPlayer and parent:isPlayer() then
			return parent:getId() == player:getId()
		end
		if not parent.getParent then
			return false
		end
		parent = parent:getParent()
	end
	return false
end

function LeaveTraining(playerId)
	local training = onExerciseTraining[playerId]
	if not training then
		return
	end

	if training.event then
		stopEvent(training.event)
	end

	training.weapon = nil
	onExerciseTraining[playerId] = nil
end

function ExerciseEvent(playerId, tilePosition, weaponId, dummyId)
	local player = Player(playerId)
	if not player then
		LeaveTraining(playerId)
		return false
	end

	local training = onExerciseTraining[playerId]
	if not training then
		return false
	end

	if training.ownerGuid ~= player:getGuid() then
		LeaveTraining(playerId)
		return false
	end

	local dummyTile = Tile(tilePosition)
	if not dummyTile or not dummyTile:getItemById(dummyId) then
		player:sendTextMessage(
			MESSAGE_EVENT_ADVANCE,
			"Someone has moved the dummy, the training has stopped."
		)
		LeaveTraining(playerId)
		return false
	end

	local playerTile = player:getTile()
	if not playerTile then
		LeaveTraining(playerId)
		return false
	end

	if not playerTile:hasFlag(TILESTATE_PROTECTIONZONE) and not staminaEvents[playerId] then
		player:sendTextMessage(
			MESSAGE_EVENT_ADVANCE,
			"You are no longer in a protection zone, the training has stopped."
		)
		LeaveTraining(playerId)
		return false
	end

	local weapon = training.weapon
	if not weapon or not weapon:isItem() or weapon:getId() ~= weaponId then
		player:sendTextMessage(
			MESSAGE_EVENT_ADVANCE,
			"The training weapon is no longer available, the training has stopped."
		)
		LeaveTraining(playerId)
		return false
	end

	if not isItemOwnedByPlayer(weapon, player) then
		player:sendTextMessage(
			MESSAGE_EVENT_ADVANCE,
			"The training weapon is no longer yours, the training has stopped."
		)
		LeaveTraining(playerId)
		return false
	end

	if not weapon:hasAttribute(ITEM_ATTRIBUTE_CHARGES) then
		player:sendTextMessage(
			MESSAGE_EVENT_ADVANCE,
			"The selected item is not a training weapon, the training has stopped."
		)
		LeaveTraining(playerId)
		return false
	end

	local weaponCharges = weapon:getAttribute(ITEM_ATTRIBUTE_CHARGES)
	if not weaponCharges or weaponCharges <= 0 then
		weapon:remove(1)
		player:sendTextMessage(
			MESSAGE_EVENT_ADVANCE,
			"Your training weapon has disappeared."
		)
		LeaveTraining(playerId)
		return false
	end

	local weaponConfig = ExerciseWeaponsTable[weaponId]
	if not weaponConfig then
		LeaveTraining(playerId)
		return false
	end

	-- The Store's three dummies are 5% better than every other one. The
	-- fraction that leaves (10.5 tries, 787.5 mana) is kept in the training
	-- session and spent on a later tick, because both engine calls take
	-- integers and would drop it -- which is where the old 10.5 lost its half
	-- every single tick.
	local onStoreDummy = table.contains(StoreDummies, dummyId)

	if weaponConfig.skill == SKILL_MAGLEVEL then
		training.manaCarry = (training.manaCarry or 0) +
			(onStoreDummy and DummyManaSpentStore or DummyManaSpentCity)
		local whole = math.floor(training.manaCarry)
		training.manaCarry = training.manaCarry - whole
		if whole > 0 then
			player:addManaSpent(whole)
		end
	else
		training.skillCarry = (training.skillCarry or 0) +
			(onStoreDummy and DummySkillTriesStore or DummySkillTriesCity)
		local whole = math.floor(training.skillCarry)
		training.skillCarry = training.skillCarry - whole
		if whole > 0 then
			player:addSkillTries(weaponConfig.skill, whole)
		end
	end

	weapon:setAttribute(ITEM_ATTRIBUTE_CHARGES, weaponCharges - 1)
	tilePosition:sendMagicEffect(CONST_ME_HITAREA)

	if weaponConfig.effect then
		player:getPosition():sendDistanceEffect(tilePosition, weaponConfig.effect)
	end

	if weapon:getAttribute(ITEM_ATTRIBUTE_CHARGES) <= 0 then
		weapon:remove(1)
		player:sendTextMessage(
			MESSAGE_EVENT_ADVANCE,
			"Your training weapon has disappeared."
		)
		LeaveTraining(playerId)
		return false
	end

	local currentTraining = onExerciseTraining[playerId]
	if not currentTraining or currentTraining ~= training then
		return false
	end

	local vocation = player:getVocation()
	currentTraining.event = addEvent(
		ExerciseEvent,
		vocation:getAttackSpeed() /
			configManager.getNumber(configKeys.RATE_EXERCISE_TRAINING_SPEED),
		playerId,
		tilePosition,
		weaponId,
		dummyId
	)

	return true
end

if onExerciseTraining == nil then
	onExerciseTraining = {}
end
