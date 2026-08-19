-- The button settings panel.
--
-- A custom AceGUI container ("ButtonSettings") that renders the rotation
-- button controls: show/hide toggle, lock toggle, scale slider, and reset
-- position button.

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

local Profile = ns.Profile
local Fields = ns.Fields
local OptionPanel = ns.OptionPanel
assert(Profile and Fields and OptionPanel,
	"load order: UI/Panels/ButtonSettings before its dependencies")
local Type, Version = "ButtonSettings", 1
if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

-- ---------------------------------------------------------------------------
local function build(panel)
	local button = Profile.current().button

	-- toggles + reset in a 2-column row
	local group = AceGUI:Create("SimpleGroup")
	group:SetLayout("Grid")
	group:SetFullWidth(true)
	panel:AddChild(group)

	local visible = AceGUI:Create("CheckBox")
	visible:SetLabel("Show button")
	visible:SetValue(button.enabled ~= false)
	visible:SetCallback("OnValueChanged", function(_, _, value)
		Profile.setButtonEnabled(button, value)
		ns.RotationButton.SetVisible(value)
	end)
	group:AddChild(visible)

	local locked = AceGUI:Create("CheckBox")
	locked:SetLabel("Lock position")
	locked:SetValue(button.locked == true)
	locked:SetCallback("OnValueChanged", function(_, _, value)
		Profile.setButtonLocked(button, value)
	end)
	group:AddChild(locked)

	local reset = AceGUI:Create("Button")
	reset:SetText("Reset position")
	reset:SetCallback("OnClick", function()
		Profile.setButtonPosition(button, "CENTER", "CENTER", 0, 0)
		ns.RotationButton.ApplyPosition(button)
	end)
	group:AddChild(reset)

	-- scale slider
	local scale = AceGUI:Create("Slider")
	scale:SetLabel("Scale")
	scale:SetSliderValues(0.5, 2.0, 0.1)
	scale:SetValue(button.scale or 1.0)
	scale:SetCallback("OnValueChanged", function(_, _, value)
		Profile.setButtonScale(button, value)
		ns.RotationButton.ApplyPosition(button)
	end)
	group:AddChild(scale)
end

OptionPanel.Register({
	type = Type,
	version = Version,
	initialHeight = 200,
	layoutHeightOffset = 0,
	build = build,
})
