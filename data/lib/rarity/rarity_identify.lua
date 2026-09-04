-- Item Rarity system -- Dormant identify. A Dormant item hasn't rolled its
-- actual tier/stats yet -- it only knows it's Dormant-worthy (see the
-- RarityStats.rollRarity Dormant branch in rarity_stats.lua). Identifying it
-- rolls it for real, live, via the exact same rollRarity function everything
-- else in this system uses (forced=true, skipDormant=true), so there's no
-- separate cache of "what it will be" that could ever go stale. Triggered by
-- at a Dormant Shrine or by using a Dormant Waker (item 39241), see the two
-- action scripts. It is no longer a direct "Use" on the item itself (that had
-- a bad UX interaction for item types the client treats as multi-use).

RarityIdentify = {}

-- Reveals a Dormant item for real. Returns true on success; false if the
-- item wasn't actually Dormant (no message sent -- caller decides how to
-- react).
function RarityIdentify.reveal(player, item)
	if item:getTier() ~= RarityStats.DORMANT_TIER then
		return false
	end

	-- forced=true guarantees a tier; skipDormant=true applies it to the item
	-- immediately instead of re-marking it Dormant again.
	RarityStats.rollRarity(item, true, true)

	local article = item:getAttribute(ITEM_ATTRIBUTE_ARTICLE)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("The dormant power awakens -- your item is %s!", article or "identified"))
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	return true
end

-- Puts one eligible ordinary equipment item to sleep by spending a charged
-- Dormancy Rune. Shared by the free temple shrine and the portable Store
-- tool so both routes follow the exact same validation and never consume a
-- charge on an invalid target.
function RarityIdentify.putToSleep(player, item)
	if item:getTier() == RarityStats.DORMANT_TIER then
		return false
	end

	if not BaoConfig or not BaoConfig.findDormancyRune then
		player:sendTextMessage(MESSAGE_FAILURE, "Dormancy Runes are not available right now.")
		return false
	end

	local itemType = ItemType(item:getId())
	if itemType:getSlotPosition() == 0 then
		player:sendTextMessage(MESSAGE_FAILURE, "Only equipment can be put to sleep.")
		return false
	end
	if item:getCount() > 1 then
		player:sendTextMessage(MESSAGE_FAILURE, "Put one aside first -- a stack cannot be put to sleep.")
		return false
	end

	if not BaoConfig.findDormancyRune(player) then
		player:sendTextMessage(MESSAGE_FAILURE,
			"You need a charged Dormancy Rune. Old Man Bao sells them for Bao Marks.")
		return false
	end
	if not BaoConfig.spendDormancyCharge(player) then
		player:sendTextMessage(MESSAGE_FAILURE, "Your Dormancy Rune has no charges left.")
		return false
	end

	item:setTier(RarityStats.DORMANT_TIER)
	item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, "Dormant")
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION,
		"This item pulses with dormant power. Awaken it at a Dormant Shrine or with a Dormant Waker.")
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"The rune goes cold in your hand. Your %s is dormant now. Wake it when you are ready.",
		itemType:getName()))
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
	return true
end
