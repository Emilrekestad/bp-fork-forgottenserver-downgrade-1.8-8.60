local spell = Spell("instant")

function spell.onCastSpell(creature, var)
	local summoncount = creature:getSummons()
	if #summoncount < 8 then
		local pos = creature:getPosition()
		for i = 1, 4 do
			local mid = Game.createMonster("Sin Devourer", Position(pos.x + math.random(-4, 4), pos.y + math.random(-4, 4), pos.z), true, true)
			if not mid then
				return
			end
			mid:setMaster(creature)
		end
		for i = 1, 4 do
			local mid2 = Game.createMonster("Damned Soul", Position(pos.x + math.random(-4, 4), pos.y + math.random(-4, 4), pos.z), true, true)
			if not mid2 then
				return
			end
		end
	end
	return
end

spell:name("shulgrax summon")
spell:words("###407")
spell:isAggressive(true)
spell:blockWalls(true)
spell:needLearn(true)
spell:register()
