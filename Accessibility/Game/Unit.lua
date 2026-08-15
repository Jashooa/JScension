-- Unit-state helpers: existence, aliveness, and resource percentages. These
-- wrap the WoW unit APIs and are shared by the condition registry and the
-- rotation engine.

local _, ns = ...

ns.Unit = {}

-- unitOK returns true when the unit exists and is alive.
function ns.Unit.unitOK(unit)
	return unit and UnitExists(unit) and not UnitIsDeadOrGhost(unit)
end

-- healthPercent returns the unit's health as a percentage, or nil when the unit
-- has no max health.
function ns.Unit.healthPercent(unit)
	local max = UnitHealthMax(unit)
	if not max or max == 0 then return nil end
	return (UnitHealth(unit) / max) * 100
end

-- powerPercent returns the unit's power (mana, rage, energy, runic) as a
-- percentage, or nil when the unit has no max power.
function ns.Unit.powerPercent(unit)
	local max = UnitPowerMax(unit)
	if not max or max == 0 then return nil end
	return (UnitPower(unit) / max) * 100
end
