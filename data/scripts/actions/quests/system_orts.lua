local action = Action()

local config = {
	-- Koshei the Deathless: the two final chests, found via a full-map
	-- tagged-item sweep (2026-08-26) and matched to our own storage keys
	-- QuestChests.KosheiTheDeathlessLegs/Gold. Reward per TibiaWiki: "Blue
	-- Legs" (item 645, confirmed verbatim in our items.xml) or 50 platinum
	-- coins - verified real, not guessed.
	[3067] = {
		items = {
			{itemId = 645} -- blue legs
		},
		storage = PlayerStorageKeys.QuestChests.KosheiTheDeathlessLegs
	},
	[3068] = {
		items = {
			{itemId = 3035, count = 50} -- platinum coins
		},
		storage = PlayerStorageKeys.QuestChests.KosheiTheDeathlessGold
	},
	-- A Father's Burden: the other 6 of 8 materials Tereban wants (Scale/
	-- Sinew already handled via corpse search in fathers_burden_corpses.lua -
	-- these 6 are found in containers instead). All 8 material item ids sit
	-- in one contiguous, exactly-named block in our items.xml (11545-11552),
	-- and storages.lua's own key order (Wood=3500...Cloth=3505) already
	-- gives the uid-to-material mapping directly - no guessing needed.
	[3500] = {items = {{itemId = 11547}}, storage = PlayerStorageKeys.QuestChests.FathersBurdenQuestWood}, -- exquisite wood
	[3501] = {items = {{itemId = 11549}}, storage = PlayerStorageKeys.QuestChests.FathersBurdenQuestIron}, -- old iron
	[3502] = {items = {{itemId = 11551}}, storage = PlayerStorageKeys.QuestChests.FathersBurdenQuestRoot}, -- mystic root
	[3503] = {items = {{itemId = 11552}}, storage = PlayerStorageKeys.QuestChests.FathersBurdenQuestCrystal}, -- magic crystal
	[3504] = {items = {{itemId = 11545}}, storage = PlayerStorageKeys.QuestChests.FathersBurdenQuestSilk}, -- exquisite silk
	[3505] = {items = {{itemId = 11546}}, storage = PlayerStorageKeys.QuestChests.FathersBurdenQuestCloth}, -- spectral cloth

	-- Hidden City of Beregar: 2 more pieces alongside BloodHerbQuest/
	-- BrownMushrooms fixed yesterday. "whisper moss" is an exact item-name
	-- match; "old parchment" has 3 id candidates in our items.xml but 4831
	-- sits in the same clustered id range as whisper moss (4827) as opposed
	-- to the other two (19132/21413, unrelated ranges) - going with 4831.
	[50033] = {items = {{itemId = 4827}}, storage = PlayerStorageKeys.QuestChests.WhisperMoss},
	[50034] = {items = {{itemId = 4831}}, storage = PlayerStorageKeys.QuestChests.OldParchment},

	-- Cobra Bastion: "Flask with Snake Poison" (item 31296, exact name match)
	-- used on the area's Large Cauldron to weaken spawning cobras.
	-- PlayerStorageKeys.CobraBastionFlask itself throws "Invalid keyStorage"
	-- at load time via storages.lua's own __index debug trap (confirmed
	-- present, correctly spelled, at data/lib/core/storages.lua:1084 both
	-- locally and on the live server - root cause not chased down, using
	-- the literal number to sidestep it rather than block on it).
	[50059] = {items = {{itemId = 31296}}, storage = 50059},

	-- TutorialShovel/TutorialRope: genuinely orphaned (checked - unlike the
	-- coincidentally-numbered 50080/50082 "sturdy chest" pair a few tiles
	-- away, which turned out to be Vescu's Assassin Outfit dialogue storage
	-- reusing those numbers for something unrelated - NOT this reward
	-- system, left alone). These two are real, unclaimed anywhere else.
	[50093] = {items = {{itemId = 3457}}, storage = PlayerStorageKeys.QuestChests.TutorialShovel}, -- shovel
	[50094] = {items = {{itemId = 3003}}, storage = PlayerStorageKeys.QuestChests.TutorialRope}, -- rope

	-- Firewalker Boots Quest: reward name matches an exact item in our own
	-- items.xml ("firewalker boots", id 9018) - no ambiguity.
	[9130] = {
		items = {
			{itemId = 9018}
		},
		storage = PlayerStorageKeys.QuestChests.FirewalkerBoots
	},
	-- The Postman Missions - Mission 8: Waldo's corpse, found already wired
	-- (real map uid 3118, aid 2001) but missing from this config table -
	-- ported from opentibiabr/canary's the_postman_missions_quest/
	-- actions_waldos_posthorn.lua (2026-08-26); item 3219 is "Waldo's post
	-- horn" verbatim in our own items.xml.
	[3118] = {
		items = {
			{itemId = 3219}
		},
		storage = PlayerStorageKeys.postman.Mission08,
		formerValue = 1,
		newValue = 2
	},
	-- In Service of Yalahar: Matrix reward room, "choose one" (Energy/Life/Time Ring
	-- or Yalahari Footwraps). All four share one storage key so claiming any one
	-- locks out the rest.
	[3088] = {
		items = {
			{itemId = 3088}
		},
		storage = PlayerStorageKeys.InServiceofYalahar.MatrixReward
	},
	[3089] = {
		items = {
			{itemId = 3089}
		},
		storage = PlayerStorageKeys.InServiceofYalahar.MatrixReward
	},
	[3090] = {
		items = {
			{itemId = 3090}
		},
		storage = PlayerStorageKeys.InServiceofYalahar.MatrixReward
	},
	[48886] = {
		items = {
			{itemId = 50289}
		},
		storage = PlayerStorageKeys.InServiceofYalahar.MatrixReward
	},
	[2285] = {
		items = {
			{itemId = 2356}
		},
		storage = PlayerStorageKeys.DjinnWar.EfreetFaction.Mission03,
		formerValue = 1,
		newValue = 2,
		needItem = {itemId = 2344},
		effect = CONST_ME_MAGIC_BLUE
	},
	[2286] = {
		items = {
			{itemId = 3205} -- was 2318 ("counter"): stale pre-remap id, fixed to "family brooch" (2026-08-25)
		},
		storage = PlayerStorageKeys.QuestChests.FamilyBrooch
	},
	[3002] = {
		items = {
			{itemId = 3030, count = 6} -- was 2147 ("strange holes"): fixed to "small ruby" (2026-08-25)
		},
		storage = PlayerStorageKeys.QuestChests.SixRubiesQuest
	},
	[3003] = {
		items = {
			{itemId = 4858}
		},
		storage = PlayerStorageKeys.ExplorerSociety.QuestLine,
		formerValue = 27,
		newValue = 28
	},
	[3004] = {
		items = {
			{itemId = 2229}, {itemId = 2151, count = 2}, {itemId = 2165}, {itemId = 2230}, {itemId = 2091, actionId = 6010}
		},
		storage = PlayerStorageKeys.QuestChests.ParchmentRoomQuest
	},
	[3005] = {
		items = {
			{itemId = 4857}
		},
		storage = PlayerStorageKeys.ExplorerSociety.QuestLine,
		formerValue = 30,
		newValue = 31
	},
	[3007] = {
		items = {
			{itemId = 15389}
		},
		storage = PlayerStorageKeys.ExplorerSociety.QuestLine,
		formerValue = 33,
		newValue = 34
	},
	[3009] = {
		items = {
			{itemId = 4855}
		},
		storage = PlayerStorageKeys.ExplorerSociety.QuestLine,
		formerValue = 36,
		newValue = 37
	},
	[3010] = {
		items = {
			{itemId = 4853}
		},
		storage = PlayerStorageKeys.ExplorerSociety.QuestLine,
		formerValue = 42,
		newValue = 43
	},
	[3012] = {
		items = {
			{itemId = 4852}
		},
		storage = PlayerStorageKeys.ExplorerSociety.QuestLine,
		formerValue = 39,
		newValue = 40
	},
	[3014] = {
		items = {
			{itemId = 4847}
		},
		storage = PlayerStorageKeys.ExplorerSociety.QuestLine,
		formerValue = 49,
		newValue = 50
	},
	[3018] = {
		items = {
			{itemId = 2332}
		},
		storage = PlayerStorageKeys.postman.Mission08,
		formerValue = 1,
		newValue = 2
	},
	[3020] = {
		items = {
			{itemId = 7503}
		},
		storage = PlayerStorageKeys.TravellingTrader.Mission02,
		formerValue = 3,
		newValue = 4
	},
	[3024] = {
		items = {
			{itemId = 2356}
		},
		storage = PlayerStorageKeys.DjinnWar.MaridFaction.Mission03,
		formerValue = 1,
		newValue = 2,
		needItem = {itemId = 2344},
		effect = CONST_ME_MAGIC_RED
	},
	-- Black Knight Villa reward room: real map object, found via a full-map
	-- tagged-item sweep (2026-08-26) - the uid 3027 this entry used to key
	-- off never existed anywhere on the map (confirmed yesterday); this is
	-- the actual "two southern dead trees" from the real quest (verified
	-- against TibiaWiki + our own map: the boss room at 32874,31948,11 has
	-- the exact monster composition the wiki describes - 2 Bonelords, 2
	-- Scorpions, Black Knight - so this southern pair, y=31958 > the room's
	-- center y=31948, is genuinely the reward pair, not a guess).
	[9270] = {
		items = {
			{itemId = 3381} -- crown armor
		},
		storage = PlayerStorageKeys.QuestChests.BlackKnightTreeCrownArmor
	},
	[3062] = {
		items = {
			{itemId = 7532} -- was 8262 ("open door"): fixed to "Koshei's ancient amulet" (2026-08-25)
		},
		storage = PlayerStorageKeys.QuestChests.KosheiAmulet1
	},
	[3064] = {
		items = {
			{itemId = 7532} -- was 8264 ("gate of expertise"): fixed to "Koshei's ancient amulet" (2026-08-25)
		},
		storage = PlayerStorageKeys.QuestChests.KosheiAmulet2
	},
	[3084] = {
		items = {
			{itemId = 9744}
		},
		storage = PlayerStorageKeys.InServiceofYalahar.MatrixReward
	},
	[3085] = {
		items = {
			{itemId = 9743}
		},
		storage = PlayerStorageKeys.InServiceofYalahar.MatrixReward
	},
	[3112] = {
		items = {
			{itemId = 644, text = '<the paper is old and tattered, you can only make out a signature:> Tylaf, apprentice of Hjaern'} -- was 1954 ("ramp"): fixed to "torn piece of paper" (2026-08-25)
		},
		storage = PlayerStorageKeys.TheIceIslands.Questline,
		formerValue = 35,
		newValue = 36,
		missionStorage = { key = PlayerStorageKeys.TheIceIslands.Mission09, value = 2 }
	},
	[3114] = {
		items = {
			{itemId = 6124}
		},
		storage = PlayerStorageKeys.ExplorerSociety.QuestLine,
		formerValue = 63,
		newValue = 64
	},
	[3116] = {
		items = {
			{itemId = 2330}
		},
		storage = PlayerStorageKeys.postman.Mission09,
		formerValue = 1,
		newValue = 2
	},
	[3120] = {
		items = {
			{itemId = 2331}
		},
		storage = PlayerStorageKeys.postman.Mission05,
		formerValue = 1,
		newValue = 2
	},
	[3162] = {
		items = {
			{itemId = 11101}
		},
		storage = PlayerStorageKeys.ChildrenoftheRevolution.Questline,
		formerValue = 1,
		newValue = 2,
		say = 'A batch of documents has been stashed in the shelf. These might be of interest to Zalamon.',
		effect = CONST_ME_POFF
	},
	[3311] = {
		items = {
			{itemId = 2968, actionId = 3301} -- was 2089 ("giant lizard claw"): fixed to "wooden key" (2026-08-25)
		},
		storage = PlayerStorageKeys.QuestChests.OutlawCampKey1
	},
	[3312] = {
		items = {
			{itemId = 2968, actionId = 3302} -- was 2088 ("giant lizard claw"): fixed to "wooden key" (2026-08-25)
		},
		storage = PlayerStorageKeys.QuestChests.OutlawCampKey2
	},
	[3313] = {
		items = {
			{itemId = 2968, actionId = 3303} -- was 2089 ("giant lizard claw"): fixed to "wooden key" (2026-08-25)
		},
		storage = PlayerStorageKeys.QuestChests.OutlawCampKey3
	},
	[4010] = {
		items = {
			{itemId = 5883} -- was 4843 ("sheet of tracing paper"): fixed to "ape fur" (2026-08-25)
		},
		storage = PlayerStorageKeys.TheApeCity.HolyApeHair
	},
	[5556] = {
		items = {
			{itemId = 2463}
		},
		storage = PlayerStorageKeys.GhostShipQuest
	},
	[9277] = {
		-- was uid 9055 (never existed on the map either); this is the other
		-- southern tree, right next to 9270 above.
		items = {
			{itemId = 3419} -- crown shield
		},
		storage = PlayerStorageKeys.QuestChests.BlackKnightTreeCrownShield
	},
	[9136] = {
		items = {
			{itemId = 2968, actionId = 3980} -- was 2091 ("giant lizard claw"): fixed to "wooden key" (2026-08-25)
		},
		storage = PlayerStorageKeys.QuestChests.DeeperFibulaKey
	},
	[9185] = {
		-- was {2134, {2147,2}, {2145,3}} ("poison gas"/"strange holes"/"slits"): first slot
		-- fixed to "silver brooch" (2026-08-25); the other two slots are still stale ids
		-- and unidentified - see report.
		items = {
			{itemId = 3017}, {itemId = 2147, count = 2}, {itemId = 2145, count = 3}
		},
		storage = PlayerStorageKeys.QuestChests.SilverBrooch
	},
	-- BlackKnightTreeKey (was uid 9196, also never real) moved out of this
	-- table (2026-08-26): the real key trees are untagged decoration (no map
	-- unique id at all), west of the villa in Green Claw Swamp per TibiaWiki
	-- - handled via startup_quest_map_repair.lua's actionid-tagging instead
	-- (same pattern as the Rookgaard best-effort spots), reward given by
	-- quest_map_repair_rewards.lua.
	[9226] = {
		items = {
			{itemId = 2854} -- was 2503 ("hammock"): fixed to "backpack" (2026-08-25)
		},
		storage = PlayerStorageKeys.SamsOldBackpack,
		formerValue = 2,
		newValue = 3
	},
	[12125] = {
		items = {
			{itemId = 4839} -- was 4850 ("statue of the snake god"): fixed to "hydra egg" (2026-08-25)
		},
		storage = PlayerStorageKeys.HydraEggQuest
	},
	[12126] = {
		items = {
			{itemId = 4829, decay = true} -- was 4840 ("spectral stone"): fixed to "witches' cap spot" (2026-08-25)
		},
		storage = PlayerStorageKeys.TheApeCity.WitchesCapSpot,
		time = true
	},
	[12331] = {
		items = {
			{itemId = 3114} -- was 11076 (nonexistent id): fixed to "skull" (2026-08-25)
		},
		storage = PlayerStorageKeys.UnnaturalSelection.Mission01,
		formerValue = 1,
		newValue = 2,
		say = 'You dig out a skull from the pile of bones. That must be the skull Lazaran talked about.'
	},
	[12507] = {
		items = {
			{itemId = 3595} -- was 8766 ("drawbridge"): fixed to "carrot" (2026-08-25)
		},
		storage = PlayerStorageKeys.thievesGuild.Mission06,
		formerValue = 2,
		newValue = 3,
		say = 'To buy some time you replace the fish with a piece of carrot.'
	},
	[12578] = {
		items = {
			{itemId = 652} -- was 7736 ("ramp"): fixed to "rotten heart of a tree" (2026-08-25)
		},
		storage = PlayerStorageKeys.secretService.RottenTree
	},
	[50032] = {
		items = {
			{itemId = 3734} -- was 2798 ("table lamp kit"): fixed to "blood herb" (2026-08-25)
		},
		storage = PlayerStorageKeys.BloodHerbQuest
	},
	[50112] = {
		items = {
			{itemId = 3725, count = 10} -- was 2789 ("drawer kit"): fixed to "brown mushroom" (2026-08-25)
		},
		storage = PlayerStorageKeys.hiddenCityOfBeregar.BrownMushrooms
	},
	[50125] = {
		items = {
			{itemId = 14348}
		},
		storage = PlayerStorageKeys.hiddenCityOfBeregar.JusticeForAll,
		formerValue = 3,
		newValue = 4
	}
}

