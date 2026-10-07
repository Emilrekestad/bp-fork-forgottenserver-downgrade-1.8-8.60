function Player.getPlayerDatabaseInfo(name_or_guid)
	local sql_where = ""

	if type(name_or_guid) == 'string' then
		sql_where = "WHERE `p`.`name`=" .. db.escapeString(name_or_guid) .. ""
	elseif type(name_or_guid) == 'number' then
		sql_where = "WHERE `p`.`id`='" .. name_or_guid .. "'"
	else
		return false
	end

	local sql_query = [[
		SELECT
			`p`.`id` as `guid`,
			`p`.`name`,
			CASE WHEN `po`.`player_id` IS NULL
				THEN 0
				ELSE 1
			END AS `online`,
			`p`.`group_id`,
			`p`.`level`,
			`p`.`experience`,
			`p`.`vocation`,
			`p`.`maglevel`,
			`p`.`skill_fist`,
			`p`.`skill_club`,
			`p`.`skill_sword`,
			`p`.`skill_axe`,
			`p`.`skill_dist`,
			`p`.`skill_shielding`,
			`p`.`skill_fishing`,
			`p`.`town_id`,
			`p`.`balance`,
			`gm`.`guild_id`,
			`gm`.`nick`,
			`g`.`name` AS `guild_name`,
			CASE WHEN `p`.`id` = `g`.`ownerid`
				THEN 1
				ELSE 0
			END AS `is_leader`,
			`gr`.`name` AS `rank_name`,
			`gr`.`level` AS `rank_level`,
			`h`.`id` AS `house_id`,
			`h`.`name` AS `house_name`,
			`h`.`town_id` AS `house_town`
		FROM `players` AS `p`
		LEFT JOIN `players_online` AS `po`
			ON `p`.`id` = `po`.`player_id`
		LEFT JOIN `guild_membership` AS `gm`
			ON `p`.`id` = `gm`.`player_id`
		LEFT JOIN `guilds` AS `g`
			ON `gm`.`guild_id` = `g`.`id`
		LEFT JOIN `guild_ranks` AS `gr`
			ON `gm`.`rank_id` = `gr`.`id`
		LEFT JOIN `houses` AS `h`
			ON `p`.`id` = `h`.`owner`
	]] .. sql_where

	local query = db.storeQuery(sql_query)
	if not query then return false end

	local info = {
		["guid"] = result.getNumber(query, "guid"),
		["name"] = result.getString(query, "name"),
		["online"] = result.getNumber(query, "online"),
		["group_id"] = result.getNumber(query, "group_id"),
		["level"] = result.getNumber(query, "level"),
		["experience"] = result.getNumber(query, "experience"),
		["vocation"] = result.getNumber(query, "vocation"),
		["maglevel"] = result.getNumber(query, "maglevel"),
		["skill_fist"] = result.getNumber(query, "skill_fist"),
		["skill_club"] = result.getNumber(query, "skill_club"),
		["skill_sword"] = result.getNumber(query, "skill_sword"),
		["skill_axe"] = result.getNumber(query, "skill_axe"),
		["skill_dist"] = result.getNumber(query, "skill_dist"),
		["skill_shielding"] = result.getNumber(query, "skill_shielding"),
		["skill_fishing"] = result.getNumber(query, "skill_fishing"),
		["town_id"] = result.getNumber(query, "town_id"),
		["balance"] = result.getNumber(query, "balance"),
		["guild_id"] = result.getNumber(query, "guild_id"),
		["nick"] = result.getString(query, "nick"),
		["guild_name"] = result.getString(query, "guild_name"),
		["is_leader"] = result.getNumber(query, "is_leader"),
		["rank_name"] = result.getString(query, "rank_name"),
		["rank_level"] = result.getNumber(query, "rank_level"),
		["house_id"] = result.getNumber(query, "house_id"),
		["house_name"] = result.getString(query, "house_name"),
		["house_town"] = result.getNumber(query, "house_town")
	}

	result.free(query)
	return info
end

