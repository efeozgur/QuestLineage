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

local function show(h)
	local T, C = QL.Theme, QL.Theme.C
	local title = QL.QuestTitle(h.questId)
	local lines
	if h.reason == "area" then
		lines = L("You are in the area of %s"):format(T.Hex(C.text) .. title .. "|r")
	else
		lines = (h.name and (T.Hex(C.text) .. h.name .. "|r  ") or "") .. L("counts for %s"):format(T.Hex(C.text) .. title .. "|r")
	end
	local what = h.row and (h.row.text or "") or ""
	local count = counter(h.row)
	if what ~= "" then lines = lines .. "\n" .. T.Hex(C.muted) .. what .. "|r" end
	if count and not what:find(count, 1, true) then lines = lines .. "  " .. T.Hex(C.accent) .. count .. "|r" end
	lines = lines .. "\n" .. T.Hex(C.dim) .. L("Click: make it the current quest") .. "|r"
	shown[h.questId] = now()
	if QL.DB().toasts ~= false and QL.Toast then
		local id = h.questId
		QL.Toast(lines, "quest", {
			head = L("ANOTHER QUEST HERE"),
			onClick = function() if QL.SetArrowTarget then QL.SetArrowTarget(id) end end,
		})
	else
		QL.Chat(L("Another quest here: ") .. title .. (count and (" " .. count) or ""))
	end
	QL.lastNearbyHint = h
end

-- A hint for questId (row = the objective it is about, reason = "target" | "plate" | "area").
-- Returns true when a card went up (or waits for the end of combat).
function QL.NearbyHint(questId, row, reason, name)
	if not questId then return false end
	local ctx = QL.Context()
	if not ctx.log[questId] or (ctx.complete and ctx.complete[questId]) then return false end
	if QL.CurrentQuest and QL.CurrentQuest(ctx) == questId then return false end
	if row and (row.done or (row.need and row.need > 0 and (row.have or 0) >= row.need)) then return false end
	local last = shown[questId]
	if last and now() - last < cooldown() then return false end
	local h = { questId = questId, row = row, reason = reason, name = name }
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
		pcall(QL.NearbyHint, questId, h.row, h.reason, h.name)
	end
end)

-- Areas ------------------------------------------------------------------------------------------------

local areas, areasAt = {}, -999

local function rebuildAreas()
	areas = {}
	local ctx = QL.Context()
	local current = QL.CurrentQuest and QL.CurrentQuest(ctx)
	for id in pairs(ctx.log) do
		if id ~= current and not (ctx.complete and ctx.complete[id]) then
			local ok, list = pcall(QL.QuestAreas, id, ctx)
			if ok then
				local rows = QL.ObjectiveRows(id, ctx)
				for k, a in ipairs(list or {}) do
					a.questId, a.key = id, id .. ":" .. k
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
				if not inside[a.key] then QL.NearbyHint(a.questId, a.row, "area") end
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
