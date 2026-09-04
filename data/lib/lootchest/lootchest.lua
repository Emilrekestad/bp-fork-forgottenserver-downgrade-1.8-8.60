-- Loot Chest system -- reusable weighted-reward chests. Load order: config
-- first (pure data), then reward (rolls/grants against it).

dofile(CORE_DIRECTORY .. "/lib/lootchest/lootchest_config.lua")
dofile(CORE_DIRECTORY .. "/lib/lootchest/lootchest_reward.lua")
