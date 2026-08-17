-- Fields: the shared AceGUI field builders used by the editor widgets.
--
-- Every form field the editor renders goes through one of these, so the
-- commit semantics are owned once and cannot drift per field. Single-line
-- text commits on Enter and clears focus (matching AceConfig's `input`);
-- the multiline code field commits on focus-lost (Enter is a newline there);
-- dropdowns, sliders, and checkboxes commit on OnValueChanged.

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0", true)

local Fields = {}

-- Text builds a single-line EditBox. commit runs on Enter, then focus clears.
function Fields.Text(label, initial, commit)
	if not AceGUI then return nil end
	local edit = AceGUI:Create("EditBox")
	edit:SetLabel(label)
	edit:SetText(initial or "")
	edit:SetCallback("OnEnterPressed", function(_, _, value)
		commit(value)
		edit.editbox:ClearFocus()
	end)
	return edit
end

-- Multiline builds a multi-line EditBox. commit runs when the box loses focus.
function Fields.Multiline(label, initial, commit)
	if not AceGUI then return nil end
	local edit = AceGUI:Create("MultiLineEditBox")
	edit:SetLabel(label)
	edit:SetFullWidth(true)
	edit:SetText(initial or "")
	edit:SetCallback("OnEditFocusLost", function()
		commit(edit.editBox:GetText())
	end)
	return edit
end

-- Dropdown builds a dropdown. entries is either an ordered array of strings
-- (identity values where key == label) or a map (e.g. Powers with number
-- keys). For arrays the dropdown builder derives the AceGUI map and uses
-- the array as the display order. commit runs on selection.
function Fields.Dropdown(label, entries, initial, commit)
	if not AceGUI then return nil end
	local list, order
	if entries[1] ~= nil then
		-- ordered array: derive identity map, use array as order
		list = {}
		for i = 1, #entries do list[entries[i]] = entries[i] end
		order = entries
	else
		-- map (e.g. Powers with number keys): use as-is, AceGUI sorts
		list = entries
	end
	local dropdown = AceGUI:Create("Dropdown")
	dropdown:SetLabel(label)
	dropdown:SetList(list, order)
	dropdown:SetValue(initial)
	dropdown:SetCallback("OnValueChanged", function(_, _, value)
		commit(value)
	end)
	return dropdown
end

-- Slider builds a numeric slider. commit runs on change.
function Fields.Slider(label, min, max, step, initial, commit)
	if not AceGUI then return nil end
	local slider = AceGUI:Create("Slider")
	slider:SetLabel(label)
	slider:SetSliderValues(min, max, step)
	-- AceGUI's slider SetValue requires a number; a stale string (e.g. a
	-- leftover "value" from a different condition type) must not crash the
	-- panel render, so coerce and clamp to the slider range.
	local n = tonumber(initial) or 0
	if n < min then n = min end
	if n > max then n = max end
	slider:SetValue(n)
	slider:SetCallback("OnValueChanged", function(_, _, value)
		commit(value)
	end)
	return slider
end

-- CheckBox builds a checkbox. commit runs on toggle.
function Fields.CheckBox(label, initial, commit)
	if not AceGUI then return nil end
	local check = AceGUI:Create("CheckBox")
	check:SetLabel(label)
	check:SetValue(initial == true)
	check:SetCallback("OnValueChanged", function(_, _, value)
		commit(value and true or false)
	end)
	return check
end

ns.Fields = Fields
