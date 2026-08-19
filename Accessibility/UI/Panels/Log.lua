-- The log panel.
--
-- A custom AceGUI container ("Log") that renders the Refresh and Clear
-- buttons and the recent log ring as a text block.

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

local Config = ns.Config
local OptionPanel = ns.OptionPanel
assert(Config and OptionPanel,
	"load order: UI/Panels/Log before its dependencies")
local Type, Version = "Log", 1
if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

local LOG_DISPLAY_LINES = 30

local function build(panel)
	local buttonGroup = AceGUI:Create("SimpleGroup")
	buttonGroup:SetLayout("Grid")
	buttonGroup:SetUserData("columns", 2)
	buttonGroup:SetUserData("cellPadH", 6)
	buttonGroup:SetFullWidth(true)
	panel:AddChild(buttonGroup)

	local refresh = AceGUI:Create("Button")
	refresh:SetText("Refresh")
	refresh:SetCallback("OnClick", function()
		Config.NotifyOptionsChanged()
	end)
	buttonGroup:AddChild(refresh)

	local clear = AceGUI:Create("Button")
	clear:SetText("Clear")
	clear:SetCallback("OnClick", function()
		ns.Log.Clear()
		Config.NotifyOptionsChanged()
	end)
	buttonGroup:AddChild(clear)

	local lines = ns.Log.Dump(LOG_DISPLAY_LINES)
	local output = AceGUI:Create("Label")
	output:SetText(#lines > 0 and table.concat(lines, "\n") or "No log entries.")
	output:SetFullWidth(true)
	panel:AddChild(output)
end

OptionPanel.Register({
	type = Type,
	version = Version,
	initialHeight = 300,
	layoutHeightOffset = 0,
	build = build,
})
