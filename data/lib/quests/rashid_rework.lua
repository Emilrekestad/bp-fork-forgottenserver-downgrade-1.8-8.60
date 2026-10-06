-- "The Price of a Good Name" -- Rashid's travelling week, replacing the old
-- Travelling Trader errands. Spec: docs/quest-reworks/11-rashid-build-plan.md,
-- dialogue in 02-rashid-owner-spoiler.md.
--
-- Six weekday commissions with independent stamps, a Sunday meeting as the
-- seventh, one Sunday catch-up per UTC date, and recognition -- trade access
-- to Rashid, nothing else -- once all seven are recorded. Rashid himself moves
-- between seven existing taverns on a UTC calendar
-- (data/scripts/globalevents/quests/rashid_schedule.lua).
--
-- Shared by Rashid, Dankwart, Lyonel, Clyde, Arito, Miraia, Willard and
-- Mirabell (npc interface) and by the sample-case action, the scheduler and the
-- quest log (scripts interface).

RashidRework = {}

-- Reserved block 51120-51159. Scanned 2026-09-11, free.
RashidRework.Storage = {
	enrolled = 51120,
	mon = 51121,
	tue = 51122,
	wed = 51123,
	thu = 51124,
	fri = 51125,
	sat = 51126,
	sunMeeting = 51127,
	trusted = 51128,
	catchupDate = 51129, -- UTC YYYYMMDD of the last Sunday catch-up
	catchupTask = 51130, -- 1..6, the day it authorised
	thuConsulted = 51131,
	clydePermission = 51132,
	caseRetrieved = 51133,
	wrapped = 51134,
	miraiaConsulted = 51135,
	willardIssued = 51136,

	genMonBill = 51140,
	genMonCorrected = 51141,
	genTueReceipt = 51142,
	genTueCorrection = 51143,
	genWedCloth = 51144,
	genWedCase = 51145,
	genFriInstruction = 51146,
	genFriCancelled = 51147,
	genSatOrder = 51148,
	genSatReceipt = 51149,

	-- Collector commissions (2026-10-04): Monday..Saturday task value 0/1/3
	cmon = 51150,
	ctue = 51151,
	cwed = 51152,
	cthu = 51153,
	cfri = 51154,
	csat = 51155,
}

-- Per-day task value.
RashidRework.Task = {
	UNSET = 0, -- not accepted
	ACCEPTED = 1,
	READY = 2, -- the supporting NPC has done their part; report to Rashid
	REPORTED = 3, -- stamped
}

-- The six weekday collections (owner, 2026-10-04). Item ids are this server's own (checked in
-- items.xml); every item has monsters that drop it (checked against the loot tables).
RashidRework.Collections = {
	mon = { { id = 10196, count = 10, name = "orc teeth" }, { id = 5897, count = 8, name = "wolf paws" }, { id = 5894, count = 8, name = "bat wings" } },
	tue = { { id = 5881, count = 10, name = "lizard scales" }, { id = 5876, count = 8, name = "lizard leathers" }, { id = 5878, count = 15, name = "minotaur leathers" } },
	wed = { { id = 3032, count = 10, name = "small emeralds" }, { id = 3029, count = 10, name = "small sapphires" }, { id = 3033, count = 10, name = "small amethysts" } },
	thu = { { id = 9657, count = 10, name = "cyclops toes" }, { id = 5896, count = 4, name = "bear paws" }, { id = 10321, count = 2, name = "mammoth tusks" } },
	fri = { { id = 3583, count = 12, name = "dragon hams" }, { id = 9644, count = 8, name = "wyvern talismans" } },
	sat = { { id = 5954, count = 2, name = "demon horns" }, { id = 6499, count = 10, name = "demonic essences" }, { id = 5882, count = 2, name = "red dragon scales" } },
}

function RashidRework.ctask(player, dayKey)
	local value = player:getStorageValue(RashidRework.Storage["c" .. dayKey], 0)
	return value > 0 and value or 0
end

function RashidRework.cset(player, dayKey, value)
	player:setStorageValue(RashidRework.Storage["c" .. dayKey], value)
end

