-- Job contracts -- the only way a hireling learns a trade.
--
-- Each contract is a physical item the player uses ON a specific hireling, so
-- the job binds to that hireling and not to the character. That is why
-- Hireling:enableSkill exists rather than a Player-level unlock: see the note
-- above Hireling:hasSkill in data/scripts/lib/hireling.lua.
--
-- These three ids are repurposed items that were unused by loot, shops,
-- scripts and the map. They carry FLAG_USEABLE in items.otb and
-- ThingAttrMultiUse in Tibia.dat -- BOTH are required, or the player cannot
-- target the hireling at all: the client hides "Use with" without the dat
-- attribute, and Game::playerUseWithCreature rejects the packet without the
-- otb flag.
local CONTRACTS = {
	[128] = HIRELING_SKILLS.TRADER,   -- trader's contract
	[22706] = HIRELING_SKILLS.BANKER, -- banker's contract
	[23547] = HIRELING_SKILLS.COOKING, -- cook's contract
}

local hirelingContracts = Action()

local function hirelingSystemEnabled()
	return configManager and configKeys and configKeys.HIRELING_SYSTEM_ENABLED and
		configManager.getBoolean(configKeys.HIRELING_SYSTEM_ENABLED)
end

local function fail(player, message)
	player:getPosition():sendMagicEffect(CONST_ME_POFF)
	player:sendTextMessage(MESSAGE_FAILURE, message)
	return true
end

function hirelingContracts.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local contract = CONTRACTS[item.itemid]
	if not contract then
		return false
	end

	if not hirelingSystemEnabled() then
		return fail(player, "The hireling system is disabled.")
	end

	-- target is whatever the player clicked: a creature, an item, or nothing.
	if not target or type(target) ~= "userdata" or not target.isCreature or not target:isCreature() then
		return fail(player, "You have to use this on one of your hirelings.")
	end

	local hireling = getHirelingByCid(target:getId())
	if not hireling then
		return fail(player, "Only a hireling can take up a trade.")
	end

	if hireling:getOwnerId() ~= player:getGuid() then
		return fail(player, "This is not your hireling.")
	end

	local skillName = contract[2]
	if hireling:hasSkill(skillName) then
		-- Bail BEFORE removing the item: a wasted contract on a hireling who
		-- already has the job would be unrecoverable.
		return fail(player, hireling:getName() .. " has already taken up this trade.")
	end

	if not hireling:enableSkill(skillName) then
		return fail(player, "The contract could not be signed. Please try again.")
	end

	item:remove(1)

	local npc = Npc(target:getId())
	if npc then
		npc:say("I shall study this at once!", TALKTYPE_PRIVATE_NP, false, player, npc:getPosition())
	end
	target:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
		hireling:getName() .. " has taken up the " .. skillName .. " trade. Ask about {services} to see what changed.")
	return true
end

for itemId in pairs(CONTRACTS) do
	hirelingContracts:id(itemId)
end

hirelingContracts:allowFarUse(false)
hirelingContracts:register()
