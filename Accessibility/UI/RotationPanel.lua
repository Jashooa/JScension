-- The rotation panel widget.
--
-- A custom AceGUI container ("RotationPanel") that renders one rotation's
-- rules as a card list: each rule card carries the spell icon and ▲/▼/Delete
-- buttons in its title, the main options in its body, and a Conditions
-- section with per-condition cards. The panel replaces the declarative
-- AceConfig rule/condition groups: it builds real AceGUI widgets directly,
-- so every button closure binds to its own rule or condition with no
-- title-key registry and no hidden bytes in titles.
--
-- AceConfig renders the panel through a leaf option with
-- `type = "execute", control = "RotationPanel"`; the option table carries a
-- `rotation` reference (a custom field AceConfig ignores). AceConfig calls
-- InjectInfo (which stores the option table in the widget's userdata) before
-- AddChild shows the widget, so the panel renders on its first OnShow.

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

-- Icon returns the texture path for a rule, with a fallback icon.
local function icon(rule)
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
	return ("|T%s:16:16|t %s"):format(icon(rule), label)
end

-- ---------------------------------------------------------------------------
-- condition card
-- ---------------------------------------------------------------------------

-- conditionExpanded tracks whether a condition's settings are shown. Keyed
-- by the condition table so it survives panel rebuilds.
local conditionExpanded = {}

-- conditionCard builds one condition card: a summary title, an in-body +/−
-- toggle, and a nested settings group shown only when expanded.
local function conditionCard(panel, rule, condIndex, container)
	local condition = rule.conditions[condIndex]
	local def = Conditions.Registry[condition.type]

	local card = AceGUI:Create("InlineGroup")
	card:SetTitle(Conditions.Describe(condition))
	card:SetFullWidth(true)
	container:AddChild(card)

	-- in-body toggle that expands/collapses the settings
	local toggle = AceGUI:Create("Button")
	toggle:SetText(conditionExpanded[condition] and "−" or "+")
	toggle:SetCallback("OnClick", function()
		conditionExpanded[condition] = not conditionExpanded[condition]
		panel:NotifyPanelChanged()
	end)
	card:AddChild(toggle)

	-- settings group: type dropdown, per-type fields, delete. Only built when
	-- expanded; a collapsed card shows just the summary and the +/− toggle.
	if conditionExpanded[condition] then
		local settings = AceGUI:Create("InlineGroup")
		settings:SetTitle("")
		card:AddChild(settings)
		buildConditionSettings(panel, rule, condIndex, settings)
	end
	return card
end

-- buildConditionSettings fills the settings group with the type dropdown,
-- one control per registry-declared field, and a delete button.
local function buildConditionSettings(panel, rule, condIndex, settings)
	local condition = rule.conditions[condIndex]
	local def = Conditions.Registry[condition.type]

	local typeDropdown = AceGUI:Create("Dropdown")
	typeDropdown:SetLabel("Condition")
	typeDropdown:SetList(conditionTypeValues())
	typeDropdown:SetValue(condition.type)
	typeDropdown:SetCallback("OnValueChanged", function(_, _, value)
		condition.type = value
		panel:NotifyPanelChanged()
	end)
	settings:AddChild(typeDropdown)

	if def then
		for field, fieldType in pairs(def.fields) do
			settings:AddChild(conditionField(condition, field, fieldType))
		end
	end

	local delete = AceGUI:Create("Button")
	delete:SetText("Delete condition")
	delete:SetCallback("OnClick", function()
		Profile.deleteCondition(rule, condIndex)
		conditionExpanded[condition] = nil
		panel:NotifyPanelChanged()
	end)
	settings:AddChild(delete)
end

-- conditionTypeValues returns the { key = label } map for the type dropdown.
local function conditionTypeValues()
	local list = Conditions.TypeList()
	local values = {}
	for i = 1, #list do
		values[list[i].key] = list[i].label
	end
	return values
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

-- spellValues returns the { name = name } map for the spell dropdown. The
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
-- rule card
-- ---------------------------------------------------------------------------

-- ruleCard builds one rule card: title bar with ▲/▼/Delete buttons, main
-- options, and a Conditions section.
local function ruleCard(panel, rotation, ruleIndex, container)
	local rule = rotation.rules[ruleIndex]
	local rules = rotation.rules

	local card = AceGUI:Create("InlineGroup")
	card:SetTitle(ruleTitle(rule, ruleIndex))
	card:SetFullWidth(true)
	container:AddChild(card)

	-- title-bar buttons, anchored to the card's top-right (right to left)
	local buttonOrder = {
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
	}
	local offset = 14
	local titleButtons = {}
	for i = #buttonOrder, 1, -1 do
		local spec = buttonOrder[i]
		local button = AceGUI:Create("Button")
		button:SetText(spec.label)
		button:SetAutoWidth(true)
		button.frame:SetParent(card.frame)
		button.frame:SetFrameLevel((card.frame:GetFrameLevel() or 1) + 2)
		button.frame:SetPoint("TOPRIGHT", card.frame, "TOPRIGHT", -offset, 0)
		button:SetDisabled(spec.disabled)
		button:SetCallback("OnClick", spec.func)
		-- AceGUI buttons start hidden and are only shown by AddChild; these
		-- are anchored to the card frame instead, so show them explicitly
		button.frame:Show()
		titleButtons[#titleButtons + 1] = button
		offset = offset + (button.frame:GetWidth() or 0) + 2
	end
	-- the title buttons are anchored to the card frame, not AddChild'd, so the
	-- panel's ReleaseChildren never sees them; release them when the card is
	-- released so the AceGUI pool stays consistent
	card:SetCallback("OnRelease", function()
		for i = 1, #titleButtons do
			AceGUI:Release(titleButtons[i])
		end
	end)

	-- main options
	local enabled = AceGUI:Create("CheckBox")
	enabled:SetLabel("Enabled")
	enabled:SetValue(rule.enabled)
	enabled:SetCallback("OnValueChanged", function(_, _, value)
		rule.enabled = value
	end)
	card:AddChild(enabled)

	local labelInput = AceGUI:Create("EditBox")
	labelInput:SetLabel("Label")
	labelInput:SetText(rule.name or "")
	labelInput:SetCallback("OnTextChanged", function(_, _, value)
		rule.name = value
	end)
	card:AddChild(labelInput)

	local spellDropdown = AceGUI:Create("Dropdown")
	spellDropdown:SetLabel("Spell")
	spellDropdown:SetList(spellValues(rule))
	spellDropdown:SetValue(rule.spell or "")
	spellDropdown:SetCallback("OnValueChanged", function(_, _, value)
		rule.spell = value
		panel:NotifyPanelChanged()
	end)
	card:AddChild(spellDropdown)

	local spellIdInput = AceGUI:Create("EditBox")
	spellIdInput:SetLabel("Spell ID (optional)")
	spellIdInput:SetText(rule.spellID and tostring(rule.spellID) or "")
	spellIdInput:SetCallback("OnTextChanged", function(_, _, value)
		rule.spellID = tonumber(value)
	end)
	card:AddChild(spellIdInput)

	local unitDropdown = AceGUI:Create("Dropdown")
	unitDropdown:SetLabel("Target unit")
	unitDropdown:SetList(Conditions.Units)
	unitDropdown:SetValue(rule.unit or "target")
	unitDropdown:SetCallback("OnValueChanged", function(_, _, value)
		rule.unit = value
	end)
	card:AddChild(unitDropdown)

	-- conditions section
	local conditionsGroup = AceGUI:Create("InlineGroup")
	conditionsGroup:SetTitle("Conditions")
	card:AddChild(conditionsGroup)

	local addCondition = AceGUI:Create("Button")
	addCondition:SetText("Add condition")
	addCondition:SetCallback("OnClick", function()
		Profile.addCondition(rule)
		panel:NotifyPanelChanged()
	end)
	conditionsGroup:AddChild(addCondition)

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
	-- the first OnShow, after AceConfig has stored the option table (which
	-- carries the rotation) in the widget's userdata.
	["OnAcquire"] = function(self)
		self:SetWidth(600)
		self:SetHeight(200)
		self.titletext:SetText("")
		self.rendered = false
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

	-- NotifyPanelChanged is called by every mutation closure: it rebuilds the
	-- whole panel from the live profile, mirroring AceConfig's rebuild-on-
	-- NotifyChange behavior for the declarative groups this widget replaces.
	["NotifyPanelChanged"] = function(self)
		self:RenderPanel()
	end,

	["RenderPanel"] = function(self)
		local rotation = self:PanelRotation()
		if not rotation then return end
		self:ReleaseChildren()
		if #rotation.rules == 0 then
			local emptyLabel = AceGUI:Create("Label")
			emptyLabel:SetText("No rules. Add one below.")
			self:AddChild(emptyLabel)
		else
			for i = 1, #rotation.rules do
				ruleCard(self, rotation, i, self)
			end
		end
		self:DoLayout()
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

local PaneBackdrop = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 3, right = 3, top = 5, bottom = 3 }
}

local function Constructor()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")

	local titletext = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titletext:SetPoint("TOPLEFT", 14, 0)
	titletext:SetPoint("TOPRIGHT", -14, 0)
	titletext:SetJustifyH("LEFT")
	titletext:SetHeight(18)

	local border = CreateFrame("Frame", nil, frame)
	border:SetPoint("TOPLEFT", 0, -17)
	border:SetPoint("BOTTOMRIGHT", -1, 3)
	border:SetBackdrop(PaneBackdrop)
	border:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
	border:SetBackdropBorderColor(0.4, 0.4, 0.4)

	local content = CreateFrame("Frame", nil, border)
	content:SetPoint("TOPLEFT", 10, -10)
	content:SetPoint("BOTTOMRIGHT", -10, 10)

	local widget = {
		frame = frame,
		content = content,
		titletext = titletext,
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
