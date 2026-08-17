-- The button settings panel.
--
-- A custom AceGUI container ("ButtonSettings") that renders the rotation
-- button controls: show/hide toggle, lock toggle, scale slider, and reset
-- position button.

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

local Config = ns.Config
local ContentInset = ns.ContentInset
local Fields = ns.Fields
assert(Config and ContentInset and Fields,
	"load order: UI/Panels/ButtonSettings before its dependencies")
local Type, Version = "ButtonSettings", 1
if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

-- ---------------------------------------------------------------------------
-- methods
-- ---------------------------------------------------------------------------

local methods = {
	["OnAcquire"] = function(self)
		self:SetWidth(600)
		self:SetHeight(200)
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
		local b = ns.addon.db.profile.button

		-- toggles + reset in a 2-column row
		local group = AceGUI:Create("SimpleGroup")
		group:SetLayout("Grid")
		group:SetFullWidth(true)
		panel:AddChild(group)

		local visible = AceGUI:Create("CheckBox")
		visible:SetLabel("Show button")
		visible:SetValue(b.enabled ~= false)
		visible:SetCallback("OnValueChanged", function(_, _, value)
			b.enabled = value
			ns.RotationButton.SetVisible(value)
		end)
		group:AddChild(visible)

		local locked = AceGUI:Create("CheckBox")
		locked:SetLabel("Lock position")
		locked:SetValue(b.locked == true)
		locked:SetCallback("OnValueChanged", function(_, _, value)
			b.locked = value
		end)
		group:AddChild(locked)

		local reset = AceGUI:Create("Button")
		reset:SetText("Reset position")
		reset:SetCallback("OnClick", function()
			b.point, b.relativePoint, b.x, b.y = "CENTER", "CENTER", 0, 0
			ns.RotationButton.ApplyPosition(b)
		end)
		group:AddChild(reset)

		-- scale slider
		local scale = AceGUI:Create("Slider")
		scale:SetLabel("Scale")
		scale:SetSliderValues(0.5, 2.0, 0.1)
		scale:SetValue(b.scale or 1.0)
		scale:SetCallback("OnValueChanged", function(_, _, value)
			b.scale = value
			ns.RotationButton.ApplyPosition(b)
		end)
		group:AddChild(scale)

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
