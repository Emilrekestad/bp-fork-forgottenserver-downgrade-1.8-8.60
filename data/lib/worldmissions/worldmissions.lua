-- World Missions system — entry point, mirrors data/lib/rarity/rarity.lua
-- and data/lib/bao/bao.lua's own dofile-chain pattern.
--
-- Loaded from data/lib/lib.lua, AFTER data/lib/functions/load.lua rather
-- than from core.lua's own chain (where bao.lua/rarity.lua live) --
-- deliberate: functions/load.lua is what installs this codebase's Lua
-- Zone implementation (overrides the native Zone global, see
-- data/lib/functions/boss_lever.lua), and Cull/Presence missions need
-- that Zone("name") factory to already exist. core.lua's own chain runs
-- BEFORE functions/load.lua, so loading from there would have raced it.

dofile(CORE_DIRECTORY .. "/lib/worldmissions/worldmissions_config.lua")
dofile(CORE_DIRECTORY .. "/lib/worldmissions/worldmissions_state.lua")
