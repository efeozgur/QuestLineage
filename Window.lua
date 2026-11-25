-- The QuestLineage window.
--
--  ┌ header ─ logo · title ───────────────────────────────────────── × ┐
--  │ sidebar             │ focused quest        3 of 8 done  ▬▬▬▬░░░  │
--  │ [This zone][Search] ├──────────────────────────────────────────────┤
--  │ Durotar             │                                              │
--  │ 6 chains            │           family tree (Tree.lua)             │
--  │ ▌chain row  ▬▬▬░░   │                                              │
--  │  chain row  ▬░░░░   ├──────────────────────────────────────────────┤
--  │  ...                │ legend                                       │
--  └─────────────────────┴──────────────────────────────────────────────┘
--
-- "This zone" lists the chains that have a quest in the player's zone (Zone.lua), the ones in
-- progress first; it follows the player from zone to zone. "Search" finds quests by name or
-- id as you type. Picking either opens that quest's family tree on the right.
--
--   QL.Open(idOrText)  a quest id focuses it; text searches (Search tab) and focuses the best hit
--   QL.ToggleWindow(), QL.RenderWindow(), QL.ShowPage("zone" | "search")

local _, QL = ...

local W, H = 1060, 660
local HEADER_H, SIDEBAR_W, INFO_H, LEGEND_H = 52, 304, 76, 36
local ZONE_ROW_H, SEARCH_ROW_H = 66, 50

local win
local focusId

local function L(s) return QL.L(s) end

local CHAIN_STATE = {
	active    = { "In progress", "active" },
	available = { "Available", "available" },
	toolow    = { "Level too low", "toolow" },
	locked    = { "Locked", "locked" },
	done      = { "Completed", "done" },
}

-- Rows ---------------------------------------------------------------------------------

local function newRow(list, height)
	local T, C = QL.Theme, QL.Theme.C
	local r = CreateFrame("Button", nil, list.child)
	r:SetHeight(height)
	r.bg = T.Fill(r, C.row)
	r.mark = r:CreateTexture(nil, "ARTWORK")
	r.mark:SetTexture(T.WHITE)
	r.mark:SetPoint("TOPLEFT"); r.mark:SetPoint("BOTTOMLEFT")
	r.mark:SetWidth(3)
	T.Color(r.mark, C.accent)
	r.sep = r:CreateTexture(nil, "BORDER")
	r.sep:SetTexture(T.WHITE)
	r.sep:SetPoint("BOTTOMLEFT", 16, 0); r.sep:SetPoint("BOTTOMRIGHT", -16, 0)
	r.sep:SetHeight(1)
	T.Color(r.sep, C.lineSoft)
	r.title = T.Text(r, 13, C.text)
	r.title:SetPoint("TOPLEFT", 18, -11)
	r.title:SetPoint("TOPRIGHT", -92, -11)
	r.sub = T.Text(r, 11, C.muted)
	r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -5)
	r.sub:SetPoint("RIGHT", r, "RIGHT", -16, 0)
	r.chip = T.Text(r, 11, C.muted)
	r.chip:SetPoint("TOPRIGHT", -16, -12)
	r.chip:SetJustifyH("RIGHT")
	r:SetScript("OnEnter", function(self)
		if not self.selected then T.Color(self.bg, C.rowHover) end
		if self.questId then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			QL.FillQuestTooltip(GameTooltip, self.questId)
			GameTooltip:Show()
		end
	end)
	r:SetScript("OnLeave", function(self)
		T.Color(self.bg, self.selected and C.rowActive or C.row)
		GameTooltip:Hide()
	end)
	r:SetScript("OnClick", function(self)
		if self.openId then QL.Open(self.openId) end
	end)
	return r
end

local function listRow(list, i, height)
	local r = list.rows[i]
	if not r then
		r = newRow(list, height)
		list.rows[i] = r
	end
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", list.child, "TOPLEFT", 0, -(i - 1) * height)
	r:SetPoint("RIGHT", list, "RIGHT", 0, 0)
	r:Show()
	return r
end

local function hideRows(list, from)
	for i = from, #list.rows do list.rows[i]:Hide() end
end

local function selectRow(r, on)
	local T, C = QL.Theme, QL.Theme.C
	r.selected = on
	T.Color(r.bg, on and C.rowActive or C.row)
	r.mark:SetShown(on)
