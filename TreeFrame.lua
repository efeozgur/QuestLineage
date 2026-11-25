-- The chain window: one card per quest, laid out left (earlier) to right (later), with elbow
-- lines between them. Header: the focused quest and how much of its chain is done, a search box.
--   QL.Open(idOrText)   focus a quest by id or by a part of its name, and show the window
--   QL.ToggleWindow()
--   QL.FillQuestTooltip(tooltip, id, ctx)   the quest lines the cards (and Hooks.lua) show

local _, QL = ...

local W, H = 860, 520
local CARD_W, CARD_H = 190, 42
local GAP_X, GAP_Y, PAD = 56, 12, 16
local WHITE = "Interface\\Buttons\\WHITE8X8"

local STATUS = {
	done      = { 0.35, 0.80, 0.35, "Done" },
	ready     = { 1.00, 0.82, 0.20, "Ready to turn in" },
	active    = { 0.40, 0.70, 1.00, "In your log" },
	available = { 0.95, 0.95, 0.95, "Available" },
	toolow    = { 0.95, 0.55, 0.30, "Level too low" },
	locked    = { 0.55, 0.55, 0.55, "Locked" },
	closed    = { 0.85, 0.28, 0.28, "Closed" },
	other     = { 0.40, 0.40, 0.40, "Not for your character" },
}
QL.STATUS = STATUS

local EDGE = {
	all        = { 0.80, 0.80, 0.80, 0.9 },
	next       = { 0.80, 0.80, 0.80, 0.9 },
	child      = { 0.80, 0.80, 0.80, 0.9 },
	any        = { 1.00, 0.72, 0.25, 0.9 },
	parent     = { 0.45, 0.72, 1.00, 0.9 },
	breadcrumb = { 0.65, 0.65, 0.65, 0.6 },
}

local function L(s) return QL.L(s) end

local function hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

local function levelColor(level)
	if level and GetQuestDifficultyColor then
		local ok, c = pcall(GetQuestDifficultyColor, level)
		if ok and type(c) == "table" and c.r then return c.r, c.g, c.b end
	end
	return 1, 0.82, 0
end

