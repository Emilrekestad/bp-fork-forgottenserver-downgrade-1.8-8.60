-- Old Man Bao — Bounties. The weekly loop that sits beside the long one.
--
-- A hunt asks for thousands of kills over days. The bounty board asks for nine
-- specific things over a week. That difference in pacing is the point: a hunt
-- is a commitment, a bounty is a reason to pick something up off the floor.
--
-- Design notes that matter if you extend this:
--
--   * Difficulty comes from the player's LEVEL, not their Bao rank. A level 30
--     character and a level 600 character are asked for completely different
--     things, and paid completely differently for them. Rank governs hunts;
--     level governs bounties. Keeping the two axes separate is what lets a
--     brand-new character and a veteran both open this tab and find work that
--     makes sense for them.
--
--   * The board is DERIVED, not stored. Which nine bounties a player is
--     offered is a pure function of (week index, player guid, level band), so
--     there is no board table to keep in sync, nothing to migrate, and a
--     restart mid-week shows exactly the same nine. Only what has been CLAIMED
--     is persisted.
--
--   * Payment is all-or-nothing: the full count, or nothing. Progress toward
--     it is read live from the player's bags, so the card is never out of step
--     with reality and there is no partial state to store.

BaoBounty = {}

-- Server save runs at 09:55 (data/scripts/globalevents/serversave.lua). The
-- board turns over on the first save of the week, so the server keeps a single
-- heartbeat rather than two that drift apart in the player's head.
local SAVE_HOUR = 9
local SAVE_MINUTE = 55
-- 1 = Sunday, matching os.date("*t").wday and the DEFAULT_RESET_DAY that
-- data/scripts/network/task_board/weekly_tasks.lua already uses.
local RESET_WDAY = 1

BaoConfig.BountySlots = 9

-- Level -> difficulty band. Thresholds chosen so the band always asks for
-- something the player can realistically farm at that level: Doorstep vermin
-- early, dragon and lizard products in the middle, demon and Soul War
-- materials at the top.
--
-- (!) Bands must be listed low to high and the last one must have no maxLevel,
-- or a high-level character falls off the end and gets no board at all.
BaoConfig.BountyLevelBands = {
	{ maxLevel = 49,   difficulty = 1 },
	{ maxLevel = 129,  difficulty = 2 },
	{ maxLevel = 299,  difficulty = 3 },
	{ maxLevel = nil,  difficulty = 4 },
	["lightning_legs"] = { displayName = "They Hum When You Stand Still", source = "Juvenile Bashmu", difficulty = 4,
		itemId = 822, count = 5, flavor = "You will get used to the sound or you will not. Either way, bring five." },
	["bows"] = { displayName = "Wood from Walking Wood", source = "Stalking Stalk", difficulty = 4,
		itemId = 3350, count = 5, flavor = "Wood taken from a thing that was also wood. I have stopped asking." },
	["serpent_swords"] = { displayName = "An Old Design", source = "Werecrocodile", difficulty = 4,
		itemId = 3297, count = 7, flavor = "Old, and still good. Take them off the lizards that never learned why." },
	["tribal_masks"] = { displayName = "Faces Not Their Own", source = "True Frost Flower Asura", difficulty = 4,
		itemId = 3403, count = 9, flavor = "They wear faces that were never theirs. Bring me the faces." },
	["voodoo_wands"] = { displayName = "Out of Circulation", source = "Burster Spectre", difficulty = 4,
		itemId = 8094, count = 12, flavor = "I want these off the roads more than I want them on my shelf." },
	["lightning_boots"] = { displayName = "They Ran Faster Than They Fought", source = "Elite Pirat", difficulty = 4,
		itemId = 820, count = 4, flavor = "Four pairs, off pirates who chose running and were still too slow." },
	["mystic_turbans"] = { displayName = "Silk and Nonsense", source = "True Dawnfire Asura", difficulty = 4,
		itemId = 3574, count = 8, flavor = "The nonsense is theirs. The silk is worth something to me." },
	["titan_axes"] = { displayName = "If You Can Carry Eleven", source = "Juggernaut", difficulty = 4,
		itemId = 7413, count = 11, flavor = "Eleven. If you manage eleven of these, you no longer need my advice." },
}

-- Difficulty bands. A bounty's entire economy comes from here: `marksPer` and
-- `repPer` are multiplied by the order's item count to get what it pays, and
-- nothing is paid until the whole order is delivered.
--
-- (!) This table is the one place to retune the bounty economy. No individual
-- bounty overrides it — change a number here and every bounty of that band
-- moves with it.
--
-- Names are deliberately plain and obviously ordered. A player should never
-- have to learn what a band means: Easy < Steady < Hard < Grim.
BaoConfig.BountyDifficulty = {
	[1] = { name = "Easy",   marksPer = 1,  repPer = 4 },
	[2] = { name = "Steady", marksPer = 4,  repPer = 16 },
	[3] = { name = "Hard",   marksPer = 15, repPer = 60 },
	[4] = { name = "Grim",   marksPer = 48, repPer = 200 },
}

