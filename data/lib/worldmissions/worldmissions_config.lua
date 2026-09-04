-- World Missions — Bender Shun's server-wide progression system. Mission
-- CONTENT lives here, hand-authored, same split as Bao's own
-- bao_config.lua (static data) vs bao_state.lua (read/write layer).
--
-- Storage keys: Game.getStorageValue/setStorageValue take plain numeric
-- keys (confirmed real, same binding data/npc/crystalserver/quests/
-- appaloosa.lua and data/scripts/actions/workbench_open.lua already use
-- for exactly this kind of server-wide flag -- see also
-- GlobalStorageKeys in data/lib/core/storages.lua for this codebase's
-- existing hand-assigned-number convention, which this follows). No
-- auto-hashing, so there's no risk of two missions silently colliding on
-- the same storage cell. Reserved range for this system: 96000-96999
-- (confirmed unused elsewhere in this codebase). Allocated so far:
--   96000-96009  liberty_bay (progress + spare)
--   96010-96019  liberty_bay appliedStorage (96010) + per-lever activated
--                flags (96011-96014, appliedStorage+objectIndex)
--   96020-96029  oramond (progress 96020, applied 96021)
--   96030-96039  roshamuul (applied 96030) + per-item progress
--                (96031-96035)
--
-- Zone: this codebase already has its own Lua Zone implementation
-- (data/lib/functions/boss_lever.lua, proven in production for boss
-- encounters) that overrides the native Zone global -- Zone("some.name")
-- returns/creates a rectangular-region object with :addArea(from, to),
-- :getPlayers(), :getMonsters(), :countPlayers(). World Missions reuses
-- that exact object, not the raw native Zone class, for Cull/Presence
-- region checks (when a Cull mission specifies one -- see Oramond below
-- for a Cull mission that deliberately doesn't).
--
-- Mission shape, by type:
--   cull       -- { type="cull", zone=<Zone name, OPTIONAL>,
--                   monsters={<names>, OPTIONAL}, threshold=<kills>,
--                   progressStorage, appliedStorage, prerequisite
--                   (OPTIONAL), onComplete, completeMessage }
--                   Omitting `zone` counts kills anywhere; omitting
--                   `monsters` counts every creature. Both omitted (as
--                   with Oramond) = every kill in the world counts.
--   delivery   -- { type="delivery", items={{itemId=<id>, name=<label>,
--                   threshold=<count>, progressStorage=<key>}, ...},
--                   appliedStorage, prerequisite (OPTIONAL), onComplete,
--                   completeMessage, statusMessage (OPTIONAL -- overrides
--                   the generic numeric readout when Shun is asked about
--                   it, for missions where he has an in-character
--                   reaction instead of a plain tally) }
--   presence   -- { type="presence", zone=<Zone name>,
--                   threshold=<simultaneous players>, progressStorage,
--                   appliedStorage, prerequisite (OPTIONAL), onComplete,
--                   completeMessage }
--   activation -- { type="activation", objects={{pos=Position(...),
--                   itemOff=<id>, itemOn=<id>, label=<OPTIONAL>}, ...},
--                   threshold=<#objects, usually #objects itself>,
--                   progressStorage, appliedStorage, prerequisite
--                   (OPTIONAL), onComplete, completeMessage }
--                   itemOff/itemOn are the two real item ids for the
--                   object's two visual states (e.g. a lever pointing
--                   left vs right) -- both required, transformed between
--                   via Item:transform(), a real confirmed binding.
--   composite  -- { type="composite", requiredMissions={<mission ids>},
--                   appliedStorage, prerequisite (OPTIONAL), onComplete,
--                   completeMessage } (no threshold/progressStorage --
--                   see WorldMissions.isThresholdMet)
--
-- prerequisite: succession. A mission with one doesn't exist to players
-- (isRevealed() is false) and can't accumulate progress until that other
-- mission is applied -- "Oramond starts when Liberty Bay is unlocked,"
-- per the owner's spec. Every contribution hook (Cull's kill listener,
-- Delivery's deliverItem, Activation's activateObject, the Presence
-- poller) and Bender Shun's dialogue both check WorldMissions.isRevealed
-- before doing anything.
--
-- onComplete(): the actual permanent change (Tile:addItem/remove, opening
-- a gate, whatever the mission calls for). Written to be idempotent and
-- safe to call more than once -- it runs once the instant the mission's
-- threshold is met (completion is immediate, not deferred to a scheduled
-- save -- see worldmissions_state.lua's applyPendingCompletions for why),
-- and again at every subsequent boot to re-paint the live map, since a
-- runtime tile edit doesn't survive a restart on its own (no
-- Game.saveMap() binding exists in this fork). All three missions below
-- turned out not to need this at all -- each one's real payoff is a live
-- WorldMissions.isApplied(...) check in Captain Bluebear.lua's Thais
-- travel keywords, not a map edit -- so onComplete is currently an empty,
-- deliberate no-op on each.
WorldMissions = WorldMissions or {}
WorldMissions.Missions = WorldMissions.Missions or {}

