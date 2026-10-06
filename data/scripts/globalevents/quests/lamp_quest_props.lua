-- "The Lamp That Wanted a Job" -- puts the two quest props on the map at boot.
--
-- The same approach WorldMissions.reapplyActivationVisuals() uses for the
-- Liberty Bay levers: create the item only if it is not already on the tile,
-- so this is idempotent whether or not map state survives a restart, and the
-- owner never has to place anything in RME.
--
-- Both positions were probed live before being committed (see
-- data/lib/quests/lamp_quest.lua). If a tile ever stops existing, this logs
-- and moves on rather than leaving the quest half-registered -- the Actions in
-- data/scripts/actions/quests/ register on the position regardless, so the
-- quest still works, the player just has nothing to look at.
local props = GlobalEvent("LampQuestProps")

-- the pile used to sit 5 tiles west of Joel; take away the old one if a boot left it there
local OLD_PILE_POS = Position(32473, 31598, 7)

function props.onStartup()
	local oldTile = Tile(OLD_PILE_POS)
	local old = oldTile and oldTile:getItemById(1822)
	if old then
		old:remove()
	end
	for key, prop in pairs(LampQuest.Prop) do
		local tile = Tile(prop.pos)
		if not tile then
			logError(string.format("[LampQuest] %s: no tile at %d, %d, %d -- the prop was not placed.",
				key, prop.pos.x, prop.pos.y, prop.pos.z))
		elseif not tile:getItemById(prop.id) then
			if Game.createItem(prop.id, 1, prop.pos) then
				logInfo(string.format("[LampQuest] %s placed at %d, %d, %d.", key, prop.pos.x, prop.pos.y, prop.pos.z))
			else
				logError(string.format("[LampQuest] %s: could not create item %d at %d, %d, %d.",
					key, prop.id, prop.pos.x, prop.pos.y, prop.pos.z))
			end
		end
	end
	return true
end

props:register()

-- the pile glows green so a player can spot it (owner, 2026-10-04): a soft pulse every 2.5 s,
-- only while somebody is near enough to see it
local glow = GlobalEvent("LampQuestPileGlow")

function glow.onThink(interval)
	local pos = LampQuest.Prop.strikerPile.pos
	if #Game.getSpectators(pos, false, true, 9, 9, 7, 7) > 0 then
		pos:sendMagicEffect(CONST_ME_GREEN_ENERGY_SPARK)
	end
	return true
end

glow:interval(2500)
glow:register()