local foodCondition = Condition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
function Player.feed(self, food)
	local condition = self:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	if condition then
		condition:setTicks(condition:getTicks() + (food * 1000))
	else
		local vocation = self:getVocation()
		if not vocation then return nil end

		foodCondition:setTicks(food * 1000)
		foodCondition:setParameter(CONDITION_PARAM_HEALTHGAIN, vocation:getHealthGainAmount())
		foodCondition:setParameter(CONDITION_PARAM_HEALTHTICKS, vocation:getHealthGainTicks() * 1000)
		foodCondition:setParameter(CONDITION_PARAM_MANAGAIN, vocation:getManaGainAmount())
		foodCondition:setParameter(CONDITION_PARAM_MANATICKS, vocation:getManaGainTicks() * 1000)

		self:addCondition(foodCondition)
	end
	return true
end

function Player.isSorcerer(self)
	return table.contains({ VOCATION.ID.SORCERER, VOCATION.ID.MASTER_SORCERER }, self:getVocation():getId())
end

function Player.isDruid(self)
	return table.contains({ VOCATION.ID.DRUID, VOCATION.ID.ELDER_DRUID }, self:getVocation():getId())
end

function Player.isKnight(self)
	return table.contains({ VOCATION.ID.KNIGHT, VOCATION.ID.ELITE_KNIGHT }, self:getVocation():getId())
end

function Player.isPaladin(self)
	return table.contains({ VOCATION.ID.PALADIN, VOCATION.ID.ROYAL_PALADIN }, self:getVocation():getId())
end

function Player.isMage(self)
	return table.contains({ VOCATION.ID.SORCERER, VOCATION.ID.MASTER_SORCERER, VOCATION.ID.DRUID, VOCATION.ID.ELDER_DRUID }, self:getVocation():getId())
end

function Player.isMonk(self)
	if not configManager.getBoolean(configKeys.MONK_VOCATION_ENABLED) then
		return false
	end

	return table.contains({ VOCATION.ID.MONK, VOCATION.ID.EXALTED_MONK }, self:getVocation():getId())
end

function Player.getClosestFreePosition(self, position, extended)
	if self:getGroup():getAccess() and self:getAccountType() >= ACCOUNT_TYPE_GOD then return position end
	return Creature.getClosestFreePosition(self, position, extended)
end

function Player.getDepotItems(self, depotId)
	return self:getDepotChest(depotId, true):getItemHoldingCount()
end

function Player.hasFlag(self, flag) return self:getGroup():hasFlag(flag) end

function Player.getLossPercent(self)
	local blessings = 0
	for i = 1, 8 do
		if self:hasBlessing(i) then
			blessings = blessings + 1
		end
	end
	local blessingReduction = blessings * 8
	local basePenalty = self:getDeathPenalty()
	local finalPenalty = math.max(0, basePenalty - blessingReduction)
	return finalPenalty
end

function Player.getPremiumTime(self) return math.max(0, self:getPremiumEndsAt() - os.time()) end

function Player.setPremiumTime(self, seconds)
	self:setPremiumEndsAt(os.time() + seconds)
	return true
end

function Player.addPremiumTime(self, seconds)
	self:setPremiumTime(self:getPremiumTime() + seconds)
	return true
end

function Player.removePremiumTime(self, seconds)
	local currentTime = self:getPremiumTime()
	if currentTime < seconds then return false end

	self:setPremiumTime(currentTime - seconds)
	return true
end

function Player.getPremiumDays(self) return math.floor(self:getPremiumTime() / 86400) end

function Player.addPremiumDays(self, days) return self:addPremiumTime(days * 86400) end

function Player.removePremiumDays(self, days) return self:removePremiumTime(days * 86400) end

function Player.isPremium(self)
	return self:getPremiumTime() > 0 or configManager.getBoolean(configKeys.FREE_PREMIUM) or
		       self:hasFlag(PlayerFlag_IsAlwaysPremium)
end

