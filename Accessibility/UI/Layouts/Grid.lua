-- Grid: AceGUI layout for equal-width columns.
--
-- Children fill row by row. A child with child:SetUserData("colspan", N)
-- spans extra columns. Rows size to their tallest child, so mixed widget
-- heights stay aligned. Content is vertically centered when the container
-- is taller than the content.
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

	-- first pass: calculate row heights so we can vertically center
	local rows = {}
	local rowH, col = 0, 1
	for i = 1, #children do
		local child = children[i]
		local span = child:GetUserData("colspan") or 1
		if span > cols then span = cols end
		if col + span - 1 > cols then
			rows[#rows + 1] = rowH
			rowH, col = 0, 1
		end
		local h = child.frame:GetHeight() or 0
		if h > rowH then rowH = h end
		col = col + span
	end
	rows[#rows + 1] = rowH

	local totalH = 0
	for i = 1, #rows do totalH = totalH + rows[i] end
	totalH = totalH + padV * (#rows - 1)

	-- vertically center when the container is taller than the content
	local containerH = content:GetHeight() or 0
	local startY = 0
	if containerH > totalH then
		startY = (containerH - totalH) / 2
	end

	-- second pass: position children
	local x, y = 0, startY
	local row = 1
	col = 1
	rowH = 0

	for i = 1, #children do
		local child = children[i]
		local span = child:GetUserData("colspan") or 1
		if span > cols then span = cols end

		if col + span - 1 > cols then
			y = y + rowH + padV
			row = row + 1
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
	if content.obj.LayoutFinished then
		content.obj:LayoutFinished(nil, totalH)
	end
end)
