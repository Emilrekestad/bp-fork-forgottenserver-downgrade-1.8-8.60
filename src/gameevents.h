// Copyright 2026 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#ifndef FS_GAMEEVENTS_H
#define FS_GAMEEVENTS_H

#include <cstdint>
#include <string>
#include <string_view>

// The C++ half of the admin console's event stream.
//
// Most events are emitted from Lua (data/lib/core/console.lua). Two things are
// not visible from there and are emitted here instead:
//
//   raid.start     -- scheduled raids are selected and started in Raids::checkRaids
//   world.message  -- Game::broadcastMessage is called directly from C++ for
//                     raid announcements and never reaches the Lua override
//   gm.command     -- talkaction dispatch is C++; there is no Lua choke point
//
// Rows are identical in shape to the ones Lua writes, so the console cannot
// tell which side produced them and does not need to.
//
// Every write goes through g_databaseTasks, never Database::executeQuery. The
// game thread must not wait on the console's telemetry: a dropped event is a
// gap in a feed, while a blocked dispatcher is a stutter every player feels.
// The coin ledger is the deliberate exception -- it is synchronous because an
// unrecorded coin movement is worse than a slow one.
namespace GameEvents {

// Writes one `game_events` row. `payloadJson` must already be valid JSON (or
// empty for none); nothing here validates it, because the only callers are in
// this repository and each builds its own object.
void emit(std::string_view type, std::string_view subjectType, std::string_view subjectId,
          const std::string& payloadJson, uint32_t accountId = 0, uint32_t playerId = 0);

// Escapes a value for inclusion in a JSON string literal. Broadcast text and
// raid names come from map data and configuration rather than from players,
// but they routinely contain quotes and apostrophes, and an unescaped quote
// would produce a payload the console silently fails to parse.
std::string jsonEscape(std::string_view value);

} // namespace GameEvents

#endif