end

-- Sidebar: This zone ----------------------------------------------------------------------

local function renderZone()
	local T, C = QL.Theme, QL.Theme.C
	local page = win.zonePage
	local list = page.list
	local area, _, name = QL.PlayerZone()
	page.zone:SetText(name or L("Unknown zone"))
	if QL.DataStatus() ~= "ok" then
		page.sub:SetText(L("QuestieDB is missing."))
		hideRows(list, 1)
		return
	end
	if not QL.IndexReady() then
		page.sub:SetText(L("Building the chain index..."))
		hideRows(list, 1)
		QL.WhenIndexed(QL.RenderWindow)
		return
	end
	local ctx = QL.Context()
	local chains = area and QL.ZoneChains(area, ctx) or {}
	local rows = {}
	for _, entry in ipairs(chains) do
		rows[#rows + 1] = { entry = entry, progress = QL.ChainProgress(entry, ctx) }
	end
	local order = QL.CHAIN_STATE_ORDER
	table.sort(rows, function(a, b)
		local sa, sb = order[a.progress.state] or 9, order[b.progress.state] or 9
		if sa ~= sb then return sa < sb end
		local la, lb = a.entry.minLevel or 0, b.entry.minLevel or 0
		if la ~= lb then return la < lb end
		return a.entry.head < b.entry.head
	end)
	local open, quests = 0, 0
	for _, row in ipairs(rows) do
		if row.progress.state ~= "done" then open = open + 1 end
		quests = quests + row.entry.size
	end
	if not area then
		page.sub:SetText(L("No quest data for this zone."))
	elseif #rows == 0 then
		page.sub:SetText(L("No quest chains in this zone."))
	else
		page.sub:SetText(L("%d chains · %d open · %d quests"):format(#rows, open, quests))
	end
	for i, row in ipairs(rows) do
		local r = listRow(list, i, ZONE_ROW_H)
		local e, p = row.entry, row.progress
		r.questId = e.head
		r.openId = p.focus
		r.title:SetText(QL.QuestTitle(e.head))
		local levels = ""
		if e.minLevel then
			levels = (e.minLevel == e.maxLevel) and L("Lv %d"):format(e.minLevel) or L("Lv %d–%d"):format(e.minLevel, e.maxLevel)
		end
		r.sub:SetText(levels .. "  ·  " .. L("%d quests"):format(e.size) .. "  ·  " .. L("%d/%d done"):format(p.done, p.total))
		local st = CHAIN_STATE[p.state] or CHAIN_STATE.locked
		local sc = T.STATUS[st[2]]
		r.chip:SetText(L(st[1]))
		r.chip:SetTextColor(sc[1], sc[2], sc[3], 1)
		r.title:SetTextColor(unpack(p.state == "done" and C.muted or C.text))
		if not r.bar then
			r.bar = T.Bar(r, 3)
			r.bar:SetPoint("BOTTOMLEFT", 18, 12)
			r.bar:SetPoint("BOTTOMRIGHT", -16, 12)
		end
		r.bar:SetValue(p.done / p.total, p.state == "done" and T.STATUS.done or nil)
		r.bar:Show()
		local on = false
		if focusId then
			for _, id in ipairs(e.ids) do if id == focusId then on = true; break end end
		end
		selectRow(r, on)
	end
	hideRows(list, #rows + 1)
	list:SetContentHeight(#rows * ZONE_ROW_H + 8)
end

-- Sidebar: Search ---------------------------------------------------------------------------

local function renderSearch()
	local T, C = QL.Theme, QL.Theme.C
	local page = win.searchPage
	local list = page.list
	local text = (page.input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
	page.input.hint:SetShown(text == "")
	page.input:SetPlaceholder(L("Quest name or id"))
	if QL.DataStatus() ~= "ok" then
		page.sub:SetText(L("QuestieDB is missing."))
		hideRows(list, 1)
		return
	end
	if not QL.IndexReady() then
		page.sub:SetText(L("Building the chain index..."))
		hideRows(list, 1)
		QL.WhenIndexed(QL.RenderWindow)
		return
	end
	if text == "" or (#text < 2 and not tonumber(text)) then
		page.sub:SetText(L("Type at least two letters."))
		hideRows(list, 1)
		list:SetContentHeight(0)
		return
	end
	local ids = QL.SearchQuests(text)
	page.sub:SetText(#ids == 0 and L("No quest found.") or L("%d quests found"):format(#ids))
	local ctx = QL.Context()
	for i, id in ipairs(ids) do
		local r = listRow(list, i, SEARCH_ROW_H)
		r.questId, r.openId = id, id
		r.title:SetText(QL.QuestTitle(id))
		r.title:SetTextColor(unpack(C.text))
		local s = T.STATUS[QL.NodeStatus(id, ctx)] or T.STATUS.locked
		local level = QL.QuestLevel(id)
		r.sub:SetText((level and (L("Lv %d"):format(level) .. "  ·  ") or "") .. T.Hex(s) .. L(s[4]) .. "|r")
		r.chip:SetText("#" .. id)
		r.chip:SetTextColor(unpack(C.dim))
		if r.bar then r.bar:Hide() end
		selectRow(r, id == focusId)
	end
	hideRows(list, #ids + 1)
	list:SetContentHeight(#ids * SEARCH_ROW_H + 8)
end

-- Main: the tree ----------------------------------------------------------------------------

local function setEmpty(title, sub)
	win.empty:SetShown(title ~= nil)
	win.emptyTitle:SetText(title or "")
	win.emptySub:SetText(sub or "")
end

local function scrollCanvas(x, y)
	local s = win.canvasScroll
	local maxH = math.max(0, (win.canvas:GetWidth() or 0) - (s:GetWidth() or 0))
	local maxV = math.max(0, (win.canvas:GetHeight() or 0) - (s:GetHeight() or 0))
	s:SetHorizontalScroll(math.max(0, math.min(maxH, x)))
	s:SetVerticalScroll(math.max(0, math.min(maxV, y)))
end

local function renderMain(animate)
	local T, C = QL.Theme, QL.Theme.C
	win.info:SetShown(false)
	if QL.DataStatus() ~= "ok" then
		win.tree:Clear()
		setEmpty(L("QuestieDB is missing"), L("QuestLineage reads its quest data from the QuestieDB addon."))
		return
	end
	if not QL.IndexReady() then
		win.tree:Clear()
		setEmpty(L("Building the chain index..."), L("This takes a few seconds once per session."))
		return
	end
	if not focusId then
		win.tree:Clear()
		setEmpty(L("Pick a quest chain"), L("Choose one from this zone on the left, or search for any quest."))
		return
	end
	local ctx = QL.Context()
	local chain = QL.BuildChain(focusId, ctx)
	if not chain then
		win.tree:Clear()
		setEmpty(L("No quest found."), "#" .. tostring(focusId))
		return
	end
	setEmpty(nil)
	win.info:Show()
	local r, g, b = QL.LevelColor(QL.QuestLevel(focusId))
	win.infoTitle:SetText(QL.QuestTitle(focusId))
	win.infoLevel:SetText(QL.QuestLevel(focusId) and L("Level %d"):format(QL.QuestLevel(focusId)) or "")
	win.infoLevel:SetTextColor(r, g, b, 1)
	local meta = L("%d quests · %d generations"):format(chain.total, #chain.layers)
	if chain.truncated then meta = meta .. "  ·  " .. L("Showing the nearest %d quests of a larger web."):format(chain.total) end
	if chain.total < 2 then meta = L("This quest has no chain.") end
	win.infoMeta:SetText(meta)
	local frac = chain.doneCount / math.max(1, chain.total)
	win.infoPct:SetText(("%d%%"):format(math.floor(frac * 100 + 0.5)))
	win.infoDone:SetText(L("%d/%d done"):format(chain.doneCount, chain.total))
	win.infoBar:SetValue(frac, frac >= 1 and T.STATUS.done or nil)

	local viewW, viewH = win.canvasScroll:GetWidth() or 600, win.canvasScroll:GetHeight() or 400
	local fx, fy = win.tree:Draw(chain, focusId, animate, viewW, viewH)
	local M = QL.TREE_METRICS
	scrollCanvas(fx + M.CARD_W / 2 - viewW / 2, fy - viewH / 3)
end

local function legendText()
	local T = QL.Theme
	local function swatch(c, w, h)
		return ("|T%s:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(T.WHITE, h, w, math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
	end
	local parts = {}
	for _, kind in ipairs({ "all", "any", "parent", "breadcrumb" }) do
		local c = T.EDGE[kind]
		parts[#parts + 1] = swatch(c, 14, 2) .. "  " .. L(c[5])
	end
	local states = {}
	for _, key in ipairs({ "done", "active", "ready", "available", "toolow", "locked", "closed" }) do
		local s = T.STATUS[key]
		states[#states + 1] = swatch(s, 6, 6) .. " " .. L(s[4])
	end
	return table.concat(parts, "     ") .. "          " .. table.concat(states, "    ")
end

function QL.RenderWindow(animate)
	if not win or not win:IsShown() then return end
	local page = QL.DB().page or "zone"
	win.zoneTab:SetLabel(L("This zone"))
	win.searchTab:SetLabel(L("Search"))
	win.zoneTab:SetActive(page == "zone")
	win.searchTab:SetActive(page == "search")
	win.zonePage:SetShown(page == "zone")
	win.searchPage:SetShown(page == "search")
	win.headerSub:SetText(L("Quest chains"))
	win.legend:SetText(legendText())
	if page == "zone" then renderZone() else renderSearch() end
	if animate == nil then animate = win.shownFocus ~= focusId end
	win.shownFocus = focusId
	renderMain(animate)
end

function QL.ShowPage(page)
	QL.DB().page = page
	QL.RenderWindow(false)
	if page == "search" and win then win.searchPage.input:SetFocus() end
end

-- Building ------------------------------------------------------------------------------------

local function savePoint(f)
	local point, _, relPoint, x, y = f:GetPoint(1)
	QL.DB().point = { point, relPoint, x, y }
end

local function createWindow()
	local T, C = QL.Theme, QL.Theme.C
	local f = CreateFrame("Frame", "QuestLineageFrame", UIParent)
	win = f
	f:SetSize(W, H)
	local p = QL.DB().point
	if type(p) == "table" and p[1] then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER") end
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	T.Fill(f, C.bg)
	T.Border(f, C.line)
	if UISpecialFrames then table.insert(UISpecialFrames, "QuestLineageFrame") end

	-- header
	local header = CreateFrame("Frame", nil, f)
	header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER_H)
	T.Fill(header, C.header)
	local glowLine = header:CreateTexture(nil, "ARTWORK")
	glowLine:SetTexture(T.WHITE)
	glowLine:SetPoint("BOTTOMLEFT"); glowLine:SetPoint("BOTTOMRIGHT")
	glowLine:SetHeight(2)
	T.Gradient(glowLine, "HORIZONTAL", C.accent, C.accent2)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() f:StartMoving() end)
	header:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePoint(f) end)
	local mark = header:CreateTexture(nil, "ARTWORK")
	mark:SetTexture(T.WHITE)
	mark:SetSize(12, 12)
	mark:SetPoint("LEFT", 20, 0)
	T.Gradient(mark, "VERTICAL", C.accent2, C.accent)
	local logo = T.Text(header, 17, C.text)
	logo:SetPoint("LEFT", mark, "RIGHT", 10, 0)
	logo:SetText("QuestLineage")
	f.headerSub = T.Text(header, 12, C.dim)
	f.headerSub:SetPoint("LEFT", logo, "RIGHT", 12, -1)
	local close = T.CloseButton(f)
	close:SetPoint("TOPRIGHT", -10, -10)
	close:SetFrameLevel(header:GetFrameLevel() + 5)

	-- sidebar
	local side = CreateFrame("Frame", nil, f)
	side:SetPoint("TOPLEFT", 0, -HEADER_H)
	side:SetPoint("BOTTOMLEFT")
	side:SetWidth(SIDEBAR_W)
	T.Fill(side, C.sidebar)
	T.Line(side, C.line, "RIGHT")
	local tabW = (SIDEBAR_W - 32 - 8) / 2
	f.zoneTab = T.Button(side, tabW, 30)
	f.zoneTab:SetPoint("TOPLEFT", 16, -16)
	f.zoneTab:SetScript("OnClick", function() QL.ShowPage("zone") end)
	f.searchTab = T.Button(side, tabW, 30)
	f.searchTab:SetPoint("LEFT", f.zoneTab, "RIGHT", 8, 0)
	f.searchTab:SetScript("OnClick", function() QL.ShowPage("search") end)

	local function page()
		local pg = CreateFrame("Frame", nil, side)
		pg:SetPoint("TOPLEFT", 0, -58)
		pg:SetPoint("BOTTOMRIGHT", -1, 0)
		return pg
	end

	local zp = page()
	zp.zone = T.Text(zp, 18, C.text)
	zp.zone:SetPoint("TOPLEFT", 18, -8)
	zp.zone:SetPoint("RIGHT", zp, "RIGHT", -16, 0)
	zp.sub = T.Text(zp, 12, C.muted)
	zp.sub:SetPoint("TOPLEFT", zp.zone, "BOTTOMLEFT", 0, -6)
	zp.list = T.Scroll(zp)
	zp.list:SetPoint("TOPLEFT", 0, -62)
	zp.list:SetPoint("BOTTOMRIGHT", 0, 8)
	zp.list.rows = {}
	local sep = zp:CreateTexture(nil, "BORDER")
	sep:SetTexture(T.WHITE)
	sep:SetPoint("TOPLEFT", 16, -58); sep:SetPoint("TOPRIGHT", -16, -58)
	sep:SetHeight(1)
	T.Color(sep, C.lineSoft)
	f.zonePage = zp

	local sp = page()
	sp.input = T.Input(sp, SIDEBAR_W - 32, 34)
	sp.input:SetPoint("TOPLEFT", 16, -4)
	sp.sub = T.Text(sp, 12, C.muted)
	sp.sub:SetPoint("TOPLEFT", sp.input, "BOTTOMLEFT", 2, -10)
	sp.list = T.Scroll(sp)
	sp.list:SetPoint("TOPLEFT", 0, -72)
	sp.list:SetPoint("BOTTOMRIGHT", 0, 8)
	sp.list.rows = {}
	local pending
	sp.input:SetScript("OnTextChanged", function(self, user)
		self.hint:SetShown((self:GetText() or "") == "")
		if not user or pending then return end
		pending = true
		local run = function() pending = nil; if win:IsShown() then renderSearch() end end
		if C_Timer and C_Timer.After then C_Timer.After(0.25, run) else run() end
	end)
	sp.input:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		local ids = QL.SearchQuests(self:GetText())
		if ids[1] then QL.Open(ids[1]) end
	end)
	f.searchPage = sp

	-- main: info bar
	local main = CreateFrame("Frame", nil, f)
	main:SetPoint("TOPLEFT", SIDEBAR_W, -HEADER_H)
	main:SetPoint("BOTTOMRIGHT")
	f.main = main
	local info = CreateFrame("Frame", nil, main)
	info:SetPoint("TOPLEFT"); info:SetPoint("TOPRIGHT")
	info:SetHeight(INFO_H)
	T.Line(info, C.line, "BOTTOM")
	f.info = info
	f.infoTitle = T.Text(info, 20, C.text)
	f.infoTitle:SetPoint("TOPLEFT", 26, -16)
	f.infoTitle:SetPoint("RIGHT", info, "RIGHT", -250, 0)
	f.infoLevel = T.Text(info, 12, C.muted)
	f.infoLevel:SetPoint("TOPLEFT", f.infoTitle, "BOTTOMLEFT", 0, -8)
	f.infoMeta = T.Text(info, 12, C.muted)
	f.infoMeta:SetPoint("LEFT", f.infoLevel, "RIGHT", 14, 0)
	f.infoMeta:SetPoint("RIGHT", info, "RIGHT", -250, 0)
	f.infoPct = T.Text(info, 22, C.accent)
	f.infoPct:SetPoint("TOPRIGHT", -26, -14)
	f.infoPct:SetJustifyH("RIGHT")
	f.infoDone = T.Text(info, 11, C.muted)
	f.infoDone:SetPoint("RIGHT", f.infoPct, "LEFT", -10, -2)
	f.infoDone:SetJustifyH("RIGHT")
	f.infoBar = T.Bar(info, 4)
	f.infoBar:SetWidth(190)
	f.infoBar:SetPoint("TOPRIGHT", -26, -50)

	-- main: legend
	local legend = CreateFrame("Frame", nil, main)
	legend:SetPoint("BOTTOMLEFT"); legend:SetPoint("BOTTOMRIGHT")
	legend:SetHeight(LEGEND_H)
	T.Fill(legend, C.header)
	T.Line(legend, C.line, "TOP")
	f.legend = T.Text(legend, 11, C.muted)
	f.legend:SetPoint("LEFT", 22, 0)
	f.legend:SetPoint("RIGHT", legend, "RIGHT", -16, 0)

	-- main: the tree canvas, both ways scrollable, draggable
	local cs = CreateFrame("ScrollFrame", nil, main)
	cs:SetPoint("TOPLEFT", 0, -INFO_H - 1)
	cs:SetPoint("BOTTOMRIGHT", 0, LEGEND_H)
	T.Fill(cs, C.canvas)
	local canvas = CreateFrame("Frame", nil, cs)
	canvas:SetSize(600, 400)
	cs:SetScrollChild(canvas)
	f.canvasScroll, f.canvas = cs, canvas
	f.tree = QL.Tree.New(canvas)
	cs:EnableMouseWheel(true)
	cs:SetScript("OnMouseWheel", function(self, delta)
		if IsShiftKeyDown and IsShiftKeyDown() then
			scrollCanvas(self:GetHorizontalScroll() - delta * 80, self:GetVerticalScroll())
		else
			scrollCanvas(self:GetHorizontalScroll(), self:GetVerticalScroll() - delta * 60)
		end
	end)
	canvas:EnableMouse(true)
	canvas:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		local cx, cy = GetCursorPosition()
		local sx, sy = cs:GetHorizontalScroll(), cs:GetVerticalScroll()
		local scale = self:GetEffectiveScale()
		self:SetScript("OnUpdate", function()
			local nx, ny = GetCursorPosition()
			scrollCanvas(sx - (nx - cx) / scale, sy + (ny - cy) / scale)
		end)
	end)
	canvas:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	canvas:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

	-- main: empty state
	local empty = CreateFrame("Frame", nil, main)
	empty:SetPoint("TOPLEFT", cs, "TOPLEFT")
	empty:SetPoint("BOTTOMRIGHT", cs, "BOTTOMRIGHT")
	empty:SetFrameLevel(cs:GetFrameLevel() + 10)
	f.empty = empty
	local ring = empty:CreateTexture(nil, "ARTWORK")
	ring:SetTexture(T.WHITE)
	ring:SetSize(44, 44)
	ring:SetPoint("CENTER", 0, 46)
	T.Gradient(ring, "VERTICAL", { C.accent2[1], C.accent2[2], C.accent2[3], 0.35 }, { C.accent[1], C.accent[2], C.accent[3], 0.35 })
	f.emptyTitle = T.Text(empty, 18, C.text)
	f.emptyTitle:SetPoint("TOP", ring, "BOTTOM", 0, -18)
	f.emptyTitle:SetJustifyH("CENTER")
	f.emptySub = T.Text(empty, 12, C.muted)
	f.emptySub:SetPoint("TOP", f.emptyTitle, "BOTTOM", 0, -8)
	f.emptySub:SetJustifyH("CENTER")

	f:SetScript("OnShow", function() QL.RenderWindow() end)
	f:SetScript("OnHide", function() f.shownFocus = nil end)
	f:Hide()
end

local function ensureWindow()
	if not win and CreateFrame then createWindow() end
	return win
end

function QL.Open(arg)
	if not ensureWindow() then return end
	local id = tonumber(arg)
	if id then
		focusId = id
		if win:IsShown() then QL.RenderWindow() else win:Show() end
		return
	end
	local text = tostring(arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		if not win:IsShown() then win:Show() end
		return
	end
	QL.DB().page = "search"
	win.searchPage.input:SetText(text)
	if not win:IsShown() then win:Show() end
	QL.WhenIndexed(function()
		local ids = QL.SearchQuests(text)
		if ids[1] then focusId = ids[1] end
		QL.RenderWindow()
	end)
end

function QL.ToggleWindow()
	if not ensureWindow() then return end
	if win:IsShown() then win:Hide() else win:Show() end
end

-- Repaint after quest-log, zone and setting changes, at most every half second, without unfolding.
local pending
local function schedule()
	if not win or not win:IsShown() or pending then return end
	pending = true
	local run = function() pending = nil; QL.RenderWindow(false) end
	if C_Timer and C_Timer.After then C_Timer.After(0.5, run) else run() end
end
QL.On("STATE_CHANGED", schedule)
QL.On("SETTING_CHANGED", schedule)
QL.Event("ZONE_CHANGED_NEW_AREA", schedule)
QL.Event("PLAYER_ENTERING_WORLD", schedule)
