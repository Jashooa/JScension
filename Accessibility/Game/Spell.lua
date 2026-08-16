-- Spell-state helpers. The single owner of the client's spell APIs and
-- their return orders. No other module calls GetSpellInfo, GetSpellCooldown,
-- IsUsableSpell, or IsSpellInRange directly: they read through these
-- wrappers, so a return-order fact lives in exactly one place.
--
-- Return orders (verified against the client's own APIDocumentation):
--   GetSpellInfo(ref):     name, rank, icon, powerCost, isFunnel, powerType,
--                          castingTime, minRange, maxRange (no spell ID)
--   GetSpellCooldown(ref): start, duration, enable
--   IsUsableSpell(ref):    isUsable, notEnoughMana
--   IsSpellInRange:        1 in range, 0 out of range, nil unknown

local _, ns = ...

local Spell = {}

-- stripRank removes a trailing "(Rank N)" / "(Ranks N-M)" suffix. The client
-- reports ranked auras and cast-bar names with the suffix; stored spell names
-- are plain, so both sides are normalized before comparison.
function Spell.stripRank(s)
	s = s:gsub("%s%((Rank)%s?%d+%-?%d*%)$", "")
	s = s:gsub("%s%((Ranks)%s?%d+%-?%d+%)$", "")
	return s
end

-- castTime returns a spell's cast time in ms, or 0 when instant.
function Spell.castTime(ref)
	return select(7, GetSpellInfo(ref)) or 0
end

-- name returns a spell's name.
function Spell.name(ref)
	return select(1, GetSpellInfo(ref))
end

-- id resolves a spell name to its numeric ID via the backported C_Spell API,
-- or returns nil when the name does not resolve or the API is absent. It is
-- used to auto-fill the editor's spell-ID field; the engine still casts by
-- name, so a nil result is not an error.
function Spell.id(name)
	if not name or name == "" then return nil end
	if type(C_Spell) ~= "table" or type(C_Spell.GetSpellID) ~= "function" then
		return nil
	end
	local ok, result = pcall(C_Spell.GetSpellID, C_Spell, name)
	if ok and type(result) == "number" and result > 0 then return result end
	return nil
end

-- cooldown returns (start, duration) for a spell.
function Spell.cooldown(ref)
	local start, duration = GetSpellCooldown(ref)
	return start, duration
end

-- usable returns (isUsable, notEnoughMana).
function Spell.usable(ref)
	return IsUsableSpell(ref)
end

-- inRange returns true when the spell is in range of the unit.
function Spell.inRange(ref, unit)
	return IsSpellInRange(ref, unit) == 1
end

-- verifyShape probes a known spell and returns false when the documented
-- GetSpellInfo return order does not hold (a client rebuild shifted it). A
-- nil probe (no known spell yet) returns true: nothing to check.
function Spell.verifyShape()
	local probe = ns.SpellPicker and ns.SpellPicker.List()[1] or nil
	if not probe then return true end
	local name, _, _, _, _, _, castingTime = GetSpellInfo(probe)
	return type(name) == "string" and type(castingTime) == "number"
end

ns.Spell = Spell
