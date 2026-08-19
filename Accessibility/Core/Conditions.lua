-- The condition runtime facade.
--
-- ConditionDefinitions owns labels, ordered fields, descriptions, and
-- evaluators. This module owns dependency validation, legacy migration,
-- sanitization, completeness, and failure-closed dispatch.
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
local ConditionDefinitions = ns.ConditionDefinitions
assert(Constants and Compare and Unit and Aura and Cooldown and Spell and Input and ConditionDefinitions,
	"load order: Core/Conditions before its dependencies")

-- The derived fields the "lua" condition stores on its own table (compile
-- cache). copyRule strips these so a compiled function never reaches the
-- SavedVariables file. Declared here so the copy consults one list.
Conditions.CacheKeys = { _compiled = true, _compiledFor = true, _error = true }
local Registry = {}
local order = {}


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

function Conditions.IsComplete(condition)
	if type(condition) ~= "table" then return false end
	local conditionType = Conditions.ResolveType(condition.type)
	local def = Registry[conditionType]
	if type(def) ~= "table" then return false end
	for i = 1, #def.fields do
		local field = def.fields[i]
		if not (def.optional and def.optional[field.key]) then
			local value = condition[field.key]
			if value == nil or value == "" then return false end
		end
	end
	return true
end

function Conditions.FieldLabel(fieldKey)
	return tostring(fieldKey or ""):gsub("_", " ")
end

function Conditions.Fields(conditionType)
	local def = Registry[Conditions.ResolveType(conditionType)]
	return def and def.fields or nil
end

function Conditions.Eval(condition)
	if type(condition) ~= "table" then return false end
	-- disabled conditions are skipped
	if condition.enabled == false then return false end
	local def = Registry[Conditions.ResolveType(condition.type)]
	if type(def) ~= "table" or type(def.eval) ~= "function" then return false end
	if not Conditions.IsComplete(condition) then return false end
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
-- fields its type declares plus its common enabled flag, or nil when the
-- type is not known.
function Conditions.Sanitize(condition)
	if type(condition) ~= "table" then return nil end
	-- migrate legacy type keys before the registry lookup
	condition.type = legacyType[condition.type] or condition.type
	local def = Registry[condition.type]
	if type(def) ~= "table" then return nil end

	local clean = { type = condition.type }
	if type(condition.enabled) == "boolean" then clean.enabled = condition.enabled end
	for i = 1, #def.fields do
		local field = def.fields[i]
		local raw = condition[field.key]
		if field.type == "percent" or field.type == "power" or field.type == "number" then
			local n = tonumber(raw)
			if n then clean[field.key] = n end
		elseif field.type == "bool" then
			clean[field.key] = raw == true and true or false
		elseif type(raw) == "string" then
			clean[field.key] = raw
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
order = ConditionDefinitions.Build(Conditions, {
	Constants = Constants,
	Compare = Compare,
	Unit = Unit,
	Aura = Aura,
	Cooldown = Cooldown,
	Spell = Spell,
	Input = Input,
})
Conditions.Order = order

ns.Conditions = Conditions
