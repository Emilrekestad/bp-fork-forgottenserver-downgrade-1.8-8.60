// Copyright 2026 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#ifndef FS_COINS_H
#define FS_COINS_H

#include <cstdint>
#include <string>

// Atomic BP Coin (`accounts`.`tibia_coins`) accounting.
//
// These are the ONLY safe way to move coins for economy-critical systems.
// The Lua-facing player:getTibiaCoins() / player:setTibiaCoins() pair
// (IOLoginData::getTibiaCoins / updateTibiaCoins) performs a read, then an
// absolute `SET` from that stale read -- two concurrent debits on the same
// account silently clobber each other and mint or destroy coins.
//
// The functions below are instead relative and guarded:
//   debit  -> "SET tibia_coins = tibia_coins - n WHERE id = ? AND tibia_coins >= n"
//   credit -> "SET tibia_coins = tibia_coins + n WHERE id = ? AND tibia_coins <= MAX - n"
// and both verify getAffectedRows() == 1, so an insufficient balance or an
// overflow fails loudly instead of corrupting the account.
//
// Every movement also writes one `coin_ledger` row saying why it happened.
// That ledger is what the admin console charts and what the nightly
// reconciliation job checks against the sum of balances, so a movement
// without one is a hole in the economy's accounting. Callers therefore have
// to supply a Movement; there is no unlabelled overload.
//
// Transactions: the ledger insert runs on the same connection immediately
// after the guarded UPDATE. When the caller already holds a DBTransaction
// (both bazaars do), the pair is atomic with the surrounding work. When it
// does not, the two statements are not wrapped -- a crash between them would
// leave a movement without a ledger row, which reconciliation reports as
// drift rather than hiding. Prefer calling inside a DBTransaction.
//
// Lua's equivalent is Coins.move in data/lib/core/coins.lua; the two write
// identical rows apart from the `source` column ('cpp' vs 'lua').
namespace Coins {

inline constexpr uint64_t MAX_TIBIA_COINS = 4'294'967'295ULL;

// Why coins moved. `kind` must be one of the kinds listed in
// data/lib/core/coins.lua (Coins.KINDS) and documented in
// docs/admin-console/01-data-model.md -- the console's dictionary is
// generated from that list, so an unknown kind becomes a movement no chart
// breaks down.
struct Movement
{
	std::string kind;
	std::string refType;      // e.g. "bazaar_auction"; empty for none
	std::string refId;        // id within refType; empty for none
	std::string metaJson;     // JSON object, or empty for none
	uint32_t playerId = 0;    // the character in play, when there is one
};

// Current balance, or 0 for an unknown/invalid account.
uint64_t getBalance(uint32_t accountId);

// Removes `amount` only if the account currently holds at least that much.
// Returns false (changing nothing) when it does not.
bool debit(uint32_t accountId, uint64_t amount, const Movement& movement);

// Adds `amount` unless doing so would exceed MAX_TIBIA_COINS.
bool credit(uint32_t accountId, uint64_t amount, const Movement& movement);

// Signed form; `delta` of 0 succeeds and writes nothing.
bool move(uint32_t accountId, int64_t delta, const Movement& movement);

} // namespace Coins

#endif // FS_COINS_H