local function titleList(ids)
	local out = {}
	for i, id in ipairs(ids) do
		if i > 4 then out[#out + 1] = "..."; break end
		out[#out + 1] = QL.QuestTitle(id)
	end
	return table.concat(out, ", ")
end

-- Tooltip ---------------------------------------------------------------------

function QL.FillQuestTooltip(tip, id, ctx)
	ctx = ctx or QL.Context()
	local level = QL.QuestLevel(id)
	local r, g, b = levelColor(level)
	tip:AddLine((level and ("[" .. level .. "] ") or "") .. QL.QuestTitle(id), r, g, b)
	local s = STATUS[QL.NodeStatus(id, ctx)]
	if s then tip:AddLine(L(s[4]), s[1], s[2], s[3]) end
	local obj = QL.QuestObjectives(id)
	if obj then tip:AddLine(obj, 1, 1, 1, true) end
	local giver, ender = QL.QuestGiver(id), QL.QuestEnder(id)
	if giver then tip:AddLine(L("Starts: ") .. giver, 0.75, 0.75, 0.75) end
	if ender then tip:AddLine(L("Ends: ") .. ender, 0.75, 0.75, 0.75) end
	local group = QL.Ids(QL.Q(id, "preQuestGroup"))
	if #group > 0 then tip:AddLine(L("Requires all of: ") .. titleList(group), 0.8, 0.8, 0.8, true) end
	local single = QL.Ids(QL.Q(id, "preQuestSingle"))
	if #single > 0 then tip:AddLine(L("Requires one of: ") .. titleList(single), 1, 0.75, 0.3, true) end
	local parent = QL.Ids(QL.Q(id, "parentQuest"))
	if #parent > 0 then tip:AddLine(L("Must be on: ") .. titleList(parent), 0.45, 0.72, 1, true) end
	local target = QL.Ids(QL.Q(id, "breadcrumbForQuestId"))
	if #target > 0 then tip:AddLine(L("Breadcrumb to: ") .. titleList(target), 0.7, 0.7, 0.7, true) end
	local closes = QL.Ids(QL.Q(id, "exclusiveTo"))
	if #closes > 0 then tip:AddLine(L("Taking it closes: ") .. titleList(closes), 1, 0.35, 0.35, true) end
end

-- Window ----------------------------------------------------------------------

local win
local focusId
local nodePool, linePool = {}, {}
local usedNodes, usedLines = 0, 0

local function savePoint(f)
	local point, _, relPoint, x, y = f:GetPoint(1)
	QL.DB().point = { point, relPoint, x, y }
end

local function border(f, r, g, b, a, size)
	f.edges = f.edges or {}
	local e = f.edges
	if #e == 0 then
		for i = 1, 4 do e[i] = f:CreateTexture(nil, "OVERLAY"); e[i]:SetTexture(WHITE) end
		e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT")
		e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT")
		e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT")
		e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT")
	end
	size = size or 1
	e[1]:SetHeight(size); e[2]:SetHeight(size); e[3]:SetWidth(size); e[4]:SetWidth(size)
	for i = 1, 4 do e[i]:SetVertexColor(r, g, b, a or 1) end
end

local function questLink(id)
	local level = QL.QuestLevel(id) or -1
	return ("|cffffff00|Hquest:%d:%d|h[%s]|h|r"):format(id, level, QL.QuestTitle(id))
end

local function insertLink(id)
	local link = questLink(id)
	if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
	if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
end

local function getNode()
	usedNodes = usedNodes + 1
	local n = nodePool[usedNodes]
	if n then n:Show(); return n end
	n = CreateFrame("Button", nil, win.canvas)
	n:SetSize(CARD_W, CARD_H)
	n.bg = n:CreateTexture(nil, "BACKGROUND")
	n.bg:SetTexture(WHITE)
	n.bg:SetAllPoints()
	n.stripe = n:CreateTexture(nil, "ARTWORK")
	n.stripe:SetTexture(WHITE)
	n.stripe:SetPoint("TOPLEFT"); n.stripe:SetPoint("BOTTOMLEFT")
	n.stripe:SetWidth(4)
	n.title = n:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	n.title:SetPoint("TOPLEFT", 10, -6)
	n.title:SetPoint("TOPRIGHT", -6, -6)
	n.title:SetJustifyH("LEFT")
	if n.title.SetWordWrap then n.title:SetWordWrap(false) end
	n.sub = n:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	n.sub:SetPoint("BOTTOMLEFT", 10, 6)
	n.sub:SetPoint("BOTTOMRIGHT", -6, 6)
	n.sub:SetJustifyH("LEFT")
	n:RegisterForClicks("LeftButtonUp")
	n:SetScript("OnEnter", function(self)
		self.bg:SetVertexColor(0.2, 0.24, 0.3, 0.98)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		QL.FillQuestTooltip(GameTooltip, self.questId)
		GameTooltip:AddLine(L("Click: center on it · Shift-click: link in chat"), 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end)
	n:SetScript("OnLeave", function(self)
		self.bg:SetVertexColor(unpack(self.bgColor))
		GameTooltip:Hide()
	end)
	n:SetScript("OnClick", function(self)
		if IsShiftKeyDown and IsShiftKeyDown() then insertLink(self.questId)
		else QL.Open(self.questId) end
	end)
	nodePool[usedNodes] = n
	return n
end

local function getLine()
	usedLines = usedLines + 1
	local t = linePool[usedLines]
	if not t then
		t = win.canvas:CreateTexture(nil, "BACKGROUND")
		t:SetTexture(WHITE)
		linePool[usedLines] = t
	end
	t:Show()
	return t
end

-- An axis-aligned segment, solid or dashed.
local function segment(x1, y1, x2, y2, color, dashed)
	local horizontal = (y1 == y2)
	local from, to = horizontal and math.min(x1, x2) or math.max(y1, y2), horizontal and math.max(x1, x2) or math.min(y1, y2)
	local length = horizontal and (to - from) or (from - to)
	if length <= 0 then return end
	local dash, gap = length, 0
	if dashed then dash, gap = 5, 4 end
	local pos = 0
	while pos < length do
		local len = math.min(dash, length - pos)
		local t = getLine()
		t:ClearAllPoints()
		t:SetVertexColor(color[1], color[2], color[3], color[4])
		if horizontal then
			t:SetSize(len, 2)
			t:SetPoint("TOPLEFT", win.canvas, "TOPLEFT", from + pos, y1 + 1)
		else
			t:SetSize(2, len)
			t:SetPoint("TOPLEFT", win.canvas, "TOPLEFT", x1 - 1, from - pos)
		end
		pos = pos + dash + gap
	end
end

local function cardPos(chain, node)
	local layerSize = #chain.layers[node.layer]
	local offset = (chain.height - layerSize) * (CARD_H + GAP_Y) / 2
	local x = PAD + (node.layer - 1) * (CARD_W + GAP_X)
	local y = -(PAD + offset + (node.row - 1) * (CARD_H + GAP_Y))
	return x, y
end

local function drawEdge(chain, e)
	local a, b = chain.nodes[e.from], chain.nodes[e.to]
	local ax, ay = cardPos(chain, a)
	local bx, by = cardPos(chain, b)
	local color = EDGE[e.kind] or EDGE.all
	if e.back then color = { 0.5, 0.5, 0.5, 0.4 } end
	local dashed = e.kind == "breadcrumb" or e.back
	local y1, y2 = ay - CARD_H / 2, by - CARD_H / 2
	local x1, x2 = ax + CARD_W, bx
	if x2 > x1 then
		local mid = x1 + GAP_X / 2
		segment(x1, y1, mid, y1, color, dashed)
		segment(mid, y1, mid, y2, color, dashed)
		segment(mid, y2, x2, y2, color, dashed)
		local dot = getLine()
		dot:ClearAllPoints()
		dot:SetVertexColor(color[1], color[2], color[3], 1)
		dot:SetSize(5, 5)
		dot:SetPoint("TOPLEFT", win.canvas, "TOPLEFT", x2 - 5, y2 + 2.5)
	else
		-- a back edge (a cycle): loop under the cards
		local low = math.min(y1, y2) - CARD_H / 2 - GAP_Y / 2
		segment(x1, y1, x1 + 8, y1, color, true)
		segment(x1 + 8, y1, x1 + 8, low, color, true)
		segment(x2 - 8, low, x1 + 8, low, color, true)
		segment(x2 - 8, low, x2 - 8, y2, color, true)
		segment(x2 - 8, y2, x2, y2, color, true)
	end
end

local function setMessage(text)
	win.message:SetText(text or "")
	win.message:SetShown(text ~= nil)
end

local function clear()
	for i = 1, usedNodes do nodePool[i]:Hide() end
	for i = 1, usedLines do linePool[i]:Hide() end
	usedNodes, usedLines = 0, 0
end

local function applyFonts()
	QL.SetFont(win.title, 15)
	QL.SetFont(win.sub, 11)
	QL.SetFont(win.message, 13)
	QL.SetFont(win.legend, 10)
	QL.SetFont(win.note, 10)
	QL.SetFont(win.searchHint, 11)
end

-- A coloured block drawn inline (|T escape with a vertex colour): the game font has no box glyphs.
local function swatch(c, w, h)
	return ("|T%s:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(WHITE, h, w, math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local function legendText()
	local function sw(kind, label)
		return swatch(EDGE[kind], 14, 2) .. " " .. L(label)
	end
	local parts = { sw("all", "requires"), sw("any", "one of"), sw("parent", "must be on"), sw("breadcrumb", "breadcrumb") }
	local states = {}
	for _, key in ipairs({ "done", "active", "ready", "available", "locked", "toolow", "closed" }) do
		local s = STATUS[key]
		states[#states + 1] = swatch(s, 8, 8) .. " " .. L(s[4])
	end
	return L("Legend: ") .. table.concat(parts, "   ") .. "     " .. table.concat(states, "  ")
end

local function scrollTo(x, y)
	local s = win.scroll
	local maxH = s:GetHorizontalScrollRange() or 0
	local maxV = s:GetVerticalScrollRange() or 0
	s:SetHorizontalScroll(math.max(0, math.min(maxH, x)))
	s:SetVerticalScroll(math.max(0, math.min(maxV, y)))
end

function QL.RenderWindow()
	if not win or not win:IsShown() then return end
	applyFonts()
	win.legend:SetText(legendText())
	win.searchHint:SetText(L("Search: quest name or id"))
	win.note:SetText("")
	clear()
	local state = QL.DataStatus()
	if state ~= "ok" then
		win.title:SetText(L("Quest Lineage"))
		win.sub:SetText("")
		setMessage(L("QuestieDB is missing: QuestLineage reads its quest data from it."))
		return
	end
	if not QL.IndexReady() then
		win.title:SetText(L("Quest Lineage"))
		win.sub:SetText("")
		setMessage(L("Building the chain index..."))
		QL.WhenIndexed(QL.RenderWindow)
		return
	end
	if not focusId then
		win.title:SetText(L("Quest Lineage"))
		win.sub:SetText("")
		setMessage(L("Search: quest name or id"))
		return
	end
	local ctx = QL.Context()
	local chain = QL.BuildChain(focusId, ctx)
	if not chain then
		setMessage(L("No quest found for: ") .. tostring(focusId))
		return
	end
	local r, g, b = levelColor(QL.QuestLevel(focusId))
	win.title:SetText(hex(r, g, b) .. QL.QuestTitle(focusId) .. "|r")
	win.sub:SetText(L("Quest chain") .. " · " .. L("%d/%d done"):format(chain.doneCount, chain.total))
	if chain.truncated then win.note:SetText(L("Showing the nearest %d quests of a larger web."):format(chain.total)) end
	setMessage(chain.total < 2 and L("This quest has no chain.") or nil)

	local cols = #chain.layers
	win.canvas:SetSize(PAD * 2 + cols * CARD_W + (cols - 1) * GAP_X, PAD * 2 + chain.height * CARD_H + (chain.height - 1) * GAP_Y)

	for _, e in ipairs(chain.edges) do drawEdge(chain, e) end
	local focusX, focusY = 0, 0
	for _, id in ipairs(chain.order) do
		local node = chain.nodes[id]
		local card = getNode()
		local x, y = cardPos(chain, node)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", win.canvas, "TOPLEFT", x, y)
		card.questId = id
		local s = STATUS[node.status] or STATUS.locked
		local dim = (node.status == "done" or node.status == "other" or node.status == "closed") and 0.55 or 1
		card.bgColor = id == focusId and { 0.16, 0.2, 0.27, 0.98 } or { 0.1, 0.11, 0.14, 0.95 }
		card.bg:SetVertexColor(unpack(card.bgColor))
		card.stripe:SetVertexColor(s[1], s[2], s[3], 1)
		if id == focusId then border(card, 1, 0.82, 0.2, 1, 2) else border(card, 0.25, 0.28, 0.33, 1, 1) end
		QL.SetFont(card.title, 11)
		QL.SetFont(card.sub, 10)
		card.title:SetText(QL.QuestTitle(id))
		card.title:SetTextColor(dim, dim, dim)
		local warn = #node.closes > 0 and ("  " .. hex(1, 0.35, 0.35) .. "(!)|r") or ""
		card.sub:SetText((node.level and (L("Lv %d"):format(node.level) .. " · ") or "") .. hex(s[1], s[2], s[3]) .. L(s[4]) .. "|r" .. warn)
		if id == focusId then focusX, focusY = x, -y end
	end
	local viewW, viewH = win.scroll:GetWidth() or W, win.scroll:GetHeight() or H
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			scrollTo(focusX + CARD_W / 2 - viewW / 2, focusY + CARD_H / 2 - viewH / 2)
		end)
	end
end

-- Search results under the box, when a name matches several quests.
local function showResults(ids)
	local list = win.results
	for _, b in ipairs(list.buttons) do b:Hide() end
	if #ids < 2 then list:Hide(); return end
	for i, id in ipairs(ids) do
		if i > 10 then break end
		local b = list.buttons[i]
		if not b then
			b = CreateFrame("Button", nil, list)
			b:SetSize(260, 18)
			b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 18)
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.text:SetPoint("LEFT", 4, 0)
			b.text:SetPoint("RIGHT", -4, 0)
			b.text:SetJustifyH("LEFT")
			b.hl = b:CreateTexture(nil, "HIGHLIGHT")
			b.hl:SetTexture(WHITE)
			b.hl:SetAllPoints()
			b.hl:SetVertexColor(1, 1, 1, 0.12)
			b:SetScript("OnClick", function(self)
				list:Hide()
				focusId = self.questId
				QL.RenderWindow()
			end)
			list.buttons[i] = b
		end
		b.questId = id
		QL.SetFont(b.text, 11)
		local level = QL.QuestLevel(id)
		b.text:SetText((level and ("[" .. level .. "] ") or "") .. QL.QuestTitle(id))
		b:Show()
	end
	list:SetHeight(8 + math.min(#ids, 10) * 18)
	list:Show()
end

local function createWindow()
	local f = CreateFrame("Frame", "QuestLineageFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	win = f
	f:SetSize(W, H)
	local p = QL.DB().point
	if type(p) == "table" and p[1] then
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		f:SetPoint("CENTER")
	end
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePoint(self) end)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		f:SetBackdropColor(0.05, 0.06, 0.08, 0.95)
		f:SetBackdropBorderColor(0.3, 0.45, 0.6, 0.9)
	else
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetTexture(WHITE); bg:SetAllPoints(); bg:SetVertexColor(0.05, 0.06, 0.08, 0.95)
	end
	if UISpecialFrames then table.insert(UISpecialFrames, "QuestLineageFrame") end

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", 16, -12)
	f.title:SetPoint("RIGHT", f, "RIGHT", -300, 0)
	f.title:SetJustifyH("LEFT")
	f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetSize(220, 20)
	box:SetPoint("TOPRIGHT", -40, -14)
	box:SetAutoFocus(false)
	f.searchHint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.searchHint:SetPoint("LEFT", 4, 0)
	box:SetScript("OnTextChanged", function(self) f.searchHint:SetShown(self:GetText() == "") end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		QL.Open(self:GetText())
	end)
	f.search = box

	local results = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
	results:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -2)
	results:SetSize(268, 30)
	results:SetFrameLevel(f:GetFrameLevel() + 20)
	if results.SetBackdrop then
		results:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		results:SetBackdropColor(0.08, 0.09, 0.12, 0.98)
		results:SetBackdropBorderColor(0.3, 0.45, 0.6, 0.9)
	end
	results.buttons = {}
	results:Hide()
	f.results = results

	local scroll = CreateFrame("ScrollFrame", nil, f)
	scroll:SetPoint("TOPLEFT", 10, -56)
	scroll:SetPoint("BOTTOMRIGHT", -10, 40)
	local canvas = CreateFrame("Frame", nil, scroll)
	canvas:SetSize(W, H)
	scroll:SetScrollChild(canvas)
	f.scroll, f.canvas = scroll, canvas

	-- wheel scrolls up/down, Shift+wheel left/right; dragging the background pans
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		if IsShiftKeyDown and IsShiftKeyDown() then
			scrollTo(self:GetHorizontalScroll() - delta * 60, self:GetVerticalScroll())
		else
			scrollTo(self:GetHorizontalScroll(), self:GetVerticalScroll() - delta * 40)
		end
	end)
	canvas:EnableMouse(true)
	canvas:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		local cx, cy = GetCursorPosition()
		local sx, sy = scroll:GetHorizontalScroll(), scroll:GetVerticalScroll()
		local scale = self:GetEffectiveScale()
		self:SetScript("OnUpdate", function()
			local nx, ny = GetCursorPosition()
			scrollTo(sx - (nx - cx) / scale, sy + (ny - cy) / scale)
		end)
	end)
	canvas:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	canvas:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

	f.message = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.message:SetPoint("CENTER", scroll, "CENTER")
	f.message:SetWidth(W - 120)

	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetTexture(WHITE)
	line:SetVertexColor(0.3, 0.45, 0.6, 0.5)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT", 10, 36)
	line:SetPoint("BOTTOMRIGHT", -10, 36)
	f.legend = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.legend:SetPoint("BOTTOMLEFT", 14, 14)
	f.legend:SetPoint("RIGHT", f, "RIGHT", -14, 0)
	f.legend:SetJustifyH("LEFT")
	f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.note:SetPoint("BOTTOMRIGHT", line, "TOPRIGHT", 0, 4)

	f:SetScript("OnShow", function() QL.RenderWindow() end)
	f:SetScript("OnHide", function() results:Hide() end)
	f:Hide()
end

local function ensureWindow()
	if not win and CreateFrame then createWindow() end
	return win
end

function QL.Open(arg)
	if not ensureWindow() then return end
	win.results:Hide()
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
	if not win:IsShown() then win:Show() end
	QL.WhenIndexed(function()
		local ids = QL.SearchQuests(text)
		if #ids == 0 then
			focusId = nil
			QL.RenderWindow()
			setMessage(L("No quest found for: ") .. text)
			return
		end
		focusId = ids[1]
		QL.RenderWindow()
		showResults(ids)
	end)
end

function QL.ToggleWindow()
	if not ensureWindow() then return end
	if win:IsShown() then win:Hide() else win:Show() end
end

-- Repaint after quest-log and setting changes, at most every half second.
local pending
local function schedule()
	if not win or not win:IsShown() or pending then return end
	pending = true
	if C_Timer and C_Timer.After then
		C_Timer.After(0.5, function() pending = nil; QL.RenderWindow() end)
	else
		pending = nil
		QL.RenderWindow()
	end
end
QL.On("STATE_CHANGED", schedule)
QL.On("SETTING_CHANGED", schedule)