-- "10 orc teeth, 8 wolf paws and 8 bat wings"
function RashidRework.wantText(dayKey)
	local parts = {}
	for _, entry in ipairs(RashidRework.Collections[dayKey]) do
		parts[#parts + 1] = entry.count .. " " .. entry.name
	end
	if #parts == 1 then
		return parts[1]
	end
	return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

-- What the player still has to bring: { "3 more orc teeth", ... }
function RashidRework.missing(player, dayKey)
	local list = {}
	for _, entry in ipairs(RashidRework.Collections[dayKey]) do
		local short = entry.count - player:getItemCount(entry.id)
		if short > 0 then
			list[#list + 1] = short .. " more " .. entry.name
		end
	end
	return list
end

-- "orc teeth 3/10, wolf paws 8/8, bat wings 0/8"
function RashidRework.progressText(player, dayKey)
	local parts = {}
	for _, entry in ipairs(RashidRework.Collections[dayKey]) do
		parts[#parts + 1] = string.format("%s %d/%d", entry.name, math.min(player:getItemCount(entry.id), entry.count), entry.count)
	end
	return table.concat(parts, ", ")
end

-- Removes the goods. Re-checks first so a race with the player moving items cannot take half.
function RashidRework.takeCollection(player, dayKey)
	if #RashidRework.missing(player, dayKey) > 0 then
		return false
	end
	for _, entry in ipairs(RashidRework.Collections[dayKey]) do
		if not player:removeItem(entry.id, entry.count) then
			return false
		end
	end
	return true
end

RashidRework.FAMILY = "rashid"
RashidRework.ACTION_SAMPLE_CASE = 51137

-- Monday..Saturday, in calendar order. `wday` is os.date's weekday (Sunday = 1).
RashidRework.Days = {
	{ key = "mon", wday = 2, name = "Monday", town = "Svargrond", host = "Dankwart" },
	{ key = "tue", wday = 3, name = "Tuesday", town = "Liberty Bay", host = "Lyonel" },
	{ key = "wed", wday = 4, name = "Wednesday", town = "Port Hope", host = "Clyde" },
	{ key = "thu", wday = 5, name = "Thursday", town = "Ankrahmun", host = "Arito" },
	{ key = "fri", wday = 6, name = "Friday", town = "Darashia", host = "Miraia" },
	{ key = "sat", wday = 7, name = "Saturday", town = "Edron", host = "Willard" },
}
RashidRework.DayByKey = {}
RashidRework.DayByWday = {}
for index, day in ipairs(RashidRework.Days) do
	day.index = index
	RashidRework.DayByKey[day.key] = day
	RashidRework.DayByWday[day.wday] = day
end

-- Rashid now stays at one spot every day (owner, 2026-10-04: 32225,31704,7, where Lothar used to
-- be). The weekly schedule below keeps its day entries because the daily COMMISSIONS still follow
-- the calendar, but every stop is the same place. The one immutable schedule (11-rashid-build-plan.md, R1). Fallbacks are the
-- adjacent customer-area tiles on the same floor, read off the deployed map
-- (tools/quest-audit/evidence.json): nonblocking, not a house tile.
RashidRework.Schedule = {
	[2] = { day = "Monday", town = "Svargrond", host = "Dankwart", pos = Position(32225, 31704, 7),
		fallback = { Position(32226, 31704, 7), Position(32224, 31704, 7) } },
	[3] = { day = "Tuesday", town = "Liberty Bay", host = "Lyonel", pos = Position(32225, 31704, 7),
		fallback = { Position(32226, 31704, 7), Position(32224, 31704, 7) } },
	[4] = { day = "Wednesday", town = "Port Hope", host = "Clyde", pos = Position(32225, 31704, 7),
		fallback = { Position(32226, 31704, 7), Position(32224, 31704, 7) } },
	[5] = { day = "Thursday", town = "Ankrahmun", host = "Arito", pos = Position(32225, 31704, 7),
		fallback = { Position(32226, 31704, 7), Position(32224, 31704, 7) } },
	[6] = { day = "Friday", town = "Darashia", host = "Miraia", pos = Position(32225, 31704, 7),
		fallback = { Position(32226, 31704, 7), Position(32224, 31704, 7) } },
	[7] = { day = "Saturday", town = "Edron", host = "Mirabell", pos = Position(32225, 31704, 7),
		fallback = { Position(32226, 31704, 7), Position(32224, 31704, 7) } },
	[1] = { day = "Sunday", town = "Carlin", host = "Liane", pos = Position(32225, 31704, 7),
		fallback = { Position(32226, 31704, 7), Position(32224, 31704, 7) } },
}

-- Where the scheduler actually managed to put Rashid (nil until it has).
-- Written only by the scheduler; the journal reads it so it never claims a
-- city he failed to reach.
RashidRework.current = nil

-- UTC calendar, explicitly: never the host's local %w.
function RashidRework.utcWday()
	return os.date("!*t").wday
end

function RashidRework.utcDate()
	return tonumber(os.date("!%Y%m%d"))
end

function RashidRework.isSunday()
	return RashidRework.utcWday() == 1
end

function RashidRework.today()
	return RashidRework.DayByWday[RashidRework.utcWday()]
end

local function get(player, key)
	local value = player:getStorageValue(RashidRework.Storage[key], 0)
	return value > 0 and value or 0
end
RashidRework.get = get

function RashidRework.set(player, key, value)
	player:setStorageValue(RashidRework.Storage[key], value)
end

function RashidRework.isEnrolled(player)
	return get(player, "enrolled") >= 1
end

function RashidRework.isTrusted(player)
	return get(player, "trusted") >= 1
end

function RashidRework.task(player, dayKey)
	return get(player, dayKey)
end

-- Reported days are stamps. Thursday has no token: consulting Arito makes it
-- READY, answering Rashid stamps it.
function RashidRework.allSixReported(player)
	for _, day in ipairs(RashidRework.Days) do
		if RashidRework.ctask(player, day.key) < RashidRework.Task.REPORTED then
			return false
		end
	end
	return true
end

RashidRework.RecognitionLine = "You brought me many kinds of goods. Now I know you. Your name goes in my ledger, and I will buy from you."

-- Idempotent. Returns true only on the call that grants recognition.
function RashidRework.checkRecognition(player)
	if RashidRework.isTrusted(player) then
		return false
	end
	if not (RashidRework.allSixReported(player) and get(player, "sunMeeting") >= 1) then
		return false
	end
	RashidRework.set(player, "trusted", 1)
	player:addAchievement("Recognised Trader")
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Rashid has written your name in his ledger. He will now buy from you.")
	return true
end

-- Tokens ---------------------------------------------------------------------

local F = RashidRework.FAMILY
local St = RashidRework.Storage

QuestTokens.define(F, "mon_bill", {
	itemId = 2834, genKey = St.genMonBill, name = "firewood bill",
	description = "Rashid's copy of Dankwart's firewood account.",
	text = "Firewood: twelve bundles. Charged at ten gold per bundle. Total: 140 gold.",
})
QuestTokens.define(F, "mon_corrected", {
	itemId = 2834, genKey = St.genMonCorrected, name = "corrected firewood account",
	description = "Signed off by Dankwart.",
	text = "Firewood: twelve bundles at ten gold. Corrected total 120 gold. Confirmed by Dankwart.",
})
QuestTokens.define(F, "tue_receipt", {
	itemId = 2834, genKey = St.genTueReceipt, name = "room receipt",
	description = "Rashid's receipt for a night at Lyonel's.",
	text = "Paid: guest room, one night. Registered guest: Rashid, son of the desert. Account filed under: Desert Trader.",
})
QuestTokens.define(F, "tue_correction", {
	itemId = 2834, genKey = St.genTueCorrection, name = "room account correction",
	description = "Signed by Lyonel.",
	text = "Room account reconciled under Desert Trader. Paid in full; duplicate charge cancelled.\nLyonel",
})
QuestTokens.define(F, "wed_cloth", {
	itemId = 5913, genKey = St.genWedCloth, identity = "writer", name = "wrapping cloth",
	description = "Clyde's cloth, for wrapping Rashid's sample case.",
})
QuestTokens.define(F, "wed_case", {
	itemId = 2853, genKey = St.genWedCase, name = "Rashid's sample case",
	actionId = RashidRework.ACTION_SAMPLE_CASE,
	description = function(player)
		if get(player, "wrapped") >= 1 then
			return "Wrapped dry in Clyde's cloth."
		end
		return "Its wrapping has split. Use it while carrying Clyde's cloth to wrap it."
	end,
})
QuestTokens.define(F, "fri_instruction", {
	itemId = 2834, genKey = St.genFriInstruction, name = "Rashid's instruction",
	description = "Rashid's genuine instruction to Miraia.",
	text = "Reserve the goods in my name. Payment on collection. No money to be collected from the supplier.\nRashid",
})
QuestTokens.define(F, "fri_cancelled", {
	itemId = 2834, genKey = St.genFriCancelled, name = "cancelled order",
	description = "The false order, cancelled by Miraia.",
	text = "Supplier to pay bearer twenty gold as collection fee. Rashid will settle the goods account later.\nCancelled before payment or release.\nMiraia",
})
QuestTokens.define(F, "sat_order", {
	itemId = 2853, genKey = St.genSatOrder, name = "Mirabell's small order",
	description = "A sealed bundle of kitchen knives for Mirabell in Edron. Paid already.",
})
QuestTokens.define(F, "sat_receipt", {
	itemId = 2834, genKey = St.genSatReceipt, name = "Mirabell's receipt",
	description = "Signed by Mirabell.",
	text = "Kitchen knives received, payment already settled.\nMirabell",
})

function RashidRework.token(player, kind)
	return QuestTokens.find(player, F, kind)
end

function RashidRework.give(player, kinds)
	local specs = {}
	for _, kind in ipairs(kinds) do
		specs[#specs + 1] = { F, kind }
	end
	return QuestTokens.give(player, specs)
end

-- What each task hands out on acceptance.
RashidRework.InitialToken = { mon = "mon_bill", tue = "tue_receipt", fri = "fri_instruction" }

-- The proof Rashid takes when a task is reported.
RashidRework.ReportToken = { mon = "mon_corrected", tue = "tue_correction", wed = "wed_case", fri = "fri_cancelled", sat = "sat_receipt" }

-- Replacement kinds by durable task progress (R10). Returns the list to
-- reissue, or nil plus the issuer to name when nothing has been earned yet.
function RashidRework.replacementFor(player, dayKey)
	local value = get(player, dayKey)
	local T = RashidRework.Task
	if value == T.UNSET or value >= T.REPORTED then
		return nil
	end
	local want
	if dayKey == "mon" then
		want = value == T.READY and "mon_corrected" or "mon_bill"
	elseif dayKey == "tue" then
		want = value == T.READY and "tue_correction" or "tue_receipt"
	elseif dayKey == "fri" then
		want = value == T.READY and "fri_cancelled" or "fri_instruction"
	elseif dayKey == "sat" then
		if value == T.READY then
			want = "sat_receipt"
		elseif get(player, "willardIssued") >= 1 then
			want = "sat_order"
		else
			return nil, "Willard in Edron is holding that order. Ask him about the {small order} first."
		end
	elseif dayKey == "wed" then
		local kinds = {}
		if get(player, "caseRetrieved") < 1 then
			return nil, "Clyde in Port Hope is keeping the sample case. Ask him about it first."
		end
		if RashidRework.token(player, "wed_case") == nil then
			kinds[#kinds + 1] = "wed_case"
		end
		-- Only before wrapping: a wrapped case never needs more cloth.
		if get(player, "wrapped") < 1 and RashidRework.token(player, "wed_cloth") == nil then
			kinds[#kinds + 1] = "wed_cloth"
		end
		return kinds
	else
		return nil -- Thursday has no physical proof
	end
	if RashidRework.token(player, want) then
		return {}
	end
	return { want }
end

-- Journal ------------------------------------------------------------------

local STATUS = {
	mon = { [1] = "ask Dankwart in Svargrond about the {firewood account}", [2] = "bring Dankwart's corrected account to Rashid" },
	tue = { [1] = "ask Lyonel in Liberty Bay about the {room account}", [2] = "bring Lyonel's correction to Rashid" },
	wed = { [1] = "ask Clyde in Port Hope about the {sample case}, then wrap it dry", [2] = "bring the wrapped sample case to Rashid" },
	thu = { [1] = "ask Arito in Ankrahmun about the {samples}", [2] = "tell Rashid which piece is being sold as something it is not" },
	fri = { [1] = "ask Miraia in Darashia about the {reserved order}", [2] = "bring the cancelled order to Rashid" },
	sat = { [1] = "ask Willard in Edron for the {small order} and take it to Mirabell", [2] = "bring Mirabell's receipt to Rashid" },
}

-- Plain lines for the quest log; braces are stripped there.
function RashidRework.journalLines(player)
	local lines = {}
	for _, day in ipairs(RashidRework.Days) do
		local value = RashidRework.ctask(player, day.key)
		local text
		if value >= RashidRework.Task.REPORTED then
			text = "settled"
		elseif value == RashidRework.Task.UNSET then
			text = string.format("not taken yet; ask Rashid for a task on %s", day.name)
		else
			text = "bring Rashid " .. RashidRework.progressText(player, day.key)
		end
		lines[#lines + 1] = string.format("%s: %s.", day.name, text)
	end
	lines[#lines + 1] = get(player, "sunMeeting") >= 1 and "Sunday: done. Rashid buys from you." or "Sunday: when all six tasks are done, ask Rashid to {trade}."
	return lines
end

-- Where Rashid is, as far as the scheduler knows.
function RashidRework.whereaboutsLine()
	local current = RashidRework.current
	if current and current.placed then
		return "Rashid lives in his cabin and gives out his tasks there."
	end
	local stop = RashidRework.Schedule[RashidRework.utcWday()]
	return "Rashid lives in his cabin and gives out his tasks there."
end

return RashidRework
