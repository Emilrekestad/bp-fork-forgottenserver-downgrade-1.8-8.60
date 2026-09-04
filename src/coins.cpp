// Copyright 2026 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#include "otpch.h"

#include "coins.h"

#include "database.h"

namespace Coins {

uint64_t getBalance(uint32_t accountId)
{
	if (accountId == 0) {
		return 0;
	}
	auto result = Database::getInstance().storeQuery(
	    fmt::format("SELECT `tibia_coins` FROM `accounts` WHERE `id` = {:d}", accountId));
	return result ? result->getNumber<uint64_t>("tibia_coins") : 0;
}

bool debit(uint32_t accountId, uint64_t amount)
{
	if (accountId == 0) {
		return false;
	}
	if (amount == 0) {
		return true;
	}
	Database& db = Database::getInstance();
	return db.executeQuery(fmt::format(
	           "UPDATE `accounts` SET `tibia_coins` = `tibia_coins` - {:d} WHERE `id` = {:d} AND `tibia_coins` >= {:d}",
	           amount, accountId, amount)) &&
	       db.getAffectedRows() == 1;
}

bool credit(uint32_t accountId, uint64_t amount)
{
	if (accountId == 0) {
		return false;
	}
	if (amount == 0) {
		return true;
	}
	if (amount > MAX_TIBIA_COINS) {
		return false;
	}
	Database& db = Database::getInstance();
	return db.executeQuery(fmt::format(
	           "UPDATE `accounts` SET `tibia_coins` = `tibia_coins` + {:d} WHERE `id` = {:d} "
	           "AND `tibia_coins` <= {:d}",
	           amount, accountId, MAX_TIBIA_COINS - amount)) &&
	       db.getAffectedRows() == 1;
}

} // namespace Coins
