-- Personal quest tokens for the 2026-09-11 access quests ("Return to Sender",
-- "The Price of a Good Name", "The Third Place at the Table") and the hireling
-- quest's flintstone. Spec: docs/quest-reworks/09-build-contract.md,
-- "Persisted token contract".
--
-- A token is an ordinary item with existing art. What makes it a token is a
-- server-written identity: family, kind, owner GUID and issue generation. It
-- counts only while its owner is the one holding it AND its generation equals
-- the generation stored on that player for (family, kind). Every reissue bumps
-- the stored generation, so a copy left in a depot or handed to a friend stops
-- counting the moment a replacement exists. Names, descriptions and letter
-- text are cosmetic; nothing here reads them back.
--
-- Where the identity lives depends on the base item, because of an engine
-- trap: Item::equalsIgnoringInstance (src/item.cpp) compares every non-string
-- attribute with std::get<int64_t>, and custom attributes are stored as a map.
-- Two STACKABLE items that both carry custom attributes would therefore throw
-- bad_variant_access the moment the engine tried to stack them -- which it
-- does on every addItemEx and on every drag onto a matching item. So:
--   * non-stackable bases (documents, letters, scrolls, bags, the flintstone)
--     carry the identity as custom attributes bq.family/kind/owner/gen;
--   * stackable bases (torn paper 644, cloth 5913) carry it as a string in
--     ITEM_ATTRIBUTE_WRITER, which the engine compares as a string and which
--     no player can rewrite on an item that is not writeable.
--
-- Loaded from data/lib/lib.lua, so NPC scripts (npc interface) and actions,
-- movements and globalevents (scripts interface) share one definition.

QuestTokens = {}
QuestTokens.kinds = {}

-- Shared failure lines (09-build-contract.md, "Dialogue contract").
QuestTokens.Lines = {
	fullInventory = "Make room for what I need to hand you. I will keep everything as it is until then.",
	wrongProof = "That is not the record issued for your work. Ask for a replacement if yours is missing.",
	alreadyDone = "That business is already settled. You need not do it again.",
	noAssignment = "We have no business of that kind underway. Ask about your mission first.",
	bagNotEmpty = "Empty your own belongings from that bag before handing it over.",
}

local ATTR_FAMILY, ATTR_KIND, ATTR_OWNER, ATTR_GEN = "bq.family", "bq.kind", "bq.owner", "bq.gen"

-- def = {
--   itemId, genKey (player storage holding the current generation),
--   identity = "custom" (default) or "writer" (stackable bases),
--   name, article, description, text   -- string or function(player, spec)
--   actionId                            -- optional, for tokens that are used
-- }
function QuestTokens.define(family, kind, def)
	assert(def.itemId and def.genKey, "QuestTokens.define needs itemId and genKey")
	def.family, def.kind = family, kind
	def.identity = def.identity or "custom"
	QuestTokens.kinds[family] = QuestTokens.kinds[family] or {}
	QuestTokens.kinds[family][kind] = def
	return def
end

function QuestTokens.getDef(family, kind)
	local defs = QuestTokens.kinds[family]
	local def = defs and defs[kind]
	if not def then
		error(string.format("QuestTokens: unknown token %s/%s", tostring(family), tostring(kind)))
	end
	return def
end

-- Identity of any item, or nil when it is not a quest token.
function QuestTokens.info(item)
	if not item or not item.getCustomAttribute then
		return nil
	end
	local family = item:getCustomAttribute(ATTR_FAMILY)
	if family then
		return {
			family = family,
			kind = item:getCustomAttribute(ATTR_KIND),
			owner = tonumber(item:getCustomAttribute(ATTR_OWNER)) or 0,
			gen = tonumber(item:getCustomAttribute(ATTR_GEN)) or 0,
		}
	end
	local writer = item:getAttribute(ITEM_ATTRIBUTE_WRITER)
	if type(writer) == "string" then
		local f, k, o, g = writer:match("^bq:([^:]+):([^:]+):(%d+):(%d+)$")
		if f then
			return { family = f, kind = k, owner = tonumber(o), gen = tonumber(g) }
		end
	end
	return nil
