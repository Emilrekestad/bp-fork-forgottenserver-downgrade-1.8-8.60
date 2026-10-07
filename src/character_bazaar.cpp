// Copyright 2026 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#include "otpch.h"

#include "character_bazaar.h"

#include "coins.h"
#include "configmanager.h"
#include "database.h"
#include "game.h"
#include "player.h"
#include "scheduler.h"
#include "tile.h"

#include <algorithm>
#include <cctype>
#include <exception>
#include <limits>

namespace {

using CharacterBazaar::AUCTION_STATUS_ACTIVE;
using CharacterBazaar::AUCTION_STATUS_EXPIRED_NO_BIDS;
using CharacterBazaar::AUCTION_STATUS_FINISHED;
using CharacterBazaar::AUCTION_STATUS_WITHDRAWN;

constexpr uint32_t FINALIZATION_INTERVAL_MS = 60 * 1000;

uint32_t asUnsignedConfig(ConfigManager::Integer config, uint32_t fallback, uint32_t maximum = UINT32_MAX)
{
	const int64_t value = ConfigManager::getInteger(config);
	if (value < 0) {
		return fallback;
	}
	return static_cast<uint32_t>(std::min<int64_t>(value, maximum));
}

uint32_t getMinimumLevel()
{
	return std::max<uint32_t>(1, asUnsignedConfig(ConfigManager::CHARACTER_BAZAAR_MIN_LEVEL, 50));
}

uint32_t getMinimumPrice()
{
	return std::max<uint32_t>(1, asUnsignedConfig(ConfigManager::CHARACTER_BAZAAR_MIN_PRICE, 100));
}

uint32_t getAuctionFee()
{
	return asUnsignedConfig(ConfigManager::CHARACTER_BAZAAR_AUCTION_FEE, 50);
}

uint32_t getCommissionPercent()
{
	return std::min<uint32_t>(100, asUnsignedConfig(ConfigManager::CHARACTER_BAZAAR_COMMISSION_PERCENT, 10, 100));
}

uint32_t getMinimumDuration()
{
	const uint64_t seconds =
	    static_cast<uint64_t>(asUnsignedConfig(ConfigManager::CHARACTER_BAZAAR_MIN_DURATION_HOURS, 24)) * 60 * 60;
	return std::max<uint32_t>(60, static_cast<uint32_t>(std::min<uint64_t>(seconds, UINT32_MAX)));
}

uint32_t getMaximumDuration()
{
	const uint64_t seconds = static_cast<uint64_t>(asUnsignedConfig(ConfigManager::CHARACTER_BAZAAR_MAX_DURATION_DAYS, 7)) *
	                         24 * 60 * 60;
	return static_cast<uint32_t>(std::min<uint64_t>(seconds, UINT32_MAX));
}

// Anti-snipe window. A bid that lands with less than this left RESETS the
// clock to exactly this much -- it never adds to it -- so genuine competition
// keeps an auction alive while a single last-second bid cannot stack time.
// Character auctions run for days, so the window is minutes rather than the
// Item Bazaar's single minute: a bidder deserves time to notice.
uint32_t getAntiSnipeSeconds()
{
	return asUnsignedConfig(ConfigManager::CHARACTER_BAZAAR_ANTI_SNIPE_MINUTES, 5, 24 * 60) * 60;
}

bool queryHasRows(const std::string& query)
{
	return static_cast<bool>(Database::getInstance().storeQuery(query));
}

bool affectedExactlyOne(Database& db, const std::string& query)
{
	return db.executeQuery(query) && db.getAffectedRows() == 1;
}

bool hasActiveAuctionForAccount(uint32_t accountId)
{
	return queryHasRows(fmt::format(
	    "SELECT `id` FROM `character_auctions` WHERE `seller_account_id` = {:d} AND `status` = {:d} LIMIT 1", accountId,
	    AUCTION_STATUS_ACTIVE));
}

bool lockAccountForAuction(uint32_t accountId)
{
	return static_cast<bool>(Database::getInstance().storeQuery(
	    fmt::format("SELECT `id` FROM `accounts` WHERE `id` = {:d} FOR UPDATE", accountId)));
}

bool addHistoryInternal(uint32_t auctionId, const std::string& action, uint32_t accountId, uint32_t playerId,
                        uint64_t amount, const std::string& message)
{
	Database& db = Database::getInstance();
	return db.executeQuery(fmt::format(
	    "INSERT INTO `character_auction_history` (`auction_id`, `action`, `account_id`, `player_id`, `amount`, `message`, "
	    "`created_at`) VALUES ({:d}, {:s}, {:d}, {:d}, {:d}, {:s}, {:d})",
	    auctionId, db.escapeString(action), accountId, playerId, amount, db.escapeString(message), time(nullptr)));
}

std::string sanitizeDescription(std::string description)
{
	for (char& character : description) {
		if (std::iscntrl(static_cast<unsigned char>(character))) {
			character = ' ';
		}
	}
	return description;
}

// One locked auction row, read FOR UPDATE at the top of every mutation.
struct AuctionRecord
{
	uint32_t id = 0;
	uint32_t playerId = 0;
	uint32_t sellerAccountId = 0;
	uint32_t currentBidderAccountId = 0;
	uint32_t startPrice = 0;
	uint32_t currentBid = 0;
	// 0 = this listing has no Buy Now. Also the ceiling on bidding: placeBid
	// refuses any bid that reaches it, which is what keeps a buyout from ever
	// settling below the standing bid.
	uint32_t buyoutPrice = 0;
	uint8_t commissionPercent = 0;
	uint8_t status = 0;
	uint32_t endAt = 0;
	std::string playerName;
};

bool lockAuction(uint32_t auctionId, AuctionRecord& out)
{
	auto result = Database::getInstance().storeQuery(fmt::format(
	    "SELECT `id`, `player_id`, `player_name`, `seller_account_id`, "
	    "COALESCE(`current_bidder_account_id`, 0) AS `bidder_account_id`, `start_price`, `current_bid`, "
	    "COALESCE(`buyout_price`, 0) AS `buyout_price`, "
	    "`commission_percent`, `status`, `end_at` FROM `character_auctions` WHERE `id` = {:d} FOR UPDATE",
	    auctionId));
	if (!result) {
		return false;
	}
	out.id = result->getNumber<uint32_t>("id");
	out.playerId = result->getNumber<uint32_t>("player_id");
	out.playerName = std::string(result->getString("player_name"));
	out.sellerAccountId = result->getNumber<uint32_t>("seller_account_id");
	out.currentBidderAccountId = result->getNumber<uint32_t>("bidder_account_id");
	out.startPrice = result->getNumber<uint32_t>("start_price");
	out.currentBid = result->getNumber<uint32_t>("current_bid");
	out.buyoutPrice = result->getNumber<uint32_t>("buyout_price");
	out.commissionPercent = result->getNumber<uint8_t>("commission_percent");
	out.status = result->getNumber<uint8_t>("status");
	out.endAt = result->getNumber<uint32_t>("end_at");
	return true;
}

// Bid movements reference the BID row, not the auction: an auction has many of
// them and coin_ledger's (ref_type, ref_id, kind) key is unique. The operation
// id rides in the metadata so a row can be traced to the request that made it.
Coins::Movement bidMovement(std::string kind, uint32_t bidId, const std::string& operationId)
{
	return Coins::Movement{std::move(kind), "char_auction_bid", std::to_string(bidId),
	                       fmt::format(R"({{"operation_id":"{:s}"}})", operationId), 0};
}

bool finalizeAuction(uint32_t auctionId)
{
	const time_t currentTime = time(nullptr);
	return DBTransaction::executeWithinTransactionRollbackOnFailure([auctionId, currentTime]() {
		Database& db = Database::getInstance();
		auto result = db.storeQuery(fmt::format(
		    "SELECT `player_id`, `seller_account_id`, COALESCE(`current_bidder_account_id`, 0) AS `bidder_account_id`, "
		    "`current_bid`, `commission_percent` FROM `character_auctions` WHERE `id` = {:d} AND `status` = {:d} "
		    "AND `end_at` <= {:d} FOR UPDATE",
		    auctionId, AUCTION_STATUS_ACTIVE, currentTime));
		if (!result) {
			return true; // already finalized by another scheduler run
		}

		const uint32_t playerId = result->getNumber<uint32_t>("player_id");
		const uint32_t sellerAccountId = result->getNumber<uint32_t>("seller_account_id");
		const uint32_t bidderAccountId = result->getNumber<uint32_t>("bidder_account_id");
		const uint64_t bid = result->getNumber<uint64_t>("current_bid");
		const uint32_t commissionPercent = std::min<uint32_t>(100, result->getNumber<uint32_t>("commission_percent"));

		if (bidderAccountId == 0 || bid == 0) {
			if (!db.executeQuery(fmt::format(
			        "UPDATE `character_auctions` SET `status` = {:d}, `finished_at` = {:d} WHERE `id` = {:d} "
			        "AND `status` = {:d}",
			        AUCTION_STATUS_EXPIRED_NO_BIDS, currentTime, auctionId, AUCTION_STATUS_ACTIVE))) {
				return false;
			}
			return addHistoryInternal(auctionId, "expired_no_bid", sellerAccountId, playerId, 0,
			                          "Auction expired without a bid.");
		}

		const uint64_t commission = bid * commissionPercent / 100;
		const uint64_t sellerPayout = bid - commission;
		if (!db.executeQuery(fmt::format(
		        "UPDATE `players` SET `account_id` = {:d} WHERE `id` = {:d} AND `account_id` = {:d}", bidderAccountId,
		        playerId, sellerAccountId)) ||
		    db.getAffectedRows() != 1 || !CharacterBazaar::creditTransferableCoins(sellerAccountId, sellerPayout, "charbazaar.payout", auctionId)) {
			return false;
		}

		if (!db.executeQuery(fmt::format(
		        "UPDATE `character_auctions` SET `status` = {:d}, `winner_account_id` = {:d}, `final_price` = {:d}, "
		        "`finished_at` = {:d} WHERE `id` = {:d} AND `status` = {:d}",
		        AUCTION_STATUS_FINISHED, bidderAccountId, bid, currentTime, auctionId, AUCTION_STATUS_ACTIVE))) {
			return false;
		}

		return addHistoryInternal(auctionId, "finished", bidderAccountId, playerId, sellerPayout,
		                          fmt::format("Auction finished for {:d} coins (commission: {:d}).", bid, commission));
	});
}

} // namespace