-- Every itemId below was verified by name against data/items/items.xml, and
-- every `source` and `count` was GENERATED from the monster loot tables by
-- scratchpad/order_candidates.js rather than chosen by hand. Hand-choosing is
-- what broke the previous table: it asked level-1-49 characters for 20 spider
-- silk, whose cheapest source is a 900xp giant spider, and effort per order
-- ranged from 90 kills to 18,750 inside a single band.
--
-- `source` is the monster the order is COSTED against -- the cheapest one a
-- player in this difficulty band can reasonably fight. It is SERVER-SIDE ONLY
-- and is never sent to the client: it exists so the economy can be re-audited
-- and so a later editor can see why a count is what it is.
--
-- The order card shows no chip at all. It used to carry a chapter name, which
-- was actively misleading -- orders are gated by LEVEL and chapters by RANK,
-- so it advertised a lock that does not exist -- and the monster name that
-- briefly replaced it only repeated what the item sprite and subtitle say.
--
-- Counts are tuned so every order costs roughly 250 kills at that source, and
-- none is outside 140-420. Effort is deliberately FLAT across bands; the
-- reward scales with the band, not the grind.
--
-- (!) Re-run scratchpad/order_candidates.js after touching this table or the
-- monster loot files. An item whose drop rate changes can silently become a
-- 1,000-kill order, which reads to the player as the board being broken.
--
-- (!) There must be at least BountySlots entries at EVERY difficulty, or a
-- player in that level band sees a short board. BaoBounty.validate() checks
-- this at startup and says so loudly. Well above 9 is wanted, not exactly 9 --
-- at exactly 9 the weekly draw shows the same board every week.
BaoConfig.Bounties = {
	-- ── Easy · levels 1-49 ────────────────────────────────────────────
	["chicken_feathers"] = { displayName = "An Undignified Errand", source = "Agrestic Chicken", difficulty = 1,
		itemId = 5890, count = 60, flavor = "Yes. Feathers. Every hunter starts somewhere, and you start here." },
	["wolf_paws"] = { displayName = "Paws for the Tanner", source = "Thornfire Wolf", difficulty = 1,
		itemId = 5897, count = 20, flavor = "The tanner pays for clean paws. Bring me clean paws." },
	["orc_teeth"] = { displayName = "Teeth of the Warband", source = "Scar Tribe Shaman", difficulty = 1,
		itemId = 10196, count = 30, flavor = "Orcs keep coming. That is convenient, for once." },
	["troll_ears"] = { displayName = "Ears in the Frost", source = "Troll Legionnaire", difficulty = 1,
		itemId = 9648, count = 15, flavor = "Frosty ears. Do not ask what I use them for." },
	["honeycombs"] = { displayName = "Sweetness and Stings", source = "Wasp", difficulty = 1,
		itemId = 5902, count = 10, flavor = "The bees will object. That is part of the price." },
	["gloom_wolf_fur"] = { displayName = "Fur from the Gloom", source = "Gloom Wolf", difficulty = 1,
		itemId = 22007, count = 20, flavor = "The gloom clings to it. Beat it out before you bring it to me." },
	["marsh_stalker_beaks"] = { displayName = "Beaks from the Wet Ground", source = "Meadow Strider", difficulty = 1,
		itemId = 17461, count = 15, flavor = "They stand still so long you forget them. They do not forget you." },
	["minotaur_horns"] = { displayName = "Horns of the Guard", source = "Minotaur Guard", difficulty = 1,
		itemId = 11472, count = 30, flavor = "Taken from the head, not off the floor. I can tell the difference." },
	["tusks"] = { displayName = "Ivory from the Plains", source = "Terrified Elephant", difficulty = 1,
		itemId = 3044, count = 30, flavor = "A big animal, frightened. Make it quick. That is the whole job." },
	["mammoth_tusks"] = { displayName = "Ivory from the Ice", source = "Mammoth", difficulty = 1,
		itemId = 10321, count = 30, flavor = "Cold work. The tusks come easier than the walking does." },
	["thick_fur"] = { displayName = "Fur Against the Cold", source = "Mammoth", difficulty = 1,
		itemId = 10307, count = 20, flavor = "You will want some of it yourself. Bring me the rest." },

	["steel_shields"] = { displayName = "Shields off the Dead", source = "Beholder", difficulty = 1,
		itemId = 3409, count = 10, flavor = "Bring them dented. I do not need them pretty, I need them steel." },
	["pirate_shirts"] = { displayName = "Off the Backs of Pirates", source = "Pirate Buccaneer", difficulty = 1,
		itemId = 6095, count = 3, flavor = "The cloth is good. The men wearing it are not. Take the cloth." },
	["coats"] = { displayName = "Cloth from the Coven", source = "Witch", difficulty = 1,
		itemId = 3562, count = 5, flavor = "A witch coat. Wash it twice before you wear it, if you must wear it." },
	["obsidian_lances"] = { displayName = "Black Glass", source = "Stalker", difficulty = 1,
		itemId = 3313, count = 3, flavor = "Obsidian holds an edge no whetstone gave it. Carry them carefully." },
	["steel_helmets"] = { displayName = "Helms for the Rack", source = "Assassin", difficulty = 1,
		itemId = 3351, count = 8, flavor = "Off assassins. They will not need them, and you will not be seen taking them." },
	["post_officer_hats"] = { displayName = "An Absurd Request", source = "Muglex Clan Chief", difficulty = 1,
		itemId = 3576, count = 19, flavor = "Do not ask. A man in Thais collects them and pays in coin I can use." },
	["dragonbreath_wands"] = { displayName = "Sticks That Spit Fire", source = "Dark Apprentice", difficulty = 1,
		itemId = 3075, count = 5, flavor = "Apprentices carry them before they learn better. Take them before they do." },
	["two_handed_swords"] = { displayName = "Iron by the Armful", source = "Bonelord", difficulty = 1,
		itemId = 3265, count = 10, flavor = "Heavy, ugly, and worth melting down. Bring your strongest bag." },

	-- ── Steady · levels 50-129 ────────────────────────────────────────
	["lizard_scales"] = { displayName = "Scales of the Zaoan", source = "Lizard Zaogun", difficulty = 2,
		itemId = 5881, count = 30, flavor = "The lizard folk armour themselves in these. So could you." },
	["cyclops_toes"] = { displayName = "Trophies of the Big Folk", source = "Cyclops Smith", difficulty = 2,
		itemId = 9657, count = 25, flavor = "A cyclops counts to one. You will need to count higher." },
	["terrorbird_beaks"] = { displayName = "Beaks of the Tall Birds", source = "Terror Bird", difficulty = 2,
		itemId = 10273, count = 25, flavor = "They run faster than you. Plan accordingly." },
	["vampire_teeth"] = { displayName = "Teeth of the Sleepless", source = "Nightfiend", difficulty = 2,
		itemId = 9685, count = 25, flavor = "Take them at the root. Half a tooth is worth nothing." },
	["minotaur_leather"] = { displayName = "Hide of the Horned", source = "Minotaur Amazon", difficulty = 2,
		itemId = 5878, count = 45, flavor = "Minotaur leather. Thick. Stubborn. Like its owner was." },
	["scarab_pincers"] = { displayName = "Pincers from the Sand", source = "Ancient Scarab", difficulty = 2,
		itemId = 9631, count = 20, flavor = "Desert work. Bring water. Bring more water than that." },
	["bonelord_eyes"] = { displayName = "Eyes That Watched Back", source = "Braindeath", difficulty = 2,
		itemId = 5898, count = 10, flavor = "They keep looking at you afterwards. You get used to it." },
	["spider_silk"] = { displayName = "Thread from the Dark", source = "Exotic Cave Spider", difficulty = 2,
		itemId = 5879, count = 10, flavor = "Silk is stronger than rope, if you know how to spin it." },
	["brimstone_shells"] = { displayName = "Shells from the Sulphur", source = "Brimstone Bug", difficulty = 2,
		itemId = 11703, count = 25, flavor = "They smell of the pit, and the shells keep the smell. My apologies." },
	["frazzle_tongues"] = { displayName = "Tongues from the Deep Dark", source = "Weakened Frazzlemaw", difficulty = 2,
		itemId = 20198, count = 30, flavor = "The weak ones first. Learn the shape of it before the strong ones find you." },
	["bony_tails"] = { displayName = "Tails of the Bone Beasts", source = "Bonebeast", difficulty = 2,
		itemId = 10277, count = 25, flavor = "Held together by nothing I can name. Bring them still held together." },
	["lizard_leather"] = { displayName = "Leather of the Zaoan", source = "Lizard Zaogun", difficulty = 2,
		itemId = 5876, count = 35, flavor = "Their officers wear the best hide. Take it from an officer." },
	["crystal_bones"] = { displayName = "Bones Grown Wrong", source = "Instable Breach Brood", difficulty = 2,
		itemId = 23521, count = 25, flavor = "The breach makes bone out of light. Do not ask me how." },

	["rhino_horn_carvings"] = { displayName = "Carved and Lost", source = "Shaper Matriarch", difficulty = 2,
		itemId = 24386, count = 50, flavor = "Someone carved these with great care, then lost them to something with none." },
	["snail_shells"] = { displayName = "Shells the Forest Keeps", source = "Nymph", difficulty = 2,
		itemId = 25696, count = 30, flavor = "The forest folk keep them. I want them. We will not discuss it further." },
	["blazing_bones"] = { displayName = "Bones That Stay Warm", source = "Dragonling", difficulty = 2,
		itemId = 16131, count = 30, flavor = "Still warm. They stay warm. That is exactly why I want them." },
	["frosty_hearts"] = { displayName = "Hearts of Slow Ice", source = "Ice Golem", difficulty = 2,
		itemId = 9661, count = 35, flavor = "A heart of ice, still beating slowly. Bring them before they thaw." },
	["lancer_beetle_shells"] = { displayName = "Armour It Grew Itself", source = "Lancer Beetle", difficulty = 2,
		itemId = 10455, count = 40, flavor = "Better work than most smiths manage, and the beetle never charged for it." },
	["lizard_essence"] = { displayName = "Essence of the Scaled", source = "Souleater", difficulty = 2,
		itemId = 11680, count = 40, flavor = "Distilled from something that did not want distilling." },
	["mutated_rat_tails"] = { displayName = "Tails from the Rot", source = "Mutated Rat", difficulty = 2,
		itemId = 9668, count = 10, flavor = "Whatever changed them is still down there. Do not go looking for it." },
	["brimstone_fangs"] = { displayName = "Fangs Through Stone", source = "Brimstone Bug", difficulty = 2,
		itemId = 11702, count = 15, flavor = "They bite through rock. Mind which way you are holding them." },
	["terra_legs"] = { displayName = "Greaves of Worked Earth", source = "Menacing Carnivor", difficulty = 2,
		itemId = 812, count = 5, flavor = "The green in them is not dye. Do not try to clean it off." },
	["terra_boots"] = { displayName = "Boots for the Long Walk", source = "Pirat Bombardier", difficulty = 2,
		itemId = 813, count = 15, flavor = "Good boots. I have worn out four pairs of my own asking for these." },
	["terra_hoods"] = { displayName = "Three Hoods, No More", source = "Bramble Wyrmling", difficulty = 2,
		itemId = 830, count = 3, flavor = "Only three. They are hard to come by and I am not a greedy man." },
	["battle_axes"] = { displayName = "Axes by the Score", source = "Young Sea Serpent", difficulty = 2,
		itemId = 3266, count = 20, flavor = "Twenty axes. Do not carry them all at once near deep water." },
	["epees"] = { displayName = "Thin Blades, Iron Owners", source = "War Golem", difficulty = 2,
		itemId = 3326, count = 16, flavor = "A thin blade off a thing made of iron. The irony is not lost on me." },
	["leather_legs"] = { displayName = "Plain Leather", source = "Minotaur Mage", difficulty = 2,
		itemId = 3559, count = 13, flavor = "Nothing special. Every hunter needs a spare pair and most forget." },
	["green_tunics"] = { displayName = "What Heroes Stopped Wearing", source = "Hero", difficulty = 2,
		itemId = 3563, count = 20, flavor = "Heroes wore these. Heroes stopped. Take the hint, and the tunic." },

	-- ── Hard · levels 130-299 ─────────────────────────────────────────
	["hydra_heads"] = { displayName = "Heads That Grew Back", source = "Hydra", difficulty = 3,
		itemId = 10282, count = 25, flavor = "Cut one, two return. Cut all of them, and be quick about it." },
	["hellspawn_tails"] = { displayName = "Tails of the Burning", source = "Hellspawn", difficulty = 3,
		itemId = 10304, count = 50, flavor = "Still warm when you bring them. Always still warm." },
	["hellhound_slobber"] = { displayName = "What the Hounds Leave", source = "Hellhound", difficulty = 3,
		itemId = 9637, count = 50, flavor = "Unpleasant. Valuable. Those two travel together often." },
	["medusa_hair"] = { displayName = "Strands Best Not Looked At", source = "Medusa", difficulty = 3,
		itemId = 10309, count = 25, flavor = "Cut it blind if you have to. Many have." },
	["fiery_hearts"] = { displayName = "Hearts Still Burning", source = "Weeper", difficulty = 3,
		itemId = 9636, count = 35, flavor = "A heart that will not go out. I have use for those." },
	["werewolf_fangs"] = { displayName = "Fangs Under the Moon", source = "Werewolf", difficulty = 3,
		itemId = 22052, count = 40, flavor = "They were men once. Do not let that slow your hand." },
	["hellfire_armor_pieces"] = { displayName = "Plates of Hellfire", source = "Hellfire Fighter", difficulty = 3,
		itemId = 9664, count = 15, flavor = "Armour that burns the wearer. Some hunters still want it." },
	["deepworm_spike_roots"] = { displayName = "Roots from the Tunnels", source = "Deepworm", difficulty = 3,
		itemId = 27593, count = 50, flavor = "Pulled from something that lives where nothing should." },
	["sparkion_stings"] = { displayName = "Stings That Still Spark", source = "Sparkion", difficulty = 3,
		itemId = 23505, count = 35, flavor = "It will bite you after it is dead. Mind the tail." },
	["blue_goanna_scales"] = { displayName = "Scales from the Sunlands", source = "Young Goanna", difficulty = 3,
		itemId = 31559, count = 20, flavor = "The young ones scatter. The scales are better for it." },
	["cursed_shoulder_spikes"] = { displayName = "Spikes of the Chosen", source = "Lizard Chosen", difficulty = 3,
		itemId = 10410, count = 15, flavor = "Chosen for what, they never said. Take the spikes and go." },
	["spiked_iron_balls"] = { displayName = "What the Guardians Carried", source = "Eternal Guardian", difficulty = 3,
		itemId = 10408, count = 25, flavor = "They guard a door that has stood open a century. Still guarding." },

	["silken_bookmarks"] = { displayName = "A Bookmark, of All Things", source = "Knowledge Elemental", difficulty = 3,
		itemId = 28566, count = 50, flavor = "From a thing made of knowing. I did not ask what it was reading." },
	["peacock_fans"] = { displayName = "Beautiful and Useless", source = "Frost Flower Asura", difficulty = 3,
		itemId = 21975, count = 45, flavor = "Someone in Zao pays well for beautiful and useless. I only broker it." },
	["dragon_tongues"] = { displayName = "Taken from the Throat", source = "Wardragon", difficulty = 3,
		itemId = 24938, count = 20, flavor = "Cut before the fire goes out of it, or it is worth nothing to me." },
	["snake_skins"] = { displayName = "Skins from the Shedding", source = "Serpent Spawn", difficulty = 3,
		itemId = 9694, count = 35, flavor = "They leave these behind willingly. Rare, that." },
	["werewolf_fur"] = { displayName = "The Warm Part", source = "Werewolf", difficulty = 3,
		itemId = 10317, count = 25, flavor = "The fur is warm and the man inside it was not. Bring me the fur." },
	["sparkion_claws"] = { displayName = "Claws That Hold a Charge", source = "Sparkion", difficulty = 3,
		itemId = 23502, count = 40, flavor = "They keep their charge after death. Wrap them separately from each other." },
	["magma_boots"] = { displayName = "Soles That Never Cool", source = "Sphinx", difficulty = 3,
		itemId = 818, count = 9, flavor = "Useful in the deep places, if you can stand to wear them that long." },
	["magma_legs"] = { displayName = "Five Pairs, No More", source = "Broodrider Inferniarch", difficulty = 3,
		itemId = 821, count = 5, flavor = "Any more and you will cook before you carry them home to me." },
	["lightning_headbands"] = { displayName = "They Crackle in the Rain", source = "Cunning Werepanther", difficulty = 3,
		itemId = 828, count = 18, flavor = "Keep them dry on the way back. I will know if you did not." },
	["glacier_masks"] = { displayName = "Cold on the Face", source = "Crazed Winter Rearguard", difficulty = 3,
		itemId = 829, count = 15, flavor = "Cold enough to numb a man. That is the entire point of them." },
	["giant_swords"] = { displayName = "Swords a Man Cannot Lift", source = "Demon Outcast", difficulty = 3,
		itemId = 3281, count = 5, flavor = "Five. They weigh what a man weighs. Plan the walk back before you start." },
	["poison_daggers"] = { displayName = "It Is the Coating I Want", source = "Warlock", difficulty = 3,
		itemId = 3299, count = 19, flavor = "The blade is ordinary. Do not lick your fingers on the way here." },
	["orcish_axes"] = { displayName = "Crude and Effective", source = "Orclops Bloodbreaker", difficulty = 3,
		itemId = 3316, count = 7, flavor = "Crude, heavy, and they work. Much like the ones swinging them." },

	-- ── Grim · levels 300+ ────────────────────────────────────────────
	["unholy_bones"] = { displayName = "Bones That Refuse", source = "Undead Dragon", difficulty = 4,
		itemId = 10316, count = 60, flavor = "Buried three times, by three different people. Here they are." },
	["demon_horns"] = { displayName = "Horns of the Named", source = "Demon", difficulty = 4,
		itemId = 5954, count = 35, flavor = "A horn, taken clean. I will know if it was scavenged." },
	["corruption_tails"] = { displayName = "Tails of the Corrupted", source = "Draken Abomination", difficulty = 4,
		itemId = 11672, count = 15, flavor = "The corruption reaches the tail last. Take it first." },
	["goosebump_leather"] = { displayName = "Leather That Shivers", source = "Retching Horror", difficulty = 4,
		itemId = 20205, count = 40, flavor = "It moves in your hand. I have stopped asking why." },
	["frazzle_skin"] = { displayName = "Skin from the Withered", source = "Frazzlemaw", difficulty = 4,
		itemId = 20199, count = 40, flavor = "It withers what touches it. Wear gloves. Wear two pairs." },
	["undead_hearts"] = { displayName = "Hearts That Stopped Twice", source = "Ghastly Dragon", difficulty = 4,
		itemId = 10450, count = 55, flavor = "It stopped once when it died. It stopped again when you found it." },
	["silencer_claws"] = { displayName = "Claws That Made No Sound", source = "Silencer", difficulty = 4,
		itemId = 20200, count = 45, flavor = "You will not hear them coming. Plan for that, not against it." },
	["energy_veins"] = { displayName = "Veins of Raw Power", source = "Tunnel Tyrant", difficulty = 4,
		itemId = 23508, count = 10, flavor = "Still humming. Keep them apart from each other." },
	["hardened_bone"] = { displayName = "Bone That Would Not Burn", source = "Undead Dragon", difficulty = 4,
		itemId = 5925, count = 35, flavor = "Fire had a go at these already. They are still here." },
	["skull_fetishes"] = { displayName = "Fetishes of the Ogres", source = "Ogre Rowdy", difficulty = 4,
		itemId = 22191, count = 30, flavor = "They make these to frighten each other. It works on them." },
	["werecrocodile_tongues"] = { displayName = "Tongues from the Waterline", source = "Feral Werecrocodile", difficulty = 4,
		itemId = 43729, count = 25, flavor = "Half a man, half a thing with teeth. The tongue is the same either way." },
	["bad_dream_essence"] = { displayName = "What the Dream Left", source = "Thanatursus", difficulty = 4,
		itemId = 10306, count = 45, flavor = "You will sleep badly for a week. It pays for the week." },
}

