-- Title-bar buttons for inline groups.
--
-- AceConfig renders inline groups as AceGUI "InlineGroup" widgets whose title
-- is a plain text fontstring, and its registry rejects custom option keys on
-- groups, so there is no native way to attach buttons to a section title.
-- This file wraps AceGUI:Create: any InlineGroup it returns gets its SetTitle
-- wrapped so that a matching entry in ns.UI.Widgets.TitleButtonGroups installs buttons at
-- the title's top-right.
--
-- Usage:
--   ns.UI.Widgets.TitleButtonGroups["Rules"] = {
--     { label = "+ Add rule", order = 1, func = fn },
--   }
--   ns.UI.Widgets.TitleButtonGroups[title] = {
--     { label = "▲", order = 1, func = fn, disabled = fn },
--     { label = "▼", order = 2, func = fn, disabled = fn },
--     { label = "Delete", order = 3, func = fn },
--   }
-- A label may be a function (e.g. "+" / "−" to reflect collapsed state); a
-- disabled field may be a function returning true to grey the button out.
-- Buttons are laid out right-to-left by order. Only groups with a matching
-- spec get buttons; a spec whose list is empty hides any installed ones.

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

-- widget state lives under the UI.Widgets namespace, not directly on ns
ns.UI = ns.UI or {}
ns.UI.Widgets = ns.UI.Widgets or {}
ns.UI.Widgets.TitleButtonGroups = ns.UI.Widgets.TitleButtonGroups or {}
local TitleButtonGroups = ns.UI.Widgets.TitleButtonGroups

local BUTTON_SIZE = 18
local GAP = 2   -- space between adjacent title buttons

-- makeButton creates (or reuses) the nth title button on a widget, anchoring
-- it to the right of the title. Returns the button.
local function makeButton(widget, n)
	if not widget._titleButtons then widget._titleButtons = {} end
	if widget._titleButtons[n] then return widget._titleButtons[n] end
	local button = AceGUI:Create("Button")
	button.frame:SetParent(widget.frame)
	button.frame:SetPoint("TOPRIGHT", widget.frame, "TOPRIGHT", -14, 0)
	button:SetHeight(BUTTON_SIZE)
	button.frame:SetFrameLevel((widget.frame:GetFrameLevel() or 0) + 2)
	button:SetAutoWidth(true)
	widget._titleButtons[n] = button
	return button
end

-- arrange positions the buttons right-to-left by order, accounting for each
-- button's current width.
local function arrange(widget, buttons)
	local offset = 14   -- same inset as the title text's right edge
	for i = #buttons, 1, -1 do
		local spec = buttons[i]
		local button = makeButton(widget, i)
		button.frame:ClearAllPoints()
		button.frame:SetPoint("TOPRIGHT", widget.frame, "TOPRIGHT", -offset, 0)
		offset = offset + (button.frame:GetWidth() or 0) + GAP
	end
end

-- StripDisplayTitle removes the NUL-suffixed index key from a title before
-- it reaches the fontstring (see Config.titleKey). Lua 5.1 cannot match the
-- NUL byte in patterns (find and %z both misbehave), so detect it by length
-- comparison, swap it for a control-char sentinel, and cut there. A title
-- without a NUL passes through untouched.
local function StripDisplayTitle(title)
	if title:gsub("%z", ""):len() ~= title:len() then
		return title:gsub("%z", "\1"):gsub("\1.*", "")
	end
	return title
end

ns.UI.Widgets.StripDisplayTitle = StripDisplayTitle

-- patch a freshly-created InlineGroup so its SetTitle installs the buttons.
local function patchInlineGroup(widget)
	if widget._titleButtonHooked then return widget end
	local stockSetTitle = widget.SetTitle
	function widget:SetTitle(title)
		stockSetTitle(self, StripDisplayTitle(title))
		local specs = TitleButtonGroups[title]
		if specs and #specs > 0 then
			for i = 1, #specs do
				local button = makeButton(self, i)
				local label = specs[i].label
				if type(label) == "function" then label = label() end
				button:SetText(label)
				button:SetCallback("OnClick", specs[i].func)
				local disabled = specs[i].disabled
				button:SetDisabled(disabled and disabled() or false)
				button.frame:Show()
			end
			arrange(self, specs)
		elseif self._titleButtons then
			for _, button in pairs(self._titleButtons) do
				button.frame:Hide()
			end
		end
	end
	widget._titleButtonHooked = true
	return widget
end

-- wrap AceGUI:Create to hook InlineGroup widgets
local stockCreate = AceGUI.Create
function AceGUI:Create(type, ...)
	local widget = stockCreate(self, type, ...)
	if type == "InlineGroup" then
		patchInlineGroup(widget)
	end
	return widget
end