namespace CharacterBazaar {

bool isEnabled()
{
	return ConfigManager::getBoolean(ConfigManager::CHARACTER_BAZAAR_ENABLED);
}

bool isPlayerOnActiveAuction(uint32_t playerId)
{
	if (playerId == 0) {
		return false;
	}
	return queryHasRows(fmt::format(
	    "SELECT `id` FROM `character_auctions` WHERE `player_id` = {:d} AND `status` = {:d} LIMIT 1", playerId,
	    AUCTION_STATUS_ACTIVE));
}

// Thin forwarders to the shared Coins module (src/coins.h). The guarded-UPDATE
// implementations used to live here; they were promoted so the Item Bazaar
// shares one copy rather than re-deriving the same atomicity trick.
uint64_t getTransferableCoins(uint32_t accountId) { return Coins::getBalance(accountId); }

namespace {

Coins::Movement charAuctionMovement(std::string kind, uint32_t auctionId)
{
	return Coins::Movement{std::move(kind), "char_auction",
	                       auctionId ? std::to_string(auctionId) : std::string{}, {}, 0};
}

} // namespace

// The commission is deliberately not a movement of its own: the bidder's
// escrow leaves circulation and only `bid - commission` is paid back out, so
// the difference between charbazaar.escrow and charbazaar.payout *is* the
// commission. Inventing a third row for it would double-count the burn.
bool debitTransferableCoins(uint32_t accountId, uint64_t amount, std::string kind, uint32_t auctionId)
{
	return Coins::debit(accountId, amount, charAuctionMovement(std::move(kind), auctionId));
}

bool creditTransferableCoins(uint32_t accountId, uint64_t amount, std::string kind, uint32_t auctionId)
{
	return Coins::credit(accountId, amount, charAuctionMovement(std::move(kind), auctionId));
}

bool addHistory(uint32_t auctionId, const std::string& action, uint32_t accountId, uint32_t playerId, uint64_t amount,
	            const std::string& message)
{
	return addHistoryInternal(auctionId, action, accountId, playerId, amount, message);
}

uint32_t getMinimumNextBid(uint32_t startPrice, uint32_t currentBid)
{
	if (currentBid == 0) {
		return startPrice;
	}
	return currentBid == UINT32_MAX ? UINT32_MAX : currentBid + 1;
}

bool canCreateAuction(Player* player, std::string& reason)
{
	if (!isEnabled()) {
		reason = "Character Bazaar is disabled.";
		return false;
	}
	if (!player || player->isRemoved()) {
		reason = "The character is not available.";
		return false;
	}
	if (player->isDead()) {
		reason = "Dead characters cannot be listed.";
		return false;
	}
	if (player->getAccountType() > ACCOUNT_TYPE_NORMAL) {
		reason = "Staff characters cannot be listed.";
		return false;
	}
	if (player->getLevel() < getMinimumLevel()) {
		reason = fmt::format("Your character must be at least level {:d}.", getMinimumLevel());
		return false;
	}
	if (!player->getTile() || !player->getTile()->hasFlag(TILESTATE_PROTECTIONZONE)) {
		reason = "You must be in a protection zone.";
		return false;
	}
	if (player->isPzLocked() || player->hasCondition(CONDITION_INFIGHT)) {
		reason = "You cannot list a character while in a fight.";
		return false;
	}
	if (isPlayerOnActiveAuction(player->getGUID()) || hasActiveAuctionForAccount(player->getAccount())) {
		reason = "This account already has an active character auction.";
		return false;
	}
	if (queryHasRows(fmt::format("SELECT `player_id` FROM `guild_membership` WHERE `player_id` = {:d} LIMIT 1",
	                             player->getGUID()))) {
		reason = "Leave your guild before listing this character.";
		return false;
	}
	if (queryHasRows(fmt::format(
	        "SELECT `id` FROM `houses` WHERE `owner` = {:d} OR `highest_bidder` = {:d} LIMIT 1", player->getGUID(),
	        player->getGUID()))) {
		reason = "Characters involved with houses cannot be listed.";
		return false;
	}
	if (ConfigManager::getBoolean(ConfigManager::MARKET_SYSTEM_ENABLED) &&
	    queryHasRows(fmt::format("SELECT `id` FROM `market_offers` WHERE `player_id` = {:d} LIMIT 1", player->getGUID()))) {
		reason = "Cancel your market offers before listing this character.";
		return false;
	}
	if (getTransferableCoins(player->getAccount()) < getAuctionFee()) {
		reason = "You do not have enough transferable Bp Coins for the auction fee.";
		return false;
	}

	reason.clear();
	return true;
}

Rules getRules(Player* player)
{
	Rules rules;
	rules.enabled = isEnabled();
	rules.eligible = canCreateAuction(player, rules.reason);
	rules.minLevel = getMinimumLevel();
	rules.minPrice = getMinimumPrice();
	rules.minDurationSeconds = getMinimumDuration();
	rules.maxDurationSeconds = std::max(getMinimumDuration(), getMaximumDuration());
	rules.fee = getAuctionFee();
	rules.commissionPercent = static_cast<uint8_t>(getCommissionPercent());
	rules.antiSnipeSeconds = getAntiSnipeSeconds();
	rules.balance = player ? getTransferableCoins(player->getAccount()) : 0;
	return rules;
}

bool createAuction(Player* player, uint32_t startPrice, uint32_t buyoutPrice, uint32_t durationSeconds,
                   const std::string& description, std::string& reason, uint32_t& outAuctionId)
{
	outAuctionId = 0;
	if (!canCreateAuction(player, reason)) {
		return false;
	}
	if (startPrice < getMinimumPrice()) {
		reason = fmt::format("The starting price must be at least {:d} coins.", getMinimumPrice());
		return false;
	}
	// Strictly above, never equal: a buyout equal to the start price is a
	// fixed-price sale, and this system is an auction. Same rule as
	// ItemBazaar::validateAuctionParameters.
	if (buyoutPrice != 0 && buyoutPrice <= startPrice) {
		reason = "The Buy Now price must be higher than the starting price.";
		return false;
	}
	const uint32_t minDuration = getMinimumDuration();
	const uint32_t maxDuration = std::max(minDuration, getMaximumDuration());
	if (durationSeconds < minDuration || durationSeconds > maxDuration) {
		reason = fmt::format("The auction duration must be between {:d} and {:d} hours.", minDuration / 3600,
		                     maxDuration / 3600);
		return false;
	}
	if (description.size() > MAX_DESCRIPTION_LENGTH) {
		reason = fmt::format("The description may contain at most {:d} characters.", MAX_DESCRIPTION_LENGTH);
		return false;
	}

	const std::string safeDescription = sanitizeDescription(description);
	const uint32_t playerId = player->getGUID();
	const uint32_t accountId = player->getAccount();
	const time_t currentTime = time(nullptr);
	uint32_t auctionId = 0;

	const bool success = DBTransaction::executeWithinTransactionRollbackOnFailure([&]() {
		reason.clear();
		auctionId = 0;
		Database& db = Database::getInstance();
		if (!lockAccountForAuction(accountId)) {
			reason = "The account is no longer available.";
			return false;
		}
		// Website character/guild edits take this same account lock. Recheck
		// eligibility here so a completed edit cannot race the initial check.
		if (!canCreateAuction(player, reason)) {
			return false;
		}
		if (!db.storeQuery(fmt::format(
		        "SELECT `id` FROM `players` WHERE `id` = {:d} AND `account_id` = {:d} AND `deletion` = 0 FOR UPDATE",
		        playerId, accountId))) {
			reason = "The character is no longer available.";
			return false;
		}
		const Outfit_t outfit = player->getCurrentOutfit();
		if (!db.executeQuery(fmt::format(
		        "INSERT INTO `character_auctions` (`player_id`, `player_name`, `seller_account_id`, `start_price`, "
		        "`buyout_price`, "
		        "`current_bid`, `auction_fee`, `commission_percent`, `status`, `created_at`, `end_at`, `description`, "
		        "`snapshot_level`, `snapshot_vocation`, `vocation`, `level`, `looktype`, `lookaddons`, `lookhead`, "
		        "`lookbody`, `looklegs`, `lookfeet`) VALUES ({:d}, {:s}, {:d}, {:d}, {:d}, 0, {:d}, {:d}, {:d}, {:d}, {:d}, {:s}, {:d}, {:d}, {:d}, {:d}, {:d}, {:d}, {:d}, {:d}, {:d}, {:d})",
		        playerId, db.escapeString(player->getName()), accountId, startPrice, buyoutPrice, getAuctionFee(), getCommissionPercent(),
		        AUCTION_STATUS_ACTIVE, currentTime, currentTime + durationSeconds, db.escapeString(safeDescription),
		        player->getLevel(), player->getVocationId(), player->getVocationId(), player->getLevel(),
		        outfit.lookType, outfit.lookAddons, outfit.lookHead, outfit.lookBody, outfit.lookLegs, outfit.lookFeet))) {
			reason = "The auction could not be created.";
			return false;
		}
		auctionId = static_cast<uint32_t>(db.getLastInsertId());
		// The row and fee share this transaction. Link the fee to its auction
		// so reconciliation can follow it; any failure rolls both back.
		if (auctionId == 0 || !debitTransferableCoins(accountId, getAuctionFee(), "charbazaar.fee", auctionId)) {
			reason = "The auction fee could not be charged.";
			return false;
		}
		if (auctionId == 0 || !addHistoryInternal(auctionId, "created", accountId, playerId, getAuctionFee(),
		                                          "Character auction created.")) {
			reason = "The auction history could not be created.";
			return false;
		}
		return true;
	});

	if (!success) {
		if (reason.empty()) {
			reason = "The auction could not be created. Please try again.";
		}
		return false;
	}

	outAuctionId = auctionId;
	reason = fmt::format("Auction #{:d} created. You will now be logged out.", auctionId);
	// Deferred, so the Player object is still alive when this returns -- which
	// is what lets the Lua wire layer write the Bao Ledger snapshot for a
	// character that is about to become permanently unreachable.
	const uint32_t creatureId = player->getID();
	g_dispatcher.addTask([creatureId]() { g_game.kickPlayer(creatureId, true); });
	return true;
}

bool placeBid(uint32_t accountId, uint32_t auctionId, uint32_t amount, const std::string& operationId,
              std::string& reason)
{
	if (!isEnabled()) {
		reason = "The Character Bazaar is currently disabled.";
		return false;
	}
	if (accountId == 0) {
		reason = "You must be logged in to bid.";
		return false;
	}
	if (amount == 0) {
		reason = "Enter a bid of at least one Bp Coin.";
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
		if (auction.status != AUCTION_STATUS_ACTIVE) {
			reason = "That auction is no longer active.";
			return false;
		}
		if (static_cast<time_t>(auction.endAt) <= now) {
			reason = "That auction has already ended.";
			return false;
		}
		// Account-wide: an alt on the seller's account is still the seller.
		if (auction.sellerAccountId == accountId) {
			reason = "You cannot bid on your own auction.";
			return false;
		}
		const uint32_t minimum = getMinimumNextBid(auction.startPrice, auction.currentBid);
		if (auction.currentBid == UINT32_MAX) {
			reason = "This auction has reached the maximum bid.";
			return false;
		}
		if (amount < minimum) {
			reason = fmt::format("Your bid must be at least {:d} Bp Coins.", minimum);
			return false;
		}
		// The buyout price is a CEILING on bidding, not a suggestion. Without
		// this, a bid could climb past the buyout and the next buyer would pay
		// LESS than the standing bid -- the seller loses coins and the standing
		// bidder loses the character they were winning. Mirrors the identical
		// guard in ItemBazaar::placeBid.
		if (auction.buyoutPrice != 0 && amount >= auction.buyoutPrice) {
			reason = fmt::format("That amount reaches the Buy Now price of {:d} Bp Coins -- use Buy Now instead.",
			                     auction.buyoutPrice);
			return false;
		}

		// The bid row first: the ledger references it.
		if (!db.executeQuery(fmt::format(
		        "INSERT INTO `character_auction_bids` (`auction_id`, `bidder_account_id`, `bid_amount`, `created_at`) "
		        "VALUES ({:d}, {:d}, {:d}, {:d})",
		        auctionId, accountId, amount, now))) {
			reason = "Your bid could not be recorded.";
			return false;
		}
		const uint32_t bidId = static_cast<uint32_t>(db.getLastInsertId());
		if (bidId == 0) {
			reason = "Your bid could not be recorded.";
			return false;
		}

		// Release the standing bid first -- also when it is this account's own,
		// so raising one's own bid is the same path and never needs a top-up.
		if (auction.currentBidderAccountId != 0 && auction.currentBid != 0) {
			if (!Coins::credit(auction.currentBidderAccountId, auction.currentBid,
			                   bidMovement("charbazaar.release", bidId, operationId))) {
				reason = "The previous bid could not be released.";
				return false;
			}
		}
		if (!Coins::debit(accountId, amount, bidMovement("charbazaar.escrow", bidId, operationId))) {
			reason = "You do not have enough available Bp Coins for this bid.";
			return false;
		}

		time_t endAt = auction.endAt;
		const uint32_t window = getAntiSnipeSeconds();
		const bool extended = window > 0 && (endAt - now) < static_cast<time_t>(window);
		if (extended) {
			endAt = now + window;
		}

		// Guarded on the bid we read, so a concurrent bid that slipped past the
		// row lock (it cannot, but the guard makes that a fact rather than a
		// belief) fails the whole transaction instead of silently overwriting.
		if (!affectedExactlyOne(db, fmt::format(
		                                "UPDATE `character_auctions` SET `current_bid` = {:d}, "
		                                "`current_bidder_account_id` = {:d}, `end_at` = {:d} WHERE `id` = {:d} "
		                                "AND `status` = {:d} AND `current_bid` = {:d}",
		                                amount, accountId, endAt, auctionId, AUCTION_STATUS_ACTIVE, auction.currentBid))) {
			reason = "That auction changed while you were bidding. Please try again.";
			return false;
		}

		if (!addHistoryInternal(auctionId, extended ? "bid_antisnipe" : "bid", accountId, auction.playerId, amount,
		                        extended ? fmt::format("Bid placed; closing time reset to {:d} minutes.", window / 60)
		                                 : "Bid placed.")) {
			reason = "Your bid could not be recorded.";
			return false;
		}
		reason = extended ? fmt::format("Bid placed. The auction now closes in {:d} minutes unless someone outbids you.",
		                                window / 60)
		                  : "Bid placed. You are the highest bidder.";
		return true;
	});
}

