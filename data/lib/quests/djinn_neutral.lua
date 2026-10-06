-- "The Third Place at the Table" -- one neutral investigation that opens both
-- Djinn trading groups, replacing the mutually exclusive Marid/Efreet access
-- quests. Spec: docs/quest-reworks/12-djinn-build-plan.md, dialogue in
-- 03-djinn-owner-spoiler.md.
--
-- Melchior -> Umar -> Nah'Bob -> blue archive -> Ubaid -> Alesar -> Rata'Mari
-- -> Alesar -> Malor and Gabel in either order. Completing it is commerce with
-- both courts; it never records allegiance to either king and never writes the
-- old Faction/MaridFaction/EfreetFaction storages.

DjinnNeutral = {}

DjinnNeutral.MIN_LEVEL = 30

-- Reserved block 51160-51189. Scanned 2026-09-11, free.
DjinnNeutral.Storage = {
	introduced = 51160,
	blueVisitor = 51161,
	archiveAuthorised = 51162,
	archiveFound = 51163,
	greenVisitor = 51164,
	receivingAuthorised = 51165,
	receivingFound = 51166,
	witnessIntroduced = 51167,
	witnessFound = 51168,
	evidenceSettled = 51169,
	greenEndorsed = 51170,
	blueEndorsed = 51171,
	complete = 51172,

	genDispatch = 51175,
	genReceiving = 51176,
	genStrip = 51177,
	genUndertaking = 51178,
}

DjinnNeutral.FAMILY = "djinn"
DjinnNeutral.ACTION_ARCHIVE = 51179

function DjinnNeutral.has(player, flag)
	return player:getStorageValue(DjinnNeutral.Storage[flag], 0) >= 1
end

function DjinnNeutral.set(player, flag)
	player:setStorageValue(DjinnNeutral.Storage[flag], 1)
end

-- Access predicates (D0). Neither visitor flag confers trade.
function DjinnNeutral.blueAccess(player)
	return DjinnNeutral.has(player, "blueVisitor") or DjinnNeutral.has(player, "complete")
end

function DjinnNeutral.greenAccess(player)
	return DjinnNeutral.has(player, "greenVisitor") or DjinnNeutral.has(player, "complete")
end

function DjinnNeutral.audience(player)
	return DjinnNeutral.has(player, "evidenceSettled") or DjinnNeutral.has(player, "complete")
end

function DjinnNeutral.canTrade(player)
	return DjinnNeutral.has(player, "complete")
end

DjinnNeutral.Lines = {
	noTrade = "Both courts must record your undertaking before I can trade with you.",
	replaced = "Here is a certified replacement. The original copy no longer serves as proof.",
	tooLow = "The mountain roads are no place for you yet. Return at level 30 and we will discuss their hospitality.",
	noIntro = "You know a word, but not why you are using it. Speak to Melchior in Ankrahmun about our hospitality.",
	premature = "Settle the merchants' account before asking for my endorsement.",
	joint = "Both courts have recorded your undertaking. Their merchants will now trade with you. Keep your bargains in your own name.",
}

-- The word of greeting --------------------------------------------------------
--
-- The classic FocusModule registers only FOCUS_GREETWORDS ("hi", "hello");
-- FocusModule:addGreetMessage just stores words that init() never registers,
-- and FocusModule.onGreet calls onGreet(cid) without the text, so CALLBACK_GREET
-- never sees what was said. Every djinn's addGreetMessage('djanni\'hah') was
-- therefore inert, and the guards' greetCallback(cid, message) read a nil
-- message. This registers the word (both spellings) as a real greeting on one
-- NPC and returns a function the greet callback can ask: "did this greeting
-- use the word?".
function DjinnNeutral.addGreetingWord(keywordHandler, npcHandler)
	local usedWord = {}
	local function onWord(cid)
		if npcHandler:isFocused(cid) then
			return false
		end
		usedWord[cid] = true
		npcHandler:onGreet(cid)
		usedWord[cid] = nil
		return true
	end
	keywordHandler:addKeyword({ "djanni'hah" }, onWord)
	keywordHandler:addKeyword({ "djannihah" }, onWord)
	return function(cid)
		return usedWord[cid] == true
	end
end

