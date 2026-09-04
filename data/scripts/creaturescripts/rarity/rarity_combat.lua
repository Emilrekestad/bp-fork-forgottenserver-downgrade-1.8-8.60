-- Item Rarity system — combat-modifier engine. Ported from a third-party
-- download (author "Leo32") onto this fork. Pulls attributes from rolled
-- items that affect combat and applies the damage/leech/crit/stun/multishot
-- changes. Registered as two CreatureEvents (RarityHealthChange /
-- RarityManaChange) — see rarity_login.lua / rarity_spawn.lua for the
-- registerEvent() wiring this fork requires (nothing auto-registers
-- creature events here, confirmed against src/creature.cpp).
--
-- Fixes applied during the port (this fork's API differs from what the
-- original download assumed):
--   1. item:getDescription() does not exist on Item in this fork (only on
--      ItemType, which has no per-instance awareness) -- every occurrence
--      below reads item:getSpecialDescription() instead, which is the real
--      binding that returns the injected [Stat: +N] bracket text.
--   2. `.uid`/`.itemid` direct field access (e.g. `attacker.uid`) is not a
--      valid binding on this fork (only `.itemid`/`.uid` -style legacy
--      fields some other forks expose) -- every occurrence is replaced with
--      the real accessor, `:getId()`.
--   3. doTargetCombatCondition did not exist anywhere in this codebase --
--      added as a small local helper matching the two call sites' actual
--      usage (always called with full Creature objects, never raw ids).
--   4. stunTarget's first parameter was named `itemdesc` in the original
--      while callers passed a creature id -- and the function body read an
--      undefined global `stuncreature` instead of that parameter, meaning
--      Stun Chance always silently failed (`Creature(nil)` -> `return
--      false` on every call). Fixed to actually take the passed-in id.
--   5. `stunAnimation` (capital A) was called via addEvent while the
--      function itself was defined as `stunanimation` (lowercase) -- a
--      case-sensitive Lua global mismatch that would have errored on first
--      stun proc. Unified on one spelling.
--
-- (!) Real stun (CONDITION_STUN) doesn't exist in vanilla TFS and would need
-- a C++ patch; this keeps the original's CONDITION_MUTED (silence)
-- placeholder rather than attempting real stun -- see the rarity plan's
-- "what we can't change" section.

-- Crits
local critmodifier = 2 -- Critical hits do 200% damage
local criteffect = CONST_ME_EXPLOSIONAREA

-- Batching manaleech/lifeleech gains so AOE spells give a single lump sum
local manaleechBatched = {}
local lifeleechBatched = {}

-- Hold the Line (stats[39]): [playerId] = {x=, y=, z=, since=os.time()} --
-- tracks how long the wearer has stood on the same tile so applyHoldTheLine
-- can ramp the reduction up over time and reset it instantly on movement.
local holdTheLineState = {}
local HOLD_THE_LINE_RAMP_SECONDS = 10 -- TEMPORARY placeholder -- balance later

-- Pin Down (stats[49]): crossbows only. [targetId] = expiry time-- lets
-- clearPinDown tell a stale scheduled unlock (from an earlier, shorter
-- proc) apart from the current one after a re-trigger refreshes the
-- timer, the same refresh-safety shape Hold the Line/Spell Echo use
-- above/below. See applyPinDown/clearPinDown near stunTarget.
local pinDownExpiry = {}
local PIN_DOWN_DURATION_SECONDS = 3 -- TEMPORARY placeholder -- balance later

-- Chain Heal (stats[50]): rods only. chainHealing guards against the jumped
-- heal re-triggering its own Chain Heal roll on itself (same shape as
-- spellEchoing/thornReflecting below). Range/power are placeholders --
-- balance later.
local chainHealing = {}
local CHAIN_HEAL_RANGE = 6 -- tiles
local CHAIN_HEAL_POWER_PERCENT = 50 -- % of the main heal the jump copies

-- Juggernaut (stats[51]): body armor, Knight/Paladin. Caps how many
-- simultaneous attackers count toward the reduction, and caps the total
-- reduction itself so a swarmed player never approaches full immunity --
-- both placeholders, balance later.
local JUGGERNAUT_ATTACKER_CAP = 5
local JUGGERNAUT_MAX_REDUCTION_PERCENT = 80

-- Cleave (stats[53]): two-handed Knight weapons. Extra-target damage share
-- -- placeholder, balance later.
local CLEAVE_DAMAGE_PERCENT = 50

-- Guardian's Pact (stats[54]): Mage/Paladin helmets. How much of a proc'd
-- hit gets redirected into a heal for the nearest injured ally, and how far
-- away that ally can be -- placeholders, balance later.
local GUARDIANS_PACT_REDIRECT_PERCENT = 50
local GUARDIANS_PACT_RANGE = 6

-- Spell Echo (stats[41]): [attackerId] = true while a delayed echo hit is in
-- flight, so the echo's own onHealthChange pass can't itself roll a new
-- echo (would otherwise chain indefinitely). Same guard shape as Rebirth's
-- `resolving` table in rarity_rebirth.lua.
local spellEchoing = {}
local SPELL_ECHO_TRIGGER_CHANCE = 20 -- TEMPORARY placeholder, % per hit -- balance later

-- What slots should be checked for elemental damage, crit, multi shot, mana leech, spelldamage etc
local checkweaponslots = {
	CONST_SLOT_LEFT,
	CONST_SLOT_RIGHT,
	CONST_SLOT_NECKLACE,
	CONST_SLOT_HEAD,
	CONST_SLOT_RING
}

-- What slots should be checked for resistances (all of them, shields can be in either hand)
local checkallslots = {
	CONST_SLOT_LEFT,
	CONST_SLOT_RIGHT,
	CONST_SLOT_HEAD,
	CONST_SLOT_NECKLACE,
	CONST_SLOT_ARMOR,
	CONST_SLOT_LEGS,
	CONST_SLOT_FEET,
	CONST_SLOT_RING
}

