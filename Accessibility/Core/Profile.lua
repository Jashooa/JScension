-- The saved-variables schema: defaults and sanitization.
--
-- AceDB owns the AccessibilityDB global. This file holds the defaults table,
-- the sanitize function that repairs a profile after load, and the rotation
-- CRUD helpers the editor calls. A bad value in a saved variable must never
-- reach the engine or the editor.
--
-- Schema:
--   profile.rotations = ordered array of { name, rules }
--   profile.active     = name of the active rotation
-- The old flat `rules` array migrates into one rotation named "Default".

local _, ns = ...

local Profile = {}

-- The fallback rotation name: defaults, legacy migration, empty-list repair,
-- and the un-sanitized fallback all use it.
local DEFAULT_ROTATION_NAME = "Default"

function Profile.newRotation(name)
	return { name = name, rules = {} }
end

function Profile.newRule()
	return { name = "", spell = "", enabled = true, conditions = {} }
end

function Profile.newCondition()
	return { type = "unit_target_type", enabled = true, negated = false }
end

-- ---------------------------------------------------------------------------
-- defaults
-- ---------------------------------------------------------------------------
Profile.defaults = {
	profile = {
		auto = false,
		pulseInterval = 0.1,
		gcdProbeSpell = "",
		queueWindow = 0.4,   -- seconds; 0 disables early-queueing
		antiSpamWindow = ns.Constants.DEFAULT_ANTI_SPAM_WINDOW,
		active = DEFAULT_ROTATION_NAME,
		rotations = {
			Profile.newRotation(DEFAULT_ROTATION_NAME),
		},
		button = {
			enabled = true,   -- false hides the cast button
			point = "CENTER",
			relativePoint = "CENTER",
			x = 0,
			y = 0,
			scale = 1.0,
			locked = false,
		},
	},
}

-- current returns the live profile. Core sets the db before the first call.
function Profile.current()
	return ns.addon.db.profile
end
-- coercion helpers come from Utils/Coerce
local asBool = ns.Coerce.asBool
local asString = ns.Coerce.asString
local asNumber = ns.Coerce.asNumber
local Constants = ns.Constants
local function clamp(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, value))
end
assert(asBool and asString and asNumber and Constants, "load order: Core/Profile before Coerce/Constants")

-- ---------------------------------------------------------------------------
-- rule sanitization
-- ---------------------------------------------------------------------------

