-- Loyalty programme core.
--
-- Reads the append-only ledger in `loyalty_premium_log`, derives tenure into
-- `loyalty_account`, and applies rewards to characters.
--
-- Two scoping facts drive the whole design:
--
-- 1. Loyalty is ACCOUNT-scoped, but `player_outfits` and `player_mounts` are
--    PLAYER-scoped. So an outfit is not granted once -- it is RECONCILED on
--    every login, which is what makes a character created next year still
--    receive the outfit its account earned last year.
--
-- 2. The website never writes items. It inserts a row into `loyalty_claims`
--    and the server delivers it. `player_storeinboxitems` is TFS's serialised
--    item format and is rewritten wholesale when the character saves -- a row
--    inserted by PHP while that character is online is destroyed on next save.

dofile('data/lib/loyalty/loyalty_config.lua')

Loyalty = Loyalty or {}

local function today()
	return os.date("%Y-%m-%d")
end

-- Stamps every currently-premium account for today, and records that the
-- stamper ran. Idempotent: safe to call repeatedly within one day.
function Loyalty.stampToday()
	local day = db.escapeString(today())

	db.query(string.format([[
		INSERT IGNORE INTO `loyalty_premium_log` (`account_id`, `day`)
		SELECT `id`, %s FROM `accounts` WHERE `premium_ends_at` > %d
	]], day, os.time()))

	db.query(string.format([[
		INSERT INTO `loyalty_stamp_days` (`day`, `stamped_at`, `accounts`)
		VALUES (%s, %d, (SELECT COUNT(*) FROM `loyalty_premium_log` WHERE `day` = %s))
		ON DUPLICATE KEY UPDATE `stamped_at` = VALUES(`stamped_at`), `accounts` = VALUES(`accounts`)
	]], day, os.time(), day))
end

