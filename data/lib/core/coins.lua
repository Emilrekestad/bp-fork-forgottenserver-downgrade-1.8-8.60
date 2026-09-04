-- Backpack Coin movements.
--
-- This is the ONLY correct way to change `accounts`.`tibia_coins` from Lua.
-- Every movement is relative, guarded, and writes a `coin_ledger` row inside
-- the same transaction, so the ledger can never disagree with the balance.
--
-- Why relative and guarded matters: the older
-- `player:getTibiaCoins()` / `player:setTibiaCoins()` pair reads a balance and
-- then writes an absolute value derived from that stale read. Two concurrent
-- debits on one account silently clobber each other and mint or destroy
-- coins. `src/coins.h` carries the same warning on the C++ side. The store got
-- away with it because its check and its write sat adjacent on a
-- single-threaded Lua path, but the coin transfer handler did not: it wrote
-- both accounts with two absolute SETs and no transaction at all.
--
-- Kinds are a closed list. `Coins.KINDS` below is the authority; the console's
-- data dictionary is generated from it, and a typo becomes a kind nobody
-- charts rather than a silent miscategorisation, so `Coins.move` rejects any
-- kind it does not know.

Coins = Coins or {}

Coins.MAX = 4294967295

-- Positive kinds add coins, negative kinds remove them. A few are marked
-- "both" because the same movement class legitimately goes either way:
-- an admin grant can be a removal, and a bazaar refund reverses an escrow.
Coins.KINDS = {
	["purchase.paypal"]        = "in",
	["purchase.stripe"]        = "in",   -- reserved, gateway disabled
	["purchase.crypto"]        = "in",   -- reserved, gateway disabled
	["grant.admin"]            = "both",
	["grant.site_reward"]      = "in",
	["redeem.item"]            = "in",
	["transfer.in"]            = "in",
	["transfer.out"]           = "out",
	["spend.store"]            = "both", -- reversal on failed delivery
	["spend.prey_slot"]        = "both",
	["spend.task_slot"]        = "both",
	["spend.battlepass"]       = "both",
	["bazaar.escrow"]          = "out",
	["bazaar.release"]         = "in",
	["bazaar.payout"]          = "in",
	["bazaar.fee"]             = "out",
	["bazaar.promotion"]       = "out",
	["bazaar.refund"]          = "in",
	["charbazaar.escrow"]      = "out",
	["charbazaar.release"]     = "in",
	["charbazaar.payout"]      = "in",
	["charbazaar.fee"]         = "out",
	["charbazaar.commission"]  = "out",
	["adjust.opening"]         = "both",
	["adjust.reconcile"]       = "both",
	["legacy.unknown"]         = "both", -- only from the deprecated wrappers
}

local function escaped(value)
	return db.escapeString(tostring(value))
end

local function nullable(value)
	if value == nil or value == "" then
		return "NULL"
	end
	return escaped(value)
end

local function readBalance(accountId)
	local resultId = db.storeQuery(string.format(
		"SELECT `tibia_coins` FROM `accounts` WHERE `id` = %d", accountId))
	if not resultId then
		return nil
	end
	local balance = result.getNumber(resultId, "tibia_coins")
	result.free(resultId)
	return balance
end

--- Moves coins and records why.
-- @param accountId number
-- @param delta number signed; negative removes
-- @param kind string one of Coins.KINDS
-- @param ref table|nil {type = "shop_history", id = 42}
-- @param meta table|nil free-form context, stored as JSON
-- @param playerId number|nil the character in play, when there is one
-- @return boolean ok, number|string balanceOrError
function Coins.move(accountId, delta, kind, ref, meta, playerId)
	accountId = tonumber(accountId) or 0
	delta = math.floor(tonumber(delta) or 0)

	if accountId <= 0 then
		return false, "invalid account"
	end
	if not Coins.KINDS[kind] then
		return false, "unknown coin kind: " .. tostring(kind)
	end
	if delta == 0 then
		return true, readBalance(accountId) or 0
	end

	local newBalance
	local failure

	local committed = db.transaction(function()
		-- Relative and guarded. The WHERE clause is the concurrency control:
		-- an insufficient balance or an overflow changes no rows, and we fail
		-- rather than write a wrong number.
		local guard
		if delta < 0 then
			guard = string.format(
				"UPDATE `accounts` SET `tibia_coins` = `tibia_coins` - %d WHERE `id` = %d AND `tibia_coins` >= %d",
				-delta, accountId, -delta)
		else
			guard = string.format(
				"UPDATE `accounts` SET `tibia_coins` = `tibia_coins` + %d WHERE `id` = %d AND `tibia_coins` <= %d",
				delta, accountId, Coins.MAX - delta)
		end

		if not db.query(guard) then
			failure = "coin update failed"
			error(failure)
		end
		if db.affectedRows() ~= 1 then
			failure = delta < 0 and "insufficient coins" or "coin balance would overflow"
			error(failure)
		end

		newBalance = readBalance(accountId)
		if not newBalance then
			failure = "could not read balance back"
			error(failure)
		end

		local refType, refId = nil, nil
		if type(ref) == "table" then
			refType, refId = ref.type, ref.id
		end

		if not db.query(string.format(
			"INSERT INTO `coin_ledger` " ..
			"(`ts`, `account_id`, `player_id`, `delta`, `balance_after`, `kind`, `ref_type`, `ref_id`, `meta`, `source`) " ..
			"VALUES (%d, %d, %s, %d, %d, %s, %s, %s, %s, 'lua')",
			os.time(),
			accountId,
			playerId and tostring(math.floor(playerId)) or "NULL",
			delta,
			newBalance,
			escaped(kind),
			nullable(refType),
			nullable(refId),
			meta and escaped(json.encode(meta)) or "NULL"
		)) then
			failure = "could not write the coin ledger"
			error(failure)
		end
	end)

	if not committed then
		return false, failure or "coin transaction rolled back"
	end
	return true, newBalance
