-- Quest actions: a small panel for the current quest with
--   item buttons   the items the quest has you use (the client's own quest item first, then the
--                  database's: the item the quest hands you, items it needs as a source, objective
--                  items with a "Use:" spell), only those in your bags; click or bind a key
--   targets        the creatures its unfinished objectives still need, and for an item the creatures
--                  that drop it (those in your zone first, at most 2 per item), with the counter; a
--                  click targets it (/targetexact)
-- They are secure buttons: the game lets them change only outside combat, so a change asked for in
-- combat waits for PLAYER_REGEN_ENABLED. Counters and cooldowns still update in combat.
--
-- Setting questActions (on); the panel moves by its header or with Shift+drag on a button
-- (questActionsPoint). Key bindings (Bindings.xml): the first item button and the first target.
--   QL.QuestUseItems(id) -> { itemId, ... }      QL.QuestTargetRows(id, ctx) -> { {npc, name, have, need}, ... }
--   QL.RefreshQuestActions()                     test hook QL.questActionsShown = { items, targets }

local _, QL = ...
QL = QL or {}

local MAX_ITEMS, MAX_TARGETS = 3, 4
local frame, pending -- the panel; a refresh asked for in combat

local function L(s) return QL.L and QL.L(s) or s end

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c
end

local function itemCount(item)
	local n = call(rawget(_G, "GetItemCount"), item)
	if n == nil and C_Item then n = call(C_Item.GetItemCount, item) end
	return tonumber(n) or 0
end

-- does the item have a "Use:" spell
local function usable(item)
	local spell = call(rawget(_G, "GetItemSpell"), item)
	if spell == nil and C_Item then spell = call(C_Item.GetItemSpell, item) end
	return spell ~= nil
end

local function inCombat() return (call(rawget(_G, "InCombatLockdown"))) and true or false end

-- Data -------------------------------------------------------------------------------------------

