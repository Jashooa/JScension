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
local Player = ns.Player
local Constants = ns.Constants
local Log = ns.Log
assert(Compatibility and Conditions and SpellPicker and Profile and Cooldown
	and Cast and Spell and Unit and Player and Constants and Log,
	"load order: Core/Rotation before its dependencies")

-- The anti-spam window spaces repeated no-cooldown instant casts. The
-- sanitized profile owns its value so users can tune it without code changes.

local lastCastAt = {}       -- spell name -> time of last attempt
local lastAttemptTime = 0   -- time of last attempt (GCD fallback)
local jitterPending = {
	rule = nil,
	spell = nil,
	unit = nil,
	guid = nil,
	dueAt = nil,
	window = nil,
	retry = false,
	retrySpell = nil,
	retryUnit = nil,
	retryGuid = nil,
}

local function clearJitter()
	jitterPending.rule = nil
	jitterPending.spell = nil
	jitterPending.unit = nil
	jitterPending.guid = nil
	jitterPending.dueAt = nil
	jitterPending.window = nil
end

local function clearPending()
	clearJitter()
	jitterPending.retry = false
	jitterPending.retrySpell = nil
	jitterPending.retryUnit = nil
	jitterPending.retryGuid = nil
end

function Rotation.ClearJitter()
	clearPending()
end

local function candidateGuid(rule)
	return Unit.guid(rule.unit or "target")
end

local function sameJitterCandidate(rule, guid)
	return jitterPending.rule == rule
		and jitterPending.spell == rule.spell
		and jitterPending.unit == (rule.unit or "target")
		and jitterPending.guid == guid
end

local function armJitter(rule, guid, currentTime, window)
	jitterPending.rule = rule
	jitterPending.spell = rule.spell
	jitterPending.unit = rule.unit or "target"
	jitterPending.guid = guid
	jitterPending.dueAt = currentTime + math.random() * window
	jitterPending.window = window
end
local lastAttemptSpell
local lastAttemptState
local lastAttemptUnit
local lastAttemptGuid
local activeCastSpell

local function normalizedSpell(spell)
	return spell and Spell.stripRank(spell) or nil
end

local function sameSpell(first, second)
	if not first or not second then return false end
	return normalizedSpell(first) == normalizedSpell(second)
end

local function markImmediateRetry()
	if not lastAttemptSpell then return end
	local retrySpell = lastAttemptSpell
	local retryUnit = lastAttemptUnit
	local retryGuid = lastAttemptGuid
	clearPending()
	jitterPending.retry = true
	jitterPending.retrySpell = retrySpell
	jitterPending.retryUnit = retryUnit
	jitterPending.retryGuid = retryGuid
end

local function retryMatches(rule, guid)
	return jitterPending.retry
		and sameSpell(jitterPending.retrySpell, rule.spell)
		and jitterPending.retryUnit == (rule.unit or "target")
		and jitterPending.retryGuid == guid
end

local function reconcileGcdAfterCancellation()
	local probe = Profile.current().gcdProbeSpell
	if probe and probe ~= "" then return end
	if lastAttemptSpell then
		local start, duration = Spell.cooldown(lastAttemptSpell)
		if Cooldown.isGCD(start, duration) then
			lastAttemptTime = start
			return
		end
	end
	lastAttemptTime = 0
end

function Rotation.OnCastStarted(spell)
	activeCastSpell = normalizedSpell(spell)
	if sameSpell(lastAttemptSpell, spell) then
		lastAttemptState = "active"
	end
end

function Rotation.OnCastSucceeded(spell)
	if lastAttemptState == "queued"
		and activeCastSpell
		and sameSpell(activeCastSpell, spell)
		and sameSpell(lastAttemptSpell, spell) then
		return
	end
	if sameSpell(lastAttemptSpell, spell) then
		lastAttemptState = "succeeded"
		jitterPending.retry = false
	end
	if sameSpell(activeCastSpell, spell) then
		activeCastSpell = nil
	end
end

function Rotation.OnCastCancelled(spell)
	local matchesAttempt = sameSpell(lastAttemptSpell, spell)
	local matchesActive = sameSpell(activeCastSpell, spell)
	if lastAttemptState == "queued" and matchesActive and matchesAttempt then
		activeCastSpell = nil
		return
	end
	if matchesAttempt and lastAttemptState ~= "succeeded" then
		markImmediateRetry()
		reconcileGcdAfterCancellation()
		lastAttemptState = "cancelled"
	end
	if matchesActive then activeCastSpell = nil end
