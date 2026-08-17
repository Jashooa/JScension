-- The log panel.
--
-- A custom AceGUI container ("Log") that renders the Refresh and Clear
-- buttons and the recent log ring as a text block.

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

local Config = ns.Config
local ContentInset = ns.ContentInset
assert(Config and ContentInset,
	"load order: UI/Panels/Log before its dependencies")
local Type, Version = "Log", 1
if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

local LOG_DISPLAY_LINES = 30

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
