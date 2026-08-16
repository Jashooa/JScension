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
--   number      a numeric value
--   spell       a spell name or numeric ID
--   string      a free string (an aura name)
--   kind        "buff" or "debuff"
--   bool        a boolean
--   target_type any, enemy, friendly, or player
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

-- ---------------------------------------------------------------------------
-- the registry entries
-- ---------------------------------------------------------------------------

register("target_type", {
	label = "Target type",
	fields = { unit = "unit", value = "target_type" },
	describe = function(condition)
		return ("%s is %s"):format(condition.unit or "target", condition.value or "enemy")
	end,
	eval = function(condition)
		local unit = condition.unit or "target"
		local want = condition.value or "enemy"
		if want == "any" then
			return Unit.unitOK(unit)
		elseif want == "player" then
			return unit == "player"
		elseif want == "enemy" then
			return Unit.unitOK(unit) and Unit.canAttack(unit)
		elseif want == "friendly" then
			return Unit.unitOK(unit) and not Unit.canAttack(unit)
		end
		return false
	end,
})

register("health_percent", {
	label = "Health percent",
	fields = { unit = "unit", op = "op", value = "number" },
	describe = function(condition)
		return ("%s health %s %s%%"):format(condition.unit or "target", condition.op or "<", tostring(condition.value or 0))
	end,
	eval = function(condition)
		local unit = condition.unit or "target"
		if not Unit.unitOK(unit) then return false end
		return Compare.compare(Unit.healthPercent(unit), condition.op or "<", tonumber(condition.value) or 0)
	end,
})

register("power_percent", {
	label = "Power percent (mana, rage, energy, runic)",
	fields = { unit = "unit", op = "op", value = "number" },
	describe = function(condition)
		return ("%s power %s %s%%"):format(condition.unit or "player", condition.op or ">", tostring(condition.value or 0))
	end,
	eval = function(condition)
		local unit = condition.unit or "player"
		if not Unit.unitOK(unit) then return false end
		return Compare.compare(Unit.powerPercent(unit), condition.op or ">", tonumber(condition.value) or 0)
	end,
})

register("aura_present", {
	label = "Aura is up",
	fields = { unit = "unit", aura = "string", kind = "kind", mine = "bool", op = "op", value = "number" },
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
		local remaining = Aura.find(condition.unit or "target", condition.aura, condition.kind or "buff", condition.mine)
		if remaining == nil then return false end
		local want = tonumber(condition.value)
		if not want then return true end
		return Compare.compare(remaining, condition.op or "<", want)
	end,
})

register("aura_missing", {
	label = "Aura missing",
	fields = { unit = "unit", aura = "string", kind = "kind", mine = "bool" },
	describe = function(condition)
		return ("%s is missing %s"):format(condition.unit or "target", condition.aura or "?")
	end,
	eval = function(condition)
		return Aura.find(condition.unit or "target", condition.aura, condition.kind or "buff", condition.mine) == nil
	end,
})

register("aura_stacks", {
	label = "Aura stack count",
	fields = { unit = "unit", aura = "string", kind = "kind", mine = "bool", op = "op", value = "number" },
	describe = function(condition)
		return ("%s stacks of %s %s %s"):format(condition.unit or "target", condition.aura or "?",
			condition.op or ">=", tostring(condition.value or 1))
	end,
	eval = function(condition)
		local _, stacks = Aura.find(condition.unit or "target", condition.aura, condition.kind or "buff", condition.mine)
		if not stacks then return false end
		return Compare.compare(stacks, condition.op or ">=", tonumber(condition.value) or 1)
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

register("cooldown_remaining", {
	label = "Cooldown remaining",
	fields = { spell = "spell", op = "op", value = "number" },
	describe = function(condition)
		return ("%s cooldown %s %ss"):format(condition.spell or "?", condition.op or "<", tostring(condition.value or 0))
	end,
	eval = function(condition)
		if not condition.spell or condition.spell == "" then return false end
		local start, duration = Spell.cooldown(condition.spell)
		if not start then return false end
		local remaining = 0
		if start > 0 and duration and duration > Constants.GCD_DURATION then
			remaining = (start + duration) - GetTime()
			if remaining < 0 then remaining = 0 end
		end
		return Compare.compare(remaining, condition.op or "<", tonumber(condition.value) or 0)
	end,
})

register("unit_exists", {
	label = "Unit exists and is alive",
	fields = { unit = "unit" },
	describe = function(condition)
		return ("%s exists"):format(condition.unit or "target")
	end,
	eval = function(condition)
		return Unit.unitOK(condition.unit or "target")
	end,
})

register("unit_hostile", {
	label = "Unit is attackable",
	fields = { unit = "unit" },
	describe = function(condition)
		return ("%s is attackable"):format(condition.unit or "target")
	end,
	eval = function(condition)
		local unit = condition.unit or "target"
		return Unit.unitOK(unit) and Unit.canAttack(unit)
	end,
})

register("unit_casting", {
	label = "Unit is casting",
	fields = { unit = "unit" },
	describe = function(condition)
		return ("%s is casting"):format(condition.unit or "target")
	end,
	eval = function(condition)
		local unit = condition.unit or "target"
		return Unit.exists(unit) and Unit.isCasting(unit)
	end,
})

register("moving", {
	label = "You are moving",
	fields = {},
	describe = function() return "you are moving" end,
	eval = function()
		local speed = Unit.speed("player")
		return speed and speed > 0
	end,
})

register("standing_still", {
	label = "You are standing still",
	fields = {},
	describe = function() return "you are standing still" end,
	eval = function()
		local speed = Unit.speed("player")
		return not speed or speed == 0
	end,
})

register("in_combat", {
	label = "You are in combat",
	fields = {},
	describe = function() return "you are in combat" end,
	eval = function() return Unit.inCombat("player") end,
})

register("range", {
	label = "Target is in range of a spell",
	fields = { spell = "spell", unit = "unit" },
	describe = function(condition)
		return ("%s in range of %s"):format(condition.unit or "target", condition.spell or "?")
	end,
	eval = function(condition)
		local unit = condition.unit or "target"
		if not condition.spell or condition.spell == "" or not Unit.exists(unit) then return false end
		return Spell.inRange(condition.spell, unit)
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
-- saved profiles from before the health_pct/power_pct rename still load.
local legacyType = {
	health_pct = "health_percent",
	power_pct = "power_percent",
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
		if fieldType == "number" then
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

-- Dropdown value sets, used by the editor.
Conditions.Units = Constants.UNIT_TOKENS
Conditions.Ops = { ["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=", ["=="] = "==", ["~="] = "~=" }
Conditions.Kinds = { buff = "buff", debuff = "debuff" }
Conditions.TargetTypes = { any = "any", enemy = "enemy", friendly = "friendly", player = "player" }

Conditions.Registry = Registry
Conditions.Order = order

ns.Conditions = Conditions
