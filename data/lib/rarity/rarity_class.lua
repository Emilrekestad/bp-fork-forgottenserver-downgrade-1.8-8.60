-- Item Rarity system — power classification. Buckets items into Class 1
-- (weakest) through Class 7 (strongest) so rollRarity can scale bonus
-- magnitude by the item's own power level, instead of every eligible item
-- rolling from identical flat ranges regardless of whether it's a starter
-- Bow or a level-600 Sanguine Blade.
--
-- Primary signal: ItemType:getMinReqLevel() (real level-requirement gate,
-- already used elsewhere in this codebase -- see data/lib/core/item.lua's
-- own wield-info text). Class boundaries are anchored to genuine gaps found
-- in this datapack's real level distribution (nothing exists between
-- 330-400 or 400-500), not arbitrary round numbers.
--
-- `classification` (the native Forge tier attribute, 1-4) is deliberately
-- NOT used as an input -- it correlates with level only on average, has
-- real inversions (Falcon Longsword: classification 2, level 300), and is
-- completely absent from every Sanguine weapon, the single most extreme
-- weapon line in the game.
--
-- Items with neither signal (mostly classic shields/rings/amulets/helmets
-- that predate the level-gating convention) fall back to relative
-- armor/defense/attack/speed magnitude (see classFromFallbackStats below),
-- capped at Class 5 -- a full survey found raw stat magnitude barely
-- correlates with real Class even among trusted level-gated items, so
-- there's no evidence a no-level item's stats justify Class 6-7.

RarityClass = {}

