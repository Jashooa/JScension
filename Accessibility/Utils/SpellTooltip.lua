-- Spell tooltip helper.
--
-- Attaches a GameTooltip spell tooltip to a frame: hovering shows the
-- tooltip for a spell, leaving hides it. The rule is resolved lazily through
-- a provider function, so a frame whose current spell changes (the cast
-- button) always shows the right tooltip.

local _, ns = ...

local SpellTooltip = {}

-- Attach wires OnEnter/OnLeave on a frame. ruleProvider is called with the
-- frame and must return a rule (with a spell) or nil; nil shows no tooltip.
-- anchor positions the tooltip relative to the frame or cursor. SpellPicker
-- is resolved at call time (Game loads after Utils in the TOC).
function SpellTooltip.Attach(frame, ruleProvider, anchor)
	local SpellPicker = ns.SpellPicker
	frame:EnableMouse(true)
	frame:SetScript("OnEnter", function(self)
		local rule = ruleProvider(self)
		local link = rule and SpellPicker.Link(rule)
		if not link then return end
		GameTooltip:SetOwner(self, anchor or "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink(link)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function(self)
		-- GameTooltip is one global frame shared by every tooltip anchor.
		-- Hide only when this frame is the one that showed it, so leaving one
		-- hover surface does not kill a tooltip another frame just opened.
		if GameTooltip:GetOwner() == self then
			GameTooltip:Hide()
		end
	end)
end

ns.SpellTooltip = SpellTooltip
