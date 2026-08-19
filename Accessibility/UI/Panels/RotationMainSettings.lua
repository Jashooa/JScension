-- The rotation main settings panel.
--
-- A custom AceGUI container ("RotationMainSettings") that renders the
-- top-level rotation controls: active rotation dropdown, new rotation
-- button, auto cast toggle, pulse interval, spell queue window, and
-- GCD probe spell.

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

local Profile = ns.Profile
local Config = ns.Config
local Constants = ns.Constants
local Fields = ns.Fields
local OptionPanel = ns.OptionPanel
assert(Profile and Config and Constants and Fields and OptionPanel,
	"load order: UI/Panels/RotationMainSettings before its dependencies")
local Type, Version = "RotationMainSettings", 1
if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

-- ---------------------------------------------------------------------------
local function build(panel)
	local profile = Profile.current()

	-- auto cast, pulse interval, spell queue window in a 2-column row
	local group = AceGUI:Create("SimpleGroup")
	group:SetLayout("Grid")
	group:SetFullWidth(true)
	panel:AddChild(group)

	-- active rotation dropdown
	local list = Profile.rotations()
	local rotationNames = {}
	for i = 1, #list do
		rotationNames[i] = list[i].name
	end
	local activeDropdown = Fields.Dropdown("Active rotation", rotationNames,
		Profile.current().active, function(value)
			Profile.setActiveByName(value)
			Config.NotifyOptionsChanged()
		end)
	group:AddChild(activeDropdown)

	-- new rotation button
	local newRotation = AceGUI:Create("Button")
	newRotation:SetText("New rotation")
	newRotation:SetCallback("OnClick", function()
		Profile.addRotation("Rotation")
		Config.NotifyOptionsChanged()
	end)
	group:AddChild(newRotation)

	local auto = AceGUI:Create("CheckBox")
	auto:SetLabel("Auto cast")
	auto:SetValue(profile.auto == true)
	auto:SetCallback("OnValueChanged", function()
		ns.addon:ToggleAuto()
	end)
	group:AddChild(auto)

	-- GCD probe spell
	local gcdProbe = Fields.Text("GCD probe spell", profile.gcdProbeSpell or "", function(value)
		Profile.setGcdProbeSpell(value)
	end)
	group:AddChild(gcdProbe)

	local pulseInterval = AceGUI:Create("Slider")
	pulseInterval:SetLabel("Pulse interval")
	pulseInterval:SetSliderValues(0.05, 1.0, 0.05)
	pulseInterval:SetValue(profile.pulseInterval or 0.2)
	pulseInterval:SetCallback("OnValueChanged", function(_, _, value)
		Profile.setPulseInterval(value)
	end)
	group:AddChild(pulseInterval)

	local queueWindow = AceGUI:Create("Slider")
	queueWindow:SetLabel("Spell queue window")
	queueWindow:SetSliderValues(0, 1.0, 0.05)
	queueWindow:SetValue(profile.queueWindow or Constants.DEFAULT_QUEUE_WINDOW)
	queueWindow:SetCallback("OnValueChanged", function(_, _, value)
		Profile.setQueueWindow(value)
	end)
	group:AddChild(queueWindow)
	local antiSpam = AceGUI:Create("Slider")
	antiSpam:SetLabel("Anti-spam window")
	antiSpam:SetSliderValues(0.0, 2.0, 0.05)
	antiSpam:SetValue(profile.antiSpamWindow or Constants.DEFAULT_ANTI_SPAM_WINDOW)
	antiSpam:SetCallback("OnValueChanged", function(_, _, value)
		Profile.setAntiSpamWindow(value)
	end)
	group:AddChild(antiSpam)
end

OptionPanel.Register({
	type = Type,
	version = Version,
	initialHeight = 300,
	layoutHeightOffset = 0,
	build = build,
})
