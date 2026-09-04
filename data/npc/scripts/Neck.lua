local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)		end
function onCreatureSay(cid, type, msg)		npcHandler:onCreatureSay(cid, type, msg)		end
function onThink()				npcHandler:onThink()				end

local function getShopItems()
	return {
		{ name = "lesser guardian gem", id = 44602, buy = 125000 },
		{ name = "guardian gem", id = 44603, buy = 1000000 },
		{ name = "greater guardian gem", id = 44604, buy = 6000000 },

		{ name = "lesser marksman gem", id = 44605, buy = 125000 },
		{ name = "marksman gem", id = 44606, buy = 1000000 },
		{ name = "greater marksman gem", id = 44607, buy = 6000000 },

		{ name = "lesser sage gem", id = 44608, buy = 125000 },
		{ name = "sage gem", id = 44609, buy = 1000000 },
		{ name = "greater sage gem", id = 44610, buy = 6000000 },

		{ name = "lesser mystic gem", id = 44611, buy = 125000 },
		{ name = "mystic gem", id = 44612, buy = 1000000 },
		{ name = "greater mystic gem", id = 44613, buy = 6000000 },

		{ name = "lesser spiritualist gem", id = 49371, buy = 125000 },
		{ name = "spiritualist gem", id = 49372, buy = 1000000 },
		{ name = "greater spiritualist gem", id = 49373, buy = 6000000 },
	}
end

local function getShopItemsById()
	local byId = {}
	for _, entry in ipairs(getShopItems()) do
		byId[entry.id] = entry
	end
	return byId
end

local function onBuy(cid, item, subType, amount, ignoreCap, inBackpacks)
	local player = Player(cid)
	local entry = getShopItemsById()[item]
	if not entry then
		return true
	end

	local totalPrice = entry.buy * amount
	if player:getMoney() < totalPrice then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "You do not have enough money.")
		return true
	end

	local count = 0
	for i = 1, amount do
		local newItem = Game.createItem(entry.id, 1)
		if player:addItemEx(newItem, false) ~= RETURNVALUE_NOERROR then
			npcHandler:say("First make sure you have enough space in your inventory.", cid)
			break
		end
		count = i
	end

	if count == 0 then
		return true
	end

	player:removeMoney(entry.buy * count)
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Bought %dx %s for %d gold.", count, entry.name, entry.buy * count))
	return true
end

local function tradeCallback(cid, message, keywords, parameters, node)
	if not npcHandler:isFocused(cid) then
		return false
	end
	npcHandler:say("Say hello to my little gems!", cid)
	openShopWindow(cid, getShopItems(), onBuy, nil)
	return true
end

npcHandler:setMessage(MESSAGE_GREET, "Listen |PLAYERNAME|! Beauty can be deadly... and manly. Very manly.")
npcHandler:setMessage(MESSAGE_FAREWELL, "Functional and stylish. |PLAYERNAME| tell Joel I said hi!")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Magic has ruined this land")
npcHandler:setMessage(MESSAGE_SENDTRADE, "Sure.")

keywordHandler:addKeyword({ "gems" }, StdModule.say, { npcHandler = npcHandler, text = "Gems... gems are truly outrageous" })
keywordHandler:addKeyword({ "trade" }, tradeCallback)
keywordHandler:addKeyword({ "weapons" }, StdModule.say, { npcHandler = npcHandler, text = "The best weapons are beautiful, and poison daggers." })
keywordHandler:addKeyword({ "job" }, StdModule.say, { npcHandler = npcHandler, text = "Sometimes, life is worth dying for. That glimmer of hope you see, that's me." })

local voices = {
	{ text = "Poison Daggers.. Poison Daggers.. what would the world be without them?" },
	{ text = "A man who fears sewage fears himself" },
	{ text = "Look upon the river... See how it bends around every obstacle? It does not rage, it does not despair.. Now imagine that in a forty-millimeter PVC pipe." },
}

npcHandler:addModule(VoiceModule:new(voices))
npcHandler:addModule(FocusModule:new())