end



-- The result of the last emitted cast, for the status command.
Rotation.lastResult = { spell = nil, ok = nil, value = nil, err = nil }

-- IsOnGCD returns true while the global cooldown is active. It probes a known
-- spell when one is configured; otherwise it uses the last-cast time.
function Rotation.IsOnGCD(currentTime)
	currentTime = currentTime or GetTime()
	local probe = Profile.current().gcdProbeSpell
	if probe and probe ~= "" then
		local start, duration = Spell.cooldown(probe)
		if Cooldown.isGCD(start, duration) then
			return (start + duration) > currentTime
		end
		return false
	end
	return (currentTime - lastAttemptTime) < Constants.GCD_DURATION
end

local function passesTargetGates(unit, spell)
	if unit == "player" then return true end
	if not Unit.isAlive(unit) then return false, "target dead" end
	if Spell.inRange(spell, unit) == false then return false, "out of range" end
	local lineOfSight = Compatibility.LoS(unit)
	if lineOfSight ~= 1 then return false, "line of sight" end
	return true
end

local function passesConditions(rule)
	local conditions = rule.conditions
	if not conditions then return true end
	for i = 1, #conditions do
		if not Conditions.Eval(conditions[i]) then return false end
	end
	return true
end

local function passesAntiSpam(rule, unit, currentTime)
	local castMs = Spell.castTime(rule.spell)
	local castName = Cast.currentCast()
	if castName then castName = Spell.stripRank(castName) end
	local refName = Spell.stripRank(rule.spell)
	local antiSpamWindow = Profile.current().antiSpamWindow
	if retryMatches(rule, Unit.guid(unit)) then return true end
	if (castMs and castMs > 0) or castName == refName then return true end
	local lastAttemptAt = lastCastAt[rule.spell]
	if lastAttemptAt and (currentTime - lastAttemptAt) < antiSpamWindow then
		return false
	end
	return true
end

-- evaluateRule runs gates specific to one rule. Global GCD and queue-window
-- gates are handled by CastBest after rule selection.
local function evaluateRule(rule, currentTime)
	local unit = rule.unit or "target"
	if Player.isMounted() then return false, "mounted" end
	local targetPasses, targetReason = passesTargetGates(unit, rule.spell)
	if not targetPasses then return false, targetReason end
	if not SpellPicker.IsKnown(rule.spell) then return false, "not known" end

	local usable, noMana = Spell.usable(rule.spell)
	if not usable then return false, "not usable" end
	if noMana then return false, "no mana" end
	if Spell.hasCharges(rule.spell) and Spell.currentCharges(rule.spell) <= 0 then
		return false, "no charges"
	end

	local start, duration = Spell.cooldown(rule.spell)
	if Cooldown.isOwnCooldown(start, duration) then
		lastCastAt[rule.spell] = nil
		if currentTime < (start + duration) then return false, "on cooldown" end
	end

	if not passesConditions(rule) then return false, "condition" end
	if not passesAntiSpam(rule, unit, currentTime) then return false, "anti-spam" end
	return true
end

-- emitRule attempts the cast and records the attempt for the GCD and anti-spam
-- gates. It stores the result for the status command.
local function emitRule(rule, currentTime)
	local unit = rule.unit or "target"
	local currentCast = Cast.currentCast()

	lastCastAt[rule.spell] = currentTime
	lastAttemptTime = currentTime
	lastAttemptSpell = rule.spell
	lastAttemptState = currentCast and "queued" or "submitted"
	lastAttemptUnit = unit
	lastAttemptGuid = Unit.guid(unit)
	activeCastSpell = currentCast and normalizedSpell(currentCast) or nil

	local ok, value, err = Compatibility.Cast(rule.spell, unit)
	return ok, value, err
end

local function selectNextRule(currentTime)
	local rules = Profile.activeRules()
	for i = 1, #rules do
		local rule = rules[i]
		if rule.enabled and rule.spell and rule.spell ~= "" then
			local passes = evaluateRule(rule, currentTime)
			if passes then return rule end
		end
	end
	return nil
