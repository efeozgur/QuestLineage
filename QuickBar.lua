-- "Where?" quick bar: a slim strip of service icons under the arrow, for asking the way without
-- opening the window. Click an icon: the arrow turns to the nearest such NPC (and the world map
-- draws it). Click it again within 10 seconds: the next nearest. Hover: the three nearest.
-- "⋯" opens a small panel with every category, grouped: trainers, professions (all of them, so a
-- trainer can be found before the profession is learnt; the known ones first and lit), vendors,
-- services.
--
-- Setting quickBar; the minimap button's Shift-click shows or hides it. The bar stands on its own:
-- drag it by its grip, its edge or any icon to put it anywhere (quickBarPoint).

local _, QL = ...

local MEDIA = "Interface\\AddOns\\QuestLineage\\Media\\"
local PRIMARY = { "repair", "inn", "flight", "classTrainer", "profTrainer", "food", "mail" }
local GROUPS = {
	{ key = "trainers", label = "Trainers" },
	{ key = "professions", label = "Professions" },
	{ key = "vendors", label = "Vendors" },
	{ key = "services", label = "Services" },
}
local CYCLE_TIME = 10

local bar, panel

local function startMove() if bar then bar:StartMoving() end end
local function stopMove()
	if not bar then return end
	bar:StopMovingOrSizing()
	local point, _, relPoint, x, y = bar:GetPoint(1)
	QL.DB().quickBarPoint = { point, relPoint, x, y }
end

-- Icons capture the mouse: let them pass a drag on to the bar (a click still clicks).
local function draggable(b)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", startMove)
	b:SetScript("OnDragStop", stopMove)
end
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
		QL.Print(L("None found near you: ") .. labelOf(key), "warn")
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
	tip:SetOwner(owner, "ANCHOR_BOTTOM")
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
	if parent == bar then draggable(b) end
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

-- The professions, the character's known ones first. -> keys, known set
local function professionKeys()
	local known, keys = {}, {}
	for _, p in ipairs(QL.KnownProfessions()) do known[p] = true; keys[#keys + 1] = QL.ProfessionKey(p) end
	for _, p in ipairs(QL.PROFESSIONS) do
		if not known[p] then keys[#keys + 1] = QL.ProfessionKey(p) end
	end
	return keys, known
end

local function fillPanel()
	local T, C = QL.Theme, QL.Theme.C
	-- tiles and headings are made once and reused
	panel.tiles = panel.tiles or {}
	panel.heads = panel.heads or {}
	for _, p in ipairs(panel.parts) do p:Hide() end
	panel.parts = {}
	local COLS, TILE_W, TILE_H = 6, 60, 50
	local y = -12
	for gi, g in ipairs(GROUPS) do
		local keys, known = {}, {}
		if g.key == "professions" then
			keys, known = professionKeys()
		else
			for _, s in ipairs(QL.SERVICES) do
				if s.group == g.key and s.key ~= "profTrainer" then keys[#keys + 1] = s.key end
			end
		end
		local head = panel.heads[gi]
		if not head then
			head = T.Text(panel, 11, C.muted, nil, true)
			panel.heads[gi] = head
		end
		head:ClearAllPoints()
		head:SetPoint("TOPLEFT", 12, y)
		head:SetText(L(g.label))
		head:Show()
		panel.parts[#panel.parts + 1] = head
		y = y - 18
		for i, key in ipairs(keys) do
			local b = panel.tiles[key]
			if not b then
				local isProf = key:sub(1, 5) == "prof:"
				local short = isProf and L(key:sub(6)) or (QL.SERVICE_BY_KEY[key] and L(QL.SERVICE_BY_KEY[key].label) or key)
				b = serviceButton(panel, key, 30, short)
				if isProf then b.icon:SetTexture(iconPath("book")) end
				b:SetSize(TILE_W, TILE_H)
				panel.tiles[key] = b
			end
			-- a known profession is lit in the accent
			b:SetActive(known[key:sub(6)] and true or false)
			local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", 8 + col * TILE_W, y - row * TILE_H)
			b:Show()
			panel.parts[#panel.parts + 1] = b
		end
		y = y - math.ceil(#keys / COLS) * TILE_H - 8
	end
	panel:SetSize(16 + COLS * TILE_W, -y + 4)
	panel:ClearAllPoints()
	panel:SetPoint("TOP", bar, "BOTTOM", 0, -6)
end

function QL.ToggleQuickPanel()
	if not bar then return end
	if not panel then buildPanel() end
	if panel:IsShown() then panel:Hide() else fillPanel(); panel:Show() end
end

-- The bar ---------------------------------------------------------------------------------------------

local function build()
	local T, C = QL.Theme, QL.Theme.C
	bar = CreateFrame("Frame", "QuestLineageQuickBar", UIParent)
	bar:SetFrameStrata("DIALOG")
	bar:SetClampedToScreen(true)
	bar:SetMovable(true)
	local SIZE, GAP, GRIP = 30, 2, 12
	local count = #PRIMARY + 1
	bar:SetSize(GRIP + 8 + count * (SIZE + GAP), SIZE + 8)
	local p = QL.DB().quickBarPoint
	if type(p) == "table" and p[1] then
		bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		bar:SetPoint("TOP", UIParent, "TOP", 0, -330)
	end
	T.Fill(bar, { 0.055, 0.063, 0.082, 0.88 })
	T.Border(bar, C.line)
	-- the grip: two columns of small dots on the left
	for row = 0, 2 do
		for col = 0, 1 do
			local d = bar:CreateTexture(nil, "ARTWORK")
			d:SetTexture(T.WHITE)
			d:SetSize(2, 2)
			d:SetPoint("LEFT", 5 + col * 4, (1 - row) * 5)
			d:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], 0.8)
		end
	end
	bar.buttons = {}
	for i, key in ipairs(PRIMARY) do
		local b = serviceButton(bar, key, SIZE)
		b:SetPoint("LEFT", GRIP + 4 + (i - 1) * (SIZE + GAP), 0)
		bar.buttons[i] = b
	end
	local more = QL.Theme.IconButton(bar, iconPath("more"), SIZE)
	more:SetPoint("LEFT", GRIP + 4 + #PRIMARY * (SIZE + GAP), 0)
	draggable(more)
	more:SetScript("OnClick", function() QL.ToggleQuickPanel() end)
	local enter, leave = more:GetScript("OnEnter"), more:GetScript("OnLeave")
	more:SetScript("OnEnter", function(self)
		enter(self)
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_BOTTOM")
		tip:AddLine(L("More: every trainer, vendor and service"), 1, 1, 1)
		tip:AddLine(L("Drag: move the bar"), 0.6, 0.6, 0.6)
		tip:Show()
	end)
	more:SetScript("OnLeave", function(self) leave(self); QL.Tip():Hide() end)
	bar.more = more
	-- its own place: drag it anywhere
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", startMove)
	bar:SetScript("OnDragStop", stopMove)
	bar:SetShown(QL.DB().quickBar ~= false)
end

function QL.ResetQuickBarPosition()
	QL.DB().quickBarPoint = nil
	if bar then
		bar:ClearAllPoints()
		bar:SetPoint("TOP", UIParent, "TOP", 0, -330)
	end
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
