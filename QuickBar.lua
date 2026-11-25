-- "Where?" quick bar: a slim strip of service icons under the arrow, for asking the way without
-- opening the window. Click an icon: the arrow turns to the nearest such NPC (and the world map
-- draws it). Click it again within 10 seconds: the next nearest. Hover: the three nearest.
-- "⋯" opens a small panel with every category, grouped: trainers, vendors, services (each of
-- the character's professions gets its own tile).
--
-- Setting quickBar; the minimap button's Shift-click shows or hides it. The bar is anchored under
-- the arrow, so it moves with it (dragging the bar drags the arrow).

local _, QL = ...

local MEDIA = "Interface\\AddOns\\QuestLineage\\Media\\"
local PRIMARY = { "repair", "inn", "flight", "classTrainer", "profTrainer", "food", "mail" }
local GROUPS = {
	{ key = "trainers", label = "Trainers" },
	{ key = "vendors", label = "Vendors" },
	{ key = "services", label = "Services" },
}
local CYCLE_TIME = 10

local bar, panel
local last = { key = nil, at = 0, index = 0 }

local function L(s) return QL.L(s) end

local function iconPath(name)
	if name == "class" then return MEDIA .. "nav_class" end
	return MEDIA .. "svc_" .. name
end

local function now() return GetTime and GetTime() or os.time() end

-- What a category is called; a profession tile carries its own name.
local function labelOf(key)
	if key:sub(1, 5) == "prof:" then return L(key:sub(6)) .. " " .. L("trainer") end
	local s = QL.SERVICE_BY_KEY[key]
	return s and L(s.label) or key
end

-- Point the arrow at the nearest (or, on a repeated click, the next nearest) of a category.
function QL.GoToService(key)
	local list = QL.NearestServices(key, 10)
	if #list == 0 then
		QL.Print(L("None found near you: ") .. labelOf(key))
		return nil
	end
	local t = now()
	if last.key == key and t - last.at < CYCLE_TIME then
		last.index = last.index % #list + 1
	else
		last.index = 1
	end
	last.key, last.at = key, t
	local pick = list[last.index]
	local label = (last.index == 1 and L("Nearest: ") or (L("Next nearest (%d): "):format(last.index))) .. labelOf(key)
	if pick.sub then label = label .. "  ·  " .. pick.sub end
	QL.SetArrowPlace(pick.kind, pick.id, { title = pick.name, label = label })
	return pick
end

local function showTip(owner, key)
	local tip = QL.Tip()
	tip:SetOwner(owner, "ANCHOR_TOP")
	tip:AddLine(labelOf(key), 1, 1, 1)
	local list = QL.NearestServices(key, 3)
	if #list == 0 then
		tip:AddLine(L("None found near you."), 0.6, 0.6, 0.6)
	else
		for i, e in ipairs(list) do
			local where = e.mapName and ("  ·  " .. e.mapName) or ""
			tip:AddLine(("%d. %s%s  ·  %s%s"):format(i, e.name, e.sub and (" <" .. e.sub .. ">") or "", QL.DistanceTextYards(e.dist), where), 0.85, 0.85, 0.85)
		end
	end
	tip:AddLine(L("Click: point the arrow · again: the next one"), 0.24, 0.84, 0.78)
	tip:Show()
end

local function serviceButton(parent, key, size, caption)
	local s = QL.SERVICE_BY_KEY[key]
	local icon = s and s.icon or "book"
	local b = QL.Theme.IconButton(parent, iconPath(icon), size, caption)
	b.key = key
	b:SetScript("OnClick", function(self)
		QL.GoToService(self.key)
		if panel and panel:IsShown() and parent == panel then panel:Hide() end
	end)
	local enter, leave = b:GetScript("OnEnter"), b:GetScript("OnLeave")
	b:SetScript("OnEnter", function(self) enter(self); pcall(showTip, self, self.key) end)
	b:SetScript("OnLeave", function(self) leave(self); QL.Tip():Hide() end)
	return b
end

-- The "more" panel ---------------------------------------------------------------------------------

local function buildPanel()
	local T, C = QL.Theme, QL.Theme.C
	panel = CreateFrame("Frame", "QuestLineageQuickPanel", bar)
	panel:SetFrameStrata("DIALOG")
	panel:SetFrameLevel(bar:GetFrameLevel() + 10)
	T.Fill(panel, { 0.055, 0.063, 0.082, 0.96 })
	T.Border(panel, C.line)
	local top = panel:CreateTexture(nil, "ARTWORK")
	top:SetTexture(T.WHITE)
	top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1)
	top:SetHeight(2)
	T.Gradient(top, "HORIZONTAL", C.accent, C.accent2)
	panel.parts = {}
	panel:Hide()
