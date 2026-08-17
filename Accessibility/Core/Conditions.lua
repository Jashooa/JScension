-- The condition registry.
--
-- One entry per condition type. An entry declares its label, its fields (with
-- a type per field), how to describe itself in one line, and how to evaluate
-- itself. The editor and the engine both read the registry, so adding a type
-- touches only this file.
--
-- Field types:
--   unit        a unit ID (player, target, focus, pet, mouseover)
--   op          a comparison operator (<, <=, >, >=, ==, ~=)
--   percent     a bounded 0-100 value; rendered as a slider
--   spell       a spell name or numeric ID
--   string      a free string (an aura name)
--   kind        "buff" or "debuff"
--   bool        a boolean
--   target_type any, enemy, friendly, or player
--   classification normal, elite, rare, rareelite, or worldboss
--   modifier    shift, control, or alt
--   power       a power pool (mana, rage, focus, energy, runic); nil uses
--               the unit's current pool
--   number      an unbounded numeric value; rendered as a text input so
--               large values like 30000 are reachable
--   code        a Lua snippet that returns true or false
--
-- eval must never error: it runs many times a second inside combat. The
-- dispatcher wraps every eval in pcall and fails closed.

local _, ns = ...

local Conditions = {}
local Constants = ns.Constants
local Compare = ns.Compare
local Unit = ns.Unit
local Aura = ns.Aura
local Cooldown = ns.Cooldown
local Spell = ns.Spell
local Input = ns.Input
assert(Constants and Compare and Unit and Aura and Cooldown and Spell and Input,
	"load order: Core/Conditions before its dependencies")

-- SNIPPET_MAX truncates long Lua snippets in the editor display.
local SNIPPET_MAX = 40

-- The derived fields the "lua" condition stores on its own table (compile
-- cache). copyRule strips these so a compiled function never reaches the
-- SavedVariables file. Declared here so the copy consults one list.
Conditions.CacheKeys = { _compiled = true, _compiledFor = true, _error = true }
local Registry = {}
local order = {}

