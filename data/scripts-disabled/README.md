# scripts-disabled

Scripts the server must NOT load in production. `Scripts::loadScripts`
(`src/script.cpp`) walks only `data/scripts/`, so nothing under this folder is
discovered, compiled or registered.

Moved here by the pre-test security audit on 2026-10-05
(`docs/security/` report `secrets-gm`):

| Path | Command words | Why it is here |
|---|---|---|
| `talkactions/stress/dupe_test.lua` | `/dupe` | Item-duplication harness from the 2026-09-08 dupe audit: creates items, forces saves, kills sessions. GOD-gated, but a load generator has no place on a server with testers. |
| `talkactions/stress/stress_db.lua` | `/stress_db` | Database load generator (thousands of queries, storage writes). |
| `talkactions/stress/stress_network.lua` | `/net` | Network flood generator. |
| `talkactions/stress/stress_reactor.lua` | `/stress_reactor` | Dispatcher/reactor load generator. |
| `talkactions/god/stress/smart_pointer_stress.lua` | `/spstress`, `/spregisterstress`, `/spconditionstress` | Registers thousands of temporary TalkActions and conditions; in-body GM check only (not logged). |
| `talkactions/god/stress/spawn_stress_demon.lua` | `/spawnstressdemon` | Mass-spawns a test monster and reloads; in-body GM check only. |
| `talkactions/test_creature_icons.lua` | `/testcreatureicon`, `/clearcreatureicon`, `/testrotten`, `/testforge` | Client-icon test harness. |

## Using one locally

Copy (do not move) the file back under `data/scripts/talkactions/` on the
LOCAL tier, then `/reload scripts` as a god character, or restart the local
server. Delete the copy before the change is staged for prod:
`tools/security/secrets-gm/check_talkaction_gates.js` fails while any of
these files is under `data/scripts/`.

Nothing in `data/scripts/` may `dofile` anything from here.
