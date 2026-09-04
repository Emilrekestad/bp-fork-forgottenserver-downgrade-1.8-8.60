local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_NONE)
combat:setParameter(COMBAT_PARAM_EFFECT, CONST_ME_NONE)
combat:setArea(createCombatArea(AREA_CIRCLE2X2))

local creatures = { "Greed", "Frenzy", "Disruption" }

local spell = Spell("instant")

function spell.onCastSpell(creature, var)
	if #creature:getSummons() < 3 then
		local monster = creatures[math.random(#creatures)]
		Game.createMonster(monster, { x = creature:getPosition().x + math.random(-1, 1), y = creature:getPosition().y + math.random(-1, 1), z = creature:getPosition().z }, false, true)
	end

	return combat:execute(creature, var)
end

spell:name("devourer summon")
spell:words("###416")
spell:blockWalls(true)
spell:needLearn(true)
spell:register()
