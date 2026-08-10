local npcType = Game.createNpcType("Captain")
npcType:outfit({lookType = 151, lookHead = 78, lookBody = 115, lookLegs = 85, lookFeet = 114, lookAddons = 2})
npcType:spawnRadius(4)
npcType:walkInterval(2000)
npcType:walkSpeed(100)
npcType:defaultBehavior()

local handler = NpcsHandler("Captain")
handler:setGreetKeywords({"hi", "hello"})
handler:setFarewellKeywords({"bye", "farewell"})
handler:setFarewellResponse({"Farewell, |PLAYERNAME|."})

local greet = handler:keyword(handler.greetWords)
greet:setGreetResponse({"Welcome on board, |PLAYERNAME|."})
greet:keyword("captain"):respond("I am the captain of this sailing-ship.")
greet:keyword("trip"):respond("Where do you want to go? To Trekolt, Rhyves, Varak or Saund?")
greet:keyword("ice"):respond("I'm sorry, but we don't serve the routes to the Ice Islands.")

local destinations = {
    trekolt = { position = Position(998, 998, 7), money = 100, premium = true },
    rhyves  = { position = Position(998, 998, 7), money = 120, premium = true },
    varak   = { position = Position(998, 998, 7), money = 160, premium = true },
    saund   = { position = Position(998, 998, 7), money = 150, premium = true }
}
handler:travelTo(destinations)