end
local function emitAndLog(rule, currentTime)
	emitRule(rule, currentTime)
	clearPending()
	local label = (rule.name and rule.name ~= "") and rule.name or rule.spell
	Log.Write("cast", ("cast %s (rule %s)"):format(rule.spell, label))
	return true
end


-- NextRule returns the first rule that would pass every gate, or nil. It is
-- the same walk CastBest performs, without casting; the button uses it to show
-- the spell that a click would actually cast.
-- The second return is a short reason ("player dead", "not compatible", or
-- "no passing rule") so the caller can log it without re-deriving the checks.
function Rotation.NextRule()
	local currentTime = GetTime()
	if Unit.isDeadOrGhost("player") then return nil, "player dead" end
	if not Compatibility.IsCompatible() then return nil, "not compatible" end
	local rule = selectNextRule(currentTime)
	if rule then return rule end
	return nil, "no passing rule"
end

-- InQueueWindow delegates to Game/Cast, which owns the queue-window logic.
function Rotation.InQueueWindow()
	return ns.Cast.inQueueWindow()
end

-- CastBest casts the first rule that passes every gate. It returns true when
function Rotation.CastBest(automatic)
	local currentTime = GetTime()

	if not automatic then
		clearPending()
		if Rotation.IsOnGCD(currentTime) then return false end
		if not Rotation.InQueueWindow() then return false end
		if Unit.isDeadOrGhost("player") then
			Log.Write("cast", "player dead")
			return false
		end
		if not Compatibility.IsCompatible() then
			Log.Write("cast", "not compatible")
			return false
		end
		local rule = selectNextRule(currentTime)
		if not rule then return false end
		return emitAndLog(rule, currentTime)
	end

	local jitterWindow = Profile.current().jitterWindow or Constants.DEFAULT_JITTER_WINDOW
	if jitterWindow <= 0 then
		clearJitter()
		if Rotation.IsOnGCD(currentTime) then return false end
		if not Rotation.InQueueWindow() then return false end
		if Unit.isDeadOrGhost("player") then
			Log.Write("cast", "player dead")
			return false
		end
		if not Compatibility.IsCompatible() then
			Log.Write("cast", "not compatible")
			return false
		end
		local rule = selectNextRule(currentTime)
		if not rule then return false end
		return emitAndLog(rule, currentTime)
	end

	if Unit.isDeadOrGhost("player") then
		clearPending()
		Log.Write("cast", "player dead")
		return false
	end
	if not Compatibility.IsCompatible() then
		clearPending()
		Log.Write("cast", "not compatible")
		return false
	end

	local rule = selectNextRule(currentTime)
	if not rule then
		clearPending()
		return false
	end
	local guid = candidateGuid(rule)
	if jitterPending.retry then
		if retryMatches(rule, guid) then
			if Rotation.IsOnGCD(currentTime) or not Rotation.InQueueWindow() then return false end
			return emitAndLog(rule, currentTime)
		end
		clearPending()
	end
	if jitterPending.window ~= jitterWindow or not sameJitterCandidate(rule, guid) then
		armJitter(rule, guid, currentTime, jitterWindow)
	end

	if currentTime < jitterPending.dueAt then return false end
	local releaseRule = selectNextRule(currentTime)
	if not releaseRule then
		clearJitter()
		return false
	end
	local releaseGuid = candidateGuid(releaseRule)
	if releaseRule ~= jitterPending.rule
		or releaseRule.spell ~= jitterPending.spell
		or releaseGuid ~= jitterPending.guid then
		clearJitter()
		armJitter(releaseRule, releaseGuid, currentTime, jitterWindow)
		return false
	end
	if Rotation.IsOnGCD(currentTime) or not Rotation.InQueueWindow() then return false end
	return emitAndLog(releaseRule, currentTime)
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
	local currentTime = GetTime()
	for i = 1, #rules do
		local rule = rules[i]
		local status
		if not rule.enabled then
			status = "disabled"
		elseif not rule.spell or rule.spell == "" then
			status = "no spell"
		else
			local passes, reason = evaluateRule(rule, currentTime)
			status = passes and "would cast" or ("blocked: " .. (reason or "?"))
		end
		lines[#lines + 1] = ("%d. %s: %s"):format(i, rule.spell, status)
	end
	return lines
end

ns.Rotation = Rotation
