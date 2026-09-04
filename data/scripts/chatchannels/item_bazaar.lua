-- Item Bazaar channel (id 11).
--
-- Read-only, like Loot (id 10): players never speak here, the server posts
-- into it. Carries two kinds of message:
--   * personal Bazaar notifications (bid accepted, outbid, won, sold,
--     expired, item returned/withdrawn)
--   * paid promotional announcements for listings whose seller paid the
--     optional promotion fee -- these are public and stay anonymous
--
-- Messages are produced by the settlement/bidding domain writing rows into
-- `bazaar_events`, which the pump in data/scripts/globalevents/item_bazaar/
-- delivers. Nothing about auction settlement depends on this channel being
-- open, or even on the player being online -- undelivered events simply stay
-- queued.

local itemBazaar = ChatChannel(11, "Item Bazaar")
itemBazaar:public(true)

function itemBazaar.onSpeak(player, type, message)
	-- read-only channel for automated Bazaar notifications
	return false
end

itemBazaar:register()
