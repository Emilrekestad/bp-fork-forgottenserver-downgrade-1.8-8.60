-- A Father's Burden: the two corpse-search steps (Wyvern Heoni's sinew, the
-- dragon Glitterscale's scale). Ported from opentibiabr/canary's
-- fathers_burden/actions_corpse.lua (2026-08-26) - verified against our own
-- items.xml (11589 "dead Glitterscale", 11590 "dead Heoni", 11550 "flexible
-- dragon scale", 11548 "strong sinew" all exist under those exact names, no
-- id remapping needed). Position-agnostic - these corpse items can appear
-- anywhere the real monster dies, same as any other corpse.
local config = {
	[11589] = {itemId = 11550, storage = PlayerStorageKeys.FathersBurdenQuest.Corpse.Scale, text = "Glitterscale's scale."},
	[11590] = {itemId = 11548, storage = PlayerStorageKeys.FathersBurdenQuest.Corpse.Sinew, text = "Heoni's sinew"},
}

local fatherCorpse = Action()

function fatherCorpse.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local corpse = config[item.itemid]
	if not corpse then
		return true
	end

	if player:getStorageValue(corpse.storage) == 1 then
		return false
	end

	player:addItem(corpse.itemId, 1)
	player:setStorageValue(corpse.storage, 1)
	player:say("You acquired " .. corpse.text, TALKTYPE_MONSTER_SAY)
	return true
end

for itemId in pairs(config) do
	fatherCorpse:id(itemId)
end
fatherCorpse:register()
