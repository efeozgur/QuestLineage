-- A QuestLineage button on the edge of the minimap (setting minimapButton, on by default).
--   left click   open or close the window
--   right click  settings
--   drag         move it round the minimap's rim (the angle is saved: minimapAngle)
--
--   QL.MinimapPosition(angle, radius) -> x, y   offset from the minimap's centre (pure, tested)

local _, QL = ...

local RADIUS = 80 -- fallback: half the classic 140px minimap plus the rim
local RIM = 5     -- how far past the minimap's edge the button's centre sits, so it rides the border
local ICON = "Interface\\Icons\\INV_Misc_Book_09"

local button

-- The rim's radius from the minimap's own size: a fixed 80 put the button inside Forever's
-- larger minimap.
function QL.MinimapRadius()
	local w = Minimap and Minimap.GetWidth and Minimap:GetWidth()
	if type(w) == "number" and w > 0 then return w / 2 + RIM end
	return RADIUS
end

function QL.MinimapPosition(angle, radius)
	local a = math.rad(angle or 0)
	radius = radius or QL.MinimapRadius()
	return math.cos(a) * radius, math.sin(a) * radius
end

local function place()
	if not button then return end
	local x, y = QL.MinimapPosition(QL.DB().minimapAngle or 215)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
QL.PlaceMinimapButton = place

-- The cursor's angle round the minimap's centre, in degrees.
local function cursorAngle()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	if not (mx and my and cx and cy and scale and scale > 0) then return nil end
	return math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
end

local function build()
	if button or not Minimap or not CreateFrame then return end
	local b = CreateFrame("Button", "QuestLineageMinimapButton", Minimap)
	button = b
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local back = b:CreateTexture(nil, "BACKGROUND")
	back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	back:SetSize(20, 20)
	back:SetPoint("TOPLEFT", 7, -5)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetTexture(ICON)
	b.icon:SetSize(17, 17)
	b.icon:SetPoint("TOPLEFT", 7, -6)
	b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	local ring = b:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	ring:SetSize(53, 53)
	ring:SetPoint("TOPLEFT")

	b:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			if QL.OpenOptions then QL.OpenOptions() end
		else
			QL.ToggleWindow()
		end
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local a = cursorAngle()
			if a then QL.DB().minimapAngle = a; place() end
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_LEFT")
		tip:AddLine("QuestLineage", 0.24, 0.84, 0.78)
		tip:AddLine(QL.L("Click: open or close"), 1, 1, 1)
		tip:AddLine(QL.L("Right-click: settings"), 1, 1, 1)
		tip:AddLine(QL.L("Drag: move round the minimap"), 0.6, 0.6, 0.6)
		tip:Show()
	end)
	b:SetScript("OnLeave", function() QL.Tip():Hide() end)
	place()
	-- the minimap can change size (other addons, the client's own settings): follow it
	if Minimap.HookScript then Minimap:HookScript("OnSizeChanged", place) end
	b:SetShown(QL.DB().minimapButton ~= false)
end

QL.Event("PLAYER_LOGIN", function()
	local ok, err = pcall(build)
	if not ok then QL.Debug("minimap button: " .. tostring(err)) end
end)

QL.On("SETTING_CHANGED", function(key)
	if key == "minimapButton" and button then button:SetShown(QL.DB().minimapButton ~= false) end
end)
