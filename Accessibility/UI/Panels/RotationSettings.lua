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
local OptionPanel = ns.OptionPanel
assert(Profile and Config and Fields and OptionPanel,
	"load order: UI/Panels/RotationSettings before its dependencies")
local Type, Version = "RotationSettings", 1
if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

-- ---------------------------------------------------------------------------
local function build(panel)
	local rotation = OptionPanel.RotationFromPath(panel)
	if not rotation then return end

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
	setActive:SetDisabled(Profile.activeName() == rotation.name)
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
end

OptionPanel.Register({
	type = Type,
	version = Version,
	initialHeight = 80,
	layoutHeightOffset = 0,
	build = build,
})
