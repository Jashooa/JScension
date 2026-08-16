-- Unit-state helpers: existence, aliveness, hostility, casting, movement,
-- and resource percentages. These wrap the WoW unit APIs and are shared by
-- the condition registry and the rotation engine, so a unit-API call does
-- not leak into Core.

local _, ns = ...

local Unit = {}

-- unitOK returns true when the unit exists and is alive.
function Unit.unitOK(unit)
	return unit and UnitExists(unit) and not UnitIsDeadOrGhost(unit)
end

-- exists returns true when the unit exists.
function Unit.exists(unit)
	return UnitExists(unit) and true or false
end

-- canAttack returns true when the unit is attackable by the player.
function Unit.canAttack(unit)
	return UnitCanAttack("player", unit) and true or false
end

-- isCasting returns true when the unit is casting or channeling.
function Unit.isCasting(unit)
	return (UnitCastingInfo(unit) or UnitChannelInfo(unit)) and true or false
end

-- speed returns the unit's movement speed.
function Unit.speed(unit)
	return GetUnitSpeed(unit)
end

-- inCombat returns true when the unit is in combat.
function Unit.inCombat(unit)
	return UnitAffectingCombat(unit) and true or false
end

-- healthPercent returns the unit's health as a percentage, or nil when the unit
-- has no max health.
function Unit.healthPercent(unit)
	local max = UnitHealthMax(unit)
	if not max or max == 0 then return nil end
	return (UnitHealth(unit) / max) * 100
end

-- powerPercent returns the unit's power (mana, rage, energy, runic) as a
-- percentage, or nil when the unit has no max power.
function Unit.powerPercent(unit)
	local max = UnitPowerMax(unit)
	if not max or max == 0 then return nil end
	return (UnitPower(unit) / max) * 100
end

ns.Unit = Unit
