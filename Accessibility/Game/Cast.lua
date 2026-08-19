-- Cast-state helpers: whether the player is casting/channelling, and whether
-- a new cast may be sent now (the spell queue window).
--
-- Sending a cast inside the queue window makes the client queue the spell
-- (its SpellQueueWindow CVar), so the next cast starts the instant the current
-- one ends - no dead time between casts. UnitCastingInfo/UnitChannelInfo
-- return endTime in ms (6th value; 5th is startTime).

local _, ns = ...

local Constants = ns.Constants
local CastState = ns.CastState
assert(Constants and CastState, "load order: Game/Cast before Constants/CastState")

local Cast = {}

-- currentCast returns the player's active cast or channel as (name, endMs),
-- or nil when idle.
function Cast.currentCast()
	local state = CastState.Read("player")
	if not state then return nil end
	return state.name, state.endTimeMilliseconds
end

-- isCasting returns true while the player is casting or channelling.
function Cast.isCasting()
	return Cast.currentCast() ~= nil
end

-- inQueueWindow returns true when a cast may be sent now: either the player
-- is not casting, or the current cast is within queueWindow seconds of
-- finishing. A queueWindow of 0 disables the early send and only casts when
-- fully idle.
function Cast.inQueueWindow()
	local window = ns.Profile.current().queueWindow or Constants.DEFAULT_QUEUE_WINDOW
	if window <= 0 then
		return Cast.currentCast() == nil
	end
	local _, endMs = Cast.currentCast()
	if not endMs then return true end   -- idle: free to cast
	-- an epsilon absorbs float error at the exact window edge (e.g. 12.0-11.6
	-- is 0.39999... in binary, so a bare <= would reject the boundary)
	return (endMs / 1000 - GetTime()) <= (window + 0.001)
end

ns.Cast = Cast
