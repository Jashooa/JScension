-- Cast-state helpers: whether the player is casting/channelling, and whether
-- a new cast may be sent now (the spell queue window).
--
-- Sending a cast inside the queue window makes the client queue the spell
-- (its SpellQueueWindow CVar), so the next cast starts the instant the current
-- one ends - no dead time between casts. UnitCastingInfo/UnitChannelInfo
-- return endTime in ms (6th value; 5th is startTime).

local _, ns = ...

local Constants = ns.Constants

ns.Cast = {}

-- isCasting returns true while the player is casting or channelling.
function ns.Cast.isCasting()
	return UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil
end

-- inQueueWindow returns true when a cast may be sent now: either the player
-- is not casting, or the current cast is within queueWindow seconds of
-- finishing. A queueWindow of 0 disables the early send and only casts when
-- fully idle.
function ns.Cast.inQueueWindow()
	local window = ns.Profile.current().queueWindow or Constants.DEFAULT_QUEUE_WINDOW
	if window <= 0 then
		return not UnitCastingInfo("player") and not UnitChannelInfo("player")
	end
	local endMs = select(6, UnitCastingInfo("player"))
	if not endMs then
		endMs = select(6, UnitChannelInfo("player"))
	end
	if not endMs then return true end   -- idle: free to cast
	-- an epsilon absorbs float error at the exact window edge (e.g. 12.0-11.6
	-- is 0.39999... in binary, so a bare <= would reject the boundary)
	return (endMs / 1000 - GetTime()) <= (window + 0.001)
end
