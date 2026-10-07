// Copyright 2026 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#ifndef FS_CHARACTER_BAZAAR_H
#define FS_CHARACTER_BAZAAR_H

#include <cstdint>
#include <string>

class Player;

// The Character Bazaar: sell a whole character for BP Coins in an ascending
// auction. The seller lists in-game, the character is locked out of the game
// while the auction runs, bidders compete from the website or the client, and
// the game server settles: ownership moves to the winner's account and the
// seller is paid the winning bid minus commission.
//
// THIS NAMESPACE IS THE ONLY AUTHORITY, exactly as ItemBazaar is for items.
// Three front doors reach it and none of them may re-implement a rule:
//   * the client, through data/scripts/network/character_bazaar/ (Lua owns the
//     wire format and calls the Game.characterBazaar* bindings in luagame.cpp);
//   * the website, by enqueuing `char_bid` / `char_cancel` rows in
//     `bazaar_commands`, drained by ItemBazaar::processCommands();
//   * the scheduler, through finalizeExpiredAuctions().
// Until 2026-09-08 bidding lived twice (here and in www/system/pages/bazaar.php)
// and the two copies had already started to disagree; that is why the PHP
// transaction was deleted rather than kept in step.
//
// Conventions, shared with item_bazaar.cpp:
//   * every mutation runs inside DBTransaction::executeWithinTransactionRollbackOnFailure,
//     which retries on deadlock, so each callback re-reads its row FOR UPDATE and
//     re-checks state at the top;
//   * coins move only through Coins::debit / Coins::credit, which write the
//     coin_ledger rows the admin console reconciles against. The commission is
//     deliberately NOT a movement of its own -- it is the difference between the
//     winner's escrow and the seller's payout, and a third row would double-count
//     the burn.
namespace CharacterBazaar {

// The client opcode reserved for this system. The C++ protocol no longer
// parses it (the Lua PacketHandler does), but the number stays claimed here so
// nobody hands it to something else -- see the opcode notes in item_bazaar.h.
inline constexpr uint8_t CLIENT_PACKET = 0x5E;
inline constexpr uint8_t SERVER_PACKET = 0x2E;

// character_auctions.status. 3 and 4 both mean "ended, character stays with the
// seller" -- the difference is who ended it, and the history row says why.
inline constexpr uint8_t AUCTION_STATUS_ACTIVE = 1;
inline constexpr uint8_t AUCTION_STATUS_FINISHED = 2;
inline constexpr uint8_t AUCTION_STATUS_EXPIRED_NO_BIDS = 3;
inline constexpr uint8_t AUCTION_STATUS_WITHDRAWN = 4;

inline constexpr uint32_t MAX_DESCRIPTION_LENGTH = 512;
inline constexpr uint64_t MAX_TIBIA_COINS = 4'294'967'295ULL;

// Everything a front end needs to draw the Sell form, computed for one player.
// `eligible` is canCreateAuction()'s verdict and `reason` its wording.
struct Rules
{
	bool enabled = false;
	bool eligible = false;
	std::string reason;
	uint32_t minLevel = 0;
	uint32_t minPrice = 0;
	uint32_t minDurationSeconds = 0;
	uint32_t maxDurationSeconds = 0;
	uint32_t fee = 0;
	uint8_t commissionPercent = 0;
	uint32_t antiSnipeSeconds = 0;
	uint64_t balance = 0;
};

bool isEnabled();
Rules getRules(Player* player);

bool isPlayerOnActiveAuction(uint32_t playerId);
bool canCreateAuction(Player* player, std::string& reason);
// `buyoutPrice` is optional: 0 means the listing has no Buy Now. When set it
// must be strictly above `startPrice` -- equal is rejected on purpose, because
// a listing whose buyout equals its start price is a fixed-price sale and this
// system is an auction.
//
// `outAuctionId` receives the new auction's id so the caller can attach the
// Bao Ledger snapshot. That is done in Lua because Bao's code owns the Ledger's
// key layout (data/lib/bao/bao_ledger.lua), not because C++ could not read it:
// KVStore::getInstance().scoped("player")->scoped(guid) reaches any character's
// kv, online or not. See data/migrations/92.lua for why a snapshot exists at all.
bool createAuction(Player* player, uint32_t startPrice, uint32_t buyoutPrice, uint32_t durationSeconds,
                   const std::string& description, std::string& reason, uint32_t& outAuctionId);

// The next bid an auction accepts: the start price until someone bids, then
// one coin over the standing bid. Mirrored for DISPLAY ONLY by the Lua network
// layer and the website; the check that matters is the one in placeBid.
uint32_t getMinimumNextBid(uint32_t startPrice, uint32_t currentBid);

// `operationId` names the attempt ("web:<command id>", "client:<...>") and is
// carried in the ledger metadata so a movement can be traced back to its cause.
// Refunds the displaced bidder, escrows the new bid, and -- when the bid lands
// inside the final anti-snipe window -- resets the clock to that window.
bool placeBid(uint32_t accountId, uint32_t auctionId, uint32_t amount, const std::string& operationId,
              std::string& reason);

// Buy Now: end the auction immediately at `buyout_price` and hand the
// character over. Mirrors ItemBazaar::buyout, by decision, including the part
// that matters most -- it stays available AFTER bidding has started, refunding
// the standing bidder before escrowing the buyer's coins. That is safe only
// because placeBid refuses any bid that reaches the buyout, so the buyout is a
// ceiling and a buyout can never settle below the standing bid.
//
// The character moves in the same transaction, so the sale is instant: a
// listed character is locked out of the game (protocolgame.cpp), which means
// no Player object exists to overwrite `account_id` at a later save, and
// IOLoginData::loadAccount re-reads the character list from the database with
// no cache in front of it.
bool buyNow(uint32_t accountId, uint32_t auctionId, const std::string& operationId, std::string& reason);

// A seller may take an unbid listing down. The fee is not returned: it paid
// for the listing, not the sale. An auction with a bid cannot be withdrawn.
bool cancelAuction(uint32_t accountId, uint32_t auctionId, std::string& reason);

void finalizeExpiredAuctions();
void scheduleFinalization();

bool addHistory(uint32_t auctionId, const std::string& action, uint32_t accountId, uint32_t playerId,
                uint64_t amount, const std::string& message);
uint64_t getTransferableCoins(uint32_t accountId);
// `kind` is a coin_ledger kind from data/lib/core/coins.lua. `auctionId` may be
// 0 when no auction reference is available. Listing fees are charged after
// INSERT inside the same transaction, so failed listings cannot take coins.
bool debitTransferableCoins(uint32_t accountId, uint64_t amount, std::string kind, uint32_t auctionId = 0);
bool creditTransferableCoins(uint32_t accountId, uint64_t amount, std::string kind, uint32_t auctionId = 0);

} // namespace CharacterBazaar

#endif // FS_CHARACTER_BAZAAR_H
