-- Item Rarity system — core roll/apply engine. Ported from a third-party
-- download (author "Leo32") onto this fork. Items can roll 'rare'/'epic'/
-- 'legendary' with a bonus stat (or two); native stats (Attack/Defense/
-- ExtraDefense/Armor/HitChance/ShootRange/Charges) are written directly onto
-- the item instance, everything else is encoded as bracketed text in the
-- item's description ([Fire Resistance: +5%]) and re-parsed at combat time
-- by data/scripts/creaturescripts/rarity/rarity_combat.lua.
--
-- Namespaced under RarityStats (this project's convention — see BaoConfig/
-- BaoState/etc.) rather than the original's bare globals.
--
-- Item-targeting lists (the `items = {...}` fields below) are a real-item-
-- grounded rebuild for OUR items.xml, not the original download's ids (which
-- were verified ~85% wrong for this datapack — they pointed at furniture,
-- corpses, and blank placeholders here). Categories without a comment noting
-- a source survey are still using structural (weapon-type/armor) targeting
-- only and don't need a whitelist.

RarityStats = {}

local stats = { -- Define the attribute and their rolls
	[1] = { -- Attack
		attribute = {
			name = 'Attack',
			rare = {1, 3},
			epic = {4, 6},
			legendary = {7, 10},
		},
		value = "Static",
		base = ITEM_ATTRIBUTE_ATTACK
	},
	[2] = { -- Defense
		attribute = {
			name = 'Defense',
			rare = {1, 2},
			epic = {3, 4},
			legendary = {5, 6},
		},
		value = "Static",
		base = ITEM_ATTRIBUTE_DEFENSE
	},
	[3] = { -- Extra Defense
		attribute = {
			name = 'Extra Defense',
			rare = {1, 1},
			epic = {2, 3},
			legendary = {4, 5},
		},
		value = "Static",
		base = ITEM_ATTRIBUTE_EXTRADEFENSE
	},
	[4] = { -- Armor
		attribute = {
			name = 'Armor',
			rare = {1, 1},
			epic = {2, 3},
			legendary = {4, 5},
		},
		value = "Static",
		base = ITEM_ATTRIBUTE_ARMOR
	},
	[5] = { -- Accuracy
		attribute = {
			name = 'Accuracy',
			rare = {1, 5},
			epic = {6, 10},
			legendary = {11, 15},
		},
		value = "Percent",
		base = ITEM_ATTRIBUTE_HITCHANCE
	},
	[6] = { -- Range
		attribute = {
			name = 'Range',
			rare = {1, 1},
			epic = {2, 2},
			legendary = {3, 3},
		},
		value = "Static",
		base = ITEM_ATTRIBUTE_SHOOTRANGE
	},
	[7] = { -- Equipment with < 50 charges
		attribute = {
			name = 'Charges',
			rare = {5, 10},
			epic = {15, 20},
			legendary = {31, 35},
		},
		value = "Static",
		base = ITEM_ATTRIBUTE_CHARGES
	},
	[8] = { -- Equipment with >= 50 charges
		attribute = {
			name = 'Charges',
			rare = {100, 250},
			epic = {350, 500},
			legendary = {1000, 2000},
		},
		value = "Static",
		base = ITEM_ATTRIBUTE_CHARGES
	},
	[9] = { -- Time
		attribute = {
			name = 'Time',
			rare = {300000, 300000},
			epic = {900000, 900000},
			legendary = {2700000, 2700000},
		},
		value = "Duration",
		base = ITEM_ATTRIBUTE_DURATION
	},
	[10] = { -- Crit Chance — structural, no whitelist needed. Used to ALSO
		         -- carry a hand-picked ring/amulet whitelist (~half of all
		         -- rings and necklaces had it, the rest arbitrarily didn't --
		         -- exactly the "no reasonable reason" inconsistency the owner
		         -- flagged and asked to have generalized). Rings/amulets no
		         -- longer get Crit Chance under the new slot-based design
		         -- (see the Ring/Necklace block in rollRarity below) -- but
		         -- it was never ring/amulet-EXCLUSIVE: still fully reachable
		         -- structurally on every melee weapon (sword/axe/club/fist),
		         -- every distance weapon, and now spellbooks too. Only the
		         -- ring/amulet path was ever whitelist-gated.
		attribute = {
			name = 'Crit Chance',
			rare = {5, 10},
			epic = {10, 15},
			legendary = {16, 20},
		},
		value = "Percent",
	},
	[11] = { -- Speed — structural, no whitelist needed. Used to be a
		         -- hand-picked boots/legs/rings whitelist; now applies to
		         -- every item in those three slots via getSlotPosition()
		         -- bitmask checks in rollRarity (see the Ring/Necklace,
		         -- Legs, and Boots blocks below), replacing the old
		         -- arbitrary per-item list entirely.
		attribute = {
			name = 'Speed',
			rare = {5, 10},
			epic = {10, 20},
			legendary = {20, 30},
		},
		value = "Static",
	},
	[12] = { -- Fire Damage — real fire-elemental weapons across power tiers,
	         -- surveyed against our items.xml (elementfire attribute)
		attribute = {
			name = 'Enhanced Fire Damage',
			rare = {15, 30},
			epic = {30, 45},
			legendary = {45, 60},
		},
		value = "Damage",
		items = {
			660, 665, 661, 662, 674, 667,          -- early/mid fiery weapon line
			3280, 3320,                            -- fire sword, fire axe
			763,                                   -- flaming arrow
			22760,                                 -- impaler of the igniter
			29421,                                 -- summerblade
			30395,                                 -- cobra club
			36657, 49524, 43868, 43864, 47376,      -- endgame fire weapons
		}
	},
	[13] = { -- Ice Damage — real ice-elemental weapons, surveyed (elementice)
		attribute = {
			name = 'Enhanced Ice Damage',
			rare = {10, 15},
			epic = {15, 25},
			legendary = {25, 35},
		},
		value = "Damage",
		items = {
			679, 684, 680, 681, 693, 688,          -- early/mid icy weapon line
			3284,                                  -- ice rapier
			762,                                   -- shiver arrow
			30283,                                 -- ice hatchet
			29422,                                 -- winterblade
			39155,                                 -- naga sword
			49526, 34085, 34083, 29419, 47375,      -- endgame ice weapons
		}
	},
	[14] = { -- Energy Damage — real energy-elemental weapons, surveyed (elementenergy)
		attribute = {
			name = 'Enhanced Energy Damage',
			rare = {50, 75},
			epic = {100, 125},
			legendary = {200, 250},
		},
		value = "Damage",
		items = {
			801, 806, 795, 796, 810, 798,          -- early/mid energy weapon line
			761,                                   -- flash arrow
			27651,                                 -- gnome sword
			28725,                                 -- falcon mace
			43870, 49530, 28724, 34087, 47374,      -- endgame energy weapons
			39156,                                 -- naga axe
		}
	},
	[15] = { -- Fire Resistance — real fire-themed armor/shields, surveyed (absorbpercentfire)
		attribute = {
			name = 'Fire Resistance',
			rare = {2, 3},
			epic = {4, 6},
			legendary = {7, 10},
		},
		value = "Percent",
		items = {
			818, 827, 821, 826,                    -- magma set (early/mid)
			12599, 10201,                          -- mage's cap, dragon scale boots
			8053, 8058,                            -- fireborn giant armor, molten plate
			22518, 22519, 22520, 22530, 22534,      -- fireheart / firemind set
			10439, 39164, 50278,                   -- Zaoan robe, dawnfire sherwani, magma robe
			8039, 44624,                           -- dragon robe, mystical dragon robe
			28715, 28721, 28722,                   -- falcon coif/shield/escutcheon
			34093, 34094,                          -- soulstrider, soulshell
		}
	},
	[16] = { -- Ice Resistance — real ice-themed armor/shields, surveyed (absorbpercentice)
		attribute = {
			name = 'Ice Resistance',
			rare = {2, 3},
			epic = {4, 6},
			legendary = {7, 10},
		},
		value = "Percent",
		items = {
			819, 829, 823, 824,                    -- glacier set (early/mid)
			10200, 50193,                          -- crystal boots, jade conical hat
			51261, 8050,                           -- norcferatu bonehood, crystalline armor
			22527, 22528, 22529,                   -- frostheart set
			19366, 28720,                          -- icy culottes, falcon greaves
			8038, 44623,                           -- robe of the ice queen, arcane dragon robe
			31579, 39153,                          -- embrace of nature, arboreal crown
			8059,                                  -- frozen plate
		}
	},
	[17] = { -- Energy Resistance — real energy-themed armor/shields, surveyed (absorbpercentenergy)
		attribute = {
			name = 'Energy Resistance',
			rare = {2, 3},
			epic = {4, 6},
			legendary = {7, 10},
		},
		value = "Percent",
		items = {
			820, 828, 822, 825,                    -- lightning set (early/mid)
			8051,                                  -- voltage armor
			27647, 27648, 27649,                   -- gnome set
			22524, 22525,                          -- thunderheart set
			23476,                                 -- void boots
			10438, 39148,                          -- spellweaver's robe, spiritthorn helmet
			8040, 25779,                           -- velvet mantle, swan feather cloak
			44622, 30345,                          -- unerring dragon scale armor, enchanted pendulet
		}
	},
	[18] = { -- Earth Resistance — real earth/poison-themed armor, surveyed.
	         -- (!) This datapack has no absorbpercentearth attribute at all --
	         -- the "earth" theme is consistently expressed via
	         -- absorbpercentpoison instead; these candidates were picked on
	         -- that basis.
		attribute = {
			name = 'Earth Resistance',
			rare = {2, 3},
			epic = {4, 6},
			legendary = {7, 10},
		},
		value = "Percent",
		items = {
			813, 830, 812, 811,                    -- terra set (early/mid)
			19372, 8052,                           -- goo shell, swamplair armor
			8054, 22085,                           -- earthborn titan armor, fur armor
			22521, 22522, 22523,                   -- earthheart set
			16105, 16106,                          -- gill coat/legs
			8041, 31578,                           -- greenwood coat, bear skin
			29418, 31577,                          -- living armor, terra helmet
			30343,                                 -- enchanted sleep shawl
		}
	},
	[19] = { -- Physical Resistance — was a hand-picked "surveyed" items
		-- whitelist (real shields/helmets/heavy armor, absorbpercentphysical)
		-- from before the generic slot-based pools existed. Removed 2026-08-25:
		-- every one of those items is a Helmet, Legs, Body Armor, or Shield
		-- item, and all four of those now grant Physical Resistance
		-- unconditionally via the generic pools below (Helmet ~line 1261,
		-- Legs ~1215, Body Armor ~1231, Shield ~1036) -- keeping both meant
		-- this stat got inserted into available_stats twice for every one of
		-- those items, so both bonus slots on an Epic/Legendary roll could
		-- independently land on it, producing a duplicated
		-- "[Physical Resistance] (Physical Resistance)" roll (confirmed live
		-- on an epic plate shield, item 3410). No remaining item type needs
		-- the whitelist now that the generic pools fully subsume it.
		attribute = {
			name = 'Physical Resistance',
			rare = {2, 3},
			epic = {4, 6},
			legendary = {7, 10},
		},
		value = "Percent",
	},
	[20] = { -- Death Resistance — real dark/undead-themed armor, surveyed (absorbpercentdeath)
		attribute = {
			name = 'Death Resistance',
			rare = {2, 3},
			epic = {4, 6},
			legendary = {7, 10},
		},
		value = "Percent",
		items = {
			3356, 3383, 3384,                       -- devil helmet, dark armor/helmet
			3421, 3434, 3441,                       -- dark/vampire/bone shield
			5741,                                   -- skull helmet
			7993,                                   -- witchhunter's coat
			8057,                                   -- divine plate
			8061,                                   -- skullcracker armor
			8062,                                   -- robe of the underworld
			13994,                                  -- depth lorica
			32585,                                  -- burial shroud
			49531, 49532,                           -- maliceforged helmet, hellstalker visor
			50260,                                  -- death oyoroi
			51260, 51264,                           -- norcferatu skullguard/bonecloak
		}
	},
	[21] = { -- Spell Damage — structural (wands only, see the Wands and Rods
		         -- branch in rollRarity). Used to also carry a hand-picked
		         -- ring/amulet whitelist; removed as part of generalizing
		         -- rings/amulets to a fixed slot-based pool that deliberately
		         -- doesn't include Spell Damage (see owner's ring/amulet
		         -- spec) -- still fully reachable on wands, unaffected.
		attribute = {
			name = 'Spell Damage',
			rare = {3, 5},
			epic = {8, 10},
			legendary = {15, 20},
		},
		value = "Percent",
	},
	[22] = { -- Multi Shot — structural (distance weapons), no whitelist needed
		attribute = {
			name = 'Multi Shot',
			rare = {1, 1},
			epic = {2, 2},
			legendary = {3, 3},
		},
		value = "Static"
	},
	[23] = { -- Stun Chance — structural, no whitelist needed
		attribute = {
			name = 'Stun Chance',
			rare = {3, 5},
			epic = {6, 10},
			legendary = {11, 15},
		},
		value = "Percent"
	},
	[24] = { -- Mana Shield — structural, no whitelist needed
		attribute = {
			name = 'Mana Shield',
			rare = {5, 10},
			epic = {11, 20},
			legendary = {21, 30},
		},
		value = "Percent"
	},
	[25] = { -- Sword Skill — structural (sword weapons); items list lets a
	         -- non-weapon item opt in too, none needed for launch
		attribute = {
			name = 'Sword Skill',
			rare = {1, 2},
			epic = {3, 5},
			legendary = {6, 10},
		},
		value = "Static"
	},
	[26] = { -- Axe Skill — structural
		attribute = {
			name = 'Axe Skill',
			rare = {1, 2},
			epic = {3, 5},
			legendary = {6, 10},
		},
		value = "Static"
	},
	[27] = { -- Club Skill — structural
		attribute = {
			name = 'Club Skill',
			rare = {1, 2},
			epic = {3, 5},
			legendary = {6, 10},
		},
		value = "Static"
	},
	[28] = { -- Melee Skills — real armor/shield pieces (not weapons; those get
	         -- their specific Sword/Axe/Club skill structurally), surveyed
		attribute = {
			name = 'Melee Skills',
			rare = {1, 2},
			epic = {3, 5},
			legendary = {6, 10},
		},
		value = "Static",
		items = {
			3369, 3370,                             -- warrior helmet, knight armor
			9377, 14042,                            -- shield of the white knight, warrior's shield
			22518, 22519, 22520,                    -- fireheart cuirass/hauberk/platemail
			44642,                                  -- stoic iks culet
			49531,                                  -- maliceforged helmet
			28720,                                  -- falcon greaves
			44621,                                  -- dauntless dragon scale armor
			34157,                                  -- lion plate
			51262,                                  -- norcferatu tuskplate
			39147,                                  -- spiritthorn armor
			43876,                                  -- sanguine legs
		}
	},
	[29] = { -- Distance Skill — structural
		attribute = {
			name = 'Distance Skill',
			rare = {1, 2},
			epic = {3, 5},
			legendary = {6, 10},
		},
		value = "Static"
	},
	[30] = { -- Shield Skill — structural
		attribute = {
			name = 'Shield Skill',
			rare = {1, 2},
			epic = {3, 5},
			legendary = {6, 10},
		},
		value = "Static"
	},
	[31] = { -- Magic Level — real caster-flavored headgear/robes/spellbooks, surveyed
		attribute = {
			name = 'Magic Level',
			rare = {1, 2},
			epic = {3, 5},
			legendary = {6, 10},
		},
		value = "Static",
		items = {
			3574, 12599,                            -- mystic turban, mage's cap (early-game)
			7991, 7992, 9653,                       -- magician's robe, mage hat, witch hat
			3567,                                   -- blue robe
			50257,                                  -- plain monk robe
			25699,                                  -- wooden spellbook
			8072, 8073,                             -- spellbook of enlightenment/warding
			14769,                                  -- spellbook of ancient arcana
			22755, 34153, 20090,                    -- book of lies, lion spellbook, umbral master spellbook
			39151, 39153,                           -- arcanomancer regalia, arboreal crown
			34093, 34095, 34096,                    -- soulstrider/soulmantle/soulshroud
			22534, 39164,                           -- firemind raiment, dawnfire sherwani
			44619,                                  -- stoic iks cuirass
			44623, 44624,                           -- arcane/mystical dragon robe
		}
	},
	[32] = { -- Max Health (+flat) — real armor spread across the full power
	         -- curve (no native max-hitpoints attribute exists in our
	         -- items.xml to anchor to, so this is slot/theme verified)
		attribute = {
			name = 'Max Health',
			rare = {30, 60},
			epic = {80, 120},
			legendary = {150, 250},
		},
		value = "Static",
		items = {
			3355, 3352,                             -- leather/chain helmet (starter)
			3378, 3358,                             -- studded/chain armor (low-mid)
			3368, 3380, 3370,                       -- winged helmet, noble armor, knight armor (mid)
			3360, 3386,                             -- golden armor, dragon scale mail (mid-high)
			13993, 3388, 3366,                      -- ornate chestplate, demon armor, magic plate armor (high)
			28719, 44621, 39147,                    -- falcon plate, dauntless dragon scale, spiritthorn armor (endgame)
		}
	},
	[33] = { -- Max Mana (+flat) — real mage-vocation-locked headgear/robes/capes
		attribute = {
			name = 'Max Mana',
			rare = {30, 60},
			epic = {80, 120},
			legendary = {150, 250},
		},
		value = "Static",
		items = {
			3573,                                   -- magician hat (starter)
			7992, 7991, 9653,                       -- mage hat, magician's robe, witch hat
			10438, 10439,                           -- spellweaver's robe, Zaoan robe
			8043, 8037, 8038, 8042,                 -- focus cape, dark lord's cape, robe of the ice queen, spirit cloak
			44623, 44624,                           -- arcane/mystical dragon robe (endgame)
		}
	},
	[34] = { -- Max Health % — structural, no whitelist needed
		attribute = {
			name = 'Max Health',
			rare = {1, 3},
			epic = {4, 6},
			legendary = {7, 10},
		},
		value = "Percent"
	},
	[35] = { -- Max Mana % — structural, no whitelist needed
		attribute = {
			name = 'Max Mana',
			rare = {1, 3},
			epic = {4, 6},
			legendary = {7, 10},
		},
		value = "Percent",
	},
	[37] = { -- Life Leech — structural (melee weapons), no whitelist needed
		attribute = {
			name = 'Life Leech',
			rare = {3, 5},
			epic = {6, 10},
			legendary = {11, 20},
		},
		value = "Percent"
	},
	[38] = { -- Mana Leech Chance — structural (wands), no whitelist needed
		attribute = {
			name = 'Mana Leech Chance',
			rare = {3, 5},
			epic = {6, 10},
			legendary = {11, 20},
		},
		value = "Percent"
	},
	[36] = { -- Rebirth — ultra-rare Legendary-only party-safety bonus.
	         -- RESTRUCTURED from a 5-item hand-picked whitelist to a fully
	         -- structural rule, same generalization pass as Hold the Line/
	         -- Chain Heal above: minClass = 5 gates it to Class 5+, and the
	         -- Wands and Rods block below only ever offers this candidate on
	         -- WEAPON_WAND items whose name contains "rod" (every real rod in
	         -- items.xml is a Druid-vocation weapon; wands are Sorcerer-only,
	         -- so this is already Druid-exclusive without a separate
	         -- vocation check). Any Class 5+ Druid rod qualifies now, not
	         -- just the 5 that existed when this was first built. See
	         -- data/scripts/creaturescripts/rarity/rarity_rebirth.lua and
	         -- data/lib/rarity/rarity_rebirth.lua for the actual mechanic --
	         -- this entry only controls whether/how often it can roll onto an
	         -- eligible rod in the first place.
		attribute = {
			name = 'Rebirth',
		},
		value = "Flag", -- no numeric magnitude, just a bracket marker
		minTier = 3, -- Legendary only
		rollChance = 250, -- secondary ~2.5% gate (out of 10000), independent of
		                  -- and stacked with the normal tier odds -- see
		                  -- BONUS_BACKLOG.md for the full odds breakdown
		minClass = 5,
	},
	[39] = { -- Hold the Line — Knight body armor, Class 4+. Incoming damage
	         -- reduction that ramps up the longer the wearer stands on the
	         -- same tile, capped at this rolled %, resetting instantly on
	         -- any movement. Numbers are placeholders -- balancing pass
	         -- still pending. See applyHoldTheLine() in rarity_combat.lua
	         -- for the ramp mechanic.
	         --
	         -- RESTRUCTURED from a hand-picked item whitelist (itself already
	         -- corrected once, from 7 items up to 25 after a bad initial
	         -- survey) to a fully structural rule: minTier -> minClass below
	         -- gates it to Class 4+, and rollRarity's Armor block only ever
	         -- offers this candidate on Knight-vocation-locked body armor in
	         -- the first place (bit.band(slotPos, SLOTP_ARMOR) plus a
	         -- vocation string check). Same owner-driven generalization pass
	         -- that redid Crit Chance/Speed/Spell Damage above -- no more
	         -- per-item lists for slot-shaped bonuses that should just apply
	         -- to "every Knight body armor," full stop.
		attribute = {
			name = 'Hold the Line',
			rare = {5, 10},
			epic = {10, 15},
			legendary = {15, 25},
		},
		value = "Percent",
		minClass = 4,
	},
	[40] = { -- Prism Heart — unique Paladin quiver bonus. Class 4+ only, real
	         -- items.xml survey of Paladin-locked quivers found no quiver
	         -- between level 100-149, so the whitelist starts at Class 5.
	         -- Converts this % of the wearer's own physical damage into a
	         -- random element every hit (chosen fresh each swing), reusing
	         -- elementalDmg() exactly as it exists for Enhanced Fire/Ice/
	         -- Energy Damage -- see applyPrismHeart() in rarity_combat.lua.
	         -- Numbers are placeholders -- balancing pass still pending.
		attribute = {
			name = 'Prism Heart',
			rare = {10, 15},
			epic = {15, 25},
			legendary = {25, 35},
		},
		value = "Percent",
		items = {
			35524, -- jungle quiver (level 150, Class 5)
			45644, -- candy-coated quiver (level 200, Class 5)
			36666, -- eldritch quiver (level 250, Class 5)
			39160, -- naga quiver (level 250, Class 5)
			39150, -- alicorn quiver (level 400, Class 7)
		}
	},
	[41] = { -- Spell Echo — unique Sorcerer wand bonus. Class 4+ only, real
	         -- items.xml survey found no Sorcerer-locked wand between level
	         -- 100-149 in this datapack, so the whitelist starts at Class 5.
	         -- Wand hits have a fixed per-cast chance (SPELL_ECHO_TRIGGER_
	         -- CHANCE in rarity_combat.lua, currently a placeholder) to
	         -- repeat ~400ms later at this rolled % of the original hit's
	         -- damage. Numbers are placeholders -- balancing pass pending.
	         -- See statChange's ORIGIN_SPELL branch in rarity_combat.lua.
	         --
	         -- Full re-audit (every wand item in items.xml mentioning
	         -- Sorcerer vocation, ~34 candidates) done after the owner
	         -- couldn't roll Spell Echo on Sanguine Coil -- the original
	         -- survey below missed 8 real Class 5+ entries. Deliberately
	         -- still excludes deepling ceremonial dagger/deepling fork/
	         -- energized limb (all Class 5, levels 180/230/180) -- those are
	         -- dual Sorcerer+Druid wands, not Sorcerer-exclusive, and every
	         -- other unique bonus in this system (Rebirth/Hold the
	         -- Line/Prism Heart) is single-vocation-locked.
		attribute = {
			name = 'Spell Echo',
			rare = {15, 25},
			epic = {25, 35},
			legendary = {35, 50},
		},
		value = "Percent",
		items = {
			27457, -- wand of destruction (level 200, Class 5)
			34152, -- lion wand (level 220, Class 5)
			35522, -- jungle wand (level 150, Class 5)
			28717, -- falcon wand (level 300, Class 6)
			36668, -- eldritch wand (level 250, Class 5)
			36669, -- gilded eldritch wand (level 250, Class 5)
			39162, -- naga wand (level 250, Class 5)
			30399, -- cobra wand (level 270, Class 6)
			49528, -- inferniarch wand (level 300, Class 6)
			49882, -- rending inferniarch wand (level 300, Class 6)
			49883, -- draining inferniarch wand (level 300, Class 6)
			49884, -- siphoning inferniarch wand (level 300, Class 6)
			47372, -- amber wand (level 330, Class 6)
			34090, -- soultainter (level 400, Class 7)
			43882, -- sanguine coil (level 600, Class 7)
			43883, -- grand sanguine coil (level 600, Class 7)
		}
	},
	[42] = { -- Dodge Chance — boots. NOT the native Forge "Ruse" mechanic
	         -- (item:getDodgeChance(), checked in src/combat.cpp:1200-1206)
	         -- -- that's gated behind item:getTier() > 0 (the native Forge
	         -- upgrade tier), which rarity-rolled items never set, and
	         -- setting it ourselves risks unintended interaction with
	         -- Forge's other tier-driven procs (Fatal/Momentum/
	         -- Transcendence) that haven't been audited. Fully custom
	         -- instead, same bracket-text pattern as every other non-native
	         -- stat here -- see applyDodgeChance() in rarity_combat.lua.
	         -- Numbers are placeholders -- balancing pass pending.
		attribute = {
			name = 'Dodge Chance',
			rare = {2, 4},
			epic = {4, 7},
			legendary = {7, 12},
		},
		value = "Percent",
	},
	[43] = { -- Fortune — rings/amulets. Scales up gold-type currency counts
	         -- (gold coin 3031, platinum coin 3035, crystal coin 3043) when
	         -- loot is created. See applyFortune() in rarity_loot_drop.lua.
	         -- Numbers are placeholders -- balancing pass pending.
		attribute = {
			name = 'Fortune',
			rare = {5, 10},
			epic = {10, 20},
			legendary = {20, 35},
		},
		value = "Percent",
	},
	[44] = { -- Magic Resistance — legs, shields (non-spellbook). One
	         -- consolidated resistance roll covering the 5 elemental damage
	         -- types this rarity system tracks (Fire/Ice/Energy/Earth/
	         -- Death) at once -- deliberately NOT Physical, which stays its
	         -- own separate stat on both slots per the owner's spec, and
	         -- deliberately weaker than Body Armor's 6 separate Resistance
	         -- rolls -- one roll, one number, broader but shallower. See
	         -- statChange's Magic Resistance branch in rarity_combat.lua.
	         -- Numbers are placeholders -- balancing pass pending.
		attribute = {
			name = 'Magic Resistance',
			rare = {1, 2},
			epic = {2, 4},
			legendary = {4, 6},
		},
		value = "Percent",
	},
	[45] = { -- Thorn — legs (Knight/Paladin-locked only), shields (any,
	         -- except spellbooks). Reflects this % of an incoming hit back
	         -- at the attacker -- this is backlog bonus #3 ("Reflect"),
	         -- renamed. See applyThorn() in rarity_combat.lua. Numbers are
	         -- placeholders -- balancing pass pending.
		attribute = {
			name = 'Thorn',
			rare = {3, 6},
			epic = {6, 10},
			legendary = {10, 15},
		},
		value = "Percent",
	},
	[46] = { -- Adrenaline Rush — boots, Class 3+, ALL vocations (unlike
	         -- Rebirth/Hold the Line/Prism Heart/Spell Echo, this one is not
	         -- vocation-gated -- gated by minClass only, matching the
	         -- owner's explicit "for all vocations" instruction). Temporary
	         -- speed+attack buff on kill -- this is backlog bonus #2
	         -- ("Adrenaline Rush"). Trigger fires from the same
	         -- Monster:onDropLoot hook rarity_loot_drop.lua already uses
	         -- (corpse:getCorpseOwner() = the killer), see
	         -- applyAdrenalineRush() there and its statChange hook in
	         -- rarity_combat.lua. Numbers/duration are placeholders --
	         -- balancing pass pending.
		attribute = {
			name = 'Adrenaline Rush',
			rare = {5, 10},
			epic = {10, 15},
			legendary = {15, 25},
		},
		value = "Percent",
		minClass = 3,
	},
	[47] = { -- Capacity — quivers. Real carry-weight bonus, same mechanism
	         -- imbuements already use for this (CONDITION_PARAM_STAT_CAPACITY,
	         -- confirmed real -- data/XML/imbuements.xml's "Increase
	         -- Capacity" category grants 150/300/500oz across its 3 tiers,
	         -- used to calibrate these ranges so Legendary sits a bit above
	         -- the best imbuement tier). Value is raw oz, not a percent --
	         -- imbuements' own "capacity" effect type is raw oz too, no x100
	         -- scaling. See rollCondition's new [13] entry above for the
	         -- CONDITION_PARAM_STAT_CAPACITY wiring. Numbers are
	         -- placeholders -- balancing pass pending.
		attribute = {
			name = 'Capacity',
			rare = {100, 200},
			epic = {200, 400},
			legendary = {400, 700},
		},
		value = "Static",
	},
	[48] = { -- Armor Breaker — crossbows only (ammotype="bolt"/AMMO_BOLT).
	         -- Ignores this % of the target's Physical Resistance for hits
	         -- from this specific attacker. Real constraint, stated plainly:
	         -- this can only ever ignore the CUSTOM (rarity-granted)
	         -- Physical Resistance this Lua system itself applies -- a
	         -- creature's native armor value is already baked into the
	         -- damage by the C++ engine before onHealthChange/statChange
	         -- ever runs, so there's no Lua hook that can retroactively
	         -- un-apply that (same category of hard limit as Rebirth's
	         -- "can't hold open a native death penalty"). Still a real,
	         -- useful effect against anything wearing rarity-rolled
	         -- resistance gear, which is the entire point of a system built
	         -- around rolled bonuses. See getArmorBreakerPercent() in
	         -- rarity_combat.lua. Numbers are placeholders -- balancing pass
	         -- pending.
		attribute = {
			name = 'Armor Breaker',
			rare = {5, 10},
			epic = {10, 20},
			legendary = {20, 35},
		},
		value = "Percent",
	},
	[49] = { -- Pin Down — crossbows only. Chance to root the target in
	         -- place briefly on hit -- real crowd control, distinct from
	         -- Stun Chance (a silence placeholder, not a movement lock).
	         -- Uses the exact same Creature:setMovementBlocked() binding
	         -- already proven working for Rebirth's downed-player state,
	         -- just applied to whatever was hit (including monsters) as
	         -- real CC instead. See applyPinDown()/clearPinDown() in
	         -- rarity_combat.lua for the refresh-safe expiry handling.
	         -- Numbers/duration are placeholders -- balancing pass pending.
		attribute = {
			name = 'Pin Down',
			rare = {5, 10},
			epic = {10, 15},
			legendary = {15, 25},
		},
		value = "Percent",
	},
	[50] = { -- Chain Heal — rods only (not wands), Class 3+. This is backlog
	         -- bonus #15. Rolled value is the % chance, per heal cast, that
	         -- a reduced-power copy of the same heal also jumps to another
	         -- injured party member near the healed target -- same "rolled
	         -- value IS the trigger chance" convention as Stun Chance/Dodge
	         -- Chance/Pin Down, not a magnitude. See the Chain Heal branch in
	         -- statChange's ORIGIN_SPELL/COMBAT_HEALING handling in
	         -- rarity_combat.lua. Numbers are placeholders -- balancing pass
	         -- pending.
		attribute = {
			name = 'Chain Heal',
			rare = {10, 15},
			epic = {15, 20},
			legendary = {20, 30},
		},
		value = "Percent",
		minClass = 3,
	},
	[51] = { -- Juggernaut — body armor, Knight/Paladin-locked, Class 4+.
	         -- Backlog bonus #12. Rolled value is a per-attacker incoming-
	         -- damage reduction: the wearer's damage taken drops further the
	         -- more creatures are simultaneously targeting them (real count,
	         -- via Creature:getTarget(), not a spectator-count
	         -- approximation -- confirmed real/registered in
	         -- BONUS_BACKLOG.md). See applyJuggernaut() in
	         -- rarity_combat.lua. Numbers/cap are placeholders -- balancing
	         -- pass pending.
		attribute = {
			name = 'Juggernaut',
			rare = {1, 2},
			epic = {2, 3},
			legendary = {3, 5},
		},
		value = "Percent",
		minClass = 4,
	},
	[52] = { -- Grave Tithe — helmets, rings, necklaces, Class 4+, all
	         -- vocations. Backlog bonus #1. +% experience from monster
	         -- kills while worn -- sums across all 3 slots if rolled on
	         -- more than one, same additive-stacking convention Crit
	         -- Chance/Thorn already use. Piggybacks on the existing
	         -- onGainExperience event chain rather than touching
	         -- default_onGainExperience.lua -- see
	         -- data/scripts/eventcallbacks/player/rarity_grave_tithe.lua.
	         -- Numbers are placeholders -- balancing pass pending.
		attribute = {
			name = 'Grave Tithe',
			rare = {3, 5},
			epic = {5, 10},
			legendary = {10, 15},
		},
		value = "Percent",
		minClass = 4,
	},
	[53] = { -- Cleave — two-handed Knight weapons (Sword/Club/Axe), Class
	         -- 2+. Backlog bonus #4. Rolled value is the % chance, per
	         -- melee hit, to also hit one additional nearby monster for
	         -- reduced damage -- Multi Shot's spectator/shuffle logic,
	         -- reused for melee instead of gated behind an ammo slot. See
	         -- the Cleave branch in statChange's RANGED/MELEE handling in
	         -- rarity_combat.lua. Numbers are placeholders -- balancing
	         -- pass pending.
		attribute = {
			name = 'Cleave',
			rare = {10, 15},
			epic = {15, 25},
			legendary = {25, 35},
		},
		value = "Percent",
		minClass = 2,
	},
	[54] = { -- Guardian's Pact — helmets, Mage (Sorcerer/Druid) and Paladin-
	         -- locked, Class 4+. Backlog bonus #7. Rolled value is the %
	         -- chance, per hit taken, to redirect a portion of that damage
	         -- away from the wearer into a heal for the most-injured nearby
	         -- party member -- reduces damage taken AND heals an ally in
	         -- the same proc, not just one or the other. See
	         -- applyGuardiansPact() in rarity_combat.lua. Numbers are
	         -- placeholders -- balancing pass pending.
		attribute = {
			name = "Guardian's Pact",
			rare = {5, 10},
			epic = {10, 15},
			legendary = {15, 20},
		},
		value = "Percent",
		minClass = 4,
	},
	[55] = { -- Glass Cannon — Mage (Sorcerer/Druid) body armor, Class 4+.
	         -- Backlog bonus #6. The one deliberately NOT-pure-upside stat
	         -- in this system: the same rolled % boosts BOTH the wearer's
	         -- own outgoing damage AND their incoming damage taken,
	         -- always-on while equipped (no trigger chance). Applied on the
	         -- attacker side uniformly (RANGED/MELEE/SPELL alike, same
	         -- placement as Adrenaline Rush) and on the defender side LAST
	         -- -- after Hold the Line/Dodge Chance/Juggernaut/Guardian's
	         -- Pact -- per owner's explicit call, so the extra damage taken
	         -- is real and felt, not quietly absorbed by every other rolled
	         -- reduction first. See rarity_combat.lua's Glass Cannon
	         -- handling (attacker-side block + applyGlassCannonIncoming()).
	         -- Numbers are placeholders -- balancing pass pending.
		attribute = {
			name = 'Glass Cannon',
			rare = {5, 10},
			epic = {10, 20},
			legendary = {20, 30},
		},
		value = "Percent",
		minClass = 4,
	},
}
RarityStats.stats = stats

