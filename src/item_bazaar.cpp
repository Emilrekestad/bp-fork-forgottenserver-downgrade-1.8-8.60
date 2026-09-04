// Copyright 2026 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#include "otpch.h"

#include "item_bazaar.h"

#include "coins.h"
#include "configmanager.h"
#include "container.h"
#include "database.h"
#include "game.h"
#include "inbox.h"
#include "iologindata.h"
#include "market.h"
#include "player.h"
#include "save_manager.h"
#include "scheduler.h"

#include <algorithm>
#include <cctype>
#include <exception>

extern Game g_game;

namespace {

using namespace ItemBazaar;

constexpr uint32_t SETTLEMENT_INTERVAL_MS = 60 * 1000;
// The website enqueues into `bazaar_commands` and polls for a result, so this
// interval is the floor on perceived web latency. 500ms against an indexed
// `(status, created_at)` lookup is cheap and keeps a web bid feeling instant.
constexpr uint32_t COMMAND_POLL_INTERVAL_MS = 500;
constexpr uint32_t RECONCILE_INTERVAL_MS = 5 * 60 * 1000;
constexpr uint32_t MAX_COMMANDS_PER_TICK = 32;

// bazaar_commands.status
constexpr uint8_t COMMAND_PENDING = 0;
constexpr uint8_t COMMAND_CLAIMED = 1;
constexpr uint8_t COMMAND_DONE = 2;
constexpr uint8_t COMMAND_FAILED = 3;

uint32_t bazaarUnsignedConfig(ConfigManager::Integer config, uint32_t fallback, uint32_t maximum = UINT32_MAX)
{
	const int64_t value = ConfigManager::getInteger(config);
	if (value < 0) {
		return fallback;
	}
	return static_cast<uint32_t>(std::min<int64_t>(value, maximum));
}

std::string bazaarEscapedBlob(Database& db, const std::string& blob)
{
	return db.escapeBlob(blob.data(), static_cast<uint32_t>(blob.size()));
}

bool bazaarAffectedExactlyOne(Database& db, const std::string& query)
{
	return db.executeQuery(query) && db.getAffectedRows() == 1;
}

// Walks a player's equipped slots and every nested container looking for one
// exact item instance. Deliberately identity-based (the __uid snowflake)
// rather than position-based: positions are client-supplied and race with
// the player moving things around mid-request.
Item* findItemByUid(Player* player, uint64_t itemUid)
{
	if (!player || itemUid == 0) {
		return nullptr;
	}

	std::vector<Container*> pending;
	for (int32_t slot = CONST_SLOT_FIRST; slot <= CONST_SLOT_LAST; ++slot) {
		Item* item = player->getInventoryItem(static_cast<slots_t>(slot));
		if (!item) {
			continue;
		}
		if (item->getItemUID() == itemUid) {
			return item;
		}
		if (Container* container = item->getContainer()) {
			pending.push_back(container);
		}
	}

	for (size_t i = 0; i < pending.size(); ++i) {
		for (const auto& child : pending[i]->getItemList()) {
			if (!child) {
				continue;
			}
			if (child->getItemUID() == itemUid) {
				return child.get();
			}
			if (Container* container = child->getContainer()) {
				pending.push_back(container);
			}
		}
	}
	return nullptr;
}

// True when this exact instance is still sitting in some player's saved
// storage. Used by reconciliation to decide whether a stranded
// PENDING_ESCROW row represents a real handover or a rolled-back one.
//
// Deliberately a substring match against the serialized blob: the __uid is
// written into the attributes stream as raw little-endian bytes inside the
// custom-attribute block, and there is no indexed column for it. This runs
// only during reconciliation sweeps, never on a hot path.
bool uidPresentInPlayerStorage(uint64_t itemUid)
{
	Database& db = Database::getInstance();
	std::string needle(reinterpret_cast<const char*>(&itemUid), sizeof(itemUid));
	const std::string escaped = bazaarEscapedBlob(db, needle);
	for (const char* table : {"player_items", "player_depotitems", "player_inboxitems", "player_storeinboxitems",
	                          "player_rewarditems"}) {
		if (db.storeQuery(fmt::format("SELECT 1 FROM `{:s}` WHERE LOCATE({:s}, `attributes`) > 0 LIMIT 1", table,
		                              escaped))) {
			return true;
		}
	}
	return false;
}

// Writes one item straight into an offline character's Depot Inbox.
//
// Modelled on Market::insertInboxItems (src/market.cpp) -- same transaction,
// same FOR UPDATE lock on the player row, same "start sid above the 0-100
// range reserved for lockers" rule -- with one deliberate difference: `pid` is
// the destination town rather than a hardcoded 0. On load
// (IOLoginData::loadPlayer) an inbox row's pid selects which depot locker's
// inbox receives it, so a hardcoded 0 files everything into locker 0, which no
// player ever opens.
bool insertInboxItemForTown(uint32_t playerId, uint32_t townId, uint16_t itemId, uint32_t count,
                            const std::string& attributes)
{
	const ItemType& itemType = Item::items[itemId];
	if (playerId == 0 || itemType.id == 0 || count == 0) {
		return false;
	}

	return DBTransaction::executeWithinTransactionRollbackOnFailure([&]() {
		Database& db = Database::getInstance();
		if (!db.storeQuery(fmt::format("SELECT `id` FROM `players` WHERE `id` = {:d} FOR UPDATE", playerId))) {
			return false;
		}

		const DBResult_ptr result = db.storeQuery(fmt::format(
		    "SELECT COALESCE(MAX(`sid`), 100) AS `sid` FROM `player_inboxitems` WHERE `player_id` = {:d}", playerId));
		if (!result) {
			return false;
		}
		const uint64_t sid = result->getNumber<uint64_t>("sid") + 1;
		if (sid > std::numeric_limits<uint32_t>::max()) {
			return false;
		}

		return db.executeQuery(fmt::format(
		    "INSERT INTO `player_inboxitems` (`player_id`, `sid`, `pid`, `itemtype`, `count`, `attributes`) "
		    "VALUES ({:d}, {:d}, {:d}, {:d}, {:d}, {:s})",
		    playerId, sid, townId, itemId, count, bazaarEscapedBlob(db, attributes)));
	});
}

std::string bazaarSanitizeMessage(std::string text)
{
	if (text.size() > MAX_RESULT_MESSAGE) {
		text.resize(MAX_RESULT_MESSAGE);
	}
	for (char& character : text) {
		if (std::iscntrl(static_cast<unsigned char>(character))) {
			character = ' ';
		}
	}
	return text;
}

// Reads one auction row, locking it for the remainder of the transaction.
// Every mutation starts here so that concurrent bids/buyouts/cancels/
// settlements serialize behind a single row lock rather than racing in
// application memory.
bool lockAuction(uint32_t auctionId, AuctionRecord& out)
{
	auto result = Database::getInstance().storeQuery(fmt::format(
	    "SELECT `id`, COALESCE(`item_id`, 0) AS `item_id`, `seller_account_id`, `itemtype`, `tier`, `item_name`, `start_price`, "
	    "COALESCE(`buyout_price`, 0) AS `buyout_price`, `current_bid`, "
	    "COALESCE(`current_bidder_account_id`, 0) AS `current_bidder_account_id`, `bid_count`, `status`, "
	    "`promoted`, `created_at`, `ends_at` FROM `bazaar_auctions` WHERE `id` = {:d} FOR UPDATE",
	    auctionId));
	if (!result) {
		return false;
	}

	out.id = result->getNumber<uint32_t>("id");
	out.itemId = result->getNumber<uint32_t>("item_id");
	out.sellerAccountId = result->getNumber<uint32_t>("seller_account_id");
	out.itemType = result->getNumber<uint16_t>("itemtype");
	out.tier = result->getNumber<uint8_t>("tier");
	out.itemName = std::string(result->getString("item_name"));
	out.startPrice = result->getNumber<uint32_t>("start_price");
	out.buyoutPrice = result->getNumber<uint32_t>("buyout_price");
	out.currentBid = result->getNumber<uint32_t>("current_bid");
	out.currentBidderAccountId = result->getNumber<uint32_t>("current_bidder_account_id");
	out.bidCount = result->getNumber<uint32_t>("bid_count");
	out.status = result->getNumber<uint8_t>("status");
	out.promoted = result->getNumber<uint8_t>("promoted") != 0;
	out.createdAt = result->getNumber<uint32_t>("created_at");
	out.endsAt = result->getNumber<uint32_t>("ends_at");
	return true;
}

// Records a coin movement. The UNIQUE index on `operation_id` is what makes
// replays safe: a retried transaction (DBTransaction retries up to 3x on
// deadlock) or a resubmitted web command hits the constraint and the whole
// transaction fails rather than paying twice.
// Describes a coin movement for `coin_ledger`. The operation id is carried in
// the metadata so a row here can be joined to its `bazaar_ledger` twin: the
// two ledgers answer different questions -- this one "where did the coins in
// the economy go", that one "what happened to this auction".
Coins::Movement bazaarMovement(std::string kind, uint32_t auctionId, const std::string& operationId)
{
	return Coins::Movement{std::move(kind), "bazaar_auction",
	                       auctionId ? std::to_string(auctionId) : std::string{},
	                       fmt::format(R"({{"operation_id":"{:s}"}})", operationId), 0};
}

bool addLedger(uint32_t accountId, uint32_t auctionId, uint32_t bidId, uint8_t type, int64_t amount,
               const std::string& operationId)
{
	Database& db = Database::getInstance();
	return db.executeQuery(fmt::format(
	    "INSERT INTO `bazaar_ledger` (`account_id`, `auction_id`, `bid_id`, `type`, `amount`, `operation_id`, "
	    "`created_at`) VALUES ({:s}, {:s}, {:s}, {:d}, {:d}, {:s}, {:d})",
	    accountId ? std::to_string(accountId) : "NULL", auctionId ? std::to_string(auctionId) : "NULL",
	    bidId ? std::to_string(bidId) : "NULL", type, amount, db.escapeString(operationId), time(nullptr)));
}

// Moves the escrowed item to a new owner and back into their Bazaar
// Inventory. One statement so ownership can never be half-applied.
bool transferItemToInventory(uint32_t bazaarItemId, uint32_t newOwnerAccountId)
{
	Database& db = Database::getInstance();
	return bazaarAffectedExactlyOne(
	    db, fmt::format("UPDATE `bazaar_items` SET `owner_account_id` = {:d}, `state` = {:d}, "
	                    "`current_auction_id` = NULL, `updated_at` = {:d} WHERE `id` = {:d} AND `state` = {:d}",
	                    newOwnerAccountId, ITEM_STATE_INVENTORY, time(nullptr), bazaarItemId, ITEM_STATE_ESCROWED));
}

// Refunds whoever currently holds the high bid. Called before a new bid takes
// over and during buyout. Safe to call when there is no current bidder.
bool releaseCurrentBid(const AuctionRecord& auction, const std::string& operationPrefix)
{
	if (auction.currentBidderAccountId == 0 || auction.currentBid == 0) {
		return true;
	}
	if (!Coins::credit(auction.currentBidderAccountId, auction.currentBid,
	                   bazaarMovement("bazaar.release", auction.id,
	                                  fmt::format("{:s}:release:{:d}", operationPrefix, auction.id)))) {
		return false;
	}
	return addLedger(auction.currentBidderAccountId, auction.id, 0, LEDGER_BID_RELEASE,
	                 static_cast<int64_t>(auction.currentBid),
	                 fmt::format("{:s}:release:{:d}:{:d}:{:d}", operationPrefix, auction.id,
	                             auction.currentBidderAccountId, auction.currentBid));
}

// Shared tail of createAuction and relistItem: the item is already escrowed,
// this writes the auction row, charges the optional promotion, and emits the
// events. Runs inside the caller's transaction.
bool insertAuctionRow(uint32_t bazaarItemId, uint64_t itemUid, uint32_t sellerAccountId, uint16_t itemType,
                      uint8_t tier, uint8_t itemClass, const std::string& itemName, const std::string& itemDescription,
                      uint32_t startPrice, uint32_t buyoutPrice, uint32_t durationHours, bool promote,
                      uint32_t& outAuctionId, std::string& reason)
{
	Database& db = Database::getInstance();
	const time_t now = time(nullptr);
	const time_t endsAt = now + static_cast<time_t>(durationHours) * 3600;

	// item_uid is stored here as well as on bazaar_items: the escrow row is
	// deleted when the item is eventually withdrawn from the Bazaar, and the
	// auction has to remain a complete historical record after that.
	if (!db.executeQuery(fmt::format(
	        "INSERT INTO `bazaar_auctions` (`item_id`, `item_uid`, `seller_account_id`, `origin_world_id`, "
	        "`itemtype`, `tier`, `item_class`, `item_category`, `item_name`, `item_description`, `start_price`, "
	        "`buyout_price`, `current_bid`, `bid_count`, `status`, `promoted`, `created_at`, `starts_at`, `ends_at`) "
	        "VALUES ({:d}, {:d}, {:d}, {:d}, {:d}, {:d}, {:d}, {:d}, {:s}, {:s}, {:d}, {:s}, 0, 0, {:d}, {:d}, {:d}, "
	        "{:d}, {:d})",
	        bazaarItemId, itemUid, sellerAccountId, getWorldId(), itemType, tier, itemClass,
	        getItemCategory(itemType), db.escapeString(itemName),
	        db.escapeString(itemDescription), startPrice, buyoutPrice ? std::to_string(buyoutPrice) : "NULL",
	        AUCTION_ACTIVE, promote ? 1 : 0, now, now, endsAt))) {
		reason = "The auction could not be created.";
		return false;
	}

	outAuctionId = static_cast<uint32_t>(db.getLastInsertId());

	if (!bazaarAffectedExactlyOne(db, fmt::format("UPDATE `bazaar_items` SET `state` = {:d}, `current_auction_id` = {:d}, "
	                                        "`updated_at` = {:d} WHERE `id` = {:d} AND `state` IN ({:d}, {:d})",
	                                        ITEM_STATE_ESCROWED, outAuctionId, now, bazaarItemId,
	                                        ITEM_STATE_PENDING_ESCROW, ITEM_STATE_INVENTORY))) {
		reason = "The item is no longer available to list.";
		return false;
	}

	// Charged only once the listing is definitely going live, and inside this
	// same transaction -- a failed listing can never take the promotion fee.
	if (promote) {
		const uint32_t fee = getPromotionFee();
		if (fee > 0) {
			if (!Coins::debit(sellerAccountId, fee,
			                  bazaarMovement("bazaar.promotion", outAuctionId,
			                                 fmt::format("promo:{:d}", outAuctionId)))) {
				reason = "You do not have enough Bp Coins for the promotion fee.";
				return false;
			}
			if (!addLedger(sellerAccountId, outAuctionId, 0, LEDGER_PROMOTION_FEE, -static_cast<int64_t>(fee),
			               fmt::format("promo:{:d}", outAuctionId))) {
				reason = "The promotion could not be recorded.";
				return false;
			}
		}
		addEvent(0, outAuctionId, EVENT_LISTING_PROMOTED, itemName);
	}

	addEvent(sellerAccountId, outAuctionId, EVENT_LISTING_CREATED, itemName);
	addAudit(outAuctionId, bazaarItemId, 0, "listed", sellerAccountId, 0, startPrice,
	         fmt::format("Listed for {:d} (buyout {:d}, {:d}h, promoted={:s}).", startPrice, buyoutPrice,
	                     durationHours, promote ? "yes" : "no"));
	return true;
}

// Validates the price/duration triple shared by createAuction and relistItem.
bool validateAuctionParameters(uint32_t startPrice, uint32_t buyoutPrice, uint32_t durationHours, std::string& reason)
{
	if (startPrice < 1) {
		reason = "The starting bid must be at least 1 Bp Coin.";
		return false;
	}
	if (buyoutPrice != 0 && buyoutPrice <= startPrice) {
		reason = "The buyout price must be higher than the starting bid.";
		return false;
	}
	if (durationHours < getMinAuctionHours() || durationHours > getMaxAuctionHours()) {
		reason = fmt::format("The duration must be between {:d} and {:d} whole hours.", getMinAuctionHours(),
		                     getMaxAuctionHours());
		return false;
	}
	return true;
}

} // namespace

