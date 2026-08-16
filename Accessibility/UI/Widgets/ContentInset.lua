-- ContentInset: the shared width/height handlers for the two custom AceGUI
-- containers.
--
-- TitleButtonGroup and RotationPanel both keep their content frame inset by
-- a fixed amount on each side, clamped to zero. The handlers are identical
-- in both, so they live here once and each widget references them directly.

local _, ns = ...

local INSET = 20

ns.ContentInset = {
	-- OnWidthSet keeps the content frame inset by INSET px on each side.
	OnWidthSet = function(self, width)
		local contentWidth = width - INSET
		if contentWidth < 0 then contentWidth = 0 end
		self.content:SetWidth(contentWidth)
		self.content.width = contentWidth
	end,
	-- OnHeightSet keeps the content frame inset by INSET px on each side.
	OnHeightSet = function(self, height)
		local contentHeight = height - INSET
		if contentHeight < 0 then contentHeight = 0 end
		self.content:SetHeight(contentHeight)
		self.content.height = contentHeight
	end,
}