-- extras.xml (Dawnbreaker/Rainbow Shield) was skipped entirely per decision —
-- all 11 of its item ids collide with real, unrelated items in our
-- items.xml, so there is nothing here to blacklist from rolling.
local cannotroll = {}

-- Check if item can be rolled (for use outside of this lib, actions, quests etc)
function RarityStats.rollCheck(item)
	local itemtype = ItemType(item:getId())
	local itemid = itemtype:getId()
	if table.contains(cannotroll, itemid) then
		return false
	end
	for _, v in pairs(stats) do
		if v.items ~= nil then
			if table.contains(v.items, itemid) then
				return true
			end
		end
	end
	local weapontype = itemtype:getWeaponType()
	if weapontype > 0 then
		if itemtype:isStackable() then
			return false
		else
			return true
		end
	elseif itemtype:getArmor() > 0 then
		return true
	end
	return false
end

-- Get duration literally
local function rollBaseDuration(item)
	local it_id = item:getId()
	local tid = ItemType(it_id):getTransformEquipId()
	if tid > 0 then
		item:transform(tid)
		local vx = item:getAttribute(ITEM_ATTRIBUTE_DURATION)
		item:transform(it_id)
		return vx
	end
	return 0
end

-- Get base/stock stat
local function rollBase(item, attr)
	local id = ItemType(item:getId())
	local v = {
		[ITEM_ATTRIBUTE_ATTACK] = id:getAttack(),
		[ITEM_ATTRIBUTE_DEFENSE] = id:getDefense(),
		[ITEM_ATTRIBUTE_EXTRADEFENSE] = id:getExtraDefense(),
		[ITEM_ATTRIBUTE_ARMOR] = id:getArmor(),
		[ITEM_ATTRIBUTE_HITCHANCE] = id:getHitChance(),
		[ITEM_ATTRIBUTE_SHOOTRANGE] = id:getShootRange(),
		[ITEM_ATTRIBUTE_CHARGES] = id:getCharges(),
		[ITEM_ATTRIBUTE_DURATION] = rollBaseDuration(item)
	}
	return v[attr]
