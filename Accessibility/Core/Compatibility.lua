-- The single seam to the injected shim.
--
-- Only this file touches the raw Compatibility global. The other modules use
-- the functions on this table. That keeps two facts in one place: the only
-- code that builds a script, and the only code that runs a protected call.

local _, ns = ...
local Compatibility = {}
local Unit = ns.Unit
assert(Unit, "load order: Core/Compatibility after Game/Unit")

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
local function pack_n(...)
	return { ... }, select("#", ...)
end
local function runCommand(command, ...)
	return _G.Compatibility(string.format(command, ...))
end

function Compatibility.Call(fmt, ...)
	local n = select("#", ...)
	local args = { ... }
	for i = 1, n do
		if type(args[i]) == "string" then
			args[i] = string.format("%q", args[i])
		end
	end
	local results, resultCount = pack_n(_G.Compatibility(string.format(fmt, unpack(args, 1, n))))
	if not results[1] then return nil, results[2] end
	return unpack(results, 2, resultCount)
end

-- ---------------------------------------------------------------------------
-- secure-function wrappers
-- ---------------------------------------------------------------------------

-- ConfirmGround confirms a pending ground-target spell at a unit's world
-- position via HandleTerrainClick (0x0080c340). TerrainClickInfo struct:
-- {target_guid_lo, target_guid_hi, x, y, z}. Flag 0x40 in DAT_00d3f4e0
-- means ground-targeted spell.
function Compatibility.ConfirmGround(unit)
	local x, y, z = Compatibility.Position(unit)
	if not x then return end
	runCommand("Compatibility_PlaceGround %f %f %f", x, y, z)
end

-- Cast runs CastSpellByName under the trusted owner. unit is the target
-- unit token ("player" for self-cast). If the spell opens a ground-
-- targeting cursor, ConfirmGround resolves it at the unit's position.
function Compatibility.Cast(spell, unit)
	if unit == "player" then
		return Compatibility.Call('CastSpellByName(%s, "player")', spell)
	end
	Compatibility.Call("CastSpellByName(%s)", spell)
	local isTargeting = Compatibility.Call("return SpellIsTargeting()")
	if isTargeting then
		Compatibility.ConfirmGround(unit)
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

-- Position returns the world position (x, y, z) of a unit by GUID lookup
-- through the shim's object manager. Returns nil if the unit is not found.
function Compatibility.Position(unit)
	local guid = Unit.guid(unit)
	if not guid then return end
	return runCommand("Compatibility_Position %s", guid)
end

-- Scale returns the OBJECT_FIELD_SCALE_X of a unit, or nil if not found.
function Compatibility.Scale(unit)
	local guid = Unit.guid(unit)
	if not guid then return end
	return runCommand("Compatibility_Scale %s", guid)
end

-- LoS returns true if there is a clear line of sight between the player and
-- a unit, false if obstructed. Eye height is 2.1 * scale per end.
function Compatibility.LoS(unit)
	local px, py, pz = Compatibility.Position("player")
	if not px then return end
	local ux, uy, uz = Compatibility.Position(unit)
	if not ux then return end
	local ps = Compatibility.Scale("player")
	local us = Compatibility.Scale(unit)
	return runCommand(
		"Compatibility_LOS %f %f %f %f %f %f %f %f",
		px, py, pz, ux, uy, uz, ps, us)
end

ns.Compatibility = Compatibility
