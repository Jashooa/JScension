-- Spell-state helpers. The single owner of the client's spell APIs and
-- their return orders. No other module calls GetSpellInfo, GetSpellCooldown,
-- IsUsableSpell, IsSpellInRange, GetSpellLink, or GetSpellCharges directly:
-- they read through these wrappers, so a return-order fact lives in exactly
-- one place.
--
-- Return orders (verified against the client's own APIDocumentation):
--   GetSpellInfo(ref):     name, rank, icon, powerCost, isFunnel, powerType,
--                          castingTime, minRange, maxRange (no spell ID)
--   GetSpellCooldown(ref): start, duration, enable
--   IsUsableSpell(ref):    isUsable, notEnoughMana
--   IsSpellInRange:        1 in range, 0 out of range, nil unknown
--   GetSpellCharges(id):   currentCharges, maxCharges, unknown, rechargeTime

local _, ns = ...

local Spell = {}

local function spellID(ref)
	if type(ref) == "number" then return ref end
	local link = GetSpellLink(ref)
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("spell:(%d+)"))
end

-- stripRank removes a trailing "(Rank N)" / "(Ranks N-M)" suffix. The client
-- reports ranked auras and cast-bar names with the suffix; stored spell names
-- are plain, so both sides are normalized before comparison.
function Spell.stripRank(s)
	s = s:gsub("%s%((Rank)%s?%d+%-?%d*%)$", "")
	s = s:gsub("%s%((Ranks)%s?%d+%-?%d+%)$", "")
	return s
end


-- name returns a spell's name.
function Spell.name(ref)
	return select(1, GetSpellInfo(ref))
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

-- hasCharges returns true when a spell uses a charge-based cooldown.
function Spell.hasCharges(ref)
	return Spell.maxCharges(ref) > 0
end

-- maxCharges returns the maximum charges for a spell, or 0 for spells without
-- charges or references that cannot be resolved to a spell ID.
function Spell.maxCharges(ref)
	local id = spellID(ref)
	if not id then return 0 end
	local _, maxCharges = GetSpellCharges(id)
	return maxCharges or 0
end

-- currentCharges returns the available charges, or 0 for spells without
-- charges or references that cannot be resolved to a spell ID.
function Spell.currentCharges(ref)
	local id = spellID(ref)
	if not id then return 0 end
	local currentCharges, maxCharges = GetSpellCharges(id)
	if not maxCharges or maxCharges == 0 then return 0 end
	return currentCharges or 0
end

-- inRange returns true when the spell is in range of the unit, false when
-- out of range, and nil when the client cannot resolve the unit distance.
-- Some spells return nil from IsSpellInRange on this client, so their
-- configured minimum and maximum ranges provide the fallback.
function Spell.inRange(ref, unit)
	local result = IsSpellInRange(ref, unit)
	if result ~= nil then return result == 1 end
	local distance = ns.Unit.distance("player", unit)
	if not distance then return nil end
	return distance >= Spell.minRange(ref) and distance <= Spell.maxRange(ref)
end

-- maxRange returns the maximum range of a spell in yards, or 0 for melee/self spells.
function Spell.maxRange(ref)
	return select(9, GetSpellInfo(ref)) or 0
end

-- minRange returns the minimum range of a spell in yards, or 0 for melee/self spells.
function Spell.minRange(ref)
	return select(8, GetSpellInfo(ref)) or 0
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
