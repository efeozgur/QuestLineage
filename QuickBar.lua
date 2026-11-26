-- "Where?" quick bar: a slim strip of service icons under the arrow, for asking the way without
-- opening the window. Click an icon: the arrow turns to the nearest such NPC (and the world map
-- draws it). Click it again within 10 seconds: the next nearest. Hover: the three nearest.
-- "⋯" opens a small panel with every category, grouped: trainers, professions (all of them, so a
-- trainer can be found before the profession is learnt; the known ones first and lit), vendors,
-- services.
--
-- Setting quickBar; the minimap button's Shift-click shows or hides it. The bar stands on its own:
-- drag it by its grip, its edge or any icon to put it anywhere (quickBarPoint). A small turn button at
-- its end (three squares that glide between a row and a column) lays the bar out horizontally or
-- vertically (setting quickBarVertical); tips and the "more" panel open on the side with room.
-- A padlock beside it pins the bar where it stands (setting quickBarLocked): no drag moves it then.

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

local function startMove()
	if bar and not QL.DB().quickBarLocked then bar:StartMoving() end
end
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

function QL.QuickBarVertical() return QL.DB().quickBarVertical == true end

local function showTip(owner, key)
	local tip = QL.Tip()
	if QL.QuickBarVertical() then tip:SetOwner(owner, "ANCHOR_SIDE", bar) else tip:SetOwner(owner, "ANCHOR_BOTTOM") end
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
	QL.PlaceQuickPanel()
end

