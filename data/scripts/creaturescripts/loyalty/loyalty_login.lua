-- Loyalty on login: recompute tenure, apply account-wide rewards to this
-- character, deliver anything the website queued, and point the player at the
-- account page when something is waiting there.
--
-- Reconciliation runs for EVERY character, every login, not once per account.
-- Outfits and mounts are player-scoped in the schema, so a character created
-- after a reward was earned would otherwise never receive it.

local loyaltyLogin = CreatureEvent("LoyaltyLogin")

function loyaltyLogin.onLogin(player)
	local accountId = player:getAccountId()
	if not accountId or accountId == 0 then
		return true
	end

	-- Recompute first: premium may have been bought on the website since the
	-- last login, and the day count gates everything below.
	Loyalty.recompute(accountId)

	local state, granted = Loyalty.reconcilePlayer(player)
	local delivered, stillPending = Loyalty.deliverClaims(player)

	-- Deferred so the messages land after the client has finished logging in;
	-- text sent inside onLogin itself is routinely dropped by the client.
	addEvent(function(playerId)
		local target = Player(playerId)
		if not target then
			return
		end

		if granted > 0 then
			target:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE,
				"Loyalty: a reward has been unlocked on this character.")
		end

		if not LoyaltyConfig.NotifyOnLogin then
			return
		end

		-- Anything earned but not yet claimed on the website.
		local claimedCount = 0
		local resultId = db.storeQuery(string.format(
			"SELECT COUNT(*) AS `n` FROM `loyalty_claims` WHERE `account_id` = %d", accountId))
		if resultId ~= false then
			claimedCount = result.getNumber(resultId, "n")
			result.free(resultId)
		end

		local claimable = 0
		for _, reward in ipairs(Loyalty.earnedRewards(state.premiumDays)) do
			if reward.kind == "item" then
				claimable = claimable + 1
			end
		end

		local unclaimed = math.max(0, claimable - claimedCount)
		if unclaimed > 0 then
			target:sendTextMessage(MESSAGE_STATUS_CONSOLE_ORANGE, string.format(
				"Loyalty: you have %d reward%s waiting. Claim %s at backpackot.com under Account Management.",
				unclaimed, unclaimed == 1 and "" or "s", unclaimed == 1 and "it" or "them"))
		end

		if stillPending and stillPending > 0 then
			target:sendTextMessage(MESSAGE_STATUS_CONSOLE_ORANGE,
				"Loyalty: a claimed reward could not be delivered -- make room in your store inbox and relog.")
		end

		local nextReward, daysLeft = Loyalty.nextReward(state.premiumDays)
		if nextReward and daysLeft <= 7 then
			target:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
				"Loyalty: %d more premium day%s until you earn the %s.",
				daysLeft, daysLeft == 1 and "" or "s", nextReward.name))
		end
	end, 1500, player:getId())

	return true
end

loyaltyLogin:register()
