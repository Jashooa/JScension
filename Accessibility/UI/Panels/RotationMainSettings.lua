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
local ContentInset = ns.ContentInset
local Fields = ns.Fields
assert(Profile and Config and Constants and ContentInset and Fields,
	"load order: UI/Panels/RotationMainSettings before its dependencies")
local Type, Version = "RotationMainSettings", 1
if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

-- ---------------------------------------------------------------------------
-- methods
-- ---------------------------------------------------------------------------

local methods = {
	["OnAcquire"] = function(self)
		self:SetWidth(600)
		self:SetHeight(300)
		self.rendered = false
	end,

	["SetText"] = function() end,

	["OnWidthSet"] = ContentInset.OnWidthSet,
	["OnHeightSet"] = ContentInset.OnHeightSet,

	["LayoutFinished"] = function(self, width, height)
		self:SetHeight((height or 0))
	end,

	["RenderPanel"] = function(self)
		self:ReleaseChildren()
		local panel = self
		local p = ns.addon.db.profile

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
		auto:SetValue(p.auto == true)
		auto:SetCallback("OnValueChanged", function()
			ns.addon:ToggleAuto()
		end)
		group:AddChild(auto)

		-- GCD probe spell
		local gcdProbe = Fields.Text("GCD probe spell", p.gcdProbeSpell or "", function(value)
			p.gcdProbeSpell = value
		end)
		group:AddChild(gcdProbe)

		local pulseInterval = AceGUI:Create("Slider")
		pulseInterval:SetLabel("Pulse interval")
		pulseInterval:SetSliderValues(0.05, 1.0, 0.05)
		pulseInterval:SetValue(p.pulseInterval or 0.2)
		pulseInterval:SetCallback("OnValueChanged", function(_, _, value)
			p.pulseInterval = value
		end)
		group:AddChild(pulseInterval)

		local queueWindow = AceGUI:Create("Slider")
		queueWindow:SetLabel("Spell queue window")
		queueWindow:SetSliderValues(0, 1.0, 0.05)
		queueWindow:SetValue(p.queueWindow or Constants.DEFAULT_QUEUE_WINDOW)
		queueWindow:SetCallback("OnValueChanged", function(_, _, value)
			p.queueWindow = value
		end)
		group:AddChild(queueWindow)

		self:DoLayout()
		local parent = self.parent
		if parent and parent.DoLayout then
			parent:DoLayout()
		end
	end,
}

-- ---------------------------------------------------------------------------
-- constructor
-- ---------------------------------------------------------------------------

local function Constructor()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 0, 0)
	content:SetPoint("BOTTOMRIGHT", 0, 0)

	local widget = {
		frame = frame,
		content = content,
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end

	widget = AceGUI:RegisterAsContainer(widget)

	frame:SetScript("OnShow", function()
		if not widget.rendered then
			widget.rendered = true
			widget:RenderPanel()
		end
	end)

	return widget
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