end

local function fillPanel()
	local T, C = QL.Theme, QL.Theme.C
	for _, p in ipairs(panel.parts) do p:Hide() end
	panel.parts = {}
	local COLS, TILE_W, TILE_H = 6, 60, 50
	local y = -12
	for _, g in ipairs(GROUPS) do
		local keys = {}
		for _, s in ipairs(QL.SERVICES) do
			if s.group == g.key and s.key ~= "profTrainer" then keys[#keys + 1] = s.key end
		end
		if g.key == "trainers" then
			for _, p in ipairs(QL.KnownProfessions()) do keys[#keys + 1] = QL.ProfessionKey(p) end
		end
		local head = T.Text(panel, 11, C.muted, nil, true)
		head:SetPoint("TOPLEFT", 12, y)
		head:SetText(L(g.label))
		panel.parts[#panel.parts + 1] = head
		y = y - 18
		for i, key in ipairs(keys) do
			local short = key:sub(1, 5) == "prof:" and L(key:sub(6)) or (QL.SERVICE_BY_KEY[key] and L(QL.SERVICE_BY_KEY[key].label) or key)
			local b = serviceButton(panel, key, 30, short)
			if key:sub(1, 5) == "prof:" then b.icon:SetTexture(iconPath("book")) end
			b:SetSize(TILE_W, TILE_H)
			local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
			b:SetPoint("TOPLEFT", 8 + col * TILE_W, y - row * TILE_H)
			panel.parts[#panel.parts + 1] = b
		end
		y = y - math.ceil(#keys / COLS) * TILE_H - 8
	end
	panel:SetSize(16 + COLS * TILE_W, -y + 4)
	panel:ClearAllPoints()
	panel:SetPoint("BOTTOM", bar, "TOP", 0, 6)
end

function QL.ToggleQuickPanel()
	if not bar then return end
	if not panel then buildPanel() end
	if panel:IsShown() then panel:Hide() else fillPanel(); panel:Show() end
end

-- The bar ---------------------------------------------------------------------------------------------

local function build()
	local T, C = QL.Theme, QL.Theme.C
	local arrow = QL.ArrowFrame and QL.ArrowFrame()
	bar = CreateFrame("Frame", "QuestLineageQuickBar", UIParent)
	bar:SetFrameStrata("DIALOG")
	bar:SetClampedToScreen(true)
	local SIZE, GAP = 30, 2
	local count = #PRIMARY + 1
	bar:SetSize(8 + count * (SIZE + GAP), SIZE + 8)
	if arrow then
		bar:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
	else
		bar:SetPoint("TOP", UIParent, "TOP", 0, -300)
	end
	T.Fill(bar, { 0.055, 0.063, 0.082, 0.88 })
	T.Border(bar, C.line)
	bar.buttons = {}
	for i, key in ipairs(PRIMARY) do
		local b = serviceButton(bar, key, SIZE)
		b:SetPoint("LEFT", 4 + (i - 1) * (SIZE + GAP), 0)
		bar.buttons[i] = b
	end
	local more = QL.Theme.IconButton(bar, iconPath("more"), SIZE)
	more:SetPoint("LEFT", 4 + #PRIMARY * (SIZE + GAP), 0)
	more:SetScript("OnClick", function() QL.ToggleQuickPanel() end)
	local enter, leave = more:GetScript("OnEnter"), more:GetScript("OnLeave")
	more:SetScript("OnEnter", function(self)
		enter(self)
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_TOP")
		tip:AddLine(L("More: every trainer, vendor and service"), 1, 1, 1)
		tip:Show()
	end)
	more:SetScript("OnLeave", function(self) leave(self); QL.Tip():Hide() end)
	bar.more = more
	-- dragging the bar drags the arrow it hangs from
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() if arrow then arrow:StartMoving() end end)
	bar:SetScript("OnDragStop", function()
		if not arrow then return end
		arrow:StopMovingOrSizing()
		local point, _, relPoint, x, y = arrow:GetPoint(1)
		QL.DB().arrowPoint = { point, relPoint, x, y }
	end)
	bar:SetShown(QL.DB().quickBar ~= false)
end

function QL.ToggleQuickBar()
	QL.Set("quickBar", QL.DB().quickBar == false)
end

QL.Event("PLAYER_LOGIN", function()
	local ok, err = pcall(build)
	if not ok then QL.Debug("quick bar: " .. tostring(err)) end
end)
QL.On("SETTING_CHANGED", function(key)
	if key == "quickBar" and bar then
		bar:SetShown(QL.DB().quickBar ~= false)
		if panel and QL.DB().quickBar == false then panel:Hide() end
	end
end)
