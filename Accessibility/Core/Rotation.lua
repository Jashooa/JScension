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
local Constants = ns.Constants
local Log = ns.Log

-- A no-cooldown spell must wait this long before it can cast again. The
-- global cooldown spaces on-GCD spells; this window spaces off-GCD instant
-- spells so they do not fire on every tick.
local ANTI_SPAM_WINDOW = 2.5

local lastCastAt = {}       -- spell name -> time of last attempt
local lastAttemptTime = 0   -- time of last attempt (GCD fallback)

-- The result of the last emitted cast, for the status command.
Rotation.lastResult = { spell = nil, ok = nil, value = nil, err = nil }

-- spellReference returns the name-or-ID a rule casts with.
local function spellReference(rule)
	return SpellPicker.Ref(rule.spellID, rule.spell)
end

-- IsOnGCD returns true while the global cooldown is active. It probes a known
-- spell when one is configured; otherwise it uses the last-cast time.
function Rotation.IsOnGCD()
	local probe = Profile.current().gcdProbeSpell
	if probe and probe ~= "" then
		local start, duration = GetSpellCooldown(probe)
		if start and start > 0 and duration and duration <= Constants.GCD_DURATION then
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
	if unit ~= "player" and not (UnitExists(unit) and not UnitIsDeadOrGhost(unit)) then
		return false
	end

	-- gate 3: the spell must be known (skip when a numeric ID is set)
	if not (rule.spellID and rule.spellID > 0) and not SpellPicker.IsKnown(rule.spell) then
		return false
	end

	-- gate 4: the spell must be usable
	local usable, noMana = IsUsableSpell(spellReference(rule))
	if not usable or noMana then return false end

	-- gate 5: the spell's own cooldown must be up. A duration at or below
	-- GCD_DURATION is the global cooldown, which the GCD gate handles.
	local start, duration = GetSpellCooldown(spellReference(rule))
	if start and start > 0 and duration and duration > Constants.GCD_DURATION then
		-- a real cooldown is running: clear the anti-spam marker, the cooldown
		-- gate already spaces this spell
		lastCastAt[rule.spell] = nil
		if (start + duration) > GetTime() then return false end
	end

	-- gate 7: the target must be in range (skip for self-cast)
	if unit ~= "player" then
		if IsSpellInRange(spellReference(rule), unit) ~= 1 then return false end
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
	local ref = spellReference(rule)
	local castMs = select(4, GetSpellInfo(ref))
	local currentCast = select(1, UnitCastingInfo("player")) or select(1, UnitChannelInfo("player"))
	local refName = (type(ref) == "number") and select(1, GetSpellInfo(ref)) or ref
	if not (castMs and castMs > 0) and currentCast ~= refName then
		local t = lastCastAt[rule.spell]
		if t and (GetTime() - t) < ANTI_SPAM_WINDOW then return false end
	end

	return true
end

-- Emit attempts the cast and records the attempt for the GCD and anti-spam
-- gates. It stores the result for the status command.
local function Emit(rule)
	local unit = rule.unit or "target"
	local selfCast = (unit == "player")
	local now = GetTime()

	lastCastAt[rule.spell] = now
	lastAttemptTime = now

	local ok, value, err = Compatibility.Cast(rule.spell, rule.spellID, selfCast)
	Rotation.lastResult = { spell = rule.spell, ok = ok, value = value, err = err }
	return ok, value, err
end

-- NextRule returns the first rule that would pass every gate, or nil. It is
-- the same walk CastBest performs, without casting; the button uses it to show
-- the spell that a click would actually cast (the first PASSING rule, not the
-- first enabled one - an earlier blocked rule must not pin the icon).
function Rotation.NextRule()
	local profile = Profile.current()
	if UnitIsDeadOrGhost("player") then return nil end
	if not Compatibility.IsCompatible() then return nil end

	local rules = Profile.activeRules()
	for i = 1, #rules do
		local rule = rules[i]
		if rule.enabled and rule.spell and rule.spell ~= "" then
			if RulePasses(rule) then
				return rule
			end
		end
	end
	return nil
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
		Log.Write("cast", "blocked: on global cooldown")
		return false
	end
	if not Rotation.InQueueWindow() then
		Log.Write("cast", "blocked: outside the queue window")
		return false
	end
	local rule = Rotation.NextRule()
	if not rule then
		if UnitIsDeadOrGhost("player") then
			Log.Write("cast", "blocked: player dead")
		elseif not Compatibility.IsCompatible() then
			Log.Write("cast", "blocked: not compatible")
		else
			Log.Write("cast", "blocked: no passing rule")
		end
		return false
	end
	Emit(rule)
	Log.Write("cast", ("cast %s (rule %s)"):format(rule.spell, tostring(rule.name)))
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
