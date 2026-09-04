// Copyright 2026 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#include "otpch.h"

#include "coins.h"

#include "database.h"

namespace {

// NULL rather than '' for absent references: the ledger's unique key on
// (ref_type, ref_id, kind) has to stay permissive for in-game movements that
// have no external reference, and SQL treats NULLs as distinct. Writing empty
// strings instead would make a second movement of the same kind collide with
// the first.
std::string sqlNullable(Database& db, const std::string& value)
{
	return value.empty() ? "NULL" : db.escapeString(value);
}

// Records why a balance changed. Called immediately after a successful
// guarded UPDATE, on the same connection, so `balance_after` is read back
// inside whatever transaction the caller holds.
bool writeLedger(Database& db, uint32_t accountId, int64_t delta, const Coins::Movement& movement)
{
	auto balanceResult =
	    db.storeQuery(fmt::format("SELECT `tibia_coins` FROM `accounts` WHERE `id` = {:d}", accountId));
	if (!balanceResult) {
		return false;
	}
	const uint64_t balanceAfter = balanceResult->getNumber<uint64_t>("tibia_coins");

	return db.executeQuery(fmt::format(
	    "INSERT INTO `coin_ledger` "
	    "(`ts`, `account_id`, `player_id`, `delta`, `balance_after`, `kind`, `ref_type`, `ref_id`, `meta`, `source`) "
	    "VALUES ({:d}, {:d}, {:s}, {:d}, {:d}, {:s}, {:s}, {:s}, {:s}, 'cpp')",
	    time(nullptr), accountId, movement.playerId ? std::to_string(movement.playerId) : "NULL", delta, balanceAfter,
	    db.escapeString(movement.kind), sqlNullable(db, movement.refType), sqlNullable(db, movement.refId),
	    sqlNullable(db, movement.metaJson)));
}

} // namespace

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

bool debit(uint32_t accountId, uint64_t amount, const Movement& movement)
{
	if (accountId == 0) {
		return false;
	}
	if (amount == 0) {
		return true;
	}
	Database& db = Database::getInstance();
	if (!db.executeQuery(fmt::format(
	        "UPDATE `accounts` SET `tibia_coins` = `tibia_coins` - {:d} WHERE `id` = {:d} AND `tibia_coins` >= {:d}",
	        amount, accountId, amount)) ||
	    db.getAffectedRows() != 1) {
		return false;
	}
	return writeLedger(db, accountId, -static_cast<int64_t>(amount), movement);
}

bool credit(uint32_t accountId, uint64_t amount, const Movement& movement)
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
	if (!db.executeQuery(fmt::format(
	        "UPDATE `accounts` SET `tibia_coins` = `tibia_coins` + {:d} WHERE `id` = {:d} "
	        "AND `tibia_coins` <= {:d}",
	        amount, accountId, MAX_TIBIA_COINS - amount)) ||
	    db.getAffectedRows() != 1) {
		return false;
	}
	return writeLedger(db, accountId, static_cast<int64_t>(amount), movement);
}

bool move(uint32_t accountId, int64_t delta, const Movement& movement)
{
	if (delta == 0) {
		return true;
	}
	if (delta < 0) {
		return debit(accountId, static_cast<uint64_t>(-delta), movement);
	}
	return credit(accountId, static_cast<uint64_t>(delta), movement);
}

} // namespace Coins