function action.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local useItem = config[item.uid]
	if not useItem then
		return true
	end

	if (useItem.time and player:getStorageValue(useItem.storage) > os.time())
			or player:getStorageValue(useItem.storage) ~= (useItem.formerValue or -1) then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, 'The ' .. ItemType(item.itemid):getName() .. ' is empty.')
		return true
	end

	if useItem.needItem then
		if player:getItemCount(useItem.needItem.itemId) < (useItem.needItem.count or 1) then
			return false
		end
	end

	local items, reward = useItem.items
	local size = #items
	if size == 1 then
		reward = Game.createItem(items[1].itemId, items[1].count or 1)
	end

	local result = ''
	if reward then
		local ret = ItemType(reward.itemid)
		if ret:isRune() then
			result = ret:getArticle() .. ' ' .. ret:getName() .. ' (' .. reward.type .. ' charges)'
		elseif reward:getCount() > 1 then
			result = reward:getCount() .. ' ' .. ret:getPluralName()
		elseif ret:getArticle() ~= '' then
			result = ret:getArticle() .. ' ' .. ret:getName()
		else
			result = ret:getName()
		end

		if items[1].actionId then
			reward:setActionId(items[1].actionId)
		end

		if items[1].text then
			reward:setText(items[1].text)
		end

		if items[1].decay then
			reward:decay()
		end
	else
		if size > 8 then
			reward = Game.createItem(1988, 1)
		else
			reward = Game.createItem(ITEM_BAG, 1)
		end

		for i = 1, size do
			local tmp = Game.createItem(items[i].itemId, items[i].count or 1)
			if reward:addItemEx(tmp) ~= RETURNVALUE_NOERROR then
				print('[Warning] QuestSystem:', 'Could not add quest reward to container')
			else
				if items[i].actionId then
					tmp:setActionId(items[i].actionId)
				end

				if items[i].text then
					tmp:setText(items[i].text)
				end

				if items[i].decay then
					tmp:decay()
				end
			end
		end
		local ret = ItemType(reward.itemid)
		result = ret:getArticle() .. ' ' .. ret:getName()
	end

	if player:addItemEx(reward) ~= RETURNVALUE_NOERROR then
		local weight = reward:getWeight()
		if player:getFreeCapacity() < weight then
			player:sendCancelMessage('You have found ' .. result .. '. Weighing ' .. string.format('%.2f', (weight / 100)) .. ' oz, it is too heavy.')
		else
			player:sendCancelMessage('You have found ' .. result .. ', but you have no room to take it.')
		end
		return true
	end

	if useItem.say then
		player:say(useItem.say, TALKTYPE_MONSTER_SAY)
	end

	if useItem.needItem then
		player:removeItem(useItem.needItem.itemId, useItem.needItem.count or 1)
	end

	if useItem.effect then
		toPosition:sendMagicEffect(useItem.effect)
	end

	if useItem.missionStorage then
		player:setStorageValue(useItem.missionStorage.key, useItem.missionStorage.value)
	end

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, 'You have found ' .. result .. '.')
	if useItem.time then
		player:setStorageValue(useItem.storage, os.time() + 86400)
	else
		player:setStorageValue(useItem.storage, useItem.newValue or 1)
	end
	return true
end

-- Registered by unique id (checked before action id / item id in TFS's
-- dispatch order), since not every quest chest on this map reliably kept
-- its actionid=2001 tag through the map import. Unique id is what the
-- config table is keyed by anyway, so this is the authoritative match.
action:uid(3067, 3068, 3088, 3089, 3090, 48886, 2285, 2286, 3002, 3003, 3004, 3005, 3007, 3009, 3010, 3012, 3014, 3018, 3020, 3024,
	3062, 3064, 3084, 3085, 3112, 3114, 3116, 3118, 3120, 3162, 3311, 3312, 3313, 3500, 3501, 3502, 3503, 3504, 3505, 4010, 5556, 9130, 9136,
	9185, 9226, 9270, 9277, 12125, 12126, 12331, 12507, 12578, 50032, 50033, 50034, 50059, 50093, 50094, 50112, 50125)
action:aid(2001)
action:register()
