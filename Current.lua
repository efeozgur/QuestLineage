-- The current quest: a small window with the quest you are doing now, its stage and its
-- objectives with counters and bars ("Boar slain 3/8"), its XP and how far it is.
--
--   ┌ CURRENT QUEST ──────────── Lv 5 · 450 XP ┐
--   │ The Gathering                             │
--   │ ● In your log  ·  120 yd                  │
--   │ ○ Bob questioned                    0/1   │
--   │ ✓ Boar Ribs                         5/5   │
--   └───────────────────────────────────────────┘
--
-- Which quest: the arrow's (or the quest an arrow place belongs to), else the last quest that
-- made progress or was taken. Under it, "Quests": every other quest in your log, one line each
-- with its first open objective and a thin bar; ready ones first, in green. Click a line: it
-- becomes the current quest (the arrow turns to it); right-click: open it in QuestLineage. The
-- header folds the list (currentLogCollapsed).
--
-- The game's own quest tracker can be hidden (setting hideGameTracker), so this window replaces
-- it: whichever of ObjectiveTrackerFrame / QuestWatchFrame / WatchFrame exists, hidden again when
-- the game shows it, never touched in combat (applied when combat ends). Objective rows flash when their counter goes up. Click the title:
-- open it in QuestLineage; right-click: fold the objectives. Drag to move (currentPoint).
-- Setting currentQuest.
--
--   QL.ObjectiveRows(id, ctx) -> { {text, have, need, done, task}, ... }   (pure-ish, tested)
--   QL.CurrentQuest(ctx) -> questId | nil

local _, QL = ...

local W = 290
local ROW_H = 30

local frame
local lastProgress
local snapshot = {}

local function L(s) return QL.L(s) end

-- Objectives -------------------------------------------------------------------------------------------

local function lower(s) return type(s) == "string" and s:lower() or "" end

