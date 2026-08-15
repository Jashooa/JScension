-- The rotation panel widget.
--
-- A custom AceGUI container ("RotationPanel") that renders one rotation's
-- rules as cards. The layout mirrors the old declarative AceConfig editor:
-- every section uses the Flow layout with the same widths (half/full) as the
-- options it replaces, so the panel looks identical to the previous UI.
--
-- Each rule card carries the spell icon and ▲/▼/Delete buttons in its title,
-- the main options in its body, and a Conditions section with per-condition
-- cards. Every button closure binds to its own rule or condition directly;
-- there is no title-key registry and no hidden bytes in titles.
--
-- AceConfig renders the panel through a leaf option with
-- `type = "execute", control = "RotationPanel"`. InjectInfo stores the option
-- path in the widget's userdata before AddChild shows the widget, so the
-- panel resolves its rotation from that path and renders on first OnShow.

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

local Profile = ns.Profile
local Conditions = ns.Conditions
local SpellPicker = ns.SpellPicker

local Type, Version = "RotationPanel", 1
if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

-- ---------------------------------------------------------------------------
-- shared render helpers
-- ---------------------------------------------------------------------------

-- RuleIcon returns the texture path for a rule, with a fallback icon.
local function ruleIcon(rule)
	return SpellPicker.Icon(rule) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- RuleTitle renders the icon + label as the card title.
local function ruleTitle(rule, index)
	local label = ""
	if rule.name and rule.name ~= "" then
		label = rule.name
	elseif rule.spell and rule.spell ~= "" then
		label = rule.spell
	else
		label = "Rule " .. index
	end
	return ("|T%s:32:32|t %s"):format(ruleIcon(rule), label)
end

-- setSpellTooltip wires GameTooltip to a fontstring so hovering it shows the
-- spell's tooltip. GetSpellLink returns a usable hyperlink for the name;
-- this client's GetSpellInfo exposes no spell ID, so no ID is resolved.
-- Fontstrings are not mouse-enabled by default, so OnEnter never fires
-- without EnableMouse.
local function setSpellTooltip(fontString, rule)
	if not fontString.SetScript then return end
	fontString:EnableMouse(true)
	fontString:SetScript("OnEnter", function(self)
		local link = SpellPicker.Link(rule)
		if not link then return end
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink(link)
		GameTooltip:Show()
	end)
	fontString:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

-- SpellValues returns the { name = name } map for the spell dropdown. The
-- rule's current spell is added so a stale value still renders.
local function spellValues(rule)
	local list = SpellPicker.List()
	local values = {}
	for i = 1, #list do
		values[list[i]] = list[i]
	end
	if rule.spell and rule.spell ~= "" then
		values[rule.spell] = rule.spell
	end
	return values
end

-- ---------------------------------------------------------------------------
-- condition card
-- ---------------------------------------------------------------------------

-- conditionExpanded tracks whether a condition's settings are shown. Keyed
-- by the condition table so it survives panel rebuilds.
local conditionExpanded = {}


-- conditionTypeValues returns the { key = label } map for the type dropdown.
local function conditionTypeValues()
	local list = Conditions.TypeList()
	local values = {}
	for i = 1, #list do
		values[list[i].key] = list[i].label
	end
	return values
end





-- dropdownField builds a dropdown bound to one condition field.
local function dropdownField(condition, field, name, values, initial)
	local dropdown = AceGUI:Create("Dropdown")
	dropdown:SetLabel(name)
	dropdown:SetList(values)
	dropdown:SetValue(initial)
	dropdown:SetCallback("OnValueChanged", function(_, _, value)
		condition[field] = value
	end)
	return dropdown
end

