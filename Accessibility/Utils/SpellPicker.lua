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

-- Icon returns the icon path for a rule, or nil when it has no spell name.
-- The editor and the button both use it so icons are consistent.
function SpellPicker.Icon(rule)
	if rule.spell and rule.spell ~= "" then
		return GetSpellTexture(rule.spell)
	end
	return nil
end

-- Link returns the spell hyperlink for a rule, or nil when it has no spell
-- name. This client's GetSpellInfo exposes no spell ID, so links come from
-- GetSpellLink. Used for tooltips.
function SpellPicker.Link(rule)
	if rule.spell and rule.spell ~= "" then
		return select(1, GetSpellLink(rule.spell))
	end
	return nil
end

ns.SpellPicker = SpellPicker