-- The live objectives of a logged quest, each matched to the database task it is about (by name
-- in the objective's text, else by order), or the database tasks of a quest not yet taken.
-- Kept per context table (a new one comes with every quest-log change), so plates, areas, the
-- window and the nearby hints share one reading of the client per quest. Callers never change the
-- rows they get.
local rowCache = setmetatable({}, { __mode = "k" })
local buildRows
function QL.ObjectiveRows(id, ctx)
	ctx = ctx or (QL.Context and QL.Context())
	if type(ctx) ~= "table" or id == nil then return buildRows(id) end
	local byId = rowCache[ctx]
	if not byId then byId = {}; rowCache[ctx] = byId end
	local rows = byId[id]
	if not rows then rows = buildRows(id); byId[id] = rows end
	return rows
end

function buildRows(id)
	local tasks = QL.QuestTasks(id)
	local live = QL.LiveObjectives(id)
	local rows = {}
	if live then
		local used = {}
		for i, o in ipairs(live) do
			local task
			local text = lower(o.text)
			for j, t in ipairs(tasks) do
				if not used[j] and ((t.name and text:find(lower(t.name), 1, true)) or (t.text and text:find(lower(t.text), 1, true))) then
					task = t; used[j] = true; break
				end
			end
			if not task and tasks[i] and not used[i] then task = tasks[i]; used[i] = true end
			rows[#rows + 1] = { text = o.text, have = o.have, need = o.need, done = o.done, task = task }
		end
	else
		for _, t in ipairs(tasks) do
			rows[#rows + 1] = { text = t.text or t.name or "?", task = t }
		end
	end
	return rows
end

-- Which quest is current ----------------------------------------------------------------------------

function QL.CurrentQuest(ctx)
	ctx = ctx or QL.Context()
	local q = QL.ArrowQuest and QL.ArrowQuest()
	if q and QL.NodeStatus(q, ctx) ~= "done" then return q end
	local t = QL.ArrowTarget and QL.ArrowTarget()
	if t and t.questId and QL.NodeStatus(t.questId, ctx) ~= "done" then return t.questId end
	if lastProgress and ctx.log[lastProgress] then return lastProgress end
	return nil
end

-- Remember the last quest whose counters went up (and which rows did, to flash them).
local function watchProgress()
	local ctx = QL.Context()
	local flashes = {}
	for id in pairs(ctx.log) do
		local live = QL.LiveObjectives(id) or {}
		local before = snapshot[id]
		local now = {}
		for i, o in ipairs(live) do
			now[i] = o.have or 0
			if before and before[i] and now[i] > before[i] then
				lastProgress = id
				flashes[#flashes + 1] = { id, i }
			end
		end
		snapshot[id] = now
	end
	return flashes
end

-- The window -------------------------------------------------------------------------------------------

-- The window hangs from its top-left corner, so it grows and folds downwards (from the top) and
-- never around its middle: after a drag the client anchors it wherever it likes (CENTER, RIGHT...),
-- so the point is re-made as TOPLEFT on UIParent's BOTTOMLEFT (both in the window's own units).
local function pinTopLeft()
	local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
	if not (ok and type(left) == "number" and type(top) == "number") then return nil end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	return left, top
end

-- Locked (setting currentLocked): no drag moves the window; the lock in its corner switches it.
local function startMove()
	if QL.DB().currentLocked == true then return end
	frame:StartMoving()
end

local function savePoint()
	local left, top = pinTopLeft()
	if left then
		QL.DB().currentPoint = { "TOPLEFT", "BOTTOMLEFT", left, top }
	else
		local point, _, relPoint, x, y = frame:GetPoint(1)
		QL.DB().currentPoint = { point, relPoint, x, y }
	end
end

local function newRow()
	local T, C = QL.Theme, QL.Theme.HUD
	local r = CreateFrame("Frame", nil, frame)
	r:SetHeight(ROW_H)
	r.flash = T.Fill(r, { C.accent[1], C.accent[2], C.accent[3], 0 })
	r.dot = r:CreateTexture(nil, "ARTWORK")
	r.dot:SetTexture("Interface\\AddOns\\QuestLineage\\Media\\ring")
	r.dot:SetSize(10, 10)
	r.dot:SetPoint("TOPLEFT", 14, -6)
	r.text = T.Text(r, 12, C.text)
	r.text:SetPoint("TOPLEFT", 32, -4)
	r.text:SetPoint("RIGHT", r, "RIGHT", -56, 0)
	r.count = T.Text(r, 12, C.text, nil, true)
	r.count:SetPoint("TOPRIGHT", -14, -4)
	r.count:SetJustifyH("RIGHT")
	r.bar = T.Bar(r, 3)
	r.bar:SetPoint("BOTTOMLEFT", 32, 6)
	r.bar:SetPoint("BOTTOMRIGHT", -14, 6)
	r.flashT = 0
	return r
end

local function build()
	local T, C = QL.Theme, QL.Theme.HUD
	frame = CreateFrame("Button", "QuestLineageCurrent", UIParent)
	frame:SetWidth(W)
	frame:SetHeight(80)
	frame:SetScale(math.max(0.6, math.min(1.6, (tonumber(QL.DB().currentScale) or 100) / 100)))
	local p = QL.DB().currentPoint
	if type(p) == "table" and p[1] then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120) end
	-- a point saved another way (older saves, the default) turns into the top-left one once the
	-- window is laid out, where it stands, so it folds from the top from then on
	frame:HookScript("OnShow", function()
		local sp = QL.DB().currentPoint
		if type(sp) == "table" and sp[1] == "TOPLEFT" and sp[2] == "BOTTOMLEFT" then return end
		local function convert() pcall(savePoint) end
		if C_Timer and C_Timer.After then C_Timer.After(0, convert) else convert() end
	end)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame:SetScript("OnDragStart", function() startMove() end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePoint() end)
	frame:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			QL.Set("currentCollapsed", not QL.DB().currentCollapsed)
		elseif self.questId then
			QL.Open(self.questId)
		end
	end)
	T.Fill(frame, { QL.Theme.PanelA(0.92) })
	T.Border(frame, C.line)
	local top = frame:CreateTexture(nil, "ARTWORK")
	top:SetTexture(T.WHITE)
	top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1)
	top:SetHeight(2)
	T.Gradient(top, "HORIZONTAL", C.accent, C.accent2)
	frame.label = T.Text(frame, 10, C.accent, nil, true)
	frame.label:SetPoint("TOPLEFT", 14, -12)
	frame.meta = T.Text(frame, 11, C.muted)
	frame.meta:SetPoint("TOPRIGHT", -34, -12) -- room for the minimise button
	frame.meta:SetJustifyH("RIGHT")
	frame.title = T.Text(frame, 15, C.text, nil, true)
	frame.title:SetPoint("TOPLEFT", 14, -28)
	frame.title:SetPoint("RIGHT", frame, "RIGHT", -30, 0) -- room for the abandon cross
	frame.stateDot = frame:CreateTexture(nil, "ARTWORK")
	frame.stateDot:SetTexture("Interface\\AddOns\\QuestLineage\\Media\\disc")
	frame.stateDot:SetSize(7, 7)
	frame.stateDot:SetPoint("TOPLEFT", 14, -53)
	-- how far the quest is: "2/3 objectives · 72%" on the state line, and a bar under it
	frame.progress = T.Text(frame, 11, C.accent, nil, true)
	frame.progress:SetPoint("TOPRIGHT", -14, -48)
	frame.progress:SetJustifyH("RIGHT")
	frame.state = T.Text(frame, 11, C.muted)
	frame.state:SetPoint("LEFT", frame.stateDot, "RIGHT", 7, 0)
	frame.state:SetPoint("RIGHT", frame.progress, "LEFT", -8, 0)
	frame.foldHint = T.Text(frame, 10, C.dim)
	frame.foldHint:SetPoint("TOPLEFT", 14, -74)
	frame.foldHint:Hide()
	-- getting there (Travel.lua): one line under the bar; its tip lists every step
	frame.way = CreateFrame("Button", nil, frame)
	frame.way:SetHeight(16)
	frame.way:SetPoint("TOPLEFT", 14, -71)
	frame.way:SetPoint("TOPRIGHT", -14, -71)
	frame.way.text = T.Text(frame.way, 10, C.accent)
	frame.way.text:SetPoint("LEFT"); frame.way.text:SetPoint("RIGHT")
	frame.way:SetScript("OnEnter", function(self)
		local trip = self.trip
		if not trip then return end
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_BOTTOM")
		tip:AddLine(L("Getting there"), 1, 1, 1)
		for i, s in ipairs(trip.steps) do
			local text, sub = QL.TripStepText(s)
			tip:AddLine(("%d. %s"):format(i, text), 0.85, 0.87, 0.92)
			if sub then tip:AddLine("    " .. sub, 0.6, 0.62, 0.68) end
		end
		local total = QL.TravelText and QL.TravelText(trip.total)
		if total then tip:AddLine(L("About %s in all, from where you stand."):format(total), 0.6, 0.62, 0.68) end
		tip:Show()
	end)
	frame.way:SetScript("OnLeave", function() QL.Tip():Hide() end)
	frame.way:Hide()
	frame.bar = T.Bar(frame, 3)
	frame.bar:SetPoint("TOPLEFT", 14, -64)
	frame.bar:SetPoint("TOPRIGHT", -14, -64)
	frame.sep = frame:CreateTexture(nil, "BORDER")
	frame.sep:SetTexture(T.WHITE)
	frame.sep:SetPoint("TOPLEFT", 14, -74); frame.sep:SetPoint("TOPRIGHT", -14, -74)
	frame.sep:SetHeight(1)
	T.Color(frame.sep, C.lineSoft)
	frame.rows = {}
	frame.logRows = {}
	local head = CreateFrame("Button", nil, frame)
	head:SetHeight(24)
	local line = head:CreateTexture(nil, "BORDER")
	line:SetTexture(T.WHITE)
	line:SetPoint("TOPLEFT", 14, 0); line:SetPoint("TOPRIGHT", -14, 0)
	line:SetHeight(1)
	T.Color(line, C.lineSoft)
	head.text = T.Text(head, 10, C.accent, nil, true)
	head.text:SetPoint("LEFT", 14, -2)
	head.fold = T.Text(head, 13, C.muted, nil, true)
	head.fold:SetPoint("RIGHT", -14, -2)
	-- show or hide every quest's objectives at once
	head.all = CreateFrame("Button", nil, head)
	head.all:SetSize(90, 18)
	head.all:SetPoint("RIGHT", head.fold, "LEFT", -10, 0)
	head.all.text = T.Text(head.all, 10, C.muted, nil, true)
	head.all.text:SetPoint("RIGHT", 0, 0)
	head.all.text:SetJustifyH("RIGHT")
	head.all:SetScript("OnClick", function() QL.ToggleLogObjectives() end)
	head.all:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(C.text)) end)
	head.all:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(C.muted)) end)
	-- the interface language: an EN | TR tab on the window's top edge, left of the lock (the zone tab's
	-- and the lock's twin), the chosen half lit (TR needs WoWTR, dimmed without it); placed with the lock below
	local lang = CreateFrame("Frame", nil, frame)
	lang:SetSize(52, 22)
	lang:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
	T.Fill(lang, { QL.Theme.PanelA(0.94) })
	T.Border(lang, C.line)
	lang.lit = lang:CreateTexture(nil, "ARTWORK")
	lang.lit:SetTexture(T.WHITE)
	lang.lit:SetSize(25, 20)
	T.Color(lang.lit, { C.accent[1], C.accent[2], C.accent[3], 0.18 })
	lang.halves = {}
	for i, code in ipairs({ "en", "tr" }) do
		local b = CreateFrame("Button", nil, lang)
		b:SetSize(26, 22)
		b:SetPoint("LEFT", (i - 1) * 26, 0)
		b.code = code
		b.text = T.Text(b, 10, C.muted, nil, true)
		b.text:SetPoint("CENTER", 0, 0)
		b.text:SetText(code:upper())
		b:SetScript("OnClick", function()
			if code == "tr" and not QL.HasWoWTR() then
				QL.Print(L("Turkish needs WoWTR; showing English until it is loaded."), "warn")
				return
			end
			if QL.DB().lang ~= code then QL.Set("lang", code) end
			if QL.RenderWindow then pcall(QL.RenderWindow, false) end
		end)
		b:SetScript("OnEnter", function(self)
			if not self.on then self.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1) end
			local tip = QL.Tip()
			tip:SetOwner(self, "ANCHOR_SIDE", frame)
			tip:AddLine(code == "tr" and "Türkçe" or "English", 1, 1, 1)
			if code == "tr" and not QL.HasWoWTR() then tip:AddLine(L("Turkish needs WoWTR"), 0.97, 0.44, 0.44) end
			tip:Show()
		end)
		b:SetScript("OnLeave", function()
			QL.RefreshLangPill()
			QL.Tip():Hide()
		end)
		lang.halves[i] = b
	end
	head.lang = lang
	head:SetScript("OnClick", function() QL.Set("currentLogCollapsed", not QL.DB().currentLogCollapsed) end)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() startMove() end)
	head:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); savePoint() end)
	head:Hide()
	frame.logHead = head
	frame.logChips = {}
	frame.logMore = T.Text(frame, 10, C.dim)
	frame.logMore:Hide()
	frame:SetScript("OnEnter", function(self)
		if not self.questId then return end
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_SIDE", frame)
		QL.FillQuestTooltip(tip, self.questId)
		tip:AddLine(L("Click: open · Right-click: fold · Drag: move"), 0.5, 0.5, 0.5)
		tip:Show()
	end)
	frame:SetScript("OnLeave", function() QL.Tip():Hide() end)
	-- abandon the current quest: a small cross in the corner while the cursor is on the window
	-- (made after the window's own OnEnter/OnLeave, which it hooks)
	frame.drop = QL.AbandonButton(frame, function() return frame.questId end)
	frame.drop:SetPoint("TOPRIGHT", -8, -26)
	-- the minimise button: folds the whole window down to its title and progress line
	local mini = CreateFrame("Button", nil, frame)
	mini:SetSize(18, 18)
	mini:SetPoint("TOPRIGHT", -8, -8)
	mini:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
	mini.bg = T.Fill(mini, { 0, 0, 0, 0 })
	mini.text = T.Text(mini, 14, C.dim, nil, true)
	mini.text:SetPoint("CENTER", 0, 1)
	mini:SetScript("OnClick", function()
		QL.Set("currentMinimized", not QL.DB().currentMinimized)
		pcall(QL.RefreshCurrent)
		if QL.Tip then QL.Tip():Hide() end
	end)
	mini:SetScript("OnEnter", function(self)
		T.Color(self.bg, C.rowHover)
		self.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_SIDE", frame)
		tip:AddLine(QL.DB().currentMinimized and L("Show the whole window") or L("Fold the window down to its title"), 1, 1, 1)
		tip:Show()
	end)
	mini:SetScript("OnLeave", function(self)
		T.Color(self.bg, { 0, 0, 0, 0 })
		self.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 1)
		QL.Tip():Hide()
	end)
	mini:Hide()
	frame.mini = mini
	-- the lock: pins the window where it stands (drags do nothing), a click switches it. A small tab
	-- on the window's top edge at the right (the zone tab's twin), clear of every text inside.
	local lock = CreateFrame("Button", nil, frame)
	lock:SetSize(26, 22)
	lock:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, -1)
	lock:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
	T.Fill(lock, { QL.Theme.PanelA(0.94) })
	T.Border(lock, C.line)
	lock.bg = T.Fill(lock, { 0, 0, 0, 0 }, "ARTWORK")
	lock.icon = lock:CreateTexture(nil, "OVERLAY")
	lock.icon:SetSize(13, 13)
	lock.icon:SetPoint("CENTER", 0, 0)
	lock:SetScript("OnClick", function()
		QL.Set("currentLocked", not (QL.DB().currentLocked == true))
		QL.RefreshCurrentLock()
		if QL.Tip then QL.Tip():Hide() end
	end)
	lock:SetScript("OnEnter", function(self)
		self.hover = true
		QL.RefreshCurrentLock()
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_SIDE", frame)
		local locked = QL.DB().currentLocked == true
		tip:AddLine(locked and L("Window locked") or L("Lock the window"), 1, 1, 1)
		tip:AddLine(locked and L("Click to unlock it, then drag to move it.") or L("Click to pin it where it stands; dragging then does nothing."), 0.7, 0.7, 0.7, true)
		tip:Show()
	end)
	lock:SetScript("OnLeave", function(self)
		self.hover = false
		QL.RefreshCurrentLock()
		QL.Tip():Hide()
	end)
	frame.lock = lock
	-- the EN | TR tab sits just left of the lock on the same edge
	if frame.logHead and frame.logHead.lang then
		frame.logHead.lang:ClearAllPoints()
		frame.logHead.lang:SetPoint("BOTTOMRIGHT", lock, "BOTTOMLEFT", 2, 0)
		QL.RefreshLangPill()
	end
	QL.BuildZoneTab()
	local since = 0
	frame:SetScript("OnUpdate", function(self, elapsed)
		elapsed = elapsed or 0.016
		-- flashing rows fade out
		for _, r in ipairs(self.rows) do
			if r.flashT > 0 then
				r.flashT = math.max(0, r.flashT - elapsed)
				r.flash:SetAlpha(r.flashT / 1.2 * 0.35)
			end
		end
		since = since + elapsed
		if since >= 1 then since = 0; pcall(QL.RefreshCurrent) end
	end)
	frame:Hide()