-- conditionField renders one registry-declared field as the right AceGUI
-- widget for its type.
local function conditionField(condition, field, fieldType)
	local name = field:gsub("_", " ")
	if fieldType == "number" then
		local slider = AceGUI:Create("Slider")
		slider:SetLabel(name)
		slider:SetSliderValues(0, 100, 1)
		slider:SetValue(condition[field] or 0)
		slider:SetCallback("OnValueChanged", function(_, _, value)
			condition[field] = value
		end)
		return slider
	elseif fieldType == "op" then
		return dropdownField(condition, field, name, Conditions.Ops, condition[field] or "<")
	elseif fieldType == "unit" then
		return dropdownField(condition, field, name, Conditions.Units, condition[field] or "target")
	elseif fieldType == "kind" then
		return dropdownField(condition, field, name, Conditions.Kinds, condition[field] or "buff")
	elseif fieldType == "target_type" then
		return dropdownField(condition, field, name, Conditions.TargetTypes, condition[field] or "enemy")
	elseif fieldType == "bool" then
		local check = AceGUI:Create("CheckBox")
		check:SetLabel(name)
		check:SetValue(condition[field] == true)
		check:SetCallback("OnValueChanged", function(_, _, value)
			condition[field] = value and true or false
		end)
		return check
	elseif fieldType == "code" then
		local edit = AceGUI:Create("MultiLineEditBox")
		edit:SetLabel(name)
		edit:SetFullWidth(true)
		edit:SetText(condition[field] or "")
		edit:SetCallback("OnTextChanged", function(_, _, value)
			condition[field] = value
		end)
		return edit
	else
		-- "spell", "string", and anything unknown render as a single-line box
		local edit = AceGUI:Create("EditBox")
		edit:SetLabel(name)
		edit:SetText(condition[field] or "")
		edit:SetCallback("OnTextChanged", function(_, _, value)
			condition[field] = value
		end)
		return edit
	end
end

-- buildConditionSettings fills the settings group with the type dropdown,
-- one control per registry-declared field, and a delete button. Widths match
-- the old editor: the type and delete are full width, fields keep their
-- buildConditionSettings fills the expanded card with the type dropdown and
-- one control per registry-declared field. Widths match the old editor: the
-- type is full width, fields keep their default single width.
local function buildConditionSettings(panel, rule, condIndex, container)
	local condition = rule.conditions[condIndex]
	local def = Conditions.Registry[condition.type]

	local typeDropdown = AceGUI:Create("Dropdown")
	typeDropdown:SetLabel("Condition")
	typeDropdown:SetFullWidth(true)
	typeDropdown:SetList(conditionTypeValues())
	typeDropdown:SetValue(condition.type)
	typeDropdown:SetCallback("OnValueChanged", function(_, _, value)
		condition.type = value
		panel:NotifyPanelChanged()
	end)
	container:AddChild(typeDropdown)

	if def then
		for field, fieldType in pairs(def.fields) do
			container:AddChild(conditionField(condition, field, fieldType))
		end
	end
end

-- conditionCard builds one condition card: the summary is the title, with
-- +/− (expand/collapse settings) and Delete as title buttons, and the
-- settings controls below, shown only when expanded.
local function conditionCard(panel, rule, condIndex, container)
	local condition = rule.conditions[condIndex]

	local card = AceGUI:Create("TitleButtonGroup")
	card:SetTitle(Conditions.Describe(condition))
	card:SetFullWidth(true)
	card:SetLayout("Flow")
	card:SetTitleButtons({
		{ label = conditionExpanded[condition] and "−" or "+", func = function()
			conditionExpanded[condition] = not conditionExpanded[condition]
			panel:NotifyPanelChanged()
		end },
		{ label = "Delete", func = function()
			Profile.deleteCondition(rule, condIndex)
			conditionExpanded[condition] = nil
			panel:NotifyPanelChanged()
		end },
	})
	container:AddChild(card)

	-- settings controls: type dropdown, per-type fields. Only built when
	-- expanded; a collapsed card shows just the summary and title buttons
	-- (border hidden so no empty box renders below the title row).
	if conditionExpanded[condition] then
		card:SetBorderVisible(true)
		buildConditionSettings(panel, rule, condIndex, card)
	else
		card:SetBorderVisible(false)
	end
	return card
end





-- ---------------------------------------------------------------------------
-- rule card
-- ---------------------------------------------------------------------------