-- Under a horizontal bar; beside a vertical one, on the side with more room.
function QL.PlaceQuickPanel()
	if not (panel and bar) then return end
	panel:ClearAllPoints()
	if not QL.QuickBarVertical() then
		panel:SetPoint("TOP", bar, "BOTTOM", 0, -6)
		return
	end
	local left = false
	local ok, cx = pcall(function() return (bar:GetCenter() or 0) * bar:GetEffectiveScale() end)
	local okU, sw = pcall(function() return UIParent:GetWidth() * UIParent:GetEffectiveScale() end)
	if ok and okU and type(cx) == "number" and type(sw) == "number" then left = cx > sw / 2 end
	if left then panel:SetPoint("TOPRIGHT", bar, "TOPLEFT", -6, 0) else panel:SetPoint("TOPLEFT", bar, "TOPRIGHT", 6, 0) end
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
	local p = QL.DB().quickBarPoint
	if type(p) == "table" and p[1] then
		bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		bar:SetPoint("TOP", UIParent, "TOP", 0, -330)
	end
	T.Fill(bar, { 0.055, 0.063, 0.082, 0.88 })
	T.Border(bar, C.line)
	-- the grip: small dots at the start (two columns of three; turned with the bar)
	bar.dots = {}
	for row = 0, 2 do
		for col = 0, 1 do
			local d = bar:CreateTexture(nil, "ARTWORK")
			d:SetTexture(T.WHITE)
			d:SetSize(2, 2)
			d:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], 0.8)
			bar.dots[#bar.dots + 1] = { tex = d, row = row, col = col }
		end
	end
	bar.buttons = {}
	for i, key in ipairs(PRIMARY) do
		bar.buttons[i] = serviceButton(bar, key, SIZE)
	end
	local more = QL.Theme.IconButton(bar, iconPath("more"), SIZE)
	draggable(more)
	more:SetScript("OnClick", function() QL.ToggleQuickPanel() end)
	local enter, leave = more:GetScript("OnEnter"), more:GetScript("OnLeave")
	more:SetScript("OnEnter", function(self)
		enter(self)
		local tip = QL.Tip()
		if QL.QuickBarVertical() then tip:SetOwner(self, "ANCHOR_SIDE", bar) else tip:SetOwner(self, "ANCHOR_BOTTOM") end
		tip:AddLine(L("More: every trainer, vendor and service"), 1, 1, 1)
		if not QL.DB().quickBarLocked then tip:AddLine(L("Drag: move the bar"), 0.6, 0.6, 0.6) end
		tip:Show()
	end)
	more:SetScript("OnLeave", function(self) leave(self); QL.Tip():Hide() end)
	bar.more = more
	-- the turn button: three squares that glide between a row and a column
	local turn = CreateFrame("Button", nil, bar)
	turn:SetSize(18, 18)
	turn.bg = T.Fill(turn, { 0, 0, 0, 0 })
	turn.sq = {}
	for i = 1, 3 do
		local s = turn:CreateTexture(nil, "OVERLAY")
		s:SetTexture(T.WHITE)
		s:SetSize(4, 4)
		s:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], 1)
		turn.sq[i] = s
	end
	turn.t = QL.QuickBarVertical() and 1 or 0
	turn.goal = turn.t
	turn:SetScript("OnEnter", function(self)
		T.Color(self.bg, C.rowHover)
		for _, s in ipairs(self.sq) do s:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1) end
		local tip = QL.Tip()
		if QL.QuickBarVertical() then tip:SetOwner(self, "ANCHOR_SIDE", bar) else tip:SetOwner(self, "ANCHOR_BOTTOM") end
		tip:AddLine(QL.QuickBarVertical() and L("Lay the bar out horizontally") or L("Lay the bar out vertically"), 1, 1, 1)
		tip:Show()
	end)
	turn:SetScript("OnLeave", function(self)
		T.Color(self.bg, { 0, 0, 0, 0 })
		for _, s in ipairs(self.sq) do s:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], 1) end
		QL.Tip():Hide()
	end)
	turn:SetScript("OnClick", function() QL.Set("quickBarVertical", not QL.QuickBarVertical()) end)
	turn:SetScript("OnUpdate", function(self, dt)
		if self.t == self.goal then return end
		local d = self.goal - self.t
		if math.abs(d) < 0.02 then self.t = self.goal else self.t = self.t + d * math.min(1, (dt or 0.016) * 14) end
		QL.PlaceTurnSquares()
	end)
	bar.turn = turn
	-- the padlock: a body and a shackle drawn from small squares; the accent while locked
	local lock = CreateFrame("Button", nil, bar)
	lock:SetSize(18, 18)
	lock.bg = T.Fill(lock, { 0, 0, 0, 0 })
	local function part(w, h)
		local s = lock:CreateTexture(nil, "OVERLAY")
		s:SetTexture(T.WHITE)
		s:SetSize(w, h)
		return s
	end
	lock.body = part(10, 7)
	lock.body:SetPoint("CENTER", lock, "CENTER", 0, -3)
	lock.left, lock.right, lock.top = part(2, 5), part(2, 5), part(6, 2)
	lock.parts = { lock.body, lock.left, lock.right, lock.top }
	lock:SetScript("OnEnter", function(self)
		T.Color(self.bg, C.rowHover)
		self.hover = true
		QL.PaintQuickLock()
		local tip = QL.Tip()
		if QL.QuickBarVertical() then tip:SetOwner(self, "ANCHOR_SIDE", bar) else tip:SetOwner(self, "ANCHOR_BOTTOM") end
		if QL.DB().quickBarLocked then
			tip:AddLine(L("Unlock the bar"), 1, 1, 1)
			tip:AddLine(L("Locked: it cannot be moved."), 0.6, 0.6, 0.6)
		else
			tip:AddLine(L("Lock the bar in place"), 1, 1, 1)
		end
		tip:Show()
	end)
	lock:SetScript("OnLeave", function(self)
		T.Color(self.bg, { 0, 0, 0, 0 })
		self.hover = false
		QL.PaintQuickLock()
		QL.Tip():Hide()
	end)
	lock:SetScript("OnClick", function() QL.Set("quickBarLocked", not QL.DB().quickBarLocked) end)
	bar.lock = lock
	QL.PaintQuickLock()
	QL.LayoutQuickBar()
	-- its own place: drag it anywhere
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", startMove)
	bar:SetScript("OnDragStop", stopMove)
	bar:SetShown(QL.DB().quickBar ~= false)
end

