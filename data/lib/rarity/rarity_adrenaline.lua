-- Item Rarity system — Adrenaline Rush (stats[46]) shared state. Lives under
-- data/lib (not data/scripts) for the same reason rarity_rebirth.lua does --
-- guaranteed loaded before any data/scripts file that touches it. Two
-- separate files need this: data/scripts/creaturescripts/rarity/
-- rarity_loot_drop.lua sets it on kill (boots check, speed condition +
-- registering the damage-boost window), data/scripts/creaturescripts/rarity/
-- rarity_combat.lua reads it on the attacker's next hits to apply the
-- temporary damage boost.

RarityAdrenaline = RarityAdrenaline or {}
-- [playerId] = expiry (os.time() seconds) while the damage-boost side of the
-- buff is active. The speed side is a real Condition (self-expiring,
-- doesn't need tracking here) -- this table only backs the damage-boost
-- check in statChange, which has no native condition equivalent to hook.
RarityAdrenaline.active = RarityAdrenaline.active or {}
RarityAdrenaline.DURATION_SECONDS = 10 -- TEMPORARY placeholder -- balance later
