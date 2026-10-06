-- GM test command: /refill fills your health and mana to the maximum.
local refill = TalkAction("/refill")

function refill.onSay(player, words, param)
	player:addHealth(player:getMaxHealth() - player:getHealth())
	player:addMana(player:getMaxMana() - player:getMana())
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
	return false
end

refill:separator(" ")
refill:accountType(6)
refill:register()
