-- Old Man Bao — hunter progression system. Load order matters: config first
-- (pure data), then lookup (derives its index from config), then state
-- (reads config for slot/threshold limits). bao_reward.lua and bao_rank.lua
-- load after bao_state.lua since both depend on it (reward for
-- addReputation/addMarks, rank for getReputation/getMasteryCount/setRank);
-- they don't depend on each other so their relative order doesn't matter.

dofile(CORE_DIRECTORY .. "/lib/bao/bao_config.lua")
-- Generated creature-product buy list (scratchpad/gen_bao_products.js). Pure
-- data, loaded before the shop so BaoConfig.Products exists for it.
dofile(CORE_DIRECTORY .. "/lib/bao/bao_products.lua")
dofile(CORE_DIRECTORY .. "/lib/bao/bao_shop.lua")
dofile(CORE_DIRECTORY .. "/lib/bao/bao_story.lua")
dofile(CORE_DIRECTORY .. "/lib/bao/bao_lookup.lua")
dofile(CORE_DIRECTORY .. "/lib/bao/bao_state.lua")
dofile(CORE_DIRECTORY .. "/lib/bao/bao_reward.lua")
dofile(CORE_DIRECTORY .. "/lib/bao/bao_rank.lua")
-- Bounties last: BaoBounty.turnIn pays reputation and therefore calls
-- BaoRank.checkRankUp, and its board selection reads BaoState for rank.
dofile(CORE_DIRECTORY .. "/lib/bao/bao_bounty.lua")
-- The Ledger reads BaoState for Marks and is read BY bao_reward/bao_bounty at
-- runtime (never at load), so it only has to exist before the first grant.
dofile(CORE_DIRECTORY .. "/lib/bao/bao_ledger.lua")
-- The Ledger's database mirror, last: it reads BaoLedger.orderedKeys and
-- BaoLedger.getRank, and BaoLedger.purchase calls back into it.
dofile(CORE_DIRECTORY .. "/lib/bao/bao_ledger_db.lua")
