-- The live spellbook name resolver.
--
-- The client has no spell-to-ID lookup table, so spells are stored by exact
-- name. This file walks the spellbook and caches the known names. The engine
-- checks a name against the cache; the editor shows the cache as a picker.

local _, ns = ...

local SpellPicker = {}

local names = nil   -- set of known names (name -> true)
local order = nil   -- sorted list of known names

-- walk reads every spell the character knows. It returns a name set and a
-- sorted name list. It is the only place that reads the spellbook API.
local function walk()
	local set, list, seen = {}, {}, {}
	for tab = 1, GetNumSpellTabs() do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		if offset and numSpells then
			for i = offset + 1, offset + numSpells do
				-- IsPassiveSpell is the reliable passive detector in this
				-- client (GetSpellBookItemInfo's type string reports "spell"
				-- for everything). Skip passives so the picker only offers
				-- spells the rotation could actually cast.
				if not IsPassiveSpell(i, BOOKTYPE_SPELL) then
					local name = GetSpellName(i, BOOKTYPE_SPELL)
					if name and name ~= "" and not seen[name] then
						seen[name] = true
						set[name] = true
						list[#list + 1] = name
					end
				end
			end
		end
	end
	table.sort(list)
	return set, list
end

-- Refresh re-reads the spellbook. Core calls it when the spellbook changes
-- (a learned spell or a changed build on Ascension).
function SpellPicker.Refresh()
	names, order = walk()
	return names, order
end

-- List returns the sorted name list. It reads the book on the first call.
function SpellPicker.List()
	if not names then SpellPicker.Refresh() end
	return order
end

-- IsKnown returns true when the cache contains the exact name.
function SpellPicker.IsKnown(name)
	if not names then SpellPicker.Refresh() end
	return names[name] == true
end

-- Ref returns the name-or-ID a rule casts with. A numeric ID wins over the
-- name when both are set.
function SpellPicker.Ref(spellID, name)
	if spellID and spellID > 0 then return spellID end
	return name
end

-- Icon returns the icon path for a rule, or nil when neither a valid ID nor a
-- name is set. The editor and the button both use it so icons are consistent.
function SpellPicker.Icon(rule)
	if rule.spellID and rule.spellID > 0 then
		local _, _, icon = GetSpellInfo(rule.spellID)
		return icon
	end
	if rule.spell and rule.spell ~= "" then
		return GetSpellTexture(rule.spell)
	end
	return nil
end

-- SpellID resolves a rule to a numeric spell ID, or nil when the rule has no
-- usable spell. A stored ID wins; a name is resolved through GetSpellInfo,
-- whose 7th return is the ID in this client. Used for tooltips.
function SpellPicker.SpellID(rule)
	if rule.spellID and rule.spellID > 0 then return rule.spellID end
	if rule.spell and rule.spell ~= "" then
		return select(7, GetSpellInfo(rule.spell))
	end
	return nil
end

ns.SpellPicker = SpellPicker
