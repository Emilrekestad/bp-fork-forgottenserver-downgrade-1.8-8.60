-- Item Rarity system — Rebirth debug diagnostic. Reports exactly why
-- findQualifyingDruid would or wouldn't find a rescuer for the caller right
-- now, checking every party member against each real condition individually
-- instead of just the final yes/no -- mirrors the philosophy of /roll's own
-- raw-truth diagnostic (data/scripts/talkactions/god/rarity/roll.lua).

local check = TalkAction("/rebirthcheck")

function check.onSay(player, words, param)
	local party = player:getParty()
	if not party then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "[RebirthCheck] You are not in a party. Participants() would only ever see yourself.")
		return false
	end

	local members = party:getMembers()
	table.insert(members, party:getLeader())

	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("[RebirthCheck] Party has %d member(s) (including leader).", #members))

	local foundQualifying = false
	for _, member in ipairs(members) do
		if member and member ~= player then
			local isDruid = member:isDruid()
			local health = member:getHealth()
			local hasRod = RarityRebirth.hasRebirthRod(member)
			local cooldownUntil = member:kv():scoped("rarity"):get("rebirth_cooldown_until") or 0
			local onCooldown = cooldownUntil > os.time()

			local rodDesc = "none equipped"
			for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
				local item = member:getSlotItem(slot)
				if item then
					local desc = item:getSpecialDescription()
					if desc and desc ~= "" then
						rodDesc = item:getName() .. ": " .. desc:gsub("\n", " | ")
					end
				end
			end

			local qualifies = isDruid and health > 0 and hasRod and not onCooldown
			if qualifies then
				foundQualifying = true
			end

			player:sendTextMessage(MESSAGE_INFO_DESCR, string.format(
				"[RebirthCheck] %s -- isDruid=%s, health=%d, hasRebirthRod=%s, onCooldown=%s (until %d, now %d), QUALIFIES=%s",
				member:getName(), tostring(isDruid), health, tostring(hasRod), tostring(onCooldown),
				cooldownUntil, os.time(), tostring(qualifies)
			))
			player:sendTextMessage(MESSAGE_INFO_DESCR, "[RebirthCheck]   Weapon slots: " .. rodDesc)
		end
	end

	player:sendTextMessage(MESSAGE_INFO_DESCR, "[RebirthCheck] Overall: " .. (foundQualifying and "a qualifying Druid WAS found -- Rebirth should trigger on your next lethal hit." or "NO qualifying Druid found -- Rebirth would NOT trigger right now."))

	return false
end

check:separator(" ")
check:accountType(6)
check:access(true)
check:register()