-- sanitizeRule repairs one rule. It returns a clean table, or nil when the
-- rule has no spell. Each condition goes through the registry sanitizer, so an
-- unknown condition type is dropped, not kept.
local function sanitizeRule(rule)
	if type(rule) ~= "table" then return nil end

	local spell = asString(rule.spell, "")
	if spell == "" then return nil end

	local unit = asString(rule.unit)

	local clean = {
		name = asString(rule.name, spell),
		spell = spell,
		enabled = asBool(rule.enabled, true),
		unit = unit,
		conditions = {},
	}

	if type(rule.conditions) == "table" then
		for i = 1, #rule.conditions do
			local condition = ns.Conditions and ns.Conditions.Sanitize(rule.conditions[i]) or nil
			if condition then
				clean.conditions[#clean.conditions + 1] = condition
			end
		end
	end

	return clean
end

-- sanitizeRotation repairs one rotation. It always returns a valid rotation.
local function sanitizeRotation(rotation)
	if type(rotation) ~= "table" then
		return Profile.newRotation("Rotation")
	end
	local name = asString(rotation.name, "")
	if name == "" then name = "Rotation" end

	local clean = Profile.newRotation(name)
	local rules = type(rotation.rules) == "table" and rotation.rules or {}
	for i = 1, #rules do
		local r = sanitizeRule(rules[i])
		if r then
			clean.rules[#clean.rules + 1] = r
		end
	end
	return clean
end

-- ---------------------------------------------------------------------------
-- profile sanitization
-- ---------------------------------------------------------------------------

-- sanitizeProfile repairs the whole profile in place. It must not error: a
-- broken saved variable degrades to defaults, it does not crash the addon.
function Profile.sanitizeProfile(p)
	if type(p) ~= "table" then return end

	p.auto = asBool(p.auto, false)
	p.pulseInterval = math.max(0.05, asNumber(p.pulseInterval, 0.1))
	p.gcdProbeSpell = asString(p.gcdProbeSpell, "")
	-- queue window: 0 (off) .. 1.0s, matching the client CVar's practical range
	p.queueWindow = math.max(0, math.min(1.0, asNumber(p.queueWindow, 0.4)))
	-- anti-spam window: 0 (off) .. 2.0s for no-cooldown instant spells
	p.antiSpamWindow = clamp(asNumber(p.antiSpamWindow, Constants.DEFAULT_ANTI_SPAM_WINDOW), 0, 2.0)
	-- migrate the old flat rules array into one "Default" rotation
	local srcRotations = p.rotations
	if type(srcRotations) ~= "table" then
		local legacy = type(p.rules) == "table" and p.rules or {}
		srcRotations = { { name = DEFAULT_ROTATION_NAME, rules = legacy } }
	end
	p.rules = nil

	local clean = {}
	local seen = {}
	for i = 1, #srcRotations do
		local rotation = sanitizeRotation(srcRotations[i])
		-- make names unique so the active-by-name pointer is unambiguous
		local name = rotation.name
		if seen[name] then
			local n = 2
			while seen[name .. " (" .. n .. ")"] do n = n + 1 end
			name = name .. " (" .. n .. ")"
			rotation.name = name
		end
		seen[name] = true
		clean[#clean + 1] = rotation
	end
	if #clean == 0 then
		clean[1] = Profile.newRotation(DEFAULT_ROTATION_NAME)
	end
	p.rotations = clean

	-- active must name an existing rotation, else the first one
	local active = asString(p.active, "")
	local found = false
	for i = 1, #clean do
		if clean[i].name == active then found = true end
	end
	if not found then active = clean[1].name end
	p.active = active

	if type(p.button) ~= "table" then p.button = {} end
	local b = p.button
	b.enabled = asBool(b.enabled, true)
	b.point = asString(b.point, "CENTER")
	b.relativePoint = asString(b.relativePoint, "CENTER")
	b.x = asNumber(b.x, 0)
	b.y = asNumber(b.y, 0)
	b.scale = math.max(0.5, math.min(2.0, asNumber(b.scale, 1.0)))
	b.locked = asBool(b.locked, false)
end

-- ---------------------------------------------------------------------------
-- rotation access
-- ---------------------------------------------------------------------------

-- rotations returns the ordered rotation array. It never returns nil: an
-- un-sanitized profile (panel opened before Core sanitizes) degrades to the
-- default single rotation instead of erroring.
function Profile.rotations()
	local p = Profile.current()
	if type(p.rotations) ~= "table" then
		p.rotations = { { name = DEFAULT_ROTATION_NAME, rules = {} } }
		p.active = p.active or DEFAULT_ROTATION_NAME
	end
	return p.rotations
end

-- activeRotation returns the active rotation object. It falls back to the
-- first rotation when the active name does not resolve (should not happen
-- after sanitize).
function Profile.activeRotation()
	local p = Profile.current()
	local list = Profile.rotations()
	local name = p.active
	for i = 1, #list do
		if list[i].name == name then
			return list[i]
		end
	end
	return list[1]
end

-- activeRules returns the active rotation's rule array.
function Profile.activeRules()
	return Profile.activeRotation().rules
end

-- ---------------------------------------------------------------------------
-- rotation CRUD (the editor calls these; each mutates the live profile)
-- ---------------------------------------------------------------------------

local function uniqueName(base)
	local p = Profile.current()
	local name = base
	local n = 2
	while true do
		local taken = false
		for i = 1, #p.rotations do
			if p.rotations[i].name == name then taken = true end
		end
		if not taken then return name end
		name = base .. " (" .. n .. ")"
		n = n + 1
	end
end

-- RULE_FIELDS lists every scalar field a rule carries, in the order a copy
-- must reproduce them. copyRule walks it so a new field is copied without a
-- second edit here. conditions is a list and is deep-copied separately.
local RULE_FIELDS = { "name", "spell", "enabled", "unit" }

-- copyRule deep-copies one rule (conditions included), stripping the derived
-- compile cache the "lua" condition type stores on its table. The cache keys
-- are declared in Conditions.CacheKeys (resolved at call time: Conditions
-- loads after Profile).
local function copyRule(rule)
	local cacheKeys = ns.Conditions and ns.Conditions.CacheKeys or {}
	local copy = { conditions = {} }
	for i = 1, #RULE_FIELDS do
		copy[RULE_FIELDS[i]] = rule[RULE_FIELDS[i]]
	end
	for i = 1, #rule.conditions do
		local src = rule.conditions[i]
		local condition = {}
		for k, v in pairs(src) do
			if not cacheKeys[k] then
				condition[k] = v
			end
		end
		copy.conditions[i] = condition
	end
	return copy
end

function Profile.addRotation(name)
	local rotation = Profile.newRotation(uniqueName(name or "Rotation"))
	Profile.rotations()[#Profile.rotations() + 1] = rotation
	return rotation
end

function Profile.duplicateRotation(rotation)
	local copy = Profile.newRotation(uniqueName(rotation.name .. " copy"))
	for i = 1, #rotation.rules do
		copy.rules[i] = copyRule(rotation.rules[i])
	end
	Profile.rotations()[#Profile.rotations() + 1] = copy
	return copy
end

-- deleteRotation removes a rotation. It refuses to delete the last one, so the
-- active pointer always has a target.
function Profile.deleteRotation(rotation)
	local list = Profile.rotations()
	if #list <= 1 then return false end
	for i = 1, #list do
		if list[i] == rotation then
			table.remove(list, i)
			if Profile.current().active == rotation.name then
				Profile.current().active = list[1].name
			end
			return true
		end
	end
	return false
end

-- renameRotation sets a rotation's name, keeping the active pointer in sync.
-- A name already taken by another rotation is refused, matching addRotation.
function Profile.renameRotation(rotation, newName)
	newName = newName or ""
	newName = newName:match("^%s*(.-)%s*$") or ""
	if newName == "" then return false end
	for i = 1, #Profile.rotations() do
		local other = Profile.rotations()[i]
		if other ~= rotation and other.name == newName then return false end
	end
	if Profile.current().active == rotation.name then
		Profile.current().active = newName
	end
	rotation.name = newName
	return true
end

-- setActive makes a rotation the active one.
function Profile.setActive(rotation)
	Profile.current().active = rotation.name
end

-- setActiveByName makes the rotation with the given name active. It is a
-- no-op when no rotation matches (the dropdown only offers real names).
function Profile.setActiveByName(name)
	local list = Profile.rotations()
	for i = 1, #list do
		if list[i].name == name then
			Profile.current().active = name
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- rule CRUD on a given rotation
-- ---------------------------------------------------------------------------

function Profile.addRule(rotation)
	rotation.rules[#rotation.rules + 1] = Profile.newRule()
end

function Profile.deleteRule(rotation, index)
	if index < 1 or index > #rotation.rules then return end
	table.remove(rotation.rules, index)
end

function Profile.addCondition(rule)
	rule.conditions[#rule.conditions + 1] = Profile.newCondition()
end

-- deleteCondition removes a condition from a rule.
function Profile.deleteCondition(rule, index)
	if index < 1 or index > #rule.conditions then return end
	table.remove(rule.conditions, index)
end

-- moveRule reorders a rule within its rotation.
function Profile.moveRule(rotation, from, to)
	local rules = rotation.rules
	if to < 1 or to > #rules or from < 1 or from > #rules or from == to then
		return
	end
	local rule = table.remove(rules, from)
	table.insert(rules, to, rule)
end
-- ---------------------------------------------------------------------------
-- persisted field mutation
-- ---------------------------------------------------------------------------


function Profile.setRuleEnabled(rule, enabled)
	rule.enabled = asBool(enabled, true)
end

function Profile.setRuleName(rule, name)
	rule.name = asString(name, "")
end

function Profile.setRuleSpell(rule, spell)
	rule.spell = asString(spell, "")
end

function Profile.setRuleUnit(rule, unit)
	rule.unit = asString(unit)
end

function Profile.setConditionEnabled(condition, enabled)
	condition.enabled = asBool(enabled, true)
end

function Profile.setConditionNegated(condition, negated)
	condition.negated = asBool(negated, false)
end

function Profile.setConditionType(condition, conditionType)
	if type(condition) ~= "table" or not ns.Conditions then return false end
	local enabled = asBool(condition.enabled, true)
	local negated = asBool(condition.negated, false)
	condition.type = asString(conditionType, condition.type)
	local clean = ns.Conditions.Sanitize(condition)
	if not clean then return false end
	clean.enabled = enabled
	clean.negated = negated
	for key in pairs(condition) do condition[key] = nil end
	for key, value in pairs(clean) do condition[key] = value end
	return true
end

function Profile.setConditionField(condition, fieldKey, value)
	if type(condition) ~= "table" or not ns.Conditions then return false end
	local fields = ns.Conditions.Fields(condition.type)
	if not fields then return false end
	for i = 1, #fields do
		local field = fields[i]
		if field.key == fieldKey then
			local fieldValue
			if field.type == "percent" or field.type == "power" or field.type == "number" then
				fieldValue = asNumber(value)
			elseif field.type == "bool" then
				fieldValue = asBool(value, false)
			else
				fieldValue = asString(value)
			end
			condition[fieldKey] = fieldValue
			return true
		end
	end
	return false
end

function Profile.setButtonEnabled(button, enabled)
	button.enabled = asBool(enabled, true)
end

function Profile.setButtonLocked(button, locked)
	button.locked = asBool(locked, false)
end

function Profile.setButtonPosition(button, point, relativePoint, x, y)
	button.point = asString(point, "CENTER")
	button.relativePoint = asString(relativePoint, "CENTER")
	button.x = asNumber(x, 0)
	button.y = asNumber(y, 0)
end

function Profile.setButtonScale(button, scale)
	button.scale = clamp(asNumber(scale, 1.0), 0.5, 2.0)
end

function Profile.setAutoEnabled(enabled)
	Profile.current().auto = asBool(enabled, false)
end

function Profile.setGcdProbeSpell(spell)
	Profile.current().gcdProbeSpell = asString(spell, "")
end

function Profile.setPulseInterval(seconds)
	Profile.current().pulseInterval = math.max(0.05, asNumber(seconds, 0.1))
end

function Profile.setAntiSpamWindow(seconds)
	Profile.current().antiSpamWindow = clamp(asNumber(seconds, Constants.DEFAULT_ANTI_SPAM_WINDOW), 0, 2.0)
end
function Profile.setQueueWindow(seconds)
	Profile.current().queueWindow = clamp(asNumber(seconds, Constants.DEFAULT_QUEUE_WINDOW), 0, 1.0)
end


ns.Profile = Profile
