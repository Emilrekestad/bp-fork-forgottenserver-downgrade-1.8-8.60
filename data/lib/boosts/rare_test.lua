-- Does the Rarity Boost actually deliver what the store offer promises?
--
-- Replays the exact tier-selection logic from RarityStats.rollRarity with and
-- without the boost's roll scaling, over enough samples that the rates are
-- meaningful. Tests the ARITHMETIC, not the live server -- the point is to
-- confirm that "+50% chance to roll a rarity tier" is a true statement about
-- what the code does, before it is sold to anyone.

local tiers = {
  [1] = { prefix = 'scarce',   rollThreshold = 5000 },
  [2] = { prefix = 'adept',    rollThreshold = 2500 },
  [3] = { prefix = 'superior', rollThreshold = 1000 },
  [4] = { prefix = 'prime',    rollThreshold = 700  },
}

local BOOST = 50 -- GlobalBoosts.Types[RARE].magnitude
local N = 2000000

local function run(boosted)
  local hits, byTier = 0, {0, 0, 0, 0}
  for _ = 1, N do
    local rarity = math.random(1, 10000)
    if boosted then
      rarity = math.max(1, math.floor(rarity * 100 / (100 + BOOST)))
    end
    local tier = 0
    for i = 1, #tiers do
      if rarity <= tiers[i].rollThreshold then tier = i end
    end
    if tier > 0 then
      hits = hits + 1
      byTier[tier] = byTier[tier] + 1
    end
  end
  return hits, byTier
end

math.randomseed(20260904)

local baseHits, baseTiers = run(false)
local boostHits, boostTiers = run(true)

print(string.format("samples per run: %d, boost magnitude: +%d%%\n", N, BOOST))
print(string.format("%-10s %12s %12s %10s", "tier", "base", "boosted", "change"))
for i = 1, #tiers do
  local b, x = baseTiers[i] / N * 100, boostTiers[i] / N * 100
  print(string.format("%-10s %11.3f%% %11.3f%% %+9.1f%%",
    tiers[i].prefix, b, x, (x / b - 1) * 100))
end

local b, x = baseHits / N * 100, boostHits / N * 100
print(string.format("\n%-10s %11.3f%% %11.3f%% %+9.1f%%", "ANY TIER", b, x, (x / b - 1) * 100))

-- The offer says "+50% chance". Anything outside a percent or so of that and
-- the wording is a lie, not a rounding difference.
local delta = (x / b - 1) * 100
if math.abs(delta - BOOST) <= 1.0 then
  print(string.format("\nPASS: overall rate moved %+.1f%%, offer claims +%d%%", delta, BOOST))
else
  print(string.format("\nFAIL: overall rate moved %+.1f%%, offer claims +%d%%", delta, BOOST))
end