bool buyNow(uint32_t accountId, uint32_t auctionId, const std::string& operationId, std::string& reason)
{
	if (!isEnabled()) {
		reason = "The Character Bazaar is currently disabled.";
		return false;
	}
	if (accountId == 0) {
		reason = "You must be logged in to buy a character.";
		return false;
	}

	const time_t currentTime = time(nullptr);
	return DBTransaction::executeWithinTransactionRollbackOnFailure([&]() {
		Database& db = Database::getInstance();
		const time_t now = time(nullptr);

		AuctionRecord auction;
		if (!lockAuction(auctionId, auction)) {
			reason = "That auction does not exist.";
			return false;
		}
		// The row lock plus this status check is what resolves two simultaneous
		// buyouts to exactly one winner: the loser only sees a non-ACTIVE
		// status once the winner's transaction has committed. It is also what
		// serialises a buyout against finalizeAuction, which takes the same
		// lock with `AND end_at <= now`.
		if (auction.status != AUCTION_STATUS_ACTIVE) {
			reason = "That auction is no longer active.";
			return false;
		}
		if (static_cast<time_t>(auction.endAt) <= now) {
			reason = "That auction has already ended.";
			return false;
		}
		if (auction.buyoutPrice == 0) {
			reason = "That auction has no Buy Now price.";
			return false;
		}
		// Account-wide: an alt on the seller's account is still the seller.
		if (auction.sellerAccountId == accountId) {
			reason = "You cannot buy your own listing.";
			return false;
		}

		// A buyout is recorded as the winning offer so that the bid history,
		// the bid count and the coin ledger all keep the shape they already
		// have -- every coin movement here references the BID row, exactly as
		// placeBid does, because coin_ledger's (ref_type, ref_id, kind) is
		// unique and an auction has many movements.
		if (!db.executeQuery(fmt::format(
		        "INSERT INTO `character_auction_bids` (`auction_id`, `bidder_account_id`, `bid_amount`, `created_at`) "
		        "VALUES ({:d}, {:d}, {:d}, {:d})",
		        auctionId, accountId, auction.buyoutPrice, now))) {
			reason = "The purchase could not be recorded.";
			return false;
		}
		const uint32_t bidId = static_cast<uint32_t>(db.getLastInsertId());
		if (bidId == 0) {
			reason = "The purchase could not be recorded.";
			return false;
		}

		// Refund whoever was winning BEFORE taking the buyer's coins, so a
		// buyer who cannot afford it leaves the standing bid untouched.
		if (auction.currentBidderAccountId != 0 && auction.currentBid != 0) {
			if (!Coins::credit(auction.currentBidderAccountId, auction.currentBid,
			                   bidMovement("charbazaar.release", bidId, operationId))) {
				reason = "The previous bid could not be released.";
				return false;
			}
		}
		if (!Coins::debit(accountId, auction.buyoutPrice, bidMovement("charbazaar.escrow", bidId, operationId))) {
			reason = "You do not have enough available Bp Coins to buy this character.";
			return false;
		}

		// The transfer and the payout, in the same order finalizeAuction uses.
		// This UPDATE is the sale: a listed character is locked out of the game
		// so no Player object exists to overwrite `account_id` at a later save,
		// and loadAccount re-reads the character list with no cache in front of
		// it -- so the character is on the buyer's account the instant this
		// transaction commits, with no server save involved.
		const uint64_t commission = static_cast<uint64_t>(auction.buyoutPrice) *
		                            std::min<uint32_t>(100, auction.commissionPercent) / 100;
		const uint64_t sellerPayout = auction.buyoutPrice - commission;
		if (!db.executeQuery(fmt::format(
		        "UPDATE `players` SET `account_id` = {:d} WHERE `id` = {:d} AND `account_id` = {:d}", accountId,
		        auction.playerId, auction.sellerAccountId)) ||
		    db.getAffectedRows() != 1) {
			reason = "The character could not be transferred.";
			return false;
		}
		if (!creditTransferableCoins(auction.sellerAccountId, sellerPayout, "charbazaar.payout", auctionId)) {
			reason = "The seller could not be paid.";
			return false;
		}

		if (!db.executeQuery(fmt::format(
		        "UPDATE `character_auctions` SET `status` = {:d}, `winner_account_id` = {:d}, `final_price` = {:d}, "
		        "`current_bid` = {:d}, `current_bidder_account_id` = {:d}, `finished_at` = {:d} "
		        "WHERE `id` = {:d} AND `status` = {:d}",
		        AUCTION_STATUS_FINISHED, accountId, auction.buyoutPrice, auction.buyoutPrice, accountId, currentTime,
		        auctionId, AUCTION_STATUS_ACTIVE))) {
			reason = "That auction was already settled.";
			return false;
		}

		if (!addHistoryInternal(auctionId, "buyout", accountId, auction.playerId, sellerPayout,
		                        fmt::format("Bought with Buy Now for {:d} coins (commission: {:d}).",
		                                    auction.buyoutPrice, commission))) {
			reason = "The purchase could not be recorded.";
			return false;
		}

		reason = fmt::format("{:s} is now on your account.", auction.playerName);
		return true;
	});
}

