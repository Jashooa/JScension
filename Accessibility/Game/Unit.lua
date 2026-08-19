-- Unit-state helpers: existence, aliveness, hostility, casting, movement,
-- and resource percentages. These wrap the WoW unit APIs and are shared by
-- the condition registry and the rotation engine, so a unit-API call does
-- not leak into Core.

local _, ns = ...

local Unit = {}
local CastState = ns.CastState
assert(CastState, "load order: Game/Unit before CastState")

-- isAlive returns true when the unit exists and is not dead or a ghost.
function Unit.isAlive(unit)
	return unit and UnitExists(unit) and not UnitIsDeadOrGhost(unit)
end

-- isDeadOrGhost returns true when the unit is dead or a ghost.
function Unit.isDeadOrGhost(unit)
	return UnitIsDeadOrGhost(unit) and true or false
end

-- exists returns true when the unit exists.
function Unit.exists(unit)
	return UnitExists(unit) and true or false
end
-- guid returns the raw unit GUID for the shim boundary.
function Unit.guid(unit)
	return UnitGUID(unit)
end

-- distance returns the 3D distance between two units, or nil when either
-- position is unavailable.
function Unit.distance(firstUnit, secondUnit)
	local Compatibility = ns.Compatibility
	if not Compatibility then return nil end
	local firstX, firstY, firstZ = Compatibility.Position(firstUnit)
	local secondX, secondY, secondZ = Compatibility.Position(secondUnit)
	if not firstX or not secondX then return nil end
	local dx = firstX - secondX
	local dy = firstY - secondY
	local dz = firstZ - secondZ
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- isCasting returns true when the unit is casting or channeling.
function Unit.isCasting(unit)
	return CastState.Read(unit) ~= nil
end

-- isCastingSpell returns true when the unit is casting or channeling the
-- named spell. Cast-bar names carry a rank suffix in this client, so both
-- sides are normalized before comparison.
function Unit.isCastingSpell(unit, spell)
	local state = CastState.Read(unit)
	if not state then return false end
	local want = spell and ns.Spell and ns.Spell.stripRank(spell) or spell
	return ns.Spell.stripRank(state.name) == want
end

-- castInterruptible returns true when the unit's current cast or channel can
-- be interrupted. A unit with no cast is not interruptible.
function Unit.castInterruptible(unit)
	local state = CastState.Read(unit)
	return state and state.interruptible or false
end

-- speed returns the unit's movement speed.
function Unit.speed(unit)
	return GetUnitSpeed(unit)
end

-- inCombat returns true when the unit is in combat.
function Unit.inCombat(unit)
	return UnitAffectingCombat(unit) and true or false
end

-- health returns the unit's raw health.
function Unit.health(unit)
	return UnitHealth(unit)
end

-- healthPercent returns the unit's health as a percentage, or nil when the unit
-- has no max health.
function Unit.healthPercent(unit)
	local max = UnitHealthMax(unit)
	if not max or max == 0 then return nil end
	return (UnitHealth(unit) / max) * 100
end

-- level returns the unit's level.
function Unit.level(unit)
	return UnitLevel(unit)
end

-- isPlayer returns true when the unit is a player rather than a mob.
function Unit.isPlayer(unit)
	return UnitIsPlayer(unit) and true or false
end

-- classification returns the unit's classification: "worldboss", "rareelite",
-- "elite", "rare", "normal", or nil.
function Unit.classification(unit)
	return UnitClassification(unit)
end

-- threatPercent returns the source unit's threat on the target as the scaled
-- percentage (100 = enough to pull), or nil when the target is not on the
-- threat list.
function Unit.threatPercent(sourceUnit, targetUnit)
	local _, _, scaledPercent = UnitDetailedThreatSituation(sourceUnit, targetUnit)
	return scaledPercent
end

-- isTanking returns true when the source unit is the primary tank of the target.
function Unit.isTanking(sourceUnit, targetUnit)
	local status = UnitThreatSituation(sourceUnit, targetUnit)
	return status ~= nil and status >= 3
end

-- power returns the unit's raw power. powerType (0 mana, 1 rage, 2 focus,
-- 3 energy, 6 runic) selects a specific pool; nil uses the current one.
function Unit.power(unit, powerType)
	if powerType ~= nil then
		return UnitPower(unit, powerType)
	end
	return UnitPower(unit)
end

-- powerMax returns the unit's max power for a pool, or nil when the unit has
-- no max power. powerType selects a specific pool; nil uses the current one.
function Unit.powerMax(unit, powerType)
	if powerType ~= nil then
		return UnitPowerMax(unit, powerType)
	end
	return UnitPowerMax(unit)
end

-- powerPercent returns the unit's power (mana, rage, energy, runic) as a
-- percentage, or nil when the unit has no max power. powerType selects a
-- specific pool; nil uses the current one.
function Unit.powerPercent(unit, powerType)
	local max = Unit.powerMax(unit, powerType)
	if not max or max == 0 then return nil end
	return (Unit.power(unit, powerType) / max) * 100
end

ns.Unit = Unit
