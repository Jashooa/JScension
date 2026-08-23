-- Ordered target-rule resolution shared by Rotation and the editor.
-- Dynamic candidates are ranked once by Compatibility and then walked in order.

local _, ns = ...

local Targeting = {}
local Compatibility = ns.Compatibility
local Unit = ns.Unit
local Constants = ns.Constants
assert(Compatibility and Unit and Constants, "load order: Core/Targeting after Compatibility and Unit")

Targeting.MAX_TARGET_RULES = 64
Targeting.MAX_NAMEPLATE_TOKENS = 40
Targeting.TARGET_REFRESH_INTERVAL = 0.25
Targeting.Types = { "fixed", "enemy", "enemy_player", "enemy_npc", "friendly_player" }
Targeting.Priorities = {
	"lowest_health_percent", "highest_health_percent", "most_missing_health", "closest", "farthest",
}
Targeting.FixedUnits = Constants.UNIT_TOKENS

local VALID_TYPES = {}
local VALID_PRIORITIES = {}
local VALID_UNITS = {}
for i = 1, #Targeting.Types do VALID_TYPES[Targeting.Types[i]] = true end
for i = 1, #Targeting.Priorities do VALID_PRIORITIES[Targeting.Priorities[i]] = true end
for i = 1, #Targeting.FixedUnits do VALID_UNITS[Targeting.FixedUnits[i]] = true end
Targeting.ValidTypes = VALID_TYPES
Targeting.ValidPriorities = VALID_PRIORITIES
Targeting.ValidUnits = VALID_UNITS

local cache = {}

local function canonicalGuid(guid)
	if type(guid) ~= "string" then return "0" end
	local value = guid:lower():gsub("^0x", ""):gsub("^0+", "")
	return value == "" and "0" or value
end

local function guidKey(guid)
	return canonicalGuid(guid)
end

local function guidEqual(first, second)
	return canonicalGuid(first) == canonicalGuid(second)
end

