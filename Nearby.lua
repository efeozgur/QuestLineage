-- Other quests nearby: while you work on one quest, a card tells you when something of another
-- quest in your log is at hand, and a click on it makes that quest the current one.
--   target   the creature you target counts for another quest     "Wolf · for Wolf Hunt · 2/8"
--   plates   a creature whose nameplate comes into view does
--   areas    you walk into one of another quest's objective areas  "You are in Wolf Hunt's area"
-- Never for the current quest, a finished objective or a quest ready to hand in; one card per quest
-- every few minutes (nearbyCooldown, whatever the reason); in combat the latest hint per quest waits for
-- the fight to end. Settings: nearbyTarget, nearbyPlates, nearbyAreas (all on). The cards are
-- toasts of kind "quest" (violet); with toasts off they are chat lines.
--
--   QL.NearbyHint(questId, row, reason, name)  QL.CheckNearbyAreas()  QL.ResetNearby()

local _, QL = ...
local L = QL.L

-- minutes between two cards for the same quest (setting nearbyCooldown, 1-15)
local function cooldown() return math.max(1, math.min(15, tonumber(QL.DB().nearbyCooldown) or 3)) * 60 end
local AREA_EVERY = 2 -- seconds between two looks at where you stand
local AREAS_EVERY = 15 -- seconds between two rebuilds of the other quests' areas

local shown = {}   -- questId -> time of its last card
local waiting = {} -- questId -> hint held back during combat
local inside = {}  -- area key -> true while you stand in it

local function now() return (GetTime and GetTime()) or 0 end
local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end

function QL.ResetNearby() shown, waiting, inside = {}, {}, {} end

local function counter(row)
	if row and row.need and row.need > 0 then return ("%d/%d"):format(row.have or 0, row.need) end
	return nil
end

-- A picture for a quest's card: the icon of an item it collects (the objective the hint is about
-- first), else QuestLineage's quest mark.
function QL.QuestPicture(questId, row)
	local function iconOf(task)
		if task and task.kind == "item" and QL.ItemIcon then
			local ok, icon = pcall(QL.ItemIcon, task.id)
			if ok and icon then return icon end
		end
	end
	local icon = row and iconOf(row.task)
	if not icon then
		local ok, tasks = pcall(QL.QuestTasks, questId)
		for _, t in ipairs(ok and tasks or {}) do
			icon = iconOf(t)
			if icon then break end
		end
	end
	if icon then return icon, true end
	return "Interface" .. string.char(92) .. "AddOns" .. string.char(92) .. "QuestLineage" .. string.char(92) .. "Media" .. string.char(92) .. "quest_mark", false
end

local function show(h)
	local T, C = QL.Theme, QL.Theme.C
	local title = QL.QuestTitle(h.questId)
	local lines
	if h.current then
		lines = L("Your current quest is here: %s"):format(T.Hex(C.text) .. title .. "|r")
	elseif h.reason == "area" then
		lines = L("You are in the area of %s"):format(T.Hex(C.text) .. title .. "|r")
	else
		lines = (h.name and (T.Hex(C.text) .. h.name .. "|r  ") or "") .. L("counts for %s"):format(T.Hex(C.text) .. title .. "|r")
	end
	local what = h.row and (h.row.text or "") or ""
	local count = counter(h.row)
	if what ~= "" then lines = lines .. "\n" .. T.Hex(C.muted) .. what .. "|r" end
	if count and not what:find(count, 1, true) then lines = lines .. "  " .. T.Hex(C.accent) .. count .. "|r" end
	if not h.current then lines = lines .. "\n" .. T.Hex(C.dim) .. L("Click: make it the current quest") .. "|r" end
	shown[h.questId] = now()
	if QL.DB().toasts ~= false and QL.Toast then
		local id = h.questId
		QL.Toast(lines, "quest", {
			icon = select(1, QL.QuestPicture(h.questId, h.row)),
			crop = select(2, QL.QuestPicture(h.questId, h.row)),
			head = h.current and L("CURRENT QUEST HERE") or L("ANOTHER QUEST HERE"),
			onClick = function() if QL.SetArrowTarget then QL.SetArrowTarget(id) end end,
		})
	else
		QL.Chat(L("Another quest here: ") .. title .. (count and (" " .. count) or ""))
	end
	QL.lastNearbyHint = h
end

-- A hint for questId (row = the objective it is about, reason = "target" | "plate" | "area").
-- Returns true when a card went up (or waits for the end of combat).
function QL.NearbyHint(questId, row, reason, name, current)
	if not questId then return false end
	local ctx = QL.Context()
	if not ctx.log[questId] or (ctx.complete and ctx.complete[questId]) then return false end
	local isCurrent = QL.CurrentQuest and QL.CurrentQuest(ctx) == questId
	if isCurrent and not current then return false end
	if row and (row.done or (row.need and row.need > 0 and (row.have or 0) >= row.need)) then return false end
	local last = shown[questId]
	if last and now() - last < cooldown() then return false end
	local h = { questId = questId, row = row, reason = reason, name = name, current = current and isCurrent or nil }
	if inCombat() then
		waiting[questId] = h
		return true
	end
	show(h)
	return true
