-- Quest items: which of your quests need an item, so it is not sold or thrown away.
--   item tooltips   a line per logged quest that needs the item: the quest's title and your count
--                   (green once that objective is done), or "used for this quest" for an item the
--                   quest hands you or needs as a source (setting itemTooltip)
--   bag marks       a small quest mark on bag slots holding such an item (setting bagMarks); the
--                   game's own bag frames only (ContainerFrame1..13, the combined bag)
--   QL.ItemQuests(item, ctx) -> { {quest, have, need, done, use}, ... }   cached per context table
-- Only post-hooks; a mark is our own texture on the slot, hidden again when the item goes.

local _, QL = ...
QL = QL or {}

local MAX_LINES = 3
local function L(s) return QL.L and QL.L(s) or s end

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c
end

-- Which quests need which item ------------------------------------------------------------------

local cache = setmetatable({}, { __mode = "k" })

local function buildIndex(ctx)
	local byItem = {}
	local function add(item, entry)
		if type(item) ~= "number" then return end
		local list = byItem[item]
		if not list then list = {}; byItem[item] = list end
		for _, e in ipairs(list) do if e.quest == entry.quest then return end end
		list[#list + 1] = entry
	end
	local ids = {}
	for q in pairs(ctx.log or {}) do ids[#ids + 1] = q end
	table.sort(ids)
	for _, q in ipairs(ids) do
		for _, row in ipairs(QL.ObjectiveRows and QL.ObjectiveRows(q, ctx) or {}) do
			local t = row.task
			if t and t.kind == "item" then
				add(t.id, { quest = q, have = row.have, need = row.need, done = row.done and true or false })
			end
		end
		for _, item in ipairs(QL.Ids(QL.Q(q, "sourceItemId"))) do add(item, { quest = q, use = true }) end
		for _, item in ipairs(QL.Ids(QL.Q(q, "requiredSourceItems"))) do add(item, { quest = q, use = true }) end
	end
	return byItem
end

function QL.ItemQuests(item, ctx)
	ctx = ctx or (QL.Context and QL.Context())
	if type(ctx) ~= "table" or type(item) ~= "number" then return {} end
	local index = cache[ctx]
	if not index then index = buildIndex(ctx); cache[ctx] = index end
	return index[item] or {}
end

-- Tooltip lines -----------------------------------------------------------------------------------

local function hex(r, g, b) return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255) end

-- the lines for one item (pure enough to test): { text, ... }
function QL.ItemTooltipLines(item, ctx)
	local out = {}
	for _, e in ipairs(QL.ItemQuests(item, ctx)) do
		if #out >= MAX_LINES then break end
		local title = hex(0.5, 0.83, 1) .. (QL.QuestTitle and QL.QuestTitle(e.quest) or ("#" .. e.quest)) .. "|r"
		local tail
		if e.use then
			tail = hex(0.58, 0.62, 0.68) .. L("used for this quest") .. "|r"
		elseif e.done then
			tail = hex(0.4, 0.85, 0.5) .. L("done") .. "|r"
		elseif e.need and e.need > 0 then
			tail = hex(0.95, 0.8, 0.35) .. ("%d/%d"):format(e.have or 0, e.need) .. "|r"
		else
			tail = hex(0.95, 0.8, 0.35) .. L("needed") .. "|r"
		end
		out[#out + 1] = title .. "  " .. tail
	end
	return out
end

local function addItemLines(tooltip, item)
	if QL.DB().itemTooltip == false or not item then return 0 end
	local lines = QL.ItemTooltipLines(item)
	for _, text in ipairs(lines) do
		tooltip:AddLine(text, 0.85, 0.85, 0.85, true)
		if QL.StyleTooltipLine then QL.StyleTooltipLine(tooltip) end
	end
	return #lines
end

local function itemFromLink(link)
	return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function hookItemTooltips()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			if tooltip ~= GameTooltip and tooltip ~= rawget(_G, "ItemRefTooltip") then return end
			local item = data and tonumber(data.id)
			if not item and tooltip.GetItem then item = itemFromLink(select(2, tooltip:GetItem())) end
			local ok, err = pcall(addItemLines, tooltip, item)
			if not ok then QL.Debug("item tooltip: " .. tostring(err)) end
		end)
	elseif GameTooltip and GameTooltip.HookScript then
		local function onItem(tooltip)
			local item = tooltip.GetItem and itemFromLink(select(2, tooltip:GetItem()))
			local ok, added = pcall(addItemLines, tooltip, item)
			if ok and added and added > 0 then tooltip:Show() end
		end
		pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", onItem)
		local ref = rawget(_G, "ItemRefTooltip")
		if ref and ref.HookScript then pcall(ref.HookScript, ref, "OnTooltipSetItem", onItem) end
	end
end

-- Bag marks -----------------------------------------------------------------------------------------

local marks = setmetatable({}, { __mode = "k" }) -- slot button -> our texture

local function containerItem(bag, slot)
	if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
	local id = C_Container and call(C_Container.GetContainerItemID, bag, slot)
	if id == nil then id = call(rawget(_G, "GetContainerItemID"), bag, slot) end
	return tonumber(id)
end

local function setMark(button, entries)
	local m = marks[button]
	if not entries or #entries == 0 then
		if m then m:Hide() end
		return
	end
	if not m then
		m = button:CreateTexture(nil, "OVERLAY", nil, 7)
		m:SetTexture("Interface\\AddOns\\QuestLineage\\Media\\quest_mark")
		m:SetSize(14, 14)
		m:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
		marks[button] = m
	end
	local allDone = true
	for _, e in ipairs(entries) do if not e.done and not e.use then allDone = false end end
	if allDone then m:SetVertexColor(0.4, 0.85, 0.5, 1) else m:SetVertexColor(0.95, 0.8, 0.35, 1) end
	m:Show()
end

local function markFrame(frame, ctx, on)
	if type(frame) ~= "table" or not frame.IsShown or not frame:IsShown() then return 0 end
	local n = 0
	local function handle(button, bag)
		if type(button) ~= "table" then return end
		local slot = button.GetID and button:GetID()
		if type(button.GetBagID) == "function" then
			local b = call(button.GetBagID, button)
			if type(b) == "number" then bag = b end
		end
		local item = on and containerItem(bag, slot) or nil
		local entries = item and QL.ItemQuests(item, ctx) or nil
		setMark(button, entries)
		if entries and #entries > 0 then n = n + 1 end
	end
	local bag = frame.GetID and frame:GetID()
	local ok, iter, state, init = false, nil, nil, nil
	if type(frame.EnumerateValidItems) == "function" then ok, iter, state, init = pcall(frame.EnumerateValidItems, frame) end
	if ok and type(iter) == "function" then
		for _, button in iter, state, init do handle(button, bag) end
	else
		local name = frame.GetName and frame:GetName()
		for j = 1, 40 do
			local button = name and _G[name .. "Item" .. j]
			if not button then break end
			handle(button, bag)
		end
	end
	return n
end

function QL.RefreshBagMarks()
	local on = QL.DB().bagMarks ~= false
	local ctx = QL.Context and QL.Context()
	local n = 0
	for i = 1, 13 do n = n + markFrame(_G["ContainerFrame" .. i], ctx, on) end
	n = n + markFrame(rawget(_G, "ContainerFrameCombinedBags"), ctx, on)
	QL.bagMarksShown = n
	return n
end

local soon = false
local function refreshSoon()
	if soon then return end
	soon = true
	local function go()
		soon = false
		local ok, err = pcall(QL.RefreshBagMarks)
		if not ok then QL.Debug("bag marks: " .. tostring(err)) end
	end
	if C_Timer and C_Timer.After then C_Timer.After(0.05, go) else go() end
end

local function hookBags()
	if type(rawget(_G, "ContainerFrame_Update")) == "function" then pcall(hooksecurefunc, "ContainerFrame_Update", refreshSoon) end
	for i = 1, 13 do
		local f = _G["ContainerFrame" .. i]
		if f and f.HookScript then pcall(f.HookScript, f, "OnShow", refreshSoon) end
	end
	local combined = rawget(_G, "ContainerFrameCombinedBags")
	if combined and combined.HookScript then pcall(combined.HookScript, combined, "OnShow", refreshSoon) end
end

QL.Event("PLAYER_LOGIN", function()
	local ok, err = pcall(hookItemTooltips)
	if not ok then QL.Debug("item tooltip hook: " .. tostring(err)) end
	ok, err = pcall(hookBags)
	if not ok then QL.Debug("bag hook: " .. tostring(err)) end
end)
QL.Event("BAG_UPDATE_DELAYED", refreshSoon)
QL.On("STATE_CHANGED", refreshSoon)
QL.On("SETTING_CHANGED", function(key) if key == "bagMarks" then refreshSoon() end end)