end

-- A small "abandon" cross for a quest in the log: shown while the cursor is on its owner (and only
-- for quests in the log); asks before dropping it.
function QL.AbandonButton(owner, questOf)
	local T, C = QL.Theme, QL.Theme.HUD
	local b = CreateFrame("Button", nil, owner)
	b:SetSize(18, 18)
	b:SetFrameLevel((owner:GetFrameLevel() or 1) + 5)
	b.bg = T.Fill(b, { 0, 0, 0, 0 })
	b.x = T.Text(b, 14, C.dim)
	b.x:SetPoint("CENTER", 0, 1)
	b.x:SetText("×")
	b:SetScript("OnClick", function() local id = questOf(); if id then QL.ConfirmAbandon(id) end end)
	b:SetScript("OnEnter", function(self)
		T.Color(self.bg, { C.danger[1], C.danger[2], C.danger[3], 0.18 })
		self.x:SetTextColor(C.danger[1], C.danger[2], C.danger[3], 1)
		QL.Tip():Hide() -- no tooltip of its own: the click asks anyway
	end)
	b:SetScript("OnLeave", function(self)
		T.Color(self.bg, { 0, 0, 0, 0 })
		self.x:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 1)
		if not (owner.IsMouseOver and owner:IsMouseOver() == true) then self:Hide() end
	end)
	b:Hide()
	local function show()
		local id = questOf()
		b:SetShown(id ~= nil and QL.Context().log[id] == true)
	end
	if owner.HookScript then
		owner:HookScript("OnEnter", show)
		owner:HookScript("OnLeave", function()
			if not (b.IsMouseOver and b:IsMouseOver() == true) then b:Hide() end
		end)
	end
	b.Refresh = show
	return b
