local spell = Spell("instant")

function spell.onCastSpell(creature, var)
	local summoncount = creature:getSummons()
	local maxsummons = 4
	if #summoncount < 4 then
		local pos = creature:getPosition()
		for i = 1, maxsummons - #summoncount do
			local mid = Game.createMonster("Disgusting Ooze", Position(pos.x + math.random(-4, 4), pos.y + math.random(-4, 4), pos.z), true, true)
			if not mid then
				return
			end
			mid:setMaster(creature)
		end
	end
	return
end

spell:name("plagirath summon")
spell:words("###411")
spell:isAggressive(true)
spell:blockWalls(true)
spell:needLearn(true)
spell:register()
