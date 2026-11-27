-- The family-tree canvas: the first quests of a chain on top, each generation below the one it
-- comes from, centred, joined by family-tree lines (a stem down from the earlier quest, a shared
-- bar, a drop onto each later one). A newly focused quest unfolds generation by generation.
--
--   local tree = QL.Tree.New(canvasFrame)
--   tree:Draw(chain, focusId, animate, minW, minH) -> focus card's x, y (canvas coordinates,
--                                         y down); the tree is centred in at least minW x minH
--   QL.CardPos(chain, node) -> x, y       a card's top-left (y negative, downward)
--   QL.CanvasSize(chain) -> w, h
--   QL.FillQuestTooltip(tooltip, id, ctx) the quest lines the cards (and Hooks.lua) show

local _, QL = ...

local CARD_W, CARD_H = 188, 66
local GAP_X, GAP_Y, PAD = 20, 50, 28
local UNFOLD_STEP, UNFOLD_TIME = 0.09, 0.24

QL.TREE_METRICS = { CARD_W = CARD_W, CARD_H = CARD_H, GAP_X = GAP_X, GAP_Y = GAP_Y, PAD = PAD }

local function L(s) return QL.L(s) end

local function levelColor(level)
	if level and GetQuestDifficultyColor then
		local ok, c = pcall(GetQuestDifficultyColor, level)
		if ok and type(c) == "table" and c.r then return c.r, c.g, c.b end
	end
	return 1, 0.82, 0
end
QL.LevelColor = levelColor

