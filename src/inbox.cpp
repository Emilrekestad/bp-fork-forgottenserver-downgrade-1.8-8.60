// Copyright 2026 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#include "otpch.h"

#include "inbox.h"
#include "iologindata.h"
#include "tools.h"

Inbox::Inbox(uint16_t type) : Container(type) {}

ReturnValue Inbox::queryAdd(int32_t, const Thing& thing, uint32_t,
		uint32_t flags, Creature* actor) const
{
	if (actor && !hasBitSet(FLAG_NOLIMIT, flags)) {
		return RETURNVALUE_NOTPOSSIBLE;
	}

	if (!hasBitSet(FLAG_NOLIMIT, flags)) {
		return RETURNVALUE_CONTAINERNOTENOUGHROOM;
	}

	const Item* item = thing.getItem();
	if (!item) {
		return RETURNVALUE_NOTPOSSIBLE;
	}

	if (item == this) {
		return RETURNVALUE_THISISIMPOSSIBLE;
	}

	if (!item->isPickupable()) {
		return RETURNVALUE_CANNOTPICKUP;
	}

	// IOLoginData::savePlayer writes only the first INBOX_SAVE_LIMIT entries
	// and silently DESTROYS the rest (the oldest, since new items are pushed
	// to the front). Without this cap, 101 cheap letters mailed to a victim
	// deleted their oldest inbox items at the next save. Refusing here covers
	// every delivery path that goes through the engine (mail, market, bazaar
	// withdrawal, loot-chest overflow); loading bypasses queryAdd, so rows
	// already in the database are unaffected.
	if (item->getParent() != this && size() >= IOLoginData::INBOX_SAVE_LIMIT) {
		return RETURNVALUE_CONTAINERNOTENOUGHROOM;
	}

	return RETURNVALUE_NOERROR;
}

void Inbox::postAddNotification(Thing* thing, const Cylinder* oldParent, int32_t index, cylinderlink_t)
{
	Cylinder* parent = getParent();
	if (parent != nullptr) {
		parent->postAddNotification(thing, oldParent, index, LINK_PARENT);
	}
}

void Inbox::postRemoveNotification(Thing* thing, const Cylinder* newParent, int32_t index, cylinderlink_t)
{
	Cylinder* parent = getParent();
	if (parent != nullptr) {
		parent->postRemoveNotification(thing, newParent, index, LINK_PARENT);
	}
}

Cylinder* Inbox::getParent() const
{
	return parent;
}
