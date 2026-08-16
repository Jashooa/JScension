-- Cooldown helpers: the single owner of the GCD-versus-own-cooldown
-- heuristic and the spell-ready check.
--
-- GetSpellCooldown returns (start, duration) where a duration at or below
-- GCD_DURATION is the global cooldown, not the spell's own cooldown. The
-- engine, the conditions, and the button all need that distinction, so it
-- lives here once instead of as four near-copies.

local _, ns = ...

local Constants = ns.Constants
local Spell = ns.Spell

local Cooldown = {}

-- isGCD reports whether a cooldown reading is the global cooldown (a short
-- duration shared by every spell), not the spell's own cooldown.
function Cooldown.isGCD(start, duration)
	return start and start > 0 and duration and duration <= Constants.GCD_DURATION
end

-- isOwnCooldown reports whether a cooldown reading is the spell's own
-- cooldown (longer than the global cooldown).
function Cooldown.isOwnCooldown(start, duration)
	return start and start > 0 and duration and duration > Constants.GCD_DURATION
end

-- isReady reports whether a spell is usable and off its own cooldown. The
-- global cooldown counts as ready: the GCD gate spaces on-GCD spells, so the
-- ready border must not flicker for a spell that is only on the GCD.
function Cooldown.isReady(ref)
	local usable, noMana = Spell.usable(ref)
	if not usable or noMana then return false end
	local start, duration = Spell.cooldown(ref)
	if not start or start == 0 then return true end
	if Cooldown.isGCD(start, duration) then return true end
	return (start + duration) <= GetTime()
end

ns.Cooldown = Cooldown