-- Hand-curated exceptions for named items whose real value (lore, prestige,
-- quest rarity) isn't reflected in items.xml's numeric attributes -- checked
-- before the derived logic below. Populated via the Item Class Ledger
-- artifact's export feature -- the owner reviewed the full classification
-- and hand-corrected 152 items that still looked wrong after the fallback
-- recalibration. "was X" in each comment is the class the algorithm alone
-- would have produced.
--
RarityClass.Overrides = {
	[3019] = 4, -- demonbone amulet (was 1 -- items.xml gives it zero combat
	            -- stats at all, no armor, no level, so it would otherwise
	            -- derive to Class 1; decided by the owner on lore/prestige
	            -- grounds instead)
	[761] = 1, -- flash arrow (was 2)
	[762] = 1, -- shiver arrow (was 2)
	[763] = 1, -- flaming arrow (was 2)
	[774] = 1, -- earth arrow (was 2)
	[812] = 3, -- terra legs (was 2)
	[821] = 3, -- magma legs (was 2)
	[822] = 3, -- lightning legs (was 2)
	[823] = 3, -- glacier kilt (was 2)
	[860] = 1, -- crimson sword (was 2)
	[3055] = 2, -- platinum amulet (was 1)
	[3208] = 1, -- giant smithhammer (was 2)
	[3265] = 1, -- two handed sword (was 2)
	[3266] = 1, -- battle axe (was 2)
	[3277] = 1, -- spear (was 2)
	[3279] = 2, -- war hammer (was 3)
	[3282] = 1, -- morning star (was 2)
	[3283] = 1, -- carlin sword (was 2)
	[3285] = 1, -- longsword (was 2)
	[3286] = 1, -- mace (was 2)
	[3287] = 1, -- throwing star (was 3)
	[3298] = 1, -- throwing knife (was 2)
	[3299] = 1, -- poison dagger (was 2)
	[3300] = 1, -- katana (was 2)
	[3303] = 6, -- great axe (was 3)
	[3305] = 1, -- battle hammer (was 2)
	[3307] = 1, -- scimitar (was 2)
	[3309] = 6, -- thunder hammer (was 3)
	[3310] = 1, -- iron hammer (was 2)
	[3312] = 4, -- silver mace (was 2)
	[3319] = 4, -- stonecutter axe (was 3)
	[3330] = 1, -- heavy machete (was 2)
	[3331] = 4, -- ravager's axe (was 3)
	[3347] = 1, -- hunting spear (was 2)
	[3351] = 2, -- steel helmet (was 3)
	[3353] = 1, -- iron helmet (was 2)
	[3354] = 1, -- brass helmet (was 2)
	[3356] = 2, -- devil helmet (was 3)
	[3357] = 2, -- plate armor (was 4)
	[3358] = 1, -- chain armor (was 3)
	[3359] = 1, -- brass armor (was 3)
	[3360] = 3, -- golden armor (was 5)
	[3361] = 1, -- leather armor (was 2)
	[3365] = 6, -- golden helmet (was 4)
	[3367] = 1, -- viking helmet (was 2)
	[3368] = 6, -- winged helmet (was 4)
	[3370] = 2, -- knight armor (was 4)
	[3372] = 1, -- brass legs (was 2)
	[3373] = 1, -- strange helmet (was 3)
	[3374] = 1, -- legion helmet (was 2)
	[3375] = 1, -- soldier helmet (was 2)
	[3377] = 1, -- scale armor (was 3)
	[3378] = 1, -- studded armor (was 2)
	[3380] = 2, -- noble armor (was 4)
	[3381] = 3, -- crown armor (was 4)
	[3383] = 1, -- dark armor (was 4)
	[3384] = 1, -- dark helmet (was 3)
	[3385] = 2, -- crown helmet (was 3)
	[3386] = 3, -- dragon scale mail (was 5)
	[3389] = 6, -- demon legs (was 3)
	[3393] = 5, -- amazon helmet (was 3)
	[3394] = 5, -- amazon armor (was 3)
	[3395] = 2, -- ceremonial mask (was 3)
	[3396] = 4, -- dwarven helmet (was 3)
	[3397] = 5, -- dwarven armor (was 4)
	[3399] = 5, -- elven mail (was 3)
	[3400] = 5, -- dragon scale helmet (was 3)
	[3402] = 2, -- native armor (was 3)
	[3403] = 2, -- tribal mask (was 1)
	[3404] = 1, -- leopard armor (was 3)
	[3405] = 1, -- horseman helmet (was 3)
	[3408] = 2, -- bonelord helmet (was 3)
	[3409] = 1, -- steel shield (was 2)
	[3410] = 1, -- plate shield (was 2)
	[3411] = 1, -- brass shield (was 2)
	[3413] = 1, -- battle shield (was 2)
	[3415] = 2, -- guardian shield (was 3)
	[3416] = 2, -- dragon shield (was 3)
	[3417] = 5, -- shield of honour (was 4)
	[3418] = 2, -- bonelord shield (was 3)
	[3419] = 2, -- crown shield (was 3)
	[3420] = 3, -- demon shield (was 4)
	[3421] = 1, -- dark shield (was 3)
	[3422] = 5, -- great shield (was 4)
	[3423] = 6, -- blessed shield (was 5)
	[3424] = 1, -- ornamented shield (was 2)
	[3425] = 1, -- dwarven shield (was 3)
	[3426] = 1, -- studded shield (was 2)
	[3427] = 2, -- rose shield (was 3)
	[3428] = 2, -- tower shield (was 3)
	[3429] = 1, -- black shield (was 2)
	[3430] = 1, -- copper shield (was 2)
	[3431] = 1, -- viking shield (was 2)
	[3432] = 1, -- ancient shield (was 3)
	[3433] = 2, -- griffin shield (was 3)
	[3434] = 3, -- vampire shield (was 4)
	[3435] = 2, -- castle shield (was 3)
	[3436] = 3, -- medusa shield (was 4)
	[3437] = 5, -- amazon shield (was 3)
	[3440] = 1, -- scarab shield (was 3)
	[3441] = 1, -- bone shield (was 2)
	[3443] = 1, -- tusk shield (was 3)
	[3444] = 1, -- sentinel shield (was 2)
	[3445] = 1, -- salamander shield (was 3)
	[3446] = 1, -- bolt (was 3)
	[3447] = 1, -- arrow (was 2)
	[3448] = 1, -- poison arrow (was 2)
	[3449] = 1, -- burst arrow (was 2)
	[3450] = 1, -- power bolt (was 3)
	[3554] = 3, -- steel boots (was 2)
	[3555] = 5, -- golden boots (was 2)
	[3556] = 2, -- crocodile boots (was 1)
	[3557] = 2, -- plate legs (was 3)
	[3558] = 1, -- chain legs (was 2)
	[3567] = 3, -- blue robe (was 4)
	[3571] = 2, -- ranger's cloak (was 3)
	[5903] = 5, -- Ferumbras' hat (was 1)
	[6131] = 2, -- tortoise shield (was 3)
	[6528] = 1, -- infernal bolt (was 4)
	[7363] = 1, -- piercing bolt (was 2)
	[7364] = 1, -- sniper arrow (was 2)
	[7365] = 1, -- onyx arrow (was 2)
	[7366] = 1, -- viper star (was 2)
	[7367] = 1, -- enchanted spear (was 2)
	[7368] = 1, -- assassin star (was 3)
	[7378] = 1, -- royal spear (was 2)
	[7385] = 1, -- crimson sword (was 2)
	[7431] = 4, -- demonbone (was 3)
	[7433] = 4, -- ravenwing (was 3)
	[7455] = 4, -- mythril axe (was 3)
	[7460] = 1, -- norse shield (was 3)
	[7461] = 1, -- krimhorn helmet (was 3)
	[7463] = 3, -- mammoth fur cape (was 4)
	[7773] = 1, -- steel axe (was 2)
	[7774] = 1, -- jagged sword (was 2)
	[8037] = 5, -- dark lord's cape (was 3)
	[8040] = 4, -- velvet mantle (was 3)
	[8042] = 2, -- spirit cloak (was 3)
	[8043] = 2, -- focus cape (was 3)
	[8044] = 2, -- belted cape (was 4)
	[8049] = 4, -- lavos armor (was 3)
	[8051] = 4, -- voltage armor (was 3)
	[8057] = 4, -- divine plate (was 3)
	[8058] = 4, -- molten plate (was 3)
	[8059] = 4, -- frozen plate (was 3)
	[8063] = 3, -- paladin armor (was 4)
	[10201] = 5, -- dragon scale boots (was 3)
	[10386] = 3, -- Zaoan shoes (was 1)
	[11674] = 3, -- cobra crown (was 2)
	[12603] = 3, -- wand of dimensions (was 2)
	[14088] = 2, -- carapace shield (was 4)
	[14250] = 3, -- deepling squelcher (was 2)
	[14251] = 1, -- tarsal arrow (was 2)
	[14252] = 1, -- vortex bolt (was 2)
	[15793] = 1, -- crystalline arrow (was 3)
	[17810] = 1, -- spike shield (was 3)
	[17829] = 3, -- buckle (was 4)
	[17846] = 2, -- leather harness (was 3)
	[17859] = 1, -- spiky club (was 2)
	[19391] = 5, -- furious frock (was 4)
	[21167] = 3, -- heat core (was 4)
	[21183] = 1, -- glooth amulet (was 3)
	[21470] = 1, -- simple arrow (was 2)
	[22726] = 3, -- rift shield (was 4)
	[22756] = 4, -- treader of torment (was 2)
	[25698] = 1, -- butterfly ring (was 3)
	[25735] = 1, -- leaf star (was 3)
	[25758] = 1, -- spectral bolt (was 5)
	[32585] = 2, -- burial shroud (was 1)
	[50267] = 2, -- boots of enlightenment (was 1)
	[3229] = 6, -- helmet of the ancients (Curse of the Seven reward; armor 8 alone would be Class 3)
	[3230] = 6, -- full helmet of the ancients
	[7390] = 4, -- justice seeker (was 3; owner 2026-10-03: Warlord arena reward)
	[7434] = 4, -- royal axe (was 3; owner 2026-10-03: Warlord arena reward)
	[7429] = 4, -- blessed sceptre (was 3; owner 2026-10-03: Warlord arena reward)
	[30323] = 6, -- rainbow necklace (was 5; owner 2026-10-02: the Chieftain arena reward, needs to roll high)
	[8026] = 4, -- warsinger bow (was 3; owner 2026-10-03: Inquisition reward room, all ten rewards Class 4)
	[8090] = 4, -- spellbook of dark mysteries (was 3; owner 2026-10-03: Inquisition reward room)
}