-- Match the animation to the ammunition type -- rebuilt against this
-- fork's real items.xml. The old table below was ~75% wrong: most ids
-- pointed at nonexistent/RESERVED SPRITE ranges or completely unrelated
-- real items (id 6529 = "pair of soft boots", 18435 = "picks", 18304 =
-- "dead bride of night", 2389 = "small blue pillow", 2399 = "round red
-- pillow", 2410 = "luxurious couch"...), so Multi Shot silently never
-- fired for almost any ammo. Rebuilt by extracting every item in
-- items.xml with `weaponType="ammunition"` and cross-checking its real
-- id against its own declared `shootType` attribute -- not typed by hand
-- from memory, to avoid repeating the exact same class of mistake.
--
-- Deliberately excludes spear/throwing star/throwing knife/snowball/
-- glooth spear/leaf star/royal star -- confirmed via items.xml that
-- EVERY one of them declares `slot="hand"` (they're the weapon itself,
-- thrown directly), never `slot="ammo"` like real ammunition (bolt/
-- arrow) does. Since Multi Shot's own trigger is gated on
-- `attacker:getSlotItem(CONST_SLOT_AMMO) ~= nil`, those items can never
-- occupy that slot -- an entry for them here would just be dead weight,
-- not a fix. (Separate, NOT fixed here: Multi Shot can still be *rolled*
-- onto those same items, since they share WEAPON_DISTANCE with bows/
-- crossbows in rarity_stats.lua's pool -- meaning a Multi Shot roll on a
-- spear or throwing star is permanently dead the moment it's rolled,
-- since it can never pass the ammo-slot check above. Flagged, not
-- addressed -- would need a design call on whether to exclude those
-- items from the Multi Shot pool entirely or add a second trigger path
-- for hand-thrown weapons.)
--
-- id 15792 "crystal bolt" intentionally shares CONST_ANI_VORTEXBOLT --
-- that's its own declared shootType in items.xml, not a copy/paste slip.
-- ids 25758/35902 are both real, separately-obtainable "spectral bolt"
-- items (same shootType); both included so neither silently falls
-- through depending on which one actually drops.
local animation = {
	[3446] = CONST_ANI_BOLT,
	[3450] = CONST_ANI_POWERBOLT,
	[6528] = CONST_ANI_INFERNALBOLT,
	[7363] = CONST_ANI_PIERCINGBOLT,
	[14252] = CONST_ANI_VORTEXBOLT,
	[15792] = CONST_ANI_VORTEXBOLT, -- crystal bolt
	[16141] = CONST_ANI_PRISMATICBOLT,
	[16142] = CONST_ANI_DRILLBOLT,
	[25758] = CONST_ANI_SPECTRALBOLT,
	[35902] = CONST_ANI_SPECTRALBOLT,

	[3447] = CONST_ANI_ARROW,
	[21470] = CONST_ANI_ARROW, -- simple arrow
	[3448] = CONST_ANI_POISONARROW,
	[3449] = CONST_ANI_BURSTARROW,
	[7365] = CONST_ANI_ONYXARROW,
	[7364] = CONST_ANI_SNIPERARROW,
	[761] = CONST_ANI_FLASHARROW,
	[763] = CONST_ANI_FLAMMINGARROW,
	[762] = CONST_ANI_SHIVERARROW,
	[774] = CONST_ANI_EARTHARROW,
	[14251] = CONST_ANI_TARSALARROW,
	[16143] = CONST_ANI_ENVENOMEDARROW,
	[15793] = CONST_ANI_CRYSTALLINEARROW,
	[35901] = CONST_ANI_DIAMONDARROW,
}

-- Used for shuffling targets, so random ones are chosen (multi-shot)
local function shuffle(t)
	local rand = math.random
	local iterations = #t
	local j
	for i = iterations, 2, -1 do
		j = rand(i)
		t[i], t[j] = t[j], t[i]
	end
end

-- Applies a condition to a target with a magic effect -- this fork has no
-- native doTargetCombatCondition; both call sites below always pass full
-- Creature objects (never raw ids), so this stays a thin, direct wrapper.
local function doTargetCombatCondition(cid, target, condition, effect)
	if not target then
		return false
	end
	target:addCondition(condition)
	if effect and effect > 0 then
		target:getPosition():sendMagicEffect(effect)
	end
	return true
end

-- Mana leech (individual amounts)
local function manaLeechConcat(attackerid, manatoadd)
	if not manaleechBatched[attackerid] then
		manaleechBatched[attackerid] = {}
	end
	if not manaleechBatched[attackerid].ReadyToCommit then
		addEvent(processManaleechBatch, 5, attackerid)
		manaleechBatched[attackerid].ReadyToCommit = true
	end
	manaleechBatched[attackerid].Mana = (manaleechBatched[attackerid].Mana or manatoadd) + ((10 / 100) * math.floor(manatoadd))
end

-- Mana leech (batched, makes AOE spells give a single bulk amount)
function processManaleechBatch(attackerid)
	if Creature(attackerid) then
		local player = Creature(attackerid)
		player:addMana(manaleechBatched[attackerid].Mana)
	end
	manaleechBatched[attackerid] = nil
end

-- Life leech (individual amounts)
local function lifeLeechConcat(attackerid, lifetoadd)
	if not lifeleechBatched[attackerid] then
		lifeleechBatched[attackerid] = {}
	end
	if not lifeleechBatched[attackerid].ReadyToCommit then
		addEvent(processLifeleechBatch, 5, attackerid)
		lifeleechBatched[attackerid].ReadyToCommit = true
	end
	lifeleechBatched[attackerid].Life = (lifeleechBatched[attackerid].Life or lifetoadd) + ((10 / 100) * math.floor(lifetoadd))
end

-- Life leech (batched, makes AOE spells give a single bulk amount)
function processLifeleechBatch(attackerid)
	if Creature(attackerid) then
		local player = Creature(attackerid)
		player:addHealth(lifeleechBatched[attackerid].Life)
	end
	lifeleechBatched[attackerid] = nil
end

-- Check player slots and get resistance information
local function getResistences(resistanceitemdesc, resistances, attackerisplayer)
	-- Magic Resistance (stats[44], legs/non-spellbook shields): one
	-- consolidated roll that folds into every elemental type's Custom
	-- resistance EXCEPT Physical, same pooling mechanism the 6 separate
	-- named Resistance stats already use -- deliberately reuses this loop
	-- instead of a parallel one, so it stacks with Fire/Ice/Energy/Earth/
	-- Death Resistance exactly like two named resistances would.
	local magicResistPercent = tonumber(string.match(resistanceitemdesc, "[%[%(]Magic Resistance: %+(%d+)%%[%]%)]")) or 0

	for _, v in pairs(resistances) do
		if string.match(resistanceitemdesc, "[%[%(]" .. v.String .. " Resistance") then
			v.Custom = v.Custom + (tonumber(string.match(resistanceitemdesc, '[%[%(]' .. v.String .. ' Resistance: %+(%d+)%%[%]%)]')) or 0)
		end
		if magicResistPercent > 0 and v.String ~= "Physical" then
			v.Custom = v.Custom + magicResistPercent
		end
		if attackerisplayer then
			local nativeResist = v.String:lower()
			if string.match(resistanceitemdesc, nativeResist .. " ([+-]%d+)%%") then
				local nativePercent = string.match(resistanceitemdesc, nativeResist .. " ([+-]%d+)%%")
				v.Native = v.Native + nativePercent
			end
		end
	end
end

-- Stun animation loop
function stunanimation(stunnedcreature, stunnedpos, counter)
	if counter ~= 0 and Creature(stunnedcreature) then
		stunnedpos:sendMagicEffect(CONST_ME_STUN)
		counter = counter - 1
		addEvent(stunanimation, 500, stunnedcreature, stunnedpos, counter)
	end
end

-- Stun condition (real CONDITION_STUN isn't available on vanilla TFS without
-- a C++ patch -- this keeps the original's CONDITION_MUTED/silence
-- placeholder rather than pretending to have real stun)
local function stunTarget(stuncreatureId, stunduration)
	local target = Creature(stuncreatureId)
	if not target then
		return false
	end
	if target:isPlayer() then
		stunduration = stunduration / 2
	end

	local mute = Condition(CONDITION_MUTED)
	mute:setParameter(CONDITION_PARAM_TICKS, stunduration)
	target:addCondition(mute)

	addEvent(stunanimation, 0, target:getId(), target:getPosition(), (stunduration / 1000) * 2)
end

-- Pin Down (stats[49]): crossbows only, real movement-lock CC -- distinct
-- from Stun Chance above, which is a silence (CONDITION_MUTED), not a root.
-- Works on players and monsters alike via the generic Creature:
-- setMovementBlocked() binding.
--
-- clearPinDown checks pinDownExpiry before unlocking: if a second Pin Down
-- proc landed after this addEvent was scheduled, expiry was pushed forward
-- and this (now-stale) callback must NOT unlock early -- it just no-ops,
-- and the later callback (scheduled by the refresh) does the real unlock.
-- Also refuses to touch a player currently held in RarityRebirth.downed --
-- that system holds its own setMovementBlocked(true) open for an unrelated
-- reason (see rarity_rebirth.lua), and Pin Down clearing it early would
-- let a downed player walk while still supposed to be down.
local function clearPinDown(targetId)
	local expiry = pinDownExpiry[targetId]
	if not expiry or os.time() < expiry then
		return
	end
	pinDownExpiry[targetId] = nil

	local target = Creature(targetId)
	if not target then
		return
	end
	if target:isPlayer() and RarityRebirth.downed[targetId] then
		return
	end
	target:setMovementBlocked(false)
end

local function applyPinDown(attacker, target, pinChance)
	if attacker == target or math.random(1, 100) > pinChance then
		return
	end
	if target:isPlayer() and RarityRebirth.downed[target:getId()] then
		return
	end

	local targetId = target:getId()
	target:setMovementBlocked(true)
	target:getPosition():sendMagicEffect(CONST_ME_GROUNDSHAKER)
	pinDownExpiry[targetId] = os.time() + PIN_DOWN_DURATION_SECONDS
	addEvent(clearPinDown, PIN_DOWN_DURATION_SECONDS * 1000, targetId)
end

-- Input damage, its type, and creature immunities/resistances - output reduced damage
local function filterResistance(damage, damageType, immunity, resistance)
	if resistance[damageType] then
		local resistancePercent = (100 - resistance[damageType])
		damage = (resistancePercent / 100) * damage
	end
	if bit.band(immunity, damageType) == damageType then
		damage = 0
	end
	return math.floor(damage)
end

-- Roll elemental damage
local function elementalDmg(weaponDescription, elementType, extraAnimation, creature, resistances, primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll)
	local dmgmin, dmgmax = string.match(weaponDescription, '[%[%(]Enhanced ' .. resistances[elementType].String .. ' Damage: (%d+)%-(%d+)[%]%)]')
	local eleDmg = (math.random(dmgmin, dmgmax))

	if creature:isMonster() then
		local resistance = creature:getType():getElementList()
		local immunity = creature:getType():getCombatImmunities()
		eleDmg = filterResistance(eleDmg, elementType, immunity, resistance)
	elseif creature:isPlayer() then
		eleDmg = eleDmg / 2
		if (resistances[elementType].Native + resistances[elementType].Custom ~= 0) then
			local resistancePercent = (100 - (resistances[elementType].Custom + resistances[elementType].Native))
			eleDmg = (resistancePercent / 100) * eleDmg
		end
	end

	if eleDmg ~= 0 then
		if extraAnimation == true then
			local pos = creature:getPosition()
			local EFFECT_TYPE = 0
			if elementType == COMBAT_FIREDAMAGE then
				EFFECT_TYPE = CONST_ME_FIREATTACK
			elseif elementType == COMBAT_ENERGYDAMAGE then
				EFFECT_TYPE = CONST_ME_ENERGYAREA
			end
			pos:sendMagicEffect(EFFECT_TYPE)
		end

		if elementalroll then
			if primaryType == elementType then
				primaryDamage = primaryDamage + eleDmg
			else
				if primaryType == 0 then
					if secondaryType == elementType then
						secondaryDamage = secondaryDamage + eleDmg
					else
						primaryDamage = eleDmg
						primaryType = elementType
					end
				else
					secondaryDamage = secondaryDamage + eleDmg
					secondaryType = elementType
				end
			end
		else
			local originalDamage = primaryDamage
			local originalType = primaryType

			primaryDamage = secondaryDamage + eleDmg
			primaryType = elementType
			secondaryDamage = originalDamage
			secondaryType = originalType

			elementalroll = true
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll
end

-- Prism Heart (stats[40]): converts a % of the wearer's own physical damage
-- into a random element every hit, chosen fresh each swing. Reuses
-- elementalDmg() exactly as it exists for Enhanced Fire/Ice/Energy Damage --
-- just fakes a fixed-magnitude "Enhanced <Type> Damage: N-N" bracket at the
-- converted amount instead of reading a pre-rolled range, so the existing
-- per-target resistance/immunity handling in elementalDmg() applies
-- unchanged.
local PRISM_HEART_ELEMENTS = {COMBAT_FIREDAMAGE, COMBAT_ICEDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_EARTHDAMAGE, COMBAT_DEATHDAMAGE}
local function applyPrismHeart(weaponDescription, creature, resistances, primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll)
	local convertPercent = tonumber(string.match(weaponDescription, "Prism Heart: %+(%d+)%%"))
	if not convertPercent then
		return primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll
	end

	local physicalDamage = elementalroll and secondaryDamage or primaryDamage
	local physicalType = elementalroll and secondaryType or primaryType
	if physicalType ~= COMBAT_PHYSICALDAMAGE or physicalDamage <= 0 then
		return primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll
	end

	local converted = math.floor((convertPercent / 100) * physicalDamage)
	if converted <= 0 then
		return primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll
	end

	if elementalroll then
		secondaryDamage = secondaryDamage - converted
	else
		primaryDamage = primaryDamage - converted
	end

	local elementType = PRISM_HEART_ELEMENTS[math.random(1, #PRISM_HEART_ELEMENTS)]
	local fakeDescription = "[Enhanced " .. resistances[elementType].String .. " Damage: " .. converted .. "-" .. converted .. "]"
	return elementalDmg(fakeDescription, elementType, false, creature, resistances, primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll)
end

-- Hold the Line (stats[39]): incoming damage reduction that ramps from 0% up
-- to the item's rolled magnitude over HOLD_THE_LINE_RAMP_SECONDS of standing
-- on the same tile, resetting instantly the moment the wearer's position
-- changes. Position is compared lazily here (no MoveEvent needed) since this
-- already runs on every incoming health/mana change against the wearer.
local function applyHoldTheLine(creature, primaryDamage, secondaryDamage)
	local armor = creature:getSlotItem(CONST_SLOT_ARMOR)
	if not armor then
		holdTheLineState[creature:getId()] = nil
		return primaryDamage, secondaryDamage
	end

	local desc = armor:getSpecialDescription()
	local maxPercent = desc and tonumber(string.match(desc, "Hold the Line: %+(%d+)%%"))
	if not maxPercent then
		holdTheLineState[creature:getId()] = nil
		return primaryDamage, secondaryDamage
	end

	local playerId = creature:getId()
	local pos = creature:getPosition()
	local state = holdTheLineState[playerId]
	if not state or state.x ~= pos.x or state.y ~= pos.y or state.z ~= pos.z then
		state = {x = pos.x, y = pos.y, z = pos.z, since = os.time()}
		holdTheLineState[playerId] = state
	end

	local elapsed = os.time() - state.since
	local rampedPercent = math.min(maxPercent, math.floor(maxPercent * elapsed / HOLD_THE_LINE_RAMP_SECONDS))
	if rampedPercent <= 0 then
		return primaryDamage, secondaryDamage
	end

	local resistanceMultiplier = (100 - rampedPercent) / 100
	return primaryDamage * resistanceMultiplier, secondaryDamage * resistanceMultiplier
end

-- Dodge Chance (stats[42]): boots only. Fully custom, NOT the native Forge
-- "Ruse" mechanic (see stats[42]'s comment in rarity_stats.lua for why).
-- Rolled like every other %-chance stat in this file (Stun Chance, Crit
-- Chance) -- 1-100 against the rolled value, not the native combat.cpp
-- dodge's 1-10000/100.0 scale, since this has nothing to do with that code
-- path.
local function applyDodgeChance(creature, primaryDamage, secondaryDamage)
	local boots = creature:getSlotItem(CONST_SLOT_FEET)
	if not boots then
		return primaryDamage, secondaryDamage
	end

	local desc = boots:getSpecialDescription()
	local dodgeChance = desc and tonumber(string.match(desc, "Dodge Chance: %+(%d+)%%"))
	if not dodgeChance then
		return primaryDamage, secondaryDamage
	end

	if math.random(1, 100) <= dodgeChance then
		creature:getPosition():sendMagicEffect(CONST_ME_DODGE)
		return 0, 0
	end
	return primaryDamage, secondaryDamage
end

-- Juggernaut (stats[51]): body armor, Knight/Paladin only. Reduces incoming
-- damage further the more creatures are simultaneously targeting the
-- wearer -- a real per-attacker count via Creature:getTarget(), not a
-- spectator-proximity approximation (confirmed real/registered binding,
-- src/luacreature.cpp). Attacker count is capped at
-- JUGGERNAUT_ATTACKER_CAP and the total reduction at
-- JUGGERNAUT_MAX_REDUCTION_PERCENT so a swarmed player never approaches
-- full immunity.
local function applyJuggernaut(creature, primaryDamage, secondaryDamage)
	local armor = creature:getSlotItem(CONST_SLOT_ARMOR)
	if not armor then
		return primaryDamage, secondaryDamage
	end

	local desc = armor:getSpecialDescription()
	local perAttackerPercent = desc and tonumber(string.match(desc, "Juggernaut: %+(%d+)%%"))
	if not perAttackerPercent then
		return primaryDamage, secondaryDamage
	end

	local attackerCount = 0
	local spectators = Game.getSpectators(creature:getPosition(), false, false, 8, 8, 8, 8)
	for _, spectator in ipairs(spectators) do
		if spectator:isMonster() and spectator:getTarget() == creature then
			attackerCount = attackerCount + 1
		end
	end
	if attackerCount <= 0 then
		return primaryDamage, secondaryDamage
	end

	local reductionPercent = math.min(perAttackerPercent * math.min(attackerCount, JUGGERNAUT_ATTACKER_CAP), JUGGERNAUT_MAX_REDUCTION_PERCENT)
	local multiplier = (100 - reductionPercent) / 100
	return primaryDamage * multiplier, secondaryDamage * multiplier
end

-- Thorn (stats[45]): legs (Knight/Paladin-locked) and shields (non-
-- spellbook). Reflects a % of the damage the wearer is about to take back
-- at whoever hit them, as flat physical damage regardless of the incoming
-- damage type (thematically a spike/thorn puncture, not a magical
-- retaliation). Sums across legs+shield if both roll it, same additive-
-- stacking convention Crit Chance already uses across multiple slots in
-- this file.
--
-- thornReflecting guards against a reflect-ping-pong: if both the original
-- attacker and defender have Thorn, the reflected hit landing on the
-- attacker would otherwise trigger THEIR Thorn back at the original
-- defender, potentially looping. Keyed by the id of whoever is currently
-- the TARGET of an in-flight reflection -- checked at the top of this
-- function, so a creature mid-reflection-target can't itself reflect
-- further until that call resolves. Same guard shape as Spell Echo's
-- spellEchoing table above.
local thornReflecting = {}

local function applyThorn(creature, attacker, primaryDamage, secondaryDamage)
	if not attacker or attacker == creature then
		return
	end
	if thornReflecting[creature:getId()] then
		return
	end

	local thornPercent = 0
	for _, slot in ipairs({CONST_SLOT_LEGS, CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = creature:getSlotItem(slot)
		if item then
			local desc = item:getSpecialDescription()
			local percent = desc and tonumber(string.match(desc, "Thorn: %+(%d+)%%"))
			if percent then
				thornPercent = thornPercent + percent
			end
		end
	end
	if thornPercent <= 0 then
		return
	end

	local reflectDamage = math.floor((thornPercent / 100) * (primaryDamage + secondaryDamage))
	if reflectDamage <= 0 then
		return
	end

	thornReflecting[attacker:getId()] = true
	doTargetCombatHealth(creature, attacker, COMBAT_PHYSICALDAMAGE, reflectDamage, reflectDamage)
	thornReflecting[attacker:getId()] = nil
end

-- Guardian's Pact (stats[54]): Mage/Paladin helmets. On a proc, redirects
-- GUARDIANS_PACT_REDIRECT_PERCENT of the hit the wearer is about to take
-- away from themself (reduces primaryDamage/secondaryDamage here) and into
-- a heal for the most-injured party member within GUARDIANS_PACT_RANGE
-- tiles (Participants() -- same party helper Rebirth/Chain Heal already
-- use). Caller is responsible for only invoking this on real damage, not
-- healing -- see the primaryType/secondaryType guard around its call site
-- in statChange, same shape as the existing manaleech/lifeleech
-- COMBAT_HEALING exclusions in this file.
local function applyGuardiansPact(creature, primaryDamage, secondaryDamage)
	local helmet = creature:getSlotItem(CONST_SLOT_HEAD)
	if not helmet then
		return primaryDamage, secondaryDamage
	end

	local desc = helmet:getSpecialDescription()
	local pactChance = desc and tonumber(string.match(desc, "Guardian's Pact: %+(%d+)%%"))
	if not pactChance or math.random(1, 100) > pactChance then
		return primaryDamage, secondaryDamage
	end

	local totalDamage = primaryDamage + secondaryDamage
	if totalDamage <= 0 then
		return primaryDamage, secondaryDamage
	end

	local selfPos = creature:getPosition()
	local bestTarget, bestDeficit = nil, 0
	for _, member in ipairs(Participants(creature, false)) do
		if member and member ~= creature and member:isPlayer() and member:getHealth() > 0 then
			local deficit = member:getMaxHealth() - member:getHealth()
			if deficit > bestDeficit and member:getPosition():getDistance(selfPos) <= GUARDIANS_PACT_RANGE then
				bestDeficit = deficit
				bestTarget = member
			end
		end
	end
	if not bestTarget then
		return primaryDamage, secondaryDamage
	end

	local redirected = math.floor((GUARDIANS_PACT_REDIRECT_PERCENT / 100) * totalDamage)
	if redirected <= 0 then
		return primaryDamage, secondaryDamage
	end

	local multiplier = math.max(0, totalDamage - redirected) / totalDamage
	bestTarget:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
	doTargetCombatHealth(creature, bestTarget, COMBAT_HEALING, redirected, redirected)
	return primaryDamage * multiplier, secondaryDamage * multiplier
end

-- Glass Cannon (stats[55]) incoming-damage side -- mage body armor.
-- Caller only invokes this inside the same COMBAT_HEALING guard as every
-- other function in this block, so no separate check needed here.
-- Always-on while equipped, no trigger chance -- this is the genuine
-- "risk" half of the stat, so it isn't gated behind a roll the way the
-- rest of this file's negative-for-the-attacker mechanics (none, in
-- practice) would be.
local function applyGlassCannonIncoming(creature, primaryDamage, secondaryDamage)
	local armor = creature:getSlotItem(CONST_SLOT_ARMOR)
	if not armor then
		return primaryDamage, secondaryDamage
	end

	local desc = armor:getSpecialDescription()
	local glassCannonPercent = desc and tonumber(string.match(desc, "Glass Cannon: %+(%d+)%%"))
	if not glassCannonPercent then
		return primaryDamage, secondaryDamage
	end

	local multiplier = 1 + (glassCannonPercent / 100)
	return primaryDamage * multiplier, secondaryDamage * multiplier
end

-- Armor Breaker (stats[48]): crossbows only. Read from the ATTACKER's
-- equipped crossbow (CONST_SLOT_LEFT/RIGHT), reducing the DEFENDER's
-- Physical Resistance -- the inverse direction of every other resistance
-- stat in this file. Honest limitation, stated plainly: this can only ever
-- discount the CUSTOM (rarity-granted) Physical Resistance this Lua system
-- itself tracks in `resistances`. A creature's native armor value is
-- already folded into the incoming damage by the C++ engine before
-- onHealthChange/statChange ever runs (same category of hard limit
-- documented for Rebirth's death-veto approach) -- there is no Lua hook
-- that can retroactively un-apply that. Still meaningfully strong against
-- anything wearing rarity-rolled resistance gear, which is the system this
-- whole feature was built to counter.
local function getArmorBreakerPercent(attacker)
	local breakerPercent = 0
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = attacker:getSlotItem(slot)
		if item then
			local desc = item:getSpecialDescription()
			local percent = desc and tonumber(string.match(desc, "Armor Breaker: %+(%d+)%%"))
			if percent then
				breakerPercent = breakerPercent + percent
			end
		end
	end
	return breakerPercent
end

local function statChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local chance = 0
	local spellmodifier = 0
	local manaleech = 0
	local lifeleech = 0
	local stunDuration = 2000
	local sourceDamage = primaryDamage
	local elementalroll = false

	local resistances = {
		[COMBAT_PHYSICALDAMAGE] = {Native = 0, Custom = 0, String = "Physical"},
		[COMBAT_FIREDAMAGE] = {Native = 0, Custom = 0, String = "Fire"},
		[COMBAT_ICEDAMAGE] = {Native = 0, Custom = 0, String = "Ice"},
		[COMBAT_ENERGYDAMAGE] = {Native = 0, Custom = 0, String = "Energy"},
		[COMBAT_EARTHDAMAGE] = {Native = 0, Custom = 0, String = "Earth"},
		[COMBAT_DEATHDAMAGE] = {Native = 0, Custom = 0, String = "Death"}
	}

	if creature:isPlayer() then
		for i = 1, #checkallslots do
			if creature:getSlotItem(checkallslots[i]) ~= nil then
				local resistanceitem = creature:getSlotItem(checkallslots[i])
				local resistanceitemdesc = resistanceitem:getSpecialDescription()
				getResistences(resistanceitemdesc, resistances, true)
			end
		end

		if attacker and attacker:isPlayer() and resistances[COMBAT_PHYSICALDAMAGE].Custom > 0 then
			local armorBreakerPercent = getArmorBreakerPercent(attacker)
			if armorBreakerPercent > 0 then
				resistances[COMBAT_PHYSICALDAMAGE].Custom = resistances[COMBAT_PHYSICALDAMAGE].Custom * (100 - math.min(armorBreakerPercent, 100)) / 100
			end
		end

		if primaryType ~= 0 then
			if resistances[primaryType] then
				if resistances[primaryType].Custom ~= 0 then
					local resistancePercent = (100 - resistances[primaryType].Custom)
					primaryDamage = (resistancePercent / 100) * primaryDamage
				end
			end
		end
		if secondaryType ~= 0 then
			if resistances[secondaryType] then
				if resistances[secondaryType].Custom ~= 0 then
					local resistancePercent = (100 - resistances[secondaryType].Custom)
					secondaryDamage = (resistancePercent / 100) * secondaryDamage
				end
			end
		end

		-- Every one of these is a defender-side DAMAGE modifier -- none of
		-- them should ever touch a heal landing on this creature. Before
		-- this guard existed, Hold the Line/Dodge Chance/Thorn ran
		-- unconditionally on every health change including heals, so a
		-- lucky Dodge Chance roll could silently zero out a heal, or Hold
		-- the Line could quietly shrink one -- a real, pre-existing bug
		-- (not introduced by Juggernaut/Guardian's Pact/Glass Cannon, but
		-- caught while adding them, and fixed here for all of them at
		-- once rather than patching each call site separately). Glass
		-- Cannon's incoming-damage boost is deliberately the LAST thing
		-- applied here, per owner's explicit call -- so its increase is
		-- never softened by any of the reductions above it, and Thorn's
		-- reflect is calculated off the final (Glass-Cannon-boosted, if
		-- applicable) damage number.
		if primaryType ~= COMBAT_HEALING and secondaryType ~= COMBAT_HEALING then
			primaryDamage, secondaryDamage = applyHoldTheLine(creature, primaryDamage, secondaryDamage)
			primaryDamage, secondaryDamage = applyDodgeChance(creature, primaryDamage, secondaryDamage)
			primaryDamage, secondaryDamage = applyJuggernaut(creature, primaryDamage, secondaryDamage)
			primaryDamage, secondaryDamage = applyGuardiansPact(creature, primaryDamage, secondaryDamage)
			primaryDamage, secondaryDamage = applyGlassCannonIncoming(creature, primaryDamage, secondaryDamage)
			applyThorn(creature, attacker, primaryDamage, secondaryDamage)
		end
	end

	if attacker then -- Ignore HP changes from healing fountains, terrain elemental fields
		if attacker:isPlayer() then
			-- Adrenaline Rush (stats[46]) damage-boost side -- the speed
			-- side is a real Condition set directly in rarity_loot_drop.lua
			-- on kill (self-expiring, no check needed here). Applied once,
			-- uniformly, before the RANGED/MELEE vs SPELL branch split below
			-- so it boosts every attack type the same way. Magnitude is
			-- snapshotted at trigger time (kill moment) into
			-- RarityAdrenaline.active, not re-read from the boots item
			-- here, so it stays correct even if boots get swapped mid-buff.
			local adrenaline = RarityAdrenaline.active[attacker:getId()]
			if adrenaline then
				if adrenaline.expiry > os.time() then
					primaryDamage = primaryDamage * (1 + (adrenaline.percent / 100))
				else
					RarityAdrenaline.active[attacker:getId()] = nil
				end
			end

			-- Glass Cannon (stats[55]) damage-dealt side -- mage body
			-- armor. Read directly from CONST_SLOT_ARMOR rather than
			-- checkweaponslots, since every other attacker-side check in
			-- this file scans the weapon-adjacent slots, not body armor.
			-- Always-on while equipped (no trigger chance), applied here
			-- uniformly before the RANGED/MELEE vs SPELL split, same
			-- placement as Adrenaline Rush above. Guarded against
			-- COMBAT_HEALING -- this is a damage stat, not a heal-power
			-- stat, even on a Sorcerer/Druid self- or party-heal.
			if primaryType ~= COMBAT_HEALING then
				local attackerArmor = attacker:getSlotItem(CONST_SLOT_ARMOR)
				if attackerArmor then
					local armorDesc = attackerArmor:getSpecialDescription()
					local glassCannonPercent = armorDesc and tonumber(string.match(armorDesc, "Glass Cannon: %+(%d+)%%"))
					if glassCannonPercent then
						primaryDamage = primaryDamage * (1 + (glassCannonPercent / 100))
					end
				end
			end

			if origin == ORIGIN_RANGED or origin == ORIGIN_MELEE then
				if secondaryType ~= 0 or primaryType ~= COMBAT_PHYSICALDAMAGE then
					local originalDamage = primaryDamage
					local originalType = primaryType

					primaryDamage = secondaryDamage
					primaryType = secondaryType
					secondaryDamage = originalDamage
					secondaryType = originalType

					elementalroll = true
				end

				for i = 1, #checkweaponslots do
					if attacker:getSlotItem(checkweaponslots[i]) ~= nil then
						local slotitem = attacker:getSlotItem(checkweaponslots[i])
						local slotitemdesc = slotitem:getSpecialDescription()

						if slotitemdesc:find "[%[%(]Enhanced Fire Damage" then
							primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll = elementalDmg(slotitemdesc, COMBAT_FIREDAMAGE, true, creature, resistances, primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll)
							if math.random(1, 3) == 3 then -- 33% chance to apply burn
								local condition = createConditionObject(CONDITION_FIRE)
								local burnDamage = 20
								if creature:isPlayer() then
									if resistances[COMBAT_FIREDAMAGE].Custom ~= 0 or resistances[COMBAT_FIREDAMAGE].Native ~= 0 then
										local resistancePercent = (100 - (resistances[COMBAT_FIREDAMAGE].Custom + resistances[COMBAT_FIREDAMAGE].Native))
										burnDamage = (resistancePercent / 100) * burnDamage
									end
								elseif creature:isMonster() then
									local resistance = creature:getType():getElementList()
									local immunity = creature:getType():getCombatImmunities()
									if resistance[COMBAT_FIREDAMAGE] then
										local resistancePercent = (100 - resistance[COMBAT_FIREDAMAGE])
										burnDamage = (resistancePercent / 100) * burnDamage
									end
									if bit.band(immunity, COMBAT_FIREDAMAGE) == COMBAT_FIREDAMAGE then
										burnDamage = 0
									end
								end
								if burnDamage ~= 0 then
									addDamageCondition(condition, 10, 2000, burnDamage)
									setConditionParam(condition, CONDITION_PARAM_DELAYED, true)
									doTargetCombatCondition(attacker, creature, condition, CONST_ME_FIRE)
								end
							end
						end
						if slotitemdesc:find "[%[%(]Enhanced Ice Damage" then
							primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll = elementalDmg(slotitemdesc, COMBAT_ICEDAMAGE, false, creature, resistances, primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll)
							if math.random(1, 5) == 5 then -- 20% to paralyze/slow
								local condition = createConditionObject(CONDITION_PARALYZE)
								setConditionParam(condition, CONDITION_PARAM_TICKS, 3000)
								setConditionParam(condition, CONDITION_PARAM_SPEED, -300)
								doTargetCombatCondition(attacker, creature, condition, CONST_ME_MAGIC_ICEAREA)
							end
						end
						if slotitemdesc:find "[%[%(]Enhanced Energy Damage" then
							primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll = elementalDmg(slotitemdesc, COMBAT_ENERGYDAMAGE, true, creature, resistances, primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll)
						end

						if slotitemdesc:find "[%[%(]Prism Heart" then
							primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll = applyPrismHeart(slotitemdesc, creature, resistances, primaryDamage, primaryType, secondaryDamage, secondaryType, elementalroll)
						end

						if slotitemdesc:find "[%[%(]Crit Chance" then
							local crit = tonumber(string.match(slotitemdesc, "Crit Chance: [+-](%d+)%%"))
							chance = chance + crit
						end

						if slotitemdesc:find "[%[%(]Mana Leech" then
							manaleech = tonumber(string.match(slotitemdesc, '[%[%(]Mana Leech[^:]*: %+(%d+)%%[%]%)]')) or 0
						end

						if slotitemdesc:find "[%[%(]Life Leech" then
							lifeleech = tonumber(string.match(slotitemdesc, '[%[%(]Life Leech: %+(%d+)%%[%]%)]')) or 0
						end

						if slotitemdesc:find "[%[%(]Stun Chance" then
							local stunchance = tonumber(string.match(slotitemdesc, '[%[%(]Stun Chance: %+(%d+)%%[%]%)]')) or 0
							local rollchance = math.random(1, 100)
							if stunchance >= rollchance and attacker ~= creature then
								stunTarget(creature:getId(), stunDuration)
							end
						end

						if slotitemdesc:find "[%[%(]Pin Down" then
							local pindownchance = tonumber(string.match(slotitemdesc, '[%[%(]Pin Down: %+(%d+)%%[%]%)]')) or 0
							if pindownchance > 0 then
								applyPinDown(attacker, creature, pindownchance)
							end
						end

						if slotitemdesc:find "[%[%(]Multi Shot" then
							if attacker:getSlotItem(CONST_SLOT_AMMO) ~= nil then
								local multishot = tonumber(string.match(slotitemdesc, "[%[%(]Multi Shot: %+(%d+)[%]%)]"))
								local ammoSlot = attacker:getSlotItem(CONST_SLOT_AMMO):getId()
								local validammo = false
								for k in pairs(animation) do
									if k == ammoSlot then
										validammo = true
										break
									end
								end
								if validammo then
									local targetpos = creature:getPosition()
									local targets = getSpectators(targetpos, 2, 2)
									local victims = {}
									if targets ~= nil then
										shuffle(targets)
										for i = 1, #targets do
											local target = Creature(targets[i])
											if target:isMonster() then
												if isSightClear(attacker:getPosition(), target:getPosition()) then
													if target:getPosition() ~= targetpos then
														local victimcount = #victims or 0
														if victimcount < multishot then
															table.insert(victims, target)
														else
															break
														end
													end
												end
											end
										end
									end
									if victims ~= nil then
										for i = 1, #victims do
											local damage = 0
											local elementalDamage = 0
											local backupDamage = 0
											local mainType = primaryType
											local altType = secondaryType
											local resistance = victims[i]:getType():getElementList()
											local immunity = victims[i]:getType():getCombatImmunities()
											attacker:getPosition():sendDistanceEffect(victims[i]:getPosition(), animation[ammoSlot])
											if elementalroll then
												mainType = secondaryType
												altType = primaryType
												damage = filterResistance(secondaryDamage, secondaryType, immunity, resistance)
												elementalDamage = filterResistance(primaryDamage, primaryType, immunity, resistance)
											else
												damage = filterResistance(primaryDamage, primaryType, immunity, resistance)
												elementalDamage = filterResistance(secondaryDamage, secondaryType, immunity, resistance)
											end
											if elementalDamage ~= 0 then
												doTargetCombatHealth(attacker, victims[i], altType, math.ceil((80 / 100) * elementalDamage), elementalDamage)
											end
											if damage ~= 0 then
												doTargetCombatHealth(attacker, victims[i], mainType, math.ceil((80 / 100) * damage), damage)
											else
												backupDamage = filterResistance(sourceDamage, COMBAT_PHYSICALDAMAGE, immunity, resistance)
												if backupDamage ~= 0 then
													doTargetCombatHealth(attacker, victims[i], COMBAT_PHYSICALDAMAGE, math.ceil((80 / 100) * sourceDamage), sourceDamage)
												else
													victims[i]:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
												end
											end
										end
									end
								end
							end
						end
					end
				end

				if chance > 0 then
					if math.random(100) <= chance then
						local pos = creature:getPosition()
						pos:sendMagicEffect(criteffect)
						if elementalroll then
							secondaryDamage = secondaryDamage * critmodifier
						else
							primaryDamage = primaryDamage * critmodifier
						end
					end
				end

				-- Cleave (stats[53]) -- two-handed Knight weapons, melee
				-- only (unlike Multi Shot, no CONST_SLOT_AMMO requirement).
				-- Checked after the crit block above so a critical swing
				-- cleaves for the boosted amount too. Reuses Multi Shot's
				-- spectator/shuffle targeting, but always exactly 1 extra
				-- target within melee range (radius 1) instead of a rolled
				-- count.
				if origin == ORIGIN_MELEE then
					for i = 1, #checkweaponslots do
						if attacker:getSlotItem(checkweaponslots[i]) ~= nil then
							local slotitemdesc = attacker:getSlotItem(checkweaponslots[i]):getSpecialDescription()
							if slotitemdesc:find "[%[%(]Cleave" then
								local cleaveChance = tonumber(string.match(slotitemdesc, '[%[%(]Cleave: %+(%d+)%%[%]%)]')) or 0
								if cleaveChance > 0 and math.random(1, 100) <= cleaveChance then
									local targetpos = creature:getPosition()
									local targets = getSpectators(targetpos, 1, 1)
									local victim = nil
									if targets ~= nil then
										shuffle(targets)
										for i2 = 1, #targets do
											local candidate = Creature(targets[i2])
											if candidate:isMonster() and candidate:getPosition() ~= targetpos then
												victim = candidate
												break
											end
										end
									end
									if victim then
										local resistance = victim:getType():getElementList()
										local immunity = victim:getType():getCombatImmunities()
										local mainType = elementalroll and secondaryType or primaryType
										local mainDamage = elementalroll and secondaryDamage or primaryDamage
										local damage = filterResistance(mainDamage, mainType, immunity, resistance)
										if damage ~= 0 then
											victim:getPosition():sendMagicEffect(CONST_ME_HITAREA)
											doTargetCombatHealth(attacker, victim, mainType, math.ceil((CLEAVE_DAMAGE_PERCENT / 100) * damage), damage)
										else
											victim:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
										end
									end
								end
								break
							end
						end
					end
				end

				if manaleech ~= 0 then
					local manatoadd = math.floor((manaleech / 100) * (primaryDamage + secondaryDamage))
					addEvent(manaLeechConcat, 5, attacker:getId(), manatoadd)
				end

				if lifeleech ~= 0 then
					local lifetoadd = math.floor((lifeleech / 100) * (primaryDamage + secondaryDamage))
					addEvent(lifeLeechConcat, 5, attacker:getId(), lifetoadd)
				end
			elseif origin == ORIGIN_SPELL then
				if resistances[primaryType] then
					if resistances[primaryType].Custom ~= 0 then
						local resistancePercent = (100 - resistances[primaryType].Custom)
						primaryDamage = (resistancePercent / 100) * primaryDamage
					end
				end

				for i = 1, #checkweaponslots do
					if attacker:getSlotItem(checkweaponslots[i]) ~= nil then
						local slotitem = attacker:getSlotItem(checkweaponslots[i])
						local slotitemdesc = slotitem:getSpecialDescription()

						if slotitemdesc:find "[%[%(]Spell Damage" then
							local spellDamage = tonumber(string.match(slotitemdesc, "Spell Damage: [+-](%d+)%%"))
							spellmodifier = spellmodifier + spellDamage
						end

						if slotitemdesc:find "[%[%(]Mana Leech" then
							manaleech = tonumber(string.match(slotitemdesc, '[%[%(]Mana Leech[^:]*: %+(%d+)%%[%]%)]')) or 0
						end

						if slotitemdesc:find "[%[%(]Life Leech" then
							lifeleech = tonumber(string.match(slotitemdesc, '[%[%(]Life Leech: %+(%d+)%%[%]%)]')) or 0
						end

						if slotitemdesc:find "[%[%(]Stun Chance" then
							local stunchance = tonumber(string.match(slotitemdesc, '[%[%(]Stun Chance: %+(%d+)%%[%]%)]')) or 0
							local rollchance = math.random(1, 100)
							if stunchance >= rollchance and attacker ~= creature then
								stunTarget(creature:getId(), stunDuration)
							end
						end
					end
				end

				if spellmodifier > 0 then
					local extraDamage = (spellmodifier / 100) * primaryDamage
					primaryDamage = primaryDamage + extraDamage
				end

				-- Chain Heal (stats[50]) -- rods only. Only relevant when the
				-- combat type IS a heal (COMBAT_HEALING), so it's checked
				-- after spellmodifier (same "boosted final amount, not the
				-- raw roll" reasoning as Spell Echo below) in its own
				-- dedicated block rather than folded into the per-slot loop
				-- above, which also runs for damage spells. Picks the most-
				-- injured party member within CHAIN_HEAL_RANGE of the
				-- already-healed target (excluding that target itself) using
				-- the same Participants() helper Rebirth already uses for
				-- party lookups.
				if primaryType == COMBAT_HEALING and not chainHealing[attacker:getId()] then
					for i = 1, #checkweaponslots do
						if attacker:getSlotItem(checkweaponslots[i]) ~= nil then
							local slotitemdesc = attacker:getSlotItem(checkweaponslots[i]):getSpecialDescription()
							if slotitemdesc:find "[%[%(]Chain Heal" then
								local chainChance = tonumber(string.match(slotitemdesc, '[%[%(]Chain Heal: %+(%d+)%%[%]%)]')) or 0
								if chainChance > 0 and math.random(1, 100) <= chainChance then
									local healPos = creature:getPosition()
									local bestTarget = nil
									local bestDeficit = 0
									for _, member in ipairs(Participants(attacker, false)) do
										if member and member ~= creature and member:isPlayer() and member:getHealth() > 0 then
											local deficit = member:getMaxHealth() - member:getHealth()
											if deficit > bestDeficit and member:getPosition():getDistance(healPos) <= CHAIN_HEAL_RANGE then
												bestDeficit = deficit
												bestTarget = member
											end
										end
									end
									if bestTarget then
										local healAmount = math.max(1, math.floor((CHAIN_HEAL_POWER_PERCENT / 100) * primaryDamage))
										local attackerId = attacker:getId()
										chainHealing[attackerId] = true
										bestTarget:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
										doTargetCombatHealth(attacker, bestTarget, COMBAT_HEALING, healAmount, healAmount)
										chainHealing[attackerId] = nil
									end
								end
								break
							end
						end
					end
				end

				-- Spell Echo (stats[41]) -- checked after spellmodifier so the
				-- echo reflects the fully-boosted final hit, not the pre-Spell-
				-- Damage raw roll. Scans checkweaponslots a second time, same
				-- pattern rarityManaChange already uses for Mana Shield.
				if primaryType ~= COMBAT_HEALING and secondaryType ~= COMBAT_HEALING and not spellEchoing[attacker:getId()] then
					for i = 1, #checkweaponslots do
						if attacker:getSlotItem(checkweaponslots[i]) ~= nil then
							local slotitemdesc = attacker:getSlotItem(checkweaponslots[i]):getSpecialDescription()
							if slotitemdesc:find "[%[%(]Spell Echo" then
								local echoPower = tonumber(string.match(slotitemdesc, "Spell Echo: %+(%d+)%%"))
								if echoPower and math.random(1, 100) <= SPELL_ECHO_TRIGGER_CHANCE then
									local echoDamage = math.max(1, math.floor((echoPower / 100) * primaryDamage))
									local echoType = primaryType
									local attackerId = attacker:getId()
									local targetId = creature:getId()
									spellEchoing[attackerId] = true
									addEvent(function()
										local echoAttacker = Creature(attackerId)
										local echoTarget = Creature(targetId)
										if echoAttacker and echoTarget and echoTarget:getHealth() > 0 then
											echoTarget:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
											doTargetCombatHealth(echoAttacker, echoTarget, echoType, echoDamage, echoDamage)
										end
										spellEchoing[attackerId] = nil
									end, 400)
								end
								break
							end
						end
					end
				end

				if manaleech ~= 0 and primaryType ~= COMBAT_HEALING and secondaryType ~= COMBAT_HEALING then
					local manatoadd = math.floor((manaleech / 100) * (primaryDamage + secondaryDamage))
					manaLeechConcat(attacker:getId(), manatoadd)
				end

				if lifeleech ~= 0 and primaryType ~= COMBAT_HEALING and secondaryType ~= COMBAT_HEALING then
					local lifetoadd = math.floor((lifeleech / 100) * (primaryDamage + secondaryDamage))
					lifeLeechConcat(attacker:getId(), lifetoadd)
				end
			end
		end
	end

	return primaryDamage, primaryType, secondaryDamage, secondaryType, origin
end

local rarityHealthChange = CreatureEvent("RarityHealthChange")
function rarityHealthChange.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	-- Rebirth's downed state (data/lib/rarity/rarity_rebirth.lua) is meant to
	-- be fully protective, not just "can't be finished off" -- onPrepareDeath
	-- alone only re-vetoes hits that would qualify as lethal against the
	-- pinned 1 HP floor, which leaves a gap if the downed player gets healed
	-- above 1 HP by an ally mid-window (a smaller follow-up hit would no
	-- longer register as lethal, and would land for real). Closing that gap
	-- here instead: while downed, all incoming damage is zeroed outright,
	-- unconditionally, before anything else in this file runs.
	if primaryType ~= 128 and RarityRebirth.downed[creature:getId()] then
		return 0, primaryType, 0, secondaryType
	end

	if primaryType ~= 128 then -- Ignore health potions
		primaryDamage, primaryType, secondaryDamage, secondaryType, origin = statChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
rarityHealthChange:register()

local rarityManaChange = CreatureEvent("RarityManaChange")
function rarityManaChange.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType ~= 64 then -- Ignore mana potions
		primaryDamage, primaryType, secondaryDamage, secondaryType, origin = statChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)

		if creature:isPlayer() then
			local manashield = 0
			for i = 1, #checkweaponslots do
				if creature:getSlotItem(checkweaponslots[i]) ~= nil then
					local slotitem = creature:getSlotItem(checkweaponslots[i])
					local slotitemdesc = slotitem:getSpecialDescription()
					if slotitemdesc:find "[%[%(]Mana Shield" then
						manashield = manashield + tonumber(string.match(slotitemdesc, '[%[%(]Mana Shield: %+(%d+)%%[%]%)]'))
					end
				end
			end
			if manashield ~= 0 then
				local shieldPercent = (100 - manashield)
				primaryDamage = (shieldPercent / 100) * primaryDamage
				secondaryDamage = (shieldPercent / 100) * secondaryDamage
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
rarityManaChange:register()
