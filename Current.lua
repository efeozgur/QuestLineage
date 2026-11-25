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
function QL.ObjectiveRows(id, ctx)
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

local function savePoint()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	QL.DB().currentPoint = { point, relPoint, x, y }
end

local function newRow()
	local T, C = QL.Theme, QL.Theme.C
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
	local T, C = QL.Theme, QL.Theme.C
	frame = CreateFrame("Button", "QuestLineageCurrent", UIParent)
	frame:SetWidth(W)
	frame:SetHeight(80)
	local p = QL.DB().currentPoint
	if type(p) == "table" and p[1] then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120) end
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePoint() end)
	frame:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			QL.Set("currentCollapsed", not QL.DB().currentCollapsed)
		elseif self.questId then
			QL.Open(self.questId)
		end
	end)
	T.Fill(frame, { 0.055, 0.063, 0.082, 0.92 })
	T.Border(frame, C.line)
	local top = frame:CreateTexture(nil, "ARTWORK")
	top:SetTexture(T.WHITE)
	top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1)
	top:SetHeight(2)
	T.Gradient(top, "HORIZONTAL", C.accent, C.accent2)
	frame.label = T.Text(frame, 10, C.accent, nil, true)
	frame.label:SetPoint("TOPLEFT", 14, -12)
	frame.meta = T.Text(frame, 11, C.muted)
	frame.meta:SetPoint("TOPRIGHT", -14, -12)
	frame.meta:SetJustifyH("RIGHT")
	frame.title = T.Text(frame, 15, C.text, nil, true)
	frame.title:SetPoint("TOPLEFT", 14, -28)
	frame.title:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
	frame.stateDot = frame:CreateTexture(nil, "ARTWORK")
	frame.stateDot:SetTexture("Interface\\AddOns\\QuestLineage\\Media\\disc")
	frame.stateDot:SetSize(7, 7)
	frame.stateDot:SetPoint("TOPLEFT", 14, -53)
	frame.state = T.Text(frame, 11, C.muted)
	frame.state:SetPoint("LEFT", frame.stateDot, "RIGHT", 7, 0)
	frame.state:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
	frame.sep = frame:CreateTexture(nil, "BORDER")
	frame.sep:SetTexture(T.WHITE)
	frame.sep:SetPoint("TOPLEFT", 14, -68); frame.sep:SetPoint("TOPRIGHT", -14, -68)
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
	head:SetScript("OnClick", function() QL.Set("currentLogCollapsed", not QL.DB().currentLogCollapsed) end)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() frame:StartMoving() end)
	head:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); savePoint() end)
	head:Hide()
	frame.logHead = head
	frame.logMore = T.Text(frame, 10, C.dim)
	frame.logMore:Hide()
	frame:SetScript("OnEnter", function(self)
		if not self.questId then return end
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_LEFT")
		QL.FillQuestTooltip(tip, self.questId)
		tip:AddLine(L("Click: open · Right-click: fold · Drag: move"), 0.5, 0.5, 0.5)
		tip:Show()
	end)
	frame:SetScript("OnLeave", function() QL.Tip():Hide() end)
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

-- The log list -----------------------------------------------------------------------------------------

local LOG_ROW_H, LOG_MAX = 36, 15

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
local function summary(id, ctx)
	local rows = QL.ObjectiveRows(id, ctx)
	local have, need, first = 0, 0, nil
	for _, o in ipairs(rows) do
		if o.need and o.need > 0 then have = have + math.min(o.have or 0, o.need); need = need + o.need end
		if not first and not o.done then first = o end
	end
	return first, need > 0 and (have / need) or nil
end

local function logRow(i)
	local T, C = QL.Theme, QL.Theme.C
	local r = frame.logRows[i]
	if r then return r end
	r = CreateFrame("Button", nil, frame)
	r:SetHeight(LOG_ROW_H)
	r.bg = T.Fill(r, { 0, 0, 0, 0 })
	r.title = T.Text(r, 12, C.text)
	r.title:SetPoint("TOPLEFT", 14, -4)
	r.title:SetPoint("RIGHT", r, "RIGHT", -64, 0)
	r.right = T.Text(r, 11, C.muted, nil, true)
	r.right:SetPoint("TOPRIGHT", -14, -5)
	r.right:SetJustifyH("RIGHT")
	r.sub = T.Text(r, 10, C.muted)
	r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -2)
	r.sub:SetPoint("RIGHT", r, "RIGHT", -14, 0)
	r.bar = T.Bar(r, 2)
	r.bar:SetPoint("BOTTOMLEFT", 14, 3)
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
		tip:SetOwner(self, "ANCHOR_LEFT")
		QL.FillQuestTooltip(tip, self.questId)
		tip:AddLine(L("Click: make it current · Right-click: open"), 0.5, 0.5, 0.5)
		tip:Show()
	end)
	r:SetScript("OnLeave", function(self) T.Color(self.bg, { 0, 0, 0, 0 }); QL.Tip():Hide() end)
	-- dragging a row moves the window
	r:RegisterForDrag("LeftButton")
	r:SetScript("OnDragStart", function() frame:StartMoving() end)
	r:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); savePoint() end)
	frame.logRows[i] = r
	return r
end

