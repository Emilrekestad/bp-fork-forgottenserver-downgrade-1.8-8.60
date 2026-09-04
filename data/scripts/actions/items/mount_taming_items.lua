-- Real Tibia's taming items: use one on its own (no target needed) to
-- permanently unlock the paired mount, consuming the item. Pairings and
-- item/mount ids verified against this datapack's own items.xml/mounts.xml --
-- 38 of real Tibia's 40 taming items have both sides present locally (Flying
-- Book and Ladybug are skipped: their mounts don't exist in mounts.xml).
-- Music Box is deliberately excluded here -- it's a multi-mount choice item,
-- handled separately by actions/items/music_box.lua.
local tamingItems = {
	[12308] = { id = 4,   name = "Black Sheep" },      -- Reins
	[12547] = { id = 16,  name = "Crystal Wolf" },      -- Diapason
	[12548] = { id = 13,  name = "Donkey" },            -- Bag of Apple Slices
	[16155] = { id = 31,  name = "Dragonling" },        -- Decorative Ribbon
	[12307] = { id = 6,   name = "Draptor" },           -- Harness
	[12546] = { id = 20,  name = "Dromedary" },         -- Fist on a Stick
	[31576] = { id = 144, name = "Gryphon" },           -- Regalia of Suon
	[32629] = { id = 162, name = "Haze" },              -- Spectral Scrap of Cloth
	[30171] = { id = 131, name = "Hibernal Moth" },     -- Purple Tendril Lantern
	[16153] = { id = 29,  name = "Ironblight" },        -- Iron Loadstone
	[12550] = { id = 18,  name = "Kingly Deer" },       -- Golden Fir Cone
	[30170] = { id = 130, name = "Lacewing Moth" },     -- Turquoise Tendril Lantern
	[16154] = { id = 30,  name = "Magma Crawler" },     -- Glow Wine
	[14142] = { id = 28,  name = "Manta Ray" },         -- Foxtail
	[12306] = { id = 5,   name = "Midnight Panther" },  -- Leather Whip
	[27605] = { id = 119, name = "Mole" },               -- Candle Stump
	[23684] = { id = 98,  name = "Neon Sparkid" },      -- Crackling Egg
	[21439] = { id = 40,  name = "Noble Lion" },        -- Lion's Heart
	[12311] = { id = 2,   name = "Racing Bird" },       -- Carrot on a Stick
	[12260] = { id = 10,  name = "Rapid Boar" },        -- Hunting Horn
	[22865] = { id = 87,  name = "Rift Runner" },       -- Mysterious Scroll
	[12509] = { id = 21,  name = "Scorpion King" },     -- Scorpion Sceptre
	[20274] = { id = 42,  name = "Shock Head" },        -- Nightmare Horn
	[23538] = { id = 94,  name = "Sparkion" },          -- Vibrant Egg
	-- Stone Rhino (mount 106) is no longer tamed from an item. Its taming item
	-- was 24960, the astral shaper rune, which is now Old Man Bao's Dormancy
	-- Rune -- so Albinius grants the mount directly at the end of the same
	-- quest instead (data/npc/crystalserver/shops/mixed/albinius.lua).
	[12549] = { id = 19,  name = "Tamed Panda" },       -- Bamboo Leaves
	[12519] = { id = 14,  name = "Tiger Slug" },        -- Slug Drug
	[12305] = { id = 8,   name = "Tin Lizzard" },       -- Tin Key
	[12318] = { id = 7,   name = "Titanica" },          -- Giant Shrimp
	[12304] = { id = 12,  name = "Undead Cavebear" },   -- Maxilla Maximus
	[12801] = { id = 15,  name = "Uniwheel" },          -- Golden Can of Oil
	[20355] = { id = 38,  name = "Ursagrodon" },        -- Melting Horn
	[23685] = { id = 99,  name = "Vortexion" },         -- Menacing Egg
	[21186] = { id = 43,  name = "Walker" },            -- Control Unit
	[5907]  = { id = 3,   name = "War Bear" },          -- Slingshot
	[12802] = { id = 17,  name = "War Horse" },         -- Sugar Oat
	[17858] = { id = 35,  name = "Water Buffalo" },     -- Leech
	[12320] = { id = 1,   name = "Widow Queen" },       -- Sweet Smelling Bait
}

local tamingAction = Action()

function tamingAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local mount = tamingItems[item:getId()]
	if not mount then
		return false
	end

	if player:ownsMount(mount.id) then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have already earned the right to ride the " .. mount.name .. ".")
		return true
	end

	if not player:addMount(mount.id) then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "This mount could not be unlocked.")
		return true
	end

	item:remove(1)
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You have earned the right to ride the " .. mount.name .. ".")
	return true
end

for itemId in pairs(tamingItems) do
	tamingAction:id(itemId)
end
tamingAction:register()
