-- The rotation rules panel.
--
-- A custom AceGUI container ("RotationRules") that renders one rotation's
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
-- `type = "execute", control = "RotationRules"`. InjectInfo stores the option
-- path in the widget's userdata before AddChild shows the widget, so the
-- panel resolves its rotation from that path and renders on first OnShow.

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

local Profile = ns.Profile
local Conditions = ns.Conditions
local SpellPicker = ns.SpellPicker
local SpellTooltip = ns.SpellTooltip
local Fields = ns.Fields
local OptionPanel = ns.OptionPanel
assert(Profile and Conditions and SpellPicker and SpellTooltip and Fields and OptionPanel,
	"load order: UI/Panels/RotationRules before its dependencies")
local Type, Version = "RotationRules", 1
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

-- spellValues returns the ordered spell list for the spell dropdown. The
-- rule's current spell is appended if stale (not in the book) so it still
-- renders. No empty entry: the spell field starts nil and the user must pick.
local function spellValues(rule)
	local list = SpellPicker.List()
	local values = {}
	for i = 1, #list do
		values[i] = list[i]
	end
	if rule.spell and rule.spell ~= "" then
		local found = false
		for i = 1, #values do
			if values[i] == rule.spell then found = true; break end
		end
		if not found then values[#values + 1] = rule.spell end
	end
	return values
end

-- ---------------------------------------------------------------------------
-- condition card
-- ---------------------------------------------------------------------------

-- conditionExpanded tracks whether a condition's settings are shown. Keyed
-- by the condition table so it survives panel rebuilds.
local conditionExpanded = {}

-- ruleExpanded tracks whether a rule's settings are shown. Keyed by the
-- rule table so it survives panel rebuilds.
local ruleExpanded = {}

-- conditionTypeValues returns the { key = label } map for the type dropdown
-- plus an order array sorted by label so the dropdown is alphabetical.
local function conditionTypeValues()
	local list = Conditions.TypeList()
	local values = {}
	for i = 1, #list do
		values[list[i].key] = list[i].label
	end
	-- sort keys by label for alphabetical display
	local order = {}
	for i = 1, #list do
		order[i] = list[i].key
	end
	table.sort(order, function(a, b) return values[a] < values[b] end)
	return values, order
end

-- conditionField renders one registry-declared field as the right AceGUI widget.
local function conditionField(condition, fieldKey, fieldType, onChange)
	local name = Conditions.FieldLabel(fieldKey)
	local function commit(value)
		Profile.setConditionField(condition, fieldKey, value)
		if onChange then onChange() end
	end
	if fieldType == "percent" then
		-- slider always has a value; init nil to 0 (slider cannot be empty)
		if condition[fieldKey] == nil then Profile.setConditionField(condition, fieldKey, 0) end
		return Fields.Slider(name, 0, 100, 1, condition[fieldKey], commit)
	elseif fieldType == "op" then
		return Fields.Dropdown(name, Conditions.Ops, condition[fieldKey], commit)
	elseif fieldType == "unit" then
		return Fields.Dropdown(name, Conditions.Units, condition[fieldKey], commit)
	elseif fieldType == "kind" then
		return Fields.Dropdown(name, Conditions.Kinds, condition[fieldKey], commit)
	elseif fieldType == "target_type" then
		return Fields.Dropdown(name, Conditions.TargetTypes, condition[fieldKey], commit)
	elseif fieldType == "classification" then
		return Fields.Dropdown(name, Conditions.Classifications, condition[fieldKey], commit)
	elseif fieldType == "modifier" then
		return Fields.Dropdown(name, Conditions.Modifiers, condition[fieldKey], commit)
	elseif fieldType == "power" then
		return Fields.Dropdown(name, Conditions.Powers, condition[fieldKey], commit)
	elseif fieldType == "number" then
		return Fields.Text(name, condition[fieldKey] and tostring(condition[fieldKey]) or "", function(value)
			Profile.setConditionField(condition, fieldKey, value)
			if onChange then onChange() end
		end)
	elseif fieldType == "bool" then
		-- checkbox always has a value; init nil to false
		if condition[fieldKey] == nil then Profile.setConditionField(condition, fieldKey, false) end
		return Fields.CheckBox(name, condition[fieldKey], commit)
	elseif fieldType == "code" then
		return Fields.Multiline(name, condition[fieldKey], function(value)
			Profile.setConditionField(condition, fieldKey, value)
			if onChange then onChange() end
		end)
	else
		-- "spell", "string", and anything unknown render as a single-line box
		return Fields.Text(name, condition[fieldKey], function(value)
			Profile.setConditionField(condition, fieldKey, value)
			if onChange then onChange() end
		end)
	end
end

-- The registry owns required and optional condition-field semantics.
local function isConditionComplete(condition)
	return Conditions.IsComplete(condition)
end

-- setCardColor applies the standard title color: red = incomplete, orange =
-- disabled, green = enabled and valid. Red overrides orange.
local function setCardColor(card, complete, enabled)
	if not complete then
		card:SetTitleColor(1, 0.3, 0.3)
	elseif enabled == false then
		card:SetTitleColor(1, 0.6, 0)
	else
		card:SetTitleColor(0.3, 0.8, 0.3)
	end
end

-- buildConditionSettings fills the expanded card with the type dropdown and
-- one control per registry-declared field. Widths match the old editor: the
-- type is full width, fields keep their default single width.
local function buildConditionSettings(panel, rule, condIndex, container)
	local condition = rule.conditions[condIndex]
	local controls = AceGUI:Create("SimpleGroup")
	controls:SetFullWidth(true)
	controls:SetLayout("Grid")
	container:AddChild(controls)

	-- updateCardState refreshes the title text and color. Red = incomplete,
	-- orange = disabled, green = enabled and valid. Red overrides orange.
	local function updateCardState()
		container:SetTitle(Conditions.Describe(condition))
		setCardColor(container, isConditionComplete(condition), condition.enabled)
	end

	local enabled = AceGUI:Create("CheckBox")
	enabled:SetLabel("Enabled")
	enabled:SetValue(condition.enabled ~= false)
	enabled:SetCallback("OnValueChanged", function(_, _, value)
		Profile.setConditionEnabled(condition, value)
		updateCardState()
	end)
	controls:AddChild(enabled)

	local negate = AceGUI:Create("CheckBox")
	negate:SetLabel("Negate")
	negate:SetValue(condition.negated == true)
	negate:SetCallback("OnValueChanged", function(_, _, value)
		Profile.setConditionNegated(condition, value)
		updateCardState()
	end)
	controls:AddChild(negate)

	local typeDropdown = AceGUI:Create("Dropdown")
	typeDropdown:SetFullWidth(true)
	typeDropdown:SetUserData("colspan", 2)
	typeDropdown:SetList(conditionTypeValues())
	typeDropdown:SetValue(condition.type)
	typeDropdown:SetCallback("OnValueChanged", function(_, _, value)
		Profile.setConditionType(condition, value)
		updateCardState()
		OptionPanel.Refresh(panel)
	end)
	controls:AddChild(typeDropdown)

	local fields = Conditions.Fields(condition.type)
	if fields then
		for i = 1, #fields do
			local field = fields[i]
			local control = conditionField(condition, field.key, field.type, updateCardState)
			if field.type == "code" then control:SetUserData("colspan", 2) end
			controls:AddChild(control)
		end
		updateCardState()
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
			OptionPanel.Refresh(panel)
		end },
		{ label = "Delete", func = function()
			Profile.deleteCondition(rule, condIndex)
			conditionExpanded[condition] = nil
			OptionPanel.Refresh(panel)
		end },
	})
	container:AddChild(card)

	if conditionExpanded[condition] then
		card:SetBorderVisible(true)
		buildConditionSettings(panel, rule, condIndex, card)
	else
		card:SetBorderVisible(false)
		setCardColor(card, isConditionComplete(condition), condition.enabled)
	end
	return card
