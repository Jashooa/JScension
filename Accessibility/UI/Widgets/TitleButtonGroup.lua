-- TitleButtonGroup: a titled container with buttons in its title bar.
--
-- A reusable AceGUI container: a title text on the left, a row of buttons
-- anchored to the title bar's right edge, and a content area for children.
-- The rotation panel uses it for the Rules section, the rule cards, and the
-- Conditions sections, so the title-button layout code lives in one place.
--
-- Usage:
--   local section = AceGUI:Create("TitleButtonGroup")
--   section:SetTitle("Rules")
--   section:SetTitleButtons({
--     { label = "Add rule", func = fn },
--     { label = "▲", disabled = ruleIndex <= 1, func = fn },
--   })
--   section:AddChild(contentWidget)

local Type, Version = "TitleButtonGroup", 1
local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

local BUTTON_GAP = 2
local TITLE_RIGHT_INSET = 14

local methods = {
	["OnAcquire"] = function(self)
		self:SetWidth(300)
		self:SetHeight(100)
		self:SetTitle("")
		self.titleButtons = nil
		-- a pooled widget may have been released with its border hidden (a
		-- collapsed condition card); every new use starts with the border
		self.borderVisible = true
		self.border:Show()
		-- drop any tooltip scripts left by the previous owner's titlebar
		self.titlebar:SetScript("OnEnter", nil)
		self.titlebar:SetScript("OnLeave", nil)
	end,

	["SetTitle"] = function(self, title)
		self.titletext:SetText(title)
	end,

	-- SetTitleButtons installs the title-bar buttons. buttons is an array of
	-- { label, func, disabled }; they render right-to-left by list order.
	-- AceGUI buttons start hidden (only AddChild shows them), so each is
	-- shown explicitly after anchoring.
	["SetTitleButtons"] = function(self, buttons)
		if self.titleButtons then
			for i = 1, #self.titleButtons do
				AceGUI:Release(self.titleButtons[i])
			end
			self.titleButtons = nil
		end
		if not buttons or #buttons == 0 then return end

		self.titleButtons = {}
		local offset = TITLE_RIGHT_INSET
		for i = #buttons, 1, -1 do
			local spec = buttons[i]
			local button = AceGUI:Create("Button")
			button:SetText(spec.label)
			button:SetAutoWidth(true)
			-- match the title bar height (18) so every title button renders at
			-- the same size instead of AceGUI's default 24px
			button:SetHeight(18)
			button.frame:SetParent(self.frame)
			button.frame:SetFrameLevel((self.frame:GetFrameLevel() or 1) + 2)
			button.frame:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -offset, 0)
			button:SetDisabled(spec.disabled == true)
			button:SetCallback("OnClick", spec.func)
			button.frame:Show()
			self.titleButtons[i] = button
			offset = offset + (button.frame:GetWidth() or 0) + BUTTON_GAP
		end
	end,

	["OnRelease"] = function(self)
		if self.titleButtons then
			for i = 1, #self.titleButtons do
				AceGUI:Release(self.titleButtons[i])
			end
			self.titleButtons = nil
		end
	end,

	-- SetBorderVisible hides or shows the surrounding box. A collapsed card
	-- (no content) shows only the title row when the border is hidden.
	["SetBorderVisible"] = function(self, visible)
		self.borderVisible = visible
		if visible then
			self.border:Show()
		else
			self.border:Hide()
		end
	end,

	["LayoutFinished"] = function(self, width, height)
		if self.noAutoHeight then return end
		-- a borderless (collapsed) card is just the title row; a boxed one
		-- adds the border padding
		local baseHeight = self.borderVisible == false and 18 or 40
		self:SetHeight((height or 0) + baseHeight)
	end,

	["OnWidthSet"] = function(self, width)
		local content = self.content
		local contentWidth = width - 20
		if contentWidth < 0 then contentWidth = 0 end
		content:SetWidth(contentWidth)
		content.width = contentWidth
	end,

	["OnHeightSet"] = function(self, height)
		local content = self.content
		local contentHeight = height - 20
		if contentHeight < 0 then contentHeight = 0 end
		content:SetHeight(contentHeight)
		content.height = contentHeight
	end,
}

-- ---------------------------------------------------------------------------
-- constructor
-- ---------------------------------------------------------------------------

local PaneBackdrop = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 3, right = 3, top = 5, bottom = 3 }
}

local function Constructor()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")

	local titletext = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titletext:SetPoint("TOPLEFT", 14, 0)
	titletext:SetPoint("TOPRIGHT", -14, 0)
	titletext:SetJustifyH("LEFT")
	titletext:SetHeight(18)

	local border = CreateFrame("Frame", nil, frame)
	border:SetPoint("TOPLEFT", 0, -17)
	border:SetPoint("BOTTOMRIGHT", -1, 3)
	border:SetBackdrop(PaneBackdrop)
	border:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
	border:SetBackdropBorderColor(0.4, 0.4, 0.4)

	local content = CreateFrame("Frame", nil, border)
	content:SetPoint("TOPLEFT", 10, -10)
	content:SetPoint("BOTTOMRIGHT", -10, 10)

	-- an invisible, mouse-enabled frame over the title bar. FontStrings are
	-- Regions, not Frames, so they cannot reliably receive mouse events; the
	-- titlebar frame gives the title row a hover surface for tooltips.
	local titlebar = CreateFrame("Frame", nil, frame)
	titlebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	titlebar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	titlebar:SetHeight(18)
	titlebar:EnableMouse(true)

	local widget = {
		frame = frame,
		content = content,
		titletext = titletext,
		titlebar = titlebar,
		border = border,
		borderVisible = true,
		type = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end

	return AceGUI:RegisterAsContainer(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