local function addRosterEntry(entries, seen, token)
	local guid = Unit.guid(token)
	local key = canonicalGuid(guid)
	if not guid or seen[key] or not Unit.exists(token) then return end
	if token ~= "player" and (not Unit.isPlayer(token) or not Unit.isFriendly(token)) then return end
	seen[key] = true
	entries[#entries + 1] = { token = token, guid = guid }
end

local function friendlyRoster()
	local entries = {}
	local seen = {}
	addRosterEntry(entries, seen, "player")
	if IsInRaid and IsInRaid() then
		local count = GetNumRaidMembers and GetNumRaidMembers() or 0
		for i = 1, count do addRosterEntry(entries, seen, "raid" .. i) end
	else
		local count = GetNumPartyMembers and GetNumPartyMembers() or 0
		for i = 1, count do addRosterEntry(entries, seen, "party" .. i) end
	end
	return entries
end
local function nameplateTokens()
	local byGuid = {}
	local signature = {}
	for i = 1, Targeting.MAX_NAMEPLATE_TOKENS do
		local token = "nameplate" .. i
		local guid = Unit.guid(token)
		if guid then
			local key = canonicalGuid(guid)
			byGuid[key] = token
			signature[#signature + 1] = key .. "=" .. token
		end
	end
	return byGuid, table.concat(signature, ",")
end


local function excludedSet(excludedGuids)
	local set = {}
	for i = 1, #(excludedGuids or {}) do set[canonicalGuid(excludedGuids[i])] = true end
	return set
end

local function exclusionKey(excludedGuids)
	local parts = {}
	for i = 1, #(excludedGuids or {}) do parts[i] = canonicalGuid(excludedGuids[i]) end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function cacheKey(targetRule, excludedGuids, rosterEntries, nameplateSignature)
	local current = guidKey(Unit.guid("target"))
	local roster = {}
	for i = 1, #(rosterEntries or {}) do roster[i] = rosterEntries[i].guid end
	return table.concat({ current, tostring(targetRule.type), tostring(targetRule.unit),
		tostring(targetRule.priority), tostring(targetRule.maxDistance),
		table.concat(roster, ","), nameplateSignature or "", exclusionKey(excludedGuids) }, "|")
end

local function fixedCandidates(targetRule, excluded)
	local unit = targetRule.unit
	local guid = unit and Unit.guid(unit)
	if not guid or excluded[canonicalGuid(guid)] then return {} end
	return { { unit = unit, guid = guid, dynamic = false } }
end

local function dynamicCandidates(targetRule, excludedGuids, rosterEntries, nameplates)
	local allowed = {}
	local rosterByIndex = {}
	if targetRule.type == "friendly_player" then
		for i = 1, #rosterEntries do
			allowed[i] = rosterEntries[i].guid
			rosterByIndex[i - 1] = rosterEntries[i].token
		end
		if #allowed == 0 then return {} end
	end
	local candidates = Compatibility.SelectVisibleUnits(
		targetRule.type,
		targetRule.priority,
		targetRule.maxDistance,
		guidKey(Unit.guid("target")),
		allowed,
		excludedGuids)
	if not candidates then return {} end
	local validCandidates = {}
	for i = 1, #candidates do
		local candidate = candidates[i]
		local unit
		if targetRule.type == "friendly_player" then
			unit = rosterByIndex[candidate.allowedIndex]
		else
			unit = nameplates[canonicalGuid(candidate.guid)]
		end
		candidate.dynamic = true
		candidate.category = targetRule.type
		if unit and guidEqual(Unit.guid(unit), candidate.guid) then
			candidate.unit = unit
			validCandidates[#validCandidates + 1] = candidate
		end
	end
	return validCandidates
end

function Targeting.IsComplete(targetRule)
	if type(targetRule) ~= "table" or type(targetRule.type) ~= "string" or not VALID_TYPES[targetRule.type] then
		return false
	end
	if targetRule.type == "fixed" then
		return type(targetRule.unit) == "string" and VALID_UNITS[targetRule.unit] == true
	end
	return VALID_PRIORITIES[targetRule.priority] and type(targetRule.maxDistance) == "number" and
		targetRule.maxDistance >= 1 and targetRule.maxDistance <= 100
end

function Targeting.Clear()
	for key in pairs(cache) do cache[key] = nil end
end

function Targeting.Candidates(targetRule, excludedGuids)
	if not Targeting.IsComplete(targetRule) then return {} end
	local exclusions = excludedSet(excludedGuids)
	local rosterEntries = targetRule.type == "friendly_player" and friendlyRoster() or nil
	local nameplates = {}
	local nameplateSignature = ""
	if targetRule.type ~= "fixed" and targetRule.type ~= "friendly_player" then
		nameplates, nameplateSignature = nameplateTokens()
	end
	local key = cacheKey(targetRule, excludedGuids, rosterEntries, nameplateSignature)
	local now = GetTime()
	local cached = cache[targetRule]
	if cached and cached.key == key and now - cached.time < Targeting.TARGET_REFRESH_INTERVAL then
		return cached.candidates
	end
	local candidates
	if targetRule.type == "fixed" then
		candidates = fixedCandidates(targetRule, exclusions)
	else
		candidates = dynamicCandidates(targetRule, excludedGuids or {}, rosterEntries or {}, nameplates)
	end
	cache[targetRule] = { key = key, time = now, candidates = candidates }
	return candidates
end

function Targeting.Resolve(targetRule, spellRule, applyTarget, excludedGuids, excludedSetValue)
	return Targeting.Candidates(targetRule, excludedGuids, excludedSetValue)
end

function Targeting.Apply(candidate)
	if not candidate or not candidate.dynamic then return true end
	return candidate.unit and guidEqual(Unit.guid(candidate.unit), candidate.guid)
end

ns.Targeting = Targeting