end

-- The log list -----------------------------------------------------------------------------------------

local LOG_ROW_H = 36
-- how many quests the list shows (setting currentLogMax, 1-30); the rest is "+N more"
local function logMax() return math.max(1, math.min(30, math.floor(tonumber(QL.DB().currentLogMax) or 15))) end

-- The other quests in the log, ready ones first, then by level.
function QL.LogQuests(ctx, exceptId)
	local out = {}
	for id in pairs(ctx.log) do
		if id ~= exceptId and QL.QuestExists(id) then out[#out + 1] = id end
	end
	table.sort(out, function(a, b)
		local ra, rb = ctx.complete[a] and 1 or 0, ctx.complete[b] and 1 or 0
		if ra ~= rb then return ra > rb end
		local la, lb = QL.QuestLevel(a) or 0, QL.QuestLevel(b) or 0
		if la ~= lb then return la < lb end
		return a < b
	end)
	return out
end

-- A quest's first open objective and its overall progress (0..1, nil without counters).
-- Every objective of a logged quest as lines (open ones first in the list's colours, done ones in
-- green with a tick) and the overall share of its counters.
local function summary(id, ctx)
	local T, C = QL.Theme, QL.Theme.HUD
	local g = T.STATUS.done
	local rows = QL.ObjectiveRows(id, ctx)
	local have, need = 0, 0
	local lines = {}
	for _, o in ipairs(rows) do
		if o.need and o.need > 0 then have = have + math.min(o.have or 0, o.need); need = need + o.need end
		local full = o.done or (o.need and o.need > 0 and (o.have or 0) >= o.need)
		if full then
			lines[#lines + 1] = T.Hex(g) .. "✓ " .. (o.text or "") .. "|r"
		else
			lines[#lines + 1] = T.Hex(C.accent) .. "•|r " .. (o.text or "")
		end
	end
	return lines, need > 0 and (have / need) or nil
end

-- Whether a list row shows its objectives: each quest can be folded on its own (logFolded[id]),
-- else the list's default (logObjectives, switched for all from the header).
function QL.LogObjectivesOpen(id)
	local over = type(QL.DB().logFolded) == "table" and QL.DB().logFolded[id]
	if over ~= nil then return not over end
	return QL.DB().logObjectives ~= false
end

function QL.ToggleLogObjectives(id)
	local db = QL.DB()
	if id then
		local map = type(db.logFolded) == "table" and db.logFolded or {}
		map[id] = QL.LogObjectivesOpen(id) -- open -> folded, folded -> open
		db.logFolded = map
	else
		-- every quest: the default flips and single choices are forgotten
		db.logObjectives = not (db.logObjectives ~= false)
		db.logFolded = {}
	end
	pcall(QL.RefreshCurrent)
end

-- A small "–" / "+" button (minimise / show) in the list's look.
local function foldButton(parent, onClick)
	local T, C = QL.Theme, QL.Theme.HUD
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(18, 16)
	b:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
	b.bg = T.Fill(b, { 0, 0, 0, 0 })
	b.text = T.Text(b, 13, C.muted, nil, true)
	b.text:SetPoint("CENTER", 0, 1)
	b.text:SetJustifyH("CENTER")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self) T.Color(self.bg, C.rowHover); self.text:SetTextColor(unpack(C.text)) end)
	b:SetScript("OnLeave", function(self) T.Color(self.bg, { 0, 0, 0, 0 }); self.text:SetTextColor(unpack(C.muted)) end)
	return b
end

local function logRow(i)
	local T, C = QL.Theme, QL.Theme.HUD
	local r = frame.logRows[i]
	if r then return r end
	r = CreateFrame("Button", nil, frame)
	r:SetHeight(LOG_ROW_H)
	r.bg = T.Fill(r, { 0, 0, 0, 0 })
	r.title = T.Text(r, 12, C.text)
	r.title:SetPoint("TOPLEFT", 30, -4) -- the abandon cross sits before it
	r.title:SetPoint("RIGHT", r, "RIGHT", -80, 0)
	r.right = T.Text(r, 11, C.muted, nil, true)
	r.right:SetPoint("TOPRIGHT", -30, -5) -- the minimise button sits to its right
	r.right:SetJustifyH("RIGHT")
	r.sub = T.Text(r, 10, C.muted)
	if r.sub.SetWordWrap then r.sub:SetWordWrap(true) end
	r.sub:SetJustifyV("TOP")
	r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -2)
	r.sub:SetPoint("RIGHT", r, "RIGHT", -14, 0)
	r.bar = T.Bar(r, 2)
	r.bar:SetPoint("BOTTOMLEFT", 30, 3)
	r.bar:SetPoint("BOTTOMRIGHT", -14, 3)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r:SetScript("OnClick", function(self, button)
		if button == "RightButton" then QL.Open(self.questId); return end
		if QL.RouteActive and QL.RouteActive() then QL.Open(self.questId); return end
		if QL.SetArrowTarget then pcall(QL.SetArrowTarget, self.questId) end
	end)
	r:SetScript("OnEnter", function(self)
		T.Color(self.bg, C.rowHover)
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_SIDE", frame)
		QL.FillQuestTooltip(tip, self.questId)
		tip:AddLine(L("Click: make it current · Right-click: open"), 0.5, 0.5, 0.5)
		tip:Show()
	end)
	r:SetScript("OnLeave", function(self) T.Color(self.bg, { 0, 0, 0, 0 }); QL.Tip():Hide() end)
	-- abandon this quest: a cross that shows while the cursor is on the row (after its scripts)
	r.drop = QL.AbandonButton(r, function() return r.questId end)
	r.drop:SetPoint("LEFT", 7, 0)
	-- minimise: hide or show this quest's objectives
	r.fold = foldButton(r, function() if r.questId then QL.ToggleLogObjectives(r.questId) end end)
	r.fold:SetPoint("TOPRIGHT", -8, -3)
	-- dragging a row moves the window
	r:RegisterForDrag("LeftButton")
	r:SetScript("OnDragStart", function() startMove() end)
	r:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); savePoint() end)
	frame.logRows[i] = r
	return r
