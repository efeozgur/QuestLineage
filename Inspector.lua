-- The detail panel on the right of the window: everything about the focused quest.
--
--   hero        the quest giver in 3D (PlayerModel, idle animation) over a soft gradient, the
--               title, level and state on top of it; an item or a question mark when the quest
--               starts from an object or an item
--   Objective   the objective text           Story    the quest text (WoWTR, or the log)
--   Tasks       live objectives with progress for a quest in the log, else the database's:
--               a frozen 3D portrait for a creature, the item's icon for an item
--   Start / Turn in   who, with a portrait, and where ("Durotar · 45.2, 63.1")
--   Rewards     XP, reputation, reward items as icon tiles (hover: the item's tooltip)
--   Chain       the quests before and after it; click one to open it
--   footer      Link in chat, Open in quest log
--
--   local insp = QL.Inspector.New(parent)   insp.frame is the panel
--   insp:Show(questId)  insp:Clear(hintTitle, hintText)

local _, QL = ...

local PAD = 18
local HERO_H = 214
local ROW_H = 44
local TILE = 38

local Inspector = {}
Inspector.__index = Inspector
QL.Inspector = Inspector

local function L(s) return QL.L(s) end

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON = {
	npc = "Interface\\Icons\\INV_Misc_Head_Human_01",
	object = "Interface\\Icons\\INV_Misc_Gear_01",
	rep = "Interface\\Icons\\INV_Misc_Note_01",
}
-- item quality colours (poor .. legendary)
local QUALITY = {
	[0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
	[4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}

-- 3D creature pictures ---------------------------------------------------------------------

local function newModel(parent)
	if not CreateFrame then return nil end
	local ok, model = pcall(CreateFrame, "PlayerModel", nil, parent)
	if not ok or not model then return nil end
	model.freeze = function()
		if model.SetAnimation then pcall(model.SetAnimation, model, 0, 0) end
		if model.FreezeAnimation then pcall(model.FreezeAnimation, model, 0, 0, 0) end
		if model.SetPaused then pcall(model.SetPaused, model, true) end
	end
	return model
end

-- Show a creature in a model; false when the client cannot.
local function setCreature(model, npcId, zoom, frozen)
	if not model or not npcId then return false end
	if model.npcId ~= npcId then
		model.npcId = npcId
		if model.ClearModel then pcall(model.ClearModel, model) end
		if not pcall(model.SetCreature, model, npcId) then model.npcId = nil; return false end
		-- portrait zoom 1 aims the camera at the head (as unit frame portraits do); a partial zoom
		-- aimed at the chest and cut heads off. The distance scale pulls back to show shoulders.
		if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 1) end
		if model.SetCamDistanceScale then pcall(model.SetCamDistanceScale, model, zoom or 1) end
		if model.SetPosition then pcall(model.SetPosition, model, 0, 0, 0) end
		if frozen then
			model.freeze()
			if model.HookScript and not model.qlHooked then
				model.qlHooked = true
				pcall(model.HookScript, model, "OnModelLoaded", function() if model.frozen then model.freeze() end end)
			end
		end
		model.frozen = frozen
	end
	model:Show()
	return true
end

-- Building blocks ---------------------------------------------------------------------------------

function Inspector.New(parent)
	local T, C = QL.Theme, QL.Theme.C
	local self = setmetatable({ pools = {}, used = {} }, Inspector)
	local f = CreateFrame("Frame", nil, parent)
	self.frame = f
	T.Fill(f, C.sidebar)
	T.Line(f, C.line, "LEFT")
	local scroll = T.Scroll(f)
	scroll:SetPoint("TOPLEFT", 1, 0)
	scroll:SetPoint("BOTTOMRIGHT", 0, 0)
	self.scroll = scroll
	self.content = scroll.child

	-- hero
	local hero = CreateFrame("Frame", nil, self.content)
	hero:SetHeight(HERO_H)
	hero:SetPoint("TOPLEFT"); hero:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
	-- a quiet night backdrop: the panel's own colour at the bottom, a deep muted indigo on top
	local bg = hero:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(T.WHITE); bg:SetAllPoints()
	T.Gradient(bg, "VERTICAL", C.sidebar, C.heroTop)
	local glow = hero:CreateTexture(nil, "BACKGROUND", nil, 1)
	glow:SetTexture(T.WHITE)
	glow:SetPoint("TOPLEFT"); glow:SetPoint("TOPRIGHT"); glow:SetHeight(HERO_H * 0.6)
	T.Gradient(glow, "VERTICAL", { C.accent[1], C.accent[2], C.accent[3], 0 }, { C.accent[1], C.accent[2], C.accent[3], 0.06 })
	hero.bg, hero.glow = bg, glow
	hero.icon = hero:CreateTexture(nil, "ARTWORK")
	hero.icon:SetSize(72, 72)
	hero.icon:SetPoint("CENTER", 0, 26)
	hero.iconRing = hero:CreateTexture(nil, "BORDER")
	hero.iconRing:SetTexture(T.WHITE)
	hero.iconRing:SetSize(80, 80)
	hero.iconRing:SetPoint("CENTER", hero.icon, "CENTER")
	T.Color(hero.iconRing, { 1, 1, 1, 0.08 })
	hero.model = newModel(hero)
	if hero.model then
		hero.model:SetPoint("TOPLEFT", 0, -8)
		hero.model:SetPoint("BOTTOMRIGHT", 0, 62)
	end
	local shade = hero:CreateTexture(nil, "OVERLAY", nil, 1)
	shade:SetTexture(T.WHITE)
	shade:SetPoint("BOTTOMLEFT"); shade:SetPoint("BOTTOMRIGHT"); shade:SetHeight(110)
	T.Gradient(shade, "VERTICAL", C.sidebar, { C.sidebar[1], C.sidebar[2], C.sidebar[3], 0 })
	hero.shade = shade
	local overlay = CreateFrame("Frame", nil, hero)
	overlay:SetAllPoints()
	overlay:SetFrameLevel((hero.model and hero.model:GetFrameLevel() or hero:GetFrameLevel()) + 5)
	hero.title = T.Text(overlay, 20, C.text, nil, true)
	if hero.title.SetWordWrap then hero.title:SetWordWrap(true) end
	hero.title:SetPoint("BOTTOMLEFT", PAD, 40)
	hero.title:SetPoint("RIGHT", overlay, "RIGHT", -PAD, 0)
	hero.dot = overlay:CreateTexture(nil, "OVERLAY")
	hero.dot:SetTexture(T.WHITE)
	hero.dot:SetSize(7, 7)
	hero.dot:SetPoint("BOTTOMLEFT", PAD, 20)
	hero.status = T.Text(overlay, 12, C.muted)
	hero.status:SetPoint("LEFT", hero.dot, "RIGHT", 7, 0)
	hero.level = T.Text(overlay, 12, C.muted)
	hero.level:SetPoint("LEFT", hero.status, "RIGHT", 14, 0)
	hero.tag = T.Text(overlay, 11, C.accent2, nil, true)
	hero.tag:SetPoint("TOPLEFT", PAD, -14)
	hero.tag:SetShadowOffset(1, -1)
	hero.giver = T.Text(overlay, 11, C.dim)
	hero.giver:SetPoint("TOPRIGHT", -PAD, -14)
	hero.giver:SetJustifyH("RIGHT")
	hero.dist = T.Text(overlay, 15, C.text)
	hero.dist:SetPoint("TOPRIGHT", hero.giver, "BOTTOMRIGHT", 0, -5)
	hero.dist:SetJustifyH("RIGHT")
	hero.dist:SetShadowOffset(1, -1)
	self.hero = hero

	-- placeholder
	self.hint = CreateFrame("Frame", nil, f)
	self.hint:SetAllPoints()
	self.hint.title = T.Text(self.hint, 15, C.text)
	self.hint.title:SetPoint("CENTER", 0, 10)
	self.hint.title:SetJustifyH("CENTER")
	self.hint.text = T.Text(self.hint, 12, C.muted)
	self.hint.text:SetPoint("TOP", self.hint.title, "BOTTOM", 0, -8)
	self.hint.text:SetJustifyH("CENTER")
	self.hint:Hide()
	return self
end

function Inspector:Take(kind, make)
	local pool = self.pools[kind]
	if not pool then pool = {}; self.pools[kind] = pool end
	local n = (self.used[kind] or 0) + 1
	self.used[kind] = n
	local o = pool[n]
	if not o then o = make(); pool[n] = o end
	o:ClearAllPoints()
	o:Show()
	return o
end

function Inspector:Reset()
	for kind, pool in pairs(self.pools) do
		for _, o in ipairs(pool) do o:Hide() end
		self.used[kind] = 0
	end
end

function Inspector:Width()
	local w = self.scroll:GetWidth() or 0
	if w < 50 then w = 340 end
	return w
end

function Inspector:Heading(text)
	local T, C = QL.Theme, QL.Theme.C
	local h = self:Take("heading", function()
		local fr = CreateFrame("Frame", nil, self.content)
		fr:SetHeight(18)
		fr.bar = fr:CreateTexture(nil, "ARTWORK")
		fr.bar:SetTexture(T.WHITE)
		fr.bar:SetSize(3, 12)
		fr.bar:SetPoint("LEFT")
		T.Gradient(fr.bar, "VERTICAL", C.accent2, C.accent)
		fr.text = T.Text(fr, 12, C.text, nil, true)
		fr.text:SetPoint("LEFT", 10, 0)
		fr.line = fr:CreateTexture(nil, "BORDER")
		fr.line:SetTexture(T.WHITE)
		fr.line:SetHeight(1)
		fr.line:SetPoint("LEFT", fr.text, "RIGHT", 10, 0)
		fr.line:SetPoint("RIGHT")
		T.Color(fr.line, C.lineSoft)
		return fr
	end)
	h:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, self.y)
	h:SetWidth(self:Width() - PAD * 2)
	h.text:SetText(text)
	self.y = self.y - 28
end

function Inspector:Paragraph(text, c, size)
	local T, C = QL.Theme, QL.Theme.C
	local p = self:Take("para", function()
		local fs = T.Text(self.content, 13, C.text)
		if fs.SetWordWrap then fs:SetWordWrap(true) end
		fs:SetJustifyV("TOP")
		if fs.SetSpacing then fs:SetSpacing(3) end
		return fs
	end)
	T.SetFont(p, size or 13)
	local cc = c or C.text
	p:SetTextColor(cc[1], cc[2], cc[3], 1)
	p:SetWidth(self:Width() - PAD * 2)
	p:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, self.y)
	p:SetText(text)
	local h = p:GetStringHeight() or 14
	self.y = self.y - h - 14