local function titleList(ids)
	local out = {}
	for i, id in ipairs(ids) do
		if i > 4 then out[#out + 1] = "..."; break end
		out[#out + 1] = QL.QuestTitle(id)
	end
	return table.concat(out, ", ")
end

-- Tooltip --------------------------------------------------------------------------

function QL.FillQuestTooltip(tip, id, ctx)
	local T = QL.Theme
	ctx = ctx or QL.Context()
	local level = QL.QuestLevel(id)
	local r, g, b = levelColor(level)
	tip:AddLine((level and ("[" .. level .. "] ") or "") .. QL.QuestTitle(id), r, g, b)
	local status = QL.NodeStatus(id, ctx)
	local s = T.STATUS[status]
	if s then tip:AddLine(QL.StatusLabel(id, status, ctx), s[1], s[2], s[3]) end
	local dkey, dc = QL.QuestDifficulty(level, ctx.level)
	if dc then tip:AddLine(L("Difficulty: ") .. L(dc[4]), dc[1], dc[2], dc[3]) end
	local dungeon = QL.QuestDungeon(id)
	if dungeon then
		local label = dungeon.kind == "raid" and L("Raid") or (dungeon.kind == "battleground" and L("Battleground") or L("Dungeon"))
		local c = T.C.accent2
		tip:AddLine(label .. ": " .. dungeon.name, c[1], c[2], c[3])
	end
	local xp, full = QL.QuestXPAt(id, ctx.level)
	if xp then
		local text = QL.L("Reward: ") .. QL.XPText(xp)
		if full and full ~= xp then text = text .. "  " .. QL.L("(full: %s)"):format(QL.FormatNumber(full)) end
		tip:AddLine(text, 0.24, 0.84, 0.78)
	end
	local obj = QL.QuestObjectives(id)
	if obj then tip:AddLine(obj, 1, 1, 1, true) end
	local giver, ender = QL.QuestGiver(id), QL.QuestEnder(id)
	if giver then tip:AddLine(L("Starts: ") .. giver, 0.75, 0.75, 0.75) end
	if ender then tip:AddLine(L("Ends: ") .. ender, 0.75, 0.75, 0.75) end
	local group = QL.Ids(QL.Q(id, "preQuestGroup"))
	if #group > 0 then tip:AddLine(L("Requires all of: ") .. titleList(group), 0.8, 0.8, 0.8, true) end
	local single = QL.Ids(QL.Q(id, "preQuestSingle"))
	if #single > 0 then tip:AddLine(L("Requires one of: ") .. titleList(single), 0.96, 0.62, 0.04, true) end
	local parent = QL.Ids(QL.Q(id, "parentQuest"))
	if #parent > 0 then tip:AddLine(L("Must be on: ") .. titleList(parent), 0.38, 0.65, 0.98, true) end
	local target = QL.Ids(QL.Q(id, "breadcrumbForQuestId"))
	if #target > 0 then tip:AddLine(L("Breadcrumb to: ") .. titleList(target), 0.7, 0.7, 0.7, true) end
	local closes = QL.Ids(QL.Q(id, "exclusiveTo"))
	if #closes > 0 then tip:AddLine(L("Taking it closes: ") .. titleList(closes), 0.97, 0.44, 0.44, true) end
end

-- Geometry -------------------------------------------------------------------------

local function cardPos(chain, node)
	local layerSize = #chain.layers[node.layer]
	local offset = (chain.height - layerSize) * (CARD_W + GAP_X) / 2
	local x = PAD + offset + (node.row - 1) * (CARD_W + GAP_X)
	local y = -(PAD + (node.layer - 1) * (CARD_H + GAP_Y))
	return x, y
end
QL.CardPos = cardPos

function QL.CanvasSize(chain)
	local cols, rows = chain.height, #chain.layers
	return PAD * 2 + cols * CARD_W + (cols - 1) * GAP_X, PAD * 2 + rows * CARD_H + (rows - 1) * GAP_Y
end

-- Links ------------------------------------------------------------------------------

local function questLink(id)
	local level = QL.QuestLevel(id) or -1
	return ("|cffffff00|Hquest:%d:%d|h[%s]|h|r"):format(id, level, QL.QuestTitle(id))
end

function QL.InsertQuestLink(id)
	local link = questLink(id)
	if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
	if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
end

-- The tree object ------------------------------------------------------------------

local Tree = {}
Tree.__index = Tree
QL.Tree = Tree

function Tree.New(canvas)
	local self = setmetatable({ canvas = canvas, cards = {}, lines = {}, usedCards = 0, usedLines = 0, gen = 1 }, Tree)
	self.unfolder = CreateFrame("Frame", nil, canvas)
	return self
end

function Tree:Clear()
	for i = 1, self.usedCards do self.cards[i]:Hide() end
	for i = 1, self.usedLines do self.lines[i]:Hide() end
	self.usedCards, self.usedLines = 0, 0
	self.unfolder:SetScript("OnUpdate", nil)
end

function Tree:Line()
	self.usedLines = self.usedLines + 1
	local t = self.lines[self.usedLines]
	if not t then
		t = self.canvas:CreateTexture(nil, "ARTWORK")
		t:SetTexture(QL.Theme.WHITE)
		self.lines[self.usedLines] = t
	end
	t.gen = self.gen
	t:SetAlpha(1)
	t:Show()
	return t
end

-- An axis-aligned segment, 2px, solid or dashed.
function Tree:Segment(x1, y1, x2, y2, c, dashed)
	local horizontal = (y1 == y2)
	local from = horizontal and math.min(x1, x2) or math.max(y1, y2)
	local length = horizontal and math.abs(x2 - x1) or math.abs(y2 - y1)
	if length <= 0 then return end
	local dash, gap = length, 0
	if dashed then dash, gap = 5, 4 end
	local pos = 0
	while pos < length do
		local len = math.min(dash, length - pos)
		local t = self:Line()
		t:ClearAllPoints()
		t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		if horizontal then
			t:SetSize(len, 2)
			t:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", from + pos, y1 + 1)
		else
			t:SetSize(2, len)
			t:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", x1 - 1, from - pos)
		end
		pos = pos + dash + gap
	end
end

-- A card's place on this canvas: the shared geometry, shifted to centre a narrow tree.
function Tree:Pos(chain, node)
	local x, y = cardPos(chain, node)
	return x + (self.ox or 0), y
end

function Tree:Edge(chain, e)
	local T = QL.Theme
	local a, b = chain.nodes[e.from], chain.nodes[e.to]
	local ax, ay = self:Pos(chain, a)
	local bx, by = self:Pos(chain, b)
	local c = T.EDGE[e.kind] or T.EDGE.all
	self.gen = b.layer
	if e.back then
		-- a cycle: a dashed loop round the right-hand side of both cards
		local grey = { T.C.dim[1], T.C.dim[2], T.C.dim[3], 0.5 }
		local y1, y2 = ay - CARD_H / 2, by - CARD_H / 2
		local side = math.max(ax, bx) + CARD_W + GAP_X / 2
		self:Segment(ax + CARD_W, y1, side, y1, grey, true)
		self:Segment(side, y1, side, y2, grey, true)
		self:Segment(bx + CARD_W, y2, side, y2, grey, true)
		return
	end
	local dashed = c[6]
	local px, cx = ax + CARD_W / 2, bx + CARD_W / 2
	local bottom, top = ay - CARD_H, by
	local bar = bottom - GAP_Y / 2
	self:Segment(px, bottom, px, bar, c, dashed)
	self:Segment(px, bar, cx, bar, c, dashed)
	self:Segment(cx, bar, cx, top, c, dashed)
	-- a small node where the line meets the card
	local dot = self:Line()
	dot:ClearAllPoints()
	dot:SetVertexColor(c[1], c[2], c[3], 1)
	dot:SetSize(6, 6)
	dot:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", cx - 3, top + 3)
end

function Tree:Card()
	local T, C = QL.Theme, QL.Theme.C
	self.usedCards = self.usedCards + 1
	local n = self.cards[self.usedCards]
	if n then n:Show(); return n end
	n = CreateFrame("Button", nil, self.canvas)
	n:SetSize(CARD_W, CARD_H)
	n.bg = T.Fill(n, C.card, "BACKGROUND", 1)
	T.Border(n, C.line)
	n.stripe = n:CreateTexture(nil, "ARTWORK")
	n.stripe:SetTexture(T.WHITE)
	n.stripe:SetPoint("TOPLEFT", 1, -1); n.stripe:SetPoint("BOTTOMLEFT", 1, 1)
	n.stripe:SetWidth(3)
	n.title = T.Text(n, 13, C.text, nil, true)
	n.title:SetPoint("TOPLEFT", 14, -10)
	n.title:SetPoint("TOPRIGHT", -24, -10)
	n.dot = n:CreateTexture(nil, "ARTWORK")
	n.dot:SetTexture(T.WHITE)
	n.dot:SetSize(6, 6)
	n.dot:SetPoint("TOPLEFT", 14, -31)
	n.status = T.Text(n, 11, C.muted)
	n.status:SetPoint("LEFT", n.dot, "RIGHT", 6, 0)
	n.level = T.Text(n, 11, C.dim)
	n.level:SetPoint("BOTTOMRIGHT", -10, 9)
	n.level:SetJustifyH("RIGHT")
	n.dist = T.Text(n, 12, C.text)
	n.dist:SetPoint("BOTTOMLEFT", 14, 9)
	n.tag = T.Text(n, 10, C.accent2, nil, true)
	n.tag:SetPoint("TOPRIGHT", -10, -30)
	n.tag:SetJustifyH("RIGHT")
	n.warn = CreateFrame("Frame", nil, n)
	n.warn:SetSize(16, 16)
	n.warn:SetPoint("TOPRIGHT", -6, -6)
	T.Fill(n.warn, { C.danger[1], C.danger[2], C.danger[3], 0.2 })
	n.warn.text = T.Text(n.warn, 11, C.danger)
	n.warn.text:SetPoint("CENTER", 0, 0)
	n.warn.text:SetJustifyH("CENTER")
	n.warn.text:SetText("!")
	n:RegisterForClicks("LeftButtonUp")
	n:SetScript("OnEnter", function(card)
		if not card.focused then T.Color(card.bg, C.cardHover) end
		local tip = QL.Tip()
		tip:SetOwner(card, "ANCHOR_RIGHT")
		QL.FillQuestTooltip(tip, card.questId)
		tip:AddLine(L("Click: center on it · Shift-click: link in chat"), 0.5, 0.5, 0.5)
		tip:Show()
	end)
	n:SetScript("OnLeave", function(card)
		T.Color(card.bg, card.focused and C.cardFocus or C.card)
		QL.Tip():Hide()
	end)
	n:SetScript("OnClick", function(card)
		if IsShiftKeyDown and IsShiftKeyDown() then QL.InsertQuestLink(card.questId)
		else
			-- a card points the arrow at its quest too
			if QL.SetArrowTarget and not (QL.RouteActive and QL.RouteActive()) then pcall(QL.SetArrowTarget, card.questId) end
			QL.Open(card.questId)
		end
	end)
	self.cards[self.usedCards] = n
	return n
end

-- Re-measure the cards' distances (the window calls this every second).
function Tree:RefreshDistances(ctx)
	if not QL.DistanceMarkup then return end
	for i = 1, self.usedCards do
		local card = self.cards[i]
		if card.distId then card.dist:SetText(QL.DistanceMarkup(card.distId, ctx) or "") end
	end
end

-- Unfolding: every card and line of generation g fades in UNFOLD_STEP * (g - 1) after the first.
function Tree:Unfold()
	local objects = {}
	for i = 1, self.usedCards do objects[#objects + 1] = self.cards[i] end
	for i = 1, self.usedLines do objects[#objects + 1] = self.lines[i] end
	for _, o in ipairs(objects) do o:SetAlpha(0) end
	local t = 0
	self.unfolder:SetScript("OnUpdate", function(frame, elapsed)
		t = t + (elapsed or 0.016)
		local busy = false
		for _, o in ipairs(objects) do
			local a = (t - ((o.gen or 1) - 1) * UNFOLD_STEP) / UNFOLD_TIME
			if a < 1 then busy = true end
			o:SetAlpha(math.max(0, math.min(1, a)))
		end
		if not busy then frame:SetScript("OnUpdate", nil) end
	end)
end

function Tree:Draw(chain, focusId, animate, minW, minH)
	local T, C = QL.Theme, QL.Theme.C
	local ctx = QL.Context()
	self:Clear()
	local w, h = QL.CanvasSize(chain)
	self.ox = math.max(0, ((minW or 0) - w) / 2)
	self.canvas:SetSize(math.max(w, minW or 0), math.max(h, minH or 0))
	for _, e in ipairs(chain.edges) do self:Edge(chain, e) end
	local fx, fy = 0, 0
	for _, id in ipairs(chain.order) do
		local node = chain.nodes[id]
		local card = self:Card()
		local x, y = self:Pos(chain, node)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", x, y)
		card:SetAlpha(1)
		card.gen = node.layer
		card.questId = id
		card.focused = (id == focusId)
		local s = T.STATUS[node.status] or T.STATUS.locked
		local faded = node.status == "done" or node.status == "other" or node.status == "closed"
		T.Color(card.bg, card.focused and C.cardFocus or C.card)
		T.Border(card, card.focused and C.accent or C.line)
		T.Glow(card, card.focused and C.accent or nil)
		card.stripe:SetVertexColor(s[1], s[2], s[3], 1)
		card.dot:SetVertexColor(s[1], s[2], s[3], 1)
		card.title:SetText(QL.QuestTitle(id))
		card.title:SetTextColor(unpack(faded and C.muted or (QL.TitleColor(id, ctx) or C.text)))
		card.tag:SetText(QL.DungeonMarkup(id, true) or "")
		card.status:SetText(QL.StatusLabel(id, node.status, ctx))
		card.status:SetTextColor(s[1], s[2], s[3], 1)
		local xp = QL.QuestXPAt(id, ctx and ctx.level)
		local lv = node.level and (faded and L("Lv %d"):format(node.level) or QL.LevelMarkup(id, ctx)) or ""
		if xp and not faded then lv = T.Hex(C.accent) .. QL.XPText(xp) .. "|r  " .. lv
		elseif xp then lv = QL.XPText(xp) .. "  " .. lv end
		card.level:SetText(lv)
		card.warn:SetShown(#node.closes > 0)
		-- how far: only for quests with somewhere to go now
		card.distId = QL.HasPlace and QL.HasPlace(node.status) and id or nil
		card.dist:SetText(card.distId and QL.DistanceMarkup and QL.DistanceMarkup(id, ctx) or "")
		if card.focused then fx, fy = x, -y end
	end
	if animate then self:Unfold() end
	return fx, fy
end
