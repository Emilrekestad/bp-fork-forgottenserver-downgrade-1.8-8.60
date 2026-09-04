-- Legacy loader counterpart to data/scripts/chatchannels/item_bazaar.lua.
-- Read-only: the Item Bazaar channel carries server-generated notifications
-- only, so player speech is always rejected.
function onSpeak(player, type, message)
	return false
end