end

-- Dormant sentinel: repurposes one more value of the same native Tier byte
-- (see the client-marker comment further down) that 1-4 already carry for
-- Scarce/Adept/Superior/Prime. A Dormant item hasn't rolled its actual
-- tier/stats yet -- see the "not skipDormant" branch below -- that only
-- happens live when a Dormant Waker is used on it (data/scripts/
-- actions/items/identifying_lens.lua, item 39241), which reads the target's
-- tier directly rather than needing anything stamped onto the item itself.
-- The client renders 5 as sparkles instead of a real tier color/marker
-- (UIItem::drawSelf, Item::draw).
RarityStats.DORMANT_TIER = 5

-- Roll a container or item. skipDormant=true bypasses the Dormant reveal
-- flow entirely and applies the roll directly (GM /roll <tier> testing
-- convenience, see data/scripts/talkactions/god/rarity/roll.lua) -- real
-- gameplay sources (monster loot, loot chests, boss soul bags) never pass
-- this, so players only ever see rolled items go through Dormant.
function RarityStats.rollRarity(container, forced, skipDormant)
	-- Tiers. slotCount is fixed per tier (always fully consumed, no longer
	-- probabilistic) -- Scarce always has exactly 1 bonus slot, Adept 2,
	-- Superior 3, Prime 4. Each slot independently rolls locked-or-open via
	-- lockChance (out of 10000), decided per slot, not as a hand-authored
	-- distribution over exact locked-counts. Locked bonuses display in
	-- [brackets], open bonuses in (parens) -- see the stat_desc-building
	-- loop below. rollThreshold is the old chance[1] value, unchanged --
	-- still the natural (unforced) roll odds for landing this tier at all.
	--
	-- Renamed 2026-08-25 (was rare/epic/legendary) and Prime added as a new
	-- 4th tier above Superior, per owner spec -- "the absolute most rare"
	-- tier, one more bonus slot than Superior. Internal field names on each
	-- stat's `attribute` table (rare/epic/legendary) were NOT renamed to
	-- match -- those are never player-visible, only `tiers[i].prefix` (used
	-- to build the actual item article/description text) is. Magnitude
	-- lookup below is by tier INDEX now, not by string-matching prefix
	-- against a hardcoded tier, so this table is the only place a tier
	-- ever needs to be added/renamed.
	--
	-- TESTING RATES (owner request, 2026-08-25): bumped over the tuned live
	-- odds (750/375/200/100) so rarity items surface constantly while
	-- trying things out. Dial back to those values (or re-balance properly)
	-- before this is meant to be the real live rate.
	local tiers = {
		[1] = { prefix = 'scarce',   rollThreshold = 5000, slotCount = 1, lockChance = 10000 }, -- live 750 (7.5%); always locked
		[2] = { prefix = 'adept',    rollThreshold = 2500, slotCount = 2, lockChance = 5000  }, -- live 375 (3.75%); 50% locked/slot
		[3] = { prefix = 'superior', rollThreshold = 1000, slotCount = 3, lockChance = 6000  }, -- live 200 (2%); 60% locked/slot
		[4] = { prefix = 'prime',    rollThreshold = 700,  slotCount = 4, lockChance = 7000  }, -- live 100 (1%); 70% locked/slot
	}
	-- Prime has no hand-authored magnitude range on any stat (~50+ stats
	-- would need one) -- per owner spec, formulaically scaled up from
	-- Superior's range instead. One constant to tune later rather than
	-- hand-balancing every stat individually.
	local PRIME_MAGNITUDE_SCALE = 1.3
	-- Index-based, NOT string-matched against a specific tier's prefix (the
	-- old code only ever special-cased tiers[3]/tiers[2] by name, silently
	-- falling through to the Rare range for anything else -- would have
	-- quietly broken Prime the same way). Field names on `attribute` stay
	-- rare/epic/legendary (internal only, see note above) mapped by index.
	local MAGNITUDE_KEY_BY_TIER = {'rare', 'epic', 'legendary'}
	local rares = 0
	local available_stats = {}
	local it_u = container
	local it_id = ItemType(it_u:getId())
	-- Computed up front (used to be computed later, only for magnitude
	-- scaling) so structural stat-eligibility checks below can also gate on
	-- it directly (minClass, e.g. Hold the Line/Adrenaline Rush), the same
	-- way minTier already gates on rolled tier.
	local itemClass = RarityClass.getItemClass(it_u:getId())
	-- Quivers are ITEM_GROUP_CONTAINER (they hold ammo -- containersize in
	-- items.xml), so isContainer() is true for them same as a backpack. Found
	-- via live testing: without this exclusion, a quiver falls into the
	-- "recurse into contents" branch below instead of ever being evaluated as
	-- an item in its own right, so it can never roll its own bonus (Prism
	-- Heart, stats[40]) -- /roll on an empty or non-empty quiver silently does
	-- nothing regardless of forced tier, since available_stats never gets
	-- populated for the quiver itself. Treat it as a normal equippable item
	-- instead; its contents (ammo) were never meant to be rolled anyway.
	local isQuiver = it_id:getWeaponType() == WEAPON_QUIVER
	if it_u:isContainer() and not isQuiver then
		local h = it_u:getItemHoldingCount()
		if h > 0 then
			local i = 1
			while i <= h do
				local bagitem = it_u:getItem(i - 1)
				if bagitem:isContainer() then
					h = h - bagitem:getItemHoldingCount()
				end
				local manualroll = forced or false
				local crares = RarityStats.rollRarity(bagitem, manualroll, skipDormant)
				rares = rares + crares
				i = i + 1
			end
		end
	else
		if not it_id:isStackable() then
			local wp = it_id:getWeaponType()
			if wp > 0 then
				-- Shields
				if wp == WEAPON_SHIELD then
					table.insert(available_stats, stats[2])  -- Defense
					table.insert(available_stats, stats[30]) -- Skill Shield

					-- Spellbooks are mechanically WEAPON_SHIELD (same
					-- off-hand slot) but thematically caster gear, not a
					-- combat shield -- items.xml never declares this
					-- distinction as an attribute (confirmed by spot-check:
					-- several spellbooks don't even share the same vocation
					-- lock, e.g. "Dragha's spellbook" has none at all), so
					-- name is the only reliable signal. Per owner's spec:
					-- spellbooks get their own caster pool instead of the
					-- shield pool (Magic Resistance/Physical Resistance/
					-- Thorn would be a strange fit on a book anyway).
					local itemName = (it_id:getName() or ""):lower()
					if itemName:find("spellbook") then
						table.insert(available_stats, stats[31]) -- Magic Level
						table.insert(available_stats, stats[11]) -- Speed
						table.insert(available_stats, stats[10]) -- Crit Chance
					else
						table.insert(available_stats, stats[19]) -- Physical Resistance
						table.insert(available_stats, stats[44]) -- Magic Resistance
						table.insert(available_stats, stats[45]) -- Thorn
					end

				-- Distance Items
				elseif wp == WEAPON_DISTANCE then
					table.insert(available_stats, stats[1])  -- Attack
					table.insert(available_stats, stats[6])  -- Range
					table.insert(available_stats, stats[10]) -- Critical Chance
					table.insert(available_stats, stats[29]) -- Skill Distance
					-- Multi Shot's trigger in rarity_combat.lua only ever
					-- checks CONST_SLOT_AMMO -- so it's excluded here for
					-- anything without a real ammotype (spears, throwing
					-- stars/knives, snowballs -- all held directly in the
					-- weapon hand per items.xml, ammoType AMMO_NONE). Rolling
					-- it onto one of those would be a permanently dead stat,
					-- since it could never pass that check. Confirmed via
					-- items.cpp: ammoType is set ONLY from an explicit
					-- ammotype="..." XML attribute, defaulting to AMMO_NONE
					-- otherwise -- not inferred from weaponType/shootType, so
					-- this check is exact, not a guess.
					if it_u:getId() ~= 5907 and it_id:getAmmoType() ~= AMMO_NONE then -- Slingshot
						table.insert(available_stats, stats[22]) -- Multi Shot
					end

					-- Crossbow-only, on top of the base distance pool above.
					-- ammotype="bolt" (AMMO_BOLT) is the real, reliable
					-- native signal that distinguishes a crossbow from a
					-- bow -- confirmed directly against items.xml (royal
					-- crossbow/plain crossbow both declare ammotype="bolt",
					-- plain bow declares ammotype="arrow"). Diamond Arrow
					-- already makes bows an easy pick on their own merits;
					-- these two are meant to give crossbows their own real
					-- identity rather than just being a worse bow.
					if it_id:getAmmoType() == AMMO_BOLT then
						table.insert(available_stats, stats[48]) -- Armor Breaker
						table.insert(available_stats, stats[49]) -- Pin Down
					end

				-- Wands and Rods
				elseif wp == WEAPON_WAND then
					table.insert(available_stats, stats[21]) -- Spell Damage
					table.insert(available_stats, stats[33]) -- Max Mana
					table.insert(available_stats, stats[31]) -- Magic Level
					table.insert(available_stats, stats[38]) -- Mana Leech Chance

					-- Chain Heal (stats[50]) -- rods only, not wands. Both
					-- share WEAPON_WAND natively (same distinction problem
					-- as Spellbook vs Shield above), so name is the
					-- reliable signal -- every real rod in items.xml is
					-- literally named "<something> rod" (terra rod, rod of
					-- destruction, lion rod, etc.), checked against the
					-- full wand/rod list before relying on it. minClass=3
					-- filters below Class 3 in the post-filter loop.
					if (it_id:getName() or ""):lower():find("rod") then
						table.insert(available_stats, stats[50]) -- Chain Heal
						table.insert(available_stats, stats[36]) -- Rebirth (minClass=5 filters below Class 5)
					end

				-- Sword, Clubs and Axes
				elseif table.contains({WEAPON_SWORD, WEAPON_CLUB, WEAPON_AXE}, wp) then
					if wp == WEAPON_SWORD then
						table.insert(available_stats, stats[25]) -- Sword Skill
					elseif wp == WEAPON_AXE then
						table.insert(available_stats, stats[26]) -- Axe Skill
					elseif wp == WEAPON_CLUB then
						table.insert(available_stats, stats[27]) -- Club Skill
					end

					if it_id:getAttack() > 0 then
						table.insert(available_stats, stats[1]) -- Attack
					end

					-- Defense on two-handed Knight weapons removed per
					-- owner's request (felt like a wasted roll on a weapon
					-- slot -- see the conversation for replacement
					-- candidates still being decided). Extra Defense stays
					-- for one-handed weapons -- a different stat, not
					-- mentioned in the removal request.
					if it_id:getSlotPosition() == 48 then -- One-handed Weapon
						table.insert(available_stats, stats[3]) -- Extra Defense
					end
					table.insert(available_stats, stats[10]) -- Critical Chance
					table.insert(available_stats, stats[37]) -- Life Leech

					-- Cleave (stats[53]) -- two-handed Knight weapons only.
					-- voc/vocLocked aren't in scope up here (only computed
					-- further down in the Armors/Amulets else branch), so
					-- checked inline the same way -- SLOTP_TWO_HAND is the
					-- same real bitmask already used for raritySlots below
					-- in this file.
					if it_id:getVocationString() ~= nil and it_id:getVocationString():find("Knight")
							and bit.band(it_id:getSlotPosition(), SLOTP_TWO_HAND) ~= 0 then
						table.insert(available_stats, stats[53]) -- Cleave (minClass=2 filters below Class 2)
					end

				-- Fist weapons (the original download never accounted for
				-- these -- no dedicated Fist Skill stat exists in this
				-- system, so they get the general Melee Skills stat instead)
				elseif wp == WEAPON_FIST then
					table.insert(available_stats, stats[28]) -- Melee Skills

					if it_id:getAttack() > 0 then
						table.insert(available_stats, stats[1]) -- Attack
					end
					table.insert(available_stats, stats[10]) -- Critical Chance
					table.insert(available_stats, stats[37]) -- Life Leech

				-- Quivers -- previously had NO structural pool at all (only
				-- Prism Heart via the whitelist below, on 5 specific items).
				-- Per owner's spec: base pool now applies to every quiver,
				-- Prism Heart stays exactly as-is on top for the whitelisted
				-- ones -- deliberately not replaced yet (still deciding on
				-- a crossbow-flavored unique).
				elseif wp == WEAPON_QUIVER then
					table.insert(available_stats, stats[47]) -- Capacity
					table.insert(available_stats, stats[46]) -- Adrenaline Rush (minClass=3 filters below Class 3)
					table.insert(available_stats, stats[10]) -- Crit Chance
					table.insert(available_stats, stats[29]) -- Distance Skill
				end
			else -- Armors, Amulets, Runes and Rings
				if it_id:getArmor() > 0 then
					table.insert(available_stats, stats[4]) -- Armor
				end

				-- Duration
				local eq_id = it_id:getTransformEquipId()
				if eq_id > 0 then
					table.insert(available_stats, stats[9]) -- Time
				end

				-- Charges
				local chargecount = it_id:getCharges()
				if chargecount > 0 and it_u:getId() ~= 2173 then -- Ignore AOL
					if chargecount >= 50 then
						table.insert(available_stats, stats[8]) -- High Charges
					else
						table.insert(available_stats, stats[7]) -- Low Charges
					end
				end

				-- Slot-based generalized pools -- per owner's request to
				-- stop hand-picking which specific rings/legs/boots/armor
				-- pieces get which "generic" stats (the exact inconsistency
				-- that prompted this: "I don't want any amulets to carry
				-- crit chance and others armor without any reasonable
				-- reason"). Every item in a given equipment slot is now
				-- eligible for a fixed pool for that slot, full stop --
				-- vocation-conditional stats (mage rings, Knight/Paladin
				-- legs, Knight body armor) are ADDITIONS on top of the base
				-- pool, not a replacement for it. getSlotPosition() is the
				-- real native bitmask (SLOTP_*), same accessor already used
				-- by RarityStats.itemAttributes below in this file --
				-- authoritative regardless of whether items.xml bothers to
				-- redeclare a slot attribute for a given item.
				local slotPos = it_id:getSlotPosition()
				local voc = it_id:getVocationString()
				local function vocLocked(name)
					return voc ~= nil and voc:find(name) ~= nil
				end
				local isMageBound = vocLocked("Sorcerer") or vocLocked("Druid")
				local isKnightBound = vocLocked("Knight")
				local isPaladinBound = vocLocked("Paladin")

				-- Ring / Necklace
				if bit.band(slotPos, SLOTP_RING) ~= 0 or bit.band(slotPos, SLOTP_NECKLACE) ~= 0 then
					table.insert(available_stats, stats[11]) -- Speed
					table.insert(available_stats, stats[33]) -- Max Mana
					table.insert(available_stats, stats[32]) -- Max Health
					table.insert(available_stats, stats[43]) -- Fortune
					table.insert(available_stats, stats[37]) -- Life Leech
					table.insert(available_stats, stats[52]) -- Grave Tithe (minClass=4 filters below Class 4), all vocations
					if isMageBound then
						table.insert(available_stats, stats[31]) -- Magic Level
					end
				end

				-- Legs
				if bit.band(slotPos, SLOTP_LEGS) ~= 0 then
					table.insert(available_stats, stats[19]) -- Physical Resistance
					table.insert(available_stats, stats[44]) -- Magic Resistance
					table.insert(available_stats, stats[32]) -- Max Health
					table.insert(available_stats, stats[11]) -- Speed
					if isKnightBound or isPaladinBound then
						table.insert(available_stats, stats[45]) -- Thorn
					end
				end

				-- Body Armor
				if bit.band(slotPos, SLOTP_ARMOR) ~= 0 then
					table.insert(available_stats, stats[32]) -- Max Health
					table.insert(available_stats, stats[15]) -- Fire Resistance
					table.insert(available_stats, stats[16]) -- Ice Resistance
					table.insert(available_stats, stats[17]) -- Energy Resistance
					table.insert(available_stats, stats[18]) -- Earth Resistance
					table.insert(available_stats, stats[19]) -- Physical Resistance
					table.insert(available_stats, stats[20]) -- Death Resistance
					if isKnightBound then
						table.insert(available_stats, stats[28]) -- Melee Skills
						table.insert(available_stats, stats[39]) -- Hold the Line (minClass=4 filters below Class 4)
					end
					if isKnightBound or isPaladinBound then
						table.insert(available_stats, stats[51]) -- Juggernaut (minClass=4 filters below Class 4)
					end
					if isMageBound then
						table.insert(available_stats, stats[55]) -- Glass Cannon (minClass=4 filters below Class 4)
					end
				end

				-- Boots
				if bit.band(slotPos, SLOTP_FEET) ~= 0 then
					table.insert(available_stats, stats[11]) -- Speed
					table.insert(available_stats, stats[42]) -- Dodge Chance
					table.insert(available_stats, stats[46]) -- Adrenaline Rush (minClass=3 filters below Class 3), all vocations
				end

				-- Helmet — default pool is Physical Resistance/Magic
				-- Resistance for every vocation (Armor itself is already
				-- inserted for any item with a real armor value at the top
				-- of this branch -- adding it again here would just double
				-- its odds, same reasoning as why Legs/Body Armor/Boots
				-- above don't re-push stats[4] either). Vocation-conditional
				-- stats are ADDITIONS on top, same shape as every other slot
				-- above. Mage-bound gets Magic Level (same stat already
				-- reachable on rings/necklaces for mages, and on
				-- spellbooks), Paladin-bound gets Distance Skill,
				-- Knight-bound gets Melee Skills (same stat already
				-- reachable on Knight body armor above).
				if bit.band(slotPos, SLOTP_HEAD) ~= 0 then
					table.insert(available_stats, stats[19]) -- Physical Resistance
					table.insert(available_stats, stats[44]) -- Magic Resistance
					table.insert(available_stats, stats[52]) -- Grave Tithe (minClass=4 filters below Class 4), all vocations
					if isMageBound then
						table.insert(available_stats, stats[31]) -- Magic Level
					end
					if isPaladinBound then
						table.insert(available_stats, stats[29]) -- Distance Skill
					end
					if isKnightBound then
						table.insert(available_stats, stats[28]) -- Melee Skills
					end
					if isMageBound or isPaladinBound then
						table.insert(available_stats, stats[54]) -- Guardian's Pact (minClass=4 filters below Class 4)
					end
				end
			end

			-- Specifically Targeted Items
			for k, v in pairs(stats) do
				if v.items ~= nil then
					if table.contains(v.items, it_u:getId()) then
						table.insert(available_stats, stats[k])
					end
				end
			end
		end
	end
	if #available_stats > 0 then
		local tier = 0
		local rarity = math.random(1, 10000)

		-- Global Rarity Boost (data/lib/boosts/global_boosts.lua). Every tier
		-- above is matched with `rarity <= rollThreshold`, so scaling the ROLL
		-- down by (100 + pct)/100 is exactly equivalent to scaling all four
		-- thresholds up by the same factor -- one line here instead of
		-- rewriting the tier table, and it cannot drift out of step with it if
		-- a fifth tier is ever added.
		--
		-- Deliberately placed before the `forced` branches but after the roll:
		-- forced rolls (/roll, identify with an explicit tier) ignore `rarity`
		-- entirely, so a boost can never distort a GM-forced or scripted tier.
		-- Guarded on GlobalBoosts because the rarity lib loads before it.
		if GlobalBoosts then
			local rareBoost = GlobalBoosts.magnitude(GlobalBoosts.ID.RARE)
			if rareBoost > 0 then
				rarity = math.max(1, math.floor(rarity * 100 / (100 + rareBoost)))
			end
		end
		if type(forced) == "string" then
			for i = 1, #tiers do
				if forced == tiers[i].prefix then
					tier = i
				end
			end
		elseif forced == true then
			tier = math.random(1, #tiers)
		else
			for i = 1, #tiers do
				if rarity <= tiers[i].rollThreshold then
					tier = i
				end
			end
		end
		-- (Owner reversal 2026-08-30: the Adept+ floor that used to sit here
		-- is gone -- Scarce is back as a normal possible outcome, including
		-- on identify. See BONUS_BACKLOG.md/REBIRTH_STATUS.md-style history
		-- if this needs to be found again later.)
		if tier > 0 then
			if not skipDormant then
				-- Dormant: don't roll or reveal anything about this item's
				-- actual bonus yet. This roll only decided whether the item
				-- is Dormant-worthy at all (tier > 0, above) -- WHAT it
				-- actually rolls is decided fresh, live, the moment it's
				-- identified: RarityIdentify.reveal (data/lib/rarity/
				-- rarity_identify.lua) calls RarityStats.rollRarity(item,
				-- true, true) on Use, reusing this exact function instead of
				-- a separate pre-roll-and-cache layer -- simpler, and
				-- nothing to go stale between rolling and identifying.
				rares = rares + 1
				it_u:setTier(RarityStats.DORMANT_TIER)
				-- No leading "a"/"an" -- reads as "Dormant Falcon Plate",
				-- not "a Dormant Falcon Plate".
				it_u:setAttribute(ITEM_ATTRIBUTE_ARTICLE, "Dormant")
				it_u:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION,
					(it_id:getDescription() == "" and "" or (it_id:getDescription() .. "\n\n"))
					.. "This item pulses with dormant power. Awaken it at a Dormant Shrine or with a Dormant Waker.")
				return rares
			end

			-- A small number of stats are gated beyond the normal
			-- tier/whitelist system: minTier restricts them to a specific
			-- rolled tier or higher (Rebirth), minClass restricts them to a
			-- specific item power Class or higher (Hold the Line,
			-- Adrenaline Rush -- see itemClass computed up top), and
			-- rollChance is an independent secondary probability checked
			-- once per roll attempt (Rebirth) -- stacking with the tier
			-- odds above to make gated stats dramatically rarer than plain
			-- eligibility alone would give. Filtered here, before slot
			-- selection, so a failed roll just removes the candidate for
			-- this attempt rather than needing special-casing in the
			-- picking loop below.
			local i = #available_stats
			while i >= 1 do
				local candidate = available_stats[i]
				local failsMinTier = candidate.minTier and candidate.minTier > tier
				local failsMinClass = candidate.minClass and candidate.minClass > itemClass
				local failsRollChance = candidate.rollChance and math.random(1, 10000) > candidate.rollChance
				if failsMinTier or failsMinClass or failsRollChance then
					table.remove(available_stats, i)
				end
				i = i - 1
			end

			-- Every slot always fires now (no probability gate) -- tier
			-- determines a fixed bonus-slot count, and each slot
			-- independently rolls locked-or-open. stats_used entries are
			-- wrapped ({def=..., locked=...}) instead of holding the raw
			-- stat definition directly, so the locked/open state survives
			-- alongside the picked stat through the rest of this function.
			local stats_used = {}
			for slot = 1, tiers[tier].slotCount do
				if #available_stats > 0 then
					local selected_stat = math.random(1, #available_stats)
					local isLocked = math.random(1, 10000) <= tiers[tier].lockChance
					table.insert(stats_used, { def = available_stats[selected_stat], locked = isLocked })
					table.remove(available_stats, selected_stat)
				end
			end
			if #stats_used > 0 then
				rares = rares + 1
				local stat_desc = {}
				local pendingNatives = {}
				-- Power-class magnitude scaling: a legendary roll on a
				-- Class 7 item (e.g. a level-600 Sanguine weapon) should
				-- roll bigger than the same legendary roll on a Class 1
				-- item (e.g. a starter Bow) -- see RarityClass for the
				-- classification design. itemClass is computed once, up at
				-- the top of this function now (also used for minClass
				-- eligibility filtering above), not re-derived here.
				for stat = 1, #stats_used do
					local def = stats_used[stat].def
					local openBracket = stats_used[stat].locked and '[' or '('
					local closeBracket = stats_used[stat].locked and ']' or ')'

					-- Flag-type stats (currently just Rebirth) have no
					-- numeric magnitude to roll -- skip the rare/epic/
					-- legendary min/max lookup entirely and just insert the
					-- bare bracket marker.
					if def.value == "Flag" then
						table.insert(stat_desc, openBracket .. def.attribute.name .. closeBracket)
						goto continueStat
					end

					local statmin = 0
					local statmax = 0
					local magnitudeKey = MAGNITUDE_KEY_BY_TIER[tier]
					if magnitudeKey then
						statmin = def.attribute[magnitudeKey][1]
						statmax = def.attribute[magnitudeKey][2]
					else
						-- Prime (tier 4): no hand-authored range exists on any
						-- stat, scale Superior's (the old "legendary" field)
						-- range up by PRIME_MAGNITUDE_SCALE instead.
						statmin = math.max(1, math.floor(def.attribute.legendary[1] * PRIME_MAGNITUDE_SCALE))
						statmax = math.max(statmin, math.floor(def.attribute.legendary[2] * PRIME_MAGNITUDE_SCALE))
					end
					local critv = math.random(statmin, statmax)
					local classMultiplier = RarityClass.getMultiplier(itemClass, def.value == "Percent")
					critv = math.max(1, math.floor(critv * classMultiplier + 0.5))
					-- Locked bonuses display in [brackets], open bonuses in
					-- (parens) -- this is the only place that decides which;
					-- every read-site elsewhere (rollCondition,
					-- rarity_combat.lua) accepts either via a character
					-- class, since locked/open only affects future
					-- reroll-eligibility, never whether the bonus works.
					local openBracket = stats_used[stat].locked and '[' or '('
					local closeBracket = stats_used[stat].locked and ']' or ')'
					if def.value ~= nil then
						local basestat = 0
						if def.base ~= nil then
							basestat = rollBase(it_u, def.base)
						end
						if def.value == "Static" then
							table.insert(stat_desc, openBracket .. def.attribute.name .. ': +' .. critv .. closeBracket)
						elseif def.value == "Percent" then
							table.insert(stat_desc, openBracket .. def.attribute.name .. ': +' .. critv .. '%' .. closeBracket)
						elseif def.value == "Damage" then
							local minimumDmg = 1
							if def.attribute.name == "Enhanced Fire Damage" then
								minimumDmg = math.max(1, critv - math.random(3, 5))
							elseif def.attribute.name == "Enhanced Ice Damage" then
								minimumDmg = math.max(1, critv - math.random(5, 9))
							end
							table.insert(stat_desc, openBracket .. def.attribute.name .. ': ' .. minimumDmg .. '-' .. critv .. closeBracket)
						elseif def.value == "Duration" then
							local timeconvert = critv / 60000
							table.insert(stat_desc, openBracket .. def.attribute.name .. ': +' .. timeconvert .. ' minutes' .. closeBracket)
						end
						-- Applied immediately -- skipDormant is the only path
						-- that still reaches this code, so there's no reason
						-- to defer these anymore.
						if basestat > 0 then
							it_u:setAttribute(def.base, basestat + critv)
						end
					end
					::continueStat::
				end

				-- GM /roll <tier> testing path: apply everything for real,
				-- immediately, exactly like before Dormant existed.
				it_u:setTier(tier)
				if it_id:getArticle() ~= "" then
					local firstLetter = tiers[tier].prefix:sub(1, 1):lower()
					local prefix = firstLetter:find("[aeiou]") and "an " or "a "
					it_u:setAttribute(ITEM_ATTRIBUTE_ARTICLE, prefix .. tiers[tier].prefix)
				else
					it_u:setAttribute(ITEM_ATTRIBUTE_ARTICLE, tiers[tier].prefix)
				end
				if it_id:getDescription() == "" then
					it_u:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "\n" .. table.concat(stat_desc, "\n"))
				else
					it_u:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, it_id:getDescription() .. "\n" .. "\n" .. table.concat(stat_desc, "\n"))
				end
			end
		end
	end
	return rares
end

-- Apply condition (passive skill/health/mana/magic-level bonuses from a
-- rolled item, via the item's description text)
function RarityStats.rollCondition(player, item, slot)
	-- "[%[%(]" matches either an opening bracket or paren -- locked ([...])
	-- and open ((...)) bonuses both apply identically here; locked/open only
	-- affects future reroll-eligibility, never whether the bonus works.
	local attributes = {
		 [1] = {"[%[%(]" .. stats[25].attribute.name .. ": ", CONDITION_PARAM_SKILL_SWORD},
		 [2] = {"[%[%(]" .. stats[26].attribute.name .. ": ", CONDITION_PARAM_SKILL_AXE},
		 [3] = {"[%[%(]" .. stats[27].attribute.name .. ": ", CONDITION_PARAM_SKILL_CLUB},
		 [4] = {"[%[%(]" .. stats[28].attribute.name .. ": ", CONDITION_PARAM_SKILL_MELEE},
		 [5] = {"[%[%(]" .. stats[29].attribute.name .. ": ", CONDITION_PARAM_SKILL_DISTANCE},
		 [6] = {"[%[%(]" .. stats[30].attribute.name .. ": ", CONDITION_PARAM_SKILL_SHIELD},
		 [7] = {"[%[%(]" .. stats[31].attribute.name .. ": ", CONDITION_PARAM_STAT_MAGICPOINTS},
		 [8] = {"[%[%(]" .. stats[32].attribute.name .. ": ", CONDITION_PARAM_STAT_MAXHITPOINTS},
		 [9] = {"[%[%(]" .. stats[33].attribute.name .. ": ", CONDITION_PARAM_STAT_MAXMANAPOINTS},
		[10] = {"[%[%(]" .. stats[34].attribute.name .. ": ", CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT, percent = true, absolute = true},
		[11] = {"[%[%(]" .. stats[35].attribute.name .. ": ", CONDITION_PARAM_STAT_MAXMANAPOINTSPERCENT, percent = true, absolute = true},
		[12] = {"[%[%(]" .. stats[11].attribute.name .. ": ", CONDITION_PARAM_SPEED},
		[13] = {"[%[%(]" .. stats[47].attribute.name .. ": ", CONDITION_PARAM_STAT_CAPACITY},
	}
	local itemDesc = item:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION)
	for k = 1, #attributes do
		local skillBonus = 0
		local attributeSearchValue = "%+(%d+)[%]%)]"
		if attributes[k].percent ~= nil then
			attributeSearchValue = "%+(%d+)%%[%]%)]"
			if attributes[k].absolute ~= nil then
				skillBonus = 100
			end
		end
		local attributeString = attributes[k][1] .. attributeSearchValue
		if itemDesc and string.match(itemDesc, attributeString) ~= nil then
			local offset = (10 * k) + slot
			skillBonus = skillBonus + tonumber(string.match(itemDesc, attributeString))

			if player:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, offset) == nil then
				local condition = Condition(CONDITION_ATTRIBUTES)
				condition:setParameter(CONDITION_PARAM_SUBID, offset)
				condition:setParameter(CONDITION_PARAM_TICKS, -1)
				condition:setParameter(attributes[k][2], skillBonus)
				player:addCondition(condition)
			else
				player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, offset)
			end
		end
	end