-- Tokens ---------------------------------------------------------------------

local F = DjinnNeutral.FAMILY
local St = DjinnNeutral.Storage

DjinnNeutral.UndertakingText = "The bearer trades under their own name. They may carry goods and accounts between the courts, claim neither court's military protection beyond the permission given, and accept responsibility for their own bargains. C17 has been recorded as damaged on arrival, not as theft by either court."

-- The signatures are reconstructed from flags, never read off the scroll.
function DjinnNeutral.undertakingText(player)
	local green = DjinnNeutral.has(player, "greenEndorsed") and "Endorsed for Mal'ouquah: Malor." or "For Mal'ouquah: ____________"
	local blue = DjinnNeutral.has(player, "blueEndorsed") and "Endorsed for Ashta'daramai: Gabel." or "For Ashta'daramai: ____________"
	return DjinnNeutral.UndertakingText .. "\n\n" .. green .. "\n" .. blue
end

QuestTokens.define(F, "dispatch_copy", {
	itemId = 2834, genKey = St.genDispatch, name = "copy of the C17 dispatch entry",
	description = "Copied in the library of Ashta'daramai. Something is written on the reverse.",
	text = "C17. Six jars of lamp oil. Released to the carrier, seals intact. Signed at departure. Recipient's acceptance: not recorded on this page.\n\n"
		.. "On the reverse, copied from an older leaf in the same volume:\n"
		.. "An undertaking for the unpledged: a guest who carries an honest account may ask leave to trade in their own name. A court's signature binds its counters, not its swords. Each court must consent for itself.",
})
QuestTokens.define(F, "receiving_copy", {
	itemId = 2834, genKey = St.genReceiving, name = "copy of the C17 receiving record",
	description = "Alesar's receiving copy. The lower strip is missing.",
	text = "C17. Six jars arrived. Two split, four contaminated by leakage. Received for inspection...\n\nThe lower strip of the receipt is missing.",
})
-- Torn paper is stackable, so its identity rides in the writer string and its
-- words in the description (the base item is not readable).
QuestTokens.define(F, "receipt_strip", {
	itemId = 644, genKey = St.genStrip, identity = "writer", name = "torn receipt strip",
	description = "...not accepted as fulfilment of the order. Damage present on arrival. Carrier notified. Replacement or credit required.",
})
QuestTokens.define(F, "undertaking", {
	itemId = 2815, genKey = St.genUndertaking, name = "neutral undertaking",
	description = "An undertaking for an independent trader, with space for two endorsements.",
	text = function(player)
		return DjinnNeutral.undertakingText(player)
	end,
})

function DjinnNeutral.token(player, kind)
	return QuestTokens.find(player, F, kind)
end

