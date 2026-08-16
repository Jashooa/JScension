-- Aura helpers: scanning unit buffs/debuffs by name.
--
-- Names are normalized before comparison: 3.3.5a UnitBuff/UnitDebuff report
-- auras with their rank suffix ("Moonfire (Rank 2)") while the editor stores
-- the plain spell name, so a trailing "(Rank N)" / "(Ranks N-M)" is stripped
-- from both sides. Without this an exact match fails and "Aura missing" is
-- true even when the aura is up.
--
-- The caster return of UnitBuff/UnitDebuff is NOT reliably "player": for auras
-- the player applied it can come back as the player's character name (a known
-- 3.3.5a behavior), so the self check accepts both. A nil or unknown caster is
-- treated as "not mine", so a mineOnly search fails closed instead of treating
-- a stranger's dot as our own.

local _, ns = ...

local Constants = ns.Constants
local Spell = ns.Spell

local Aura = {}

-- stripRank removes a trailing "(Rank N)" or "(Ranks N-M)" suffix.
local function stripRank(s)
	s = s:gsub("%s%((Rank)%s?%d+%-?%d*%)$", "")
	s = s:gsub("%s%((Ranks)%s?%d+%-?%d+%)$", "")
	return s
end

-- find walks an aura list for a name. It returns remaining seconds and stacks.
-- mineOnly restricts the search to auras the player applied, which is the
-- usual need for a dot or a self buff.
function Aura.find(unit, name, kind, mineOnly)
	if not unit or not UnitExists(unit) or not name or name == "" then return nil end
	-- the editor stores an aura name, but accept a numeric spell ID too:
	local id = tonumber(name)
	if id then
		local resolved = Spell.name(id)
		if resolved then name = resolved end
	end
	if type(name) ~= "string" then return nil end
	local scan = (kind == "debuff") and UnitDebuff or UnitBuff
	-- strip the rank before lowercasing: the strip pattern is case-sensitive
	local needle = stripRank(name):lower()
	local selfName = mineOnly and UnitName("player") or nil

	for i = 1, Constants.MAX_AURAS do
		-- UnitBuff/UnitDebuff return (name, rank, icon, count, dispelType,
		-- duration, expires, caster, ...) in this client.
		local aname, _, _, count, _, duration, expires, caster = scan(unit, i)
		if not aname then break end
		if stripRank(aname):lower() == needle then
			local mine = not mineOnly
				or caster == "player" or caster == "pet"
				or (selfName and caster == selfName)
			if not mine then
				-- keep looking: someone else's copy of the same aura
			else
				local remaining = 0
				if expires and expires > 0 then
					remaining = expires - GetTime()
					if remaining < 0 then remaining = 0 end
				end
				return remaining, (count and count > 0) and count or 1
			end
		end
	end
	return nil
end

ns.Aura = Aura