end

-- A row: picture, name, sub line, right-hand text, optional progress bar; clickable.
function Inspector:Row(o)
	local T, C = QL.Theme, QL.Theme.C
	local r = self:Take("row", function()
		local b = CreateFrame("Button", nil, self.content)
		b:SetHeight(ROW_H)
		b.bg = T.Fill(b, C.card)
		T.Border(b, C.lineSoft)
		b.pic = CreateFrame("Frame", nil, b)
		b.pic:SetSize(ROW_H - 10, ROW_H - 10)
		b.pic:SetPoint("LEFT", 5, 0)
		T.Fill(b.pic, C.canvas)
		T.Border(b.pic, C.line)
		b.icon = b.pic:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.model = newModel(b.pic)
		if b.model then b.model:SetPoint("TOPLEFT", 1, -1); b.model:SetPoint("BOTTOMRIGHT", -1, 1) end
		b.dot = b:CreateTexture(nil, "ARTWORK")
		b.dot:SetTexture(T.WHITE)
		b.dot:SetSize(6, 6)
		b.dot:SetPoint("LEFT", 14, 0)
		b.name = T.Text(b, 13, C.text)
		b.sub = T.Text(b, 11, C.muted)
		b.right = T.Text(b, 12, C.text)
		b.right:SetPoint("RIGHT", -10, 0)
		b.right:SetJustifyH("RIGHT")
		b.bar = T.Bar(b, 2)
		b.bar:SetPoint("BOTTOMLEFT", ROW_H, 6)
		b.bar:SetPoint("BOTTOMRIGHT", -10, 6)
		b:SetScript("OnEnter", function(btn)
			T.Color(btn.bg, C.cardHover)
			if btn.tip then
				local tip = QL.Tip()
				tip:SetOwner(btn, "ANCHOR_LEFT")
				btn.tip(tip)
				tip:Show()
			end
		end)
		b:SetScript("OnLeave", function(btn) T.Color(btn.bg, C.card); QL.Tip():Hide() end)
		b:SetScript("OnClick", function(btn) if btn.click then btn.click() end end)
		return b
	end)
	local w = self:Width() - PAD * 2
	r:SetWidth(w)
	r:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, self.y)
	r.click, r.tip = o.click, o.tip
	-- picture: creature model, else icon, else a status dot
	local hasPic = o.npc or o.icon
	r.pic:SetShown(hasPic and true or false)
	r.dot:SetShown(not hasPic and o.dot ~= nil)
	if o.dot then r.dot:SetVertexColor(o.dot[1], o.dot[2], o.dot[3], 1) end
	local modelShown = false
	if o.npc and r.model then modelShown = setCreature(r.model, o.npc, 1.05, true) end
	if r.model and not modelShown then r.model:Hide(); r.model.npcId = nil end
	r.icon:SetShown(not modelShown and hasPic and true or false)
	if not modelShown and hasPic then r.icon:SetTexture(o.icon or QUESTION) end
	local left = hasPic and (ROW_H + 4) or (o.dot and 28 or 12)
	r.name:ClearAllPoints()
	r.name:SetPoint("TOPLEFT", left, o.sub and -8 or -14)
	r.name:SetPoint("RIGHT", r, "RIGHT", -(o.right and 70 or 10), 0)
	r.name:SetText(o.name or "")
	local nc = o.nameColor or C.text
	r.name:SetTextColor(nc[1], nc[2], nc[3], 1)
	r.sub:ClearAllPoints()
	r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
	r.sub:SetPoint("RIGHT", r, "RIGHT", -10, 0)
	r.sub:SetText(o.sub or "")
	r.sub:SetShown(o.sub ~= nil)
	r.right:SetText(o.right or "")
	local rc = o.rightColor or C.text
	r.right:SetTextColor(rc[1], rc[2], rc[3], 1)
	r.bar:SetShown(o.progress ~= nil)
	if o.progress then
		r.bar:ClearAllPoints()
		r.bar:SetPoint("BOTTOMLEFT", left, 6)
		r.bar:SetPoint("BOTTOMRIGHT", -10, 6)
		r.bar:SetValue(o.progress, o.progress >= 1 and QL.Theme.STATUS.done or nil)
	end
	self.y = self.y - ROW_H - 6
	return r
