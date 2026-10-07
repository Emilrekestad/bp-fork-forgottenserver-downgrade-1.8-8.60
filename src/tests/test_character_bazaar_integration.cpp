// Opt-in real-domain integration probe. Only accepts an isolated test schema.
// The runner creates the schema/fixtures; this executable never uses config.lua.
#include "../otpch.h"
#include "../character_bazaar.h"
#include "../configmanager.h"
#include "../database.h"
#include "../game.h"
#include "../iologindata.h"
#include "../player.h"
#include "../tile.h"
#include "../vocation.h"
#include <iostream>
#include <regex>

extern Vocations g_vocations;

int main(int argc, char** argv)
{
	const char* database = std::getenv("BAZAAR_TEST_SCHEMA");
	if (!database) { std::cout << "SKIP: requires BAZAAR_TEST_SCHEMA\n"; return 0; }
	if (!std::regex_match(database, std::regex("bazaar_test_[a-f0-9]{16}")) || argc != 2) return 2;
	try {
		ConfigManager::setString(ConfigManager::MYSQL_HOST, "localhost");
		ConfigManager::setString(ConfigManager::MYSQL_USER, "root");
		ConfigManager::setString(ConfigManager::MYSQL_PASS, "");
		ConfigManager::setString(ConfigManager::MYSQL_DB, database);
		ConfigManager::setInteger(ConfigManager::SQL_PORT, 3306);
		ConfigManager::setBoolean(ConfigManager::CHARACTER_BAZAAR_ENABLED, true);
		ConfigManager::setInteger(ConfigManager::CHARACTER_BAZAAR_MIN_LEVEL, 1);
		ConfigManager::setInteger(ConfigManager::CHARACTER_BAZAAR_MIN_PRICE, 100);
		ConfigManager::setInteger(ConfigManager::CHARACTER_BAZAAR_AUCTION_FEE, 50);
		ConfigManager::setInteger(ConfigManager::CHARACTER_BAZAAR_COMMISSION_PERCENT, 10);
		ConfigManager::setInteger(ConfigManager::CHARACTER_BAZAAR_MIN_DURATION_HOURS, 0);
		ConfigManager::setInteger(ConfigManager::CHARACTER_BAZAAR_MAX_DURATION_DAYS, 7);
		Database& db = Database::getInstance();
		if (!db.connect()) return 3;
		const auto identity = db.storeQuery("SELECT DATABASE() AS db");
		if (!identity || identity->getString("db") != database) return 4;
		const std::string action = argv[1];
		if (action == "settle" || action == "settle-disabled") {
			if (action == "settle-disabled") ConfigManager::setBoolean(ConfigManager::CHARACTER_BAZAAR_ENABLED, false);
			CharacterBazaar::finalizeExpiredAuctions();
			std::cout << "PROBE_SETTLED\n";
			return 0;
		}
		if (action != "create" && action != "create-rejected") return 5;
		if (!Item::items.loadFromOtb("data/items/items.otb") || !g_game.groups.load() || !g_vocations.loadFromXml()) return 6;
		auto player = std::make_shared<Player>(nullptr);
		player->setGUID(10);
		if (!IOLoginData::preloadPlayer(player.get()) || !player->setVocation(1)) return 7;
		auto tile = std::make_shared<StaticTile>(100, 100, 7);
		tile->setFlag(TILESTATE_PROTECTIONZONE);
		player->setParent(tile.get());
		std::string result;
		// Exercise the production level gate before using the low-level fixture.
		ConfigManager::setInteger(ConfigManager::CHARACTER_BAZAAR_MIN_LEVEL, 50);
		if (CharacterBazaar::canCreateAuction(player.get(), result)) return 8;
		ConfigManager::setInteger(ConfigManager::CHARACTER_BAZAAR_MIN_LEVEL, 1);
		if (action == "create-rejected") {
			if (CharacterBazaar::createAuction(player.get(), 100, 60, "Concurrent edit fixture", result)) return 13;
			std::cout << "PROBE_REJECTED\n";
			player->setParent(nullptr);
			return 0;
		}
		if (!CharacterBazaar::createAuction(player.get(), 100, 60, "Isolated integration fixture", result)) {
			std::cerr << result << '\n'; return 9;
		}
		if (CharacterBazaar::createAuction(player.get(), 100, 60, "Duplicate", result)) return 10;
		if (!CharacterBazaar::isPlayerOnActiveAuction(10)) return 11;
		std::cout << "PROBE_CREATED_AND_LOCKED\n";
		player->setParent(nullptr);
		return 0;
	} catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 12; }
}