---@param message string|number
function Player.sendCancelMessage(self, message)
	if type(message) == "number" then message = Game.getReturnMessage(message) end
	return self:sendTextMessage(MESSAGE_STATUS_SMALL, message)
end

function Player.isUsingOtClient(self)
	if self.isUsingOtc and self:isUsingOtc() then
		return true
	end

	if self.isUsingOtcV8 and self:isUsingOtcV8() then
		return true
	end

	local client = self:getClient()
	local os = client and client.os or CLIENTOS_NONE
	return os == CLIENTOS_OTCLIENT_LINUX or os == CLIENTOS_OTCLIENT_WINDOWS or os == CLIENTOS_OTCLIENT_MAC or
		       (os >= CLIENTOS_OTCLIENTV8_LINUX and os <= CLIENTOS_OTCLIENTV8_WEB)
end

function Player.sendExtendedOpcode(self, opcode, buffer)
	if not self:isUsingOtClient() then return false end
	buffer = buffer or ""
	if type(buffer) ~= "string" then
		buffer = tostring(buffer)
	end
	-- NetworkMessage::addString silently refuses strings above 8192 bytes.
	-- Avoid sending a malformed packet containing only 0x32 + opcode.
	if #buffer > 8192 then
		return false
	end

	local networkMessage<close> = NetworkMessage()
	networkMessage:addByte(0x32)
	networkMessage:addByte(opcode)
	networkMessage:addString(buffer)
	networkMessage:sendToPlayer(self)
	return true
end

function Player.sendFightMode(self)
	if not self:isUsingOtClient() then return false end

	local msg<close> = NetworkMessage()
	msg:addByte(0xA7)
	msg:addByte(self:getFightMode())
	msg:addByte(self:isChasingEnabled() and 1 or 0)
	msg:addByte(self:isSecureModeEnabled() and 1 or 0)
	msg:sendToPlayer(self)
	return true
end

-- ---------------------------------------------------------------------------
-- Integrity saves (docs/security/dupe-and-crash-audit-2026-09-08.md)
--
-- Players used to be written to the database only on logout and at the daily
-- server save, so a crash rolled everyone back by up to a day. Every transfer
-- that persists ONE side immediately (mail to an offline player, bank
-- transfer, guild bank, stash, market, house) duplicated value on the next
-- crash. Player.saveOnTransfer is the fix: an asynchronous, coalesced save of
-- the party whose state only lived in memory. It is called from every transfer
-- path and from the periodic autosave, and it never blocks the dispatcher.
--
-- saveAsync() returns false while a flush for the same player is still in
-- flight (SaveManager::schedulePlayerFlush). The snapshot in that flush
-- predates the transfer, so a false is retried rather than dropped.
-- ---------------------------------------------------------------------------
IntegritySave = IntegritySave or {
	lastSave = {},   -- guid -> os.mtime() of the last queued save
	nextAllowed = {}, -- guid -> earliest ms a new save may be queued
	pending = {},    -- guid -> true while a deferred save is scheduled
	MIN_INTERVAL_MS = 2500,
	RETRY_MS = 1000,
	MAX_RETRIES = 5,
}

local function integrityQueue(playerId, guid, reason, attempt)
	IntegritySave.pending[guid] = nil
	local player = Player(playerId)
	if not player then
		-- Logged out in the meantime; logout already saved synchronously.
		return
	end
	if player:saveAsync() then
		IntegritySave.lastSave[guid] = os.mtime()
		IntegritySave.nextAllowed[guid] = os.mtime() + IntegritySave.MIN_INTERVAL_MS
		return
	end
	if attempt < IntegritySave.MAX_RETRIES then
		IntegritySave.pending[guid] = true
		addEvent(integrityQueue, IntegritySave.RETRY_MS, playerId, guid, reason, attempt + 1)
	else
		logger.warn("[IntegritySave] gave up queueing save for %s (%s) after %d attempts",
			player:getName(), tostring(reason), attempt)
	end
end

