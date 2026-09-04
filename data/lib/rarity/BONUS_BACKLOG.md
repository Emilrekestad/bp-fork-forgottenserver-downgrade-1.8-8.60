# Rarity System — Bonus Backlog

Reference-only. Nothing in this file is loaded by the server (it is **not**
`dofile`'d from `rarity.lua`/`core.lua`). Originally written to keep the 15
bonus ideas below from getting lost between sessions, before any of them
were built. **Status as of the most recent pass: 12 of 15 implemented and
deployed** (Grave Tithe, Adrenaline Rush, Reflect/Thorn, Cleave, Glass
Cannon, Guardian's Pact, Prism Heart, Hold the Line, Juggernaut, Spell
Echo, Chain Heal, plus Rebirth — see entry #14), each hand-distributed to
specific equipment slots/vocations by the owner, the same curation pattern
already used for `RarityClass.Overrides` in `rarity_class.lua`. The
remaining 3 (Bloodthirst, Hoarder's Blessing, Wanderer's Fortune) were
explicitly declined — not planned.

Two names were reworked for brevity per the owner's request:
- Grave Robber's Fortune → **Grave Tithe**
- Vampiric Strike → **Bloodthirst**

**Update (unattended follow-up pass):** verified several of the "needs
checking" hooks below directly against the C++ source and existing scripts
rather than leaving them as open questions. Findings are noted inline
against each affected bonus and in Shared Infrastructure. Nothing was
implemented — this pass only confirmed feasibility and exact hook points.

## The 15 bonuses

1. **Grave Tithe** — **IMPLEMENTED AND DEPLOYED.** Helmets, rings,
   necklaces, Class 4+, all vocations. +% experience from kills while
   worn. **Confirmed cheap.** `data/scripts/eventcallbacks/player/default_onGainExperience.lua`
   already has a live `Event().onGainExperience(player, source, exp, rawExp,
   sendText)` handler that returns the modified `exp`, with an existing
   chain of rate multipliers (Stamina/Base/LowLevel/Bonus/Prey/Influenced) to
   drop a new multiplier into. That same file already registers a *second*
   independent `onGainExperience` handler further down (`message:register
   (math.huge)`, for the kill-XP toast) — proving this event supports
   multiple registered handlers side by side. Grave Tithe can be its own new
   `Event():register()` block reading the killer's equipped bonus, without
   touching the existing file at all.

2. **Adrenaline Rush** — **IMPLEMENTED AND DEPLOYED.** Boots, Class 3+, all
   vocations. Temporary speed/attack buff for a few seconds after a kill.
   **Confirmed — no new hook needed.** This rarity system's own
   `rarity_loot_drop.lua` already listens to `Monster:onDropLoot(monster,
   corpse)` on every kill server-wide. `corpse:getCorpseOwner()` returns the
   killer's player id — the exact same pattern `hunt_analyzer/
   huntanalyzer.lua:93` and `party_analyzer/partytracker.lua:135` already
   use off this identical event to attribute a kill to a player. Adrenaline
   Rush can piggyback on the loot-drop hook this system already runs, not a
   new event.

3. **Reflect** — **IMPLEMENTED AND DEPLOYED, renamed Thorn.** Legs
   (Knight/Paladin-locked), shields (non-spellbook). % of incoming damage
   bounced back at the attacker. Mirrors
   the resistance-checking loop already in `statChange`
   (`data/scripts/creaturescripts/rarity/rarity_combat.lua`), just calls
   `doTargetCombatHealth` back at the attacker instead of only reducing the
   wearer's damage taken.

4. **Cleave** — **IMPLEMENTED AND DEPLOYED.** Two-handed Knight weapons
   (Sword/Club/Axe), Class 2+. Melee attacks get a scaled-down chance to
   also hit a second nearby target. Reuses the Multi Shot spectator/shuffle
   code, re-triggered from a melee branch instead of gated behind ranged
   ammo/`CONST_SLOT_AMMO`.

5. **Bloodthirst** — **DECLINED, not building.** Heal a % of damage dealt,
   but only on a Crit. Would gate the existing Life Leech call behind the
   crit-roll branch instead of firing unconditionally.

6. **Glass Cannon** — **IMPLEMENTED AND DEPLOYED.** Mage (Sorcerer/Druid)
   body armor, Class 4+. +% damage dealt AND +% damage taken while
   equipped. The incoming-damage boost is deliberately the LAST modifier
   applied in `statChange`'s defender chain (after Hold the Line/Dodge
   Chance/Juggernaut/Guardian's Pact), per owner's explicit call, so it's
   genuine risk/reward and can't be quietly absorbed by other rolled
   reductions first.

7. **Guardian's Pact** — **IMPLEMENTED AND DEPLOYED.** Mage
   (Sorcerer/Druid) and Paladin-locked helmets, Class 4+. When hit, a %
   chance to redirect some of that damage into a heal for the
   most-injured nearby party member. Uses `Participants()`
   (`data/lib/core/party.lua`) plus redirect logic in `statChange`'s
   defender block.

8. **Hoarder's Blessing** — **DECLINED, not building.** % chance a
   charge-based item (wand/rod/rune) doesn't consume a charge on use. Partially de-risked: `data/lib/compat/
   compat.lua` confirms this fork's `Weapon` objects support a native
   `onUseWeapon` callback (`weapon:onUseWeapon(value)`), with working
   examples already in the codebase (`data/scripts/weapons/viper_star.lua`,
   `poison_arrow.lua`, `burst_arrow.lua`) — so wands/rods (both `WEAPON_WAND`
   in this fork) have a real, proven hook to intercept charge use on. Runes
   are a different item class (used via `Action`, not `Weapon`) and weren't
   checked this pass — worth a quick look at how rune charge-decrement is
   currently scripted before assuming the same pattern covers them too.

9. **Wanderer's Fortune** — **DECLINED, not building.** Increases the chance for *other* drops to roll
   rare/epic/legendary while worn (the self-reinforcing "rarity that boosts
   rarity" stat). `rarity_loot_drop.lua` already calls
   `RarityStats.rollRarity` on kill — read the killer's own equipped
   Wanderer's Fortune bonus before that call and nudge the tier
   `rollThreshold` values for that roll.

10. **Prism Heart** — **IMPLEMENTED AND DEPLOYED.** Unique Paladin quiver
    bonus, Class 4+. A portion of physical damage converts into a random
    element every swing. Reuses `elementalDmg()` exactly as it exists
    today, just randomizes which `elementType` fires each hit instead of
    reading one fixed type from a specific bracket.

11. **Hold the Line** — **IMPLEMENTED AND DEPLOYED.** Knight body armor,
    Class 4+. Defense increases the longer you stand on the same tile. Used
    a new per-player position+timestamp tracker (`holdTheLineState` in
    `rarity_combat.lua`) — no state like this existed anywhere in the
    rarity system before this.

12. **Juggernaut** — **IMPLEMENTED AND DEPLOYED.** Body armor,
    Knight/Paladin-locked, Class 4+. Gain resistance scaled to how many
    creatures are currently attacking you. Plugs into the existing
    resistance loop in `statChange`. **Confirmed — no proxy needed.** `Creature:getTarget()` /
    `:setTarget()` are real, registered Lua bindings (`src/luacreature.cpp:
    1475-1476`), inherited by `Monster`. The precise implementation is: grab
    spectators (monsters) around the player, count how many have
    `monster:getTarget()` equal to the player. Exact, not approximate — the
    "count nearby hostile monsters" fallback from the original write-up is
    no longer needed.

13. **Spell Echo** — **IMPLEMENTED AND DEPLOYED.** Unique Sorcerer wand
    bonus, Class 4+. Offensive spells have a chance to repeat at reduced
    power. Ended up not needing a new "about to resolve" hook after all —
    built directly off the existing post-cast health-change event in
    `statChange`'s `ORIGIN_SPELL` branch instead.

14. **Rebirth (Revive)** — **IMPLEMENTED AND DEPLOYED**, no longer just a
    backlog spec. Originally a 5-item hand-picked whitelist (Rod of
    Destruction, Lion Rod, Falcon Rod, Sanguine Rod, Grand Sanguine Rod);
    RESTRUCTURED to a structural rule matching Hold the Line/Chain Heal —
    `minClass = 5` plus the same WEAPON_WAND-and-name-contains-"rod" check
    used for Chain Heal, so it now rolls on any Class 5+ Druid rod, not just
    the 5 that existed when this was first built. Legendary-tier only, plus
    an independent ~2.5% secondary roll gate on top of normal tier odds —
    deliberately the rarest roll in the whole system (see `stats[36]` in
    `rarity_stats.lua`). The in-game trigger (`RarityRebirth.hasRebirthRod`)
    was already item-agnostic — it reads the equipped item's rolled
    `[Rebirth]` description tag, not an item id — so this was a pure
    roll-eligibility change, nothing in the revive mechanic itself needed
    touching.

    Final mechanic (evolved during design from the original talkaction idea
    to a step-on-holy-tile trigger, after review against a reference image):
    a lethal hit on a party member is vetoed via the native
    `CREATURE_EVENT_PREPAREDEATH` hook (confirmed real:
    `src/creatureevent.h:21`, fired `src/game.cpp:6993-6998` before
    `drainHealth()` applies — returning `false` cancels the killing blow
    outright, no C++ patch needed). The downed player is pinned at 1 HP,
    movement-blocked, fully damage-immune (`rarity_combat.lua`'s
    `rarityHealthChange`), and a synthetic corpse + ring of 8 holy tiles
    spawns around them. Any qualifying Druid (party member, has a
    Rebirth-rolled rod equipped, off cooldown) stepping onto a tile
    instantly revives the downed player at 20% HP — no channel, the risk is
    purely positional (walking into the death spot mid-fight). The downed
    player can also type `!accept` to skip waiting and let the deferred
    death resolve immediately. If nobody reaches them within 60 seconds,
    the same real-death resolution fires automatically. Cooldown: 45
    minutes per Druid, tracked via `player:kv():scoped("rarity")`.

    Files: `data/lib/rarity/rarity_rebirth.lua` (shared state/helpers — has
    to live in `data/lib`, not `data/scripts`, so it's guaranteed loaded
    before the CreatureEvent/MoveEvent files that reference it at their own
    top-level registration time), `data/scripts/creaturescripts/rarity/
    rarity_rebirth.lua` (the `onPrepareDeath` veto),
    `data/scripts/movements/rarity/rarity_rebirth_tile.lua` (the holy-tile
    `MoveEvent`), `data/scripts/talkactions/player/rarity/accept.lua`.

    Known open item: no existing ground-tile item in this datapack visually
    matches the holy-symbol-ring reference image — the deployed version
    reuses a plain carpet item (id 30932) functionally, paired with a
    `CONST_ME_HOLYAREA` effect burst. A pixel-accurate match would need new
    client sprite work, a different kind of task than anything else done
    this session.

    Not yet live-tested with two real players (needs an actual Druid +
    dying party member in-game to verify the full revive/accept/timeout
    flow) — everything server-side is deployed and boots clean with zero
    errors, but the gameplay loop itself hasn't been played through yet.

15. **Chain Heal** — **IMPLEMENTED AND DEPLOYED.** Rods only (not wands),
    Class 3+. Healing can jump to another injured party member.
    `statChange` already special-cases `COMBAT_HEALING` in its leech-gating
    logic, so the "a heal just landed" detection point already exists — add
    a branch there that checks `getParty():getMembers()` for a hurt member
    nearby and applies a reduced heal to them too.

## Shared infrastructure (build once, several bonuses ride on it)

Genuinely new pieces (nothing pre-existing to reuse), smallest list first:

- **Position/time-on-tile tracker** (new) — Hold the Line. Only bonus on
  this list with no existing analog anywhere in the codebase.
- **Spell-about-to-resolve hook** (new) — Spell Echo. This rarity system has
  never touched spell-cast timing, only post-cast health/mana-change.
- **Player-facing accept/decline interaction** (new) — the one still-open
  piece of Rebirth. No existing pattern in this codebase for this specific
  shape of player prompt.

Everything else below turned out to already exist natively or elsewhere in
this codebase — confirmed by reading the C++ source and sibling scripts
directly, not assumed:

- **Deferred-death veto** (native, unused by this system) —
  `CREATURE_EVENT_PREPAREDEATH` / `onPrepareDeath(creature, killer)`,
  `src/game.cpp:6993-6998`. Fires before a lethal hit applies; returning
  `false` cancels the killing blow outright. Needed by Rebirth.
- **On-kill attribution** (native, already in active use by two other
  systems) — `corpse:getCorpseOwner()` off the same `Monster:onDropLoot`
  event `rarity_loot_drop.lua` already hooks. Needed by Adrenaline Rush,
  and by Grave Tithe if it doesn't just extend
  `default_onGainExperience.lua` directly instead.
- **XP-modifier hook** (native, already live) —
  `data/scripts/eventcallbacks/player/default_onGainExperience.lua`,
  supports multiple stacked handlers already. Needed by Grave Tithe.
- **Precise "who is attacking me" check** (native) — `Creature:getTarget()`
  (`src/luacreature.cpp:1475`). Needed by Juggernaut.
- **Charge-use interception** (native, proven via `viper_star.lua` /
  `poison_arrow.lua` / `burst_arrow.lua`) — `Weapon:onUseWeapon`. Covers
  wands/rods for Hoarder's Blessing; runes still unverified.
- **Native Party API** (available, just unused by this system so far) —
  Guardian's Pact, Rebirth, Chain Heal.
- **Existing `statChange` resistance loop** — Reflect, Juggernaut.
- **Existing crit-roll branch** (`rarity_combat.lua:483-493`) — Bloodthirst.
- **Existing `elementalDmg()`** — Prism Heart.
- **Existing `rarity_loot_drop.lua` → `RarityStats.rollRarity` call** —
  Wanderer's Fortune.
- **Existing `COMBAT_HEALING` detection in `statChange`** — Chain Heal.

Net effect of this pass: of the 5 items originally flagged as needing new
infrastructure, only 2 (the position tracker and the spell-cast hook)
actually do. Everything else already has a real, working hook somewhere in
this codebase.
