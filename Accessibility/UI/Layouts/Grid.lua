-- Grid: AceGUI layout for equal-width columns.
--
-- Children fill row by row. A child with child:SetUserData("colspan", N)
-- spans extra columns. Rows size to their tallest child, so mixed widget
-- heights stay aligned.
--
-- Usage:
--   container:SetUserData("columns", 3)      -- default 2
--   container:SetUserData("cellPadH", 6)     -- horizontal gap, default 4
--   container:SetUserData("cellPadV", 4)     -- vertical gap, default 4
--   container:SetLayout("Grid")

local AceGUI = LibStub("AceGUI-3.0")

AceGUI:RegisterLayout("Grid", function(content, children)
	local cols = content.obj:GetUserData("columns") or 2
	local padH = content.obj:GetUserData("cellPadH") or 4
	local padV = content.obj:GetUserData("cellPadV") or 4

	local totalW = content:GetWidth() or 0
	if totalW <= 0 then totalW = content.width or 300 end
	local cellW = (totalW - padH * (cols - 1)) / cols

	local x, y = 0, 0
	local col = 1
	local rowH = 0

	for i = 1, #children do
		local child = children[i]
		local span = child:GetUserData("colspan") or 1
		if span > cols then span = cols end

		-- wrap if this child does not fit in the current row
		if col + span - 1 > cols then
			y = y + rowH + padV
			x, col, rowH = 0, 1, 0
		end

		local w = cellW * span + padH * (span - 1)
		local frame = child.frame
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
		frame:SetWidth(w)
		if child.OnWidthSet then child:OnWidthSet(w) end
		frame:Show()

		local h = frame:GetHeight() or 0
		if h > rowH then rowH = h end

		x = x + w + padH
		col = col + span
	end

	-- report used height so scrollframes and parent groups size correctly
	local total = y + rowH
	if content.obj.LayoutFinished then
		content.obj:LayoutFinished(nil, total)
	end
end)
