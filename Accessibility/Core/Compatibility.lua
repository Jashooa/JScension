-- The single seam to the injected shim.
--
-- Only this file touches the raw Compatibility global. The other modules use
-- the functions on this table. That keeps two facts in one place: the only
-- code that builds a script, and the only code that runs a protected call.

local _, ns = ...
local Compatibility = {}

-- ---------------------------------------------------------------------------
-- status
-- ---------------------------------------------------------------------------

-- Cached result of the compatibility probe. nil = not probed yet.
local compatible = nil
-- lastProbeAt / lastProbeAvailable: state of the last probe, so a broken
-- trust gate is not re-probed through the shim on every pulse tick.
local lastProbeAt = 0
local lastProbeAvailable = false
local PROBE_INTERVAL = 1.0

-- IsAvailable returns true when the shim installed the Compatibility global.
function Compatibility.IsAvailable()
	return type(_G.Compatibility) == "function"
end

-- Recheck runs the issecure probe and caches the result. Run it again after a
-- /reload or when the shim attaches late. The global may exist while the
-- trust gate fails, so a real probe must confirm the gate.
function Compatibility.Recheck()
	lastProbeAvailable = Compatibility.IsAvailable()
	if not lastProbeAvailable then
		compatible = false
		return false
	end
	-- The shim returns (ok, value, err) from the script. The probe returns
	-- issecure(): 1 in a trusted context, nil otherwise.
	local ok, value = _G.Compatibility("return issecure()")
	lastProbeAt = GetTime()
	if ok and (value == true or value == 1) then
		compatible = true
	else
		compatible = false
	end
	return compatible
end

-- IsCompatible returns the cached probe result. It runs the probe on the first
-- call. A cached false is re-probed when the shim global has appeared since
-- the last probe: the shim can attach after addon load (game restart without
-- injection), and a stale false would block every cast until a manual reload.
-- The re-probe is rate-limited to once per PROBE_INTERVAL so a persistently
-- broken trust gate does not run a secure script 14 times a second.
function Compatibility.IsCompatible()
	local available = Compatibility.IsAvailable()
	if compatible == nil then
		return Compatibility.Recheck()
	end
	if compatible == false and available
		and (not lastProbeAvailable or (GetTime() - lastProbeAt) >= PROBE_INTERVAL) then
		return Compatibility.Recheck()
	end
	lastProbeAvailable = available   -- remember for the next call's attach detection
	return compatible
end

-- ---------------------------------------------------------------------------
-- Call: the one place a script is built
-- ---------------------------------------------------------------------------

-- Call builds one script and runs it through the shim. A string argument is
-- escaped with %q into a Lua literal. A number passes through unchanged.
-- The templates in the wrappers below are constants. Never pass a raw string
-- through %s: a spell name could then inject code.
function Compatibility.Call(fmt, ...)
	local n = select("#", ...)
	local args = { ... }
	for i = 1, n do
		if type(args[i]) == "string" then
			args[i] = string.format("%q", args[i])
		end
	end
	return _G.Compatibility(string.format(fmt, unpack(args, 1, n)))
end

-- ---------------------------------------------------------------------------
-- secure-function wrappers
-- ---------------------------------------------------------------------------

-- Cast runs CastSpellByName under the trusted owner. name is the exact spell
-- name; selfCast casts on the player.
function Compatibility.Cast(name, selfCast)
	if selfCast then
		return Compatibility.Call('return CastSpellByName(%s, "player")', name)
	end
	return Compatibility.Call("return CastSpellByName(%s)", name)
end

-- StopCasting stops the current cast.
function Compatibility.StopCasting()
	return Compatibility.Call("return SpellStopCasting()")
end

-- UseAction presses an action-bar slot by number.
function Compatibility.UseAction(slot)
	return Compatibility.Call("return UseAction(%d)", slot)
end

ns.Compatibility = Compatibility
