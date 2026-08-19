-- Shared lifecycle for AceGUI option panels.
--
-- Panels provide only their child-building function. This module owns the
-- container frame, first-show rendering, deferred refresh, and layout flow.

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

local Profile = ns.Profile
local Config = ns.Config
local ContentInset = ns.ContentInset
assert(Profile and Config and ContentInset,
	"load order: UI/Widgets/OptionPanel before Profile/Config/ContentInset")

local OptionPanel = {}

function OptionPanel.RotationFromPath(widget)
	local user = widget:GetUserDataTable()
	local path = user.path
	if type(path) ~= "table" then return nil end
	for i = 1, #path do
		local index = Config.rotationIndexFromKey(path[i])
		if index then return Profile.rotations()[index] end
	end
	return nil
end

function OptionPanel.Refresh(widget)
	if widget.refreshPending then return end
	widget.refreshPending = true
	widget.frame:SetScript("OnUpdate", function()
		widget.frame:SetScript("OnUpdate", nil)
		widget.refreshPending = nil
		widget:RenderPanel()
	end)
end

local function methodsFor(spec)
	return {
		OnAcquire = function(self)
			self:SetWidth(600)
			self:SetHeight(spec.initialHeight)
			self.titletext:SetText("")
			self.rendered = false
			self.refreshPending = nil
			self._scrollToBottom = nil
			self.frame:SetScript("OnUpdate", nil)
		end,
		SetText = function() end,
		OnWidthSet = ContentInset.OnWidthSet,
		OnHeightSet = ContentInset.OnHeightSet,
		LayoutFinished = function(self, width, height)
			self:SetHeight((height or 0) + spec.layoutHeightOffset)
		end,
		RenderPanel = function(self)
			local scrollToBottom = self._scrollToBottom
			self._scrollToBottom = nil
			self:ReleaseChildren()
			spec.build(self)
			self:DoLayout()
			local parent = self.parent
			if parent and parent.DoLayout then parent:DoLayout() end
			if scrollToBottom and parent and parent.SetScroll then
				parent:SetScroll(1000)
			end
		end,
	}
end

function OptionPanel.Register(spec)
	assert(spec and spec.type and spec.version and spec.initialHeight
		and spec.layoutHeightOffset and spec.build,
		"option panel spec is incomplete")
	local Type, Version = spec.type, spec.version
	if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

	local methods = methodsFor(spec)
	local function Constructor()
		local frame = CreateFrame("Frame", nil, UIParent)
		frame:SetFrameStrata("FULLSCREEN_DIALOG")

		local content = CreateFrame("Frame", nil, frame)
		content:SetPoint("TOPLEFT", 0, 0)
		content:SetPoint("BOTTOMRIGHT", 0, 0)

		local widget = {
			frame = frame,
			content = content,
			titletext = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal"),
			type = Type,
		}
		for method, func in pairs(methods) do widget[method] = func end
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
end

ns.OptionPanel = OptionPanel
