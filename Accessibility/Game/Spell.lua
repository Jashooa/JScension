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

-- castTime returns a spell's cast time in ms, or 0 when instant.
function Spell.castTime(ref)
	return select(7, GetSpellInfo(ref)) or 0
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

-- inRange returns true when the spell is in range of the unit.
function Spell.inRange(ref, unit)
	return IsSpellInRange(ref, unit) == 1
end

ns.Spell = Spell