-- ─── 1. Unlock Liberty Bay (Easy) ───────────────────────────────────────
-- Activation: 4 levers, mainland + Edron (reached by boat). Lever pair
-- 9110 (pointing left/unpulled) -> 9111 (pointing right/pulled), owner's
-- own pick, confirmed as a real existing pair in this fork's items.xml.
-- Permanently stuck once pulled (activateObject only ever succeeds once
-- per object, see worldmissions_state.lua).
WorldMissions.Missions["liberty_bay"] = {
	name = "Unlock Liberty Bay",
	difficulty = "Easy",
	type = "activation",
	threshold = 4,
	progressStorage = 96000,
	appliedStorage = 96010,
	objects = {
		{pos = Position(32758, 32144, 7), itemOff = 9110, itemOn = 9111, label = "Venore"},
		{pos = Position(32426, 32361, 7), itemOff = 9110, itemOn = 9111, label = "Thais"},
		{pos = Position(32677, 31707, 7), itemOff = 9110, itemOn = 9111, label = "Ab'Dendriel"},
		{pos = Position(33286, 31823, 7), itemOff = 9110, itemOn = 9111, label = "Edron"},
	},
	completeMessage = "Something shifted, someone should probably check in with Bender Shun..",
	-- Same shape as Oramond/Roshamuul below -- the actual payoff is a live
	-- WorldMissions.isApplied("liberty_bay") check in Captain Bluebear.lua's
	-- travel keyword (Thais boat), not a tile edit here. Before it's
	-- applied he still quotes the price and only backs out at the "yes"
	-- confirmation with an in-character safety excuse, per owner's spec.
	onComplete = function() end,
}

-- ─── 2. Oramond (Easy) ──────────────────────────────────────────────────
-- Cull, deliberately global: no `zone`, no `monsters` -- every kill
-- anywhere in the world counts, gatekeeping spawns by total server-wide
-- kill volume rather than a specific creature or region. Starts (progress
-- begins accumulating) only once Liberty Bay is applied.
WorldMissions.Missions["oramond"] = {
	name = "Oramond",
	difficulty = "Easy",
	type = "cull",
	prerequisite = "liberty_bay",
	threshold = 500000,
	progressStorage = 96020,
	appliedStorage = 96021,
	completeMessage = "Bender Shun feeds the last of your offerings into the great machinery. Gears scream, furnaces roar, and somewhere beneath the earth... an ancient industry awakens.",
	-- No tile edit needed for this mission's actual payoff -- per owner's
	-- spec, completing it just unlocks Oramond as a boat destination from
	-- Thais. That's handled as a live WorldMissions.isApplied("oramond")
	-- check in data/npc/scripts/Captain Bluebear.lua's travel keyword,
	-- not here -- it needs no separate "apply at boot" step the way a
	-- Tile:addItem/remove edit would, since isApplied() is itself already
	-- durably persisted the instant it flips true (see
	-- worldmissions_state.lua's applyPendingCompletions).
	onComplete = function() end,
}

-- ─── 3. Roshamuul ───────────────────────────────────────────────────────
-- Delivery, multi-item. Real item ids confirmed against this fork's
-- items.xml: iron ore 5880, demonic essence 6499, rope belt 11492,
-- silencer claws 20200, gold coin 3031. Runs in PARALLEL with Oramond, not
-- after it -- both share liberty_bay as their only prerequisite, per
-- owner's explicit "Roshamuul and Oramond can be available at the same
-- time."
WorldMissions.Missions["roshamuul"] = {
	name = "Roshamuul",
	type = "delivery",
	prerequisite = "liberty_bay",
	items = {
		{itemId = 5880, name = "iron ore", threshold = 10000, progressStorage = 96031},
		{itemId = 6499, name = "demonic essence", threshold = 4000, progressStorage = 96032},
		{itemId = 11492, name = "rope belt", threshold = 3000, progressStorage = 96033},
		{itemId = 20200, name = "silencer claws", threshold = 1000, progressStorage = 96034},
		{itemId = 3031, name = "gold coins", threshold = 2000000, progressStorage = 96035},
	},
	appliedStorage = 96030,
	statusMessage = "HAH, WORK FOR ME MINIONS! I don't need your pity supplies. Stones move, because I tell them to. Demons and Rocks bow to my pointing.",
	completeMessage = "The ground trembles beneath every living thing. Bender Shun has called upon the stone — and something far worse has answered with it.",
	-- Same as Oramond -- the payoff is a live isApplied("roshamuul") check
	-- in Captain Bluebear.lua's travel keyword, not a tile edit here.
	onComplete = function() end,
}