end

-- Filters for the list (setting currentLogFilter): every quest, the quests of the zone you are
-- in (their own zone or their givers'), your class's quests, chain quests.
local LOG_FILTERS = {
	{ id = "all", label = "All" },
	{ id = "zone", label = "Zone" },
	{ id = "class", label = "Class" },
	{ id = "chain", label = "Chain" },
}

local function asSet(list)
	local set = {}
	for _, id in ipairs(list or {}) do set[id] = true end
	return set
end

-- ids split by filter: { all = ids, zone = {...}, class = {...}, chain = {...} }
function QL.FilterLogQuests(ids, ctx)
	local out = { all = ids, zone = {}, class = {}, chain = {} }
	local area = QL.PlayerZone and QL.PlayerZone()
	local zone = asSet(area and QL.ZoneQuests(area))
	local class = asSet(ctx.classFlag and QL.ClassQuests(ctx.classFlag))
	for _, id in ipairs(ids) do
		if zone[id] then out.zone[#out.zone + 1] = id end
		if class[id] then out.class[#out.class + 1] = id end
		if QL.ChainSummary(id, ctx) then out.chain[#out.chain + 1] = id end
	end
	return out
end

local function chip(i)
	local T, C = QL.Theme, QL.Theme.HUD
	local b = frame.logChips[i]
	if b then return b end
	b = CreateFrame("Button", nil, frame)
	b:SetHeight(20)
	b.bg = T.Fill(b, { 0, 0, 0, 0 })
	b.text = T.Text(b, 10, C.muted, nil, true)
	b.text:SetPoint("CENTER", 0, 1)
	b.text:SetJustifyH("CENTER")
	b.under = b:CreateTexture(nil, "OVERLAY")
	b.under:SetTexture(T.WHITE)
	b.under:SetPoint("BOTTOMLEFT", 4, 0); b.under:SetPoint("BOTTOMRIGHT", -4, 0)
	b.under:SetHeight(2)
	T.Color(b.under, C.accent)
	b:SetScript("OnClick", function(self) QL.Set("currentLogFilter", self.filter) end)
	b:SetScript("OnEnter", function(self) if not self.active then T.Color(self.bg, C.rowHover) end end)
	b:SetScript("OnLeave", function(self) T.Color(self.bg, { 0, 0, 0, 0 }) end)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function() startMove() end)
	b:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); savePoint() end)
	frame.logChips[i] = b
	return b
end

local function drawChips(y, groups, filter)
	local T, C = QL.Theme, QL.Theme.HUD
	local x = 10
	for i, f in ipairs(LOG_FILTERS) do
		local b = chip(i)
		b.filter = f.id
		b.active = f.id == filter
		local n = #groups[f.id]
		b.text:SetText(L(f.label) .. " " .. (b.active and T.Hex(C.text) or T.Hex(C.dim)) .. n .. "|r")
		b.text:SetTextColor(unpack(b.active and C.accent or (n > 0 and C.muted or C.dim)))
		b.under:SetShown(b.active)
		b:SetWidth(math.max(44, (b.text:GetStringWidth() or 40) + 16))
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", x, y)
		b:Show()
		x = x + (b:GetWidth() or 50) + 2
	end
	return y - 24
end

-- The list header's EN | TR pill: the language in use lit, TR dimmed while WoWTR is missing.
function QL.RefreshLangPill()
	local lang = frame and frame.logHead and frame.logHead.lang
	if not lang then return end
	local C = QL.Theme.HUD
	local tr = QL.UseTurkish()
	for i, b in ipairs(lang.halves) do
		b.on = (b.code == "tr") == tr
		local c = b.on and C.accent or (b.code == "tr" and not QL.HasWoWTR() and C.dim or C.muted)
		b.text:SetTextColor(c[1], c[2], c[3], 1)
		if b.on then
			lang.lit:ClearAllPoints()
			lang.lit:SetPoint("LEFT", (i - 1) * 26 + 1, 0)
		end
	end
end

local function drawLog(y, ctx, currentId)
	local T, C = QL.Theme, QL.Theme.HUD
	local ids = QL.LogQuests(ctx, currentId)
	local head = frame.logHead
	for _, r in ipairs(frame.logRows) do r:Hide() end
	for _, b in ipairs(frame.logChips) do b:Hide() end
	frame.logMore:Hide()
	if #ids == 0 then head:Hide(); return y end
	head:ClearAllPoints()
	head:SetPoint("TOPLEFT", 0, y)
	head:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
	local folded = QL.DB().currentLogCollapsed
	head.text:SetText(L("QUESTS") .. "  " .. T.Hex(C.muted) .. #ids .. "|r")
	head.fold:SetText(folded and "+" or "–")
	head.all:SetShown(not folded)
	head.all.text:SetText((QL.DB().logObjectives ~= false) and L("– objectives") or L("+ objectives"))
	QL.RefreshLangPill()
	head:Show()
	y = y - 26
	if folded then return y end
	local filter = QL.DB().currentLogFilter or "all"
	local groups = QL.FilterLogQuests(ids, ctx)
	if not groups[filter] then filter = "all" end
	y = drawChips(y, groups, filter)
	ids = groups[filter]
	if #ids == 0 then
		frame.logMore:ClearAllPoints()
		frame.logMore:SetPoint("TOPLEFT", 14, y - 2)
		frame.logMore:SetText(L("No quests under this filter"))
		frame.logMore:Show()
		return y - 20
	end
	local ready = T.STATUS.done
	for i, id in ipairs(ids) do
		if i > logMax() then
			frame.logMore:ClearAllPoints()
			frame.logMore:SetPoint("TOPLEFT", 14, y - 2)
			frame.logMore:SetText(L("+%d more"):format(#ids - logMax()))
			frame.logMore:Show()
			y = y - 18
			break
		end
		local r = logRow(i)
		r.questId = id
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, y)
		r:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
		r.title:SetText(QL.QuestTitle(id))
		local isReady = ctx.complete[id]
		r.title:SetTextColor(unpack(isReady and { ready[1], ready[2], ready[3] } or (QL.TitleColor(id, ctx) or C.text)))
		local lines, frac = summary(id, ctx)
		if isReady then
			r.right:SetText(L("Ready"))
			r.right:SetTextColor(ready[1], ready[2], ready[3], 1)
			local who = QL.QuestFinisher(id)
			r.sub:SetText(who and (L("Turn in: ") .. who.name) or "")
		else
			local level = QL.QuestLevel(id)
			r.right:SetText(level and QL.LevelMarkup(id, ctx) or "")
			r.right:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)
			if QL.LogObjectivesOpen(id) or #lines == 0 then
				r.sub:SetText(table.concat(lines, "\n"))
			else
				-- minimised: one line with how far it is
				local p = QL.QuestCompletion(id, ctx)
				r.sub:SetText(p and (T.Hex(C.dim) .. L("%d/%d objectives · %d%%"):format(p.done, p.total, p.percent) .. "|r") or "")
			end
		end
		r.fold:SetShown(not isReady and #lines > 0)
		r.fold.text:SetText(QL.LogObjectivesOpen(id) and "–" or "+")
		if frac and not isReady then
			r.bar:Show()
			r.bar:SetValue(frac)
		else
			r.bar:Hide()
		end
		-- the row grows with its objective lines
		r.sub:SetWidth(math.max(60, (frame:GetWidth() or 300) - 30 - 14))
		local subH = ((r.sub:GetText() or "") ~= "") and (r.sub:GetStringHeight() or 12) or 0
		local h = math.max(LOG_ROW_H, 4 + 15 + 2 + subH + 10)
		r:SetHeight(h)
		r:Show()
		y = y - h
	end
	return y
end

local STAGE = {
	available = "Pick up",
	toolow = "Pick up",
	locked = "Pick up",
	active = "In your log",
	ready = "Ready to turn in",
}

-- The lock tab's look: closed and in the accent while locked, open and dim otherwise.
function QL.RefreshCurrentLock()
	local lock = frame and frame.lock
	if not lock then return end
	local C = QL.Theme.HUD
	local locked = QL.DB().currentLocked == true
	lock.icon:SetTexture("Interface\\AddOns\\QuestLineage\\Media\\" .. (locked and "lock" or "lock_open"))
	local c = locked and C.accent or (lock.hover and C.text or C.dim)
	lock.icon:SetVertexColor(c[1], c[2], c[3], 1)
	QL.Theme.Color(lock.bg, lock.hover and C.rowHover or { 0, 0, 0, 0 })
	lock:Show()
end

function QL.RefreshCurrent(flashes)
	if not frame then return end
	if QL.DB().currentQuest == false then frame:Hide(); return end
	local ctx = QL.Context()
	local id = QL.CurrentQuest(ctx)
	local T, C = QL.Theme, QL.Theme.HUD
	local currentParts = { frame.label, frame.meta, frame.title, frame.stateDot, frame.state, frame.progress, frame.bar }
	frame.foldHint:Hide()
	frame.mini:SetShown(id ~= nil)
	QL.RefreshCurrentLock()
	if not id then
		-- no current quest: the window shows the log alone (or nothing when the log is empty)
		frame.questId = nil
		for _, p in ipairs(currentParts) do p:Hide() end
		frame.way:Hide(); frame.way.trip = nil
		frame.sep:Hide()
		for _, r in ipairs(frame.rows) do r:Hide() end
		local y = drawLog(-10, ctx, nil)
		if y == -10 then frame:Hide(); return end
		frame:SetHeight(-y + 6)
		frame:Show()
		return
	end
	for _, p in ipairs(currentParts) do p:Show() end
	frame.questId = id
	frame.label:SetText(L("CURRENT QUEST"))
	local xp = QL.QuestXPAt(id, ctx.level)
	local meta = QL.LevelMarkup(id, ctx)
	if xp then meta = meta .. "  ·  " .. T.Hex(C.accent) .. QL.XPText(xp) .. "|r" end
	local dungeon = QL.DungeonMarkup(id, true)
	if dungeon then meta = dungeon .. "  ·  " .. meta end
	frame.meta:SetText(meta)
	frame.title:SetText(QL.QuestTitle(id))
	frame.title:SetTextColor(unpack(QL.TitleColor(id, ctx) or C.text))
	local status = QL.NodeStatus(id, ctx)
	local s = T.STATUS[status] or T.STATUS.available
	frame.stateDot:SetVertexColor(s[1], s[2], s[3], 1)
	local stage = L(STAGE[status] or s[4])
	-- who to see, for the stages that are about a person
	if status == "ready" or (status == "active" and QL.ObjectiveRows(id, ctx)[1] == nil) then
		local who = QL.QuestFinisher(id)
		if who then stage = L("Turn in: ") .. who.name end
	elseif status ~= "active" then
		local who = QL.QuestStarter(id)
		if who then stage = L("Pick up: ") .. who.name end
	end
	local d = QL.DistanceText and QL.DistanceText(id, ctx)
	frame.state:SetText(T.Hex(s) .. stage .. "|r" .. (d and ("  ·  " .. d) or ""))

	-- completion: objectives done and the share of all counters
	local p = QL.QuestCompletion(id, ctx)
	if p then
		local g = T.STATUS.done
		local full = p.fraction >= 1
		frame.progress:SetText(L("%d/%d objectives · %d%%"):format(p.done, p.total, p.percent))
		frame.progress:SetTextColor(unpack(full and { g[1], g[2], g[3], 1 } or C.accent))
		frame.bar:SetValue(p.fraction, full and g or nil)
	else
		frame.progress:SetText("")
	end
	frame.progress:SetShown(p ~= nil)
	frame.bar:SetShown(p ~= nil)
	frame.completion = p

	-- minimised: only the label, the title, the share done and the bar
	local mini = QL.DB().currentMinimized and true or false
	frame.mini.text:SetText(mini and "+" or "–")
	frame.bar:ClearAllPoints()
	frame.bar:SetPoint("TOPLEFT", 14, mini and -50 or -64)
	frame.bar:SetPoint("TOPRIGHT", -14, mini and -50 or -64)
	if mini then
		for _, q in ipairs({ frame.stateDot, frame.state, frame.progress, frame.sep, frame.foldHint, frame.logHead, frame.logMore, frame.way }) do q:Hide() end
		for _, r in ipairs(frame.rows) do r:Hide() end
		for _, r in ipairs(frame.logRows) do r:Hide() end
		for _, b in ipairs(frame.logChips) do b:Hide() end
		if p then
			frame.meta:SetText(T.Hex(p.fraction >= 1 and T.STATUS.done or C.accent) .. ("%d%%"):format(p.percent) .. "|r")
		else
			frame.meta:SetText("")
		end
		frame:SetHeight(p and 62 or 50)
		frame:Show()
		return
	end

	-- objectives (right-click folds them; then a line says how many are hidden)
	local all = QL.ObjectiveRows(id, ctx)
	local folded = QL.DB().currentCollapsed and #all > 0
	local rows = folded and {} or all
	-- getting there: a line when the quest is in another zone or on another continent
	local trip = QL.TripFor and QL.TripFor(id, ctx)
	local wayOff = 0
	if trip then
		frame.way.text:SetText(L("Way: ") .. (QL.TripSummary(trip) or ""))
		frame.way.trip = trip
		frame.way:Show()
		wayOff = 18
	else
		frame.way:Hide(); frame.way.trip = nil
	end
	frame.sep:ClearAllPoints()
	frame.sep:SetPoint("TOPLEFT", 14, -74 - wayOff); frame.sep:SetPoint("TOPRIGHT", -14, -74 - wayOff)
	frame.foldHint:ClearAllPoints()
	frame.foldHint:SetPoint("TOPLEFT", 14, -74 - wayOff)
	frame.foldHint:SetShown(folded)
	if folded then frame.foldHint:SetText(L("%d objectives hidden · right-click: show"):format(#all)) end
	local y = -82 - wayOff
	for i, o in ipairs(rows) do
		local r = frame.rows[i]
		if not r then r = newRow(); frame.rows[i] = r end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, y)
		r:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
		r:Show()
		local done = o.done
		r.text:SetText(o.text or "")
		r.text:SetTextColor(unpack(done and C.muted or C.text))
		local g = T.STATUS.done
		if done then
			r.dot:SetTexture("Interface\\AddOns\\QuestLineage\\Media\\disc")
			r.dot:SetVertexColor(g[1], g[2], g[3], 1)
		else
			r.dot:SetTexture("Interface\\AddOns\\QuestLineage\\Media\\ring")
			r.dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
		end
		if o.need and o.need > 0 then
			r.count:SetText(("%d/%d"):format(o.have or 0, o.need))
			r.count:SetTextColor(unpack(done and { g[1], g[2], g[3] } or C.text))
			r.bar:Show()
			r.bar:SetValue((o.have or 0) / o.need, done and g or nil)
		else
			r.count:SetText("")
			r.bar:Hide()
		end
		y = y - ROW_H
	end
	for i = #rows + 1, #frame.rows do frame.rows[i]:Hide() end
	for _, f in ipairs(flashes or {}) do
		if f[1] == id and frame.rows[f[2]] then frame.rows[f[2]].flashT = 1.2 end
	end
	frame.sep:SetShown(#rows > 0)
	y = y + (#rows > 0 and -4 or (folded and -6 or 10))
	y = drawLog(y, ctx, id)
	frame:SetHeight(-y + 8)
	frame:Show()
end

-- The zone tab: a small tab on the window's top edge naming the zone you are in and its level band
-- (from the zone's quests, QL.ZoneLevels). The band's colour says how it sits against your level:
-- teal when you are inside it, the quests' difficulty colour when you are below (orange/red) or above
-- (green/grey); a thin line along the bottom shows where you stand in it.

function QL.BuildZoneTab()
	local T, C = QL.Theme, QL.Theme.HUD
	local tab = CreateFrame("Frame", nil, frame)
	tab:SetHeight(22)
	tab:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, -1)
	tab:EnableMouse(true)
	tab:RegisterForDrag("LeftButton")
	tab:SetScript("OnDragStart", function() startMove() end)
	tab:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); savePoint() end)
	T.Fill(tab, { QL.Theme.PanelA(0.94) })
	T.Border(tab, C.line)
	tab.pin = tab:CreateTexture(nil, "ARTWORK")
	tab.pin:SetTexture("Interface\\AddOns\\QuestLineage\\Media\\disc")
	tab.pin:SetSize(7, 7)
	tab.pin:SetPoint("LEFT", 10, 0)
	tab.name = T.Text(tab, 11, C.text, nil, true)
	tab.name:SetPoint("LEFT", tab.pin, "RIGHT", 6, 0)
	tab.range = T.Text(tab, 11, C.accent, nil, true)
	tab.range:SetPoint("LEFT", tab.name, "RIGHT", 9, 0)
	tab.line = tab:CreateTexture(nil, "OVERLAY", nil, 5)
	tab.line:SetTexture(T.WHITE)
	tab.line:SetPoint("BOTTOMLEFT", 1, 1)
	tab.line:SetHeight(2)
	tab:SetScript("OnEnter", function(self)
		if not self.zoneName then return end
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_SIDE", frame)
		tip:AddLine(self.zoneName, 1, 1, 1)
		if self.lo then
			tip:AddLine(L("Quest levels here: %d–%d"):format(self.lo, self.hi), 0.75, 0.8, 0.85)
			tip:AddLine(L("from %d quests of this zone"):format(self.count or 0), 0.5, 0.55, 0.6)
			tip:AddLine(L(self.relation or ""), self.rr or 1, self.rg or 1, self.rb or 1)
		else
			tip:AddLine(L("No level data for this zone"), 0.5, 0.55, 0.6)
		end
		tip:Show()
	end)
	tab:SetScript("OnLeave", function() QL.Tip():Hide() end)
	tab:Hide()
	frame.zoneTab = tab
end

function QL.RefreshZoneTab(ctx)
	local tab = frame and frame.zoneTab
	if not tab then return end
	if QL.DB().currentZoneTab == false or not frame:IsShown() then tab:Hide(); return end
	local area, _, name = QL.PlayerZone()
	if type(name) ~= "string" or name == "" then tab:Hide(); return end
	ctx = ctx or QL.Context()
	local T, C = QL.Theme, QL.Theme.HUD
	local lo, hi, count
	if area then lo, hi, count = QL.ZoneLevels(area, ctx) end
	tab.zoneName, tab.lo, tab.hi, tab.count = name, lo, hi, count
	tab.name:SetText(name)
	local c, relation = C.accent, "You are within this band"
	local level = ctx.level
	if lo and level then
		if level < lo then
			local _, dc = QL.QuestDifficulty(lo, level)
			c, relation = dc or C.accent, "Above your level: quests here are hard for you"
		elseif level > hi then
			local _, dc = QL.QuestDifficulty(hi, level)
			c, relation = dc or C.muted, "Below your level: quests here are easy for you"
		end
	end
	tab.relation, tab.rr, tab.rg, tab.rb = relation, c[1], c[2], c[3]
	tab.pin:SetVertexColor(c[1], c[2], c[3], 1)
	-- the language tab and the lock take the right end of the edge: the zone tab stays clear of them
	local room = W - 82 - 4
	local rangeW = 0
	if lo then
		tab.range:SetText(lo == hi and L("Lv %d"):format(lo) or L("Lv %d–%d"):format(lo, hi))
		rangeW = 9 + (tab.range:GetStringWidth() or 0)
	end
	local nameW = tab.name:GetStringWidth() or 0
	local nameMax = math.max(40, room - (10 + 7 + 6 + 14) - rangeW)
	if nameW > nameMax then nameW = nameMax end
	tab.name:SetWidth(nameW)
	local width = 10 + 7 + 6 + nameW + 14
	if lo then
		tab.range:SetTextColor(c[1], c[2], c[3], 1)
		tab.range:Show()
		width = width + rangeW
		local f = (level and hi > lo) and math.max(0, math.min(1, (level - lo) / (hi - lo))) or (level and level >= lo and 1 or 0)
		tab.line:SetVertexColor(c[1], c[2], c[3], 0.9)
		tab.line:SetWidth(math.max(0.01, (width - 2) * f))
		tab.line:SetShown(f > 0)
	else
		tab.range:Hide()
		tab.line:Hide()
	end
	tab:SetWidth(width)
	tab:Show()
end

local refreshCurrentInner = QL.RefreshCurrent
function QL.RefreshCurrent(flashes)
	refreshCurrentInner(flashes)
	if frame then pcall(QL.RefreshZoneTab) end
end

-- How far a logged quest is: { done, total (objectives), fraction, percent } from its objective
-- rows; a counter counts by its units (3 of 5 ribs = 3/5), one without a counter as 0 or 1. A
-- quest the game calls complete is 100%. nil for a quest with nothing to count that is not done.
function QL.QuestCompletion(id, ctx)
	ctx = ctx or QL.Context()
	local rows = QL.ObjectiveRows(id, ctx) or {}
	local have, need, done = 0, 0, 0
	for _, o in ipairs(rows) do
		if o.need and o.need > 0 then
			need = need + o.need
			have = have + math.min(o.have or 0, o.need)
		else
			need = need + 1
			have = have + (o.done and 1 or 0)
		end
		-- a full counter counts as done even when the client has not flagged it yet
		if o.done or (o.need and o.need > 0 and (o.have or 0) >= o.need) then done = done + 1 end
	end
	local complete = ctx.complete and ctx.complete[id]
	if #rows == 0 then
		if not complete then return nil end
		return { done = 1, total = 1, fraction = 1, percent = 100 }
	end
	local fraction = complete and 1 or (need > 0 and have / need or 0)
	if complete then done = #rows end
	return { done = done, total = #rows, fraction = fraction, percent = math.floor(fraction * 100 + 0.5) }
end

-- The game's own quest tracker ----------------------------------------------------------------------

local GAME_TRACKERS = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }
local hookedTrackers = {}
local pendingTracker = false

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- Hidden for good: outside combat the tracker moves under a hidden frame (a Show from the game then
-- draws nothing); in combat, where that is not allowed, it only goes see-through (alpha is never
-- protected), and the move waits for PLAYER_REGEN_ENABLED. The game shows its tracker on every
-- quest update, kills in combat included, which made it pop up while hidden.
local hiddenParent
local function getHiddenParent()
	if not hiddenParent and CreateFrame then
		hiddenParent = CreateFrame("Frame", nil, UIParent)
		hiddenParent:Hide()
	end
	return hiddenParent
end

local function silence(f)
	pcall(f.SetAlpha, f, 0)
	if inCombat() then pendingTracker = true; return end
	local hp = getHiddenParent()
	if hp and f.SetParent and f.GetParent then
		local ok, p = pcall(f.GetParent, f)
		if ok and p ~= hp then
			f.qlParent, f.qlMoved = p, true
			pcall(f.SetParent, f, hp)
		end
	end
	pcall(f.Hide, f)
end

local function restore(f, name)
	if inCombat() then pendingTracker = true; return end
	if f.qlMoved and f.SetParent then pcall(f.SetParent, f, f.qlParent or UIParent) end
	f.qlParent, f.qlMoved = nil, nil
	pcall(f.SetAlpha, f, 1)
	pcall(f.Show, f)
	if name == "ObjectiveTrackerFrame" and ObjectiveTracker_Update then pcall(ObjectiveTracker_Update) end
	if name == "QuestWatchFrame" and QuestWatch_Update then pcall(QuestWatch_Update) end
end

function QL.ApplyGameTracker()
	pendingTracker = false
	local hide = QL.DB().hideGameTracker == true
	for _, name in ipairs(GAME_TRACKERS) do
		local f = _G[name]
		if type(f) == "table" and f.Hide then
			if not hookedTrackers[name] and f.HookScript then
				hookedTrackers[name] = true
				-- the game shows it again on quest changes: silence it again at once
				pcall(f.HookScript, f, "OnShow", function(self)
					if QL.DB().hideGameTracker == true then silence(self) end
				end)
			end
			if hide then
				silence(f)
				f.wasHiddenByQL = true
			elseif f.wasHiddenByQL then
				restore(f, name)
				if not pendingTracker then f.wasHiddenByQL = false end
			end
		end
	end
end

-- trackers that load later (load-on-demand) and quest-watch changes get the same treatment
QL.Event("ADDON_LOADED", function() if QL.DB().hideGameTracker == true then pcall(QL.ApplyGameTracker) end end)
QL.Event("QUEST_WATCH_UPDATE", function() if QL.DB().hideGameTracker == true then pcall(QL.ApplyGameTracker) end end)

QL.Event("PLAYER_REGEN_ENABLED", function() if pendingTracker then pcall(QL.ApplyGameTracker) end end)
function QL.ApplyCurrentScale()
	if not frame then return end
	local pct = tonumber(QL.DB().currentScale) or 100
	frame:SetScale(math.max(0.6, math.min(1.6, pct / 100)))
end

QL.On("SETTING_CHANGED", function(key)
	if key == "hideGameTracker" then pcall(QL.ApplyGameTracker) end
	if key == "currentScale" then pcall(QL.ApplyCurrentScale) end
end)

QL.Event("PLAYER_LOGIN", function()
	-- the game's tracker is now hidden by default; saved settings from before (where the old
	-- default "shown" was written in) switch over once
	local db = QL.DB()
	if not db.trackerDefaultHidden then
		db.trackerDefaultHidden = true
		db.hideGameTracker = true
	end
	pcall(QL.ApplyGameTracker)
	local ok, err = pcall(build)
	if not ok then QL.Debug("current quest: " .. tostring(err)); return end
	pcall(watchProgress)
	if C_Timer and C_Timer.After then C_Timer.After(2, function() pcall(QL.RefreshCurrent) end) end
end)

-- A quest you accept becomes the current quest (setting acceptedCurrent): the arrow turns to it,
-- since the window follows the arrow's quest. Left alone while a route runs or the arrow points at
-- your corpse.
QL.Event("QUEST_ACCEPTED", function(_, a, b)
	local id = type(b) == "number" and b or a
	if type(id) ~= "number" or id <= 0 then return end
	lastProgress = id
	if QL.DB().acceptedCurrent == false then return end
	if QL.RouteActive and QL.RouteActive() then return end
	local t = QL.ArrowTarget and QL.ArrowTarget()
	if t and t.corpse then return end
	if QL.SetArrowTarget then pcall(QL.SetArrowTarget, id, true) end
	pcall(QL.RefreshCurrent)
end)

QL.On("STATE_CHANGED", function()
	local ok, flashes = pcall(watchProgress)
	local ok2, err = pcall(QL.RefreshCurrent, ok and flashes or nil)
	if not ok2 then QL.Debug("current quest: " .. tostring(err)) end
end)
for _, m in ipairs({ "ARROW_CHANGED", "SETTING_CHANGED", "ROUTE_CHANGED", "INDEX_READY" }) do
	QL.On(m, function() pcall(QL.RefreshCurrent) end)
end