function QL.QuestUseItems(id)
	local out, seen = {}, {}
	if not id then return out end
	local function add(item, check)
		if type(item) ~= "number" or item <= 0 or seen[item] or #out >= MAX_ITEMS then return end
		seen[item] = true
		if itemCount(item) > 0 and (not check or usable(item)) then out[#out + 1] = item end
	end
	-- the client's own quest item (the one the quest log shows a button for)
	local index = QL.QuestLogIndex and QL.QuestLogIndex(id)
	if index then
		local link = call(rawget(_G, "GetQuestLogSpecialItemInfo"), index)
		if type(link) == "string" then add(tonumber(link:match("item:(%d+)"))) end
	end
	-- the database: what the quest hands you, what it needs as a source, its objective items
	for _, item in ipairs(QL.Ids(QL.Q(id, "sourceItemId"))) do add(item, true) end
	for _, item in ipairs(QL.Ids(QL.Q(id, "requiredSourceItems"))) do add(item, true) end
	local obj = QL.Q(id, "objectives")
	if type(obj) == "table" and type(obj[3]) == "table" then
		for _, e in ipairs(obj[3]) do add(type(e) == "table" and e[1] or e, true) end
	end
	return out
end

local DROPPERS_PER_ITEM = 2

-- the creatures that drop an item, those in the player's zone first (database order otherwise)
local function droppers(item)
	local list = QL.ItemDroppers and QL.ItemDroppers(item) or QL.Ids(QL.I(item, "npcDrops"))
	local here = QL.PlayerZone and QL.PlayerZone()
	if not here then return list end
	local near, far = {}, {}
	for _, npc in ipairs(list) do
		local zone = QL.N(npc, "zoneID")
		if zone == here or (zone and QL.TopArea and QL.TopArea(zone) == here) then near[#near + 1] = npc else far[#far + 1] = npc end
	end
	for _, npc in ipairs(far) do near[#near + 1] = npc end
	return near
end

function QL.QuestTargetRows(id, ctx)
	local out, seen = {}, {}
	if not id or not QL.ObjectiveRows then return out end
	local function add(npc, row, item)
		local name = npc and QL.N(npc, "name")
		if #out < MAX_TARGETS and type(name) == "string" and not seen[name] then
			seen[name] = true
			out[#out + 1] = { npc = npc, name = name, have = row.have, need = row.need, item = item }
			return true
		end
	end
	local rows = QL.ObjectiveRows(id, ctx)
	-- creatures to kill or talk to first, then the droppers of the items
	for _, row in ipairs(rows) do
		local t = row.task
		if t and not row.done and t.kind == "npc" then add(t.id, row) end
	end
	for _, row in ipairs(rows) do
		local t = row.task
		if t and not row.done and t.kind == "item" then
			local n = 0
			for _, npc in ipairs(droppers(t.id)) do
				if n >= DROPPERS_PER_ITEM then break end
				if add(npc, row, t.id) then n = n + 1 end
			end
		end
	end
	return out
end

-- /ql actions: why the panel shows what it shows
function QL.QuestActionsDebug()
	local chat = QL.Chat or print
	local db = QL.DB()
	local ctx = QL.Context and QL.Context()
	local q = QL.CurrentQuest and QL.CurrentQuest(ctx)
	chat("setting questActions: " .. tostring(db.questActions ~= false))
	chat("current quest: " .. tostring(q) .. (q and (" " .. tostring(QL.QuestTitle and QL.QuestTitle(q))) or "") .. " · in log: " .. tostring(q and ctx and ctx.log and ctx.log[q] or false))
	if q then
		for i, row in ipairs(QL.ObjectiveRows(q, ctx)) do
			local t = row.task
			chat(("  objective %d: %s · done %s · task %s %s"):format(i, tostring(row.text), tostring(row.done), tostring(t and t.kind), tostring(t and t.id)))
		end
		chat("  items: " .. table.concat(QL.QuestUseItems(q), ", "))
		for _, t in ipairs(QL.QuestTargetRows(q, ctx)) do chat("  target: " .. t.name .. (t.item and (" (drops " .. t.item .. ")") or "")) end
	end
	local f = rawget(_G, "QuestLineageQuestActions")
	chat("panel: " .. (f and (f:IsShown() and "shown" or "hidden") or "not built") .. (pending and " · waiting for combat to end" or ""))
end

-- The panel --------------------------------------------------------------------------------------

local ITEM, ROW_H, PAD, PIC = 34, 30, 6, 26

local function savePoint()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	QL.DB().questActionsPoint = { point, relPoint, x, y }
end
local function startMove() if not inCombat() then frame:StartMoving() end end
local function stopMove() frame:StopMovingOrSizing(); savePoint() end
-- buttons click: only Shift+drag moves the panel from them
local function shiftMove(b)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function() if IsShiftKeyDown and IsShiftKeyDown() then startMove() end end)
	b:SetScript("OnDragStop", stopMove)
end

local function secureButton(name, w, h)
	local b = CreateFrame("Button", name, frame, "SecureActionButtonTemplate")
	b:SetSize(w, h)
	-- modern clients fire a bound key on the press or the release (ActionButtonUseKeyDown)
	if not pcall(b.RegisterForClicks, b, "AnyUp", "AnyDown") then pcall(b.RegisterForClicks, b, "AnyUp") end
	shiftMove(b)
	return b
end

local function build()
	local T, C = QL.Theme, QL.Theme.HUD
	frame = CreateFrame("Frame", "QuestLineageQuestActions", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", startMove)
	frame:SetScript("OnDragStop", stopMove)
	local p = QL.DB().questActionsPoint
	if type(p) == "table" and p[1] then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("RIGHT", UIParent, "RIGHT", -260, -40)
	end
	frame.bg = T.Fill(frame, { T.PanelA(0.88) })
	T.Border(frame, C.line)
	frame.title = T.Text(frame, 10, C.muted, nil, true)
	frame.title:SetPoint("TOPLEFT", PAD, -PAD)
	frame.title:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	frame.title:SetJustifyH("LEFT")

	frame.items = {}
	for i = 1, MAX_ITEMS do
		local b = secureButton("QuestLineageItemButton" .. i, ITEM, ITEM)
		b:SetAttribute("type", "item")
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		T.Border(b, C.line)
		b.count = T.Text(b, 10, C.text, "OVERLAY", true)
		b.count:SetPoint("BOTTOMRIGHT", -2, 2)
		b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
		b.cd:SetAllPoints()
		b.hl = b:CreateTexture(nil, "HIGHLIGHT")
		b.hl:SetAllPoints()
		b.hl:SetTexture(T.WHITE)
		b.hl:SetVertexColor(1, 1, 1, 0.12)
		-- items are the game's: its own tooltip draws them
		b:SetScript("OnEnter", function(self)
			if not (self.item and GameTooltip) then return end
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			pcall(GameTooltip.SetItemByID, GameTooltip, self.item)
			GameTooltip:AddLine(L("Click: use it · Shift+drag: move"), 0.24, 0.84, 0.78)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		b:Hide()
		frame.items[i] = b
	end

	frame.targets = {}
	for i = 1, MAX_TARGETS do
		local b = secureButton("QuestLineageTargetButton" .. i, 180, ROW_H)
		b:SetAttribute("type", "macro")
		b.bg = T.Fill(b, { 1, 1, 1, 0 })
		-- the creature's face (a frozen 3D portrait), the quest mark when the client has no model
		b.pic = CreateFrame("Frame", nil, b)
		b.pic:SetSize(PIC, PIC)
		b.pic:SetPoint("LEFT", 2, 0)
		T.Fill(b.pic, C.canvas)
		T.Border(b.pic, C.line)
		b.mark = b.pic:CreateTexture(nil, "ARTWORK")
		b.mark:SetTexture("Interface\\AddOns\\QuestLineage\\Media\\quest_mark")
		b.mark:SetSize(14, 14)
		b.mark:SetPoint("CENTER")
		b.model = QL.NewCreatureModel and QL.NewCreatureModel(b.pic)
		if b.model then b.model:SetPoint("TOPLEFT", 1, -1); b.model:SetPoint("BOTTOMRIGHT", -1, 1) end
		-- an item to collect: its icon in the portrait's corner
		b.itemIcon = b:CreateTexture(nil, "OVERLAY")
		b.itemIcon:SetSize(13, 13)
		b.itemIcon:SetPoint("BOTTOMRIGHT", b.pic, "BOTTOMRIGHT", 3, -3)
		b.itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.name = T.Text(b, 11, C.text)
		b.name:SetPoint("LEFT", b.pic, "RIGHT", 6, 0)
		b.name:SetPoint("RIGHT", b, "RIGHT", -46, 0)
		b.name:SetJustifyH("LEFT")
		b.counter = T.Text(b, 10, C.muted)
		b.counter:SetPoint("RIGHT", -4, 0)
		b:SetScript("OnEnter", function(self)
			self.bg:SetVertexColor(1, 1, 1, 0.06)
			local tip = QL.Tip()
			tip:SetOwner(self, "ANCHOR_LEFT")
			tip:AddLine(self.label or "?", 1, 1, 1)
			if self.itemName then tip:AddLine(L("Drops: ") .. self.itemName, 0.85, 0.85, 0.85) end
			tip:AddLine(L("Click: target it (when it is near) · Shift+drag: move"), 0.24, 0.84, 0.78)
			tip:Show()
		end)
		b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(1, 1, 1, 0); QL.Tip():Hide() end)
		b:Hide()
		frame.targets[i] = b
	end
	frame:Hide()
end

local function updateCounts()
	if not frame then return end
	for _, b in ipairs(frame.items) do
		if b.item then
			local n = itemCount(b.item)
			b.count:SetText(n > 1 and tostring(n) or "")
			local start, dur, enable = call(rawget(_G, "GetItemCooldown"), b.item)
			if start == nil and C_Container then start, dur, enable = call(C_Container.GetItemCooldown, b.item) end
			if b.cd.SetCooldown and type(start) == "number" and type(dur) == "number" then
				pcall(b.cd.SetCooldown, b.cd, start, dur)
			end
		end
	end
end

local function layout()
	if not frame then build() end
	local db = QL.DB()
	local ctx = QL.Context and QL.Context()
	local q = db.questActions ~= false and QL.CurrentQuest and QL.CurrentQuest(ctx) or nil
	q = (q and ctx and ctx.log and ctx.log[q]) and q or nil
	local items = q and QL.QuestUseItems(q) or {}
	local targets = q and QL.QuestTargetRows(q, ctx) or {}
	QL.questActionsShown = { items = items, targets = targets, quest = q }
	if #items == 0 and #targets == 0 then frame:Hide(); return end

	frame.title:SetText(QL.QuestTitle and QL.QuestTitle(q) or ("#" .. q))
	local y = PAD + 16
	for i, b in ipairs(frame.items) do
		local item = items[i]
		b.item = item
		if item then
			b:SetAttribute("item", "item:" .. item)
			b.icon:SetTexture(QL.ItemIcon and QL.ItemIcon(item) or "Interface\\Icons\\INV_Misc_QuestionMark")
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) * (ITEM + 4), -y)
			b:Show()
		else
			b:SetAttribute("item", nil)
			b:Hide()
		end
	end
	if #items > 0 then y = y + ITEM + 6 end
	for i, b in ipairs(frame.targets) do
		local t = targets[i]
		if t then
			b.label = t.name
			b.itemName = t.item and QL.I(t.item, "name") or nil
			b:SetAttribute("macrotext", "/targetexact " .. t.name)
			b.name:SetText(t.name)
			local face = b.model and t.npc and QL.SetCreatureModel(b.model, t.npc, 1.05, true)
			if b.model and not face then b.model:Hide(); b.model.npcId = nil end
			b.mark:SetShown(not face)
			local icon = t.item and QL.ItemIcon and QL.ItemIcon(t.item)
			if icon then b.itemIcon:SetTexture(icon); b.itemIcon:Show() else b.itemIcon:Hide() end
			b.counter:SetText((t.need and t.need > 0) and ("%d/%d"):format(t.have or 0, t.need) or "")
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
			b:Show()
			y = y + ROW_H
		else
			b:SetAttribute("macrotext", nil)
			b:Hide()
		end
	end
	frame:SetSize(180 + PAD * 2, y + PAD)
	frame:Show()
	updateCounts()
end

function QL.RefreshQuestActions()
	if inCombat() then pending = true; return end
	pending = false
	local ok, err = pcall(layout)
	if not ok and QL.Debug then QL.Debug(err) end
end

-- the key binding names (Key Bindings > AddOns)
local function bindingNames()
	_G.BINDING_HEADER_QUESTLINEAGE = "QuestLineage"
	_G["BINDING_NAME_CLICK QuestLineageItemButton1:LeftButton"] = L("Use the quest item")
	_G["BINDING_NAME_CLICK QuestLineageTargetButton1:LeftButton"] = L("Target the quest's creature")
end
bindingNames()

local soon = false
local function refreshSoon()
	if soon then return end
	soon = true
	local function go() soon = false; QL.RefreshQuestActions() end
	if C_Timer and C_Timer.After then C_Timer.After(0.3, go) else go() end
end

QL.On("LOGIN", function() bindingNames(); QL.RefreshQuestActions() end)
QL.On("STATE_CHANGED", refreshSoon)
QL.On("ARROW_CHANGED", refreshSoon)
QL.On("SETTING_CHANGED", function(key)
	if key == "lang" then bindingNames() end
	if key == "questActions" or key == "lang" then QL.RefreshQuestActions() end
end)
QL.Event("BAG_UPDATE_DELAYED", refreshSoon)
QL.Event("BAG_UPDATE_COOLDOWN", updateCounts)
QL.Event("PLAYER_REGEN_ENABLED", function() if pending then QL.RefreshQuestActions() end end)