function DjinnNeutral.give(player, kinds)
	local specs = {}
	for _, kind in ipairs(kinds) do
		specs[#specs + 1] = { F, kind }
	end
	return QuestTokens.give(player, specs)
end

-- Rewrite the carried scroll's annotation after an endorsement.
function DjinnNeutral.refreshUndertaking(player)
	local scroll = DjinnNeutral.token(player, "undertaking")
	if scroll then
		scroll:setAttribute(ITEM_ATTRIBUTE_TEXT, DjinnNeutral.undertakingText(player))
	end
end

-- The second endorsement, from whichever leader gives it. Records completion
-- exactly once; the scroll stays with the player as a keepsake.
function DjinnNeutral.endorse(player, flag)
	DjinnNeutral.set(player, flag)
	DjinnNeutral.refreshUndertaking(player)
	if DjinnNeutral.has(player, "greenEndorsed") and DjinnNeutral.has(player, "blueEndorsed")
		and not DjinnNeutral.has(player, "complete") then
		DjinnNeutral.set(player, "complete")
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Both courts have endorsed your undertaking. Nah'Bob, Haroun, Alesar and Yaman will trade with you.")
		return true
	end
	return false
end

-- Places ---------------------------------------------------------------------

DjinnNeutral.Position = {
	archive = Position(33100, 32524, 3),
}
DjinnNeutral.ArchiveBookcases = { [2436] = true, [2437] = true }

-- Door crossings (D8). Normal quest doors since 2026-10-06 (owner): an authorised player uses the
-- door from the public side and it opens; they walk through it themselves and it closes again
-- behind them. Anyone on the private side is always let out, and a refused player or a tailgater
-- who steps into the open doorway is pushed back. `key` is the door's action id and the storage
-- the generic closing_door handler checks for quest doors (it bounces anyone whose storage is -1). Sides and tiles
-- were read off the deployed map with a multi-floor route check
-- (docs/quest-reworks/implementation-evidence.md, "Door crossing matrix").
DjinnNeutral.Doors = {
	{ -- Ashta'daramai, east door of Umar's hall (quest door 1674, AID 0)
		pos = Position(33106, 32532, 6), axis = "x", closedId = 1674, openId = 1675, key = 51180,
		public = Position(33105, 32532, 6), private = Position(33107, 32532, 6),
		access = DjinnNeutral.blueAccess,
		deny = "The door seems to be sealed against unwanted intruders.",
	},
	{ -- Mal'ouquah, south door of Ubaid's hall (quest door 1676, AID 0)
		pos = Position(33047, 32626, 6), axis = "y", closedId = 1676, openId = 1677, key = 51181,
		public = Position(33047, 32625, 6), private = Position(33047, 32627, 6),
		access = DjinnNeutral.greenAccess,
		deny = "The door seems to be sealed against unwanted intruders.",
	},
	{ -- Mal'ouquah, lower level, the way to Rata'Mari. The map has a LOCKED door (1671, "It is locked.")
		-- here; it is swapped for the ordinary closed door 1672 at boot so it reads as a quest door
		pos = Position(33047, 32628, 7), axis = "y", closedId = 1672, openId = 1673, replaces = 1671, key = 51182,
		public = Position(33047, 32629, 7), private = Position(33047, 32627, 7),
		access = DjinnNeutral.greenAccess,
		deny = "The door seems to be sealed against unwanted intruders.",
	},
}

-- Quest log --------------------------------------------------------------------

function DjinnNeutral.logText(player)
	local has = function(flag) return DjinnNeutral.has(player, flag) end
	if has("complete") then
		return "Both courts have recorded your undertaking. Nah'Bob and Haroun in Ashta'daramai, and Alesar and Yaman in Mal'ouquah, trade with you in your own name. You are sworn to neither king, and their military quarters remain their own business."
	end
	if has("evidenceSettled") then
		local left = {}
		if not has("greenEndorsed") then
			left[#left + 1] = "Malor, at the top of Mal'ouquah"
		end
		if not has("blueEndorsed") then
			left[#left + 1] = "Gabel, at the top of Ashta'daramai"
		end
		return "Alesar set the C17 account beside the old undertaking. Ask for the endorsement of " .. table.concat(left, " and ") .. ", in either order, by speaking of your undertaking."
	end
	if has("witnessFound") then
		return "Rata'Mari gave you the missing strip of the receipt. Take the dispatch copy, the receiving copy and the strip to Alesar in Mal'ouquah and speak of the receipt."
	end
	if has("witnessIntroduced") then
		return "Alesar says the missing words of the receipt ended up in a rat's nest. Ask Rata'Mari, on the lower level of Mal'ouquah near the kitchens, about the missing words."
	end
	if has("receivingFound") then
		return "Alesar's receiving copy of C17 stops mid-sentence. Ask him about the missing words."
	end
	if has("greenVisitor") then
		return "Ubaid lets you reach the public halls of Mal'ouquah. Ask Alesar about the account."
	end
	if has("archiveFound") then
		return "The blue record proves dispatch, not acceptance. Speak to Ubaid at Mal'ouquah as a guest, then ask Alesar for the receiving record."
	end
	if has("archiveAuthorised") then
		return "Nah'Bob lets you copy the C17 dispatch entry. Look for the dispatch record in the southern row of the library, one floor below his counter in Ashta'daramai."
	end
	if has("blueVisitor") then
		return "Umar has let you into the public halls of Ashta'daramai. Ask Nah'Bob for a trade and explain that you are a neutral trader."
	end
	return "Melchior taught you the word of greeting, djanni'hah, and how to ask for hospitality. Go to Umar at Ashta'daramai, the blue fortress in the Kha'zeel mountains, and ask to be received as a guest."
end

return DjinnNeutral