-- Rewrites `loyalty_ladder` from LoyaltyConfig. Called at startup so the
-- website always renders the ladder the server is actually enforcing.
--
-- Rows are replaced, not merged: a reward deleted from the config disappears
-- from the site too. Already-delivered claims are unaffected -- loyalty_claims
-- holds no foreign key here precisely so retiring a reward never erases the
-- record of someone having received it.
function Loyalty.publishLadder()
	local keep = {}

	for _, reward in ipairs(LoyaltyConfig.Rewards) do
		-- Preview looktype: an outfit previews as its FIRST listed lookType
		-- (the gendered pair renders the same costume either way), a mount as
		-- its client id, an item as nothing -- items draw from sprite files.
		local lookType = 0
		if reward.kind == "outfit" then
			lookType = (reward.lookTypes or {})[1] or 0
		elseif reward.kind == "mount" then
			lookType = reward.clientId or 0
		end

		keep[#keep + 1] = db.escapeString(reward.id)
		db.query(string.format([[
			INSERT INTO `loyalty_ladder`
				(`reward_id`, `days`, `kind`, `name`, `description`, `item_id`, `count`,
				 `look_type`, `look_addons`)
			VALUES (%s, %d, %s, %s, %s, %d, %d, %d, %d)
			ON DUPLICATE KEY UPDATE
				`days` = VALUES(`days`), `kind` = VALUES(`kind`),
				`name` = VALUES(`name`), `description` = VALUES(`description`),
				`item_id` = VALUES(`item_id`), `count` = VALUES(`count`),
				`look_type` = VALUES(`look_type`), `look_addons` = VALUES(`look_addons`)
		]],
			db.escapeString(reward.id), reward.days, db.escapeString(reward.kind),
			db.escapeString(reward.name or reward.id), db.escapeString(reward.description or ""),
			reward.itemId or 0, reward.count or 1,
			lookType, reward.addons or 0))
	end

	if #keep > 0 then
		db.query("DELETE FROM `loyalty_ladder` WHERE `reward_id` NOT IN (" .. table.concat(keep, ",") .. ")")
	else
		db.query("DELETE FROM `loyalty_ladder`")
	end
end

-- Recomputes derived state from the ledger.
--
-- Days the stamper never ran are SKIPPED rather than treated as lapses -- they
-- are absent from loyalty_stamp_days, so an outage cannot break a streak.
function Loyalty.recompute(accountId)
	local premium = {}
	local resultId = db.storeQuery(string.format(
		"SELECT `day` FROM `loyalty_premium_log` WHERE `account_id` = %d", accountId))
	if resultId ~= false then
		repeat
			premium[result.getString(resultId, "day")] = true
		until not result.next(resultId)
		result.free(resultId)
	end

	local premiumDays, streak, bestStreak = 0, 0, 0

	resultId = db.storeQuery("SELECT `day` FROM `loyalty_stamp_days` ORDER BY `day` ASC")
	if resultId ~= false then
		repeat
			if premium[result.getString(resultId, "day")] then
				premiumDays = premiumDays + 1
				streak = streak + 1
				if streak > bestStreak then
					bestStreak = streak
				end
			else
				streak = 0
			end
		until not result.next(resultId)
		result.free(resultId)
	end

	db.query(string.format([[
		INSERT INTO `loyalty_account`
			(`account_id`, `premium_days`, `streak_days`, `best_streak`, `updated_at`)
		VALUES (%d, %d, %d, %d, %d)
		ON DUPLICATE KEY UPDATE
			`premium_days` = VALUES(`premium_days`),
			`streak_days` = VALUES(`streak_days`),
			`best_streak` = VALUES(`best_streak`),
			`updated_at` = VALUES(`updated_at`)
	]], accountId, premiumDays, streak, bestStreak, os.time()))

	return { premiumDays = premiumDays, streak = streak, bestStreak = bestStreak }
end

function Loyalty.getState(accountId)
	local resultId = db.storeQuery(string.format([[
		SELECT `premium_days`, `streak_days`, `best_streak`
		FROM `loyalty_account` WHERE `account_id` = %d
	]], accountId))
	if resultId == false then
		return Loyalty.recompute(accountId)
	end

	local state = {
		premiumDays = result.getNumber(resultId, "premium_days"),
		streak = result.getNumber(resultId, "streak_days"),
		bestStreak = result.getNumber(resultId, "best_streak"),
	}
	result.free(resultId)
	return state
end

-- Every reward the account has reached.
function Loyalty.earnedRewards(premiumDays)
	local earned = {}
	for _, reward in ipairs(LoyaltyConfig.Rewards) do
		if reward.days <= premiumDays then
			earned[#earned + 1] = reward
		end
	end
	return earned
end

-- The soonest reward not yet reached, and how many days away it is.
function Loyalty.nextReward(premiumDays)
	local best = nil
	for _, reward in ipairs(LoyaltyConfig.Rewards) do
		if reward.days > premiumDays and (not best or reward.days < best.days) then
			best = reward
		end
	end
	if not best then
		return nil
	end
	return best, best.days - premiumDays
end

-- Grants the auto-applied rewards (outfit / mount) to one character.
-- Idempotent by construction: each underlying add is a no-op when the
-- character already has it, so this runs on every login without a ledger of
-- what was already applied.
function Loyalty.reconcilePlayer(player)
	local state = Loyalty.getState(player:getAccountId())
	local granted = 0

	for _, reward in ipairs(Loyalty.earnedRewards(state.premiumDays)) do
		if reward.kind == "outfit" then
			-- Both gendered lookTypes are granted. A character can only wear
			-- the one matching its sex, but granting both means a sex change
			-- -- or a differently-sexed character made later -- never silently
			-- loses a reward the account already earned.
			for _, lookType in ipairs(reward.lookTypes or {}) do
				if not player:hasOutfit(lookType, reward.addons or 0) then
					player:addOutfitAddon(lookType, reward.addons or 0)
					granted = granted + 1
				end
			end
		elseif reward.kind == "mount" then
			if not player:hasMount(reward.mountId) then
				player:addMount(reward.mountId)
				granted = granted + 1
			end
		end
	end

	return state, granted
end

-- Delivers claims the website queued for this character.
--
-- Mirrors gamestore.lua's delivery path exactly (getStoreInbox + addItemEx),
-- because that is the only supported way to put an item in a store inbox --
-- the table behind it is engine-owned.
function Loyalty.deliverClaims(player)
	local guid = player:getId()
	local pending = {}

	local resultId = db.storeQuery(string.format(
		"SELECT `id`, `reward_id` FROM `loyalty_claims` WHERE `player_id` = %d AND `status` = 'pending'",
		guid))
	if resultId == false then
		return 0, 0
	end
	repeat
		pending[#pending + 1] = {
			id = result.getNumber(resultId, "id"),
			rewardId = result.getString(resultId, "reward_id"),
		}
	until not result.next(resultId)
	result.free(resultId)

	if #pending == 0 then
		return 0, 0
	end

	local byId = {}
	for _, reward in ipairs(LoyaltyConfig.Rewards) do
		byId[reward.id] = reward
	end

	local delivered = 0
	for _, claim in ipairs(pending) do
		local reward = byId[claim.rewardId]
		local failure = nil

		if not reward or reward.kind ~= "item" then
			-- A reward id no longer in config. Leave it pending and say so,
			-- rather than marking it delivered and losing the claim.
			failure = "unknown reward"
		else
			local inbox = player:getStoreInbox()
			if not inbox then
				failure = "no store inbox"
			else
				local item = Game.createItem(reward.itemId, reward.count or 1)
				if not item then
					failure = "item creation failed"
				elseif inbox:addItemEx(item) ~= RETURNVALUE_NOERROR then
					item:remove()
					failure = "store inbox full"
				end
			end
		end

		if failure then
			-- Stays 'pending' on a transient failure (a full inbox clears
			-- itself once the player makes room), so the next login retries.
			db.query(string.format(
				"UPDATE `loyalty_claims` SET `note` = %s WHERE `id` = %d",
				db.escapeString(failure), claim.id))
		else
			db.query(string.format(
				"UPDATE `loyalty_claims` SET `status` = 'delivered', `delivered_at` = %d, `note` = '' WHERE `id` = %d",
				os.time(), claim.id))
			player:sendTextMessage(MESSAGE_STATUS_SMALL,
				string.format("%s was sent to your store inbox.", reward.name))
			delivered = delivered + 1
		end
	end

	return delivered, #pending - delivered
end

-- The character shown on the public loyalty board.
--
-- `accounts.name` is a LOGIN CREDENTIAL and must never appear publicly, so the
-- board is fronted by a character instead. Players nominate one on the
-- website; until they do, their highest-level living character stands in.
--
-- The nomination is re-validated against the account on every read rather than
-- trusted, so a character that was deleted -- or a row left behind by a
-- transferred character -- falls back instead of showing a stale name.
function Loyalty.getPrimaryPlayerId(accountId)
	local nominated = 0
	local resultId = db.storeQuery(string.format(
		"SELECT `primary_player_id` FROM `loyalty_account` WHERE `account_id` = %d", accountId))
	if resultId ~= false then
		nominated = result.getNumber(resultId, "primary_player_id")
		result.free(resultId)
	end

	if nominated > 0 then
		resultId = db.storeQuery(string.format(
			"SELECT `id` FROM `players` WHERE `id` = %d AND `account_id` = %d AND `deletion` = 0",
			nominated, accountId))
		if resultId ~= false then
			result.free(resultId)
			return nominated
		end
	end

	resultId = db.storeQuery(string.format([[
		SELECT `id` FROM `players`
		WHERE `account_id` = %d AND `deletion` = 0
		ORDER BY `level` DESC, `experience` DESC LIMIT 1
	]], accountId))
	if resultId == false then
		return 0
	end

	local fallback = result.getNumber(resultId, "id")
	result.free(resultId)
	return fallback
end

function Loyalty.setPrimaryPlayerId(accountId, playerId)
	local resultId = db.storeQuery(string.format(
		"SELECT `id` FROM `players` WHERE `id` = %d AND `account_id` = %d AND `deletion` = 0",
		playerId, accountId))
	if resultId == false then
		return false
	end
	result.free(resultId)

	db.query(string.format([[
		INSERT INTO `loyalty_account` (`account_id`, `primary_player_id`, `updated_at`)
		VALUES (%d, %d, %d)
		ON DUPLICATE KEY UPDATE
			`primary_player_id` = VALUES(`primary_player_id`),
			`updated_at` = VALUES(`updated_at`)
	]], accountId, playerId, os.time()))
	return true
end