end

-- the first of the npc's quests that is not the current one
local function forNpc(npcId)
	local list = npcId and QL.PlateIndex and QL.PlateIndex()[npcId]
	if not list then return nil end
	local current = QL.CurrentQuest and QL.CurrentQuest()
	for _, e in ipairs(list) do
		if e[1] ~= current then return e[1], e[2] end
	end
	return nil
end

local function unitName(unit)
	if not UnitName then return nil end
	local ok, n = pcall(UnitName, unit)
	if ok and type(n) == "string" and not (issecretvalue and issecretvalue(n)) then return n end
	return nil
end

local function fromUnit(unit, reason)
	if not QL.NpcIdOf then return end
	local questId, row = forNpc(QL.NpcIdOf(unit))
	if questId then QL.NearbyHint(questId, row, reason, unitName(unit)) end
end

QL.Event("PLAYER_TARGET_CHANGED", function()
	if QL.DB().nearbyTarget == false then return end
	pcall(fromUnit, "target", "target")
end)

QL.Event("NAME_PLATE_UNIT_ADDED", function(_, unit)
	if QL.DB().nearbyPlates == false or type(unit) ~= "string" then return end
	pcall(fromUnit, unit, "plate")
end)

QL.Event("PLAYER_REGEN_ENABLED", function()
	local list = waiting
	waiting = {}
	for questId, h in pairs(list) do
		shown[questId] = nil -- it was held, not shown
		pcall(QL.NearbyHint, questId, h.row, h.reason, h.name, h.current)
	end
end)

-- Areas ------------------------------------------------------------------------------------------------

local areas, areasAt = {}, -999

local function rebuildAreas()
	areas = {}
	local ctx = QL.Context()
	local current = QL.CurrentQuest and QL.CurrentQuest(ctx)
	for id in pairs(ctx.log) do
		if (id ~= current or QL.DB().nearbyCurrent ~= false) and not (ctx.complete and ctx.complete[id]) then
			local ok, list = pcall(QL.QuestAreas, id, ctx)
			if ok then
				local rows = QL.ObjectiveRows(id, ctx)
				for k, a in ipairs(list or {}) do
					a.questId, a.key, a.isCurrent = id, id .. ":" .. k, (id == current)
					-- the objective it belongs to, by its label
					for _, r in ipairs(rows) do
						if r.task and (r.task.name == a.label or r.text == a.label) then a.row = r; break end
					end
					areas[#areas + 1] = a
				end
			end
		end
	end
	areasAt = now()
end

local function mapSize(map)
	if not (C_Map and C_Map.GetMapWorldSize) then return nil end
	local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
	if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
	return nil
end

-- Looks where you stand: walking into another quest's area brings its card (once per entry).
function QL.CheckNearbyAreas(force)
	if QL.DB().nearbyAreas == false then return end
	if force or now() - areasAt > AREAS_EVERY then rebuildAreas() end
	local map, px, py = QL.PlayerPosition()
	if not map or not px then return end
	local w, h = mapSize(map)
	if not w then return end
	local still = {}
	for _, a in ipairs(areas) do
		local x, y = QL.ProjectToMap(a.map, a.x, a.y, map)
		if x then
			local dx, dy = (x - px) * w, (y - py) * h
			if dx * dx + dy * dy <= a.r * a.r then
				still[a.key] = true
				if not inside[a.key] then QL.NearbyHint(a.questId, a.row, "area", nil, a.isCurrent) end
			end
		end
	end
	inside = still
end

QL.Event("PLAYER_LOGIN", function()
	if not CreateFrame then return end
	local f = CreateFrame("Frame")
	local since = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		since = since + (elapsed or 0)
		if since < AREA_EVERY then return end
		since = 0
		pcall(QL.CheckNearbyAreas)
	end)
end)
-- the log or the current quest changed: the areas are rebuilt on the next look
for _, m in ipairs({ "STATE_CHANGED", "ARROW_CHANGED" }) do
	QL.On(m, function() areasAt = -999 end)
end

-- Next quest ---------------------------------------------------------------------------------------------
-- When the current quest is handed in, a small card offers the next quest in the log for five seconds:
-- a click makes it current, otherwise nothing changes. Setting nextQuestOffer (on).

local NEXT_LIFE = 5
local recent = {} -- the last two current quests (the turn-in can come after the log already changed)

local function noteCurrent()
	if not QL.CurrentQuest then return end
	local ok, id = pcall(QL.CurrentQuest)
	if not ok or not id or recent[1] == id then return end
	recent = { id, recent[1] }
end
QL.On("STATE_CHANGED", noteCurrent)
QL.On("ARROW_CHANGED", noteCurrent)

