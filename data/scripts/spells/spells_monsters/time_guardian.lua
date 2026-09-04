local forms = { "The Blazing Time Guardian", "The Freezing Time Guardian" }

local function revertToBaseForm(monsterId)
	local form = Creature(monsterId)
	if not form then
		return
	end

	local pos = form:getPosition()
	local health = form:getHealth()
	form:remove()

	local base = Game.createMonster("The Time Guardian", pos, false, true, CONST_ME_MAGIC_BLUE)
	if base then
		base:addHealth(health - base:getHealth())
	end
end

local spell = Spell("instant")

function spell.onCastSpell(creature, var)
	local pos = creature:getPosition()
	local health = creature:getHealth()

	local form = Game.createMonster(forms[math.random(1, 2)], pos, false, true, CONST_ME_MAGIC_RED)
	if not form then
		return true
	end
	form:addHealth(health - form:getHealth())
	creature:remove()

	addEvent(revertToBaseForm, 30 * 1000, form:getId())
	return true
end

spell:name("time guardian")
spell:words("###440")
spell:isAggressive(true)
spell:blockWalls(true)
spell:needLearn(true)
spell:register()
