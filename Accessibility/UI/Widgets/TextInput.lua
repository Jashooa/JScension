-- TextInput: the shared single-line text field used by the editor widgets.
--
-- Builds an AceGUI EditBox that commits on Enter and clears focus, matching
-- AceConfig's `input` widget (which wires OnEnterPressed). Every single-line
-- text field in the editor goes through this so the commit semantics cannot
-- drift per field.

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0", true)

local TextInput = {}

-- Build returns an EditBox bound to a commit callback, or nil when AceGUI is
-- unavailable (the widget-loading guard makes the editor bail out anyway).
function TextInput.Build(label, initial, commit)
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

ns.TextInput = TextInput
