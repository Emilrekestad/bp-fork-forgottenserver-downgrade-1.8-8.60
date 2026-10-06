-- Old Man Bao's Shop — what Marks actually buy.
--
-- The old shop sold only consumables, on the reasoning that gear must stay
-- exclusive to the hunt rare-roll. That instinct was right and the conclusion
-- was wrong: it left the deepest grind in the game paying out in potions, with
-- nothing to save toward.
--
-- This sells ACCESS, CAPACITY and PERMANENCE instead — things that change how
-- you play rather than what you are holding. Not one entry here is a weapon or
-- a piece of armour, so the rare-roll economy is untouched.
--
-- Entry shape:
--   category     which section of the Rewards tab it appears under
--   minRank      Bao's trust gate, same ladder the hunts use
--   cost         Marks
--   oneTime      tracked per player; the card shows "Owned" afterwards
--   description  one line saying what it actually does, shown on the card
--   AND EITHER
--     itemId + count   a plain item grant, or
--     grant(player)    a function returning ok, reason -- for anything that
--                      is not an item (storage unlocks, blessings, slots)
--
-- (!) A `grant` runs AFTER the Marks have already been taken. It must return
-- false only for conditions it checked itself; bao_protocol refunds on false.

-- Storage keys owned by other systems. Bao writes the same key those systems
-- read, so a Marks purchase and a Bp Coins purchase are indistinguishable
-- afterwards -- there is no second source of truth to drift.
local PREY_PERMANENT_SLOT_KEY = 780200        -- prey_system.lua
-- Bao's own gate keys. 990600-990799 was verified free before use.
BaoConfig.StorageKeys = {
	weaponProficiency = 990600,
	wheelAccess = 990601,
	gemsAccess = 990602,
}

-- A one-time unlock can come from somewhere other than Bao: the Bp Coins
-- store sells the prey slot, Weapon Proficiency and the Talent Compass too
-- (gamestore.lua, UNLOCK_OFFERS), and the Prey window has its own coin path.
-- Those write the unlock's storage key but not Bao's purchase record, so an
-- entry with a `storageKey` counts as owned when that key is set. Without
-- this his card keeps offering it and takes Marks for something already open.
function BaoConfig.ownsShopItem(player, itemKey)
	if BaoState.hasPurchased(player, itemKey) then
		return true
	end
	local item = BaoConfig.ShopItems and BaoConfig.ShopItems[itemKey]
	return item ~= nil and item.storageKey ~= nil and player:getStorageValue(item.storageKey) == 1
end

-- Extra hunt slots live in kv rather than storage: nothing outside Bao reads
-- them, and BaoState already owns slot shape.
BaoConfig.MaxPurchasableSlots = 2

local BLESSING_COUNT = 8

-- Rank at which Bao starts buying creature products at all (his own short
-- list), and the rank at which he becomes the one-stop shop for everything
-- Grizzly Adams and Yasir buy. Read by his NPC script AND by the Profile's
-- milestone list, so the two can never advertise different numbers.
BaoConfig.TradeMinRank = 2
BaoConfig.ProductsMinRank = 4

-- The headline unlocks, in the order a player would reach them. This is what
-- the Profile advertises: a new player has no way to know Bao is worth
-- focusing on early unless something tells them what is behind him.
--
-- `key` points at a BaoConfig.ShopItems entry (cost and rank come from there,
-- so they cannot drift). `rank` entries are gates that are not purchases --
-- his trade lists open on rank alone.
-- (!) The Profile column holds at most 11 rows (BaoChapterLine in
-- game_bao/bao.otui: 20px + 1px each, 244px of room). A 12th row is cut off
-- the bottom without any error.
BaoConfig.MilestoneOrder = {
	{ key = "weapon_proficiency" },
	{ key = "gems_access" },
	{ rank = "TradeMinRank", label = "He buys creature products",
	  note = "The short list -- what a Doorstep hunter finds" },
	{ key = "wheel_access" },
	{ key = "charm_slot_7" },
	{ key = "hunt_slot_4" },
	{ key = "prey_slot" },
	{ rank = "ProductsMinRank", label = "He buys everything",
	  note = "All 250 products, at the best price in the game" },
	{ key = "hunt_slot_5" },
	{ key = "charm_slot_8" },
}