-- The padlock: shut and accent-coloured while locked, open (the shackle lifted off one side) while not.
function QL.PaintQuickLock()
	local lock = bar and bar.lock
	if not lock then return end
	local C = QL.Theme.C
	local locked = QL.DB().quickBarLocked and true or false
	local c = (locked or lock.hover) and C.accent or C.muted
	for _, p in ipairs(lock.parts) do p:SetVertexColor(c[1], c[2], c[3], 1) end
	local lift = locked and 0 or 2
	lock.left:ClearAllPoints()
	lock.left:SetPoint("BOTTOM", lock.body, "TOP", -2, 0 + lift)
	lock.right:ClearAllPoints()
	lock.right:SetPoint("BOTTOM", lock.body, "TOP", 2, 0 + lift)
	lock.right:SetShown(locked)
	lock.top:ClearAllPoints()
	lock.top:SetPoint("BOTTOM", lock.body, "TOP", 0, 3 + lift)
end

-- The squares of the turn button at the turn's progress t (0 = a row, 1 = a column).
function QL.PlaceTurnSquares()
	local turn = bar and bar.turn
	if not turn then return end
	for i, s in ipairs(turn.sq) do
		local k = (i - 2) * 5
		s:ClearAllPoints()
		s:SetPoint("CENTER", turn, "CENTER", k * (1 - turn.t), -k * turn.t)
	end
end

-- Places the grip, icons and turn button in a row or a column (setting quickBarVertical).
function QL.LayoutQuickBar()
	if not bar then return end
	local SIZE, GAP, GRIP, TURN = 30, 2, 12, 44
	local vertical = QL.QuickBarVertical()
	local count = #PRIMARY + 1
	local run = GRIP + 4 + count * (SIZE + GAP) -- along the bar, up to the turn button
	if vertical then bar:SetSize(SIZE + 8, run + TURN + 4) else bar:SetSize(run + TURN + 4, SIZE + 8) end
	for _, d in ipairs(bar.dots) do
		d.tex:ClearAllPoints()
		if vertical then
			d.tex:SetPoint("TOP", bar, "TOP", (1 - d.row) * 5, -(5 + d.col * 4))
		else
			d.tex:SetPoint("LEFT", bar, "LEFT", 5 + d.col * 4, (1 - d.row) * 5)
		end
	end
	local function put(frame, i)
		frame:ClearAllPoints()
		local off = GRIP + 4 + i * (SIZE + GAP)
		if vertical then frame:SetPoint("TOP", bar, "TOP", 0, -off) else frame:SetPoint("LEFT", bar, "LEFT", off, 0) end
	end
	for i, b in ipairs(bar.buttons) do put(b, i - 1) end
	put(bar.more, #PRIMARY)
	bar.turn:ClearAllPoints()
	bar.lock:ClearAllPoints()
	if vertical then
		bar.turn:SetPoint("TOP", bar, "TOP", 0, -(run + 2))
		bar.lock:SetPoint("TOP", bar, "TOP", 0, -(run + 22))
	else
		bar.turn:SetPoint("LEFT", bar, "LEFT", run + 2, 0)
		bar.lock:SetPoint("LEFT", bar, "LEFT", run + 22, 0)
	end
	bar.turn.goal = vertical and 1 or 0
	if not bar.turn.shown then bar.turn.t = bar.turn.goal; bar.turn.shown = true end
	QL.PlaceTurnSquares()
	QL.PlaceQuickPanel()
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
	if key == "quickBarLocked" and bar then QL.PaintQuickLock() end
	if key == "quickBarVertical" and bar then
		-- keep the corner where it was while the bar turns
		local left, top = bar:GetLeft(), bar:GetTop()
		QL.LayoutQuickBar()
		if left and top then
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
			local point, _, relPoint, x, y = bar:GetPoint(1)
			QL.DB().quickBarPoint = { point, relPoint, x, y }
		end
	end
	if key == "quickBar" and bar then
		bar:SetShown(QL.DB().quickBar ~= false)
		if panel and QL.DB().quickBar == false then panel:Hide() end
	end
end)