local function drawLog(y, ctx, currentId)
	local T, C = QL.Theme, QL.Theme.C
	local ids = QL.LogQuests(ctx, currentId)
	local head = frame.logHead
	for _, r in ipairs(frame.logRows) do r:Hide() end
	frame.logMore:Hide()
	if #ids == 0 then head:Hide(); return y end
	head:ClearAllPoints()
	head:SetPoint("TOPLEFT", 0, y)
	head:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
	local folded = QL.DB().currentLogCollapsed
	head.text:SetText(L("QUESTS") .. "  " .. T.Hex(C.muted) .. #ids .. "|r")
	head.fold:SetText(folded and "+" or "–")
	head:Show()
	y = y - 26
	if folded then return y end
	local ready = T.STATUS.done
	for i, id in ipairs(ids) do
		if i > LOG_MAX then
			frame.logMore:ClearAllPoints()
			frame.logMore:SetPoint("TOPLEFT", 14, y - 2)
			frame.logMore:SetText(L("+%d more"):format(#ids - LOG_MAX))
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
		local first, frac = summary(id, ctx)
		if isReady then
			r.right:SetText(L("Ready"))
			r.right:SetTextColor(ready[1], ready[2], ready[3], 1)
			local who = QL.QuestFinisher(id)
			r.sub:SetText(who and (L("Turn in: ") .. who.name) or "")
		else
			local level = QL.QuestLevel(id)
			r.right:SetText(level and QL.LevelMarkup(id, ctx) or "")
			r.right:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)
			r.sub:SetText(first and (first.text or "") or "")
		end
		if frac and not isReady then
			r.bar:Show()
			r.bar:SetValue(frac)
		else
			r.bar:Hide()
		end
		r:Show()
		y = y - LOG_ROW_H
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

function QL.RefreshCurrent(flashes)
	if not frame then return end
	if QL.DB().currentQuest == false then frame:Hide(); return end
	local ctx = QL.Context()
	local id = QL.CurrentQuest(ctx)
	local T, C = QL.Theme, QL.Theme.C
	local currentParts = { frame.label, frame.meta, frame.title, frame.stateDot, frame.state }
	if not id then
		-- no current quest: the window shows the log alone (or nothing when the log is empty)
		frame.questId = nil
		for _, p in ipairs(currentParts) do p:Hide() end
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

	-- objectives
	local rows = QL.DB().currentCollapsed and {} or QL.ObjectiveRows(id, ctx)
	local y = -76
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
	y = y + (#rows > 0 and -4 or 10)
	y = drawLog(y, ctx, id)
	frame:SetHeight(-y + 8)
	frame:Show()
end

-- The game's own quest tracker ----------------------------------------------------------------------

local GAME_TRACKERS = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }
local hookedTrackers = {}
local pendingTracker = false

local function inCombat() return InCombatLockdown and InCombatLockdown() end

function QL.ApplyGameTracker()
	if inCombat() then pendingTracker = true; return end
	pendingTracker = false
	local hide = QL.DB().hideGameTracker == true
	for _, name in ipairs(GAME_TRACKERS) do
		local f = _G[name]
		if type(f) == "table" and f.Hide then
			if not hookedTrackers[name] and f.HookScript then
				hookedTrackers[name] = true
				-- the game shows it again on quest changes: hide it again (outside combat)
				pcall(f.HookScript, f, "OnShow", function(self)
					if QL.DB().hideGameTracker == true then
						if inCombat() then pendingTracker = true else self:Hide() end
					end
				end)
			end
			if hide then
				pcall(f.Hide, f)
			elseif f.wasHiddenByQL then
				pcall(f.Show, f)
				if name == "ObjectiveTrackerFrame" and ObjectiveTracker_Update then pcall(ObjectiveTracker_Update) end
				if name == "QuestWatchFrame" and QuestWatch_Update then pcall(QuestWatch_Update) end
			end
			f.wasHiddenByQL = hide
		end
	end
end

QL.Event("PLAYER_REGEN_ENABLED", function() if pendingTracker then pcall(QL.ApplyGameTracker) end end)
QL.On("SETTING_CHANGED", function(key) if key == "hideGameTracker" then pcall(QL.ApplyGameTracker) end end)

QL.Event("PLAYER_LOGIN", function()
	pcall(QL.ApplyGameTracker)
	local ok, err = pcall(build)
	if not ok then QL.Debug("current quest: " .. tostring(err)); return end
	pcall(watchProgress)
	if C_Timer and C_Timer.After then C_Timer.After(2, function() pcall(QL.RefreshCurrent) end) end
end)

QL.Event("QUEST_ACCEPTED", function(_, a, b)
	local id = type(b) == "number" and b or a
	if type(id) == "number" and id > 0 then lastProgress = id end
end)

QL.On("STATE_CHANGED", function()
	local ok, flashes = pcall(watchProgress)
	local ok2, err = pcall(QL.RefreshCurrent, ok and flashes or nil)
	if not ok2 then QL.Debug("current quest: " .. tostring(err)) end
end)
for _, m in ipairs({ "ARROW_CHANGED", "SETTING_CHANGED", "ROUTE_CHANGED", "INDEX_READY" }) do
	QL.On(m, function() pcall(QL.RefreshCurrent) end)
end
