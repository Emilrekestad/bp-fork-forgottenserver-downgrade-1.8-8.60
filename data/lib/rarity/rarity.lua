-- Item Rarity system — entry point, mirrors data/lib/bao/bao.lua's own
-- chain-loading pattern. Currently a single file, but kept as its own
-- dofile chain (rather than adding rarity_stats.lua directly to core.lua)
-- so future rarity lib files can be added here without touching core.lua
-- again.

dofile(CORE_DIRECTORY .. "/lib/rarity/rarity_class.lua")
dofile(CORE_DIRECTORY .. "/lib/rarity/rarity_stats.lua")
dofile(CORE_DIRECTORY .. "/lib/rarity/rarity_identify.lua")
dofile(CORE_DIRECTORY .. "/lib/rarity/rarity_rebirth.lua")
dofile(CORE_DIRECTORY .. "/lib/rarity/rarity_adrenaline.lua")