end

--- Removes coins from a player's account.
function Coins.spend(player, amount, kind, ref, meta)
	if not player then
		return false, "no player"
	end
	amount = math.abs(math.floor(tonumber(amount) or 0))
	return Coins.move(player:getAccountId(), -amount, kind, ref, meta, player:getGuid())
end

--- Adds coins to a player's account.
function Coins.grant(player, amount, kind, ref, meta)
	if not player then
		return false, "no player"
	end
	amount = math.abs(math.floor(tonumber(amount) or 0))
	return Coins.move(player:getAccountId(), amount, kind, ref, meta, player:getGuid())
end

--- Current balance for an account id, or 0 when unknown.
function Coins.balance(accountId)
	return readBalance(tonumber(accountId) or 0) or 0
end

--- Moves coins between two accounts atomically.
-- Both legs and both ledger rows share one transaction and one reference, so
-- a transfer is either fully recorded or never happened. Replaces the old
-- two-absolute-SET path in the game store.
-- @return boolean ok, string|nil error
function Coins.transfer(fromAccountId, toAccountId, amount, meta, fromPlayerId)
	fromAccountId = tonumber(fromAccountId) or 0
	toAccountId = tonumber(toAccountId) or 0
	amount = math.abs(math.floor(tonumber(amount) or 0))

	if fromAccountId <= 0 or toAccountId <= 0 then
		return false, "invalid account"
	end
	if fromAccountId == toAccountId then
		return false, "cannot transfer to the same account"
	end
	if amount <= 0 then
		return false, "amount must be positive"
	end

	-- One reference ties the two legs together in the ledger.
	local reference = string.format("%d:%d:%d:%d", fromAccountId, toAccountId, amount, os.time())
	local failure

	local committed = db.transaction(function()
		if not db.query(string.format(
			"UPDATE `accounts` SET `tibia_coins` = `tibia_coins` - %d WHERE `id` = %d AND `tibia_coins` >= %d",
			amount, fromAccountId, amount)) or db.affectedRows() ~= 1 then
			failure = "insufficient coins"
			error(failure)
		end
		if not db.query(string.format(
			"UPDATE `accounts` SET `tibia_coins` = `tibia_coins` + %d WHERE `id` = %d AND `tibia_coins` <= %d",
			amount, toAccountId, Coins.MAX - amount)) or db.affectedRows() ~= 1 then
			failure = "the recipient cannot hold that many coins"
			error(failure)
		end

		local now = os.time()
		local legs = {
			{account = fromAccountId, delta = -amount, kind = "transfer.out", player = fromPlayerId},
			{account = toAccountId,   delta = amount,  kind = "transfer.in",  player = nil},
		}
		for _, leg in ipairs(legs) do
			local balance = readBalance(leg.account)
			if not balance then
				failure = "could not read balance back"
				error(failure)
			end
			if not db.query(string.format(
				"INSERT INTO `coin_ledger` " ..
				"(`ts`, `account_id`, `player_id`, `delta`, `balance_after`, `kind`, `ref_type`, `ref_id`, `meta`, `source`) " ..
				"VALUES (%d, %d, %s, %d, %d, %s, 'transfer', %s, %s, 'lua')",
				now,
				leg.account,
				leg.player and tostring(math.floor(leg.player)) or "NULL",
				leg.delta,
				balance,
				escaped(leg.kind),
				escaped(reference),
				meta and escaped(json.encode(meta)) or "NULL"
			)) then
				failure = "could not write the coin ledger"
				error(failure)
			end
		end
	end)

	if not committed then
		return false, failure or "transfer rolled back"
	end
	return true
end
