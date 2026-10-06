-- Kazordoon ore wagons. Each wagon (item 7131/7132 with an action id) is named by the sign
-- above its rail; using the wagon takes you to that place. Free for everyone.
--
-- The five places and where the wagons deliver you:
local PLACES = {
	["Main Gate"] = Position(32577, 31972, 9),
	["Temple"] = Position(32628, 31923, 11),
	["Shops"] = Position(32607, 31905, 9),
	["Depot"] = Position(32657, 31904, 8),
	["Steamship"] = Position(32676, 31977, 15),
	["Kazordoon Surface North"] = Position(32601, 31873, 7),
	["Colossus Top"] = Position(32578, 31930, 0),
	["Kazordoon Surface South"] = Position(32617, 31947, 7),
	["Kazordoon Surface West"] = Position(32550, 31931, 7),
	["the Surface station"] = Position(32618, 31901, 9),
}

-- wagon action id -> place (read off the signs: z15 station 32672-32680,31974; z11 station
-- 32624-32632,31920; z8 station 32653-32661,31901; z9 stations 32604,31901-31909 and 32574,31969-31978)
local WAGONS = {
	[50148] = "Main Gate", [50149] = "Temple", [50150] = "Shops", [50151] = "Depot", -- z15
	[50144] = "Main Gate", [50145] = "Steamship", [50146] = "Shops", [50147] = "Depot", -- z11
	[50152] = "Main Gate", [50153] = "Temple", [50154] = "Shops", [50155] = "Steamship", -- z8
	[50159] = "Main Gate", [50158] = "Depot", [50157] = "Temple", [50156] = "Steamship", -- z9, x32604 (the last sign reads "Steamboat to Cormaya")
	[50136] = "the Surface station", [50137] = "the Surface station", [50138] = "the Surface station", [50139] = "the Surface station", -- the surface wagons: down to the station
	[50230] = "Kazordoon Surface North", [50231] = "Colossus Top", [50232] = "Kazordoon Surface South", [50233] = "Kazordoon Surface West", -- z9, x32615-32621
	[50143] = "Depot", [50142] = "Shops", [50141] = "Temple", [50140] = "Steamship", -- z9, x32574 (the Main Gate station; last sign "Steamboat to Cormaya")
}

local wagon = Action()

function wagon.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if item.itemid ~= 7131 and item.itemid ~= 7132 then
		return false
	end
	local place = WAGONS[item.actionid]
	local destination = place and PLACES[place]
	if not destination then
		return false
	end
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(destination)
	destination:sendMagicEffect(CONST_ME_TELEPORT)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The wagon carries you to " .. (place:find("^the ") and place or ("the " .. place)) .. ".")
	return true
end

for actionId in pairs(WAGONS) do
	wagon:aid(actionId)
end
wagon:register()