-- ruleCard builds one rule card: title bar with ▲/▼/Delete buttons, main
-- options, and a Conditions section. Control widths match the old editor:
-- Enabled half, Label full, Spell full, Spell ID half, Target unit half,
-- Conditions full.
local function ruleCard(panel, rotation, ruleIndex, container)
	local rule = rotation.rules[ruleIndex]
	local rules = rotation.rules

	local card = AceGUI:Create("TitleButtonGroup")
	card:SetTitle(ruleTitle(rule, ruleIndex))
	card:SetFullWidth(true)
	card:SetLayout("Flow")
	card:SetTitleButtons({
		{ label = "▲", disabled = ruleIndex <= 1, func = function()
			Profile.moveRule(rotation, ruleIndex, ruleIndex - 1)
			panel:NotifyPanelChanged()
		end },
		{ label = "▼", disabled = ruleIndex >= #rules, func = function()
			Profile.moveRule(rotation, ruleIndex, ruleIndex + 1)
			panel:NotifyPanelChanged()
		end },
		{ label = "Delete", disabled = false, func = function()
			Profile.deleteRule(rotation, ruleIndex)
			panel:NotifyPanelChanged()
		end },
	})
	-- hovering the card title shows the spell tooltip (icon included). The
	-- titlebar frame is the hover surface (fontstrings are Regions and cannot
	-- reliably receive mouse events).
	setSpellTooltip(card.titlebar, rule)
	container:AddChild(card)

	-- main options
	local enabled = AceGUI:Create("CheckBox")
	enabled:SetLabel("Enabled")
	enabled:SetRelativeWidth(0.5)
	enabled:SetValue(rule.enabled)
	enabled:SetCallback("OnValueChanged", function(_, _, value)
		rule.enabled = value
	end)
	card:AddChild(enabled)

	local labelInput = AceGUI:Create("EditBox")
	labelInput:SetLabel("Label")
	labelInput:SetFullWidth(true)
	labelInput:SetText(rule.name or "")
	labelInput:SetCallback("OnTextChanged", function(_, _, value)
		rule.name = value
	end)
	card:AddChild(labelInput)

	local spellDropdown = AceGUI:Create("Dropdown")
	spellDropdown:SetLabel("Spell")
	spellDropdown:SetFullWidth(true)
	spellDropdown:SetList(spellValues(rule))
	spellDropdown:SetValue(rule.spell or "")
	spellDropdown:SetCallback("OnValueChanged", function(_, _, value)
		rule.spell = value
		panel:NotifyPanelChanged()
	end)
	card:AddChild(spellDropdown)

	local spellIdInput = AceGUI:Create("EditBox")
	spellIdInput:SetLabel("Spell ID (optional)")
	spellIdInput:SetRelativeWidth(0.5)
	spellIdInput:SetText(rule.spellID and tostring(rule.spellID) or "")
	spellIdInput:SetCallback("OnTextChanged", function(_, _, value)
		rule.spellID = tonumber(value)
	end)
	card:AddChild(spellIdInput)

	local unitDropdown = AceGUI:Create("Dropdown")
	unitDropdown:SetLabel("Target unit")
	unitDropdown:SetRelativeWidth(0.5)
	unitDropdown:SetList(Conditions.Units)
	unitDropdown:SetValue(rule.unit or "target")
	unitDropdown:SetCallback("OnValueChanged", function(_, _, value)
		rule.unit = value
	end)
	card:AddChild(unitDropdown)

	-- conditions section: title bar carries the "Add condition" button
	local conditionsGroup = AceGUI:Create("TitleButtonGroup")
	conditionsGroup:SetTitle("Conditions")
	conditionsGroup:SetFullWidth(true)
	conditionsGroup:SetLayout("Flow")
	conditionsGroup:SetTitleButtons({
		{ label = "Add condition", func = function()
			Profile.addCondition(rule)
			panel:NotifyPanelChanged()
		end },
	})
	card:AddChild(conditionsGroup)

	for i = 1, #rule.conditions do
		conditionCard(panel, rule, i, conditionsGroup)
	end

	return card
end


-- ---------------------------------------------------------------------------
-- the panel widget
-- ---------------------------------------------------------------------------

