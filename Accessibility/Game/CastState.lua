-- Shared cast and channel state adapter.
--
-- The client exposes normal casts and channels through separate APIs with
-- different interruptibility positions. This module normalizes both results.

local _, ns = ...

local CastState = {}

local function stateFrom(name, endTimeMilliseconds, notInterruptible)
	if not name then return nil end
	return {
		name = name,
		endTimeMilliseconds = endTimeMilliseconds,
		interruptible = notInterruptible ~= true,
	}
end

function CastState.Read(unit)
	local name, _, _, _, _, endTimeMilliseconds, _, _, notInterruptible = UnitCastingInfo(unit)
	local state = stateFrom(name, endTimeMilliseconds, notInterruptible)
	if state then return state end

	name, _, _, _, _, endTimeMilliseconds, _, notInterruptible = UnitChannelInfo(unit)
	return stateFrom(name, endTimeMilliseconds, notInterruptible)
end

ns.CastState = CastState
