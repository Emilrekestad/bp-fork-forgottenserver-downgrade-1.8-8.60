-- One-time testing grant for "Harding": Tibia Coins, Prey Wildcards, bank
-- gold, and a teleport to Thais temple. Separate flag from the earlier
-- Knight setup / Roshamuul teleport scripts so it doesn't redo either.

local GRANT_FLAG = 990003

local hardingGrant = CreatureEvent("HardingTestingGrant")

function hardingGrant.onLogin(player)
	if player:getName() ~= "Harding" then
		return true
	end

	if player:getStorageValue(GRANT_FLAG) == 1 then
		return true
	end

	Coins.grant(player, 5000, "grant.admin", nil, {actor = "harding_testing_grant", reason = "test character setup"})
	player:setPreyWildcards(player:getPreyWildcards() + 300)
	player:setBankBalance(player:getBankBalance() + 30000000)
	player:teleportTo(Position(32369, 32241, 7))

	player:setStorageValue(GRANT_FLAG, 1)
	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Testing grant applied: +5000 Bp Coins, +300 Prey Wildcards, +30,000,000 bank gold, teleported to Thais temple.")

	return true
end

hardingGrant:register()
