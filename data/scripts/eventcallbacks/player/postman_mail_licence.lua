-- The postal licence (10-postman-build-plan.md, P7): sending mail needs
-- "Return to Sender"; receiving never does.
--
-- Mail only ever leaves a player one way: a parcel or letter dragged or thrown
-- onto a tile holding a mailbox (Mailbox::queryAdd accepts nothing else).
-- Player:onMoveItem runs for exactly that, with the acting player, BEFORE the
-- engine moves anything -- so a refusal leaves the item where it was and
-- nothing is lost. The engine's own internal moves (Mailbox::sendItem into
-- the recipient's inbox) do not pass through here, so delivery, offline
-- recipients, the stamped transform and the sender save in
-- default_onItemMoved.lua are untouched. Mailboxes are recognised by item
-- type, never by the 230 audited positions, so new ones inherit the rule.
--
-- Registered first (trigger index -100): default_onMoveItem.lua returns `true`
-- on map moves, which ends the callback chain for everything after it.
--
-- Two quest rules ride along because they are the same kind of refusal:
-- quest tokens never go into the mail (Sam's reply belongs to Benjamin's
-- supervised dispatch, not a player called Kevin), and quest bags never
-- take the player's own belongings in (09-build-contract.md).

local MAIL_ITEMS = {
	[ITEM_PARCEL] = true,
	[ITEM_LETTER] = true,
}

local function refuse(player, text)
	-- An event message, not a cancel: the engine answers a refused move with
	-- its own cancel text, which would overwrite ours in the status bar.
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
	return RETURNVALUE_NOTPOSSIBLE
end

local function isSamReply(item)
	local info = QuestTokens.info(item)
	if info and info.family == PostmanRework.FAMILY and info.kind == "sam_reply" then
		return true
	end
	if item:isContainer() then
		for _, sub in ipairs(item:getItems(true)) do
			if isSamReply(sub) then
				return true
			end
		end
	end
	return false
end

local event = Event()

event.onMoveItem = function(self, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if toCylinder and toCylinder.isItem and toCylinder:isItem() and QuestTokens.isToken(toCylinder) then
		return refuse(self, "That bag carries a quest delivery. Keep your own belongings elsewhere.")
	end

	if not item or not MAIL_ITEMS[item:getId()] then
		return RETURNVALUE_NOERROR
	end
	if toPosition.x == 0xFFFF then
		return RETURNVALUE_NOERROR -- into a container or an inventory slot
	end
	local tile = Tile(toPosition)
	if not tile or not tile:getItemByType(ITEM_TYPE_MAILBOX) then
		return RETURNVALUE_NOERROR
	end

	if QuestTokens.containsToken(item) then
		-- Dropping Sam's reply itself on Benjamin's supervised mailbox is the natural gesture,
		-- so it completes the dispatch exactly like using the mailbox does
		local box = PostmanRework.Position.trialMailbox
		if toPosition.x == box.x and toPosition.y == box.y and toPosition.z == box.z
				and PostmanRework.stage(self) == PostmanRework.Stage.SUPERVISED then
			local reply = item
			if QuestTokens.isValid(self, reply, PostmanRework.FAMILY, "sam_reply") then
				local ok = QuestTokens.exchange(self, { reply }, { { PostmanRework.FAMILY, "dispatch_receipt" } })
				if not ok then
					return refuse(self, "You have no room for the dispatch receipt. Make room and drop the reply again.")
				end
				PostmanRework.setStage(self, PostmanRework.Stage.DISPATCHED)
				box:sendMagicEffect(CONST_ME_MAGIC_BLUE)
				self:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The reply slips into the collection bag. You receive a stamped dispatch receipt.")
				self:saveOnTransfer("quest.postman")
				return RETURNVALUE_NOTPOSSIBLE -- nothing is actually mailed; the reply was swapped for the receipt
			end
		end
		if isSamReply(item) then
			return refuse(self, "This reply belongs to a supervised dispatch. Follow Benjamin's instructions at the Thais post office.")
		end
		return refuse(self, "Quest papers stay with you. They cannot be sent by mail.")
	end

	if not PostmanRework.canSendMail(self) then
		return refuse(self, "You need a postal licence to send mail. Speak to Kevin at the postal headquarters.")
	end
	return RETURNVALUE_NOERROR
end

event:register(-100)
