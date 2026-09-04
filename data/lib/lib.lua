DATA_DIRECTORY = "data"
CORE_DIRECTORY = DATA_DIRECTORY

-- Core API functions implemented in Lua
dofile(CORE_DIRECTORY .. '/lib/core/core.lua')

-- Compatibility library for our old Lua API
dofile(CORE_DIRECTORY .. '/lib/compat/compat.lua')

-- Debugging helper function for Lua developers
dofile(CORE_DIRECTORY .. '/lib/debugging/dump.lua')

dofile(CORE_DIRECTORY .. '/lib/functions/load.lua')

-- World Missions — after functions/load.lua specifically, so this
-- codebase's Lua Zone(name) implementation (installed by that file's own
-- dofile of boss_lever.lua) already exists. See
-- lib/worldmissions/worldmissions.lua for why.
dofile(CORE_DIRECTORY .. '/lib/worldmissions/worldmissions.lua')

-- Loyalty programme. Depends on nothing but the DB and the achievements lib
-- (already loaded via core.lua), so its position here is not significant.
dofile(CORE_DIRECTORY .. '/lib/loyalty/loyalty.lua')

-- Achievements database mirror. Must load AFTER core.lua, which defines the
-- `achievements` catalogue this reads and the Player.addAchievement it hooks.
dofile(CORE_DIRECTORY .. '/lib/achievements/achievements_db.lua')

-- Global server boosts. Self-contained: it owns its own table, and the only
-- globals it touches (Game, db, Condition) exist before any lib loads. Loaded
-- here rather than from a script so the store's purchase handler, the
-- eventcallbacks and the globalevent all see the same GlobalBoosts table
-- regardless of which of them the script loader reaches first.
dofile(CORE_DIRECTORY .. '/lib/boosts/global_boosts.lua')

-- Highscores. Pure catalogue plus a query engine; it reads `players` and the
-- mirror tables the two libs above maintain, and nothing reads it back, so it
-- loads last. Its Vocation() lookups run per request, not at load.
dofile(CORE_DIRECTORY .. '/lib/highscores/highscores.lua')

-- Loot Seller rules (item 27446). Reads ItemType sell prices and the
-- ItemPriceRegistry that lib/core/core.lua already installed, and is read
-- back by data/scripts/actions/items/loot_seller.lua. Nothing here runs at
-- load time, so its position is not significant.
dofile(CORE_DIRECTORY .. '/lib/lootseller/loot_seller.lua')

local startupFile = io.open("data/startup/startup.lua", "r")
if startupFile ~= nil then
	dofile("data/startup/startup.lua")
	io.close(startupFile)
end
