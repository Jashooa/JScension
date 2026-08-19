-- The condition registry definitions.
--
-- This module owns condition labels, ordered fields, descriptions, and
-- evaluators. Conditions.lua owns only the runtime facade and data mechanics.

local _, ns = ...

local ConditionDefinitions = {}
local SNIPPET_MAX = 40

function ConditionDefinitions.Build(conditions, dependencies)
	local Constants = dependencies.Constants
	local Compare = dependencies.Compare
	local Unit = dependencies.Unit
	local Aura = dependencies.Aura
	local Cooldown = dependencies.Cooldown
	local Spell = dependencies.Spell
	local Input = dependencies.Input
	assert(Constants and Compare and Unit and Aura and Cooldown and Spell and Input,
		"condition definitions require all game dependencies")

	local registry = conditions.Registry
	local order = {}

	local function register(key, definition)
		definition.key = key
		registry[key] = definition
		order[#order + 1] = key
	end

	local function powerName(power)
		if power == nil then return "power" end
		return conditions.Powers[power] or "power"
	end

	register("unit_target_type", {
		label = "Target type",
		fields = { { key = "unit", type = "unit" }, { key = "value", type = "target_type" } },
		describe = function(condition)
			return ("%s is %s"):format(condition.unit or "?", condition.value or "?")
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
		fields = { { key = "unit", type = "unit" }, { key = "op", type = "op" }, { key = "value", type = "percent" } },
		describe = function(condition)
			return ("%s health %s %s%%"):format(condition.unit or "?", condition.op or "?", tostring(condition.value or "?"))
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
		fields = { { key = "unit", type = "unit" }, { key = "op", type = "op" }, { key = "value", type = "number" } },
		describe = function(condition)
			return ("%s health %s %s"):format(condition.unit or "?", condition.op or "?", tostring(condition.value or "?"))
		end,
		eval = function(condition)
			local unit = condition.unit
			if not Unit.isAlive(unit) then return false end
			return Compare.compare(Unit.health(unit), condition.op, tonumber(condition.value))
		end,
	})

	register("unit_power_percent", {
		label = "Power percent",
		fields = { { key = "unit", type = "unit" }, { key = "power", type = "power" }, { key = "op", type = "op" }, { key = "value", type = "percent" } },
		optional = { power = true },  -- nil = current pool
		describe = function(condition)
			return ("%s %s %s %s%%"):format(condition.unit or "?", powerName(condition.power),
				condition.op or "?", tostring(condition.value or "?"))
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
		fields = { { key = "unit", type = "unit" }, { key = "power", type = "power" }, { key = "op", type = "op" }, { key = "value", type = "number" } },
		optional = { power = true },  -- nil = current pool
		describe = function(condition)
			return ("%s %s %s %s"):format(condition.unit or "?", powerName(condition.power),
				condition.op or "?", tostring(condition.value or "?"))
		end,
		eval = function(condition)
			local unit = condition.unit
			if not Unit.isAlive(unit) then return false end
			return Compare.compare(Unit.power(unit, condition.power), condition.op, tonumber(condition.value))
		end,
	})

	register("unit_aura_present", {
		label = "Unit has aura",
		fields = { { key = "unit", type = "unit" }, { key = "aura", type = "string" }, { key = "kind", type = "kind" }, { key = "mine", type = "bool" }, { key = "op", type = "op" }, { key = "value", type = "percent" } },
		-- mine defaults to false (checkbox init), op/value are nil for
		-- presence-only checks (no time comparison)
		optional = { mine = true, op = true, value = true },
		describe = function(condition)
			local base = ("%s has %s"):format(condition.unit or "?", condition.aura or "?")
			if condition.value and condition.value ~= "" then
				base = base .. (" with %s %ss left"):format(condition.op or "?", tostring(condition.value))
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
		fields = { { key = "unit", type = "unit" }, { key = "aura", type = "string" }, { key = "kind", type = "kind" }, { key = "mine", type = "bool" } },
		optional = { mine = true },
		describe = function(condition)
			return ("%s is missing %s"):format(condition.unit or "?", condition.aura or "?")
		end,
		eval = function(condition)
			return Aura.find(condition.unit, condition.aura, condition.kind, condition.mine) == nil
		end,
	})

	register("unit_aura_stacks", {
		label = "Unit aura stack count",
		fields = { { key = "unit", type = "unit" }, { key = "aura", type = "string" }, { key = "kind", type = "kind" }, { key = "mine", type = "bool" }, { key = "op", type = "op" }, { key = "value", type = "percent" } },
		optional = { mine = true },
		describe = function(condition)
			return ("%s stacks of %s %s %s"):format(condition.unit or "?", condition.aura or "?",
				condition.op or "?", tostring(condition.value or "?"))
		end,
		eval = function(condition)
			local _, stacks = Aura.find(condition.unit, condition.aura, condition.kind, condition.mine)
			if not stacks then return false end
			return Compare.compare(stacks, condition.op, tonumber(condition.value))
		end,
	})

	register("spell_ready", {
		label = "Spell is off cooldown",
		fields = { { key = "spell", type = "spell" } },
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
		fields = { { key = "spell", type = "spell" } },
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
		fields = { { key = "spell", type = "spell" }, { key = "op", type = "op" }, { key = "value", type = "percent" } },
		describe = function(condition)
			return ("%s cooldown %s %ss"):format(condition.spell or "?", condition.op or "?", tostring(condition.value or "?"))
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
		fields = { { key = "unit", type = "unit" } },
		describe = function(condition)
			return ("%s exists"):format(condition.unit or "?")
		end,
		eval = function(condition)
			return Unit.isAlive(condition.unit)
		end,
	})

	register("unit_hostile", {
		label = "Unit is attackable",
		fields = { { key = "unit", type = "unit" } },
		describe = function(condition)
			return ("%s is attackable"):format(condition.unit or "?")
		end,
		eval = function(condition)
			local unit = condition.unit
			return Unit.isAlive(unit) and Unit.canAttack(unit)
		end,
	})

	register("unit_casting", {
		label = "Unit is casting",
		fields = { { key = "unit", type = "unit" } },
		describe = function(condition)
			return ("%s is casting"):format(condition.unit or "?")
		end,
		eval = function(condition)
			local unit = condition.unit
			return Unit.exists(unit) and Unit.isCasting(unit)
		end,
	})

	register("unit_moving", {
		label = "Unit is moving",
		fields = { { key = "unit", type = "unit" } },
		describe = function(condition)
			return ("%s is moving"):format(condition.unit or "?")
		end,
		eval = function(condition)
			local speed = Unit.speed(condition.unit)
			return speed and speed > 0
		end,
	})

	register("unit_standing_still", {
		label = "Unit is standing still",
		fields = { { key = "unit", type = "unit" } },
		describe = function(condition)
			return ("%s is standing still"):format(condition.unit or "?")
		end,
		eval = function(condition)
			local speed = Unit.speed(condition.unit)
			return not speed or speed == 0
		end,
	})

	register("unit_in_combat", {
		label = "Unit is in combat",
		fields = { { key = "unit", type = "unit" } },
		describe = function(condition)
			return ("%s is in combat"):format(condition.unit or "?")
		end,
		eval = function(condition)
			return Unit.inCombat(condition.unit)
		end,
	})

	register("unit_range", {
		label = "Target is in range of a spell",
		fields = { { key = "spell", type = "spell" }, { key = "unit", type = "unit" } },
		describe = function(condition)
			return ("%s in range of %s"):format(condition.unit or "?", condition.spell or "?")
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
		fields = { { key = "op", type = "op" }, { key = "value", type = "percent" } },
		describe = function(condition)
			return ("combo points %s %s"):format(condition.op or "?", tostring(condition.value or "?"))
		end,
		eval = function(condition)
			local points = Unit.comboPoints("target")
			if not points then return false end
			return Compare.compare(points, condition.op, tonumber(condition.value))
		end,
	})

	register("player_shapeshift_form", {
		label = "Player is in a shapeshift form",
		fields = { { key = "form", type = "string" } },
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
		fields = { { key = "unit", type = "unit" }, { key = "spell", type = "spell" } },
		describe = function(condition)
			return ("%s is casting %s"):format(condition.unit or "?", condition.spell or "?")
		end,
		eval = function(condition)
			local unit = condition.unit
			if not condition.spell or condition.spell == "" or not Unit.exists(unit) then return false end
			return Unit.isCastingSpell(unit, condition.spell)
		end,
	})

	register("unit_cast_interruptible", {
		label = "Unit's cast is interruptible",
		fields = { { key = "unit", type = "unit" } },
		describe = function(condition)
			return ("%s's cast is interruptible"):format(condition.unit or "?")
		end,
		eval = function(condition)
			local unit = condition.unit
			return Unit.exists(unit) and Unit.castInterruptible(unit)
		end,
	})

	register("unit_level", {
		label = "Unit level",
		fields = { { key = "unit", type = "unit" }, { key = "op", type = "op" }, { key = "value", type = "percent" } },
		describe = function(condition)
			return ("%s level %s %s"):format(condition.unit or "?", condition.op or "?", tostring(condition.value or "?"))
		end,
		eval = function(condition)
			local unit = condition.unit
			if not Unit.exists(unit) then return false end
			return Compare.compare(Unit.level(unit), condition.op, tonumber(condition.value))
		end,
	})

	register("unit_is_player", {
		label = "Unit is a player",
		fields = { { key = "unit", type = "unit" } },
		describe = function(condition)
			return ("%s is a player"):format(condition.unit or "?")
		end,
		eval = function(condition)
			local unit = condition.unit
			return Unit.exists(unit) and Unit.isPlayer(unit)
		end,
	})

	register("unit_classification", {
		label = "Unit classification",
		fields = { { key = "unit", type = "unit" }, { key = "value", type = "classification" } },
		describe = function(condition)
			return ("%s is %s"):format(condition.unit or "?", condition.value or "?")
		end,
		eval = function(condition)
			local unit = condition.unit
			if not Unit.exists(unit) then return false end
			return Unit.classification(unit) == (condition.value)
		end,
	})

	register("unit_threat_percent", {
		label = "Threat on unit (scaled percent)",
		fields = { { key = "unit", type = "unit" }, { key = "op", type = "op" }, { key = "value", type = "percent" } },
		describe = function(condition)
			return ("threat on %s %s %s%%"):format(condition.unit or "?", condition.op or "?", tostring(condition.value or "?"))
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
		fields = { { key = "unit", type = "unit" } },
		describe = function(condition)
			return ("you are tanking %s"):format(condition.unit or "?")
		end,
		eval = function(condition)
			local unit = condition.unit
			return Unit.exists(unit) and Unit.isTanking(unit)
		end,
	})

	register("unit_aura_remains", {
		label = "Unit aura time remaining",
		fields = { { key = "unit", type = "unit" }, { key = "aura", type = "string" }, { key = "kind", type = "kind" }, { key = "mine", type = "bool" }, { key = "op", type = "op" }, { key = "value", type = "percent" } },
		optional = { mine = true },
		describe = function(condition)
			return ("%s has %s with %s %ss left"):format(condition.unit or "?", condition.aura or "?",
				condition.op or "?", tostring(condition.value or "?"))
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
		fields = { { key = "key", type = "modifier" } },
		describe = function(condition)
			return ("%s is held"):format(condition.key or "?")
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
		fields = { { key = "code", type = "code" } },
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

	return order
end

ns.ConditionDefinitions = ConditionDefinitions