end

function Inspector:Tiles(itemIds)
	local T, C = QL.Theme, QL.Theme.C
	local perRow = math.max(1, math.floor((self:Width() - PAD * 2 + 6) / (TILE + 6)))
	for i, itemId in ipairs(itemIds) do
		local tile = self:Take("tile", function()
			local b = CreateFrame("Button", nil, self.content)
			b:SetSize(TILE, TILE)
			T.Fill(b, C.canvas)
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
			b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			b:SetScript("OnEnter", function(btn)
				GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
				local ok = GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, btn.itemId)
				if not ok then pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. btn.itemId) end
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			b:SetScript("OnClick", function(btn)
				if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink and GetItemInfo then
					local _, link = GetItemInfo(btn.itemId)
					if link then ChatEdit_InsertLink(link) end
				end
			end)
			return b
		end)
		tile.itemId = itemId
		tile.icon:SetTexture(QL.ItemIcon(itemId) or QUESTION)
		local q = QUALITY[QL.ItemQuality(itemId) or 1] or QUALITY[1]
		T.Border(tile, { q[1], q[2], q[3], 0.9 }, 1)
		local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
		tile:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD + col * (TILE + 6), self.y - row * (TILE + 6))
	end
	local rows = math.ceil(#itemIds / perRow)
	self.y = self.y - rows * (TILE + 6) - 8
end

function Inspector:Buttons(list)
	local T = QL.Theme
	local x = PAD
	local room = (self.content.GetWidth and self.content:GetWidth() or 0)
	if type(room) ~= "number" or room < 200 then room = 9999 end
	for _, o in ipairs(list) do
		local b = self:Take("button", function() return T.Button(self.content, 140, 30) end)
		b:SetLabel(o.label)
		b:SetActive(false)
		local C = T.C
		local lc = o.danger and C.danger or C.muted
		b.label:SetTextColor(lc[1], lc[2], lc[3], 1)
		b:SetWidth(math.max(110, (b.label:GetStringWidth() or 80) + 30))
		-- a new line when the row is full
		if x > PAD and x + b:GetWidth() > room - PAD then
			x = PAD
			self.y = self.y - 38
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, self.y)
		b:SetScript("OnClick", o.click)
		x = x + b:GetWidth() + 8
	end
	self.y = self.y - 42
