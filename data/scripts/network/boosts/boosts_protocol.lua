-- Global Server Boosts — client protocol.
--
-- Same shape as achievements / bao / item bazaar / questlog: one raw opcode
-- byte per direction via PacketHandler (receive) and NetworkMessage +
-- :sendToPlayer (send). Unlike those, this one is mostly SERVER-PUSHED — the
-- HUD has no window to open, so the client is told about every state change
-- rather than polling for it.
--
-- 0x56/0x57 (86/87 decimal): confirmed free against the client's
-- GameServerOpcodes / ClientOpcodes enums (otclient-src/src/client/
-- protocolcodes.h — 80/81/82 and 90-99 are the only native claims anywhere
-- near this range on either side) AND every custom opcode already taken in
-- this codebase: 0x28-0x3F, 0x4A-0x4F (achievements/bao/item bazaar), 0x53
-- (task board), 0x54/0x55 (quest log), 0x5A-0x5C, 0x5F, 0x61-0x62, 0x73, and
-- the high 0x9x-0xFx native/custom range. See bao_protocol.lua's header for
-- why this checklist is not optional: an opcode collision here previously
-- made every Bao action silently walk the player north.
local OPCODE_BOOSTS_REQUEST = 0x57 -- client -> server
local OPCODE_BOOSTS_SEND = 0x56    -- server -> client

local RESP_STATE = 0x01
local ACTION_REQUEST_STATE = 0x01

local ACTION_COOLDOWN = 400

local function supportsCustomNetwork(player)
	return player and player.isUsingOtClient and player:isUsingOtClient()
end

-- Payload: byte count, then per boost
--   byte   id            (GlobalBoosts.ID — the client maps this to an accent
--                         colour)
--   string short         ("Exp", "Haste", "Reg" — what the HUD pill shows)
--   string name          ("Experience Boost")
--   string effect        ("+50% experience for every player online")
--   u16    remaining     (seconds; the client counts down locally from here)
--   u16    cap           (MAX_STACK_SECONDS, so the drain bar has a scale)
--   string contributor   (who last paid; "" if unknown)
--
-- short/name/effect ride the wire rather than living only in the client, so a
-- boost added server-side renders with no client change at all -- the pill
-- draws `short` as text and the client holds only an accent colour per id.
-- Both u16 fields are safe: the cap is 12 hours (43200) and remaining can
-- never exceed it.

local function sendState(player)
	if not supportsCustomNetwork(player) then
		return false
	end

	local active = GlobalBoosts.active()

	local out = NetworkMessage(player)
	out:addByte(OPCODE_BOOSTS_SEND)
	out:addByte(RESP_STATE)
	out:addByte(math.min(#active, 255))

	for index, entry in ipairs(active) do
		if index > 255 then
			break
		end
		out:addByte(entry.id)
		out:addString(entry.boost.short or entry.boost.name)
		out:addString(entry.boost.name)
		out:addString(entry.boost.effect)
		out:addU16(math.min(65535, entry.remaining))
		out:addU16(math.min(65535, GlobalBoosts.MAX_STACK_SECONDS))
		out:addString(entry.contributor or "")
	end

	return out:sendToPlayer(player)
end

GlobalBoosts.sendState = sendState

-- Overrides the no-op stub declared in lib/boosts/global_boosts.lua. Called
-- on every activation, extension and expiry — never on a timer, because the
-- client owns the countdown between pushes.
function GlobalBoosts.broadcastState()
	for _, player in ipairs(Game.getPlayers()) do
		sendState(player)
	end
end

local requestHandler = PacketHandler(OPCODE_BOOSTS_REQUEST)

function requestHandler.onReceive(player, msg)
	local action = NetworkGuard.readByte(msg)
	if not action then
		return
	end

	if not NetworkGuard.cooldown(player, "boosts:" .. action, ACTION_COOLDOWN) then
		return
	end

	if action == ACTION_REQUEST_STATE then
		sendState(player)
	end
end

requestHandler:register()