namespace ItemBazaar {

// --- configuration ---

bool isEnabled() { return ConfigManager::getBoolean(ConfigManager::ITEM_BAZAAR_ENABLED); }

uint32_t getMaxActiveAuctions()
{
	return std::max<uint32_t>(1, bazaarUnsignedConfig(ConfigManager::ITEM_BAZAAR_MAX_ACTIVE_AUCTIONS, 40));
}

uint32_t getMinAuctionHours()
{
	return std::max<uint32_t>(1, bazaarUnsignedConfig(ConfigManager::ITEM_BAZAAR_MIN_HOURS, 1));
}

uint32_t getMaxAuctionHours()
{
	return std::max(getMinAuctionHours(), bazaarUnsignedConfig(ConfigManager::ITEM_BAZAAR_MAX_HOURS, 168));
}

uint32_t getDefaultAuctionHours()
{
	return std::clamp(bazaarUnsignedConfig(ConfigManager::ITEM_BAZAAR_DEFAULT_HOURS, 24), getMinAuctionHours(),
	                  getMaxAuctionHours());
}

uint32_t getSaleFeePercent()
{
	return std::min<uint32_t>(100, bazaarUnsignedConfig(ConfigManager::ITEM_BAZAAR_SALE_FEE_PERCENT, 10, 100));
}

uint32_t getMinSaleFee() { return bazaarUnsignedConfig(ConfigManager::ITEM_BAZAAR_MIN_SALE_FEE, 1); }

uint32_t getPromotionFee() { return bazaarUnsignedConfig(ConfigManager::ITEM_BAZAAR_PROMOTION_FEE, 5); }

uint32_t getAntiSnipeThresholdSeconds()
{
	return bazaarUnsignedConfig(ConfigManager::ITEM_BAZAAR_ANTI_SNIPE_THRESHOLD, 60);
}

uint32_t getAntiSnipeResetSeconds() { return bazaarUnsignedConfig(ConfigManager::ITEM_BAZAAR_ANTI_SNIPE_RESET, 60); }

uint16_t getWorldId()
{
	return static_cast<uint16_t>(bazaarUnsignedConfig(ConfigManager::ITEM_BAZAAR_WORLD_ID, 1, UINT16_MAX));
}

uint64_t calculateSaleFee(uint64_t salePrice)
{
	if (salePrice == 0) {
		return 0;
	}
	// Integer floor, then a floor of MIN_SALE_FEE so tiny sales still pay
	// something -- and never more than the sale itself.
	const uint64_t percentFee = salePrice * getSaleFeePercent() / 100;
	return std::min(salePrice, std::max<uint64_t>(percentFee, getMinSaleFee()));
}

uint32_t getMinimumNextBid(const AuctionRecord& auction)
{
	if (auction.currentBid == 0) {
		return auction.startPrice;
	}
	return auction.currentBid + 1;
}

// --- eligibility ---

uint8_t getItemCategory(uint16_t itemType)
{
	const ItemType& it = Item::items[itemType];

	// weaponType is the reliable discriminator here: items.xml sets it on every
	// weapon and shield, whereas `classification` is only present on a handful
	// of items and slotType is often left implicit.
	switch (it.weaponType) {
		case WEAPON_SWORD:
			return CATEGORY_SWORD;
		case WEAPON_CLUB:
			return CATEGORY_CLUB;
		case WEAPON_AXE:
			return CATEGORY_AXE;
		case WEAPON_DISTANCE:
			return CATEGORY_DISTANCE;
		case WEAPON_SHIELD:
			return CATEGORY_SHIELD;
		case WEAPON_WAND:
			return CATEGORY_WAND;
		case WEAPON_AMMO:
			return CATEGORY_AMMUNITION;
		case WEAPON_QUIVER:
			return CATEGORY_QUIVER;
		case WEAPON_FIST:
			return CATEGORY_FIST;
		default:
			break;
	}

	// Not a weapon: fall back to where it is worn. Tested most-specific first
	// because slotPosition is a bitfield and armor pieces frequently carry
	// SLOTP_TWO_HAND/SLOTP_WHEREEVER alongside their real slot.
	const uint32_t slot = it.slotPosition;
	if (slot & SLOTP_HEAD) {
		return CATEGORY_HELMET;
	}
	if (slot & SLOTP_ARMOR) {
		return CATEGORY_ARMOR;
	}
	if (slot & SLOTP_LEGS) {
		return CATEGORY_LEGS;
	}
	if (slot & SLOTP_FEET) {
		return CATEGORY_BOOTS;
	}
	if (slot & SLOTP_NECKLACE) {
		return CATEGORY_AMULET;
	}
	if (slot & SLOTP_RING) {
		return CATEGORY_RING;
	}
	return CATEGORY_UNKNOWN;
}

bool isItemEligible(const Item* item, std::string& reason)
{
	if (!item) {
		reason = "That item is not available.";
		return false;
	}

	const uint8_t tier = item->getTier();
	if (tier < TIER_MIN_ELIGIBLE || tier > TIER_MAX_ELIGIBLE) {
		reason = "Only rarity equipment can be listed on the Item Bazaar.";
		return false;
	}

	// Exact-instance escrow requires a stable identity. Stackables are
	// deliberately excluded from the engine's UID system, and a container
	// would drag its contents along, so neither can be escrowed as one row.
	if (!item->hasItemUID()) {
		reason = "That item cannot be listed.";
		return false;
	}
	if (item->getContainer()) {
		reason = "Containers cannot be listed on the Item Bazaar.";
		return false;
	}

	const ItemType& itemType = Item::items[item->getID()];
	if (itemType.stackable || item->getItemCount() != 1) {
		reason = "Only single, non-stackable items can be listed.";
		return false;
	}
	if (!itemType.moveable || !itemType.pickupable) {
		reason = "That item cannot be traded.";
		return false;
	}
	// Respects the existing non-transferable markers used elsewhere in the
	// datapack (quest/system items keep these unset or are decay-bound).
	if (itemType.isRune() || itemType.type == ITEM_TYPE_KEY || itemType.type == ITEM_TYPE_TELEPORT ||
	    itemType.type == ITEM_TYPE_MAGICFIELD || itemType.type == ITEM_TYPE_DOOR ||
	    itemType.type == ITEM_TYPE_DEPOT || itemType.type == ITEM_TYPE_MAILBOX ||
	    itemType.type == ITEM_TYPE_TRASHHOLDER || itemType.type == ITEM_TYPE_BED ||
	    itemType.type == ITEM_TYPE_REWARDCHEST) {
		reason = "That item cannot be listed on the Item Bazaar.";
		return false;
	}
	if (item->hasAttribute(ITEM_ATTRIBUTE_DECAYSTATE) || item->hasAttribute(ITEM_ATTRIBUTE_DURATION)) {
		reason = "Items with a limited lifetime cannot be listed.";
		return false;
	}
	if (item->hasAttribute(ITEM_ATTRIBUTE_OWNER)) {
		reason = "Bound items cannot be listed.";
		return false;
	}

	reason.clear();
	return true;
}

// --- reads ---

std::optional<AuctionRecord> getAuction(uint32_t auctionId)
{
	auto result = Database::getInstance().storeQuery(fmt::format(
	    "SELECT `id`, COALESCE(`item_id`, 0) AS `item_id`, `seller_account_id`, `itemtype`, `tier`, `item_class`, "
	    "`item_category`, `item_name`, `start_price`, "
	    "COALESCE(`buyout_price`, 0) AS `buyout_price`, `current_bid`, "
	    "COALESCE(`current_bidder_account_id`, 0) AS `current_bidder_account_id`, `bid_count`, `status`, "
	    "`promoted`, `created_at`, `ends_at`, COALESCE(`item_description`, '') AS `item_description`, "
	    "COALESCE(`final_price`, 0) AS `final_price`, "
	    "COALESCE(`fee`, 0) AS `fee`, COALESCE(`winner_account_id`, 0) AS `winner_account_id`, "
	    "`settlement_reason` FROM `bazaar_auctions` WHERE `id` = {:d}",
	    auctionId));
	if (!result) {
		return std::nullopt;
	}

	AuctionRecord auction;
	auction.id = result->getNumber<uint32_t>("id");
	auction.itemId = result->getNumber<uint32_t>("item_id");
	auction.sellerAccountId = result->getNumber<uint32_t>("seller_account_id");
	auction.itemType = result->getNumber<uint16_t>("itemtype");
	auction.tier = result->getNumber<uint8_t>("tier");
	auction.itemClass = result->getNumber<uint8_t>("item_class");
	auction.itemCategory = result->getNumber<uint8_t>("item_category");
	auction.itemName = std::string(result->getString("item_name"));
	auction.itemDescription = std::string(result->getString("item_description"));
	auction.startPrice = result->getNumber<uint32_t>("start_price");
	auction.buyoutPrice = result->getNumber<uint32_t>("buyout_price");
	auction.currentBid = result->getNumber<uint32_t>("current_bid");
	auction.currentBidderAccountId = result->getNumber<uint32_t>("current_bidder_account_id");
	auction.bidCount = result->getNumber<uint32_t>("bid_count");
	auction.status = result->getNumber<uint8_t>("status");
	auction.promoted = result->getNumber<uint8_t>("promoted") != 0;
	auction.createdAt = result->getNumber<uint32_t>("created_at");
	auction.endsAt = result->getNumber<uint32_t>("ends_at");
	auction.finalPrice = result->getNumber<uint32_t>("final_price");
	auction.fee = result->getNumber<uint32_t>("fee");
	auction.winnerAccountId = result->getNumber<uint32_t>("winner_account_id");
	auction.settlementReason = result->getNumber<uint8_t>("settlement_reason");
	return auction;
}

uint32_t getActiveAuctionCount(uint32_t accountId)
{
	auto result = Database::getInstance().storeQuery(
	    fmt::format("SELECT COUNT(*) AS `total` FROM `bazaar_auctions` WHERE `seller_account_id` = {:d} "
	                "AND `status` = {:d}",
	                accountId, AUCTION_ACTIVE));
	return result ? result->getNumber<uint32_t>("total") : 0;
}

// --- audit / events ---

bool addAudit(uint32_t auctionId, uint32_t itemId, uint64_t itemUid, const std::string& action, uint32_t accountId,
              uint32_t playerId, int64_t amount, const std::string& message)
{
	Database& db = Database::getInstance();
	return db.executeQuery(fmt::format(
	    "INSERT INTO `bazaar_audit` (`auction_id`, `item_id`, `item_uid`, `action`, `account_id`, `player_id`, "
	    "`amount`, `message`, `created_at`) VALUES ({:s}, {:s}, {:s}, {:s}, {:s}, {:s}, {:d}, {:s}, {:d})",
	    auctionId ? std::to_string(auctionId) : "NULL", itemId ? std::to_string(itemId) : "NULL",
	    itemUid ? std::to_string(itemUid) : "NULL", db.escapeString(action),
	    accountId ? std::to_string(accountId) : "NULL", playerId ? std::to_string(playerId) : "NULL", amount,
	    db.escapeString(bazaarSanitizeMessage(message)), time(nullptr)));
}

bool addEvent(uint32_t accountId, uint32_t auctionId, uint8_t type, const std::string& payload)
{
	Database& db = Database::getInstance();
	return db.executeQuery(fmt::format(
	    "INSERT INTO `bazaar_events` (`account_id`, `auction_id`, `type`, `payload`, `created_at`) "
	    "VALUES ({:s}, {:s}, {:d}, {:s}, {:d})",
	    accountId ? std::to_string(accountId) : "NULL", auctionId ? std::to_string(auctionId) : "NULL", type,
	    db.escapeString(bazaarSanitizeMessage(payload)), time(nullptr)));
}

// --- listing ---

bool createAuction(Player* player, uint64_t itemUid, uint32_t startPrice, uint32_t buyoutPrice,
                   uint32_t durationHours, bool promote, uint8_t itemClass, std::string& reason,
                   uint32_t& outAuctionId)
{
	if (!isEnabled()) {
		reason = "The Item Bazaar is currently disabled.";
		return false;
	}
	if (!player || player->isRemoved()) {
		reason = "You are not available right now.";
		return false;
	}
	if (!validateAuctionParameters(startPrice, buyoutPrice, durationHours, reason)) {
		return false;
	}

	const uint32_t accountId = player->getAccount();
	if (getActiveAuctionCount(accountId) >= getMaxActiveAuctions()) {
		reason = fmt::format("You already have the maximum of {:d} active auctions.", getMaxActiveAuctions());
		return false;
	}

	Item* item = findItemByUid(player, itemUid);
	if (!item) {
		reason = "You are not carrying that item.";
		return false;
	}
	if (!isItemEligible(item, reason)) {
		return false;
	}
	if (promote && Coins::getBalance(accountId) < getPromotionFee()) {
		reason = "You do not have enough Bp Coins for the promotion fee.";
		return false;
	}

	// Capture everything needed to rebuild this exact instance before it is
	// touched, so the escrow row is a complete, standalone record of it.
	const uint16_t itemType = item->getID();
	const uint8_t tier = item->getTier();
	const uint8_t itemCategory = getItemCategory(itemType);
	const std::string itemName{item->getName()};
	// The rarity system writes its bonus lines into ITEM_ATTRIBUTE_DESCRIPTION
	// (data/lib/rarity/rarity_stats.lua), so this one string carries
	// everything that makes the instance worth bidding on.
	const std::string itemDescription{item->getSpecialDescription()};
	PropWriteStream propWriteStream;
	item->serializeAttr(propWriteStream);
	const std::string attributes{propWriteStream.getStream()};

	Database& db = Database::getInstance();
	const time_t now = time(nullptr);
	uint32_t bazaarItemId = 0;

	// STEP 1 -- claim the instance. Committed on its own, BEFORE the item
	// leaves the player, so the UNIQUE index on item_uid is the thing that
	// arbitrates concurrent/replayed listing attempts. A crash after this
	// point leaves a PENDING_ESCROW row, which reconcilePendingEscrow()
	// resolves by checking where the instance actually ended up -- the
	// alternative orderings can either dupe the item or lose it silently.
	const bool claimed = DBTransaction::executeWithinTransactionRollbackOnFailure([&]() {
		if (!db.executeQuery(fmt::format(
		        "INSERT INTO `bazaar_items` (`item_uid`, `owner_account_id`, `origin_world_id`, `itemtype`, "
		        "`count`, `tier`, `item_class`, `item_category`, `item_name`, `item_description`, `attributes`, `state`, "
		        "`source_player_id`, `created_at`, `updated_at`) "
		        "VALUES ({:d}, {:d}, {:d}, {:d}, 1, {:d}, {:d}, {:d}, {:s}, {:s}, {:s}, {:d}, {:d}, {:d}, {:d})",
		        itemUid, accountId, getWorldId(), itemType, tier, itemClass, itemCategory, db.escapeString(itemName),
		        db.escapeString(itemDescription), bazaarEscapedBlob(db, attributes), ITEM_STATE_PENDING_ESCROW,
		        player->getGUID(), now, now))) {
			return false;
		}
		bazaarItemId = static_cast<uint32_t>(db.getLastInsertId());
		return true;
	});

	if (!claimed || bazaarItemId == 0) {
		reason = "That item is already being handled by the Bazaar.";
		return false;
	}

	// STEP 2 -- hand the item over for real, then force the player's save so
	// the removal is durable. Without savePlayerSync a crash here would
	// restore the player with the item still in their inventory while the
	// escrow row also exists: a duplicate.
	if (g_game.internalRemoveItem(item) != RETURNVALUE_NOERROR || !g_saveManager.savePlayerSync(player)) {
		db.executeQuery(fmt::format("DELETE FROM `bazaar_items` WHERE `id` = {:d} AND `state` = {:d}", bazaarItemId,
		                            ITEM_STATE_PENDING_ESCROW));
		reason = "The item could not be handed to the Bazaar. Please try again.";
		return false;
	}

	// STEP 3 -- publish the auction.
	const bool listed = DBTransaction::executeWithinTransactionRollbackOnFailure([&]() {
		return insertAuctionRow(bazaarItemId, itemUid, accountId, itemType, tier, itemClass, itemName, itemDescription,
		                        startPrice, buyoutPrice, durationHours, promote, outAuctionId, reason);
	});

	if (!listed) {
		// The item is already out of the player's hands and durably escrowed,
		// so it is NOT lost -- park it in their Bazaar Inventory rather than
		// attempting a fragile re-insert into a live inventory.
		db.executeQuery(fmt::format("UPDATE `bazaar_items` SET `state` = {:d}, `updated_at` = {:d} WHERE `id` = {:d}",
		                            ITEM_STATE_INVENTORY, time(nullptr), bazaarItemId));
		addAudit(0, bazaarItemId, itemUid, "listing_failed", accountId, player->getGUID(), 0,
		         "Listing failed after escrow; item placed in Bazaar Inventory.");
		if (reason.empty()) {
			reason = "The auction could not be created. The item is in your Bazaar Inventory.";
		}
		return false;
	}

	return true;
}

bool relistItem(uint32_t accountId, uint32_t bazaarItemId, uint32_t startPrice, uint32_t buyoutPrice,
                uint32_t durationHours, bool promote, std::string& reason, uint32_t& outAuctionId)
{
	if (!isEnabled()) {
		reason = "The Item Bazaar is currently disabled.";
		return false;
	}
	if (!validateAuctionParameters(startPrice, buyoutPrice, durationHours, reason)) {
		return false;
	}
	if (getActiveAuctionCount(accountId) >= getMaxActiveAuctions()) {
		reason = fmt::format("You already have the maximum of {:d} active auctions.", getMaxActiveAuctions());
		return false;
	}

	// Already escrowed, so this is a pure DB move -- one transaction, no
	// item handover and none of createAuction's crash window.
	return DBTransaction::executeWithinTransactionRollbackOnFailure([&]() {
		Database& db = Database::getInstance();
		auto result = db.storeQuery(fmt::format(
		    "SELECT `item_uid`, `itemtype`, `tier`, `item_class`, `item_name`, COALESCE(`item_description`, '') AS `item_description`, "
		    "`state`, `owner_account_id` FROM `bazaar_items` "
		    "WHERE `id` = {:d} FOR UPDATE",
		    bazaarItemId));
		if (!result) {
			reason = "That item is not in your Bazaar Inventory.";
			return false;
		}
		if (result->getNumber<uint32_t>("owner_account_id") != accountId ||
		    result->getNumber<uint8_t>("state") != ITEM_STATE_INVENTORY) {
			reason = "That item is not available to list.";
			return false;
		}

		return insertAuctionRow(bazaarItemId, result->getNumber<uint64_t>("item_uid"), accountId,
		                        result->getNumber<uint16_t>("itemtype"), result->getNumber<uint8_t>("tier"),
		                        result->getNumber<uint8_t>("item_class"), std::string(result->getString("item_name")),
		                        std::string(result->getString("item_description")), startPrice, buyoutPrice,
		                        durationHours, promote, outAuctionId, reason);
	});
}

// --- bidding ---

bool placeBid(uint32_t accountId, uint32_t auctionId, uint32_t amount, const std::string& operationId,
              std::string& reason)
{
	if (!isEnabled()) {
		reason = "The Item Bazaar is currently disabled.";
		return false;
	}
	if (accountId == 0) {
		reason = "You must be logged in to bid.";
		return false;
	}

	return DBTransaction::executeWithinTransactionRollbackOnFailure([&]() {
		Database& db = Database::getInstance();
		const time_t now = time(nullptr);

		AuctionRecord auction;
		if (!lockAuction(auctionId, auction)) {
			reason = "That auction does not exist.";
			return false;
		}
		if (auction.status != AUCTION_ACTIVE) {
			reason = "That auction is no longer active.";
			return false;
		}
		if (static_cast<time_t>(auction.endsAt) <= now) {
			reason = "That auction has already ended.";
			return false;
		}
		// Account-wide, so an alt on the seller's account is still the seller.
		if (auction.sellerAccountId == accountId) {
			reason = "You cannot bid on your own auction.";
			return false;
		}
		if (amount < getMinimumNextBid(auction)) {
			reason = fmt::format("Your bid must be at least {:d} Bp Coins.", getMinimumNextBid(auction));
			return false;
		}
		// Buyout is the ceiling for ordinary bidding: reaching it must go
		// through the buyout path so the auction closes immediately.
		if (auction.buyoutPrice != 0 && amount >= auction.buyoutPrice) {
			reason = "That amount reaches the buyout price -- use Buyout instead.";
			return false;
		}

		// Release the previous holder first so the current top bidder can
		// simply raise their own bid without needing a separate top-up path.
		if (!releaseCurrentBid(auction, fmt::format("bid:{:s}", operationId))) {
			reason = "The previous bid could not be released.";
			return false;
		}
		if (!Coins::debit(accountId, amount, bazaarMovement("bazaar.escrow", auctionId, operationId))) {
			reason = "You do not have enough available Bp Coins for this bid.";
			return false;
		}

		if (!db.executeQuery(fmt::format(
		        "INSERT INTO `bazaar_bids` (`auction_id`, `bidder_account_id`, `amount`, `created_at`) "
		        "VALUES ({:d}, {:d}, {:d}, {:d})",
		        auctionId, accountId, amount, now))) {
			reason = "Your bid could not be recorded.";
			return false;
		}
		const uint32_t bidId = static_cast<uint32_t>(db.getLastInsertId());

		if (!addLedger(accountId, auctionId, bidId, LEDGER_BID_ESCROW, -static_cast<int64_t>(amount), operationId)) {
			reason = "Your bid could not be recorded.";
			return false;
		}

		// Anti-snipe: RESET the remaining time to one minute, never add to it,
		// so continued genuine bidding keeps extending but a single late bid
		// cannot stack minutes onto the clock.
		time_t endsAt = auction.endsAt;
		const bool extended = (endsAt - now) < static_cast<time_t>(getAntiSnipeThresholdSeconds());
		if (extended) {
			endsAt = now + getAntiSnipeResetSeconds();
		}

		if (!bazaarAffectedExactlyOne(
		        db, fmt::format("UPDATE `bazaar_auctions` SET `current_bid` = {:d}, `current_bidder_account_id` = "
		                        "{:d}, `bid_count` = `bid_count` + 1, `ends_at` = {:d} WHERE `id` = {:d} "
		                        "AND `status` = {:d} AND `current_bid` = {:d}",
		                        amount, accountId, endsAt, auctionId, AUCTION_ACTIVE, auction.currentBid))) {
			reason = "That auction changed while you were bidding. Please try again.";
			return false;
		}

		if (auction.currentBidderAccountId != 0) {
			addEvent(auction.currentBidderAccountId, auctionId, EVENT_OUTBID, auction.itemName);
		}
		addEvent(accountId, auctionId, EVENT_BID_ACCEPTED, auction.itemName);
		// The seller is told too -- they are the one party with a stake in the
		// auction who would otherwise hear nothing until it settled.
		addEvent(auction.sellerAccountId, auctionId, EVENT_BID_RECEIVED, auction.itemName);
		addAudit(auctionId, auction.itemId, 0, extended ? "bid_antisnipe" : "bid", accountId, 0, amount,
		         fmt::format("Bid accepted{:s}.", extended ? " (deadline reset to 1 minute)" : ""));
		return true;
	});
}

bool buyout(uint32_t accountId, uint32_t auctionId, const std::string& operationId, std::string& reason)
{
	if (!isEnabled()) {
		reason = "The Item Bazaar is currently disabled.";
		return false;
	}
	if (accountId == 0) {
		reason = "You must be logged in to buy out an auction.";
		return false;
	}

	return DBTransaction::executeWithinTransactionRollbackOnFailure([&]() {
		Database& db = Database::getInstance();
		const time_t now = time(nullptr);

		AuctionRecord auction;
		if (!lockAuction(auctionId, auction)) {
			reason = "That auction does not exist.";
			return false;
		}
		// The row lock plus this status check is what makes two simultaneous
		// buyouts resolve to exactly one winner: the loser sees a non-ACTIVE
		// status once the winner's transaction commits.
		if (auction.status != AUCTION_ACTIVE) {
			reason = "That auction is no longer active.";
			return false;
		}
		if (static_cast<time_t>(auction.endsAt) <= now) {
			reason = "That auction has already ended.";
			return false;
		}
		if (auction.buyoutPrice == 0) {
			reason = "That auction has no buyout price.";
			return false;
		}
		if (auction.sellerAccountId == accountId) {
			reason = "You cannot buy out your own auction.";
			return false;
		}

		if (!releaseCurrentBid(auction, fmt::format("buyout:{:s}", operationId))) {
			reason = "The previous bid could not be released.";
			return false;
		}
		if (!Coins::debit(accountId, auction.buyoutPrice,
		                  bazaarMovement("bazaar.escrow", auctionId, operationId))) {
			reason = "You do not have enough available Bp Coins for this buyout.";
			return false;
		}
		if (!addLedger(accountId, auctionId, 0, LEDGER_BUYOUT_ESCROW, -static_cast<int64_t>(auction.buyoutPrice),
		               operationId)) {
			reason = "The buyout could not be recorded.";
			return false;
		}

		const uint64_t fee = calculateSaleFee(auction.buyoutPrice);
		const uint64_t payout = auction.buyoutPrice - fee;

		if (!Coins::credit(auction.sellerAccountId, payout,
		                   bazaarMovement("bazaar.payout", auctionId,
		                                  fmt::format("payout:{:d}", auctionId))) ||
		    !addLedger(auction.sellerAccountId, auctionId, 0, LEDGER_SELLER_PAYOUT, static_cast<int64_t>(payout),
		               fmt::format("payout:{:d}", auctionId)) ||
		    !addLedger(0, auctionId, 0, LEDGER_SALE_FEE, static_cast<int64_t>(fee),
		               fmt::format("fee:{:d}", auctionId))) {
			reason = "The seller could not be paid.";
			return false;
		}

		if (!transferItemToInventory(auction.itemId, accountId)) {
			reason = "The item could not be transferred.";
			return false;
		}

		if (!bazaarAffectedExactlyOne(
		        db, fmt::format("UPDATE `bazaar_auctions` SET `status` = {:d}, `winner_account_id` = {:d}, "
		                        "`final_price` = {:d}, `fee` = {:d}, `current_bid` = {:d}, "
		                        "`current_bidder_account_id` = {:d}, `settled_at` = {:d}, `settlement_reason` = {:d} "
		                        "WHERE `id` = {:d} AND `status` = {:d}",
		                        AUCTION_SETTLED, accountId, auction.buyoutPrice, fee, auction.buyoutPrice, accountId,
		                        now, SETTLED_BY_BUYOUT, auctionId, AUCTION_ACTIVE))) {
			reason = "That auction was already settled.";
			return false;
		}

		addEvent(accountId, auctionId, EVENT_BUYOUT_COMPLETE, auction.itemName);
		addEvent(auction.sellerAccountId, auctionId, EVENT_AUCTION_SOLD, auction.itemName);
		addAudit(auctionId, auction.itemId, 0, "buyout", accountId, 0, auction.buyoutPrice,
		         fmt::format("Buyout for {:d} (fee {:d}, seller received {:d}).", auction.buyoutPrice, fee, payout));
		return true;
	});
}

bool cancelAuction(uint32_t accountId, uint32_t auctionId, std::string& reason)
{
	return DBTransaction::executeWithinTransactionRollbackOnFailure([&]() {
		Database& db = Database::getInstance();

		AuctionRecord auction;
		if (!lockAuction(auctionId, auction)) {
			reason = "That auction does not exist.";
			return false;
		}
		if (auction.sellerAccountId != accountId) {
			reason = "That is not your auction.";
			return false;
		}
		if (auction.status != AUCTION_ACTIVE) {
			reason = "That auction is no longer active.";
			return false;
		}
		// Once a bid has been accepted the seller is committed -- otherwise a
		// seller could pull the item out from under a legitimate bidder.
		if (auction.bidCount > 0 || auction.currentBidderAccountId != 0) {
			reason = "You cannot cancel an auction that has already received a bid.";
			return false;
		}

		if (!transferItemToInventory(auction.itemId, accountId)) {
			reason = "The item could not be returned.";
			return false;
		}
		if (!bazaarAffectedExactlyOne(db, fmt::format("UPDATE `bazaar_auctions` SET `status` = {:d}, `settled_at` = {:d} "
		                                        "WHERE `id` = {:d} AND `status` = {:d} AND `bid_count` = 0",
		                                        AUCTION_CANCELLED, time(nullptr), auctionId, AUCTION_ACTIVE))) {
			reason = "That auction changed while you were cancelling it.";
			return false;
		}

		addEvent(accountId, auctionId, EVENT_AUCTION_CANCELLED, auction.itemName);
		addAudit(auctionId, auction.itemId, 0, "cancelled", accountId, 0, 0,
		         "Seller cancelled; item returned to Bazaar Inventory.");
		return true;
	});
}

// --- withdrawal ---

bool withdrawItem(uint32_t accountId, uint32_t bazaarItemId, uint32_t targetPlayerId, uint32_t townId,
                  std::string& reason, std::string& outTownName)
{
	if (!isEnabled()) {
		reason = "The Item Bazaar is currently disabled.";
		return false;
	}

	Database& db = Database::getInstance();

	// Never trust a frontend-supplied character id: confirm it belongs to this
	// account before anything else.
	auto owner = db.storeQuery(fmt::format("SELECT `name`, `account_id`, `town_id` FROM `players` WHERE `id` = {:d}",
	                                       targetPlayerId));
	if (!owner || owner->getNumber<uint32_t>("account_id") != accountId) {
		reason = "That character does not belong to your account.";
		return false;
	}
	const std::string targetName = std::string(owner->getString("name"));
	const uint32_t homeTownId = owner->getNumber<uint32_t>("town_id");

	// tier / item_class / item_description / source_player_id are read purely so
	// the compensating re-insert below can restore the row faithfully if
	// delivery fails. Omitting them there silently stripped an item of the
	// rarity that gives it all of its value.
	auto itemRow = db.storeQuery(
	    fmt::format("SELECT `item_uid`, `itemtype`, `count`, `tier`, `item_class`, `item_name`, "
	                "COALESCE(`item_description`, '') AS `item_description`, `attributes`, `state`, "
	                "`source_player_id`, `owner_account_id`, `origin_world_id` "
	                "FROM `bazaar_items` WHERE `id` = {:d}",
	                bazaarItemId));
	if (!itemRow || itemRow->getNumber<uint32_t>("owner_account_id") != accountId ||
	    itemRow->getNumber<uint8_t>("state") != ITEM_STATE_INVENTORY) {
		reason = "That item is not in your Bazaar Inventory.";
		return false;
	}
	if (itemRow->getNumber<uint16_t>("origin_world_id") != getWorldId()) {
		reason = "That item belongs to a different world.";
		return false;
	}

	const uint64_t itemUid = itemRow->getNumber<uint64_t>("item_uid");
	const uint16_t itemType = itemRow->getNumber<uint16_t>("itemtype");
	const uint32_t count = std::max<uint32_t>(1, itemRow->getNumber<uint32_t>("count"));
	const uint8_t itemTier = itemRow->getNumber<uint8_t>("tier");
	const uint8_t itemClass = itemRow->getNumber<uint8_t>("item_class");
	const std::string itemName = std::string(itemRow->getString("item_name"));
	const std::string itemDescription = std::string(itemRow->getString("item_description"));
	const uint32_t sourcePlayerId = itemRow->getNumber<uint32_t>("source_player_id");
	const std::string attributes = std::string(itemRow->getString("attributes"));

	// The Depot Inbox silently discards everything past 100 entries on save
	// (IOLoginData::savePlayer). Refusing here is the difference between a
	// clear error and a destroyed unique item.
	auto inboxCount = db.storeQuery(fmt::format(
	    "SELECT COUNT(*) AS `total` FROM `player_inboxitems` WHERE `player_id` = {:d}", targetPlayerId));
	const uint32_t existingInboxItems = inboxCount ? inboxCount->getNumber<uint32_t>("total") : 0;
	Player* onlineTarget = g_game.getPlayerByName(targetName).get();

	// The Depot Inbox is global (one container per player, shown in every
	// town's locker -- see Player::inbox), so there is no destination to
	// choose: a withdrawal is reachable from any depot, exactly like a parcel.
	(void)townId;
	(void)homeTownId;
	outTownName = "Depot Inbox";

	if (onlineTarget) {
		if (const Inbox* inbox = onlineTarget->getInbox()) {
			if (inbox->size() >= IOLoginData::INBOX_SAVE_LIMIT) {
				reason = "That character's Depot Inbox is full. Empty it and try again.";
				return false;
			}
		}
	} else if (existingInboxItems >= IOLoginData::INBOX_SAVE_LIMIT) {
		reason = "That character's Depot Inbox is full. Empty it and try again.";
		return false;
	}

	// Remove from the Bazaar FIRST, in its own committed transaction. If
	// delivery then fails we put it back; the reverse ordering would risk
	// handing out the item twice on a retry.
	const bool claimed = DBTransaction::executeWithinTransactionRollbackOnFailure([&]() {
		return bazaarAffectedExactlyOne(
		    Database::getInstance(),
		    fmt::format("DELETE FROM `bazaar_items` WHERE `id` = {:d} AND `state` = {:d} AND `owner_account_id` = {:d}",
		                bazaarItemId, ITEM_STATE_INVENTORY, accountId));
	});
	if (!claimed) {
		reason = "That item is no longer available to withdraw.";
		return false;
	}

	bool delivered = false;
	if (onlineTarget) {
		PropStream propStream;
		propStream.init(attributes.data(), attributes.size());
		auto item = Item::CreateItem(itemType, static_cast<uint16_t>(count));
		if (item && (attributes.empty() || item->unserializeAttr(propStream))) {
			if (Inbox* inbox = onlineTarget->getInbox()) {
				delivered = g_game.internalAddItem(inbox, item.get(), INDEX_WHEREEVER, FLAG_NOLIMIT) ==
				            RETURNVALUE_NOERROR;
				if (delivered) {
					onlineTarget->onReceiveMail();
				}
			}
		}
	} else {
		// Offline: written straight into player_inboxitems with pid = 0, the
		// same shape savePlayer now writes, so the load path files it into the
		// player's single global inbox.
		delivered = insertInboxItemForTown(targetPlayerId, 0, itemType, count, attributes);
	}

	if (!delivered) {
		// Compensate: restore the escrow row verbatim so nothing is lost.
		Database& restoreDb = Database::getInstance();
		const time_t now = time(nullptr);
		restoreDb.executeQuery(fmt::format(
		    "INSERT INTO `bazaar_items` (`id`, `item_uid`, `owner_account_id`, `origin_world_id`, `itemtype`, "
		    "`count`, `tier`, `item_class`, `item_category`, `item_name`, `item_description`, `attributes`, `state`, "
		    "`source_player_id`, `created_at`, `updated_at`) "
		    "VALUES ({:d}, {:d}, {:d}, {:d}, {:d}, {:d}, {:d}, {:d}, {:d}, {:s}, {:s}, {:s}, {:d}, {:d}, {:d}, {:d})",
		    bazaarItemId, itemUid, accountId, getWorldId(), itemType, count, itemTier, itemClass,
		    getItemCategory(itemType),
		    restoreDb.escapeString(itemName), restoreDb.escapeString(itemDescription),
		    bazaarEscapedBlob(restoreDb, attributes), ITEM_STATE_INVENTORY, sourcePlayerId, now, now));
		addAudit(0, bazaarItemId, itemUid, "withdraw_failed", accountId, targetPlayerId, 0,
		         "Delivery failed; item restored to Bazaar Inventory.");
		reason = "The item could not be delivered. It is still in your Bazaar Inventory.";
		return false;
	}

	addEvent(accountId, 0, EVENT_ITEM_WITHDRAWN, itemName);
	addAudit(0, bazaarItemId, itemUid, "withdrawn", accountId, targetPlayerId, 0,
	         fmt::format("Delivered to {:s}'s Depot Inbox.", targetName));
	return true;
}

// --- settlement ---

bool settleAuction(uint32_t auctionId)
{
	return DBTransaction::executeWithinTransactionRollbackOnFailure([&]() {
		Database& db = Database::getInstance();
		const time_t now = time(nullptr);

		AuctionRecord auction;
		if (!lockAuction(auctionId, auction)) {
			return true; // vanished; nothing to do
		}
		// Idempotent by design: a second settlement pass, a scheduler overlap,
		// or a deadlock retry all land here and exit successfully.
		if (auction.status != AUCTION_ACTIVE || static_cast<time_t>(auction.endsAt) > now) {
			return true;
		}

		// No bids: the item goes back to the seller's Bazaar Inventory.
		if (auction.currentBidderAccountId == 0 || auction.currentBid == 0) {
			if (!transferItemToInventory(auction.itemId, auction.sellerAccountId)) {
				return false;
			}
			if (!bazaarAffectedExactlyOne(db, fmt::format("UPDATE `bazaar_auctions` SET `status` = {:d}, `settled_at` = "
			                                        "{:d} WHERE `id` = {:d} AND `status` = {:d}",
			                                        AUCTION_EXPIRED, now, auctionId, AUCTION_ACTIVE))) {
				return false;
			}
			addEvent(auction.sellerAccountId, auctionId, EVENT_AUCTION_EXPIRED, auction.itemName);
			addAudit(auctionId, auction.itemId, 0, "expired_no_bid", auction.sellerAccountId, 0, 0,
			         "Expired without a bid; item returned to Bazaar Inventory.");
			return true;
		}

		// Winner's coins were escrowed at bid time, so settlement only has to
		// consume them: pay the seller the remainder after the fee.
		const uint64_t fee = calculateSaleFee(auction.currentBid);
		const uint64_t payout = auction.currentBid - fee;

		if (!Coins::credit(auction.sellerAccountId, payout,
		                   bazaarMovement("bazaar.payout", auctionId,
		                                  fmt::format("payout:{:d}", auctionId))) ||
		    !addLedger(auction.sellerAccountId, auctionId, 0, LEDGER_SELLER_PAYOUT, static_cast<int64_t>(payout),
		               fmt::format("payout:{:d}", auctionId)) ||
		    !addLedger(0, auctionId, 0, LEDGER_SALE_FEE, static_cast<int64_t>(fee),
		               fmt::format("fee:{:d}", auctionId))) {
			return false;
		}

		if (!transferItemToInventory(auction.itemId, auction.currentBidderAccountId)) {
			return false;
		}

		if (!bazaarAffectedExactlyOne(
		        db, fmt::format("UPDATE `bazaar_auctions` SET `status` = {:d}, `winner_account_id` = {:d}, "
		                        "`final_price` = {:d}, `fee` = {:d}, `settled_at` = {:d}, `settlement_reason` = {:d} "
		                        "WHERE `id` = {:d} AND `status` = {:d}",
		                        AUCTION_SETTLED, auction.currentBidderAccountId, auction.currentBid, fee, now,
		                        SETTLED_BY_AUCTION, auctionId, AUCTION_ACTIVE))) {
			return false;
		}

		addEvent(auction.currentBidderAccountId, auctionId, EVENT_AUCTION_WON, auction.itemName);
		addEvent(auction.sellerAccountId, auctionId, EVENT_AUCTION_SOLD, auction.itemName);
		addAudit(auctionId, auction.itemId, 0, "settled", auction.currentBidderAccountId, 0, auction.currentBid,
		         fmt::format("Sold for {:d} (fee {:d}, seller received {:d}).", auction.currentBid, fee, payout));
		return true;
	});
}

void settleExpiredAuctions()
{
	if (!isEnabled()) {
		return;
	}
	auto result = Database::getInstance().storeQuery(
	    fmt::format("SELECT `id` FROM `bazaar_auctions` WHERE `status` = {:d} AND `ends_at` <= {:d} LIMIT 200",
	                AUCTION_ACTIVE, time(nullptr)));
	if (!result) {
		return;
	}
	do {
		const uint32_t auctionId = result->getNumber<uint32_t>("id");
		if (!settleAuction(auctionId)) {
			LOG_ERROR(fmt::format("[ItemBazaar] Failed to settle auction #{:d}.", auctionId));
		}
	} while (result->next());
}

void reconcilePendingEscrow()
{
	if (!isEnabled()) {
		return;
	}
	Database& db = Database::getInstance();
	// Only rows old enough that an in-flight listing cannot still be working
	// on them (createAuction's steps 1-3 complete in milliseconds).
	auto result = db.storeQuery(fmt::format(
	    "SELECT `id`, `item_uid`, `owner_account_id` FROM `bazaar_items` WHERE `state` = {:d} AND `created_at` < {:d} "
	    "LIMIT 100",
	    ITEM_STATE_PENDING_ESCROW, time(nullptr) - 120));
	if (!result) {
		return;
	}

	do {
		const uint32_t itemId = result->getNumber<uint32_t>("id");
		const uint64_t itemUid = result->getNumber<uint64_t>("item_uid");
		const uint32_t accountId = result->getNumber<uint32_t>("owner_account_id");

		if (uidPresentInPlayerStorage(itemUid)) {
			// The handover never completed -- the player still owns it, so the
			// claim must be dropped or the item would exist twice.
			db.executeQuery(fmt::format("DELETE FROM `bazaar_items` WHERE `id` = {:d} AND `state` = {:d}", itemId,
			                            ITEM_STATE_PENDING_ESCROW));
			addAudit(0, itemId, itemUid, "reconcile_dropped", accountId, 0, 0,
			         "Pending escrow dropped; instance still owned by a character.");
		} else {
			// The item really did leave the player, so completing the escrow is
			// what keeps it from being lost.
			db.executeQuery(fmt::format(
			    "UPDATE `bazaar_items` SET `state` = {:d}, `updated_at` = {:d} WHERE `id` = {:d} AND `state` = {:d}",
			    ITEM_STATE_INVENTORY, time(nullptr), itemId, ITEM_STATE_PENDING_ESCROW));
			addAudit(0, itemId, itemUid, "reconcile_recovered", accountId, 0, 0,
			         "Pending escrow completed into Bazaar Inventory.");
		}
	} while (result->next());
}

// --- website command queue ---

void processCommands()
{
	if (!isEnabled()) {
		return;
	}
	Database& db = Database::getInstance();
	auto result = db.storeQuery(
	    fmt::format("SELECT `id`, `account_id`, `action`, `params` FROM `bazaar_commands` WHERE `status` = {:d} "
	                "ORDER BY `id` ASC LIMIT {:d}",
	                COMMAND_PENDING, MAX_COMMANDS_PER_TICK));
	if (!result) {
		return;
	}

	std::vector<std::tuple<uint64_t, uint32_t, std::string, std::string>> commands;
	do {
		commands.emplace_back(result->getNumber<uint64_t>("id"), result->getNumber<uint32_t>("account_id"),
		                      std::string(result->getString("action")), std::string(result->getString("params")));
	} while (result->next());

	for (const auto& [commandId, accountId, action, params] : commands) {
		// Claim first, guarded on still-PENDING, so a restart mid-tick or a
		// second server instance can never execute the same command twice.
		if (!bazaarAffectedExactlyOne(db, fmt::format("UPDATE `bazaar_commands` SET `status` = {:d}, `claimed_at` = {:d} "
		                                        "WHERE `id` = {:d} AND `status` = {:d}",
		                                        COMMAND_CLAIMED, time(nullptr), commandId, COMMAND_PENDING))) {
			continue;
		}

		std::string reason;
		bool success = false;

		// params is a compact "a=1;b=2" list -- the website never sends an
		// account id, that is taken from the authenticated session row.
		auto param = [&params](const std::string& key) -> uint64_t {
			const std::string needle = key + "=";
			size_t pos = params.find(needle);
			if (pos == std::string::npos) {
				return 0;
			}
			pos += needle.size();
			uint64_t value = 0;
			while (pos < params.size() && std::isdigit(static_cast<unsigned char>(params[pos]))) {
				value = value * 10 + static_cast<uint64_t>(params[pos] - '0');
				++pos;
			}
			return value;
		};

		const std::string operationId = fmt::format("web:{:d}", commandId);
		if (action == "bid") {
			success = placeBid(accountId, static_cast<uint32_t>(param("auction")),
			                   static_cast<uint32_t>(param("amount")), operationId, reason);
		} else if (action == "buyout") {
			success = buyout(accountId, static_cast<uint32_t>(param("auction")), operationId, reason);
		} else if (action == "cancel") {
			success = cancelAuction(accountId, static_cast<uint32_t>(param("auction")), reason);
		} else if (action == "relist") {
			uint32_t auctionId = 0;
			success = relistItem(accountId, static_cast<uint32_t>(param("item")),
			                     static_cast<uint32_t>(param("start")), static_cast<uint32_t>(param("buyout")),
			                     static_cast<uint32_t>(param("hours")), param("promote") != 0, reason, auctionId);
		} else if (action == "withdraw") {
			std::string townName;
			success = withdrawItem(accountId, static_cast<uint32_t>(param("item")),
			                       static_cast<uint32_t>(param("character")), 0, reason, townName);
		} else {
			reason = "Unknown Bazaar action.";
		}

		db.executeQuery(fmt::format(
		    "UPDATE `bazaar_commands` SET `status` = {:d}, `result_code` = {:d}, `result_message` = {:s}, "
		    "`completed_at` = {:d} WHERE `id` = {:d}",
		    success ? COMMAND_DONE : COMMAND_FAILED, success ? 0 : 1,
		    db.escapeString(bazaarSanitizeMessage(success ? std::string{} : reason)), time(nullptr), commandId));
	}
}

namespace {

// Each background job re-arms only itself. They deliberately do NOT share one
// re-arm point: a single function that re-added all three would multiply the
// timers on every tick.
template <typename Func>
void scheduleRepeating(uint32_t intervalMs, const char* label, Func job, void (*rearm)())
{
	g_scheduler.addEvent(intervalMs, [label, job, rearm]() {
		try {
			job();
		} catch (const std::exception& exception) {
			LOG_ERROR(fmt::format("[ItemBazaar] Exception during {:s}: {:s}", label, exception.what()));
		} catch (...) {
			LOG_ERROR(fmt::format("[ItemBazaar] Unknown exception during {:s}.", label));
		}
		rearm();
	});
}

void scheduleSettlement()
{
	scheduleRepeating(SETTLEMENT_INTERVAL_MS, "settlement", settleExpiredAuctions, &scheduleSettlement);
}

void scheduleCommandPolling()
{
	scheduleRepeating(COMMAND_POLL_INTERVAL_MS, "command processing", processCommands, &scheduleCommandPolling);
}

void scheduleReconciliation()
{
	scheduleRepeating(RECONCILE_INTERVAL_MS, "reconciliation", reconcilePendingEscrow, &scheduleReconciliation);
}

} // namespace

void scheduleTasks()
{
	if (!isEnabled()) {
		return;
	}
	scheduleSettlement();
	scheduleCommandPolling();
	scheduleReconciliation();
}

} // namespace ItemBazaar
