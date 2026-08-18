-- The rotation engine.
--
-- It walks the rule list top down and casts the first rule that passes every
-- gate. The order in the editor is the priority order. All logic here is
-- tainted: it reads state and calls Compatibility.Cast. It never calls a
-- protected function directly.

local _, ns = ...

local Rotation = {}

local Compatibility = ns.Compatibility
local Conditions = ns.Conditions
local SpellPicker = ns.SpellPicker
local Profile = ns.Profile
local Cooldown = ns.Cooldown
local Cast = ns.Cast
local Spell = ns.Spell
local Unit = ns.Unit
local Constants = ns.Constants
local Log = ns.Log
assert(Compatibility and Conditions and SpellPicker and Profile and Cooldown
	and Cast and Spell and Unit and Constants and Log,
	"load order: Core/Rotation before its dependencies")

-- A no-cooldown spell must wait this long before it can cast again. The
-- global cooldown spaces on-GCD spells; this window spaces off-GCD instant
-- spells so they do not fire on every tick.
local ANTI_SPAM_WINDOW = 2.5

local lastCastAt = {}       -- spell name -> time of last attempt
local lastAttemptTime = 0   -- time of last attempt (GCD fallback)

-- The result of the last emitted cast, for the status command.
Rotation.lastResult = { spell = nil, ok = nil, value = nil, err = nil }

-- IsOnGCD returns true while the global cooldown is active. It probes a known
-- spell when one is configured; otherwise it uses the last-cast time.
function Rotation.IsOnGCD()
	local probe = Profile.current().gcdProbeSpell
	if probe and probe ~= "" then
		local start, duration = Spell.cooldown(probe)
		if Cooldown.isGCD(start, duration) then
			return (start + duration) > GetTime()
		end
		return false
	end
	return (GetTime() - lastAttemptTime) < Constants.GCD_DURATION
end

-- RulePasses runs the per-spell gates. The global-cooldown gate is checked
-- once before the walk, not here.
local function RulePasses(rule)
	local unit = rule.unit or "target"

	-- gate 2: the target unit must exist and be alive (skip for self-cast)
	if unit ~= "player" and not Unit.isAlive(unit) then
		return false
	end

	-- gate 3: the spell must be known
	if not SpellPicker.IsKnown(rule.spell) then
		return false
	end

	-- gate 4: the spell must be usable
	local usable, noMana = Spell.usable(rule.spell)
	if not usable or noMana then return false end

	-- gate 5: the spell's own cooldown must be up. The global cooldown is
	-- handled by the GCD gate, not here.
	local start, duration = Spell.cooldown(rule.spell)
	if Cooldown.isOwnCooldown(start, duration) then
		-- a real cooldown is running: clear the anti-spam marker, the cooldown
		-- gate already spaces this spell
		lastCastAt[rule.spell] = nil
		if (start + duration) > GetTime() then return false end
	end

	-- gate 7: the target must be in range (skip for self-cast)
	if unit ~= "player" then
		if not Spell.inRange(rule.spell, unit) then return false end
	end

	-- gate 8: every condition must pass
	local conds = rule.conditions
	if conds then
		for i = 1, #conds do
			if not Conditions.Eval(conds[i]) then return false end
		end
	end

	-- gate 9: anti-spam for no-cooldown spells. A spell with a cast time is
	-- already spaced by its own cast, so queueing it early inside the queue
	-- window is safe and desired; the 2.5s window is longer than most casts
	-- and would otherwise block the re-send, breaking the queue. Anti-spam
	-- therefore only gates instant spells, and never a re-send of the spell
	-- currently being cast or channelled (that is a queue, not spam).
	local castMs = Spell.castTime(rule.spell)
	local castName = Cast.currentCast()
	if castName then castName = Spell.stripRank(castName) end
	local refName = Spell.stripRank(rule.spell)
	if not (castMs and castMs > 0) and castName ~= refName then
		local t = lastCastAt[rule.spell]
		if t and (GetTime() - t) < ANTI_SPAM_WINDOW then return false end
	end

	return true
end

-- Emit attempts the cast and records the attempt for the GCD and anti-spam
-- gates. It stores the result for the status command.
local function Emit(rule)
	local unit = rule.unit or "target"
	local now = GetTime()

	lastCastAt[rule.spell] = now
	lastAttemptTime = now

	local ok, value, err = Compatibility.Cast(rule.spell, unit)
	return ok, value, err
end

-- NextRule returns the first rule that would pass every gate, or nil. It is
-- the same walk CastBest performs, without casting; the button uses it to show
-- the spell that a click would actually cast (the first PASSING rule, not the
-- first enabled one - an earlier blocked rule must not pin the icon).
-- The second return is a short reason ("player dead", "not compatible", or
-- "no passing rule") so the caller can log it without re-deriving the checks.
function Rotation.NextRule()
	local profile = Profile.current()
	if Unit.isDeadOrGhost("player") then return nil, "player dead" end
	if not Compatibility.IsCompatible() then return nil, "not compatible" end

	local rules = Profile.activeRules()
	for i = 1, #rules do
		local rule = rules[i]
		if rule.enabled and rule.spell and rule.spell ~= "" then
			if RulePasses(rule) then
				return rule
			end
		end
	end
	return nil, "no passing rule"
end

-- InQueueWindow delegates to Game/Cast, which owns the queue-window logic.
function Rotation.InQueueWindow()
	return ns.Cast.inQueueWindow()
end

-- CastBest casts the first rule that passes every gate. It returns true when
-- a cast was attempted, false otherwise. The decision is logged so a session
-- can be debugged from the persisted ring buffer.
function Rotation.CastBest()
	if Rotation.IsOnGCD() then
		return true
	end
	if not Rotation.InQueueWindow() then
		return false
	end
	local rule = Rotation.NextRule()
	if not rule then
		return false
	end
	Emit(rule)
	local label = (rule.name and rule.name ~= "") and rule.name or rule.spell
	Log.Write("cast", ("cast %s (rule %s)"):format(rule.spell, label))
	return true
end

-- Simulate reports what CastBest would cast, without casting. It returns a
-- table of one-line strings, one per rule.
function Rotation.Simulate()
	local rules = Profile.activeRules()
	local lines = {}
	if not rules or #rules == 0 then
		lines[1] = "no rules"
		return lines
	end
	for i = 1, #rules do
		local rule = rules[i]
		local state
		if not rule.enabled then
			state = "disabled"
		elseif not rule.spell or rule.spell == "" then
			state = "no spell"
		elseif RulePasses(rule) then
			state = "would cast"
		else
			state = "blocked"
		end
		lines[#lines + 1] = ("%d. %s: %s"):format(i, rule.spell, state)
	end
	return lines
end

ns.Rotation = Rotation
