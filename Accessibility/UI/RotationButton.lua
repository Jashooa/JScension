-- The in-world cast button.
--
-- A plain frame, not a secure one. Its OnClick is tainted and calls
-- Rotation.CastBest, which hands the cast to Compatibility.Cast. The button
-- shows the first enabled spell's icon and a gold border when that spell is
-- ready.

local _, ns = ...

local RotationButton = {}

local Profile = ns.Profile
local Rotation = ns.Rotation
local SpellPicker = ns.SpellPicker
local Cooldown = ns.Cooldown
local SpellTooltip = ns.SpellTooltip
assert(Profile and Rotation and SpellPicker and Cooldown and SpellTooltip,
	"load order: UI/RotationButton before its dependencies")

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local BUTTON_SIZE = 44
local AUTO_BUTTON_SIZE = 16
local REFRESH_INTERVAL = 0.25

local frame = nil
local autoButton = nil

-- spellReady returns true when the rule's spell is usable and off cooldown.
local function spellReady(rule)
	local ref = SpellPicker.Ref(rule.spellID, rule.spell)
	return Cooldown.isReady(ref)
end

-- Refresh updates the icon and the ready border. The icon shows the spell a
-- click would actually cast: Rotation.NextRule returns the first rule that
-- passes every gate, so an earlier blocked rule does not pin a stale icon.
function RotationButton.Refresh()
	if not frame then return end
	local rule = Rotation.NextRule()
	frame.currentRule = rule
	local icon = QUESTION_MARK
	local ready = false
	if rule then
		icon = SpellPicker.Icon(rule) or QUESTION_MARK
		ready = spellReady(rule)
	end
	frame.icon:SetTexture(icon)
	if ready then
		frame:SetBackdropBorderColor(1, 0.82, 0, 1)     -- gold
	else
		frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)  -- dim
	end
end

-- RefreshAuto repaints the auto toggle: green when auto is on, red when off.
-- It reads the live profile so the colour follows every auto change (button
-- click, slash command, or the options panel), not just the last click here.
function RotationButton.RefreshAuto()
	if not autoButton then return end
	if Profile.current().auto then
		autoButton:SetBackdropColor(0.1, 0.8, 0.1, 1)   -- green: on
	else
		autoButton:SetBackdropColor(0.8, 0.1, 0.1, 1)   -- red: off
	end
end

-- SetVisible shows or hides the button frame. Hiding keeps the saved position
-- intact; re-showing restores it at the same spot.
function RotationButton.SetVisible(visible)
	if not frame then return end
	if visible then
		frame:Show()
	else
		frame:Hide()
	end
end

-- ApplyPosition places the button from the saved settings.
function RotationButton.ApplyPosition(saved)
	if not frame then return end
	local b = saved or Profile.current().button
	frame:ClearAllPoints()
	frame:SetPoint(b.point or "CENTER", UIParent, b.relativePoint or "CENTER", b.x or 0, b.y or 0)
	frame:SetScale(b.scale or 1.0)
	RotationButton.SetVisible(b.enabled ~= false)
	RotationButton.Refresh()
end

-- Create builds the button. Core calls it once.
function RotationButton.Create(saved)
	if frame then return end

	frame = CreateFrame("Button", "AccessibilityButton", UIParent)
	frame:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	-- Without RegisterForDrag the engine never dispatches OnDragStart, so
	-- the button could not be moved. LeftButton matches the click binding.
	frame:RegisterForDrag("LeftButton")

	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 2,
	})
	frame:SetBackdropColor(0, 0, 0, 0.6)

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetAllPoints(frame)
	frame.icon:SetTexture(QUESTION_MARK)

	-- hovering the button shows the tooltip for the spell it would cast;
	-- currentRule is refreshed on every Refresh
	SpellTooltip.Attach(frame, function(self)
		return self.currentRule
	end, "ANCHOR_RIGHT")

	-- auto toggle: a small "A" button pinned to the cast button's top-right
	autoButton = CreateFrame("Button", nil, frame)
	autoButton:SetSize(AUTO_BUTTON_SIZE, AUTO_BUTTON_SIZE)
	-- sits just outside the cast button's top-right corner; the two buttons'
	-- top edges line up (same Y)
	autoButton:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
	autoButton:SetFrameLevel(frame:GetFrameLevel() + 5)
	autoButton:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	autoButton:SetBackdropColor(0.8, 0.1, 0.1, 1)   -- red until first refresh
	autoButton.text = autoButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	autoButton.text:SetPoint("CENTER")
	autoButton.text:SetText("A")
	autoButton:SetScript("OnClick", function()
		ns.addon:ToggleAuto()
	end)

	frame:SetScript("OnClick", function()
		ns.addon:PulseOnce()
	end)
	frame:SetScript("OnDragStart", function(self)
		if Profile.current().button.locked then return end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local b = Profile.current().button
		local point, _, relPoint, x, y = self:GetPoint()
		b.point = point
		b.relativePoint = relPoint
		b.x = x
		b.y = y
	end)

	-- refresh the ready strip and the auto toggle a few times a second
	local sinceRefresh = 0
	frame:SetScript("OnUpdate", function(self, dt)
		sinceRefresh = sinceRefresh + dt
		if sinceRefresh < REFRESH_INTERVAL then return end
		sinceRefresh = 0
		RotationButton.Refresh()
		RotationButton.RefreshAuto()
	end)

	RotationButton.ApplyPosition(saved)
	RotationButton.RefreshAuto()
end

ns.RotationButton = RotationButton
