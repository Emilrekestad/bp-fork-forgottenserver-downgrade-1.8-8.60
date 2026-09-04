# Rebirth System — Status

Reference-only, like `BONUS_BACKLOG.md` in this same folder. Not loaded by
the server (not `dofile`'d anywhere) — purely a record of where this feature
stands, since it went through a lot of live-test-driven iteration.

## What it is

An ultra-rare Legendary-only bonus (`stats[36]` in `rarity_stats.lua`,
`value = "Flag"`, `minTier = 3`, an independent `rollChance = 250`/10000
≈2.5%) rollable only on 5 specific Class 5+ Druid rods: Rod of Destruction
(27458), Lion Rod (34151), Falcon Rod (28716), Sanguine Rod (43885), Grand
Sanguine Rod (43886).

When a party member takes a lethal hit and a *different* party member is a
Druid wearing a Rebirth-rolled rod (alive, off cooldown), the native
`CREATURE_EVENT_PREPAREDEATH` hook vetoes the killing blow. The downed
player is:
- pinned at 1 HP, movement-blocked, given a red-cross status icon
- changed to the White Shade ghost outfit (lookType 560, visible to
  everyone — not `setGhostMode`, which is full invisibility to non-staff)
- made fully damage-immune
- continuously stripped from monster aggro every second (a single drop at
  the moment of downing isn't enough — monsters can reacquire them later)

A ring of 8 holy tiles spawns around them (currently a plain carpet item,
30932, as a functional placeholder — see "Open items" below). The
qualifying Druid stepping on one instantly revives the downed player at 50%
HP with negative conditions cleared (poison/fire/energy/drown/freezing/
dazzled/cursed/bleeding) and the ghost outfit restored.

A `ModalWindow` ("Rebirth" / "Accept Death" / "Discard") lets the downed
player skip ahead to a real death. Both Enter and Escape default to the
safe Discard button, not Accept Death — an irreversible action should never
be the accidental keypress. `!accept` works as a chat-command fallback too.

Unresolved after 60 seconds, the same real death fires automatically —
going through the actual native death pipeline (temple respawn, normal
skill/XP loss), guarded by a `resolving` flag so that finishing blow can
never re-trigger Rebirth on itself (see bug #4 below).

## Files (all deployed, server boots clean as of last verification — 3035
scripts, zero errors)

- `data/lib/rarity/rarity_stats.lua` — Rebirth stat entry + Flag branch +
  minTier/rollChance filter
- `data/lib/rarity/rarity_rebirth.lua` — shared state/constants/helpers.
  **`COOLDOWN_SECONDS` is currently 60 (1 minute) for testing** — real
  value is 45\*60 (2700), clearly commented in the file, needs restoring
  once testing wraps up
- `data/scripts/creaturescripts/rarity/rarity_rebirth.lua` — the
  `onPrepareDeath` veto
- `data/scripts/creaturescripts/rarity/rarity_rebirth_modal.lua` — Accept
  Death / Discard handler
- `data/scripts/movements/rarity/rarity_rebirth_tile.lua` — holy-tile
  revive trigger
- `data/scripts/talkactions/player/rarity/accept.lua` — `!accept` fallback
- `data/scripts/creaturescripts/rarity/rarity_login.lua` — registers all
  the CreatureEvents (RarityHealthChange/RarityManaChange/
  RarityRebirthDeath/RarityRebirthModal)
- `data/scripts/creaturescripts/rarity/rarity_combat.lua` — downed-state
  damage-immunity check added here too
- `data/scripts/talkactions/god/rarity/rebirthcheck.lua` — diagnostic
  command, **still not confirmed working**, deprioritized once the real
  mechanic started functioning correctly

## Bugs found and fixed via live testing (in order)

1. **Unwanted teleport** — a physical corpse item (id 1979, sanctified
   grave) spawned on the downed player's own tile. Grave/tombstone scenery
   items are essentially always solid, so placing one under a standing
   creature triggered the engine's own "creature now standing on a blocked
   tile" auto-relocation, which checks the facing direction first — exactly
   matching the reported symptom. Fixed by removing the ground-item corpse
   entirely.
2. **Ghost visual was actually full invisibility** — `setGhostMode(true)`
   makes the player invisible to every non-staff player (confirmed in
   `src/luaplayer.cpp:2960-2995`), not a translucent shared visual. Replaced
   with a real outfit change to White Shade (lookType 560,
   `data/monsters/undeads/white_shade.lua`), which every player renders
   normally.
3. **Stale cooldown blocked all revives for a long stretch** — a cooldown
   timestamp written during early testing under the old 45-minute value
   kept blocking the Druid from qualifying long after `COOLDOWN_SECONDS`
   was lowered in code. Lowering the constant only affects *future* writes,
   it doesn't clear an already-stored value. Fixed by deleting the stale
   `kv_store` row directly.
4. **Accept Death / natural timeout didn't actually kill the player** — the
   finishing blow (`addHealth`) goes through the exact same combat pipeline
   as any other hit, which re-fires `onPrepareDeath`. Since the downed
   state was already cleared by that point, the handler fell through to
   `findQualifyingDruid` again and could re-trigger Rebirth on its own
   finishing blow. Fixed with a `resolving` guard table checked first in
   `onPrepareDeath` — the first attempt at this fix only added the
   guard-setting logic in `finalizeRealDeath` and forgot to add the actual
   check in `onPrepareDeath` itself; caught and corrected in the next
   round.
5. **Monsters kept attacking the downed player** — `dropAggro` only ran
   once, at the moment of downing. Any monster that reacquired the player
   as a target moments later just kept swinging (damage nullified but
   still visually/functionally intrusive). Fixed with a repeating
   1-second loop (`startAggroDropLoop`) that keeps stripping aggro for the
   whole downed duration.
6. **Character permanently stuck in the ghost outfit** — direct DB fixes
   only touch the database row, not an already-loaded live session. TFS
   saves the player's live in-memory state back to the DB on logout, so if
   the character was online (or logged back in and died again) before a
   clean save/logout happened, the still-broken in-memory outfit got
   written right back over the fix — repeatedly. Also compounded by
   relogging back into the same dangerous spot where monsters were,
   potentially re-triggering fresh Rebirth cycles that re-captured "560" as
   the "original" outfit each time. Finally resolved by applying the DB fix
   while the character was confirmed fully offline, with no live session
   left to overwrite it.

## Open items for next session

**Resolved since this doc was first written**, kept here for history:
- Holy tiles' plain-carpet placeholder (item 30932) — owner confirmed
  in-game it reads fine as-is ("Rebirth symbols looks good"). No client
  sprite work needed; not revisiting unless that changes.
- `BONUS_BACKLOG.md`'s Rebirth entry — already rewritten to match the
  current step-on-tile/`onPrepareDeath` design, not the old corpse-item/
  `setGhostMode` one.
- The other 14 backlog bonuses — 12 of 15 are now built and deployed
  (Adrenaline Rush, Reflect/Thorn, Prism Heart, Hold the Line, Spell Echo,
  Chain Heal, Juggernaut, Grave Tithe, Cleave, Guardian's Pact, Glass
  Cannon, plus Rebirth itself). Owner explicitly declined the remaining 3
  (Bloodthirst, Hoarder's Blessing, Wanderer's Fortune) — not planned.
- `RarityClass.Overrides` — populated with 172 hand-curated entries (not
  empty). Demonbone Amulet (id 3019) decided as Class 4.

**Still open:**
1. Confirm Harding Rook's outfit fix actually held after their next login
   (last action taken in that session, unconfirmed at time of writing)
2. Restore `COOLDOWN_SECONDS` to 45\*60 once testing wraps up — currently
   still 60 (1 minute), deliberately short for active testing
3. `/rebirthcheck` still doesn't respond — never root-caused, since the
   real mechanic started working correctly before this got chased down
4. Never empirically confirmed whether `ModalWindow` blocks player input
   while open — reasoned it doesn't, based on general TFS/OTClient
   convention (used for non-blocking things like outfit-change
   confirmations), but this hasn't been directly tested/confirmed in this
   client
