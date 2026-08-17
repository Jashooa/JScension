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

-- CastGround places a pending ground-target spell at a unit's on-screen
-- position. Each protected call runs through Compatibility.Call separately.
function Compatibility.CastGround(spell, unit)
	local w, h = GetScreenWidth(), GetScreenHeight()
	local aspect = w / h
	local d = math.sqrt(w * w + h * h)

	-- save cursor (base UI space → per-axis fraction)
	local scx, scy = GetCursorPosition()
	local savedX = scx / (768 * aspect)
	local savedY = scy / 768

	-- target screen position (diagonal-normalised → per-axis fraction)
	local tx, ty = GetScreenPosition(unit)
	local gx = tx * d / w
	local gy = ty * d / h

	SetCursorPosition(gx, gy)
	Compatibility.Call("CameraOrSelectOrMoveStart()")
	Compatibility.Call("CameraOrSelectOrMoveStop()")
	SetCursorPosition(savedX, savedY)
end

-- Cast runs CastSpellByName under the trusted owner. unit is the target
-- unit token ("player" for self-cast). If the spell opens a ground-
-- targeting cursor, CastGround resolves it at the unit's position.
function Compatibility.Cast(spell, unit)
	if unit == "player" then
		return Compatibility.Call('CastSpellByName(%s, "player")', spell)
	end
	Compatibility.Call("CastSpellByName(%s)", spell)
	local isTargeting = Compatibility.Call("return SpellIsTargeting()")
	if isTargeting then
		Compatibility.CastGround(spell, unit)
	end
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
