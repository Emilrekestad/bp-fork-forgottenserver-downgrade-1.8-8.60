 local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()					end

-- standard price of one blessing by level (this server has no shared helper for it)
local function getBlessingsCost(level)
	if level <= 30 then
		return 2000
	elseif level >= 120 then
		return 20000
	end
	return 2000 + 200 * (level - 30)
end

-- Keys are written out here (not read from the Storage lib) so that /reload scripts is enough.
local INQUISITION_KEYS = {
	Questline = 12160, Mission01 = 12161, Mission02 = 12162, Mission03 = 12163, Mission04 = 12164,
	EnterTeleport = 12176, CountTry = 12179, UngreezKilled = 12180,
	SealUshuriel = 12190, SealZugurosh = 12191, SealMadareth = 12192, SealVats = 12193,
	SealAnnihilon = 12194, SealHellgorak = 12195, LatrivanKilled = 12196, GolgordanKilled = 12197,
	RewardAccess = 12198, CrystalCaves = 12199, BloodHalls = 12200,
}

-- Mission 4: every seal starts as "still holds" (1) in the quest log; a broken seal (2) stays broken.
local SEAL_KEYS = { 12190, 12191, 12192, 12193, 12194, 12195 }

local function openSeals(player)
	for _, key in ipairs(SEAL_KEYS) do
		if player:getStorageValue(key) < 1 then
			player:setStorageValue(key, 1)
		end
	end
