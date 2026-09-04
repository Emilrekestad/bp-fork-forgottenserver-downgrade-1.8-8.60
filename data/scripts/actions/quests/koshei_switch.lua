-- Koshei the Deathless: the sundial switch that opens the coffin once the 5
-- statues are in the right pattern. Ported from opentibiabr/canary's
-- koshei_the_deathless_quest/action_switch.lua (2026-08-26) - the switch
-- itself (uid 3070) is a real, already-placed map object ("sundial", item
-- 7534), found via a map scan. Statue/coffin item ids (2062/2063 for the
-- statues, 162/167 for the closed/open coffin) all verified against our own
-- items.xml under those exact names.
local config = {
	{position = Position(33276, 32444, 8), itemId = 2062},
	{position = Position(33278, 32450, 8), itemId = 2062},
	{position = Position(33284, 32450, 8), itemId = 2062},
	{position = Position(33281, 32442, 8), itemId = 2063},
	{position = Position(33286, 32444, 8), itemId = 2063},
}

local coffinPosition = Position(33273, 32458, 8)

local function revertCoffin()
	local coffinItem = Tile(coffinPosition):getItemById(167)
	if coffinItem then
		coffinItem:transform(162)
	end
end

local kosheiSwitch = Action()

function kosheiSwitch.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local statuesInOrder = true
	for i = 1, #config do
		local statue = config[i]
		if not Tile(statue.position):getItemById(statue.itemId) then
			statuesInOrder = false
			break
		end
	end

	if not statuesInOrder or Tile(coffinPosition):getItemById(167) then
		player:say("Nothing happens", TALKTYPE_MONSTER_SAY, false, player, toPosition)
		return true
	end

	local coffinItem = Tile(coffinPosition):getItemById(162)
	if coffinItem then
		coffinItem:transform(167)
		addEvent(revertCoffin, 2 * 60 * 1000)
		player:say("CLICK", TALKTYPE_MONSTER_SAY, false, player, coffinPosition)
	end
	return true
end

kosheiSwitch:uid(3070)
kosheiSwitch:register()
