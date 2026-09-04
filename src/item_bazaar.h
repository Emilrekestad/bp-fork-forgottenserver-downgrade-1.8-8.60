// Copyright 2026 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#ifndef FS_ITEM_BAZAAR_H
#define FS_ITEM_BAZAAR_H

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

class Player;
class Item;

// The Item Bazaar: an account-wide, anonymous auction house for rarity
// equipment, priced in BP Coins, with optional Buyout and one-minute
// anti-sniping.
//
// THIS NAMESPACE IS THE ONLY AUTHORITY. The game client reaches it through
// ProtocolGame::parseItemBazaar; backpackot.com reaches it by enqueuing rows
// in `bazaar_commands` which processCommands() drains. Neither interface may
// re-implement any rule below -- that duplication is exactly the flaw the
// Character Bazaar has today (bidding lives twice: character_bazaar.cpp and
// www/system/pages/bazaar.php).
//
// Correctness conventions, all inherited from character_bazaar.cpp / market.cpp:
//
//  * Every mutation runs inside DBTransaction::executeWithinTransactionRollbackOnFailure.
//    That wrapper RETRIES UP TO 3x on deadlock, so every callback must be
//    idempotent: each one re-reads its row with SELECT ... FOR UPDATE and
//    re-checks state at the top, so a replay is a no-op rather than a
//    double-charge. (CharacterBazaar::createAuction gets this wrong; do not
//    copy that part.)
//  * Coins move only via the Coins:: helpers (guarded, relative UPDATEs),
//    never player:setTibiaCoins().
//  * Items are escrowed as exact instances: the engine's own per-item
//    snowflake (Item::getItemUID) plus the full serializeAttr() blob. The
//    UNIQUE index on bazaar_items.item_uid is the structural guarantee that
//    one instance cannot be escrowed twice.
namespace ItemBazaar {

// Opcodes, picked from the documented custom range (OTClientV8 64-79, see
// otclient-src/src/client/protocolcodes.h) and verified free in BOTH
// directions. Do not change these casually:
//   * 0x2A (42) looked free but is GameServerSpecialContainer client-side, and
//     the client tries Lua opcode handlers BEFORE its native switch
//     (protocolgameparse.cpp), so claiming it would silently break special
//     containers.
//   * 0x4C/0x4D belong to game_bao, 0x5E to the Character Bazaar.
inline constexpr uint8_t CLIENT_PACKET = 0x4E; // client -> server
inline constexpr uint8_t SERVER_PACKET = 0x4F; // server -> client

// bazaar_items.state
inline constexpr uint8_t ITEM_STATE_PENDING_ESCROW = 0;
inline constexpr uint8_t ITEM_STATE_INVENTORY = 1;
inline constexpr uint8_t ITEM_STATE_ESCROWED = 2;

// bazaar_auctions.status
inline constexpr uint8_t AUCTION_ACTIVE = 1;
inline constexpr uint8_t AUCTION_SETTLING = 2;
inline constexpr uint8_t AUCTION_SETTLED = 3;
inline constexpr uint8_t AUCTION_EXPIRED = 4;
inline constexpr uint8_t AUCTION_CANCELLED = 5;

// bazaar_auctions.settlement_reason
inline constexpr uint8_t SETTLED_BY_AUCTION = 1;
inline constexpr uint8_t SETTLED_BY_BUYOUT = 2;

// bazaar_ledger.type
inline constexpr uint8_t LEDGER_BID_ESCROW = 1;
inline constexpr uint8_t LEDGER_BID_RELEASE = 2;
inline constexpr uint8_t LEDGER_BUYOUT_ESCROW = 3;
inline constexpr uint8_t LEDGER_SELLER_PAYOUT = 4;
inline constexpr uint8_t LEDGER_SALE_FEE = 5;
inline constexpr uint8_t LEDGER_PROMOTION_FEE = 6;
inline constexpr uint8_t LEDGER_REFUND = 7;

// bazaar_events.type
inline constexpr uint8_t EVENT_LISTING_CREATED = 1;
inline constexpr uint8_t EVENT_LISTING_PROMOTED = 2;
inline constexpr uint8_t EVENT_BID_ACCEPTED = 3;
inline constexpr uint8_t EVENT_OUTBID = 4;
inline constexpr uint8_t EVENT_AUCTION_WON = 5;
inline constexpr uint8_t EVENT_AUCTION_SOLD = 6;
inline constexpr uint8_t EVENT_BUYOUT_COMPLETE = 7;
inline constexpr uint8_t EVENT_AUCTION_EXPIRED = 8;
inline constexpr uint8_t EVENT_ITEM_RETURNED = 9;
inline constexpr uint8_t EVENT_ITEM_WITHDRAWN = 10;
inline constexpr uint8_t EVENT_AUCTION_CANCELLED = 11;
// Sent to the SELLER when their auction receives a bid. Distinct from
// EVENT_BID_ACCEPTED (which goes to the bidder) and EVENT_OUTBID (which goes
// to whoever was just displaced).
inline constexpr uint8_t EVENT_BID_RECEIVED = 12;

// Rarity tiers the Bazaar accepts. Mirrors data/lib/rarity/rarity_stats.lua:
// 1..4 are the revealed tiers, 5 is Dormant (RarityStats.DORMANT_TIER).
inline constexpr uint8_t TIER_MIN_ELIGIBLE = 1;
inline constexpr uint8_t TIER_DORMANT = 5;
inline constexpr uint8_t TIER_MAX_ELIGIBLE = 5;

inline constexpr uint32_t MAX_RESULT_MESSAGE = 512;

// Equipment categories, derived from the ItemType (weaponType, falling back to
// slotPosition) so browsing can be filtered by what an item actually IS --
// "show me shields" -- rather than by matching substrings of its name.
//
// Derived server-side rather than accepted from a caller: it is display and
// filter data, but it is also the thing a client could otherwise use to
// mislabel a listing. These values are persisted, so their meaning is fixed --
// append new ones, never renumber.
enum ItemCategory : uint8_t
{
	CATEGORY_UNKNOWN = 0,
	CATEGORY_SWORD = 1,
	CATEGORY_CLUB = 2,
	CATEGORY_AXE = 3,
	CATEGORY_DISTANCE = 4,
	CATEGORY_SHIELD = 5,
	CATEGORY_WAND = 6, // wands and rods both parse to WEAPON_WAND
	CATEGORY_AMMUNITION = 7,
	CATEGORY_FIST = 8,
	CATEGORY_QUIVER = 9,
	CATEGORY_HELMET = 10,
	CATEGORY_ARMOR = 11,
	CATEGORY_LEGS = 12,
	CATEGORY_BOOTS = 13,
	CATEGORY_AMULET = 14,
	CATEGORY_RING = 15,
	CATEGORY_LAST = CATEGORY_RING,
};

// Category for an item type; CATEGORY_UNKNOWN when it fits none of them.
uint8_t getItemCategory(uint16_t itemType);

struct AuctionRecord
{
	uint32_t id = 0;
	uint32_t itemId = 0;
	uint32_t sellerAccountId = 0;
	uint16_t itemType = 0;
	uint8_t tier = 0;
	// Power bracket from RarityClass.getItemClass (Lua). Captured at listing
	// time so the thresholds are not re-implemented per frontend.
	uint8_t itemClass = 0;
	// One of ItemCategory, derived from the ItemType at listing time.
	uint8_t itemCategory = CATEGORY_UNKNOWN;
	std::string itemName;
	// ITEM_ATTRIBUTE_DESCRIPTION as it was at listing time -- carries the
	// rarity bonus lines, so buyers can see what they are bidding on without
	// anything having to deserialise the attributes blob.
	std::string itemDescription;
	uint32_t startPrice = 0;
	uint32_t buyoutPrice = 0; // 0 == no buyout
	uint32_t currentBid = 0;
	uint32_t currentBidderAccountId = 0;
	uint32_t bidCount = 0;
	uint8_t status = 0;
	bool promoted = false;
	uint32_t createdAt = 0;
	uint32_t endsAt = 0;
	// Populated once settled; 0 while the auction is still running.
	uint32_t finalPrice = 0;
	uint32_t fee = 0;
	uint32_t winnerAccountId = 0;
	uint8_t settlementReason = 0;
};

// --- configuration (config.lua `itemBazaar*` keys) ---
bool isEnabled();
uint32_t getMaxActiveAuctions();
uint32_t getMinAuctionHours();
uint32_t getMaxAuctionHours();
uint32_t getDefaultAuctionHours();
uint32_t getSaleFeePercent();
uint32_t getMinSaleFee();
uint32_t getPromotionFee();
uint32_t getAntiSnipeThresholdSeconds();
uint32_t getAntiSnipeResetSeconds();
uint16_t getWorldId();

// Fee on a completed sale. THE single implementation -- the client and the
// website may display an estimate, but never compute the authoritative value.
uint64_t calculateSaleFee(uint64_t salePrice);

// Smallest bid that would currently be accepted (start price if no bids yet,
// otherwise current bid + 1).
uint32_t getMinimumNextBid(const AuctionRecord& auction);

// --- eligibility ---
// Server-side truth about whether an item may be listed. The client's opinion
// is never trusted.
bool isItemEligible(const Item* item, std::string& reason);

// --- domain operations ---
// Every one of these is safe to call from either interface, validates
// everything itself, and reports a player-facing reason on failure.
// `itemUid` is the engine's per-item snowflake (Item::getItemUID), NOT an
// inventory position -- the server locates the instance itself, so a
// tampered or stale client position cannot select someone else's item.
bool createAuction(Player* player, uint64_t itemUid, uint32_t startPrice, uint32_t buyoutPrice,
                   uint32_t durationHours, bool promote, uint8_t itemClass, std::string& reason,
                   uint32_t& outAuctionId);
bool placeBid(uint32_t accountId, uint32_t auctionId, uint32_t amount, const std::string& operationId,
              std::string& reason);
bool buyout(uint32_t accountId, uint32_t auctionId, const std::string& operationId, std::string& reason);
bool cancelAuction(uint32_t accountId, uint32_t auctionId, std::string& reason);
bool relistItem(uint32_t accountId, uint32_t bazaarItemId, uint32_t startPrice, uint32_t buyoutPrice,
                uint32_t durationHours, bool promote, std::string& reason, uint32_t& outAuctionId);
// Delivers an escrowed item into a character's Depot Inbox.
//
// `townId` picks WHICH depot the item appears in, and is not cosmetic: this
// engine gives every depot locker its own separate Inbox container
// (Player::getDepotLocker creates a fresh ITEM_INBOX per locker), so an item
// delivered to one town is invisible from every other town's depot. Passing 0
// falls back to the character's home town. Callers should surface the
// resulting town name to the player, or they will not know where to collect.
bool withdrawItem(uint32_t accountId, uint32_t bazaarItemId, uint32_t targetPlayerId, uint32_t townId,
                  std::string& reason, std::string& outTownName);

// --- reads ---
std::optional<AuctionRecord> getAuction(uint32_t auctionId);
uint32_t getActiveAuctionCount(uint32_t accountId);

// --- settlement / background ---
// Resolves one expired auction. Idempotent: re-running on an already-settled
// auction is a no-op that reports success.
bool settleAuction(uint32_t auctionId);
void settleExpiredAuctions();
void processCommands();
// Resolves bazaar_items rows stranded in PENDING_ESCROW by a crash between
// the escrow write and the player save.
void reconcilePendingEscrow();
void scheduleTasks();

// --- audit / events ---
bool addAudit(uint32_t auctionId, uint32_t itemId, uint64_t itemUid, const std::string& action, uint32_t accountId,
              uint32_t playerId, int64_t amount, const std::string& message);
bool addEvent(uint32_t accountId, uint32_t auctionId, uint8_t type, const std::string& payload);

} // namespace ItemBazaar

#endif // FS_ITEM_BAZAAR_H
