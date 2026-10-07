// Copyright 2023 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#include "otpch.h"

#include "depotchest.h"

#include "tools.h"

DepotChest::DepotChest(uint16_t type) : Container(type, DEPOT_BOX_COUNT) {}

uint32_t DepotChest::getStoredItemCount() const
{
	uint32_t boxes = 0;
	for (const auto& item : itemlist) {
		if (item->getID() >= ITEM_DEPOT_BOX_1 && item->getID() <= ITEM_DEPOT_BOX_LAST) {
			++boxes;
		}
	}
	return getItemHoldingCount() - boxes;
}

ReturnValue DepotChest::queryStoredLimit(const Item& item, uint32_t count) const
{
	uint32_t addCount = 1;
	if (isHoldingItem(&item)) {
		// a move inside this depot only adds an item when it splits a stack
		addCount = (item.isStackable() && item.getItemCount() != count) ? 1 : 0;
	} else if (const Container* container = item.getContainer()) {
		addCount = container->getItemHoldingCount() + 1;
	}

	if (getStoredItemCount() + addCount > maxDepotItems) {
		return RETURNVALUE_DEPOTISFULL;
	}
	return RETURNVALUE_NOERROR;
}

ReturnValue DepotChest::queryAdd(int32_t index, const Thing& thing, uint32_t count, uint32_t flags,
                                 Creature* actor /* = nullptr*/) const
{
	const Item* item = thing.getItem();
	if (item == nullptr) {
		return RETURNVALUE_NOTPOSSIBLE;
	}

	if (!hasBitSet(FLAG_NOLIMIT, flags)) {
		const ReturnValue ret = queryStoredLimit(*item, count);
		if (ret != RETURNVALUE_NOERROR) {
			return ret;
		}
	}

	return Container::queryAdd(index, thing, count, flags, actor);
}

ReturnValue DepotChest::queryRemove(const Thing& thing, uint32_t count, uint32_t flags,
                                    Creature* actor /* = nullptr */) const
{
	const Item* item = thing.getItem();
	if (item && item->getID() >= ITEM_DEPOT_BOX_1 && item->getID() <= ITEM_DEPOT_BOX_LAST) {
		return RETURNVALUE_NOTPOSSIBLE;
	}

	return Container::queryRemove(thing, count, flags, actor);
}

Cylinder* DepotChest::queryDestination(int32_t& index, const Thing& thing, Item** destItem, uint32_t& flags,
                                       uint32_t destinationInstanceId)
{
	const Item* item = thing.getItem();
	if (item && item->getID() >= ITEM_DEPOT_BOX_1 && item->getID() <= ITEM_DEPOT_BOX_LAST) {
		return Container::queryDestination(index, thing, destItem, flags, destinationInstanceId);
	}

	if (index == INDEX_WHEREEVER) {
		for (const auto& it : itemlist) {
			if (it->getID() >= ITEM_DEPOT_BOX_1 && it->getID() <= ITEM_DEPOT_BOX_LAST) {
				Container* box = it->getContainer();
				if (box && box->size() < box->capacity() * DEPOT_BOX_MAX_PAGES) {
					index = INDEX_WHEREEVER;
					*destItem = nullptr;
					return box->queryDestination(index, thing, destItem, flags, destinationInstanceId);
				}
			}
		}
	}

	return Container::queryDestination(index, thing, destItem, flags, destinationInstanceId);
}

void DepotChest::postAddNotification(Thing* thing, const Cylinder* oldParent, int32_t index, cylinderlink_t)
{
	Cylinder* parent = getParent();
	if (parent != nullptr) {
		parent->postAddNotification(thing, oldParent, index, LINK_PARENT);
	}

	save = true;
}

void DepotChest::postRemoveNotification(Thing* thing, const Cylinder* newParent, int32_t index, cylinderlink_t)
{
	Cylinder* parent = getParent();
	if (parent != nullptr) {
		parent->postRemoveNotification(thing, newParent, index, LINK_PARENT);
	}

	save = true;
}

DepotBox::DepotBox(uint16_t type) : Container(type) {}

ReturnValue DepotBox::queryAdd(int32_t index, const Thing& thing, uint32_t count, uint32_t flags,
                               Creature* actor /* = nullptr*/) const
{
	const Item* item = thing.getItem();
	if (item && item->getParent() != this && !hasBitSet(FLAG_NOLIMIT, flags) &&
	    size() >= capacity() * DEPOT_BOX_MAX_PAGES) {
		return RETURNVALUE_CONTAINERNOTENOUGHROOM;
	}

	return Container::queryAdd(index, thing, count, flags, actor);
}

/*Cylinder* DepotChest::getParent() const
{
    if (parent) {
        return parent->getParent();
    }
    return nullptr;
}*/
