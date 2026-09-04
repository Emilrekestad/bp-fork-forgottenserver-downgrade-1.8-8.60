// Copyright 2026 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#ifndef FS_COINS_H
#define FS_COINS_H

#include <cstdint>

// Atomic BP Coin (`accounts`.`tibia_coins`) accounting.
//
// These are the ONLY safe way to move coins for economy-critical systems.
// The Lua-facing player:getTibiaCoins() / player:setTibiaCoins() pair
// (IOLoginData::getTibiaCoins / updateTibiaCoins) performs a read, then an
// absolute `SET` from that stale read -- two concurrent debits on the same
// account silently clobber each other and mint or destroy coins. The store
// gets away with it only because its check and its write sit adjacent on a
// single-threaded Lua path with no yield between them.
//
// The functions below are instead relative and guarded:
//   debit  -> "SET tibia_coins = tibia_coins - n WHERE id = ? AND tibia_coins >= n"
//   credit -> "SET tibia_coins = tibia_coins + n WHERE id = ? AND tibia_coins <= MAX - n"
// and both verify getAffectedRows() == 1, so an insufficient balance or an
// overflow fails loudly instead of corrupting the account. Call them inside
// a DBTransaction when they need to be atomic with other work.
//
// Originally private to the Character Bazaar (character_bazaar.cpp); promoted
// here so the Item Bazaar and any future economy feature share exactly one
// implementation rather than each re-deriving the guarded-UPDATE trick.
namespace Coins {

inline constexpr uint64_t MAX_TIBIA_COINS = 4'294'967'295ULL;

// Current balance, or 0 for an unknown/invalid account.
uint64_t getBalance(uint32_t accountId);

// Removes `amount` only if the account currently holds at least that much.
// Returns false (changing nothing) when it does not.
bool debit(uint32_t accountId, uint64_t amount);

// Adds `amount` unless doing so would exceed MAX_TIBIA_COINS.
bool credit(uint32_t accountId, uint64_t amount);

} // namespace Coins

#endif // FS_COINS_H