BaoConfig.ShopCategories = {
	{ key = "supplies", title = "Supplies", note = "Things a hunter runs out of" },
	{ key = "access", title = "What Bao Can Open For You", note = "Permanent, one purchase each" },
	{ key = "wheel", title = "Promotion Scrolls", note = "Talent Compass points that stay forever" },
	{ key = "capacity", title = "Room to Work", note = "More hunts, more often" },
	{ key = "prestige", title = "Trophies", note = "Nothing here makes you stronger" },
}

-- Outfits are stored per looktype and a character's sex decides which one it
-- can wear, so BOTH are always granted -- otherwise half the server buys an
-- outfit they cannot put on. Looktypes verified against data/XML/outfits.xml.
local function grantOutfit(maleLook, femaleLook, label)
	return function(player)
		if player:hasOutfit(maleLook) or player:hasOutfit(femaleLook) then
			return false, "You already wear that."
		end
		player:addOutfit(maleLook)
		player:addOutfit(femaleLook)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
			"Old Man Bao hands over a bundle without ceremony. \"%s. Wear it where people can see.\"", label))
		return true
	end
end

-- Mount ids verified against data/XML/mounts.xml.
local function grantMount(mountId, label)
	return function(player)
		if player:hasMount(mountId) then
			return false, "That one already answers to you."
		end
		player:addMount(mountId)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
			"Old Man Bao whistles once, low. \"%s. It hunted before you did. Remember that.\"", label))
		return true
	end
end