--- Queue an asynchronous save of this player because value just moved.
-- Coalesces bursts: at most one queued save per MIN_INTERVAL_MS per player,
-- with the trailing call deferred rather than dropped, so the final state
-- after a burst of transfers is always the one that lands on disk.
function Player.saveOnTransfer(self, reason)
	if not self or not self.isPlayer or not self:isPlayer() then
		return false
	end
	local guid = self:getGuid()
	if IntegritySave.pending[guid] then
		return true
	end
	local now = os.mtime()
	local wait = (IntegritySave.nextAllowed[guid] or 0) - now
	if wait <= 0 then
		integrityQueue(self:getId(), guid, reason, 1)
	else
		IntegritySave.pending[guid] = true
		addEvent(integrityQueue, wait, self:getId(), guid, reason, 1)
	end
	return true
end

--- Milliseconds since this player's last queued integrity/autosave save, or
--- nil when none has happened this session. Used by the autosave sweep.
function Player.getIntegritySaveAge(self)
	local last = IntegritySave.lastSave[self:getGuid()]
	if not last then
		return nil
	end
	return os.mtime() - last
end

-- Every bank-balance change is a value transfer, so treat the setter itself as
-- the hook. Found 2026-09-08 during the crash tests: the old XML-system banker
-- scripts (data/npc/scripts/Naji.lua and about twenty copies) never call the
-- helpers above. They write the balance straight to the database with
-- doPlayerSetBalance plus an UPDATE, while the coins they took only left
-- memory, so a crash after a deposit returned the coins AND kept the balance.
-- Wrapping the C++ setter covers those and every future caller at once; the
-- save is coalesced, so a burst of balance changes costs one save.
do
	local rawSetBankBalance = Player.setBankBalance
	function Player.setBankBalance(self, balance)
		local result = rawSetBankBalance(self, balance)
		self:saveOnTransfer("balance")
		return result
	end
end

