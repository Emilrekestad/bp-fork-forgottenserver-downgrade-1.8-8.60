-- Live tuning: knobs the console can turn without a restart.
--
-- Every value here used to be a constant somewhere in a Lua file, which meant
-- changing it was a file edit, a deploy and a restart -- and so it did not get
-- changed, and the rarity system went to launch on its testing rates. A knob
-- is read from `server_tuning` at boot, kept in memory, and re-read on a
-- timer, so a change from the console lands within seconds and survives a
-- restart.
--
-- Two rules keep this safe to leave writable:
--
-- 1. **Every key is declared here, with a type, a range and a default.** An
--    unknown key is refused, a value outside its range is clamped, and a
--    value that does not parse falls back to the default. Whatever the
--    console writes, the game reads something sane.
--
-- 2. **The hot path never touches the database.** `Tuning.get` is a table
--    lookup. The experience callback runs on every kill; it cannot afford a
--    query and it does not make one.
--
-- Percent knobs (`rate.*`) are added to whatever the boosts contribute, so a
-- base of +25% loot and a running Loot Boost of +25% is +50%. They exist so
-- that "the server runs on 1.5x experience" is a decision made in the console
-- and visible on the Balance view, not a number nobody remembers editing.

Tuning = Tuning or {}

-- key -> {type, default, min, max, description}
-- `type` is "percent" (integer, may be negative for a nerf), "int", "bool" or
-- "enum" (with `options`).
Tuning.KEYS = {
	-- Base rate multipliers, in percent added. 0 = the configured rate.
	["rate.experience"] = { type = "percent", default = 0, min = -90, max = 900,
		description = "Extra experience on top of the configured stages, in percent" },
	["rate.loot"] = { type = "percent", default = 0, min = 0, max = 400,
		description = "Chance of an extra loot roll on every drop, in percent" },
	["rate.spawn"] = { type = "percent", default = 0, min = 0, max = 300,
		description = "Chance that a natural spawn is doubled, in percent" },

	-- The bonus system's odds. "testing" is the wide-open rates used while
	-- trying things out; "live" is the tuned set. Switching is one click.
	["rarity.mode"] = { type = "enum", default = "testing", options = { "testing", "live" },
		description = "Which rarity odds are in force: the testing set or the tuned live set" },
	-- Extra percent on every rarity tier's threshold, on top of the mode and
	-- any running Rarity Boost. Lets the live set be nudged without editing it.
	["rarity.bonus"] = { type = "percent", default = 0, min = -50, max = 200,
		description = "Adjustment to every rarity tier's chance, in percent" },

	-- Boost magnitudes. Override what a purchased boost is worth.
	["boost.experience.magnitude"] = { type = "int", default = 50, min = 5, max = 300,
		description = "Experience Boost: percent added while it runs" },
	["boost.loot.magnitude"] = { type = "int", default = 25, min = 5, max = 200,
		description = "Loot Boost: chance of an extra roll while it runs" },
	["boost.spawn.magnitude"] = { type = "int", default = 50, min = 5, max = 200,
		description = "Spawn Boost: chance a spawn is doubled while it runs" },
	["boost.rare.magnitude"] = { type = "int", default = 50, min = 5, max = 300,
		description = "Rarity Boost: percent added to every tier's chance while it runs" },
	["boost.speed.magnitude"] = { type = "int", default = 60, min = 10, max = 200,
		description = "Speed Boost: speed points added while it runs" },
	["boost.regeneration.magnitude"] = { type = "int", default = 100, min = 25, max = 400,
		description = "Regeneration Boost: extra regeneration in percent while it runs" },

	-- Circuit breakers. Off means the feature refuses politely and the
	-- console shows it as tripped. For the two-in-the-morning exploit.
	["feature.store"] = { type = "bool", default = true,
		description = "The in-game store. Off refuses every purchase" },
	["feature.hirelings"] = { type = "bool", default = true,
		description = "Hireling jobs and workshops" },
	["feature.rarity"] = { type = "bool", default = true,
		description = "The bonus system. Off means natural loot rolls no rarity at all" },
}

