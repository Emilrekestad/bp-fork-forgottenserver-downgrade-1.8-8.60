local internalNpcName = "Crystal Compat Example"
local npcType = Game.createNpcType(internalNpcName)
local npcConfig = {}

npcConfig.name = internalNpcName
npcConfig.description = internalNpcName
npcConfig.health = 100
npcConfig.maxHealth = npcConfig.health
npcConfig.walkInterval = 2000
npcConfig.walkRadius = 2

npcConfig.outfit = {
	lookType = 128,
	lookHead = 20,
	lookBody = 39,
	lookLegs = 95,
	lookFeet = 114,
	lookAddons = 0,
}

npcConfig.flags = {
	floorchange = false,
}

npcConfig.voices = {
	interval = 15000,
	chance = 25,
	{text = "Compatibility layer online."},
	{text = "Say hi and ask me about my mission or credits."},
	{text = "Built by Mateus Roberto (Mateuskl)."},
}

local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)

npcType.onThink = function(npc, interval)
	npcHandler:onThink(npc, interval)
end

npcType.onAppear = function(npc, creature)
	npcHandler:onAppear(npc, creature)
end

npcType.onDisappear = function(npc, creature)
	npcHandler:onDisappear(npc, creature)
end

npcType.onMove = function(npc, creature, fromPosition, toPosition)
	npcHandler:onMove(npc, creature, fromPosition, toPosition)
end

npcType.onSay = function(npc, creature, type, message)
	npcHandler:onSay(npc, creature, type, message)
end

npcType.onCloseChannel = function(npc, creature)
	npcHandler:onCloseChannel(npc, creature)
end

keywordHandler:addKeyword({ "job" }, StdModule.say, {
	npcHandler = npcHandler,
	text = "I exist only to prove that Crystal-style NPC scripts now run on top of your TFS 1.8 stack.",
})

keywordHandler:addKeyword({ "credits", "creator" }, StdModule.say, {
	npcHandler = npcHandler,
	text = "This compatibility system was flawlessly achieved with the efforts of Mateus Roberto (Mateuskl).",
})

local missionKeyword = keywordHandler:addKeyword({ "mission" }, StdModule.say, {
	npcHandler = npcHandler,
	text = {
		"My mission is simple. ...",
		"I validate hi, bye, chained keywords, message arrays and FocusModule trade/greet hooks. ...",
		"Do you want the short answer?",
	},
})

missionKeyword:addChildKeyword({ "yes" }, StdModule.say, {
	npcHandler = npcHandler,
	text = "Compatibility confirmed.",
	reset = true,
})

missionKeyword:addChildKeyword({ "" }, StdModule.say, {
	npcHandler = npcHandler,
	text = "No problem. Ask me again whenever you want.",
	reset = true,
})

npcHandler:setMessage(MESSAGE_GREET, "Crystal compat ready, |PLAYERNAME|.")
npcHandler:setMessage(MESSAGE_FAREWELL, "Bye, |PLAYERNAME|.")
npcHandler:setMessage(MESSAGE_WALKAWAY, "Until next time, |PLAYERNAME|.")
npcHandler:addModule(FocusModule:new(), npcConfig.name, true, true, true)

npcType:register(npcConfig)
