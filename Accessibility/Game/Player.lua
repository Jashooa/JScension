-- Player-state helpers: player-relative combat, combo points, and forms.
--
-- These APIs are player-specific even when they accept a target unit, so they
-- stay separate from the generic Unit helpers.

local _, ns = ...

local Player = {}

-- canAttack returns true when the player can attack the unit.
function Player.canAttack(unit)
	return UnitCanAttack("player", unit) and true or false
end

-- comboPoints returns the player's combo points on the unit, or nil when the
-- unit is not a valid combo target.
function Player.comboPoints(unit)
	return GetComboPoints("player", unit)
end

-- shapeshiftForm returns the index of the player's current shapeshift form,
-- or 0 when not in a form.
function Player.shapeshiftForm()
	return GetShapeshiftForm() or 0
end

-- shapeshiftFormName returns the name of the player's current shapeshift
-- form, or nil when not in a form.
function Player.shapeshiftFormName()
	local form = Player.shapeshiftForm()
	if not form or form == 0 then return nil end
	local _, name = GetShapeshiftFormInfo(form)
	return name
end

ns.Player = Player
