local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_FIREDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, CONST_ME_FIREATTACK)
combat:setArea(createCombatArea(AREA_CIRCLE3X3))

function onGetFormulaValues(player, level, maglevel)
	return -800, -1400
end

combat:setCallback(CALLBACK_PARAM_LEVELMAGICVALUE, "onGetFormulaValues")

local spell = Spell("instant")

function spell.onCastSpell(creature, var)
	creature:say("THE GROUND BEGINS TO HEAT UP RAPIDLY!", TALKTYPE_MONSTER_YELL)
	return combat:execute(creature, var)
end

spell:name("mazoran fire")
spell:words("###425")
spell:isAggressive(true)
spell:blockWalls(true)
spell:needLearn(true)
spell:register()