end

-- ---------------------------------------------------------------------------
-- rule card
-- ---------------------------------------------------------------------------

-- ruleCard builds one rule card. Settings are shown only when expanded; a
-- collapsed card shows just the title and buttons. The title color follows
-- the same scheme as conditions: red = incomplete, orange = disabled,
-- green = enabled and valid.
local function ruleCard(panel, rotation, ruleIndex, container)
	local rule = rotation.rules[ruleIndex]
	local rules = rotation.rules

	local card = AceGUI:Create("TitleButtonGroup")
	card:SetTitle(ruleTitle(rule, ruleIndex))
	card:SetFullWidth(true)
	card:SetLayout("Flow")
	local function isRuleComplete()
		return rule.spell and rule.spell ~= "" and rule.unit and rule.unit ~= ""
	end
	local function updateCardState()
		card:SetTitle(ruleTitle(rule, ruleIndex))
		setCardColor(card, isRuleComplete(), rule.enabled)
	end
	updateCardState()
	card:SetTitleButtons({
		{ label = ruleExpanded[rule] and "−" or "+", func = function()
			ruleExpanded[rule] = not ruleExpanded[rule]
			OptionPanel.Refresh(panel)
		end },
		{ label = "▲", disabled = ruleIndex <= 1, func = function()
			Profile.moveRule(rotation, ruleIndex, ruleIndex - 1)
			OptionPanel.Refresh(panel)
		end },
		{ label = "▼", disabled = ruleIndex >= #rules, func = function()
			Profile.moveRule(rotation, ruleIndex, ruleIndex + 1)
			OptionPanel.Refresh(panel)
		end },
		{ label = "Delete", func = function()
			Profile.deleteRule(rotation, ruleIndex)
			ruleExpanded[rule] = nil
			OptionPanel.Refresh(panel)
		end },
	})
	SpellTooltip.Attach(card.titlebar, function() return rule end)
	container:AddChild(card)

	if ruleExpanded[rule] then
		card:SetBorderVisible(true)
		local controls = AceGUI:Create("SimpleGroup")
		controls:SetFullWidth(true)
		controls:SetLayout("Grid")
		card:AddChild(controls)

		local enabled = AceGUI:Create("CheckBox")
		enabled:SetLabel("Enabled")
		enabled:SetValue(rule.enabled ~= false)
		enabled:SetCallback("OnValueChanged", function(_, _, value)
			Profile.setRuleEnabled(rule, value)
			updateCardState()
		end)
		controls:AddChild(enabled)

		local labelInput = Fields.Text("Label", rule.name, function(value)
			Profile.setRuleName(rule, value)
			card:SetTitle(ruleTitle(rule, ruleIndex))
		end)
		controls:AddChild(labelInput)
		local spellDropdown = Fields.Dropdown("Spell", spellValues(rule), rule.spell, function(value)
			Profile.setRuleSpell(rule, value)
			updateCardState()
			OptionPanel.Refresh(panel)
		end)
		controls:AddChild(spellDropdown)

		local unitDropdown = Fields.Dropdown("Target unit", Conditions.Units, rule.unit, function(value)
			Profile.setRuleUnit(rule, value)
			updateCardState()
		end)
		controls:AddChild(unitDropdown)

		local conditionsGroup = AceGUI:Create("TitleButtonGroup")
		conditionsGroup:SetTitle("Conditions")
		conditionsGroup:SetFullWidth(true)
		conditionsGroup:SetUserData("colspan", 2)
		conditionsGroup:SetLayout("Flow")
		conditionsGroup:SetTitleButtons({
			{ label = "Add condition", func = function()
				Profile.addCondition(rule)
				conditionExpanded[rule.conditions[#rule.conditions]] = true
				OptionPanel.Refresh(panel)
			end },
		})
		controls:AddChild(conditionsGroup)

		for i = 1, #rule.conditions do
			conditionCard(panel, rule, i, conditionsGroup)
		end
	else
		card:SetBorderVisible(false)
		setCardColor(card, isRuleComplete(), rule.enabled)
	end

	return card
end

-- ---------------------------------------------------------------------------
-- panel content
-- ---------------------------------------------------------------------------

local function build(panel)
	local rotation = OptionPanel.RotationFromPath(panel)
	if not rotation then return end

	-- Rules section: its title bar carries the "Add rule" button
	local rulesSection = AceGUI:Create("TitleButtonGroup")
	rulesSection:SetTitle("Rules")
	rulesSection:SetFullWidth(true)
	rulesSection:SetLayout("Flow")
	rulesSection:SetTitleButtons({
		{ label = "Add rule", func = function()
			Profile.addRule(rotation)
			ruleExpanded[rotation.rules[#rotation.rules]] = true
			panel._scrollToBottom = true
			OptionPanel.Refresh(panel)
		end },
	})
	panel:AddChild(rulesSection)

	if #rotation.rules == 0 then
		local emptyLabel = AceGUI:Create("Label")
		emptyLabel:SetText("No rules. Add one above.")
		rulesSection:AddChild(emptyLabel)
	else
		for i = 1, #rotation.rules do
			ruleCard(panel, rotation, i, rulesSection)
		end
	end
end

OptionPanel.Register({
	type = Type,
	version = Version,
	initialHeight = 200,
	layoutHeightOffset = 40,
	build = build,
})