BaoConfig.ShopItems = {
	-- ── Supplies ──────────────────────────────────────────────────────
	-- Rope and shovel are the two tools every hunter needs and nobody enjoys
	-- buying. Bao sells the GOOD versions: an elvenhair rope and a light
	-- shovel weigh a fraction of the ordinary ones, which is exactly the sort
	-- of quiet quality-of-life a hunter's outfitter should be known for.
	["elvenhair_rope"] = {
		displayName = "Elvenhair Rope", category = "supplies", minRank = 0, cost = 60,
		description = "Weighs almost nothing. You will not go back.",
		itemId = 646, count = 1, oneTime = false,
	},
	["light_shovel"] = {
		displayName = "Light Shovel", category = "supplies", minRank = 0, cost = 60,
		description = "Same hole, a quarter of the weight on your back.",
		itemId = 5710, count = 1, oneTime = false,
	},
	["expedition_backpack"] = {
		displayName = "Expedition Backpack", category = "supplies", minRank = 0, cost = 120,
		description = "Twenty slots. Bao has opinions about hunters who bring less.",
		itemId = 10324, count = 1, oneTime = false,
	},
	-- Hireling job contracts (owner, 2026-10-04): open to everyone from the start. The rune
	-- crafter is the cheap one; use the contract on one of your hirelings. The Bp Coins store
	-- sells the same four (gamestore.lua, HIRELING_JOBS).
	["contract_rune_crafter"] = {
		displayName = "Rune Crafter's Contract", category = "supplies", minRank = 0, cost = 200,
		description = "Teaches one of your hirelings to make runes. Use it on the hireling.",
		itemId = 3236, count = 1, oneTime = false,
	},
	["contract_trader"] = {
		displayName = "Trader's Contract", category = "supplies", minRank = 0, cost = 400,
		description = "Teaches one of your hirelings to trade. Use it on the hireling.",
		itemId = 128, count = 1, oneTime = false,
	},
	["contract_banker"] = {
		displayName = "Banker's Contract", category = "supplies", minRank = 0, cost = 400,
		description = "Teaches one of your hirelings to bank your gold. Use it on the hireling.",
		itemId = 22706, count = 1, oneTime = false,
	},
	["contract_cook"] = {
		displayName = "Cook's Contract", category = "supplies", minRank = 0, cost = 400,
		description = "Teaches one of your hirelings to cook. Use it on the hireling.",
		itemId = 23547, count = 1, oneTime = false,
	},
	["blessings"] = {
		displayName = "Bao's Blessing", category = "supplies", minRank = 1, cost = 400,
		displayItemId = 3057, -- an amulet of loss -- blessings are what stop death costing you
		description = "All blessings, at once. Cheaper than dying without them.",
		oneTime = false,
		grant = function(player)
			local granted = 0
			for blessing = 1, BLESSING_COUNT do
				if not player:hasBlessing(blessing) then
					player:addBlessing(blessing, 1)
					granted = granted + 1
				end
			end
			if granted == 0 then
				return false, "You already carry every blessing."
			end
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
				"Old Man Bao mutters something old over you. %d blessing(s) granted.", granted))
			return true
		end,
	},

	-- ── Access ────────────────────────────────────────────────────────
	-- The "I finally got it" purchases. Each writes the same flag the owning
	-- system already reads, so nothing here is a parallel implementation.
	["weapon_proficiency"] = {
		displayName = "Weapon Proficiency", category = "access", minRank = 0, cost = 600,
		displayItemId = 6109, -- a weapon rack (the whetstone 15826 read as a brick at 32px)
		description = "Bao teaches you to actually read a weapon. Unlocks the Proficiency window.",
		oneTime = true,
		storageKey = BaoConfig.StorageKeys.weaponProficiency, -- also sold in the store (5171)
		grant = function(player)
			player:setStorageValue(BaoConfig.StorageKeys.weaponProficiency, 1)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
				"Old Man Bao turns your blade over twice. \"Now you will see what it is telling you.\"")
			return true
		end,
	},
	["gems_access"] = {
		displayName = "Gems", category = "access", minRank = 0, cost = 600,
		displayItemId = 44604, -- a large knight gem (the small one is a speck at 32px)
		description = "Bao shows you what is inside a stone. Unlocks the Gems window.",
		oneTime = true,
		grant = function(player)
			player:setStorageValue(BaoConfig.StorageKeys.gemsAccess, 1)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
				'Old Man Bao holds a stone up to the light. "Now you can see inside." The Gems window is open to you.')
			return true
		end,
	},
	["wheel_access"] = {
		displayName = "The Talent Compass", category = "access", minRank = 2, cost = 2500,
		displayItemId = 8775, -- a gear wheel (1941 has no items.xml entry and drew a broken plank)
		description = "Bao shows you the Talent Compass. What you make of it is your business.",
		oneTime = true,
		storageKey = BaoConfig.StorageKeys.wheelAccess, -- also sold in the store (5172)
		grant = function(player)
			player:setStorageValue(BaoConfig.StorageKeys.wheelAccess, 1)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
				"Old Man Bao draws a circle in the dirt and does not explain it. The Talent Compass is open to you.")
			return true
		end,
	},
	["charm_slot_7"] = {
		displayName = "A Seventh Charm Slot", category = "access", minRank = 3, cost = 6000,
		displayItemId = 8827, -- a charged ghost charm (the blank rune 3147 read as a grey rock)
		description = "One more creature you can keep a charm on, forever. Stacks on top of whatever your account already allows, Premium or not.",
		oneTime = true,
		grant = function(player)
			return player:addCharmExpansion(1)
		end,
	},
	["charm_slot_8"] = {
		displayName = "An Eighth Charm Slot", category = "access", minRank = 5, cost = 18000,
		displayItemId = 8827,
		description = "The last one Bao will cut for you. He does not explain why there is a limit.",
		oneTime = true,
		requires = "charm_slot_7",
		grant = function(player)
			return player:addCharmExpansion(1)
		end,
	},
	["prey_slot"] = {
		displayName = "Third Prey Slot", category = "access", minRank = 3, cost = 4000,
		displayItemId = 10302, -- a compass -- prey is about tracking something down
		description = "A permanent third Prey slot. No Premium required, ever.",
		oneTime = true,
		storageKey = PREY_PERMANENT_SLOT_KEY, -- also sold in the store (5170)
		grant = function(player)
			player:setStorageValue(PREY_PERMANENT_SLOT_KEY, 1)
			return true
		end,
	},

	-- ── Wheel promotion scrolls ───────────────────────────────────────
	-- Real items (43946-43950) that data/scripts/actions/items/wheel_scrolls.lua
	-- redeems for Wheel points that stay forever -- 10/15/25/40/60 in order
	-- since 2026-09-11 (WheelTables.PROMOTION_SCROLLS; three times the old
	-- 3/5/9/13/20, with the wheel's three points a level). The numbers below
	-- are read from that table so the shop can never disagree with the scroll.
	--
	-- Pricing rises faster than the points do, deliberately: the cheap
	-- scrolls should feel reachable within a couple of bounty weeks and the
	-- advanced one should be a genuine season-long goal.
	["scroll_abridged"] = {
		displayName = "Abridged Promotion Scroll", category = "wheel", minRank = 2, cost = 900,
		description = string.format("+%d Talent Compass points. They stay forever.", WheelTables.PROMOTION_SCROLLS[43946].points),
		itemId = 43946, count = 1, oneTime = true,
	},
	["scroll_basic"] = {
		displayName = "Basic Promotion Scroll", category = "wheel", minRank = 3, cost = 2000,
		description = string.format("+%d Talent Compass points. They stay forever.", WheelTables.PROMOTION_SCROLLS[43947].points),
		itemId = 43947, count = 1, oneTime = true,
	},
	["scroll_revised"] = {
		displayName = "Revised Promotion Scroll", category = "wheel", minRank = 4, cost = 4500,
		description = string.format("+%d Talent Compass points. They stay forever.", WheelTables.PROMOTION_SCROLLS[43948].points),
		itemId = 43948, count = 1, oneTime = true,
	},
	["scroll_extended"] = {
		displayName = "Extended Promotion Scroll", category = "wheel", minRank = 5, cost = 9000,
		description = string.format("+%d Talent Compass points. They stay forever.", WheelTables.PROMOTION_SCROLLS[43949].points),
		itemId = 43949, count = 1, oneTime = true,
	},
	["scroll_advanced"] = {
		displayName = "Advanced Promotion Scroll", category = "wheel", minRank = 6, cost = 18000,
		description = string.format("+%d Talent Compass points. The last thing on the wall.", WheelTables.PROMOTION_SCROLLS[43950].points),
		itemId = 43950, count = 1, oneTime = true,
	},

	-- ── Capacity ──────────────────────────────────────────────────────
	-- The most on-theme purchases in the shop: Bao deepening Bao.
	["hunt_slot_4"] = {
		displayName = "A Fourth Hunt", category = "capacity", minRank = 3, cost = 5000,
		displayItemId = 2822, -- a map -- one more place to be
		description = "Carry four of Bao's hunts at once instead of three.",
		oneTime = true,
		grant = function(player)
			return BaoState.grantExtraSlot(player, 1)
		end,
	},
	["hunt_slot_5"] = {
		displayName = "A Fifth Hunt", category = "capacity", minRank = 5, cost = 15000,
		displayItemId = 347, -- a scroll -- one more contract
		description = "Carry five. Bao will ask if you are sure. He will still say yes.",
		oneTime = true,
		requires = "hunt_slot_4",
		grant = function(player)
			return BaoState.grantExtraSlot(player, 2)
		end,
	},

	-- (The Rune of Mystery left this shop on 2026-10-03: it is now a rare drop from
	-- Surged monsters, see data/scripts/lib/surge.lua. BaoConfig.DORMANCY_RUNE_ID
	-- and BaoConfig.spendRuneCharge below are still the rune's own code.)
}

-- ─── Trophies ───────────────────────────────────────────────────────────
--
-- Purely cosmetic, and the most expensive things Bao owns. That is the point:
-- nothing here changes a number, so pricing them at the top of the curve
-- costs the game's balance nothing while giving the endgame something to
-- actually chase. The last two are meant to take months.
--
-- The thematic tie-ins are deliberate. The bear and wolf mounts are the
-- creatures whose paws you have been handing Bao since level 1, and the Gorgon
-- Hydra is the payoff for every hydra head in the Deep Country bounty pool --
-- you spent the whole game bringing him those, and now you ride one.
BaoConfig.Trophies = {
	{ key = "outfit_hunter",     name = "Hunter's Garb",       rank = 1, cost = 800,
	  desc = "The coat Bao's people wear. You have earned the right to it.",
	  grant = grantOutfit(137, 129, "Hunter"), look = 137, lookFemale = 129 },
	{ key = "mount_rapid_boar",  name = "Rapid Boar",          rank = 1, cost = 1000,
	  desc = "You started out chasing these. Now one carries you.",
	  grant = grantMount(10, "Rapid Boar"), look = 377 },
	{ key = "outfit_wayfarer",   name = "Wayfarer's Clothes",  rank = 2, cost = 2000,
	  desc = "For a hunter who has started going further than the doorstep.",
	  grant = grantOutfit(366, 367, "Wayfarer"), look = 366, lookFemale = 367 },
	{ key = "mount_shadow_hart", name = "Shadow Hart",         rank = 2, cost = 3000,
	  desc = "The stag. Every hunter's first proper quarry, tamed.",
	  grant = grantMount(72, "Shadow Hart"), look = 685 },
	{ key = "mount_war_bear",    name = "War Bear",            rank = 3, cost = 8000,
	  desc = "You have been bringing Bao their paws for years. He noticed.",
	  grant = grantMount(3, "War Bear"), look = 370 },
	{ key = "mount_crystal_wolf", name = "Crystal Wolf",       rank = 3, cost = 8000,
	  desc = "Same arrangement as the bear, and it likes you rather less.",
	  grant = grantMount(16, "Crystal Wolf"), look = 390 },
	{ key = "outfit_beastmaster", name = "Beastmaster's Attire", rank = 3, cost = 5000,
	  desc = "Worn by hunters the animals have stopped arguing with.",
	  grant = grantOutfit(636, 637, "Beastmaster"), look = 636, lookFemale = 637 },
	{ key = "mount_feral_tiger", name = "Feral Tiger",         rank = 4, cost = 20000,
	  desc = "It hunts the way Bao taught you. Respect that, then ride it.",
	  grant = grantMount(124, "Feral Tiger"), look = 1092 },
	{ key = "outfit_dragon_slayer", name = "Dragon Slayer's Plate", rank = 4, cost = 12000,
	  desc = "The old milestone. Everyone knows what it means.",
	  grant = grantOutfit(1289, 1288, "Dragon Slayer"), look = 1289, lookFemale = 1288 },
	{ key = "outfit_dragon_knight", name = "Dragon Knight's Plate", rank = 5, cost = 30000,
	  desc = "Heavier, older, and considerably harder to earn.",
	  grant = grantOutfit(1445, 1444, "Dragon Knight"), look = 1445, lookFemale = 1444 },
	{ key = "mount_emperor_deer", name = "Emperor Deer",       rank = 5, cost = 45000,
	  desc = "The one that got away, every time, for years. Not any more.",
	  grant = grantMount(74, "Emperor Deer"), look = 687 },
	{ key = "outfit_trophy_hunter", name = "Trophy Hunter's Regalia", rank = 6, cost = 100000,
	  desc = "There is no higher compliment Bao can pay you than this coat.",
	  grant = grantOutfit(958, 957, "Trophy Hunter"), look = 958, lookFemale = 957 },
	{ key = "mount_gorgon_hydra", name = "Gorgon Hydra",       rank = 6, cost = 150000,
	  desc = "You have handed Bao a great many hydra heads. He kept the rest.",
	  grant = grantMount(223, "Gorgon Hydra"), look = 1724 },
}

for _, trophy in ipairs(BaoConfig.Trophies) do
	BaoConfig.ShopItems[trophy.key] = {
		displayName = trophy.name, category = "prestige",
		minRank = trophy.rank, cost = trophy.cost,
		description = trophy.desc, oneTime = true,
		grant = trophy.grant,
		-- Preview lookType. An outfit or a mount has no item sprite, so without
		-- this the client drew nothing at all and a 150,000-Mark mount was an
		-- empty row -- the single worst place in the window to show a blank.
		look = trophy.look, lookFemale = trophy.lookFemale,
	}
end


-- ─── Potions, priced per unit ───────────────────────────────────────────
--
-- These used to be fixed bundles at flat prices -- 20 Ultimate Health Potions
-- for 1,600 Marks, which is an entire Chapter VI hunt for something any NPC
-- sells for gold. Dead air, and it made the whole shop look like a junk stall.
--
-- Now the player names the quantity and the price follows it, so the decision
-- is theirs: a stack of potions now, or keep saving for the Wheel. Per-unit
-- costs are deliberately low -- Marks should buy CONVENIENCE here, because
-- anything gold can already buy has no business being expensive in Marks. What
-- the shop charges real Marks for is the things gold cannot touch.
local POTIONS = {
	{ key = "potion_health",      id = 266,   name = "Health Potions",          rank = 0, unit = 2,
	  desc = "The ordinary kind. Bao keeps a crate of them." },
	{ key = "potion_mana",        id = 268,   name = "Mana Potions",            rank = 0, unit = 2,
	  desc = "The ordinary kind. Bao keeps a crate of these too." },
	{ key = "potion_strong_health", id = 236, name = "Strong Health Potions",   rank = 1, unit = 4,
	  desc = "For when the ordinary kind stops keeping up." },
	{ key = "potion_strong_mana", id = 237,  name = "Strong Mana Potions",      rank = 1, unit = 4,
	  desc = "For when the ordinary kind stops keeping up." },
	{ key = "potion_great_health", id = 239, name = "Great Health Potions",     rank = 2, unit = 7,
	  desc = "Hunters who have stopped pretending they are careful." },
	{ key = "potion_great_mana",  id = 238,  name = "Great Mana Potions",       rank = 2, unit = 7,
	  desc = "Hunters who have stopped pretending they are careful." },
	{ key = "potion_great_spirit", id = 7642, name = "Great Spirit Potions",    rank = 3, unit = 9,
	  desc = "Both at once, for those who need both at once." },
	{ key = "potion_ultimate_health", id = 7643, name = "Ultimate Health Potions", rank = 4, unit = 12,
	  desc = "When the great kind stopped being enough." },
	{ key = "potion_ultimate_mana", id = 23373, name = "Ultimate Mana Potions", rank = 4, unit = 12,
	  desc = "When the great kind stopped being enough." },
	{ key = "potion_ultimate_spirit", id = 23374, name = "Ultimate Spirit Potions", rank = 5, unit = 16,
	  desc = "The last word in not dying. Bao charges accordingly." },
}

for _, p in ipairs(POTIONS) do
	BaoConfig.ShopItems[p.key] = {
		displayName = p.name, category = "supplies",
		minRank = p.rank, cost = p.unit, itemId = p.id,
		description = p.desc, oneTime = false,
		-- `scalable` tells the client to draw a quantity stepper and multiply
		-- the price by it. `maxUnits` is a hard server-side ceiling, checked on
		-- purchase -- the stepper is a convenience, never the authority.
		--
		-- (!) 100 because that is the stackable cap. Game.createItem with a
		-- count above it produces an invalid over-stack rather than failing
		-- cleanly, so the ceiling has to match the stack size.
		scalable = true, maxUnits = 100,
	}
end

-- ─── The Rune of Mystery ──────────────────────────────────────────────────
--
-- Item 24960, repurposed from the astral shaper rune. See the comment on that
-- entry in data/items/items.xml for what moved out of the way -- in short, the
-- Astral Shaper quest now grants the Stone Rhino mount directly instead of
-- handing over this rune to be used for taming, so nothing was lost.
--
-- The rune is used directly on the equipment ("Use with...", 2026-09-11):
-- data/scripts/actions/items/rune_of_mystery.lua spends a charge from the
-- rune the player actually used. Before that it was only a charge carrier and
-- a shrine or the Waker spent the charge from whichever rune it found.
BaoConfig.DORMANCY_RUNE_ID = 24960

-- Spends one charge from THIS rune, removing it when its last charge goes.
-- False if it had none to spend. The rune is stackable (2026-09-12) and its
-- charge count IS its stack count now. ITEM_ATTRIBUTE_CHARGES is kept
-- mirrored to the new count on every partial spend -- see the migration
-- comment in rarity_identify.lua for why it is not just dropped.
function BaoConfig.spendRuneCharge(rune)
	if not rune or rune:getCount() <= 0 then
		return false
	end
	local remaining = rune:getCount() - 1
	if remaining <= 0 then
		rune:remove(1)
		return true
	end
	rune:transform(rune:getId(), remaining)
	rune:setAttribute(ITEM_ATTRIBUTE_CHARGES, remaining)
	return true
end

-- ─── Validation ─────────────────────────────────────────────────────────

-- Every entry must be grantable one way or the other, sit in a real category,
-- and -- if it names a prerequisite -- name one that exists.
function BaoConfig.validateShop()
	local problems = 0
	local categories = {}
	for _, c in ipairs(BaoConfig.ShopCategories) do
		categories[c.key] = true
	end

	for key, item in pairs(BaoConfig.ShopItems) do
		if not item.itemId and not item.grant then
			problems = problems + 1
			print(string.format("[Bao] shop entry '%s' has neither itemId nor grant().", key))
		end
		if not categories[item.category] then
			problems = problems + 1
			print(string.format("[Bao] shop entry '%s' is in unknown category '%s'.",
				key, tostring(item.category)))
		end
		if item.requires and not BaoConfig.ShopItems[item.requires] then
			problems = problems + 1
			print(string.format("[Bao] shop entry '%s' requires '%s', which does not exist.",
				key, item.requires))
		end
		if item.itemId and ItemType(item.itemId):getName() == "" then
			problems = problems + 1
			print(string.format("[Bao] shop entry '%s' points at item %d, which has no name in items.xml.",
				key, item.itemId))
		end
	end
	return problems
end

-- Prey is hidden for launch (config.lua preySystemEnabled, 2026-09-16). Bao
-- cannot sell a slot for a window nobody can open, so his entry is dropped
-- while the flag is off. Everything downstream follows from the entry being
-- absent: the shop list is built from pairs(ShopItems), the Profile milestone
-- loop skips a key with no item, the unlock count drops by one, and a crafted
-- purchase packet gets "That item is not available." Nothing else to switch --
-- flip the config flag and his card is back.
if not configManager.getBoolean(configKeys.PREY_SYSTEM_ENABLED) then
	BaoConfig.ShopItems.prey_slot = nil
end

-- Runs at load, like the ladder and bounty checks. An unnamed item or a
-- dangling `requires` is invisible until a player opens the tab and finds a
-- blank row -- cheap to catch here instead.
BaoConfig.validateShop()
