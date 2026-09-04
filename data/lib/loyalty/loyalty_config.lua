-- Loyalty programme configuration.
--
-- Rewards unlock on PREMIUM DAYS drawn from `loyalty_premium_log`, never from
-- `accounts.premium_ends_at` (a deadline carries no history). One number, and
-- it means exactly what it says: 365 means 365 premium days on the account.
--
-- There is deliberately no tier abstraction. A reward is a name, a day count
-- and a thing you get -- anything more was a layer nobody asked for.
--
-- The streak is a COUNTER only. It is displayed, but it does not gate or
-- accelerate anything: a lapse costs the days missed and nothing else.
--
-- Hard rule: loyalty pays in COSMETICS AND DECORATION, never in power. No
-- reward may grant a stat, a rate, or an item with combat value -- tenure must
-- never become an edge, or lapsing premium becomes a competitive penalty
-- rather than a missed keepsake.

LoyaltyConfig = LoyaltyConfig or {}

-- Reward kinds:
--   outfit -- granted to EVERY character on the account, existing and future.
--             `lookTypes` is a LIST because outfits are gender-split in
--             outfits.xml (Discoverer is 1094 male / 1095 female). Granting
--             only one leaves half the account's characters unable to wear
--             the reward they earned, with nothing to explain why.
--   mount  -- mount id, likewise granted to every character.
--   item   -- NOT auto-granted. Shown on the account page as claimable; the
--             player picks one character and it lands in that character's
--             store inbox. One claim per account, enforced by
--             UNIQUE(account_id, reward_id) on loyalty_claims.
--
-- `id` is the stable key written into loyalty_claims.reward_id. It is a
-- database value: NEVER renumber or rename one that has shipped, or existing
-- claims orphan and the reward becomes claimable a second time.
LoyaltyConfig.Rewards = {
	{
		-- (!) The Citizen outfit itself is `unlocked="yes"` in outfits.xml, so
		-- every character already owns the base look. The reward here is
		-- genuinely the ADDONS -- addOutfitAddon(128, 3) is what does the work,
		-- and without addons = 3 this entry would grant nothing at all.
		id = "outfit_citizen", days = 10, kind = "outfit",
		lookTypes = { 128, 136 }, addons = 3,
		name = "Citizen Outfit",
		description = "Both addons, on every character.",
	},
	{
		-- (!) 22121 is INFERRED, not verified. items.xml declares 22120-22121
		-- as one range sharing a single definition, and no script in this
		-- codebase references either id, so nothing here distinguishes the
		-- activated doll from the dormant one. The higher id of such a pair is
		-- conventionally the activated variant. Both are valid items so this
		-- passes validation either way -- eyeball it in-game and swap to 22120
		-- if the sprite is wrong.
		id = "doll_little_adventurer", days = 75, kind = "item",
		itemId = 22121, count = 1,
		name = "Little Adventurer Doll",
		description = "A small companion who has already seen a great deal.",
	},
	{
		-- `clientId` is the mount's CLIENT id from mounts.xml (218 -> 1632).
		-- It is used only to draw the preview on the website, which goes
		-- through an outfit imager that knows nothing about server ids.
		id = "mount_foxmouse", days = 100, kind = "mount",
		mountId = 218, clientId = 1632,
		name = "Foxmouse",
		description = "Unlocked on every character, including ones you make later.",
	},
	{
		id = "bp_25_years", days = 250, kind = "item",
		itemId = 39693, count = 1,
		name = "25 Years Backpack",
		description = "A commemorative backpack.",
	},
	{
		id = "doll_gamemaster", days = 300, kind = "item",
		itemId = 4100, count = 1,
		name = "Gamemaster Doll",
		description = "Strictly decorative. It cannot kick anyone.",
	},
	{
		id = "outfit_discoverer", days = 365, kind = "outfit",
		lookTypes = { 1094, 1095 }, addons = 3,
		name = "Discoverer Outfit",
		description = "Full outfit with both addons, on every character.",
	},
	{
		id = "outfit_royal_costume", days = 730, kind = "outfit",
		lookTypes = { 1456, 1457 }, addons = 3,
		name = "Royal Costume",
		description = "Full outfit with both addons, on every character.",
	},

}

-- Substituted, same day thresholds as originally specified:
--   30 days  -- "Adventurer Backpack" does not exist in this items.xml (nor
--               under the possessive spelling), so the Expedition Backpack
--               (10324) carries the adventuring intent.
--   150 days -- "15 Years Backpack" does not exist either; only the 25-years
--               line does. The Anniversary Backpack (14674) is the
--               commemorative backpack this server actually has.
-- Swap either for a real id if you would rather have something else.
table.insert(LoyaltyConfig.Rewards, 1, {
	id = "bp_expedition", days = 30, kind = "item",
	itemId = 10324, count = 1,
	name = "Expedition Backpack",
	description = "Your first month on the road.",
})

table.insert(LoyaltyConfig.Rewards, {
	id = "bp_anniversary", days = 150, kind = "item",
	itemId = 14674, count = 1,
	name = "Anniversary Backpack",
	description = "A commemorative backpack.",
})

-- Keep the list in day order regardless of where entries were appended, so
-- the published ladder and every UI that reads it agree on sequence.
table.sort(LoyaltyConfig.Rewards, function(a, b)
	if a.days == b.days then
		return a.id < b.id
	end
	return a.days < b.days
end)

LoyaltyConfig.NotifyOnLogin = true

-- An unreachable or malformed entry grants nothing and errors nowhere -- the
-- same silent failure that cost Bao's ladder 17 hunts before it was caught.
-- Validate loud, and refuse to publish a ladder that fails.
function LoyaltyConfig.validateLadder()
	local ok = true
	local seenId = {}

	for _, reward in ipairs(LoyaltyConfig.Rewards) do
		local label = tostring(reward.id)

		if seenId[reward.id] then
			print("[Loyalty] DUPLICATE REWARD ID '" .. label .. "'")
			ok = false
		end
		seenId[reward.id] = true

		if type(reward.days) ~= "number" or reward.days < 1 then
			print(string.format("[Loyalty] REWARD '%s' has an invalid day threshold (%s)",
				label, tostring(reward.days)))
			ok = false
		end

		if reward.kind == "item" then
			local itemType = ItemType(reward.itemId or 0)
			if not itemType or itemType:getId() == 0 then
				print(string.format("[Loyalty] REWARD '%s' names item %s, which does not exist",
					label, tostring(reward.itemId)))
				ok = false
			elseif itemType:getName() == "" then
				-- An id present in items.otb but absent from items.xml resolves
				-- to a nameless item. It looks valid here and is worthless
				-- in-game, so treat it as a failure rather than ship it.
				print(string.format("[Loyalty] REWARD '%s' names item %d, which has no items.xml entry",
					label, reward.itemId))
				ok = false
			end

		elseif reward.kind == "outfit" then
			if type(reward.lookTypes) ~= "table" or #reward.lookTypes == 0 then
				print(string.format("[Loyalty] REWARD '%s' must list at least one lookType", label))
				ok = false
			end

		elseif reward.kind == "mount" then
			if type(reward.mountId) ~= "number" then
				print(string.format("[Loyalty] REWARD '%s' has no mountId", label))
				ok = false
			end

		else
			print(string.format("[Loyalty] REWARD '%s' has unknown kind '%s'",
				label, tostring(reward.kind)))
			ok = false
		end
	end

	if ok then
		print(string.format("[Loyalty] Ladder OK -- %d rewards.", #LoyaltyConfig.Rewards))
	end
	return ok
end
