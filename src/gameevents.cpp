// Copyright 2026 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#include "otpch.h"

#include "gameevents.h"

#include "database.h"
#include "databasetasks.h"

namespace GameEvents {

std::string jsonEscape(std::string_view value)
{
	std::string out;
	out.reserve(value.size() + 8);
	for (const char c : value) {
		switch (c) {
			case '"':
				out += "\\\"";
				break;
			case '\\':
				out += "\\\\";
				break;
			case '\n':
				out += "\\n";
				break;
			case '\r':
				out += "\\r";
				break;
			case '\t':
				out += "\\t";
				break;
			default:
				// Control characters are illegal unescaped in JSON strings.
				if (static_cast<unsigned char>(c) < 0x20) {
					out += fmt::format("\\u{:04x}", static_cast<unsigned char>(c));
				} else {
					out += c;
				}
				break;
		}
	}
	return out;
}

void emit(std::string_view type, std::string_view subjectType, std::string_view subjectId,
          const std::string& payloadJson, uint32_t accountId, uint32_t playerId)
{
	Database& db = Database::getInstance();

	const std::string sqlSubjectType = subjectType.empty() ? "NULL" : db.escapeString(std::string{subjectType});
	const std::string sqlSubjectId = subjectId.empty() ? "NULL" : db.escapeString(std::string{subjectId});
	const std::string sqlPayload = payloadJson.empty() ? "NULL" : db.escapeString(payloadJson);

	g_databaseTasks.addTask(fmt::format(
	    "INSERT INTO `game_events` "
	    "(`ts`, `type`, `version`, `account_id`, `player_id`, `subject_type`, `subject_id`, `payload`) "
	    "VALUES ({:d}, {:s}, 1, {:s}, {:s}, {:s}, {:s}, {:s})",
	    time(nullptr), db.escapeString(std::string{type}), accountId ? std::to_string(accountId) : "NULL",
	    playerId ? std::to_string(playerId) : "NULL", sqlSubjectType, sqlSubjectId, sqlPayload));
}

} // namespace GameEvents