end

-- Content ---------------------------------------------------------------------------------------

local function placeText(kind, id)
	local zone, x, y = QL.QuestPlace(kind, id)
	if not zone then return nil end
	if x and y and x >= 0 and y >= 0 then return ("%s  ·  %.1f, %.1f"):format(zone, x, y) end
	return zone
end

-- Point the arrow at an NPC, object or item drop spots for this quest ("Start: Bob", ...).
local function pointAt(kind, id, name, role, questId)
	if QL.SetArrowPlace then
		QL.SetArrowPlace(kind, id, { title = name, label = role .. ": " .. QL.QuestTitle(questId), questId = questId })
	end
end

local function placeTip(name, sub)
	return function(tip)
		tip:AddLine(name or "?", 1, 1, 1)
		if sub then tip:AddLine(sub, 0.7, 0.7, 0.7, true) end
		tip:AddLine(L("Click: point the arrow here"), 0.24, 0.84, 0.78)
	end
end

local function personRow(self, who, fallbackTitle, questId, role)
	if not who then return end
	local o = { name = who.name, sub = fallbackTitle }
	if who.kind == "npc" then
		o.npc = who.id
		o.icon = ICON.npc
		o.sub = placeText("npc", who.id) or fallbackTitle
	elseif who.kind == "object" then
		o.icon = ICON.object
		o.sub = placeText("object", who.id) or fallbackTitle
	else
		o.icon = QL.ItemIcon(who.id) or QUESTION
		o.sub = L("Starts from an item")
	end
	if questId then
		o.click = function() pointAt(who.kind, who.id, who.name, role, questId) end
		o.tip = placeTip(who.name, o.sub)
	end
	self:Row(o)
