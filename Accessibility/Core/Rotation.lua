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
local Targeting = ns.Targeting
local Cooldown = ns.Cooldown
local Cast = ns.Cast
local Spell = ns.Spell
local Unit = ns.Unit
local Player = ns.Player
local Constants = ns.Constants
local Log = ns.Log
assert(Compatibility and Conditions and SpellPicker and Profile and Targeting and Cooldown
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

local function candidateGuid(selection)
	return selection and selection.candidate and selection.candidate.guid
end

local function candidateUnit(selection)
	local candidate = selection and selection.candidate
	return candidate and (candidate.unit or "target") or "target"
end

local function sameJitterCandidate(selection, guid)
	return selection and jitterPending.rule == selection.rule
		and jitterPending.spell == selection.rule.spell
		and jitterPending.unit == candidateUnit(selection)
		and jitterPending.guid == guid
end

local function armJitter(selection, guid, currentTime, window)
	jitterPending.rule = selection.rule
	jitterPending.spell = selection.rule.spell
	jitterPending.unit = candidateUnit(selection)
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
local function retryMatches(selection, guid)
	return selection
		and jitterPending.retry
		and sameSpell(jitterPending.retrySpell, selection.rule.spell)
		and jitterPending.retryUnit == candidateUnit(selection)
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
function Rotation.OnCastFailed(spell)
	local matchesAttempt = sameSpell(lastAttemptSpell, spell)
	local matchesActive = sameSpell(activeCastSpell, spell)
	if lastAttemptState == "queued" and matchesActive and matchesAttempt then
		activeCastSpell = nil
		return
	end
	if matchesAttempt and lastAttemptState ~= "succeeded" then
		clearPending()
		reconcileGcdAfterCancellation()
		lastAttemptState = "failed"
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

local function passesConditions(rule, contextUnit)
	local conditions = rule.conditions
	if not conditions then return true end
	for i = 1, #conditions do
		if not Conditions.Eval(conditions[i], contextUnit) then return false end
	end
	return true
end

local function passesAntiSpam(rule, selection, currentTime)
	local castMs = Spell.castTime(rule.spell)
	local castName = Cast.currentCast()
	if castName then castName = Spell.stripRank(castName) end
	local refName = Spell.stripRank(rule.spell)
	local antiSpamWindow = Profile.current().antiSpamWindow
	if retryMatches(selection, candidateGuid(selection)) then return true end
	if (castMs and castMs > 0) or castName == refName then return true end
	local lastAttemptAt = lastCastAt[rule.spell]
	if lastAttemptAt and (currentTime - lastAttemptAt) < antiSpamWindow then return false end
	return true
end

local function passesSpellGates(rule, currentTime)
	if Player.isMounted() then return false, "mounted" end
	if not SpellPicker.IsKnown(rule.spell) then return false, "not known" end
	if Spell.hasCharges(rule.spell) and Spell.currentCharges(rule.spell) <= 0 then
		return false, "no charges"
	end
	local start, duration = Spell.cooldown(rule.spell)
	if Cooldown.isOwnCooldown(start, duration) then
		lastCastAt[rule.spell] = nil
		if currentTime < (start + duration) then return false, "on cooldown" end
	end
	return true
end

local function passesCandidateUsability(rule, unit)
	local usable, noMana = Spell.usable(rule.spell)
	if noMana then return false, "no mana" end
	if usable then return true end
	local candidateGuid = Unit.guid(unit)
	local targetGuid = Unit.guid("target")
	if candidateGuid and targetGuid and candidateGuid ~= targetGuid then return true end
	return false, "not usable"
end

local function evaluateCandidate(rule, targetRule, candidate, currentTime)
	local selection = { rule = rule, targetRule = targetRule, candidate = candidate }
	local unit = candidate.unit
	if not unit or (candidate.dynamic and not Targeting.Apply(candidate)) or
		(not candidate.dynamic and Unit.guid(unit) ~= candidate.guid) then
		return false, "unit unavailable"
	end
	local ok, passes, reason = pcall(function()
		local targetPasses, targetReason = passesTargetGates(unit, rule.spell)
		if not targetPasses then return false, targetReason end
		local usablePasses, usableReason = passesCandidateUsability(rule, unit)
		if not usablePasses then return false, usableReason end
		if not passesConditions(rule, unit) then return false, "condition" end
		if not passesAntiSpam(rule, selection, currentTime) then return false, "anti-spam" end
		return true
	end)
	if not ok then return false, "candidate evaluation" end
	return passes, reason, selection
end

-- evaluateRule runs spell gates once, then walks ordered targeting rules and
-- each selector's ranked batch. Global GCD and queue-window gates stay outside.
local function evaluateRule(rule, currentTime)
	local spellPasses, spellReason = passesSpellGates(rule, currentTime)
	if not spellPasses then return false, nil, spellReason end
	local targetRules = rule.targetRules
	if type(targetRules) ~= "table" or #targetRules == 0 then
		return false, nil, "no target rule"
	end
	local excluded = {}
	local excludedList = {}
	local lastReason = "no target"
	for i = 1, #targetRules do
		local targetRule = targetRules[i]
		local candidates = Targeting.Resolve(targetRule, rule, false, excludedList, excluded)
		local candidateIndex
		for candidateIndex = 1, #candidates do
			local candidate = candidates[candidateIndex]
			if candidate and candidate.guid and not excluded[candidate.guid] then
				local passes, reason, selection =
					evaluateCandidate(rule, targetRule, candidate, currentTime)
				if passes then return true, selection end
				lastReason = reason or lastReason
				excluded[candidate.guid] = true
				excludedList[#excludedList + 1] = candidate.guid
			end
		end
	end
	return false, nil, lastReason
end

-- emitRule attempts the cast and records the attempt for the GCD and anti-spam
-- gates. Dynamic candidates remain on their unit tokens; no visible target
-- mutation occurs here.
local function emitRule(selection, currentTime)
	local rule = selection.rule
	local candidate = selection.candidate
	local unit = candidate.unit or "target"
	if candidate.dynamic and not Targeting.Apply(candidate) then
		return false, nil, "unit unavailable"
	end
	local currentCast = Cast.currentCast()
	lastCastAt[rule.spell] = currentTime
	lastAttemptTime = currentTime
	lastAttemptSpell = rule.spell
	lastAttemptState = currentCast and "queued" or "submitted"
	lastAttemptUnit = unit
	lastAttemptGuid = candidate.guid or Unit.guid(unit)
	activeCastSpell = currentCast and normalizedSpell(currentCast) or nil
	local ok, value, err = Compatibility.Cast(rule.spell, unit)
	Rotation.lastResult = { spell = rule.spell, ok = ok, value = value, err = err }
	return ok, value, err
end

local function passesGlobalConditions(rotation)
	local conditions = rotation.conditions
	if not conditions then return true end
	for i = 1, #conditions do
		if not Conditions.Eval(conditions[i]) then return false end
	end
	return true
end

local function selectNextRule(currentTime)
	local rotation = Profile.activeRotation()
	local lastSelectionReason
	if not passesGlobalConditions(rotation) then return nil, "global condition" end
	local rules = rotation.rules
	for i = 1, #rules do
		local rule = rules[i]
		if rule.enabled and rule.spell and rule.spell ~= "" then
			local passes, selection, reason = evaluateRule(rule, currentTime)
			if passes then return selection end
			if reason then lastSelectionReason = reason end
		end
	end
	return nil, lastSelectionReason
end

local function emitAndLog(selection, currentTime)
	local ok = emitRule(selection, currentTime)
	if not ok then return false end
	clearPending()
	local rule = selection.rule
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
	local selection, reason = selectNextRule(currentTime)
	if selection then return selection.rule end
	return nil, reason or "no passing rule"
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
		if Rotation.IsOnGCD(currentTime) or not Rotation.InQueueWindow() then return false end
		if Unit.isDeadOrGhost("player") then
			Log.Write("cast", "player dead")
			return false
		end
		if not Compatibility.IsCompatible() then
			Log.Write("cast", "not compatible")
			return false
		end
		local selection = selectNextRule(currentTime)
		if not selection then return false end
		return emitAndLog(selection, currentTime)
	end

	local jitterWindow = Profile.current().jitterWindow or Constants.DEFAULT_JITTER_WINDOW
	if jitterWindow <= 0 then
		clearJitter()
		if Rotation.IsOnGCD(currentTime) or not Rotation.InQueueWindow() then return false end
		if Unit.isDeadOrGhost("player") then
			Log.Write("cast", "player dead")
			return false
		end
		if not Compatibility.IsCompatible() then
			Log.Write("cast", "not compatible")
			return false
		end
		local selection = selectNextRule(currentTime)
		if not selection then return false end
		return emitAndLog(selection, currentTime)
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

	local selection = selectNextRule(currentTime)
	if not selection then
		clearPending()
		return false
	end
	local guid = candidateGuid(selection)
	if jitterPending.retry then
		if retryMatches(selection, guid) then
			if Rotation.IsOnGCD(currentTime) or not Rotation.InQueueWindow() then return false end
			return emitAndLog(selection, currentTime)
		end
		clearPending()
	end
	if jitterPending.window ~= jitterWindow or not sameJitterCandidate(selection, guid) then
		armJitter(selection, guid, currentTime, jitterWindow)
	end
	if currentTime < jitterPending.dueAt then return false end

	local releaseSelection = selectNextRule(currentTime)
	if not releaseSelection then
		clearJitter()
		return false
	end
	local releaseGuid = candidateGuid(releaseSelection)
	if releaseSelection.rule ~= jitterPending.rule
		or releaseSelection.rule.spell ~= jitterPending.spell
		or releaseGuid ~= jitterPending.guid then
		clearJitter()
		armJitter(releaseSelection, releaseGuid, currentTime, jitterWindow)
		return false
	end
	if Rotation.IsOnGCD(currentTime) or not Rotation.InQueueWindow() then return false end
	return emitAndLog(releaseSelection, currentTime)
end

-- Simulate reports what CastBest would cast, without casting. It returns a
-- table of one-line strings, one per rule.
function Rotation.Simulate()
	local rotation = Profile.activeRotation()
	local rules = rotation.rules
	local lines = {}
	if not rules or #rules == 0 then
		lines[1] = "no rules"
		return lines
	end
	local globalPasses = passesGlobalConditions(rotation)
	local currentTime = GetTime()
	local firstRuleIndex = 1
	if not globalPasses then
		lines[1] = "global: blocked: global condition"
		firstRuleIndex = 2
	end
	for i = 1, #rules do
		local rule = rules[i]
		local status
		if not rule.enabled then
			status = "disabled"
		elseif not rule.spell or rule.spell == "" then
			status = "no spell"
		else
			local passes, selection, reason = evaluateRule(rule, currentTime)
			if passes then
				local candidate = selection.candidate
				status = "would cast (" .. (candidate.unit or candidate.guid or "?") .. ")"
			else
				status = "blocked: " .. (reason or "?")
			end
		end
		lines[firstRuleIndex + i - 1] = ("%d. %s: %s"):format(i, rule.spell, status)
	end
	return lines
end

ns.Rotation = Rotation