local function register(key, def)
	def.key = key
	Registry[key] = def
	order[#order + 1] = key
end

-- powerName renders a power pool for a describe line; nil means the current
-- pool. Declared before the registry entries because their describe closures
-- capture it as an upvalue.
local function powerName(power)
	if power == nil then return "power" end
	return Conditions.Powers[power] or "power"
end

-- ---------------------------------------------------------------------------
-- the registry entries
-- ---------------------------------------------------------------------------

register("unit_target_type", {
	label = "Target type",
	fields = { unit = "unit", value = "target_type" },
	describe = function(condition)
		return ("%s is %s"):format(condition.unit or "target", condition.value or "enemy")
	end,
	eval = function(condition)
		local unit = condition.unit
		local want = condition.value
		if want == "any" then
			return Unit.isAlive(unit)
		elseif want == "player" then
			return unit == "player"
		elseif want == "enemy" then
			return Unit.isAlive(unit) and Unit.canAttack(unit)
		elseif want == "friendly" then
			return Unit.isAlive(unit) and not Unit.canAttack(unit)
		end
		return false
	end,
})

register("unit_health_percent", {
	label = "Health percent",
	fields = { unit = "unit", op = "op", value = "percent" },
	describe = function(condition)
		return ("%s health %s %s%%"):format(condition.unit or "target", condition.op or "<", tostring(condition.value or 0))
	end,
	eval = function(condition)
		local unit = condition.unit
		if not Unit.isAlive(unit) then return false end
		return Compare.compare(Unit.healthPercent(unit), condition.op, tonumber(condition.value))
	end,
})

register("unit_health", {
	label = "Health (raw value)",
	-- raw is an unbounded number (not a 0-100 percent), rendered as a text
	-- input so values like 30000 are reachable
	fields = { unit = "unit", op = "op", value = "number" },
	describe = function(condition)
		return ("%s health %s %s"):format(condition.unit or "target", condition.op or "<", tostring(condition.value or 0))
	end,
	eval = function(condition)
		local unit = condition.unit
		if not Unit.isAlive(unit) then return false end
		return Compare.compare(Unit.health(unit), condition.op, tonumber(condition.value))
	end,
})

register("unit_power_percent", {
	label = "Power percent",
	fields = { unit = "unit", power = "power", op = "op", value = "percent" },
	optional = { power = true },  -- nil = current pool
	describe = function(condition)
		return ("%s %s %s %s%%"):format(condition.unit or "player", powerName(condition.power),
			condition.op or ">", tostring(condition.value or 0))
	end,
	eval = function(condition)
		local unit = condition.unit
		if not Unit.isAlive(unit) then return false end
		return Compare.compare(Unit.powerPercent(unit, condition.power), condition.op, tonumber(condition.value))
	end,
})

register("unit_power", {
	label = "Power (raw value)",
	-- raw is an unbounded number (not a 0-100 percent), rendered as a text
	-- input so values like 30000 are reachable
	fields = { unit = "unit", power = "power", op = "op", value = "number" },
	optional = { power = true },  -- nil = current pool
	describe = function(condition)
		return ("%s %s %s %s"):format(condition.unit or "player", powerName(condition.power),
			condition.op or ">", tostring(condition.value or 0))
	end,
	eval = function(condition)
		local unit = condition.unit
		if not Unit.isAlive(unit) then return false end
		return Compare.compare(Unit.power(unit, condition.power), condition.op, tonumber(condition.value))
	end,
})

register("unit_aura_present", {
	label = "Unit has aura",
	fields = { unit = "unit", aura = "string", kind = "kind", mine = "bool", op = "op", value = "percent" },
	-- mine defaults to false (checkbox init), op/value are nil for
	-- presence-only checks (no time comparison)
	optional = { mine = true, op = true, value = true },
	describe = function(condition)
		local base = ("%s has %s"):format(condition.unit or "target", condition.aura or "?")
		if condition.value and condition.value ~= "" then
			base = base .. (" with %s %ss left"):format(condition.op or "<", tostring(condition.value))
		end
		return base
	end,
	eval = function(condition)
		-- nil = absent; a number (even 0, a permanent aura) = present. The
		-- comparison uses the first return of findAura.
		local remaining = Aura.find(condition.unit, condition.aura, condition.kind, condition.mine)
		if remaining == nil then return false end
		local want = tonumber(condition.value)
		if not want then return true end
		return Compare.compare(remaining, condition.op, want)
	end,
})

register("unit_aura_missing", {
	label = "Unit is missing aura",
	fields = { unit = "unit", aura = "string", kind = "kind", mine = "bool" },
	optional = { mine = true },
	describe = function(condition)
		return ("%s is missing %s"):format(condition.unit or "target", condition.aura or "?")
	end,
	eval = function(condition)
		return Aura.find(condition.unit, condition.aura, condition.kind, condition.mine) == nil
	end,
})

register("unit_aura_stacks", {
	label = "Unit aura stack count",
	fields = { unit = "unit", aura = "string", kind = "kind", mine = "bool", op = "op", value = "percent" },
	optional = { mine = true },
	describe = function(condition)
		return ("%s stacks of %s %s %s"):format(condition.unit or "target", condition.aura or "?",
			condition.op or ">=", tostring(condition.value or 1))
	end,
	eval = function(condition)
		local _, stacks = Aura.find(condition.unit, condition.aura, condition.kind, condition.mine)
		if not stacks then return false end
		return Compare.compare(stacks, condition.op, tonumber(condition.value))
	end,
})

register("spell_ready", {
	label = "Spell is off cooldown",
	fields = { spell = "spell" },
	describe = function(condition)
		return ("%s is ready"):format(condition.spell or "?")
	end,
	eval = function(condition)
		if not condition.spell or condition.spell == "" then return false end
		local start, duration = Spell.cooldown(condition.spell)
		if not start then return false end
		if start == 0 then return true end
		-- a duration at or below GCD_DURATION is the global cooldown, not this
		-- spell's own.
		if Cooldown.isGCD(start, duration) then return true end
		return (start + duration) <= GetTime()
	end,
})
register("spell_usable", {
	label = "Spell is usable (known, enough resource)",
	fields = { spell = "spell" },
	describe = function(condition)
		return ("%s is usable"):format(condition.spell or "?")
	end,
	eval = function(condition)
		if not condition.spell or condition.spell == "" then return false end
		local usable, noMana = Spell.usable(condition.spell)
		return usable and not noMana
	end,
})

register("spell_cooldown_remaining", {
	label = "Spell cooldown remaining",
	fields = { spell = "spell", op = "op", value = "percent" },
	describe = function(condition)
		return ("%s cooldown %s %ss"):format(condition.spell or "?", condition.op or "<", tostring(condition.value or 0))
	end,
	eval = function(condition)
		if not condition.spell or condition.spell == "" then return false end
		local start, duration = Spell.cooldown(condition.spell)
		if not start then return false end
		local remaining = 0
		if Cooldown.isOwnCooldown(start, duration) then
			remaining = (start + duration) - GetTime()
			if remaining < 0 then remaining = 0 end
		end
		return Compare.compare(remaining, condition.op, tonumber(condition.value))
	end,
})

register("unit_exists", {
	label = "Unit exists and is alive",
	fields = { unit = "unit" },
	describe = function(condition)
		return ("%s exists"):format(condition.unit or "target")
	end,
	eval = function(condition)
		return Unit.isAlive(condition.unit)
	end,
})

register("unit_hostile", {
	label = "Unit is attackable",
	fields = { unit = "unit" },
	describe = function(condition)
		return ("%s is attackable"):format(condition.unit or "target")
	end,
	eval = function(condition)
		local unit = condition.unit
		return Unit.isAlive(unit) and Unit.canAttack(unit)
	end,
})

register("unit_casting", {
	label = "Unit is casting",
	fields = { unit = "unit" },
	describe = function(condition)
		return ("%s is casting"):format(condition.unit or "target")
	end,
	eval = function(condition)
		local unit = condition.unit
		return Unit.exists(unit) and Unit.isCasting(unit)
	end,
})

register("unit_moving", {
	label = "Unit is moving",
	fields = { unit = "unit" },
	describe = function(condition)
		return ("%s is moving"):format(condition.unit or "player")
	end,
	eval = function(condition)
		local speed = Unit.speed(condition.unit)
		return speed and speed > 0
	end,
})

register("unit_standing_still", {
	label = "Unit is standing still",
	fields = { unit = "unit" },
	describe = function(condition)
		return ("%s is standing still"):format(condition.unit or "player")
	end,
	eval = function(condition)
		local speed = Unit.speed(condition.unit)
		return not speed or speed == 0
	end,
})

register("unit_in_combat", {
	label = "Unit is in combat",
	fields = { unit = "unit" },
	describe = function(condition)
		return ("%s is in combat"):format(condition.unit or "player")
	end,
	eval = function(condition)
		return Unit.inCombat(condition.unit)
	end,
})

register("unit_range", {
	label = "Target is in range of a spell",
	fields = { spell = "spell", unit = "unit" },
	describe = function(condition)
		return ("%s in range of %s"):format(condition.unit or "target", condition.spell or "?")
	end,
	eval = function(condition)
		local unit = condition.unit
		if not condition.spell or condition.spell == "" or not Unit.exists(unit) then return false end
		return Spell.inRange(condition.spell, unit)
	end,
})

register("player_combo_points", {
	label = "Player combo points on target",
	-- Combo points only ever exist on the player's current target, so the
	-- unit is fixed to "target" and the condition has no unit field.
	fields = { op = "op", value = "percent" },
	describe = function(condition)
		return ("combo points %s %s"):format(condition.op or ">=", tostring(condition.value or 0))
	end,
	eval = function(condition)
		local points = Unit.comboPoints("target")
		if not points then return false end
		return Compare.compare(points, condition.op, tonumber(condition.value))
	end,
})

register("player_shapeshift_form", {
	label = "Player is in a shapeshift form",
	fields = { form = "string" },
	describe = function(condition)
		return ("in form %s"):format(condition.form or "?")
	end,
	eval = function(condition)
		if not condition.form or condition.form == "" then return false end
		return Unit.shapeshiftFormName() == condition.form
	end,
})

register("unit_casting_spell", {
	label = "Unit is casting a specific spell",
	fields = { unit = "unit", spell = "spell" },
	describe = function(condition)
		return ("%s is casting %s"):format(condition.unit or "target", condition.spell or "?")
	end,
	eval = function(condition)
		local unit = condition.unit
		if not condition.spell or condition.spell == "" or not Unit.exists(unit) then return false end
		return Unit.isCastingSpell(unit, condition.spell)
	end,
})

register("unit_cast_interruptible", {
	label = "Unit's cast is interruptible",
	fields = { unit = "unit" },
	describe = function(condition)
		return ("%s's cast is interruptible"):format(condition.unit or "target")
	end,
	eval = function(condition)
		local unit = condition.unit
		return Unit.exists(unit) and Unit.castInterruptible(unit)
	end,
})

register("unit_level", {
	label = "Unit level",
	fields = { unit = "unit", op = "op", value = "percent" },
	describe = function(condition)
		return ("%s level %s %s"):format(condition.unit or "target", condition.op or ">=", tostring(condition.value or 0))
	end,
	eval = function(condition)
		local unit = condition.unit
		if not Unit.exists(unit) then return false end
		return Compare.compare(Unit.level(unit), condition.op, tonumber(condition.value))
	end,
})

register("unit_is_player", {
	label = "Unit is a player",
	fields = { unit = "unit" },
	describe = function(condition)
		return ("%s is a player"):format(condition.unit or "target")
	end,
	eval = function(condition)
		local unit = condition.unit
		return Unit.exists(unit) and Unit.isPlayer(unit)
	end,
})

register("unit_classification", {
	label = "Unit classification",
	fields = { unit = "unit", value = "classification" },
	describe = function(condition)
		return ("%s is %s"):format(condition.unit or "target", condition.value or "normal")
	end,
	eval = function(condition)
		local unit = condition.unit
		if not Unit.exists(unit) then return false end
		return Unit.classification(unit) == (condition.value)
	end,
})

register("unit_threat_percent", {
	label = "Threat on unit (scaled percent)",
	fields = { unit = "unit", op = "op", value = "percent" },
	describe = function(condition)
		return ("threat on %s %s %s%%"):format(condition.unit or "target", condition.op or ">=", tostring(condition.value or 0))
	end,
	eval = function(condition)
		local unit = condition.unit
		if not Unit.exists(unit) then return false end
		local pct = Unit.threatPercent(unit)
		if not pct then return false end
		return Compare.compare(pct, condition.op, tonumber(condition.value))
	end,
})

register("unit_is_tanking", {
	label = "You are tanking the unit",
	fields = { unit = "unit" },
	describe = function(condition)
		return ("you are tanking %s"):format(condition.unit or "target")
	end,
	eval = function(condition)
		local unit = condition.unit
		return Unit.exists(unit) and Unit.isTanking(unit)
	end,
})

register("unit_aura_remains", {
	label = "Unit aura time remaining",
	fields = { unit = "unit", aura = "string", kind = "kind", mine = "bool", op = "op", value = "percent" },
	optional = { mine = true },
	describe = function(condition)
		return ("%s has %s with %s %ss left"):format(condition.unit or "target", condition.aura or "?",
			condition.op or ">", tostring(condition.value or 0))
	end,
	eval = function(condition)
		-- nil = absent. A permanent aura reports 0 remaining; 0 is a number,
		-- so it compares normally (0 > N fails for any positive N).
		local remaining = Aura.find(condition.unit, condition.aura, condition.kind, condition.mine)
		if remaining == nil then return false end
		return Compare.compare(remaining, condition.op, tonumber(condition.value))
	end,
})

register("modifier_keys", {
	label = "A modifier key is held",
	fields = { key = "modifier" },
	describe = function(condition)
		return ("%s is held"):format(condition.key or "shift")
	end,
	eval = function(condition)
		local key = condition.key
		if key == "control" then return Input.control() end
		if key == "alt" then return Input.alt() end
		return Input.shift()
	end,
})

-- The escape hatch. Ascension builds do things no fixed list covers, so this
-- type takes a Lua snippet that returns true or false. The snippet compiles
-- once and is cached. A broken snippet fails closed.
register("lua", {
	label = "Custom Lua (must return true or false)",
	fields = { code = "code" },
	describe = function(condition)
		local code = condition.code or ""
		if #code > SNIPPET_MAX then code = code:sub(1, SNIPPET_MAX) .. "..." end
		return "lua: " .. code
	end,
	eval = function(condition)
		if not condition.code or condition.code == "" then return false end
		if condition._compiledFor ~= condition.code then
			local fn, err = loadstring("return " .. condition.code)
			if not fn then
				fn = loadstring(condition.code)
			end
			condition._compiled = fn
			condition._compiledFor = condition.code
			condition._error = (not fn) and (err or "could not compile") or nil
		end
		if not condition._compiled then return false end
		local ok, result = pcall(condition._compiled)
		if not ok then return false end
		return result and true or false
	end,
})

-- ---------------------------------------------------------------------------
-- dispatch + editor access
-- ---------------------------------------------------------------------------

-- Eval runs one condition. It fails closed: a bad type, a missing eval, or an
-- eval error all return false.
-- legacyType maps pre-rename condition type keys to their current names, so
-- saved profiles from before a rename still load. Every rename adds a line
-- here; the key is the old stored value, the value is the current registry
-- key.
local legacyType = {
	health_pct = "unit_health_percent",
	power_pct = "unit_power_percent",
	target_type = "unit_target_type",
	health_percent = "unit_health_percent",
	power_percent = "unit_power_percent",
	aura_present = "unit_aura_present",
	aura_missing = "unit_aura_missing",
	aura_stacks = "unit_aura_stacks",
	aura_remains = "unit_aura_remains",
	cooldown_remaining = "spell_cooldown_remaining",
	moving = "unit_moving",
	standing_still = "unit_standing_still",
	in_combat = "unit_in_combat",
	range = "unit_range",
	combo_points = "player_combo_points",
	shapeshift_form = "player_shapeshift_form",
	cast_interruptible = "unit_cast_interruptible",
	threat_pct = "unit_threat_percent",
	is_tanking = "unit_is_tanking",
}

-- ResolveType maps a stored type key to its current name, migrating legacy
-- keys (health_pct -> health_percent). Every lookup path uses it so a saved
-- condition from before a rename keeps working without waiting for a profile
-- re-sanitize.
function Conditions.ResolveType(key)
	return legacyType[key] or key
end

function Conditions.Eval(condition)
	if type(condition) ~= "table" then return false end
	local def = Registry[Conditions.ResolveType(condition.type)]
	if type(def) ~= "table" or type(def.eval) ~= "function" then return false end
	-- completeness check: every declared field must be set. optional fields
	-- (listed in def.optional) may be nil (e.g. power = current pool).
	for field in pairs(def.fields) do
		if not (def.optional and def.optional[field]) then
			local v = condition[field]
			if v == nil or v == "" then return false end
		end
	end
	local ok, result = pcall(def.eval, condition)
	if not ok then return false end
	return result and true or false
end

-- Describe renders one condition as one line. It never errors.
function Conditions.Describe(condition)
	if type(condition) ~= "table" then return "(bad condition)" end
	local def = Registry[Conditions.ResolveType(condition.type)]
	if type(def) ~= "table" or type(def.describe) ~= "function" then return "(bad condition)" end
	local ok, text = pcall(def.describe, condition)
	if not ok or type(text) ~= "string" then return "(bad condition)" end
	return text
end

-- TypeList returns the ordered list of { key, label } for the editor dropdown.
function Conditions.TypeList()
	local list = {}
	for i = 1, #order do
		local key = order[i]
		list[i] = { key = key, label = Registry[key].label }
	end
	return list
end

-- Sanitize repairs one condition. It returns a clean table with only the
-- fields its type declares, or nil when the type is not known.
function Conditions.Sanitize(condition)
	if type(condition) ~= "table" then return nil end
	-- migrate legacy type keys before the registry lookup
	condition.type = legacyType[condition.type] or condition.type
	local def = Registry[condition.type]
	if type(def) ~= "table" then return nil end

	local clean = { type = condition.type }
	for field, fieldType in pairs(def.fields) do
		local raw = condition[field]
		if fieldType == "percent" or fieldType == "power" or fieldType == "number" then
			local n = tonumber(raw)
			if n then clean[field] = n end
		elseif fieldType == "bool" then
			clean[field] = raw == true and true or false
		elseif type(raw) == "string" then
			clean[field] = raw
		end
	end
	return clean
end

-- Dropdown value sets, used by the editor. Ordered arrays: the dropdown
-- builder derives the AceGUI map from the array, and the first element is
-- the default when a new condition is added. Powers stays number-keyed
-- (not an identity map) because the client's powerType is a number.
Conditions.Units = Constants.UNIT_TOKENS
Conditions.Ops = { "<", "<=", "==", "~=", ">", ">=" }
Conditions.Kinds = { "buff", "debuff" }
Conditions.TargetTypes = { "any", "enemy", "friendly", "player" }
Conditions.Classifications = { "normal", "elite", "rare", "rareelite", "worldboss" }
Conditions.Modifiers = { "shift", "control", "alt" }
-- Power pools: numeric powerType -> name. AceGUI's dropdown displays the
-- map's values and sorts the keys numerically, so keying by the client's
-- powerType (0 mana, 1 rage, 2 focus, 3 energy, 6 runic) shows the names
-- in order. Verified live: UnitPower accepts the type argument. An
-- unselected pool uses the unit's current one.
Conditions.Powers = { [0] = "mana", [1] = "rage", [2] = "focus", [3] = "energy", [6] = "runic" }

Conditions.Registry = Registry
Conditions.Order = order

ns.Conditions = Conditions