end

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	local totalBlessPrice = math.floor(getBlessingsCost(player:getLevel()) * 5 * 1.1)

	local S = INQUISITION_KEYS
	local m1, m2, m3, m4 = player:getStorageValue(S.Mission01), player:getStorageValue(S.Mission02), player:getStorageValue(S.Mission03), player:getStorageValue(S.Mission04)

	if msgcontains(msg, "inquisitor") then
		npcHandler:say("The churches of the gods entrusted me with the enormous and responsible task to lead the inquisition. I leave the field work to inquisitors who I recruit from fitting people that cross my way.", cid)
	elseif msgcontains(msg, "join") then
		if player:getStorageValue(S.Questline) < 1 then
			npcHandler:say("Do you want to join the inquisition?", cid)
			npcHandler.topic[cid] = 2
		end
	elseif msgcontains(msg, "blessing") or msgcontains(msg, "bless") then
		if player:getStorageValue(S.RewardAccess) >= 1 then
			npcHandler:say("Do you want to receive the blessing of the inquisition - which means all five available blessings - for " .. totalBlessPrice .. " gold?", cid)
			npcHandler.topic[cid] = 7
		else
			npcHandler:say("You cannot get this blessing until you have faced the inquisition and reported to me.", cid)
			npcHandler.topic[cid] = 0
		end
	elseif msgcontains(msg, "count") then
		if m2 == 2 then
			if player:getStorageValue(S.CountTry) == 1 then
				npcHandler:say("You may still wake him. Press the buried coffin in the crypt, and he will rise.", cid)
			else
				npcHandler:say("He bested you? Then try again. The crypt will answer once more. Press the coffin when you are ready.", cid)
				player:setStorageValue(S.CountTry, 1)
			end
		else
			npcHandler:say("The Count is a vampire lord. I have no use for him unless the inquisition sends you after him.", cid)
		end
		npcHandler.topic[cid] = 0
	elseif msgcontains(msg, "holy water") or msgcontains(msg, "vial") or msgcontains(msg, "flask") then
		if m3 == 2 then
			if player:getItemCount(133) < 1 then
				npcHandler:say("You lost the holy water? Careless. Here is another. Do not lose this one.", cid)
				player:addItem(133, 1)
			else
				npcHandler:say("You still carry it. Use it on the cauldron on the island.", cid)
			end
		else
			npcHandler:say("Holy water is for those on a mission against the unholy.", cid)
		end
		npcHandler.topic[cid] = 0
	elseif msgcontains(msg, "mission") or msgcontains(msg, "report") or msgcontains(msg, "quest") then
		if player:getStorageValue(S.Questline) < 1 then
			npcHandler:say("Do you want to join the inquisition?", cid)
			npcHandler.topic[cid] = 2
		elseif m1 == 1 then
			npcHandler:say("Have you been to {Bender Shun}? He must tell us that the world is ready before the inquisition can march. Go and see him.", cid)
		elseif m1 == 2 then
			npcHandler:say({
				"Bender Shun says the world is ready? Then the time has come. ...",
				"Your first test is simple. Bring me 20 vampire dusts. Come back with them and I will tell you more."
			}, cid)
			player:setStorageValue(S.Mission01, 3)
			player:setStorageValue(S.Mission02, 1)
		elseif m2 == 1 then
			npcHandler:say("I need 20 vampire dusts. Do you have them with you?", cid)
			npcHandler.topic[cid] = 4
		elseif m2 == 2 then
			if player:getItemCount(7924) > 0 then
				npcHandler:say("You have the Count's ring? Give it to me. Do you hand over the ring?", cid)
				npcHandler.topic[cid] = 5
			else
				npcHandler:say("Bring me the ring of the Count. Press the buried coffin in the crypt to wake him. If he bests you, say {the Count} to me and I will let you try again.", cid)
			end
		elseif m2 >= 3 and m3 < 1 then
			npcHandler:say({
				"Your next test: bring me 30 demonic essences. Demons are the greatest servants of evil, and I need proof you can face them. ...",
				"Come back when you have them."
			}, cid)
			player:setStorageValue(S.Mission03, 1)
		elseif m3 == 1 then
			npcHandler:say("I need 30 demonic essences. Do you have them with you?", cid)
			npcHandler.topic[cid] = 6
		elseif m3 == 2 or m3 == 3 then
			npcHandler:say("You know your task. Fly to {Eclipse}, pour the holy water into the cauldron, help kill Ungreez and bring me the witches' grimoire. If you lose the holy water, ask me for a {vial}.", cid)
		elseif m3 == 4 then
			npcHandler:say("Do you have the witches' grimoire?", cid)
			npcHandler.topic[cid] = 8
		elseif m3 >= 5 and m4 < 1 then
			npcHandler:say({
				"I am impressed with you. The time has come to face the inquisition's true enemies. ...",
				"Below lie the realms of the seven. Break their seals one by one: Ushuriel, Zugurosh, Madareth, Latrivan and Golgordan, Annihilon, and last Hellgorak. ...",
				"Only when Hellgorak is dead can you leave through the final teleport. Then report to me. Go, and good luck. You will need it."
			}, cid)
			player:setStorageValue(S.Mission04, 1)
			player:setStorageValue(S.EnterTeleport, 1)
			openSeals(player)
		elseif m4 == 1 then
			openSeals(player)
			npcHandler:say("Your mission is to face the inquisition: break every seal, boss by boss. Hellgorak is the last. Check your quest log for the seals that still hold. Come back when Hellgorak is dead.", cid)
		elseif m4 >= 2 and player:getStorageValue(S.RewardAccess) < 1 then
			npcHandler:say({
				"You faced the inquisition and Hellgorak is dead! The gods will remember this day. ...",
				"I grant you both addons of the Hand of the Inquisition outfit. The reward room of the inquisition is open to you too: take one chest, and choose wisely."
			}, cid)
			player:setStorageValue(S.Mission04, 3)
			player:setStorageValue(S.RewardAccess, 1)
			player:setStorageValue(12204, 1)
			for _, lookType in ipairs({ 1243, 1244 }) do
				player:addOutfitAddon(lookType, 1)
				player:addOutfitAddon(lookType, 2)
			end
			player:getPosition():sendMagicEffect(CONST_ME_HOLYAREA)
		elseif m4 >= 3 then
			npcHandler:say("You faced the inquisition and won. The reward room is open to you. May the gods go with you.", cid)
		end
	elseif msgcontains(msg, "eclipse") then
		if m3 == 2 or m3 == 3 then
			npcHandler:say("Go to Femor Hills and tell the carpet pilot the codeword {eclipse}. He will take you there.", cid)
		end
	elseif msgcontains(msg, "bender shun") or msgcontains(msg, "shun") then
		if m1 == 1 then
			npcHandler:say("Bender Shun knows the state of the world better than anyone. Ask him about the {inquisition}. If he says the world is ready, return to me.", cid)
		else
			npcHandler:say("Bender Shun is a strange man, but his word about the world is to be trusted.", cid)
		end
	elseif msgcontains(msg, "outfit") then
		if m3 >= 5 then
			npcHandler:say("The outfit of the Hand of the Inquisition is yours. Wear it with pride.", cid)
		else
			npcHandler:say("An outfit must be earned.", cid)
		end
	elseif msgcontains(msg, "yes") then
		if npcHandler.topic[cid] == 2 then
			npcHandler:say({
				"So be it. Now you are a member of the inquisition. ...",
				"Before anything starts, the world must be ready. Go to {Bender Shun} and ask him about the {inquisition}. When he confirms it, report back to me."
			}, cid)
			player:setStorageValue(S.Questline, 1)
			player:setStorageValue(S.Mission01, 1)
		elseif npcHandler.topic[cid] == 4 then
			if player:removeItem(5905, 20) then
				npcHandler:say({
					"Good. Now to the test. The Count, a vampire lord, hides in a crypt in the Green Claw Swamp. ...",
					"Press the buried coffin in the crypt to wake him. Bring me his ring. If he bests you, say {the Count} to me and you may try again."
				}, cid)
				player:setStorageValue(S.Mission02, 2)
				player:setStorageValue(S.CountTry, 1)
			else
				npcHandler:say("You do not have 20 vampire dusts.", cid)
			end
		elseif npcHandler.topic[cid] == 5 then
			if player:removeItem(7924, 1) then
				npcHandler:say("Excellent. The Count is no more. Ask me for the next {mission}.", cid)
				player:setStorageValue(S.Mission02, 3)
				player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
			else
				npcHandler:say("You do not have the ring.", cid)
			end
		elseif npcHandler.topic[cid] == 6 then
			if player:removeItem(6499, 30) then
				npcHandler:say({
					"Good. Now the real work begins. A coven of witches hides on an island called {Eclipse}. ...",
					"Travel to Femor Hills and tell the carpet pilot the codeword eclipse. Use this vial of holy water on the cauldron there. A demon named Ungreez watches the island. Help kill him, then take the witches' grimoire from the chest and bring it to me."
				}, cid)
				player:setStorageValue(S.Mission03, 2)
				player:addItem(133, 1)
			else
				npcHandler:say("You do not have 30 demonic essences.", cid)
			end
		elseif npcHandler.topic[cid] == 8 then
			if player:removeItem(7874, 1) then
				npcHandler:say({
					"The grimoire! With this we will find the rest of the coven. You have done well. ...",
					"As a reward, I give you the outfit of the Hand of the Inquisition. The addons must be earned later."
				}, cid)
				player:setStorageValue(S.Mission03, 5)
				player:addOutfit(1243)
				player:addOutfit(1244)
				player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
			else
				npcHandler:say("You do not have the grimoire.", cid)
			end
		elseif npcHandler.topic[cid] == 7 then
			if player:getBlessings() == 5 then
				npcHandler:say("You already have been blessed!", cid)
			elseif player:removeTotalMoney(totalBlessPrice) then
				npcHandler:say("You have been blessed by all of five gods!, |PLAYERNAME|.", cid)
				for b = 1, 5 do
					player:addBlessing(b)
				end
				player:getPosition():sendMagicEffect(CONST_ME_HOLYAREA)
			else
				npcHandler:say("Come back when you have enough money.", cid)
			end
		end
		npcHandler.topic[cid] = 0
	elseif msgcontains(msg, "no") then
		if npcHandler.topic[cid] > 0 then
			npcHandler:say("Then no.", cid)
			npcHandler.topic[cid] = 0
		end
	elseif msgcontains(msg, 'dark') then
		npcHandler:say({
			'The dark powers are always present. If a human shows only the slightest weakness, they try to corrupt him and to lure him into their service. ...',
			'We must be constantly aware of evil that comes in many disguises.'
		}, cid)
		npcHandler.topic[cid] = 0
	elseif msgcontains(msg, 'king') then
		npcHandler:say({
			'The Thaian kings are crowned by a representative of the churches. This means they reign in the name of the gods of good and are part of the godly plan for humanity. ...',
			'As nominal head of the church of Banor, the kings aren\'t only worldly but also spiritual authorities. ...',
			'The kings fund the inquisition and sometimes provide manpower in matters of utmost importance. The inquisition, in return, protects the realm from heretics and individuals that aim to undermine the holy reign of the kings.'
		}, cid)
		npcHandler.topic[cid] = 0
	elseif msgcontains(msg, 'banor') then
		npcHandler:say({
			'In the past, the order of Banor was the only order of knighthood in existence. In the course of time, the order concentrated more and more on spiritual matters rather than on worldly ones. ...',
			'Nowadays, the order of Banor sanctions new orders and offers spiritual guidance to the fighters of good.'
		}, cid)
		npcHandler.topic[cid] = 0
	elseif msgcontains(msg, 'fardos') then
		npcHandler:say('The priests of Fardos are often mystics who have secluded themselves from worldly matters. Others provide guidance and healing to people in need in the temples.', cid)
		npcHandler.topic[cid] = 0
	elseif msgcontains(msg, 'uman') then
		npcHandler:say({
			'The church of Uman oversees the education of the masses as well as the doings of the sorcerer and druid guilds. It decides which lines of research are in accordance with the will of Uman and which are not. ...',
			'Concerned, the inquisition watches the attempts of these guilds to become more and more independent and to make own decisions. ...',
			'Unfortunately, the sorcerer guild has become dangerously influential and so the hands of our priests are tied due to political matters ...',
			'The druids lately claim that they are serving Crunor\'s will and not Uman\'s. Such heresy could only become possible with the independence of Carlin from the Thaian kingdom. ...',
			'The spiritual centre of the druids switched to Carlin where they have much influence and cannot be supervised by the inquisition.'
		}, cid)
		npcHandler.topic[cid] = 0
	elseif msgcontains(msg, 'fafnar') then
		npcHandler:say({
			'Fafnar is mostly worshipped by the peasants and farmers in rural areas. ...',
			'The inquisition has a close eye on these activities. Simply people tend to mix local superstitions with the teachings of the gods. This again may lead to heretical subcults.'
		}, cid)
		npcHandler.topic[cid] = 0
	elseif msgcontains(msg, 'edron') then
		npcHandler:say({
			'Edron illustrates perfectly why the inquisition is needed and why we need more funds and manpower. ...',
			'Our agents were on their way to investigate certain occurrences there when some faithless knights fled to some unholy ruins. ...',
			'We were unable to wipe them out and the local order of knighthood was of little help. ...',
			'It\'s almost sure that something dangerous is going on there, so we have to continue our efforts.'
		}, cid)
		npcHandler.topic[cid] = 0
	elseif msgcontains(msg, 'ankrahmun') then
		npcHandler:say({
			'Even though they claim differently, this city is in the firm grip of Zathroth and his evil minions. Their whole twisted religion is a mockery of the teachings of our gods ...',
			'As soon as we have gathered the strength, we should crush this city once and for all.'
		}, cid)
		npcHandler.topic[cid] = 0
	end
	return true