local function classFromLevel(level)
	if level <= 19 then
		return 1
	elseif level <= 49 then
		return 2
	elseif level <= 99 then
		return 3
	elseif level <= 149 then
		return 4
	elseif level <= 250 then
		return 5
	elseif level <= 330 then
		return 6
	else
		return 7
	end
end

-- Fallback for items with no level requirement at all: derive from relative
-- armor/defense/attack/speed magnitude, per item shape.
--
-- Recalibrated after the owner spotted visibly wrong results from the
-- original version (capped at Class 3, no speed signal at all): Great Axe
-- (a real level-95 Knight weapon, correctly Class 3 via classFromLevel) and
-- Plate Armor (no level at all, landing in "Class 3" only because armor=10
-- happened to clear this function's old >=7 cutoff) read as equally
-- powerful despite being measured by two completely different systems.
-- Boots of Haste landed in Class 1 because armor/defense/attack were the
-- ONLY signals checked -- its +20 speed was invisible to the formula
-- entirely.
--
-- Real caveat found while recalibrating (full survey against every
-- rarity-eligible item, see the Item Class Ledger artifact): raw armor/
-- defense/attack barely correlates with actual Class even among *trusted*,
-- level-gated items -- Class 6/7 weapons often carry LOWER base attack than
-- Class 2/3 ones, since high-end power comes from elemental damage/leech/
-- crit/augments instead of the base number. So this stays deliberately
-- capped at Class 5, not extended to 7 -- there's no real evidence a
-- no-level item's raw stats justify competing with true top-tier gated
-- gear. Thresholds below are anchored to this datapack's real distribution
-- among no-level items, not guessed.
--
-- This is inherently an imprecise proxy for a chunk of items (roughly a
-- third of everything rarity-eligible) that have no better signal available
-- at all. For any specific item that still looks wrong after this, use
-- RarityClass.Overrides above rather than trying to make one formula
-- perfect for all 455 of them -- it's checked before any of this runs.
local function classFromFallbackStats(itemType)
	if itemType:getWeaponType() == WEAPON_SHIELD then
		local def = itemType:getDefense()
		if def >= 39 then
			return 5
		elseif def >= 33 then
			return 4
		elseif def >= 25 then
			return 3
		elseif def >= 15 then
			return 2
		else
			return 1
		end
	end

	local armor = itemType:getArmor()
	if armor > 0 then
		if armor >= 14 then
			return 5
		elseif armor >= 10 then
			return 4
		elseif armor >= 6 then
			return 3
		elseif armor >= 3 then
			return 2
		else
			return 1
		end
	end

	local attack = itemType:getAttack()
	if attack > 0 then
		if attack >= 60 then
			return 5
		elseif attack >= 45 then
			return 4
		elseif attack >= 30 then
			return 3
		elseif attack >= 15 then
			return 2
		else
			return 1
		end
	end

	-- Speed (e.g. Boots of Haste, +20) -- previously invisible to this
	-- function entirely, since only armor/defense/attack were ever checked.
	-- Real binding: ItemType has no getSpeed(), speed lives in the
	-- Abilities struct (src/luaitemtype.cpp's luaItemTypeGetAbilities).
	local speed = itemType:getAbilities().speed
	if speed and speed > 0 then
		if speed >= 30 then
			return 4
		elseif speed >= 20 then
			return 3
		elseif speed >= 10 then
			return 2
		else
			return 1
		end
	end

	return 1 -- nothing at all (pure accessories with no armor value, e.g. plain rings)
end

-- Returns the item's power class, 1-7.
function RarityClass.getItemClass(itemId)
	if RarityClass.Overrides[itemId] then
		return RarityClass.Overrides[itemId]
	end

	local itemType = ItemType(itemId)
	local level = itemType:getMinReqLevel()
	if level and level > 0 then
		return classFromLevel(level)
	end

	return classFromFallbackStats(itemType)
end

-- Flat stats (Static/Damage/Duration value types) use the full curve;
-- Percent stats use a dampened curve (half the deviation from 1.0x) to
-- avoid runaway numbers like a 40% crit chance at Class 7.
local FLAT_MULTIPLIER = {
	[1] = 0.4, [2] = 0.6, [3] = 0.8, [4] = 1.0, [5] = 1.3, [6] = 1.6, [7] = 2.0,
}
local PERCENT_MULTIPLIER = {
	[1] = 0.7, [2] = 0.8, [3] = 0.9, [4] = 1.0, [5] = 1.15, [6] = 1.3, [7] = 1.5,
}

function RarityClass.getMultiplier(class, isPercent)
	local curve = isPercent and PERCENT_MULTIPLIER or FLAT_MULTIPLIER
	return curve[class] or 1.0
end