end

function QuestTokens.isToken(item)
	return QuestTokens.info(item) ~= nil
end

function QuestTokens.generation(player, family, kind)
	local value = player:getStorageValue(QuestTokens.getDef(family, kind).genKey, 0)
	return value > 0 and value or 0
end

function QuestTokens.isValid(player, item, family, kind)
	local info = QuestTokens.info(item)
	return info ~= nil and info.family == family and info.kind == kind and info.owner == player:getGuid()
		and info.gen > 0 and info.gen == QuestTokens.generation(player, family, kind)
end

local function isCarriedBy(item, player)
	if not item then
		return false
	end
	-- Item has no isRemoved() method in Lua (only Creature does); a removed item
	-- raises when it is used, so look at its top parent under pcall instead.
	local ok, top = pcall(item.getTopParent, item)
	if not ok then
		return false
	end
	return top ~= nil and top.isPlayer ~= nil and top:isPlayer() and top:getId() == player:getId()
end
QuestTokens.isCarriedBy = isCarriedBy

-- Everything the player carries: equipped items and, recursively, the
-- contents of every equipped container. With ignoreEquipped the equipped
-- items themselves are skipped but container contents still count -- the
-- same rule Player::removeItemOfType uses for shop sales.
function QuestTokens.carried(player, ignoreEquipped)
	local list = {}
	-- CONST_SLOT_FIRST / CONST_SLOT_LAST are C++ only; Lua has the named slots
	for slot = CONST_SLOT_HEAD, CONST_SLOT_AMMO do
		local item = player:getSlotItem(slot)
		if item then
			if not ignoreEquipped then
				list[#list + 1] = item
			end
			if item:isContainer() then
				for _, sub in ipairs(item:getItems(true)) do
					list[#list + 1] = sub
				end
			end
		end
	end
	return list
end

-- The single valid token of this kind the player carries, if any.
function QuestTokens.find(player, family, kind)
	for _, item in ipairs(QuestTokens.carried(player)) do
		if QuestTokens.isValid(player, item, family, kind) then
			return item
		end
	end
	return nil
end

-- Every carried item of this family/kind, valid or stale.
function QuestTokens.findAll(player, family, kind)
	local found = {}
	for _, item in ipairs(QuestTokens.carried(player)) do
		local info = QuestTokens.info(item)
		if info and info.family == family and info.kind == kind then
			found[#found + 1] = item
		end
	end
	return found
end

local function resolve(value, player, spec)
	if type(value) == "function" then
		return value(player, spec)
	end
	return value
end

local function build(player, def, gen, spec)
	local item = Game.createItem(def.itemId, 1)
	if not item then
		return nil
	end
	local guid = player:getGuid()
	if def.identity == "writer" then
		item:setAttribute(ITEM_ATTRIBUTE_WRITER, string.format("bq:%s:%s:%d:%d", def.family, def.kind, guid, gen))
	else
		item:setCustomAttribute(ATTR_FAMILY, def.family)
		item:setCustomAttribute(ATTR_KIND, def.kind)
		item:setCustomAttribute(ATTR_OWNER, guid)
		item:setCustomAttribute(ATTR_GEN, gen)
	end
	local name = resolve(def.name, player, spec)
	if name then
		item:setAttribute(ITEM_ATTRIBUTE_NAME, name)
	end
	local article = resolve(def.article, player, spec)
	if article then
		item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, article)
	end
	local description = resolve(def.description, player, spec)
	if description then
		item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, description)
	end
	local text = resolve(def.text, player, spec)
	if text then
		item:setAttribute(ITEM_ATTRIBUTE_TEXT, text)
	end
	if def.actionId then
		item:setActionId(def.actionId)
	end
	return item
end

-- Issue one or more tokens, all or nothing. specs = { {family, kind}, ... }.
-- Every item is built and placed before any generation is written: if one
-- does not fit, the ones already placed are taken back and nothing changes,
-- so a full backpack never invalidates the token the player still holds.
-- Storage values and inventory are saved together by the engine, so a crash
-- rolls both back to the same save point.
function QuestTokens.give(player, specs)
	local built, placed, gens = {}, {}, {}
	for index, spec in ipairs(specs) do
		local def = QuestTokens.getDef(spec[1], spec[2])
		local key = def.family .. "/" .. def.kind
		local gen = (gens[key] or QuestTokens.generation(player, def.family, def.kind)) + 1
		gens[key] = gen
		local item = build(player, def, gen, spec)
		if not item then
			return false, "create"
		end
		built[index] = { item = item, def = def, gen = gen }
	end
	for _, entry in ipairs(built) do
		if player:addItemEx(entry.item, false) ~= RETURNVALUE_NOERROR then
			for _, done in ipairs(placed) do
				done:remove()
			end
			return false, "full"
		end
		placed[#placed + 1] = entry.item
	end
	for _, entry in ipairs(built) do
		player:setStorageValue(entry.def.genKey, entry.gen)
	end
	return true, placed
end

-- Swap validated input tokens for new ones. Outputs are placed first; the
-- inputs are only removed once every output fits. On failure nothing moves.
function QuestTokens.exchange(player, inputs, outputs)
	for _, item in ipairs(inputs) do
		if not isCarriedBy(item, player) then
			return false, "missing"
		end
	end
	if outputs and #outputs > 0 then
		local ok, result = QuestTokens.give(player, outputs)
		if not ok then
			return false, result
		end
		for _, item in ipairs(inputs) do
			item:remove()
		end
		return true, result
	end
	for _, item in ipairs(inputs) do
		item:remove()
	end
	return true, {}
end

-- True when this item is a token or (for containers) holds one anywhere.
function QuestTokens.containsToken(item)
	if QuestTokens.isToken(item) then
		return true
	end
	if item and item.isContainer and item:isContainer() then
		for _, sub in ipairs(item:getItems(true)) do
			if QuestTokens.isToken(sub) then
				return true
			end
		end
	end
	return false
end

-- A quest bag must be handed back empty: the player's own belongings never
-- ride along into an NPC's hands.
function QuestTokens.isEmptyBag(item)
	return not item:isContainer() or item:getSize() == 0
end

-- Run grant() exactly once per player for this storage key.
function QuestTokens.completeOnce(player, storageKey, grant)
	if player:getStorageValue(storageKey, 0) >= 1 then
		return false
	end
	player:setStorageValue(storageKey, 1)
	if grant then
		grant(player)
	end
	return true
end

-- Shop sale guard. Every sell path (classic ShopModule, RevScript NpcShop and
-- the crystal compatibility shop) calls this instead of player:removeItem, so
-- a quest token can never be turned into gold -- not even by accident when an
-- ordinary document or cloth of the same base id is being sold beside it.
-- Players who hold no token of that id take the untouched engine path.
function QuestTokens.removeForSale(player, itemId, amount, subType, ignoreEquipped)
	local carried = QuestTokens.carried(player, ignoreEquipped)
	local holdsToken = false
	for _, item in ipairs(carried) do
		if item:getId() == itemId and QuestTokens.isToken(item) then
			holdsToken = true
			break
		end
	end
	if not holdsToken then
		return player:removeItem(itemId, amount, subType, ignoreEquipped)
	end

	local ordinary, available = {}, 0
	for _, item in ipairs(carried) do
		if item:getId() == itemId and not QuestTokens.isToken(item)
			and (subType == nil or subType < 0 or item:getSubType() == subType) then
			ordinary[#ordinary + 1] = item
			available = available + math.max(1, item:getCount())
		end
	end
	if available < amount then
		return false
	end
	local left = amount
	for _, item in ipairs(ordinary) do
		if left <= 0 then
			break
		end
		local count = math.max(1, item:getCount())
		local take = math.min(count, left)
		if take >= count then
			item:remove()
		else
			item:remove(take)
		end
		left = left - take
	end
	return true
end

return QuestTokens
