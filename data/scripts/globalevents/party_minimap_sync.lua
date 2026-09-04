-- Broadcasts each active party's member positions to every member of that
-- party, every tick, so the client (otclient-src/modules/game_minimap) can
-- draw a name + arrow marker for teammates on the minimap even when they're
-- off-screen - mirrors real Tibia's party-tracking minimap feature.
--
-- Delivery uses Player:sendExtendedOpcode() (data/lib/core/player.lua), which
-- gates on isUsingOtClient() and handles the 0x32 wire format plus the 8192
-- byte cap. Deliberately NOT gated on isUsingAstraClient(): that flag also
-- switches the server's item wire format
-- (shouldSendAstraQuiverCountU16()/canSendAstraItemState() in
-- protocolgame.cpp) to something this client's getItem() doesn't parse,
-- which desyncs every item packet.
local EXT_OPCODE_PARTY_POSITIONS = 150 -- must match otclient-src's ExtendedIds.PartyPositions

local partyMinimapSync = GlobalEvent("PartyMinimapSync")

-- Tracks which players got a roster last tick, so leaving a party (or
-- logging out mid-party) sends exactly one "you have no teammates anymore"
-- clearing packet instead of repeating it forever, while players who were
-- never in a party get no traffic at all.
local hadRoster = {}

-- "v" is the vocation CLIENT id, not the vocation id: base and promoted
-- vocations share a clientid in data/XML/vocations.xml (Knight and Elite
-- Knight are both 1), so the client can colour by vocation without knowing
-- about promotions. See PARTY_VOCATION_COLORS in gamelib/ui/uiminimap.lua.
--
-- Tibia character names can't contain quotes/backslashes/control characters
-- (enforced at character creation), so no escaping is needed here.
local function buildRosterJson(members)
	local parts = {}
	for i = 1, #members do
		local member = members[i]
		local pos = member:getPosition()
		local vocation = member:getVocation()
		local vocationClientId = 0
		if vocation and vocation.getClientId then
			vocationClientId = vocation:getClientId() or 0
		end
		parts[#parts + 1] = string.format(
			'{"id":%d,"name":"%s","x":%d,"y":%d,"z":%d,"v":%d}',
			member:getId(), member:getName(), pos.x, pos.y, pos.z, vocationClientId)
	end
	return "[" .. table.concat(parts, ",") .. "]"
end

function partyMinimapSync.onThink(interval)
	for _, player in ipairs(Game.getPlayers()) do
		if player.isUsingOtClient and player:isUsingOtClient() then
			local party = player:getParty()
			local playerId = player:getId()

			if party then
				local roster = { party:getLeader() }
				local members = party:getMembers()
				for i = 1, #members do
					roster[#roster + 1] = members[i]
				end

				player:sendExtendedOpcode(EXT_OPCODE_PARTY_POSITIONS, buildRosterJson(roster))
				hadRoster[playerId] = true
			elseif hadRoster[playerId] then
				player:sendExtendedOpcode(EXT_OPCODE_PARTY_POSITIONS, "[]")
				hadRoster[playerId] = nil
			end
		end
	end
	return true
end

partyMinimapSync:interval(500)
partyMinimapSync:register()