-- the quest to offer after `doneId`: ready ones first, then by level (QL.LogQuests)
function QL.NextQuestAfter(doneId, ctx)
	ctx = ctx or QL.Context()
	for _, id in ipairs(QL.LogQuests(ctx, doneId)) do
		if ctx.log[id] and QL.NodeStatus(id, ctx) ~= "done" then return id end
	end
	return nil
end

function QL.OfferNextQuest(doneId)
	if QL.DB().nextQuestOffer == false then return false end
	if QL.RouteActive and QL.RouteActive() then return false end
	local ctx = QL.Context()
	local nextId = QL.NextQuestAfter(doneId, ctx)
	if not nextId then return false end
	local q = QL.ArrowQuest and QL.ArrowQuest()
	if q and q ~= doneId and ctx.log[q] then return false end -- already pointing at another logged quest
	local T, C = QL.Theme, QL.Theme.C
	local ready = ctx.complete and ctx.complete[nextId]
	local lines = T.Hex(C.text) .. QL.QuestTitle(nextId) .. "|r"
	if ready then lines = lines .. "  " .. T.Hex(T.STATUS.done) .. L("ready to hand in") .. "|r" end
	lines = lines .. "\n" .. T.Hex(C.dim) .. L("Click: switch to it") .. "|r"
	QL.lastNextOffer = nextId
	if QL.DB().toasts ~= false and QL.Toast then
		QL.Toast(lines, "quest", {
			head = L("NEXT QUEST?"),
			icon = select(1, QL.QuestPicture(nextId)),
			crop = select(2, QL.QuestPicture(nextId)),
			life = NEXT_LIFE,
			onClick = function() if QL.SetArrowTarget then QL.SetArrowTarget(nextId) end end,
		})
	else
		QL.Chat(L("Next quest: ") .. QL.QuestTitle(nextId))
	end
	return true
end

-- The chain goes on: the quest(s) that follow a handed-in one. -> questId, "available" | "toolow", level
function QL.ChainFollowUp(doneId, ctx)
	ctx = ctx or QL.Context()
	local lowId
	for _, e in ipairs(QL.Dependents(doneId)) do
		local id, kind = e[1], e[2]
		if kind ~= "parent" and id and id ~= doneId then
			local st = QL.NodeStatus(id, ctx)
			if st == "available" then return id, "available" end
			if st == "toolow" and not lowId then lowId = id end
		end
	end
	if lowId then return lowId, "toolow", tonumber(QL.Q(lowId, "requiredLevel")) end
	return nil
end

-- A card for the next quest of the chain: a click points the arrow at it; too high a level says so.
function QL.OfferChainQuest(doneId)
	if QL.DB().nextQuestOffer == false then return false end
	local ctx = QL.Context()
	ctx.done = ctx.done or {}
	ctx.done[doneId] = true -- the cached context may not know the hand-in yet
	if ctx.log then ctx.log[doneId] = nil end
	local id, state, need = QL.ChainFollowUp(doneId, ctx)
	if not id then return false end
	local T, C = QL.Theme, QL.Theme.C
	local lines = T.Hex(C.text) .. QL.QuestTitle(id) .. "|r"
	local icon, crop = QL.QuestPicture(id)
	if state == "available" then
		lines = lines .. "\n" .. T.Hex(C.dim) .. L("Click: head to it") .. "|r"
		QL.lastChainOffer = id
		if QL.DB().toasts ~= false and QL.Toast then
			QL.Toast(lines, "quest", {
				head = L("THE CHAIN CONTINUES"), icon = icon, crop = crop, life = NEXT_LIFE,
				onClick = function() if QL.SetArrowTarget then QL.SetArrowTarget(id) end end,
			})
		else
			QL.Chat(L("Next in the chain: ") .. QL.QuestTitle(id))
		end
	else
		local msg = need and L("This quest is not suitable for your level yet (needs level %d)"):format(need)
			or L("This quest is not suitable for your level yet")
		lines = lines .. "\n" .. T.Hex(C.muted) .. msg .. "|r"
		QL.lastChainOffer = id
		if QL.DB().toasts ~= false and QL.Toast then
			QL.Toast(lines, "warn", { head = L("THE CHAIN CONTINUES"), icon = icon, crop = crop, life = NEXT_LIFE })
		else
			QL.Chat(QL.QuestTitle(id) .. ": " .. msg)
		end
	end
	return true
end

QL.Event("QUEST_TURNED_IN", function(_, questId)
	questId = tonumber(questId)
	if not questId then return end
	local wasCurrent = recent[1] == questId or recent[2] == questId
	if wasCurrent then recent = {} end
	local function go()
		local ok, shownChain = pcall(QL.OfferChainQuest, questId)
		if wasCurrent and not (ok and shownChain) then pcall(QL.OfferNextQuest, questId) end
	end
	if C_Timer and C_Timer.After then C_Timer.After(0.8, go) else go() end
end)
