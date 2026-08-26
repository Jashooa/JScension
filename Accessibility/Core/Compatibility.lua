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
local TARGET_CATEGORIES = {
	enemy = 0,
	enemy_player = 1,
	enemy_npc = 2,
	friendly_player = 3,
}
local TARGET_CRITERIA = {
	lowest_health_percent = 0,
	highest_health_percent = 1,
	most_missing_health = 2,
	closest = 3,
	farthest = 4,
}

local function targetEnum(value, values)
	if type(value) == "number" then return value end
	return values[value]
end

local function guidWords(low, high)
	return ("0x%08x%08x"):format(high, low)
end

local function appendGuidArguments(parts, guids)
	parts[#parts + 1] = tostring(#guids)
	for i = 1, #guids do parts[#parts + 1] = tostring(guids[i]) end
end

function Compatibility.SelectVisibleUnits(category, criterion, maxDistance, currentGuid,
	allowedGuids, excludedGuids)
	category = targetEnum(category, TARGET_CATEGORIES)
	criterion = targetEnum(criterion, TARGET_CRITERIA)
	allowedGuids = allowedGuids or {}
	excludedGuids = excludedGuids or {}
	if category == nil or criterion == nil or type(maxDistance) ~= "number" or maxDistance < 0 or
		type(currentGuid) ~= "string" then return end
	local parts = {
		("Compatibility_SelectVisibleUnit %d %d %f %s"):format(
			category, criterion, maxDistance, currentGuid),
	}
	appendGuidArguments(parts, allowedGuids)
	appendGuidArguments(parts, excludedGuids)
	local count = runCommand(table.concat(parts, " "))
	if type(count) ~= "number" or count < 0 then return end
	local candidates = {}
	for i = 1, count do
		local low, high, allowedIndex, health, maxHealth, distanceSquared =
			runCommand(("Compatibility_SelectedVisibleUnit %d"):format(i))
		if low == nil or high == nil then return end
		candidates[i] = {
			guid = guidWords(low, high),
			allowedIndex = allowedIndex,
			health = health,
			maxHealth = maxHealth,
			distanceSquared = distanceSquared,
		}
	end
	return candidates
end



local UNIT_COUNT_RELATIONSHIPS = {
	any = 0,
	enemy = 1,
	friendly = 2,
	player = 3,
}


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
	unit = unit or "target"
	Compatibility.Call("CastSpellByName(%s, %s)", spell, unit)
	local isTargeting = Compatibility.Call("return SpellIsTargeting()")
	if isTargeting then
		Compatibility.ConfirmGround(unit)
	end
	return true
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
-- UnitCountInRange counts living visible units around a unit GUID. targetType
-- uses the same any/enemy/friendly/player values as the condition editor.
function Compatibility.UnitCountInRange(centerUnit, targetType, radius)
	local guid = Unit.guid(centerUnit)
	local relationship = type(targetType) == "string" and UNIT_COUNT_RELATIONSHIPS[targetType]
	if not guid or relationship == nil or type(radius) ~= "number" or radius < 0 then return end
	return runCommand("Compatibility_UnitCountInRange %s %d %f", guid, relationship, radius)
end


-- LoS returns true if a spell has a clear line of sight between the player and
-- a unit, false if obstructed. The shim uses the WMO-only spell LOS mask.
function Compatibility.LoS(unit)
	if unit == "player" then return 1 end
	local sourceGuid = Unit.guid("player")
	local targetGuid = Unit.guid(unit)
	if not sourceGuid or not targetGuid then return end
	return runCommand("Compatibility_LOS %s %s", sourceGuid, targetGuid)
end

ns.Compatibility = Compatibility
