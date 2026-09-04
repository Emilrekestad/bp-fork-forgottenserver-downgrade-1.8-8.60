-- Item Rarity system — GM-only debug command. Force-rolls rarity on the item
-- on the ground/tile in front of the caller. Ported from the third-party
-- download's talkactions/scripts/roll.lua unchanged in logic, registered
-- under this fork's talkaction conventions (see
-- data/scripts/talkactions/god/bao/bao_gm_commands.lua for the same
-- accountType(6):access(true) gating pattern).
--
-- Usage: /roll            -- random tier, revealed immediately
--        /roll scarce     -- forced scarce, revealed immediately
--        /roll adept      -- forced adept, revealed immediately
--        /roll superior   -- forced superior, revealed immediately
--        /roll prime      -- forced prime (renamed 2026-08-25, was
--                             rare/epic/legendary; prime is a new 4th tier),
--                             revealed immediately
--        /roll dormant    -- forced random tier (Adept+ guaranteed, same as
--                             any Dormant roll), but goes through the real
--                             Dormant flow instead of skipping it -- use this
--                             specifically to test identify, not the tier
--                             names above (those bypass Dormant on purpose,
--                             so testing a specific tier's numbers stays fast)

local roll = TalkAction("/roll")

function roll.onSay(player, words, param)
	local position = player:getPosition()
	position:getNextPosition(player:getDirection())

	local tile = Tile(position)
	if not tile then
		player:sendCancelMessage("Object not found.")
		return false
	end

	local thing = tile:getTopVisibleThing(player)
	if not thing then
		player:sendCancelMessage("Thing not found.")
		return false
	end

	if thing:isItem() then
		if thing == tile:getGround() then
			player:sendCancelMessage("There is nothing here to roll.")
			return false
		end
		local forcedTier = param
		local skipDormant = true
		if forcedTier == "" then
			forcedTier = true
		elseif forcedTier == "dormant" then
			forcedTier = true
			skipDormant = false
		end
		RarityStats.rollRarity(thing, forcedTier, skipDormant)
		position:sendMagicEffect(73) -- matches the original download's effect id

		-- Report the item's actual raw server-side state back to the GM,
		-- bypassing the client's look-text distance rendering entirely
		-- (getAttribute reads ITEM_ATTRIBUTE_DESCRIPTION directly, not
		-- through internalItemGetDescription's lookDistance <= 1 gate) --
		-- this is debug tooling, so show ground truth, not what "look"
		-- happens to display from wherever the GM is standing.
		local article = thing:getAttribute(ITEM_ATTRIBUTE_ARTICLE)
		local rawDesc = thing:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION)
		local itemClass = RarityClass.getItemClass(thing:getId())
		if not skipDormant and thing:getTier() == RarityStats.DORMANT_TIER then
			-- Dormant path: nothing about the actual roll is decided yet --
			-- that only happens live, on identify (RarityIdentify.reveal) --
			-- so there's nothing to preview here beyond confirming the item
			-- is correctly marked.
			player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("[Rarity] Rolled Dormant (Class %d item). Use a Dormant Shrine or Waker to identify and roll for real.",
				itemClass))
		elseif article and article ~= "" and (article:find("scarce") or article:find("adept") or article:find("superior") or article:find("prime")) then
			-- Count locked ([...]) vs open ((...)) bonus lines for quick
			-- verification that slot count/lock chance are behaving as
			-- designed, without having to manually count brackets by eye.
			local _, lockedCount = string.gsub(rawDesc or "", "%[%a", "")
			local _, openCount = string.gsub(rawDesc or "", "%(%a", "")
			player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("[Rarity] Rolled '%s' (Class %d, %d locked / %d open). Raw description attribute: %s",
				article, itemClass, lockedCount, openCount, (rawDesc and rawDesc ~= "") and rawDesc or "(EMPTY -- no stats were applied, this is a bug)"))
		else
			player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("[Rarity] No tier rolled (Class %d item -- may have zero eligible stats, or -- for a natural /roll -- simply missed the odds).", itemClass))
		end
	end
	return true
end

roll:separator(" ")
roll:accountType(6)
roll:access(true)
roll:register()
