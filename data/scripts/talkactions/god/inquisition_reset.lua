-- GM test command: /inqreset wipes your own Inquisition progress (storages 12160-12182),
-- so the quest can be walked again from Henricus. Old test data from the earlier
-- version of the quest sits in these keys and confuses the new missions.
local talk = TalkAction("/inqreset")

function talk.onSay(player, words, param)
	for key = 12160, 12182 do
		player:setStorageValue(key, -1)
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, "Your Inquisition progress is reset.")
	return false
end

talk:separator(" ")
talk:accountType(6)
talk:register()

-- GM check: /inqstate prints your Inquisition storages and what the quest log sees.
local state = TalkAction("/inqstate")

function state.onSay(player, words, param)
	local parts = {}
	for key = 12160, 12200 do
		parts[#parts + 1] = key .. "=" .. player:getStorageValue(key)
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, "Storages: " .. table.concat(parts, " "))
	player:sendTextMessage(MESSAGE_INFO_DESCR, "Lib keys loaded: SealUshuriel=" .. tostring(Storage.TheInquisition.SealUshuriel) .. " CrystalCaves=" .. tostring(Storage.TheInquisition.CrystalCaves) .. " BloodHalls=" .. tostring(Storage.TheInquisition.BloodHalls))
	local total, found = 0, false
	for _, quest in pairs(Game.getQuests()) do
		total = total + 1
		if quest.name == "The Inquisition" then
			found = true
			local shown = {}
			for _, mission in ipairs(quest:getMissions(player)) do
				shown[#shown + 1] = mission.name
			end
			player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Quest registered (id %d), started=%s, missions shown: %s",
				quest.id, tostring(quest:isStarted(player)), table.concat(shown, " | ")))
		end
	end
	if not found then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "The Inquisition is NOT in the registry (" .. total .. " quests loaded).")
	end
	return false
end

state:separator(" ")
state:accountType(6)
state:register()

-- GM test: /inqseal <ushuriel|zugurosh|madareth|vats|annihilon|hellgorak> marks that seal broken for you.
local seal = TalkAction("/inqseal")
local SEALS = { ushuriel = 12190, zugurosh = 12191, madareth = 12192, vats = 12193, annihilon = 12194, hellgorak = 12195 }

function seal.onSay(player, words, param)
	local key = SEALS[param:lower()]
	if not key then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Use: /inqseal ushuriel | zugurosh | madareth | vats | annihilon | hellgorak")
		return false
	end
	player:setStorageValue(key, 2)
	player:sendTextMessage(MESSAGE_INFO_DESCR, "Seal marked broken: " .. param:lower())
	return false
end

seal:separator(" ")
seal:accountType(6)
seal:register()