local values = {}      -- key -> parsed value
local loadedAt = 0

local function coerce(spec, raw)
	if spec.type == "bool" then
		if raw == nil then
			return spec.default
		end
		local s = tostring(raw):lower()
		return s == "1" or s == "true" or s == "on" or s == "yes"
	elseif spec.type == "enum" then
		local s = tostring(raw or "")
		for _, option in ipairs(spec.options) do
			if option == s then
				return s
			end
		end
		return spec.default
	else
		local n = tonumber(raw)
		if n == nil then
			return spec.default
		end
		n = math.floor(n)
		if spec.min and n < spec.min then n = spec.min end
		if spec.max and n > spec.max then n = spec.max end
		return n
	end
end

local function encode(spec, value)
	if spec.type == "bool" then
		return value and "1" or "0"
	end
	return tostring(value)
end

--- Reads every row. Called at boot and on the refresh timer.
function Tuning.load()
	local fresh = {}
	for key, spec in pairs(Tuning.KEYS) do
		fresh[key] = spec.default
	end

	local resultId = db.storeQuery("SELECT `key`, `value` FROM `server_tuning`")
	if resultId then
		repeat
			local key = result.getString(resultId, "key")
			local spec = Tuning.KEYS[key]
			if spec then
				fresh[key] = coerce(spec, result.getString(resultId, "value"))
			end
		until not result.next(resultId)
		result.free(resultId)
	end

	values = fresh
	loadedAt = os.time()
	return true
end

--- The hot path. A table lookup and nothing else.
function Tuning.get(key)
	local value = values[key]
	if value == nil then
		local spec = Tuning.KEYS[key]
		return spec and spec.default or nil
	end
	return value
end

--- Convenience for the callbacks: a percent knob as a number, never nil.
function Tuning.percent(key)
	return tonumber(Tuning.get(key)) or 0
end

--- Convenience for the breakers: true unless explicitly off.
function Tuning.enabled(key)
	local value = Tuning.get(key)
	if value == nil then
		return true
	end
	return value and true or false
end

--- Sets one knob: validates, writes through, applies in memory.
-- Returns ok, message, {key, previous, value}.
function Tuning.set(key, raw, by)
	local spec = Tuning.KEYS[key]
	if not spec then
		return false, "unknown tuning key: " .. tostring(key)
	end

	local value = coerce(spec, raw)
	local previous = Tuning.get(key)
	values[key] = value

	db.query(string.format(
		"INSERT INTO `server_tuning` (`key`, `value`, `updated_at`, `updated_by`) VALUES (%s, %s, %d, %s) " ..
		"ON DUPLICATE KEY UPDATE `value` = VALUES(`value`), `updated_at` = VALUES(`updated_at`), " ..
		"`updated_by` = VALUES(`updated_by`)",
		db.escapeString(key), db.escapeString(encode(spec, value)), os.time(),
		db.escapeString(tostring(by or ""):sub(1, 32))))

	-- Some knobs have to be pushed to players who are already online.
	if key:find("^boost%.") and GlobalBoosts and GlobalBoosts.syncAllPlayers then
		GlobalBoosts.syncAllPlayers()
	end

	return true, string.format("%s: %s -> %s", key, tostring(previous), tostring(value)),
		{ key = key, previous = previous, value = value }
end

--- Everything, for the console's Balance view and the bridge query.
function Tuning.snapshot()
	local out = {}
	for key, spec in pairs(Tuning.KEYS) do
		out[key] = {
			value = Tuning.get(key),
			default = spec.default,
			type = spec.type,
			min = spec.min,
			max = spec.max,
			options = spec.options,
			description = spec.description,
		}
	end
	return out, loadedAt
end

Tuning.load()