end

local function chainRows(self, ids, ctx)
	local T = QL.Theme
	for _, id in ipairs(ids) do
		local s = T.STATUS[QL.NodeStatus(id, ctx)] or T.STATUS.locked
		local level = QL.QuestLevel(id)
		self:Row({
			name = QL.QuestTitle(id),
			dot = s,
			right = level and L("Lv %d"):format(level) or nil,
			rightColor = QL.Theme.C.muted,
			click = function()
				-- a linked quest: open it and point the arrow at it (unless a route is running)
				if QL.SetArrowTarget and not (QL.RouteActive and QL.RouteActive()) then pcall(QL.SetArrowTarget, id) end
				QL.Open(id)
			end,
			tip = function(tip) QL.FillQuestTooltip(tip, id, ctx) end,
		})
	end
end

function Inspector:Clear(title, text)
	self:Reset()
	self.hero:Hide()
	self.hint:Show()
	self.hint.title:SetText(title or "")
	self.hint.text:SetText(text or "")
	self.scroll:SetContentHeight(0)
end

function Inspector:Show(id, chain)
	local T, C = QL.Theme, QL.Theme.C
	self:Reset()
	self.hint:Hide()
	local ctx = QL.Context()
	local hero = self.hero
	hero:Show()
	hero:SetWidth(self:Width())

	-- hero: the giver in 3D, else an icon
	local starter = QL.QuestStarter(id)
	local modelShown = false
	if starter and starter.kind == "npc" and hero.model then
		modelShown = setCreature(hero.model, starter.id, 1.7, false)
		if modelShown and hero.model.SetFacing then pcall(hero.model.SetFacing, hero.model, -0.35) end
	end
	if hero.model and not modelShown then hero.model:Hide(); hero.model.npcId = nil end
	local icon = QUESTION
	if starter and starter.kind == "item" then icon = QL.ItemIcon(starter.id) or QUESTION
	elseif starter and starter.kind == "object" then icon = ICON.object end
	hero.icon:SetTexture(icon)
	hero.icon:SetShown(not modelShown)
	hero.iconRing:SetShown(not modelShown)
	hero.title:SetText(QL.QuestTitle(id))
	local status = QL.NodeStatus(id, ctx)
	local s = T.STATUS[status] or T.STATUS.locked
	hero.dot:SetVertexColor(s[1], s[2], s[3], 1)
	hero.status:SetText(L(s[4]))
	hero.status:SetTextColor(s[1], s[2], s[3], 1)
	local level = QL.QuestLevel(id)
	local req = QL.Q(id, "requiredLevel")
	local lv = level and QL.LevelMarkup(id, ctx, "Level %d") or ""
	local dkey, dc = QL.QuestDifficulty(level, ctx.level)
	if dc and (dkey == "hard" or dkey == "impossible") then lv = lv .. " " .. T.Hex(dc) .. "(" .. L(dc[4]) .. ")|r" end
	hero.tag:SetText(QL.DungeonMarkup(id) or "")
	if type(req) == "number" and req > 0 and level and req ~= level then lv = lv .. "  ·  " .. L("needs %d"):format(req) end
	local heroXP = QL.QuestXPAt(id, ctx.level)
	if heroXP then lv = lv .. "  ·  " .. T.Hex(C.accent) .. QL.XPText(heroXP) .. "|r" end
	hero.level:SetText(lv)
	hero.giver:SetText(starter and starter.name or "")
	hero.dist:SetText(QL.DistanceMarkup and QL.DistanceMarkup(id, ctx, 13) or "")

	self.y = -HERO_H - 8

	local objective = QL.QuestObjectives(id)
	if objective then
		self:Heading(L("Objective"))
		self:Paragraph(objective)
	end
	local story = QL.QuestDescription(id)
	if story then
		self:Heading(L("Story"))
		self:Paragraph(story, C.muted, 12)
	end

	-- tasks: live with progress, else from the database with pictures
	local live = QL.LiveObjectives(id)
	local tasks = QL.QuestTasks(id)
	if live or #tasks > 0 then
		self:Heading(L("Tasks"))
		if live then
			for i, o in ipairs(live) do
				local t = tasks[i]
				local row = { name = o.text, progress = o.need > 0 and (o.have / o.need) or (o.done and 1 or 0) }
				if o.need > 0 then row.right = ("%d/%d"):format(o.have, o.need) end
				row.rightColor = o.done and T.STATUS.done or C.text
				row.nameColor = o.done and C.muted or C.text
				if t then
					row.npc = t.npc
					row.icon = (t.kind == "item" and QL.ItemIcon(t.id)) or ICON[t.kind] or QUESTION
					if not o.done and t.kind ~= "rep" then
						local kind, tid = t.kind, t.id
						row.click = function() pointAt(kind, tid, t.name or o.text, L("Tasks"), id) end
						row.tip = placeTip(t.name or o.text, o.text)
					end
				end
				self:Row(row)
			end
		else
			for _, t in ipairs(tasks) do
				local name = t.text or t.name or "?"
				local sub
				if t.kind == "npc" then sub = L("Slay")
				elseif t.kind == "item" then sub = L("Collect")
				elseif t.kind == "object" then sub = L("Use")
				elseif t.kind == "rep" then sub = L("Reputation") end
				local kind, tid = t.kind, t.id
				self:Row({
					name = name, sub = sub, npc = t.npc,
					icon = (t.kind == "item" and QL.ItemIcon(t.id)) or ICON[t.kind] or QUESTION,
					click = kind ~= "rep" and function() pointAt(kind, tid, t.name or name, sub or L("Tasks"), id) end or nil,
					tip = kind ~= "rep" and placeTip(t.name or name, sub) or nil,
				})
			end
		end
	end

	-- people
	local finisher = QL.QuestFinisher(id)
	if starter then
		self:Heading(L("Start"))
		personRow(self, starter, nil, id, L("Start"))
	end
	if finisher then
		self:Heading(L("Turn in"))
		personRow(self, finisher, nil, id, L("Turn in"))
	end

	-- rewards
	local xp, fullXP = QL.QuestXPAt(id, ctx.level)
	local reps = QL.QuestReputation(id)
	local items = QL.RewardItems(id)
	if xp or #reps > 0 or #items > 0 then
		self:Heading(L("Rewards"))
		local parts = {}
		if xp then
			local t = T.Hex(C.accent) .. QL.XPText(xp) .. "|r"
			if fullXP and fullXP ~= xp then t = t .. " " .. T.Hex(C.dim) .. L("(full: %s)"):format(QL.FormatNumber(fullXP)) .. "|r" end
			parts[#parts + 1] = t
		end
		for _, r in ipairs(reps) do
			local sign = r[2] > 0 and "+" or ""
			parts[#parts + 1] = T.Hex(r[2] > 0 and T.STATUS.done or C.danger) .. sign .. r[2] .. "|r " .. (r[3] or L("Faction #%d"):format(r[1]))
		end
		if #parts > 0 then self:Paragraph(table.concat(parts, "    "), C.text, 13) end
		if xp and status ~= "done" then
			self.y = self.y + 6
			self:Paragraph(QL.GainText(QL.LevelGain(xp)), C.muted, 11)
		end
		if #items > 0 then self:Tiles(items) end
	end

	-- chain neighbours
	local before, after = {}, {}
	if chain then
		for _, e in ipairs(chain.edges) do
			if not e.back then
				if e.to == id then before[#before + 1] = e.from end
				if e.from == id then after[#after + 1] = e.to end
			end
		end
	end
	if #before > 0 then
		self:Heading(L("Comes after"))
		chainRows(self, before, ctx)
	end
	if #after > 0 then
		self:Heading(L("Leads to"))
		chainRows(self, after, ctx)
	end
	local closes = QL.Ids(QL.Q(id, "exclusiveTo"))
	if #closes > 0 then
		self:Heading(L("Closes for good"))
		for _, cid in ipairs(closes) do
			self:Row({ name = QL.QuestTitle(cid), dot = C.danger, nameColor = C.danger, click = function() QL.Open(cid) end })
		end
	end

	-- actions
	self.y = self.y - 4
	local actions = {}
	if QL.SetArrowTarget and status ~= "done" then
		if QL.ArrowQuest() == id then
			actions[#actions + 1] = { label = L("Stop the arrow"), click = function() QL.ClearArrow(); QL.RenderWindow(false) end }
		else
			actions[#actions + 1] = { label = L("Point the arrow"), click = function() QL.SetArrowTarget(id); QL.RenderWindow(false) end }
		end
	end
	actions[#actions + 1] = { label = L("Link in chat"), click = function() QL.InsertQuestLink(id) end }
	if ctx.log[id] and QuestMapFrame_OpenToQuestDetails then
		actions[#actions + 1] = { label = L("Open in quest log"), click = function() pcall(QuestMapFrame_OpenToQuestDetails, id) end }
	end
	if ctx.log[id] and QL.ConfirmAbandon then
		actions[#actions + 1] = { label = L("Abandon quest"), danger = true, click = function() QL.ConfirmAbandon(id) end }
	end
	self:Buttons(actions)
	self.scroll:SetContentHeight(-self.y + 12)
	self.scroll:SetVerticalScroll(0)
	if self.scroll.UpdateThumb then self.scroll.UpdateThumb() end
end