end

-- Get item attributes (equip-time entry point — called from
-- data/scripts/eventcallbacks/player/rarity_onupdateinventory.lua)
function RarityStats.itemAttributes(player, item, slot, equip)
	local article = item:getAttribute(ITEM_ATTRIBUTE_ARTICLE)
	-- Tier prefixes were renamed 2026-08-25 (rare/epic/legendary ->
	-- scarce/adept/superior/prime) but this gate was missed, so every passive
	-- stat bonus below (skills, magic level, speed, capacity, Max Health/Mana)
	-- silently stopped applying to every rarity item from that point on -
	-- confirmed via item.getAttribute(ITEM_ATTRIBUTE_ARTICLE) never containing
	-- the old strings anymore. Combat-time stats (attack/crit/leech/etc.,
	-- read live from the description in rarity_combat.lua) were unaffected.
	if article ~= "" and (article:find("scarce") or article:find("adept") or article:find("superior") or article:find("prime")) then
		local appropriateSlot = false
		local slotType = ItemType(item:getId()):getSlotPosition()
		local raritySlots = {
			[CONST_SLOT_LEFT] = {validPositions = {[1] = SLOTP_LEFT, [2] = SLOTP_RIGHT, [3] = SLOTP_TWO_HAND}},
			[CONST_SLOT_RIGHT] = {validPositions = {[1] = SLOTP_LEFT, [2] = SLOTP_RIGHT, [3] = SLOTP_TWO_HAND}},
			[CONST_SLOT_HEAD] = {validPositions = {[1] = SLOTP_HEAD}},
			[CONST_SLOT_NECKLACE] = {validPositions = {[1] = SLOTP_NECKLACE}},
			[CONST_SLOT_ARMOR] = {validPositions = {[1] = SLOTP_ARMOR}},
			[CONST_SLOT_LEGS] = {validPositions = {[1] = SLOTP_LEGS}},
			[CONST_SLOT_FEET] = {validPositions = {[1] = SLOTP_FEET}},
			[CONST_SLOT_RING] = {validPositions = {[1] = SLOTP_RING}}
		}
		if raritySlots[slot] ~= nil then
			if slot == CONST_SLOT_LEFT or slot == CONST_SLOT_RIGHT then
				local weapon = ItemType(item:getId()):getWeaponType()
				if weapon ~= WEAPON_NONE and weapon ~= WEAPON_AMMO then
					appropriateSlot = true
				end
			else
				for i = 1, #raritySlots[slot].validPositions do
					if bit.band(slotType, raritySlots[slot].validPositions[i]) ~= 0 then
						appropriateSlot = true
						break
					end
				end
			end
			if appropriateSlot then
				RarityStats.rollCondition(player, item, slot)
			end
		end
	end
end
