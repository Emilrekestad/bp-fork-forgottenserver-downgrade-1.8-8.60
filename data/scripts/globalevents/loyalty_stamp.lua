-- Daily premium stamper.
--
-- Runs hourly rather than once a day on purpose: a once-daily timer loses the
-- whole day if the server happens to be down when it fires, and the ledger's
-- value is precisely that it has no holes. Stamping is idempotent
-- (INSERT IGNORE on a composite PK), so the extra runs cost one query.

local loyaltyStamp = GlobalEvent("LoyaltyPremiumStamp")

function loyaltyStamp.onThink(interval)
	Loyalty.stampToday()
	return true
end

loyaltyStamp:interval(60 * 60 * 1000)
loyaltyStamp:register()

-- Validate the ladder at startup. An orphaned reward or a non-increasing
-- threshold grants nothing and errors nowhere -- the same silent failure that
-- cost Bao's ladder 17 hunts before it was caught.
local loyaltyStartup = GlobalEvent("LoyaltyStartup")

function loyaltyStartup.onStartup()
	if LoyaltyConfig.validateLadder() then
		-- Only publish a ladder that validated. Pushing a broken one would put
		-- rewards on the website that the server will never actually grant.
		Loyalty.publishLadder()
	else
		print("[Loyalty] Ladder NOT published to the website -- fix the errors above.")
	end
	Loyalty.stampToday()
	return true
end

loyaltyStartup:register()