local methods = {
	-- OnAcquire resets to a hidden, empty state. The actual render happens on
	-- the first OnShow, after AceConfig has stored the option path in the
	-- widget's userdata.
	["OnAcquire"] = function(self)
		self:SetWidth(600)
		self:SetHeight(200)
		self.titletext:SetText("")
		self.rendered = false
		self.rebuildPending = nil
		self.frame:SetScript("OnUpdate", nil)
	end,

	-- SetText is called by AceConfig's execute-control setup; the panel has
	-- no button text, so it is a no-op.
	["SetText"] = function() end,

	["OnWidthSet"] = function(self, width)
		local content = self.content
		local contentWidth = width - 20
		if contentWidth < 0 then contentWidth = 0 end
		content:SetWidth(contentWidth)
		content.width = contentWidth
	end,

	["OnHeightSet"] = function(self, height)
		local content = self.content
		local contentHeight = height - 20
		if contentHeight < 0 then contentHeight = 0 end
		content:SetHeight(contentHeight)
		content.height = contentHeight
	end,

	["LayoutFinished"] = function(self, width, height)
		self:SetHeight((height or 0) + 40)
	end,

	-- NotifyPanelChanged is called by every mutation closure. It must NOT
	-- rebuild synchronously: the closure runs inside a widget callback, and
	-- releasing children there would pool the very button being clicked.
	-- The rebuild is deferred one frame via a one-shot OnUpdate, so the
	-- click finishes before anything is released. The panel and its parent
	-- ScrollFrame survive (unlike a full dialog refresh), so the scroll
	-- position is preserved instead of jumping.
	["NotifyPanelChanged"] = function(self)
		if self.rebuildPending then return end
		self.rebuildPending = true
		self.frame:SetScript("OnUpdate", function()
			self.frame:SetScript("OnUpdate", nil)
			self.rebuildPending = nil
			self:RenderPanel()
		end)
	end,

	["RenderPanel"] = function(self)
		local rotation = self:PanelRotation()
		if not rotation then return end
		self:ReleaseChildren()

		-- Rules section: its title bar carries the "Add rule" button
		local rulesSection = AceGUI:Create("TitleButtonGroup")
		rulesSection:SetTitle("Rules")
		rulesSection:SetFullWidth(true)
		rulesSection:SetLayout("Flow")
		rulesSection:SetTitleButtons({
			{ label = "Add rule", func = function()
				Profile.addRule(rotation)
				self:NotifyPanelChanged()
			end },
		})
		self:AddChild(rulesSection)

		if #rotation.rules == 0 then
			local emptyLabel = AceGUI:Create("Label")
			emptyLabel:SetText("No rules. Add one above.")
			rulesSection:AddChild(emptyLabel)
		else
			for i = 1, #rotation.rules do
				ruleCard(self, rotation, i, rulesSection)
			end
		end
		self:DoLayout()
		-- the panel's height changed; re-run the parent's layout (the
		-- ScrollFrame that hosts this panel) so its content height and
		-- scrollbar range track the new content length
		local parent = self.parent
		if parent and parent.DoLayout then
			parent:DoLayout()
		end
	end,

	-- PanelRotation resolves this panel's rotation from the option path
	-- AceConfig stored in the widget userdata: the path is the arg-key chain
	-- from the root (e.g. {"rotations", "rotation1", "rotationPanel"}), and
	-- the "rotationN" element indexes into the live rotation list.
	["PanelRotation"] = function(self)
		local user = self:GetUserDataTable()
		local path = user.path
		if type(path) ~= "table" then return nil end
		for i = 1, #path do
			local key = path[i]
			if type(key) == "string" then
				local index = key:match("^rotation(%d+)$")
				if index then
					local list = Profile.rotations()
					return list[tonumber(index)]
				end
			end
		end
		return nil
	end,
}

-- ---------------------------------------------------------------------------
-- constructor
-- ---------------------------------------------------------------------------

-- The panel is a bare container: it holds the Rules section, which provides
-- the visible bordered box. No backdrop, border, or title of its own.
local function Constructor()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 0, 0)
	content:SetPoint("BOTTOMRIGHT", 0, 0)

	local widget = {
		frame = frame,
		content = content,
		titletext = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal"),
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end

	widget = AceGUI:RegisterAsContainer(widget)

	-- render once the widget is shown (after InjectInfo stored the option)
	frame:SetScript("OnShow", function()
		if not widget.rendered then
			widget.rendered = true
			widget:RenderPanel()
		end
	end)

	return widget
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
