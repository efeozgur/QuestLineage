-- The QuestLineage window.
--
--  ┌ header ─ logo · title ──────────────────────────────────────────────────── × ┐
--  │ rail │ list                │ chain: first quest  +XP ▬▬░ │ detail panel    │
--  │ ≡    │ Durotar             ├─────────────────────────────┤ (Inspector.lua) │
--  │ Görev│ 12 quests · 3 log   │                             │  3D giver       │
--  │ ∞    │ ▌quest row   +450   │  family tree (Tree.lua)     │  objective      │
--  │ Zinc.│  quest row   +300   │                             │  tasks, people  │
--  │ ◆    │  ...                ├─────────────────────────────┤  rewards, chain │
--  │ Sınıf│                     │ legend                      │  actions        │
--  │ ⌕ Ara│                     │                             │                 │
--  └──────┴─────────────────────┴─────────────────────────────┴─────────────────┘
--
-- The rail on the left picks the list: Quests (normal quests, most XP first), Chains (this zone),
-- Class (the character's class quests) and Search. "Chains" lists the chains that have a quest in the player's zone (Zone.lua), the ones in
-- progress first; it follows the player from zone to zone. "Search" finds quests by name or
-- id as you type. Picking either opens that quest's family tree in the middle and its details
-- on the right. Each part renders under pcall: an error is recorded (/ql errors) and flagged in
-- the header instead of stopping the rest of the window.
--
--   QL.Open(idOrText)  a quest id focuses it; text searches (Search tab) and focuses the best hit
--   QL.ToggleWindow(), QL.RenderWindow(), QL.ShowPage("zone" | "search")

local _, QL = ...

local W, H = 1320, 740
local HEADER_H, RAIL_W, SIDEBAR_W, INFO_H, LEGEND_H, INSPECTOR_W = 52, 64, 292, 76, 34, 344
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
	r.dist = T.Text(r, 13, C.text)
	r.dist:SetPoint("TOPRIGHT", r.chip, "BOTTOMRIGHT", 0, -5)
	r.dist:SetJustifyH("RIGHT")
	-- route tick box: filled when picked; shows the stop number while a route runs
	local ck = CreateFrame("Button", nil, r)
	ck:SetSize(18, 18)
	ck:SetPoint("TOPLEFT", 12, -10)
	ck.fill = T.Fill(ck, C.canvas)
	T.Border(ck, C.line)
	ck.num = T.Text(ck, 10, C.bg, nil, true)
	ck.num:SetPoint("CENTER", 0, 0)
	ck.num:SetJustifyH("CENTER")
	ck:SetScript("OnClick", function(self)
		local id = r.questId
		if id then QL.RouteSelect(id, not QL.RouteSelected(id)) end
	end)
	ck:SetScript("OnEnter", function(self)
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_RIGHT")
		tip:AddLine(L("Add to the route"), 1, 1, 1)
		tip:Show()
	end)
	ck:SetScript("OnLeave", function() QL.Tip():Hide() end)
	ck:Hide()
	r.check = ck
	r:SetScript("OnEnter", function(self)
		if not self.selected then T.Color(self.bg, C.rowHover) end
		if self.questId then
			local tip = QL.Tip()
			tip:SetOwner(self, "ANCHOR_RIGHT")
			QL.FillQuestTooltip(tip, self.questId)
			tip:Show()
		end
	end)
	r:SetScript("OnLeave", function(self)
		T.Color(self.bg, self.selected and C.rowActive or C.row)
		QL.Tip():Hide()
	end)
	r:SetScript("OnClick", function(self)
		if not self.openId then return end
		-- the Quests list also points the arrow at the quest
		if self.arrowOnClick and not (QL.RouteActive and QL.RouteActive()) then
			if QL.SetArrowTarget then
				local ok, err = pcall(QL.SetArrowTarget, self.openId)
				if not ok then QL.Debug("arrow: " .. tostring(err)); QL.Print(L("The arrow could not be built: /ql errors"), "error") end
			else
				QL.Print(L("The arrow is not loaded: quit the game fully and start it again (new files need a restart)."), "error")
			end
		end
		QL.Open(self.openId)
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

-- Chain rows (the Chains and Class pages): the chain's first quest, levels, done count, XP
-- still to earn, its state, the distance to the quest the row opens, and a progress bar.
-- rows = { { entry = QL.GroupChains entry, progress = QL.ChainProgress }, ... }
local function fillChainRows(list, rows, ctx)
	local T, C = QL.Theme, QL.Theme.C
	for _, r in ipairs(list.rows) do
		r.check:Hide()
		r.title:SetPoint("TOPLEFT", 18, -11)
	end
	for i, row in ipairs(rows) do
		local r = listRow(list, i, ZONE_ROW_H)
		r.arrowOnClick = true -- a chain row points the arrow at the quest it opens
		r.sub:SetPoint("RIGHT", r, "RIGHT", -86, 0)
		local e, p = row.entry, row.progress
		r.questId = e.head
		r.openId = p.focus
		-- the distance to the quest the row opens, unless the chain is done or nothing is open
		r.distId = (p.state ~= "done" and QL.HasPlace and QL.HasPlace(QL.NodeStatus(p.focus, ctx))) and p.focus or nil
		r.dist:SetText(r.distId and QL.DistanceMarkup(r.distId, ctx) or "")
		r.title:SetText(QL.QuestTitle(e.head))
		local levels = ""
		if e.minLevel then
			levels = (e.minLevel == e.maxLevel) and L("Lv %d"):format(e.minLevel) or L("Lv %d–%d"):format(e.minLevel, e.maxLevel)
			local _, dc = QL.QuestDifficulty(e.maxLevel, ctx.level)
			if dc then levels = T.Hex(dc) .. levels .. "|r" end
		end
		local xp = QL.ChainXP(e.ids, ctx)
		local xpText
		if p.state == "done" then
			xpText = xp.done > 0 and (T.Hex(C.muted) .. QL.XPText(xp.done) .. "|r") or nil
		elseif xp.remaining > 0 then
			xpText = T.Hex(C.accent) .. "+" .. QL.XPText(xp.remaining) .. "|r"
		end
		local dungeons = 0
		for _, id in ipairs(e.ids) do if QL.QuestDungeon(id) then dungeons = dungeons + 1 end end
		local dungeonText = dungeons > 0 and (T.Hex(C.accent2) .. L("Dungeon") .. (dungeons > 1 and (" ×" .. dungeons) or "") .. "|r") or nil
		r.sub:SetText(levels .. "  ·  " .. (dungeonText and (dungeonText .. "  ·  ") or "") .. L("%d/%d done"):format(p.done, p.total) .. (xpText and ("  ·  " .. xpText) or ""))
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
	fillChainRows(list, rows, ctx)
end

-- Sidebar: Search ---------------------------------------------------------------------------

-- Sidebar: Class (the character's class quests: chains and single quests; open ones first, by
-- level; completed ones last) ----------------------------------------------------------------

local function renderClass()
	local T, C = QL.Theme, QL.Theme.C
	local page = win.classPage
	local list = page.list
	local info = QL.PlayerClass()
	page.zone:SetText(info.name)
	page.zone:SetTextColor(info.color[1], info.color[2], info.color[3], 1)
	if info.coords and page.icon then
		page.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
		page.icon:SetTexCoord(info.coords[1], info.coords[2], info.coords[3], info.coords[4])
		page.icon:Show()
	elseif page.icon then
		page.icon:Hide()
	end
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
	local rows = {}
	for _, entry in ipairs(QL.ClassChains(ctx)) do
		rows[#rows + 1] = { entry = entry, progress = QL.ChainProgress(entry, ctx) }
	end
	table.sort(rows, function(a, b)
		local da, db = a.progress.state == "done", b.progress.state == "done"
		if da ~= db then return db end
		local la, lb = a.entry.minLevel or 0, b.entry.minLevel or 0
		if la ~= lb then return la < lb end
		return a.entry.head < b.entry.head
	end)
	local open, now, quests, xpLeft = 0, 0, 0, 0
	for _, row in ipairs(rows) do
		if row.progress.state ~= "done" then open = open + 1 end
		if row.progress.state == "available" or row.progress.state == "active" then now = now + 1 end
		quests = quests + row.entry.size
		xpLeft = xpLeft + QL.ChainXP(row.entry.ids, ctx).remaining
	end
	if #rows == 0 then
		page.sub:SetText(L("No class quests found for your class."))
	else
		local text = L("%d quests · %d open · %d to do now"):format(quests, open, now)
		if xpLeft > 0 then text = text .. "  ·  " .. T.Hex(C.accent) .. "+" .. QL.XPText(xpLeft) .. "|r" end
		page.sub:SetText(text)
	end
	fillChainRows(list, rows, ctx)
end

-- Sidebar: Quests (normal quests: the log, and what this zone offers now; most XP first) ------

local QUEST_ROW_H = 54

local function renderQuests()
	local T, C = QL.Theme, QL.Theme.C
	local page = win.questsPage
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
	local quests = QL.ZoneQuestList(area, ctx)
	local inLog, total = 0, 0
	for _, q in ipairs(quests) do
		if q.inLog then inLog = inLog + 1 end
		total = total + (q.xp or 0)
	end
	if #quests == 0 then
		page.sub:SetText(L("No quests to take here right now."))
	else
		page.sub:SetText(L("%d quests · %d in your log"):format(#quests, inLog) .. "  ·  " .. T.Hex(C.accent) .. QL.XPText(total) .. "|r")
	end
	for i, q in ipairs(quests) do
		local r = listRow(list, i, QUEST_ROW_H)
		r.questId, r.openId = q.id, q.id
		r.arrowOnClick = true
		r.check:Show()
		r.title:SetPoint("TOPLEFT", 40, -11)
		local picked = QL.RouteSelected(q.id)
		local stop = QL.RouteStop and QL.RouteStop(q.id)
		T.Color(r.check.fill, (stop or picked) and C.accent or C.canvas)
		T.Border(r.check, (stop or picked) and C.accent or C.line)
		r.check.num:SetText(stop and tostring(stop) or "")
		r.sub:SetPoint("RIGHT", r, "RIGHT", -86, 0)
		r.distId = q.id
		r.dist:SetText(QL.DistanceMarkup and QL.DistanceMarkup(q.id, ctx) or "")
		r.title:SetText(QL.QuestTitle(q.id))
		r.title:SetTextColor(unpack(QL.TitleColor(q.id, ctx) or C.text))
		local s = T.STATUS[q.status] or T.STATUS.available
		local level = QL.QuestLevel(q.id)
		local chain = QL.ChainSummary(q.id, ctx)
		local dungeon = QL.DungeonMarkup(q.id)
		r.sub:SetText((level and (QL.LevelMarkup(q.id, ctx) .. "  ·  ") or "") .. (dungeon and (dungeon .. "  ·  ") or "")
			.. T.Hex(s) .. L(s[4]) .. "|r"
			.. (chain and ("  ·  " .. L("Chain %d/%d"):format(chain.index, chain.total)) or ""))
		if q.xp then
			r.chip:SetText("+" .. QL.XPText(q.xp))
			r.chip:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
		else
			r.chip:SetText(L("no XP data"))
			r.chip:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 1)
		end
		if r.bar then r.bar:Hide() end
		selectRow(r, q.id == focusId)
		if QL.ArrowQuest and QL.ArrowQuest() == q.id then
			r.title:SetText(T.Hex(C.accent) .. "» |r" .. QL.QuestTitle(q.id))
		end
	end
	hideRows(list, #quests + 1)
	list:SetContentHeight(#quests * QUEST_ROW_H + 8)

	-- route footer
	local foot = page.foot
	local info = QL.RouteInfo and QL.RouteInfo()
	if info then
		foot.text:SetText(T.Hex(C.accent) .. L("Route %d/%d"):format(info.index, info.total) .. "|r  ·  " .. QL.QuestTitle(info.next))
		local d = QL.DistanceText and QL.DistanceText(info.next, ctx)
		foot.sub:SetText(L("The arrow leads stop by stop; the order is planned again as quests move on.") .. (d and ("  " .. d) or ""))
		foot.go:SetLabel(L("Stop route"))
		foot.go:SetActive(false)
		foot.clear:Hide()
	else
		local n = #QL.RouteSelection()
		if n == 0 then
			foot.text:SetText(L("Route"))
			foot.sub:SetText(L("Tick quests on the left to visit them nearest first."))
		else
			foot.text:SetText(L("%d quests ticked"):format(n))
			foot.sub:SetText(L("Ordered by distance, nearest first, from where you stand."))
		end
		foot.go:SetLabel(L("Build route"))
		foot.go:SetActive(n > 0)
		foot.go:SetEnabled(n > 0)
		foot.clear:SetLabel(L("Clear"))
		foot.clear:SetShown(n > 0)
	end
end

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
		r.arrowOnClick = true
		r.check:Hide()
		r.title:SetPoint("TOPLEFT", 18, -11)
		r.distId = nil
		r.dist:SetText("")
		r.sub:SetPoint("RIGHT", r, "RIGHT", -16, 0)
		r.questId, r.openId = id, id
		r.title:SetText(QL.QuestTitle(id))
		r.title:SetTextColor(unpack(QL.TitleColor(id, ctx) or C.text))
		local s = T.STATUS[QL.NodeStatus(id, ctx)] or T.STATUS.locked
		local level = QL.QuestLevel(id)
		local xp = QL.QuestXPAt(id, ctx.level)
		local dungeon = QL.DungeonMarkup(id, true)
		r.sub:SetText((level and (QL.LevelMarkup(id, ctx) .. "  ·  ") or "") .. (dungeon and (dungeon .. "  ·  ") or "") .. T.Hex(s) .. L(s[4]) .. "|r"
			.. (xp and ("  ·  " .. T.Hex(C.accent) .. QL.XPText(xp) .. "|r") or ""))
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
		win.inspector:Clear(L("No quest selected"), L("Its details show here."))
		return
	end
	local ctx = QL.Context()
	local chain = QL.BuildChain(focusId, ctx)
	if not chain then
		win.tree:Clear()
		setEmpty(L("No quest found."), "#" .. tostring(focusId))
		win.inspector:Clear(L("No quest found."), "#" .. tostring(focusId))
		return
	end
	setEmpty(nil)
	win.info:Show()
	-- the chain is named after its first quest (lowest level of the first generation)
	local head = chain.layers[1][1]
	for _, id in ipairs(chain.layers[1]) do
		if (QL.QuestLevel(id) or 0) < (QL.QuestLevel(head) or 0) then head = id end
	end
	win.infoTitle:SetText(QL.QuestTitle(head))
	win.infoLevel:SetText(L("Quest chain"))
	win.infoLevel:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
	local meta = L("%d quests · %d generations"):format(chain.total, #chain.layers) .. "  ·  " .. L("%d/%d done"):format(chain.doneCount, chain.total)
	if chain.truncated then meta = meta .. "  ·  " .. L("Showing the nearest %d quests of a larger web."):format(chain.total) end
	if chain.total < 2 then meta = L("This quest has no chain.") end
	win.infoMeta:SetText(meta)
	-- the chain's XP: what is left to earn at your level, and where it takes you
	local xp = QL.ChainXP(chain.order, ctx)
	local note = xp.unknown > 0 and ("  " .. T.Hex(C.dim) .. L("(%d without XP data)"):format(xp.unknown) .. "|r") or ""
	if xp.remaining > 0 then
		local gain = QL.LevelGain(xp.remaining)
		win.infoXPLabel:SetText(L("Chain completed:"))
		win.infoXP:SetText("+" .. QL.XPText(xp.remaining))
		win.infoXP:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
		win.infoGain:SetText(QL.GainText(gain) .. note)
		win.levelBar:Set(gain)
		win.levelBar:Show()
	elseif xp.done > 0 then
		win.infoXPLabel:SetText(L("Chain done, earned:"))
		win.infoXP:SetText(QL.XPText(xp.done))
		win.infoXP:SetTextColor(T.STATUS.done[1], T.STATUS.done[2], T.STATUS.done[3], 1)
		win.infoGain:SetText(note)
		win.levelBar:Hide()
	else
		win.infoXPLabel:SetText("")
		win.infoXP:SetText("")
		win.infoGain:SetText(xp.unknown > 0 and L("No XP data for this chain.") or "")
		win.levelBar:Hide()
	end

	local viewW, viewH = win.canvasScroll:GetWidth() or 600, win.canvasScroll:GetHeight() or 400
	local fx, fy = win.tree:Draw(chain, focusId, animate, viewW, viewH)
	local M = QL.TREE_METRICS
	scrollCanvas(fx + M.CARD_W / 2 - viewW / 2, fy - viewH / 3)
	win.inspector:Show(focusId, chain)
end

local function legendText()
	local T = QL.Theme
	local function swatch(c, w, h)
		return ("|T%s:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(T.WHITE, h, w, math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
	end
	local parts = {}
	for _, kind in ipairs({ "all", "any", "parent", "breadcrumb" }) do
		local c = T.EDGE[kind]
		parts[#parts + 1] = swatch(c, 16, 2) .. "  " .. L(c[5])
	end
	return table.concat(parts, "       ") .. "       " .. T.Hex(T.C.dim) .. L("Wheel: scroll · Shift+wheel: sideways · drag: pan") .. "|r"
end

-- Each part of the window renders on its own: one failing part is recorded and flagged, the
-- others still draw.
local function safe(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		QL.Debug(name .. ": " .. tostring(err))
		if win and win.errorFlag then
			win.errorFlag:SetText(L("Something went wrong: /ql errors"))
			win.errorFlag:Show()
		end
	end
	return ok
end

function QL.RenderWindow(animate)
	if not win or not win:IsShown() then return end
	local page = QL.DB().page or "quests"
	win.questsTab:SetLabel(L("Quests"))
	win.zoneTab:SetLabel(L("Chains"))
	win.classTab:SetLabel(L("Class"))
	win.searchTab:SetLabel(L("Search"))
	win.questsTab:SetActive(page == "quests")
	win.zoneTab:SetActive(page == "zone")
	win.classTab:SetActive(page == "class")
	win.searchTab:SetActive(page == "search")
	win.questsPage:SetShown(page == "quests")
	win.zonePage:SetShown(page == "zone")
	win.classPage:SetShown(page == "class")
	win.searchPage:SetShown(page == "search")
	win.headerSub:SetText(L("Quest chains"))
	local tr = QL.UseTurkish()
	win.langEN:SetActive(not tr)
	win.langTR:SetActive(tr)
	if not QL.HasWoWTR() then win.langTR.label:SetTextColor(0.4, 0.43, 0.49, 1) end
	win.legend:SetText(legendText())
	if page == "quests" then safe("quest list", renderQuests)
	elseif page == "zone" then safe("zone list", renderZone)
	elseif page == "class" then safe("class list", renderClass)
	else safe("search", renderSearch) end
	if animate == nil then animate = win.shownFocus ~= focusId end
	win.shownFocus = focusId
	safe("tree", renderMain, animate)
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
	local logo = T.Text(header, 17, C.text, nil, true)
	logo:SetPoint("LEFT", mark, "RIGHT", 10, 0)
	logo:SetText("QuestLineage")
	f.headerSub = T.Text(header, 12, C.dim)
	f.headerSub:SetPoint("LEFT", logo, "RIGHT", 12, -1)
	local close = T.CloseButton(f)
	close:SetPoint("TOPRIGHT", -10, -10)
	close:SetFrameLevel(header:GetFrameLevel() + 5)
	-- language switch: EN | TR (TR needs WoWTR; dimmed without it)
	local function langButton(code, label)
		local b = T.Button(header, 36, 24)
		b:SetLabel(label)
		b:SetFrameLevel(header:GetFrameLevel() + 5)
		b:SetScript("OnClick", function()
			if code == "tr" and not QL.HasWoWTR() then
				QL.Print(L("Turkish needs WoWTR; showing English until it is loaded."), "warn")
				return
			end
			QL.Set("lang", code)
			QL.RenderWindow(false)
		end)
		local enter = b:GetScript("OnEnter")
		b:SetScript("OnEnter", function(self)
			if enter then enter(self) end
			local tip = QL.Tip()
			tip:SetOwner(self, "ANCHOR_BOTTOM")
			tip:AddLine(code == "tr" and "Türkçe" or "English", 1, 1, 1)
			if code == "tr" and not QL.HasWoWTR() then tip:AddLine(L("Turkish needs WoWTR"), 0.97, 0.44, 0.44) end
			tip:Show()
		end)
		local leave = b:GetScript("OnLeave")
		b:SetScript("OnLeave", function(self)
			if leave then leave(self) end
			QL.Tip():Hide()
		end)
		return b
	end
	f.langTR = langButton("tr", "TR")
	f.langTR:SetPoint("RIGHT", close, "LEFT", -10, 0)
	f.langEN = langButton("en", "EN")
	f.langEN:SetPoint("RIGHT", f.langTR, "LEFT", -4, 0)
	f.errorFlag = T.Text(header, 11, C.danger)
	f.errorFlag:SetPoint("RIGHT", f.langEN, "LEFT", -12, 0)
	f.errorFlag:SetJustifyH("RIGHT")
	f.errorFlag:Hide()

	-- navigation rail: one icon button per list
	local rail = CreateFrame("Frame", nil, f)
	rail:SetPoint("TOPLEFT", 0, -HEADER_H)
	rail:SetPoint("BOTTOMLEFT")
	rail:SetWidth(RAIL_W)
	T.Fill(rail, C.header)
	T.Line(rail, C.line, "RIGHT")
	local MEDIA = "Interface\\AddOns\\QuestLineage\\Media\\"
	local y = -8
	for _, item in ipairs({
		{ "questsTab", "nav_quests", "quests" },
		{ "zoneTab", "nav_chains", "zone" },
		{ "classTab", "nav_class", "class" },
		{ "searchTab", "nav_search", "search" },
	}) do
		local b = T.RailButton(rail, MEDIA .. item[2], RAIL_W - 1, 62)
		b:SetPoint("TOPLEFT", 0, y)
		local key = item[3]
		b:SetScript("OnClick", function() QL.ShowPage(key) end)
		f[item[1]] = b
		y = y - 64
	end

	-- the list panel
	local side = CreateFrame("Frame", nil, f)
	side:SetPoint("TOPLEFT", RAIL_W, -HEADER_H)
	side:SetPoint("BOTTOMLEFT", RAIL_W, 0)
	side:SetWidth(SIDEBAR_W)
	T.Fill(side, C.sidebar)
	T.Line(side, C.line, "RIGHT")

	local function page()
		local pg = CreateFrame("Frame", nil, side)
		pg:SetPoint("TOPLEFT", 0, -10)
		pg:SetPoint("BOTTOMRIGHT", -1, 0)
		return pg
	end

	-- a zone page: zone name, a summary line, a scrolling list
	local function zonePage()
		local zp = page()
		zp.zone = T.Text(zp, 18, C.text, nil, true)
		zp.zone:SetPoint("TOPLEFT", 18, -8)
		zp.zone:SetPoint("RIGHT", zp, "RIGHT", -16, 0)
		zp.sub = T.Text(zp, 12, C.muted)
		zp.sub:SetPoint("TOPLEFT", zp.zone, "BOTTOMLEFT", 0, -6)
		zp.sub:SetPoint("RIGHT", zp, "RIGHT", -16, 0)
		zp.list = T.Scroll(zp)
		zp.list:SetPoint("TOPLEFT", 0, -62)
		zp.list:SetPoint("BOTTOMRIGHT", 0, 8)
		zp.list.rows = {}
		local sep = zp:CreateTexture(nil, "BORDER")
		sep:SetTexture(T.WHITE)
		sep:SetPoint("TOPLEFT", 16, -58); sep:SetPoint("TOPRIGHT", -16, -58)
		sep:SetHeight(1)
		T.Color(sep, C.lineSoft)
		return zp
	end
	f.questsPage = zonePage()
	do
		local qp = f.questsPage
		qp.list:SetPoint("BOTTOMRIGHT", 0, 96)
		local foot = CreateFrame("Frame", nil, qp)
		foot:SetPoint("BOTTOMLEFT"); foot:SetPoint("BOTTOMRIGHT")
		foot:SetHeight(92)
		T.Fill(foot, C.header)
		T.Line(foot, C.line, "TOP")
		foot.text = T.Text(foot, 12, C.text, nil, true)
		foot.text:SetPoint("TOPLEFT", 16, -12)
		foot.text:SetPoint("RIGHT", foot, "RIGHT", -16, 0)
		foot.sub = T.Text(foot, 11, C.muted)
		foot.sub:SetPoint("TOPLEFT", foot.text, "BOTTOMLEFT", 0, -4)
		foot.sub:SetPoint("RIGHT", foot, "RIGHT", -16, 0)
		foot.go = T.Button(foot, 150, 28)
		foot.go:SetPoint("BOTTOMLEFT", 16, 12)
		foot.clear = T.Button(foot, 100, 28)
		foot.clear:SetPoint("LEFT", foot.go, "RIGHT", 8, 0)
		foot.go:SetScript("OnClick", function()
			if QL.RouteActive() then QL.StopRoute() else QL.StartRoute() end
			QL.RenderWindow(false)
		end)
		foot.clear:SetScript("OnClick", function() QL.ClearRouteSelection() end)
		qp.foot = foot
	end
	f.zonePage = zonePage()
	-- the class page: the class's emblem beside its name
	local cp = zonePage()
	cp.icon = cp:CreateTexture(nil, "ARTWORK")
	cp.icon:SetSize(30, 30)
	cp.icon:SetPoint("TOPLEFT", 16, -6)
	cp.zone:ClearAllPoints()
	cp.zone:SetPoint("TOPLEFT", 54, -8)
	cp.zone:SetPoint("RIGHT", cp, "RIGHT", -16, 0)
	cp.sub:ClearAllPoints()
	cp.sub:SetPoint("TOPLEFT", 18, -40)
	cp.sub:SetPoint("RIGHT", cp, "RIGHT", -16, 0)
	f.classPage = cp

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
	main:SetPoint("TOPLEFT", RAIL_W + SIDEBAR_W, -HEADER_H)
	main:SetPoint("BOTTOMRIGHT", -INSPECTOR_W, 0)
	f.main = main

	-- detail panel
	f.inspector = QL.Inspector.New(f)
	f.inspector.frame:SetPoint("TOPRIGHT", 0, -HEADER_H)
	f.inspector.frame:SetPoint("BOTTOMRIGHT")
	f.inspector.frame:SetWidth(INSPECTOR_W)
	local info = CreateFrame("Frame", nil, main)
	info:SetPoint("TOPLEFT"); info:SetPoint("TOPRIGHT")
	info:SetHeight(INFO_H)
	T.Line(info, C.line, "BOTTOM")
	f.info = info
	f.infoLevel = T.Text(info, 11, C.accent)
	f.infoLevel:SetPoint("TOPLEFT", 26, -14)
	f.infoTitle = T.Text(info, 19, C.text, nil, true)
	f.infoTitle:SetPoint("TOPLEFT", f.infoLevel, "BOTTOMLEFT", 0, -5)
	f.infoTitle:SetPoint("RIGHT", info, "RIGHT", -270, 0)
	f.infoMeta = T.Text(info, 12, C.muted)
	f.infoMeta:SetPoint("TOPLEFT", f.infoTitle, "BOTTOMLEFT", 0, -5)
	f.infoMeta:SetPoint("RIGHT", info, "RIGHT", -270, 0)
	-- right: the chain's XP and its share of your level
	f.infoXP = T.Text(info, 21, C.accent, nil, true)
	f.infoXP:SetPoint("TOPRIGHT", -26, -12)
	f.infoXP:SetJustifyH("RIGHT")
	f.infoXPLabel = T.Text(info, 11, C.muted)
	f.infoXPLabel:SetPoint("RIGHT", f.infoXP, "LEFT", -8, -2)
	f.infoXPLabel:SetJustifyH("RIGHT")
	f.infoGain = T.Text(info, 11, C.muted)
	f.infoGain:SetPoint("TOPRIGHT", -26, -40)
	f.infoGain:SetJustifyH("RIGHT")
	f.levelBar = T.LevelBar(info, 5)
	f.levelBar:SetWidth(220)
	f.levelBar:SetPoint("TOPRIGHT", -26, -58)

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
	f.emptyTitle = T.Text(empty, 18, C.text, nil, true)
	f.emptyTitle:SetPoint("TOP", ring, "BOTTOM", 0, -18)
	f.emptyTitle:SetJustifyH("CENTER")
	f.emptySub = T.Text(empty, 12, C.muted)
	f.emptySub:SetPoint("TOP", f.emptyTitle, "BOTTOM", 0, -8)
	f.emptySub:SetJustifyH("CENTER")

	f:SetScript("OnShow", function() f.errorFlag:Hide(); QL.RenderWindow() end)
	local since = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		since = since + (elapsed or 0)
		if since < 1 then return end
		since = 0
		local ok, err = pcall(QL.RefreshDistances)
		if not ok then QL.Debug("distances: " .. tostring(err)) end
	end)
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

-- The distances on the Quests list and in the detail panel, re-measured as you move.
function QL.RefreshDistances()
	if not win or not win:IsShown() or not QL.DistanceText then return end
	local ctx = QL.Context()
	for _, page in ipairs({ win.questsPage, win.zonePage }) do
		if page:IsShown() then
			for _, r in ipairs(page.list.rows) do
				if r:IsShown() and r.distId then
					r.dist:SetText(QL.DistanceMarkup(r.distId, ctx) or "")
				end
			end
		end
	end
	if win.tree and win.tree.RefreshDistances then win.tree:RefreshDistances(ctx) end
	if focusId and win.inspector and win.inspector.hero.dist then
		win.inspector.hero.dist:SetText(QL.DistanceMarkup(focusId, ctx, 13) or "")
	end
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
QL.On("ARROW_CHANGED", schedule)
QL.On("ROUTE_CHANGED", schedule)
QL.Event("ZONE_CHANGED_NEW_AREA", schedule)
QL.Event("PLAYER_ENTERING_WORLD", schedule)
