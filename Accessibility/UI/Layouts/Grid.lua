-- Grid: AceGUI layout for equal-width columns.
--
-- Children fill row by row. A child with child:SetUserData("colspan", N)
-- spans extra columns. Rows size to their tallest child, so mixed widget
-- heights stay aligned. Shorter children are vertically centered within
-- their row.
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
	-- Nested containers must lay out at their final width before row heights
	-- are measured. Otherwise a child grid can grow after this grid positions
	-- it, causing its contents to escape the parent card.
	local function layoutChild(child, width)
		child:SetWidth(width)
		if child.DoLayout then child:DoLayout() end
	end
	for i = 1, #children do
		local child = children[i]
		local span = child:GetUserData("colspan") or 1
		if span > cols then span = cols end
		layoutChild(child, cellW * span + padH * (span - 1))
	end

	-- first pass: calculate each row's max height
	local rows = {}
	local rowH, col = 0, 1
	for i = 1, #children do
		local span = children[i]:GetUserData("colspan") or 1
		if span > cols then span = cols end
		if col + span - 1 > cols then
			rows[#rows + 1] = rowH
			rowH, col = 0, 1
		end
		local h = children[i].frame:GetHeight() or 0
		if h > rowH then rowH = h end
		col = col + span
	end
	rows[#rows + 1] = rowH

	local totalH = 0
	for i = 1, #rows do totalH = totalH + rows[i] end
	totalH = totalH + padV * (#rows - 1)

	-- second pass: position children, centering shorter ones in each row
	local x, y = 0, 0
	local row = 1
	col = 1

	for i = 1, #children do
		local child = children[i]
		local span = child:GetUserData("colspan") or 1
		if span > cols then span = cols end

		if col + span - 1 > cols then
			y = y + rows[row] + padV
			row = row + 1
			x, col = 0, 1
		end

		local w = cellW * span + padH * (span - 1)
		local frame = child.frame
		local h = frame:GetHeight() or 0
		local rowMax = rows[row] or 0
		local offsetY = y
		if rowMax > 0 and h < rowMax then
			offsetY = y + (rowMax - h) / 2
		end
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", content, "TOPLEFT", x, -offsetY)
		-- Width and nested layout were established in the prepass.
		frame:Show()

		x = x + w + padH
		col = col + span
	end

	if content.obj.LayoutFinished then
		content.obj:LayoutFinished(nil, totalH)
	end
end)
