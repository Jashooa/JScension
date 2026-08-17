-- Input-state helpers: keyboard modifier keys. These wrap the client's
-- IsShiftKeyDown/IsControlKeyDown/IsAltKeyDown so a raw input API call does
-- not leak into Core. Used by the modifier_keys condition.

local _, ns = ...

local Input = {}

-- shift returns true when Shift is held.
function Input.shift()
	return IsShiftKeyDown() and true or false
end

-- control returns true when Ctrl is held.
function Input.control()
	return IsControlKeyDown() and true or false
end

-- alt returns true when Alt is held.
function Input.alt()
	return IsAltKeyDown() and true or false
end

ns.Input = Input
