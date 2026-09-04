local TIBIA_COINS_ITEM_ID = 22118
local MAX_TIBIA_COINS = 4294967295

local function shopHistoryExists()
	if db.tableExists then
		return db.tableExists("shop_history")
	end
	return true
end

local function addCoinHistory(player, amount)
	if not shopHistoryExists() then
		return
	end

	db.query("INSERT INTO `shop_history` (`account`, `player`, `date`, `title`, `price`, `costSecond`, `count`, `target`) VALUES (" ..
		player:getAccountId() .. ", " ..
		player:getGuid() .. ", NOW(), " ..
		db.escapeString("Bp Coins Item") .. ", " ..
		amount .. ", 0, 1, " ..
		db.escapeString("Item " .. TIBIA_COINS_ITEM_ID) .. ")")
end

local tibiaCoins = Action()

function tibiaCoins.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local currentCoins = player:getTibiaCoins()
	if currentCoins >= MAX_TIBIA_COINS then
		player:sendCancelMessage("You already have the maximum Bp Coins.")
		return true
	end

	local amount = math.min(item:getCount(), MAX_TIBIA_COINS - currentCoins)
	if amount <= 0 then
		player:sendCancelMessage("Could not redeem Bp Coins.")
		return true
	end

	-- Credit first. The old order wrote the balance and then removed the item,
	-- so a failed write left the player with neither. Now a failure leaves the
	-- item in the backpack, which is the recoverable side.
	local credited, newBalance = Coins.grant(player, amount, "redeem.item", nil, {
		item_id = TIBIA_COINS_ITEM_ID,
		amount_on_item = amount,
	})
	if not credited then
		player:sendCancelMessage("Could not redeem Bp Coins.")
		return true
	end

	item:remove(amount)
	addCoinHistory(player, amount)

	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "You redeemed " .. amount .. " Bp Coins. New balance: " .. newBalance .. ".")
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
	return true
end

tibiaCoins:id(TIBIA_COINS_ITEM_ID)
tibiaCoins:register()
