-- The rotation settings panel.
--
-- A custom AceGUI container ("RotationSettings") that renders one rotation's
-- settings: the name input and the Set active / Duplicate / Delete buttons.
-- The buttons use the Grid layout so they sit in a single row.
--
-- AceConfig renders the panel through a leaf option with
-- `type = "execute", control = "RotationSettings"`. InjectInfo stores the
-- option path in the widget's userdata before AddChild shows the widget, so
-- the panel resolves its rotation from that path and renders on first OnShow.

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

local Profile = ns.Profile
local Config = ns.Config
local Fields = ns.Fields
local ContentInset = ns.ContentInset
assert(Profile and Config and Fields and ContentInset,
	"load order: UI/Panels/RotationSettings before its dependencies")
local Type, Version = "RotationSettings", 1
if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

-- ---------------------------------------------------------------------------
-- methods
-- ---------------------------------------------------------------------------

local methods = {
	-- OnAcquire resets to a hidden, empty state. The actual render happens on
	-- the first OnShow, after AceConfig has stored the option path in the
	-- widget's userdata.
	["OnAcquire"] = function(self)
		self:SetWidth(600)
		self:SetHeight(80)
		self.rendered = false
	end,

	-- SetText is called by AceConfig's execute-control setup; the panel has
	-- no button text, so it is a no-op.
	["SetText"] = function() end,

	["OnWidthSet"] = ContentInset.OnWidthSet,
	["OnHeightSet"] = ContentInset.OnHeightSet,

	["LayoutFinished"] = function(self, width, height)
		self:SetHeight((height or 0))
	end,

	-- PanelRotation resolves this panel's rotation from the option path
	-- AceConfig stored in the widget userdata. Identical to
	-- RotationRules.PanelRotation.
	["PanelRotation"] = function(self)
		local user = self:GetUserDataTable()
		local path = user.path
		if type(path) ~= "table" then return nil end
		for i = 1, #path do
			local index = Config.rotationIndexFromKey(path[i])
			if index then
				return Profile.rotations()[index]
			end
		end
		return nil
	end,

	-- RenderPanel builds the settings controls.
	["RenderPanel"] = function(self)
		local rotation = self:PanelRotation()
		if not rotation then return end
		self:ReleaseChildren()

		local panel = self

		-- name input
		local nameInput = Fields.Text("Name", rotation.name, function(value)
			Profile.renameRotation(rotation, value)
			Config.NotifyOptionsChanged()
		end)
		nameInput:SetFullWidth(true)
		panel:AddChild(nameInput)

		-- button row: 3 equal columns via Grid layout
		local buttonGroup = AceGUI:Create("SimpleGroup")
		buttonGroup:SetLayout("Grid")
		buttonGroup:SetUserData("columns", 3)
		buttonGroup:SetFullWidth(true)
		panel:AddChild(buttonGroup)

		local setActive = AceGUI:Create("Button")
		setActive:SetText("Set active")
		setActive:SetDisabled(Profile.current().active == rotation.name)
		setActive:SetCallback("OnClick", function()
			Profile.setActive(rotation)
			Config.NotifyOptionsChanged()
		end)
		buttonGroup:AddChild(setActive)

		local duplicate = AceGUI:Create("Button")
		duplicate:SetText("Duplicate")
		duplicate:SetCallback("OnClick", function()
			Profile.duplicateRotation(rotation)
			Config.NotifyOptionsChanged()
		end)
		buttonGroup:AddChild(duplicate)

		local delete = AceGUI:Create("Button")
		delete:SetText("Delete")
		delete:SetDisabled(#Profile.rotations() <= 1)
		delete:SetCallback("OnClick", function()
			Profile.deleteRotation(rotation)
			Config.NotifyOptionsChanged()
		end)
		buttonGroup:AddChild(delete)

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
