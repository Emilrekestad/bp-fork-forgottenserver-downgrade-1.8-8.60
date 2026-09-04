-- Old Man Bao — reverse index: monster name (lowercase) -> list of hunt ids
-- that monster contributes to. Built once at startup from BaoConfig.Hunts so
-- kill tracking never has to iterate every hunt definition per kill.

BaoLookup = {}
BaoLookup.byMonster = {}

function BaoLookup.build()
	BaoLookup.byMonster = {}

	for huntId, hunt in pairs(BaoConfig.Hunts) do
		if hunt.kind == "single" and hunt.target then
			local key = hunt.target:lower()
			BaoLookup.byMonster[key] = BaoLookup.byMonster[key] or {}
			table.insert(BaoLookup.byMonster[key], huntId)
		elseif hunt.kind == "family" and hunt.targets then
			for monsterName, _ in pairs(hunt.targets) do
				local key = monsterName:lower()
				BaoLookup.byMonster[key] = BaoLookup.byMonster[key] or {}
				table.insert(BaoLookup.byMonster[key], huntId)
			end
		end
	end
end

-- Returns the list of hunt ids relevant to this monster name, or nil if this
-- monster isn't part of any configured Bao hunt (the common case).
function BaoLookup.getHuntsFor(monsterName)
	if not monsterName then
		return nil
	end
	return BaoLookup.byMonster[monsterName:lower()]
end

-- Returns the point weight a kill of this monster contributes toward the
-- given hunt (1 for "single" hunts, the configured weight for "family" hunts).
function BaoLookup.getWeight(huntId, monsterName)
	local hunt = BaoConfig.Hunts[huntId]
	if not hunt then
		return 0
	end
	if hunt.kind == "single" then
		return 1
	elseif hunt.kind == "family" and hunt.targets then
		return hunt.targets[monsterName] or 0
	end
	return 0
end

BaoLookup.build()