-- ─── Level band and reward maths ─────────────────────────────────────────

-- Ceiling on order difficulty by Bao's rank, independent of level.
--
-- Level alone was confusing next to the Hunts tab, which gates on rank: a
-- level 300 stranger who had never spoken to Bao was handed Grim work while
-- his hunts were still beginner ones. Both now apply -- level says what you can
-- physically farm, rank says what Bao trusts you with -- and the lower of the
-- two wins.
BaoConfig.BountyRankCap = {
	[0] = 1, [1] = 2, [2] = 2, [3] = 3, [4] = 3, [5] = 4, [6] = 4,
}

-- The difficulty this player gets, and which of the two gates is holding them
-- there. The second return is what lets the board explain itself instead of
-- just quietly showing easier work than the player expected.
function BaoBounty.difficultyFor(player)
	local level = player:getLevel()
	local byLevel = BaoConfig.BountyLevelBands[#BaoConfig.BountyLevelBands].difficulty
	for _, band in ipairs(BaoConfig.BountyLevelBands) do
		if not band.maxLevel or level <= band.maxLevel then
			byLevel = band.difficulty
			break
		end
	end

	local byRank = BaoConfig.BountyRankCap[BaoState.getRankId(player)] or 1
	if byRank < byLevel then
		return byRank, "rank"
	end
	return byLevel, "level"
end

local function band(bounty)
	return BaoConfig.BountyDifficulty[bounty.difficulty] or BaoConfig.BountyDifficulty[1]
end

-- What a completed order is worth. Multiplied by the item count, so a bigger
-- order inside the same band pays proportionally more.
function BaoBounty.payoutFor(bounty)
	local b = band(bounty)
	return bounty.count * b.marksPer, bounty.count * b.repPer, b.name
end

-- The level range of a difficulty band, for display ("levels 50-129").
function BaoBounty.levelRangeFor(difficulty)
	local low = 1
	for _, b in ipairs(BaoConfig.BountyLevelBands) do
		if b.difficulty == difficulty then
			return low, b.maxLevel
		end
		low = (b.maxLevel or low) + 1
	end
	return low, nil
end

-- ─── Rotation ────────────────────────────────────────────────────────────

-- Epoch of the most recent reset: the RESET_WDAY on-or-before now, at the save
-- time. Derived from local calendar fields rather than dividing a raw epoch,
-- so it lands on the right local weekday regardless of the host's timezone.
local function lastResetTime(now)
	local t = os.date("*t", now)
	local secondsIntoDay = (t.hour * 3600) + (t.min * 60) + t.sec
	local saveAt = (SAVE_HOUR * 3600) + (SAVE_MINUTE * 60)

	-- Days since the reset weekday. wday is 1..7 with 1 = Sunday.
	local daysSince = (t.wday - RESET_WDAY) % 7
	-- On reset day but before the save, the week that is running is still the
	-- previous one.
	if daysSince == 0 and secondsIntoDay < saveAt then
		daysSince = 7
	end

	return (now - secondsIntoDay) - (daysSince * 86400) + saveAt
end

function BaoBounty.weekIndex()
	return math.floor(lastResetTime(os.time()) / 604800)
end

function BaoBounty.secondsUntilReset()
	local now = os.time()
	return math.max(0, (lastResetTime(now) + 604800) - now)
end

-- ─── Deterministic selection ─────────────────────────────────────────────

-- A small integer hash, used INSTEAD of math.random so that picking a board
-- never touches the global RNG state. Seeding math.randomseed here would
-- silently change every loot roll and rare-reward roll that ran afterwards in
-- the same tick, which is exactly the kind of bug nobody would trace back to
-- a bounty board.
local function hash32(...)
	local h = 2166136261
	for _, value in ipairs({...}) do
		local n = value
		if type(n) == "string" then
			for i = 1, #n do
				h = (h ~ n:byte(i)) & 0xFFFFFFFF
				h = (h * 16777619) & 0xFFFFFFFF
			end
		else
			n = math.floor(n) & 0xFFFFFFFF
			for _ = 1, 4 do
				h = (h ~ (n & 0xFF)) & 0xFFFFFFFF
				h = (h * 16777619) & 0xFFFFFFFF
				n = n >> 8
			end
		end
	end
	h = (h ~ (h >> 16)) & 0xFFFFFFFF
	h = (h * 2246822507) & 0xFFFFFFFF
	h = (h ~ (h >> 13)) & 0xFFFFFFFF
	return h
end

-- Every bounty at this difficulty, in a stable order. Sorted by key, NOT left
-- in pairs() order: Lua seeds its string hash per process, so an unsorted list
-- would silently hand the player a different board after every server restart
-- even within the same week.
local function keysForDifficulty(difficulty)
	local keys = {}
	for key, bounty in pairs(BaoConfig.Bounties) do
		if bounty.difficulty == difficulty then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	return keys
end

-- Picks BountySlots distinct bounties for this player and week. Pure: same
-- inputs always produce the same board, so nothing needs storing.
function BaoBounty.boardFor(player)
	local difficulty = BaoBounty.difficultyFor(player)
	local keys = keysForDifficulty(difficulty)
	local slots = math.min(BaoConfig.BountySlots, #keys)
	if slots <= 0 then
		return {}
	end

	local week = BaoBounty.weekIndex()
	local guid = player:getGuid()

	-- Partial Fisher-Yates over a copy, with the swap index drawn from the
	-- hash rather than from math.random. Distinct by construction — no
	-- "pick again if we already have it" loop that could spin.
	local pool = {}
	for i, key in ipairs(keys) do
		pool[i] = key
	end

	local board = {}
	for slot = 1, slots do
		local remaining = #pool - slot + 1
		local pick = slot + (hash32(week, guid, difficulty, slot) % remaining)
		pool[slot], pool[pick] = pool[pick], pool[slot]
		local key = pool[slot]
		board[slot] = { key = key, bounty = BaoConfig.Bounties[key] }
	end

	-- Cheapest order first, so the board reads as a ladder within the week.
	table.sort(board, function(a, b)
		if a.bounty.count ~= b.bounty.count then
			return a.bounty.count < b.bounty.count
		end
		return a.key < b.key
	end)
	return board
end

-- ─── Per-player state ────────────────────────────────────────────────────
--
-- Only one thing is worth persisting: which orders have been paid out this
-- week. The blob is replaced wholesale when the week changes, so stale weeks
-- never accumulate.

local function bountyStore(player)
	return player:kv():scoped("bao"):scoped("bounty")
end

local function loadWeekState(player)
	local stored = bountyStore(player):get("current")
	local week = BaoBounty.weekIndex()
	if type(stored) ~= "table" or stored.week ~= week then
		return { week = week, claimed = {} }
	end
	stored.claimed = stored.claimed or {}
	return stored
end

local function saveWeekState(player, state)
	bountyStore(player):set("current", state)
end

function BaoBounty.isClaimed(player, key)
	return loadWeekState(player).claimed[key] == true
end

-- What the player is carrying right now.
--
-- Arguments are (itemId, subType, ignoreEquipped). -1 matches any subtype, and
-- ignoreEquipped = true skips items worn directly in an equipment slot while
-- still counting everything inside containers — which is where creature
-- products actually live.
--
-- (!) This MUST pass the same ignoreEquipped as the removeItem call in
-- turnIn. If the two disagreed, a player could be shown enough to hand in and
-- then have the hand-in refused.
-- ─── What an order will actually accept ────────────────────────────────
--
-- (!) THE most important rule in this file, now that orders ask for equipment.
--
-- The rarity system stores its tier ON THE SAME item id as the plain version
-- (RarityStats sets item:setTier(1..4), and 5 for Dormant), and the old
-- hand-in was `player:removeItem(itemId, count, -1, true)` -- which filters
-- nothing. An order for 12 steel helmets would have happily eaten a Prime one,
-- or a Dormant that had not been revealed yet. There is no way to express
-- "only the plain ones" through removeItem, so the walk is done by hand.
--
-- Rejected: anything with a rarity tier, anything Dormant, anything imbued
-- (turning in an imbued item would silently destroy the imbuements).
local function isPlain(item)
	if not item then
		return false
	end
	if item.getTier and item:getTier() ~= 0 then
		return false
	end
	if item.hasImbuements and item:hasImbuements() then
		return false
	end
	return true
end

-- Explicit slot list: CONST_SLOT_FIRST/_LAST exist in C++ but are NOT exported
-- to Lua, so a numeric range errors out. Same list the Item Bazaar walks.
local INVENTORY_SLOTS = {
	CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_BACKPACK, CONST_SLOT_ARMOR,
	CONST_SLOT_RIGHT, CONST_SLOT_LEFT, CONST_SLOT_LEGS, CONST_SLOT_FEET,
	CONST_SLOT_RING, CONST_SLOT_AMMO,
}

-- Every acceptable item of this type the player is carrying IN A BAG.
--
-- Equipped items are deliberately not counted: an order must never be able to
-- strip the armour a player is wearing, and "bring them to me in your bag" is
-- the rule a player already expects. The equipped slots are still visited,
-- because that is how the backpack itself is reached.
local function plainItems(player, itemId)
	local found = {}
	local queue = {}
	for _, slot in ipairs(INVENTORY_SLOTS) do
		local item = player:getSlotItem(slot)
		if item and item:isContainer() then
			queue[#queue + 1] = item
		end
	end

	local index = 1
	while index <= #queue do
		local container = queue[index]
		index = index + 1
		for _, child in ipairs(container:getItems()) do
			if child:getId() == itemId and isPlain(child) then
				found[#found + 1] = child
			end
			if child:isContainer() then
				queue[#queue + 1] = child
			end
		end
	end
	return found
end

BaoBounty.isPlainOrderItem = isPlain

function BaoBounty.carriedFor(player, bounty)
	local total = 0
	for _, item in ipairs(plainItems(player, bounty.itemId)) do
		total = total + item:getCount()
	end
	return total
end

-- Takes exactly `count`, all-or-nothing. The list is gathered and totalled
-- BEFORE anything is removed, so a short order can never destroy half of it
-- and then fail.
function BaoBounty.takeOrderItems(player, itemId, count)
	local found = plainItems(player, itemId)
	local total = 0
	for _, item in ipairs(found) do
		total = total + item:getCount()
	end
	if total < count then
		return false
	end

	local remaining = count
	for _, item in ipairs(found) do
		if remaining <= 0 then
			break
		end
		local held = item:getCount()
		if held <= remaining then
			remaining = remaining - held
			item:remove()
		else
			item:remove(remaining)
			remaining = 0
		end
	end
	return remaining == 0
end

-- ─── Turn-in ─────────────────────────────────────────────────────────────

-- Hands in a completed order. All or nothing: the full count, or no payment.
-- Returns ok, reasonOrSummary.
--
-- Order matters: the items are removed FIRST and the reward is only granted if
-- that removal actually succeeded. Paying first and removing second would let
-- a failed removal mint marks from nothing.
function BaoBounty.turnIn(player, key)
	local bounty = BaoConfig.Bounties[key]
	if not bounty then
		return false, "That order is no longer posted."
	end
	if bounty.difficulty ~= BaoBounty.difficultyFor(player) then
		return false, "That work is not for someone at your level."
	end

	-- Confirm the bounty is actually on this player's current board — without
	-- this, a client could hand in any bounty in the config at any time.
	local onBoard = false
	for _, entry in ipairs(BaoBounty.boardFor(player)) do
		if entry.key == key then
			onBoard = true
			break
		end
	end
	if not onBoard then
		return false, "That order is not on your board this week."
	end

	local state = loadWeekState(player)
	if state.claimed[key] then
		return false, "You have already brought me those."
	end

	if BaoBounty.carriedFor(player, bounty) < bounty.count then
		return false, "You do not have the full order yet."
	end
	-- (!) NOT removeItem: it cannot filter by attribute, and every order item
	-- shares its id with the rarity and Dormant versions of itself.
	if not BaoBounty.takeOrderItems(player, bounty.itemId, bounty.count) then
		return false, "You do not have the full order yet."
	end

	local marks, reputation = BaoBounty.payoutFor(bounty)
	BaoState.addMarks(player, marks)
	BaoState.addReputation(player, reputation)

	state.claimed[key] = true
	saveWeekState(player, state)
	BaoState.bumpCounter(player, "bounties")

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"Old Man Bao counts the lot once and nods. \"%s. %d Marks, %d Reputation. Good work.\"",
		bounty.displayName, marks, reputation))

	-- A bounty pays reputation, so it can complete a rank on its own.
	BaoRank.checkRankUp(player)

	return true, { marks = marks, reputation = reputation }
end

-- ─── Startup validation ─────────────────────────────────────────────────

-- A board smaller than BountySlots is not an error, but it is a bad
-- impression that nothing else would ever surface. Same reasoning as
-- BaoRank.validateLadder: cheap to check once, invisible otherwise.
function BaoBounty.validate()
	local problems = 0
	local counts = {}
	for _, bounty in pairs(BaoConfig.Bounties) do
		counts[bounty.difficulty] = (counts[bounty.difficulty] or 0) + 1
		if not BaoConfig.BountyDifficulty[bounty.difficulty] then
			problems = problems + 1
			print(string.format("[Bao] bounty '%s' has no difficulty band %s",
				bounty.displayName, tostring(bounty.difficulty)))
		end
		-- `source` never reaches the client -- it records WHICH monster the
		-- count was solved against, so the audit script can re-check the
		-- economy and a later editor can see why a count is what it is.
		if type(bounty.source) ~= "string" or bounty.source == "" then
			problems = problems + 1
			print(string.format("[Bao] bounty '%s' has no source monster - its count cannot be re-audited.",
				bounty.displayName))
		end
	end
	for difficulty, def in pairs(BaoConfig.BountyDifficulty) do
		if (counts[difficulty] or 0) < BaoConfig.BountySlots then
			problems = problems + 1
			print(string.format(
				"[Bao] difficulty '%s' has only %d bounties but the board shows %d - add entries with difficulty = %d.",
				def.name, counts[difficulty] or 0, BaoConfig.BountySlots, difficulty))
		end
	end
	-- The last band must be open-ended or high-level players get no board.
	local last = BaoConfig.BountyLevelBands[#BaoConfig.BountyLevelBands]
	if last.maxLevel then
		problems = problems + 1
		print("[Bao] the highest BountyLevelBands entry has a maxLevel - players above it would get no bounties.")
	end
	return problems
end

BaoBounty.validate()