-- Always pass the number through the isValidMoney function first before using the transferMoneyTo
function Player.transferMoneyTo(self, target, amount)
	if not target then return false end
	if isValidMoney and not isValidMoney(amount) then return false end

	-- See if you can afford this transfer
	local balance = self:getBankBalance()
	if amount > balance then return false end

	-- See if player is online
	local targetPlayer = Player(target.guid)
	if targetPlayer then
		targetPlayer:setBankBalance(targetPlayer:getBankBalance() + amount)
	else
		-- Security audit 2026-10-05 (ECON-6 / PERS-6): a direct UPDATE while the
		-- receiver is logging in, or has a save flush in flight, is overwritten by
		-- that flush (the gold vanishes while the sender's ledger says it arrived).
		-- Refuse; the sender simply tries again a moment later.
		if Game.isPlayerSavePending and Game.isPlayerSavePending(target.guid) then
			return false
		end
		db.query("UPDATE `players` SET `balance` = `balance` + " .. amount .. " WHERE `id` = '" ..
			         target.guid .. "'")
	end

	self:setBankBalance(self:getBankBalance() - amount)

	-- The receiver is either saved by their own transfer save (online) or was
	-- written straight to the database (offline). The sender was neither, and
	-- a crash would hand the gold back to them.
	self:saveOnTransfer("bank.transfer")
	if targetPlayer then
		targetPlayer:saveOnTransfer("bank.transfer")
	end
	GameEvents.emitForPlayer("bank.transfer", self, {
		amount = amount,
		to_guid = target.guid,
		to_name = target.name,
		to_online = targetPlayer ~= nil,
	}, "player", tostring(target.guid))
	return true
end

function Player.canCarryMoney(self, amount)
	-- Anyone can carry as much imaginary money as they desire
	if amount == 0 then return true end

	-- The 3 below loops will populate these local variables
	local totalWeight = 0
	local inventorySlots = 0

	local currencyItems = Game.getCurrencyItems()
	for index = #currencyItems, 1, -1 do
		local currency = currencyItems[index]
		-- Add currency coins to totalWeight and inventorySlots
		local worth = currency:getWorth()
		local currencyCoins = math.floor(amount / worth)
		if currencyCoins > 0 then
			amount = amount - (currencyCoins * worth)
			while currencyCoins > 0 do
				local count = math.min(100, currencyCoins)
				totalWeight = totalWeight + currency:getWeight(count)
				currencyCoins = currencyCoins - count
				inventorySlots = inventorySlots + 1
			end
		end
	end

	-- If player don't have enough capacity to carry this money
	if self:getFreeCapacity() < totalWeight then return false end

	-- If player don't have enough available inventory slots to carry this money
	local backpack = self:getSlotItem(CONST_SLOT_BACKPACK) --[[@as Container]]
	if not backpack or backpack:getEmptySlots(true) < inventorySlots then return false end
	return true
end

function Player.withdrawMoney(self, amount)
	local balance = self:getBankBalance()
	if amount > balance or not self:addMoney(amount) then return false end

	self:setBankBalance(balance - amount)
	self:saveOnTransfer("bank.withdraw")
	return true
end

function Player.depositMoney(self, amount)
	if not self:removeMoney(amount) then return false end

	self:setBankBalance(self:getBankBalance() + amount)
	self:saveOnTransfer("bank.deposit")
	return true
end

function Player.removeTotalMoney(self, amount)
	local moneyCount = self:getMoney()
	local bankCount = self:getBankBalance()
	if amount <= moneyCount then
		self:removeMoney(amount)
		return true
	elseif amount <= (moneyCount + bankCount) then
		if moneyCount ~= 0 then
			self:removeMoney(moneyCount)
			local remains = amount - moneyCount
			self:setBankBalance(bankCount - remains)
			self:sendTextMessage(MESSAGE_INFO_DESCR,
			                     ("Paid %d from inventory and %d gold from bank account. Your account balance is now %d gold."):format(
				                     moneyCount, amount - moneyCount, self:getBankBalance()))
			return true
		end
			self:setBankBalance(bankCount - amount)
			self:sendTextMessage(MESSAGE_INFO_DESCR,
			                     ("Paid %d gold from bank account. Your account balance is now %d gold."):format(
				                     amount, self:getBankBalance()))
			return true
		end
	return false
end

function Player.removeMoneyBank(self, amount)
	return self:removeTotalMoney(amount)
end

function Player.addLevel(self, amount, round)
	round = round or false
	local level, amount = self:getLevel(), amount or 1
	if amount > 0 then
		return self:addExperience(Game.getExperienceForLevel(level + amount) -
			                          (round and self:getExperience() or Game.getExperienceForLevel(level)))
	end
		return self:removeExperience(
			       ((round and self:getExperience() or Game.getExperienceForLevel(level)) -
				       Game.getExperienceForLevel(level + amount)))
end

function Player.addMagicLevel(self, value)
	local currentMagLevel = self:getBaseMagicLevel()
	local sum = 0

	if value > 0 then
		while value > 0 do
			sum = sum + self:getVocation():getRequiredManaSpent(currentMagLevel + value)
			value = value - 1
		end

		return self:addManaSpent(sum - self:getManaSpent())
	else
		value = math.min(currentMagLevel, math.abs(value))
		while value > 0 do
			sum = sum + self:getVocation():getRequiredManaSpent(currentMagLevel - value + 1)
			value = value - 1
		end

		return self:removeManaSpent(sum + self:getManaSpent())
	end
end

function Player.addSkillLevel(self, skillId, value)
	local currentSkillLevel = self:getSkillLevel(skillId)
	local sum = 0

	if value > 0 then
		while value > 0 do
			sum = sum + self:getVocation():getRequiredSkillTries(skillId, currentSkillLevel + value)
			value = value - 1
		end

		return self:addSkillTries(skillId, sum - self:getSkillTries(skillId))
	else
		value = math.min(currentSkillLevel, math.abs(value))
		while value > 0 do
			sum = sum + self:getVocation():getRequiredSkillTries(skillId, currentSkillLevel - value + 1)
			value = value - 1
		end

		return self:removeSkillTries(skillId, sum + self:getSkillTries(skillId), true)
	end
end

function Player.addSkill(self, skillId, value, round)
	if skillId == SKILL_LEVEL then
		return self:addLevel(value, round or false)
	elseif skillId == SKILL_MAGLEVEL then
		return self:addMagicLevel(value)
	end
	return self:addSkillLevel(skillId, value)
end

function Player.getWeaponType(self)
	local weapon = self:getSlotItem(CONST_SLOT_LEFT)
	if weapon then return weapon:getType():getWeaponType() end
	return WEAPON_NONE
end

function Player.isPromoted(self)
	local vocation = self:getVocation()
	if not vocation then
		return false
	end

	local demotion = vocation:getDemotion()
	if not demotion then
		return false
	end

	return vocation:getId() ~= demotion:getId()
end

function Player.setAccountStorageValue(self, key, value)
	return Game.setAccountStorageValue(self:getAccountId(), key, value)
end

function Player.getAccountStorageValue(self, key)
	return Game.getAccountStorageValue(self:getAccountId(), key)
end

-- Deprecated coin wrappers.
--
-- These used to read a balance and write back an absolute value, which two
-- concurrent callers can clobber. They now route through Coins.move, so they
-- are safe, but they record the movement as `legacy.unknown` -- a kind no
-- chart breaks down usefully. Every remaining caller should be converted to
-- Coins.spend / Coins.grant with a real kind; the traceback below is how they
-- are found. See data/lib/core/coins.lua and docs/admin-console/02-coin-reroute.md.
-- Warn once per call site per boot. The point is to find the remaining
-- callers, not to count them, and one of them (the Hunting Task reward) fires
-- often enough that logging every call would bury everything else.
local legacyCoinCallsSeen = {}

local function warnLegacyCoinCall(name)
	local site = debug.getinfo(3, "Sl")
	local key = site and string.format("%s:%d", site.short_src, site.currentline) or name
	if legacyCoinCallsSeen[key] then
		return
	end
	legacyCoinCallsSeen[key] = true
	logger.warn("[Coins] %s at %s is still on the deprecated wrapper; give it a real ledger kind (see data/lib/core/coins.lua).",
		name, key)
end

function Player.addTibiaCoins(self, tibiaCoins)
	warnLegacyCoinCall("Player:addTibiaCoins")
	local ok = Coins.grant(self, tibiaCoins, "legacy.unknown", nil, {via = "addTibiaCoins"})
	return ok
end

function Player.removeTibiaCoins(self, removeCoins)
	warnLegacyCoinCall("Player:removeTibiaCoins")
	local ok = Coins.spend(self, removeCoins, "legacy.unknown", nil, {via = "removeTibiaCoins"})
	return ok
end

function Player.setExhaustion(self, key, milliseconds)
	return self:setStorageValue(key, os.mtime() + milliseconds)
end

function Player.getExhaustion(self, key)
	local milliseconds = self:getStorageValue(key)
	if not milliseconds then return 0 end
	return math.max(0, os.mtime() - milliseconds)
end

function Player.hasExhaustion(self, key) return self:getExhaustion(key) > 0 end

function Player.questKV(self, questName)
	return self:kv():scoped("quests"):scoped(questName)
end

---@param type ExperienceRateType
---@param value integer
function Player:addExperienceRate(type, value)
	return self:setExperienceRate(type, self:getExperienceRate(type) + value)
end

do
	if not nextUseStaminaTime then nextUseStaminaTime = {} end

	local function useXpBoost(player, seconds)
		if not player.getXpBoostTime or not player.setXpBoostTime then return end

		local boostTime = player:getXpBoostTime()
		if boostTime <= 0 then return end

		if player:getStamina() <= 840 then
			return
		end

		player:setXpBoostTime(math.max(0, boostTime - seconds))
	end

	local function useStamina(player)
		local staminaMinutes = player:getStamina()
		if staminaMinutes == 0 then return end

		local playerId = player:getId()
		if not nextUseStaminaTime[playerId] then nextUseStaminaTime[playerId] = 0 end

		local currentTime = os.time()
		local timePassed = currentTime - nextUseStaminaTime[playerId]
		if timePassed <= 0 then return end

		if timePassed > 60 then
			if staminaMinutes > 2 then
				staminaMinutes = staminaMinutes - 2
			else
				staminaMinutes = 0
			end
			nextUseStaminaTime[playerId] = currentTime + 120
			useXpBoost(player, 120)
		else
			staminaMinutes = staminaMinutes - 1
			nextUseStaminaTime[playerId] = currentTime + 60
			useXpBoost(player, 60)
		end
		player:setStamina(math.floor(staminaMinutes))
	end

	function Player:updateStamina()
		if not configManager.getBoolean(configKeys.STAMINA_SYSTEM) then return false end

		useStamina(self)

		local staminaMinutes = self:getStamina()
		if staminaMinutes > 2400 and self:isPremium() then
			self:setExperienceRate(ExperienceRateType.STAMINA, 150)
		else
			self:setExperienceRate(ExperienceRateType.STAMINA, 100)
		end
		return true
	end

	-- Guild Balance Functions
	function Player.depositGuildMoney(self, amount)
		local guild = self:getGuild()
		if not guild then
			return false, "You are not in a guild."
		end

		if not self:removeMoney(amount) then
			return false, "You don't have enough money."
		end

		guild:setBankBalance(guild:getBankBalance() + amount)
		-- Guild::setBankBalance writes the guilds row immediately; the
		-- depositor's inventory only lives in memory until saved.
		self:saveOnTransfer("guild.deposit")
		GameEvents.emitForPlayer("bank.transfer", self, {
			amount = amount, guild_id = guild:getId(), direction = "to_guild",
		}, "guild", tostring(guild:getId()))
		return true, "Successfully deposited " .. amount .. " gold to guild bank."
	end

	function Player.withdrawGuildMoney(self, amount)
		local guild = self:getGuild()
		if not guild then
			return false, "You are not in a guild."
		end

		-- Check if player has permission (Leader or Vice-Leader)
		if self:getGuid() ~= guild:getOwnerGUID() and self:getGuildLevel() ~= 2 then
			return false, "Only guild leaders and vice-leaders can withdraw money."
		end

		if amount > guild:getBankBalance() then
			return false, "Guild doesn't have enough money."
		end

		if not self:addMoney(amount) then
			return false, "You can't carry that much money."
		end

		guild:setBankBalance(guild:getBankBalance() - amount)
		self:saveOnTransfer("guild.withdraw")
		GameEvents.emitForPlayer("bank.transfer", self, {
			amount = amount, guild_id = guild:getId(), direction = "from_guild",
		}, "guild", tostring(guild:getId()))
		return true, "Successfully withdrew " .. amount .. " gold from guild bank."
	end

	function Player.transferGuildMoneyToPlayer(self, targetPlayer, amount)
		local guild = self:getGuild()
		if not guild then
			return false, "You are not in a guild."
		end

		-- Check if player has permission (Leader or Vice-Leader)
		if self:getGuid() ~= guild:getOwnerGUID() and self:getGuildLevel() ~= 2 then
			return false, "Only guild leaders and vice-leaders can transfer money."
		end

		if amount > guild:getBankBalance() then
			return false, "Guild doesn't have enough money."
		end

		local target = Player(targetPlayer)
		if not target then
			return false, "Target player not found."
		end

		guild:setBankBalance(guild:getBankBalance() - amount)
		target:setBankBalance(target:getBankBalance() + amount)
		target:saveOnTransfer("guild.transfer")
		GameEvents.emitForPlayer("bank.transfer", self, {
			amount = amount, guild_id = guild:getId(), direction = "guild_to_player",
			to_guid = target:getGuid(), to_name = target:getName(),
		}, "player", tostring(target:getGuid()))
		return true, "Successfully transferred " .. amount .. " gold to " .. target:getName() .. "."
	end

	function Player.getGuildBalance(self)
		local guild = self:getGuild()
		if not guild then
			return 0
		end
		return guild:getBankBalance()
	end
end
