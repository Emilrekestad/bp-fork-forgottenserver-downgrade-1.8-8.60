-- Barbarian Test: the physical mechanics (horn-filling, bear hugging,
-- mammoth pushing, mead drinking). Ported from opentibiabr/canary's
-- barbarian_test/action_horn.lua + action_mead.lua (2026-08-26).
--
-- Sven's dialogue (data/npc/scripts/Sven.lua) already implements the full
-- Questline 1->8 progression around these two actions - it was the only
-- half of this quest missing. Verified: items 7140/7141 (mead horn),
-- 7174/7175 (bear), 7176 (mammoth) all exist under those exact ids in our
-- items.xml, and both check positions (32201,31154,7 mead spot; 32253,
-- 31049,5 bear) have the expected real items sitting there already.
local sendSleepEffect = function(position)
	position:sendMagicEffect(CONST_ME_SLEEP)
end

local barbarianHorn = Action()

function barbarianHorn.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if item.itemid == 7140 and Tile(Position(32201, 31154, 7)):getItemById(7142) then
		player:say("You fill your horn with ale.", TALKTYPE_MONSTER_SAY)
		item:transform(7141)
		toPosition:sendMagicEffect(CONST_ME_MAGIC_BLUE)
	elseif item.itemid == 7141 and Tile(Position(32253, 31049, 5)):getItemById(7174) then
		local targetItem = Tile(Position(32253, 31049, 5)):getItemById(7174)
		if targetItem then
			player:say("The bear is now unconscious.", TALKTYPE_MONSTER_SAY)
			targetItem:transform(7175)
			toPosition:sendMagicEffect(CONST_ME_STUN)
		end
	elseif item.itemid == 7175 then
		if player:getStorageValue(PlayerStorageKeys.BarbarianTest.Questline) == 4 then
			player:say("You hug the unconcious bear.", TALKTYPE_MONSTER_SAY)
			player:setStorageValue(PlayerStorageKeys.BarbarianTest.Questline, 5)
			player:setStorageValue(PlayerStorageKeys.BarbarianTest.Mission02, 2) -- Barbarian Test 2: The Bear Hugging
			player:addAchievement("Bearhugger")
			item:transform(7174)
			toPosition:sendMagicEffect(CONST_ME_SLEEP)
		else
			player:say("You don't feel like hugging an unconcious bear.", TALKTYPE_MONSTER_SAY)
		end
	elseif item.itemid == 7174 then
		player:say("Grr.", TALKTYPE_MONSTER_SAY)
		player:say("The bear is not amused by the disturbance.", TALKTYPE_MONSTER_SAY)
		doAreaCombatHealth(player, COMBAT_PHYSICALDAMAGE, player:getPosition(), 0, -10, -30, CONST_ME_POFF)
	elseif item.itemid == 7176 then
		if player:getStorageValue(PlayerStorageKeys.BarbarianTest.Questline) == 6 then
			if player:getCondition(CONDITION_DRUNK) then
				player:say("You hustle the mammoth. What a fun. *hicks*.", TALKTYPE_MONSTER_SAY)
				player:setStorageValue(PlayerStorageKeys.BarbarianTest.Questline, 7)
				player:setStorageValue(PlayerStorageKeys.BarbarianTest.Mission03, 2) -- Barbarian Test 3: The Mammoth Pushing
				item:transform(7177)
				item:decay()
				addEvent(sendSleepEffect, 60 * 1000, toPosition)
				toPosition:sendMagicEffect(CONST_ME_SLEEP)
			else
				player:say("You are not drunk enought to hustle a mammoth.", TALKTYPE_MONSTER_SAY)
			end
		end
	end
	return true
end

barbarianHorn:id(7140, 7141, 7174, 7175, 7176)
barbarianHorn:register()

local drunkCondition = Condition(CONDITION_OUTFIT)
drunkCondition:setOutfit({lookTypeEx = 111})
drunkCondition:setTicks(1000)

local barbarianMead = Action()

function barbarianMead.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local questline = player:getStorageValue(PlayerStorageKeys.BarbarianTest.Questline)
	local totalSips = player:getStorageValue(PlayerStorageKeys.BarbarianTest.MeadTotalSips)
	if questline >= 3 then
		player:say("You already passed the test, no need to torture yourself anymore.", TALKTYPE_MONSTER_SAY)
	elseif questline == 2 and totalSips < 20 then
		if math.random(5) > 1 then
			player:say("The world seems to spin but you manage to stay on your feet.", TALKTYPE_MONSTER_SAY)
			local successSips = math.max(player:getStorageValue(PlayerStorageKeys.BarbarianTest.MeadSuccessSips), 0) + 1
			player:setStorageValue(PlayerStorageKeys.BarbarianTest.MeadSuccessSips, successSips)
			if successSips >= 10 then
				player:say("10 sips in a row. Yeah!", TALKTYPE_MONSTER_SAY)
				player:setStorageValue(PlayerStorageKeys.BarbarianTest.Questline, 3)
				player:setStorageValue(PlayerStorageKeys.BarbarianTest.Mission01, 3) -- Barbarian Test 1: Barbarian Booze
				return true
			end
		else
			player:say("The mead was too strong. You passed out for a moment.", TALKTYPE_MONSTER_SAY)
			player:addCondition(drunkCondition)
			player:getPosition():sendMagicEffect(CONST_ME_HITBYPOISON)
			player:setStorageValue(PlayerStorageKeys.BarbarianTest.MeadSuccessSips, 0)
		end
		player:setStorageValue(PlayerStorageKeys.BarbarianTest.MeadTotalSips, totalSips + 1)
	elseif (questline == 1 or questline == 2) and totalSips >= 20 then
		player:say("Ask Sven for another round.", TALKTYPE_MONSTER_SAY)
		player:setStorageValue(PlayerStorageKeys.BarbarianTest.Questline, 1)
		player:setStorageValue(PlayerStorageKeys.BarbarianTest.Mission01, 1) -- Barbarian Test 1: Barbarian Booze
	end
	return true
end

barbarianMead:position(Position(32201, 31154, 7))
barbarianMead:register()
