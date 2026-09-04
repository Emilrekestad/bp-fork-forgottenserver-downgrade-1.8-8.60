-- Runtime map-data repair for quest chests that a map-data scan (2026-08-25)
-- found either untagged (no unique id) or entirely absent from world.otbm.
-- TFS's Lua API exposes item:setActionId() but NOT a unique-id setter, so
-- this is done via action id instead - functionally equivalent for our
-- purposes, but it means these chests are NOT the "real" map objects the
-- original quest content expected; they're a scripted stand-in until someone
-- places/tags the real ones in RME. See quest_map_repair_rewards.lua for the
-- matching Action handlers, and the report delivered alongside this change
-- for exactly what still needs manual placement.
--
-- Idempotent: safe to run on every boot.

local ev = GlobalEvent("questMapRepair")

local ROOKGAARD_CHAIN_ARMOR_ACTIONID = 60201

-- "Large trunk" containers next to the one Rookgaard chest that's already
-- correctly wired (2473/uid 64129/aid 2000 at 32097,32187,8) - all three
-- currently have uid=0 and aid=0 (pure decoration). We can't tell which one
-- (if any) was the intended Chain Armor Quest trunk, so all three are wired
-- to one shared storage: whichever the player opens first pays out, the
-- rest report empty - matches the "search several, only one has it" feel of
-- the original quest even though we're guessing at the room.
local rookgaardTrunkCandidates = {
	{pos = Position(32116, 32187, 8), itemid = 2483},
	{pos = Position(32117, 32187, 8), itemid = 2483},
	{pos = Position(32114, 32188, 8), itemid = 2485},
}

local ROOKGAARD_DOUBLET_ACTIONID = 60202

-- Doublet Quest: like Chain Armor, DoubletQuest (storage 64121) exists as a
-- reserved key but was never wired to any chest anywhere on the map (2026-08-25
-- scan). No adjacent "already working" chest to anchor a guess off of here, so
-- this is a single best-effort pick (user confirmed "pick a reasonable spot"
-- rather than wait) - an untouched, undecorated "chest" near the surface
-- level of Rookgaard, away from the Chain Armor trunk room.
local rookgaardDoubletCandidate = {pos = Position(32171, 32197, 7), itemid = 2472}

-- Black Knight Villa - CORRECTED 2026-08-26 after owner pushback ("those
-- need the Crown reward", "the keys should be in trees outside of the villa
-- and in the wild"). Verified against TibiaWiki + our own map:
--   - The boss room (32874,31948,11, radius 15) has the exact monster set
--     the wiki describes (2 Bonelords, 2 Scorpions, Black Knight) - real,
--     not a guess.
--   - The two southern dead trees IN that room (uid 9270, 9277 - found via
--     a full-map tagged-item sweep) give the Crown Armor/Shield -  wired
--     directly in system_orts.lua now, no synthetic spawn needed, they're
--     real map objects.
--   - Key 5010 comes from "2 dead trees west of the villa" in Green Claw
--     Swamp per TibiaWiki - these ARE real, untagged decoration on our map
--     (item 3634, confirmed present, no unique id), found via a map-wide
--     scan for every dead tree west of the boss room. Tagged here rather
--     than spawned, since the trees themselves already exist.
local BLACK_KNIGHT_TREE_KEY_ACTIONID = 60303
local blackKnightKeyTrees = {
	{pos = Position(32761, 31983, 7), itemid = 3634},
	{pos = Position(32767, 31987, 7), itemid = 3634},
}

local INQUISITION_VAMPIRE_ALTAR_ACTIONID = 60401

-- The Inquisition Quest - Vampire Hunt (Mission 3): ported from the
-- avelino/Otxserver-New reference (2026-08-26). Positions confirmed real on
-- our own map (item 2342 sits at all 3, consistently) even though the
-- reference's own item id (2199, "obelisk" in our items.xml) isn't what's
-- actually there - adapted to tag the real item instead of guessing a
-- replacement. See inquisition_vampire_hunt.lua for the trigger logic.
local inquisitionVampireAltars = {
	{pos = Position(32777, 31982, 9), itemid = 2342},
	{pos = Position(32779, 31977, 9), itemid = 2342},
	{pos = Position(32781, 31982, 9), itemid = 2342},
}

function ev.onStartup()
	local tagged = 0
	for _, candidate in ipairs(rookgaardTrunkCandidates) do
		local tile = Tile(candidate.pos)
		if tile then
			local item = tile:getItemById(candidate.itemid)
			if item and item:getActionId() ~= ROOKGAARD_CHAIN_ARMOR_ACTIONID then
				item:setActionId(ROOKGAARD_CHAIN_ARMOR_ACTIONID)
				tagged = tagged + 1
			end
		else
			print(">> [questMapRepair] WARNING: no tile at Rookgaard trunk candidate " .. candidate.pos.x .. "," .. candidate.pos.y .. "," .. candidate.pos.z)
		end
	end

	do
		local tile = Tile(rookgaardDoubletCandidate.pos)
		if tile then
			local item = tile:getItemById(rookgaardDoubletCandidate.itemid)
			if item and item:getActionId() ~= ROOKGAARD_DOUBLET_ACTIONID then
				item:setActionId(ROOKGAARD_DOUBLET_ACTIONID)
				tagged = tagged + 1
			end
		else
			print(">> [questMapRepair] WARNING: no tile at Rookgaard doublet candidate " .. rookgaardDoubletCandidate.pos.x .. "," .. rookgaardDoubletCandidate.pos.y .. "," .. rookgaardDoubletCandidate.pos.z)
		end
	end

	for _, tree in ipairs(blackKnightKeyTrees) do
		local tile = Tile(tree.pos)
		if tile then
			local item = tile:getItemById(tree.itemid)
			if item and item:getActionId() ~= BLACK_KNIGHT_TREE_KEY_ACTIONID then
				item:setActionId(BLACK_KNIGHT_TREE_KEY_ACTIONID)
				tagged = tagged + 1
			end
		else
			print(">> [questMapRepair] WARNING: no tile at Black Knight key tree spot " .. tree.pos.x .. "," .. tree.pos.y .. "," .. tree.pos.z)
		end
	end

	for _, altar in ipairs(inquisitionVampireAltars) do
		local tile = Tile(altar.pos)
		if tile then
			local item = tile:getItemById(altar.itemid)
			if item and item:getActionId() ~= INQUISITION_VAMPIRE_ALTAR_ACTIONID then
				item:setActionId(INQUISITION_VAMPIRE_ALTAR_ACTIONID)
				tagged = tagged + 1
			end
		else
			print(">> [questMapRepair] WARNING: no tile at Inquisition vampire altar " .. altar.pos.x .. "," .. altar.pos.y .. "," .. altar.pos.z)
		end
	end

	print(">> [questMapRepair] Tagged " .. tagged .. " total items (Rookgaard trunks/doublet chest, Black Knight key trees, Inquisition altars)")
end

ev:type("startup")
ev:register()
