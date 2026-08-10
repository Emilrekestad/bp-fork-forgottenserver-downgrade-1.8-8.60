local firstItems = CreatureEvent("FirstItems")
function firstItems.onLogin(player)
	return true -- new characters start with no gear
end
firstItems:register()