end

keywordHandler:addKeyword({'paladin'}, StdModule.say, {npcHandler = npcHandler, text = 'It\'s a shame that only a few paladins still use their abilities to further the cause of the gods of good. Too many paladins have become selfish and greedy.'})
keywordHandler:addKeyword({'knight'}, StdModule.say, {npcHandler = npcHandler, text = 'Nowadays, most knights seem to have forgotten the noble cause to which all knights were bound in the past. Only a few have remained pious, serve the gods and follow their teachings.'})
keywordHandler:addKeyword({'sorcerer'}, StdModule.say, {npcHandler = npcHandler, text = 'Those who wield great power have to resist great temptations. We have the burden to eliminate all those who give in to the temptations.'})
keywordHandler:addKeyword({'druid'}, StdModule.say, {npcHandler = npcHandler, text = 'The druids here still follow the old rules. Sadly, the druids of Carlin have left the right path in the last years.'})
keywordHandler:addKeyword({'dwarf'}, StdModule.say, {npcHandler = npcHandler, text = 'The dwarfs are allied with Thais but follow their own obscure religion. Although dwarfs keep mostly to themselves, we have to observe this alliance closely.'})
keywordHandler:addKeyword({'kazordoon'}, StdModule.say, {npcHandler = npcHandler, text = 'The dwarfs are allied with Thais but follow their own obscure religion. Although dwarfs keep mostly to themselves, we have to observe this alliance closely.'})
keywordHandler:addKeyword({'elves'}, StdModule.say, {npcHandler = npcHandler, text = 'Those elves are hardly any more civilised than orcs. They can become a threat to mankind at any time.'})
keywordHandler:addKeyword({'ab\'dendriel'}, StdModule.say, {npcHandler = npcHandler, text = 'Those elves are hardly any more civilised than orcs. They can become a threat to mankind at any time.'})
keywordHandler:addKeyword({'venore'}, StdModule.say, {npcHandler = npcHandler, text = 'Venore is somewhat difficult to handle. The merchants have a close eye on our activities in their city and our authority is limited there. However, we will use all of our influence to prevent a second Carlin.'})
keywordHandler:addKeyword({'drefia'}, StdModule.say, {npcHandler = npcHandler, text = 'Drefia used to be a city of sin and heresy, just like Carlin nowadays. One day, the gods decided to destroy this town and to erase all evil there.'})
keywordHandler:addKeyword({'darashia'}, StdModule.say, {npcHandler = npcHandler, text = 'Darashia is a godless town full of mislead fools. One day, it will surely share the fate of its sister town Drefia.'})
keywordHandler:addKeyword({'demon'}, StdModule.say, {npcHandler = npcHandler, text = 'Demons exist in many different shapes and levels of power. In general, they are servants of the dark gods and command great powers of destruction.'})
keywordHandler:addKeyword({'carlin'}, StdModule.say, {npcHandler = npcHandler, text = 'Carlin is a city of sin and heresy. After the reunion of Carlin with the kingdom, the inquisition will have much work to purify the city and its inhabitants.'})
keywordHandler:addKeyword({'zathroth'}, StdModule.say, {npcHandler = npcHandler, text = 'We can see his evil influence almost everywhere. Keep your eyes open or the dark one will lead you on the wrong way and destroy you.'})
keywordHandler:addKeyword({'crunor'}, StdModule.say, {npcHandler = npcHandler, text = 'The church of Crunor works closely together with the druid guild. This makes a cooperation sometimes difficult.'})
keywordHandler:addKeyword({'gods'}, StdModule.say, {npcHandler = npcHandler, text = 'We owe to the gods of good our creation and continuing existence. If it weren\'t for them, we would surely fall prey to the minions of the vile and dark gods.'})
keywordHandler:addKeyword({'church'}, StdModule.say, {npcHandler = npcHandler, text = 'The churches of the gods united to fight heresy and dark magic. They are the shield of the true believers, while the inquisition is the sword that fights all enemies of virtuousness.'})
keywordHandler:addKeyword({'inquisitor'}, StdModule.say, {npcHandler = npcHandler, text = 'The churches of the gods entrusted me with the enormous and responsible task to lead the inquisition. I leave the field work to inquisitors who I recruit from fitting people that cross my way.'})
keywordHandler:addKeyword({'believer'}, StdModule.say, {npcHandler = npcHandler, text = 'Belive on the gods and they will show you the path.'})
keywordHandler:addKeyword({'job'}, StdModule.say, {npcHandler = npcHandler, text = 'By edict of the churches I\'m the Lord Inquisitor.'})
keywordHandler:addKeyword({'name'}, StdModule.say, {npcHandler = npcHandler, text = 'I\'m Henricus, the Lord Inquisitor.'})

npcHandler:setMessage(MESSAGE_GREET, "Greetings, fellow {believer} |PLAYERNAME|!")
npcHandler:setMessage(MESSAGE_FAREWELL, "Always be on guard, |PLAYERNAME|!")
npcHandler:setMessage(MESSAGE_WALKAWAY, "This ungraceful haste is most suspicious!")

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())
