-- Diamond Arrow (id 35901) -- was a plain flat-damage arrow with no weapon
-- script at all (confirmed: items.xml only gave it weaponType/ammotype/
-- shootType/attack, nothing else), missing its real signature mechanic
-- entirely. Real Tibia: damages a 21-field area centred on the target (2
-- fields of radius -- a 5x5 square with the 4 corners removed, the same
-- shape the old pre-2007 Fireball Rune used), always Physical damage
-- (unaffected by elemental bow imbuements), with a blue electricity burst
-- on impact. Since the target sits inside its own splash, it's effectively
-- unmissable. Source: TibiaWiki (Diamond Arrow / Diamond Arrow Missile
-- pages).
--
-- Built on the exact same pattern as data/scripts/weapons/burst_arrow.lua,
-- this datapack's other AoE ammo -- Weapon(WEAPON_AMMO), COMBAT_FORMULA_SKILL
-- with the native weapon-damage roll (0..1x, no custom Lua callback). This
-- matters specifically: a real, documented bug in another TFS-family fork
-- (opentibiabr/canary issue #2546) hardcoded a custom damage formula that
-- ignored the equipped bow's own attack bonus entirely, making bow upgrades
-- pointless with Diamond Arrows. COMBAT_FORMULA_SKILL avoids that class of
-- bug outright -- it defers to Weapon::getWeaponDamage() natively
-- (src/combat.cpp:293-304), which already correctly combines the bow's
-- attack with the ammo's own, the same as any other arrow.
local area = createCombatArea({
	{0, 1, 1, 1, 0},
	{1, 1, 1, 1, 1},
	{1, 1, 3, 1, 1},
	{1, 1, 1, 1, 1},
	{0, 1, 1, 1, 0},
})

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, CONST_ME_BLUE_ENERGY_SPARK)
combat:setParameter(COMBAT_PARAM_DISTANCEEFFECT, CONST_ANI_DIAMONDARROW)
combat:setParameter(COMBAT_PARAM_BLOCKARMOR, true)
combat:setFormula(COMBAT_FORMULA_SKILL, 0, 0, 1, 0)
combat:setArea(area)

local diamondArrow = Weapon(WEAPON_AMMO)

function diamondArrow.onUseWeapon(player, variant)
	if player:getSkull() == SKULL_BLACK then
		return false
	end
	return combat:execute(player, variant)
end

diamondArrow:id(35901)
diamondArrow:attack(37)
diamondArrow:action("removecount")
diamondArrow:ammoType("arrow")
diamondArrow:shootType(CONST_ANI_DIAMONDARROW)
diamondArrow:maxHitChance(100)
diamondArrow:register()