bool cancelAuction(uint32_t accountId, uint32_t auctionId, std::string& reason)
{
	if (accountId == 0) {
		reason = "You must be logged in.";
		return false;
	}
	return DBTransaction::executeWithinTransactionRollbackOnFailure([&]() {
		Database& db = Database::getInstance();
		AuctionRecord auction;
		if (!lockAuction(auctionId, auction)) {
			reason = "That auction does not exist.";
			return false;
		}
		if (auction.sellerAccountId != accountId) {
			reason = "Only the seller can withdraw a listing.";
			return false;
		}
		if (auction.status != AUCTION_STATUS_ACTIVE) {
			reason = "That auction is no longer active.";
			return false;
		}
		if (auction.currentBid != 0 || auction.currentBidderAccountId != 0) {
			reason = "A listing with a bid on it cannot be withdrawn.";
			return false;
		}
		if (!affectedExactlyOne(db, fmt::format(
		                                "UPDATE `character_auctions` SET `status` = {:d}, `finished_at` = {:d} "
		                                "WHERE `id` = {:d} AND `status` = {:d} AND `current_bid` = 0",
		                                AUCTION_STATUS_WITHDRAWN, time(nullptr), auctionId, AUCTION_STATUS_ACTIVE))) {
			reason = "That auction changed while you were withdrawing it. Please try again.";
			return false;
		}
		if (!addHistoryInternal(auctionId, "withdrawn", accountId, auction.playerId, 0,
		                        "Listing withdrawn by the seller before any bid.")) {
			reason = "The auction history could not be written.";
			return false;
		}
		reason = fmt::format("{:s} is no longer for sale and can log in again. The listing fee is not refunded.",
		                     auction.playerName);
		return true;
	});
}

void finalizeExpiredAuctions()
{
	// Disabling new activity must not strand existing character/coin escrow.
	const time_t currentTime = time(nullptr);
	auto result = Database::getInstance().storeQuery(fmt::format(
	    "SELECT `id` FROM `character_auctions` WHERE `status` = {:d} AND `end_at` <= {:d}", AUCTION_STATUS_ACTIVE,
	    currentTime));
	if (!result) {
		return;
	}

	do {
		const uint32_t auctionId = result->getNumber<uint32_t>("id");
		if (!finalizeAuction(auctionId)) {
			LOG_ERROR(fmt::format("[CharacterBazaar] Failed to finalize auction #{}.", auctionId));
		}
	} while (result->next());
}

void scheduleFinalization()
{
	g_scheduler.addEvent(FINALIZATION_INTERVAL_MS, []() {
		try {
			finalizeExpiredAuctions();
		} catch (const std::exception& exception) {
			LOG_ERROR(fmt::format("[CharacterBazaar] Exception during finalization: {}", exception.what()));
		} catch (...) {
			LOG_ERROR("[CharacterBazaar] Unknown exception during finalization.");
		}
		scheduleFinalization();
	});
}

} // namespace CharacterBazaar
