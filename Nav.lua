-- Navigation logic for the arrow: where a quest sends you now, where you are, and the way.
-- No frames here (Arrow.lua draws); client calls are pcall-guarded, and values the client may
-- hand back as "secret" (issecretvalue) read as nil.
--
--   QL.QuestTarget(id, ctx) -> { kind = pickup|objective|turnin, label, points = { {map, x, y}, ... } } | nil
--       pickup     the quest is not in the log: where its giver stands
--       objective  in the log and not complete: the creatures, objects and item droppers of
--                  its unfinished objectives (or its exploration spot)
--       turnin     complete (or nothing else known): where it is handed in
--   QL.PlayerPosition() -> map, x, y        (0-1 on the player's best map)
--   QL.ProjectToMap(fromMap, x, y, toMap) -> x, y   through world coordinates, same continent only
--   QL.Bearing(dx, dy, facing) -> radians to rotate an up-pointing arrow
--   QL.Locate(target) -> { dist, dx, dy, point, map, px, py } | { otherMap = point } | nil

local _, QL = ...

local atan2 = math.atan2 or math.atan
local TWO_PI = math.pi * 2
local MAX_POINTS = 150

local function plain(v)
	if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function xyOf(pos)
	if type(pos) ~= "table" then return nil end
	if pos.GetXY then
		local ok, x, y = pcall(pos.GetXY, pos)
		if ok then return plain(x), plain(y) end
	end
	return plain(pos.x), plain(pos.y)
end

-- Targets ------------------------------------------------------------------------------------

-- Spawn points of an NPC or object, as {map, x 0-1, y 0-1}; instance markers (-1, -1) skipped.
local function addSpawns(points, kind, id)
	local spawns = kind == "npc" and QL.N(id, "spawns") or QL.O(id, "spawns")
	if type(spawns) ~= "table" then return end
	for area, list in pairs(spawns) do
		local map = QL.AreaUiMap(area)
		if map and type(list) == "table" then
			for _, p in ipairs(list) do
				if #points >= MAX_POINTS then return end
				if type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number" and p[1] >= 0 and p[2] >= 0 then
					points[#points + 1] = { map = map, x = p[1] / 100, y = p[2] / 100 }
				end
			end
		end
	end
end

local function personPoints(field, id)
	local by = QL.Q(id, field)
	local points = {}
	if type(by) ~= "table" then return points, nil end
	local name
	for _, npc in ipairs(QL.Ids(by[1])) do
		addSpawns(points, "npc", npc)
		name = name or QL.N(npc, "name")
	end
	for _, obj in ipairs(QL.Ids(by[2])) do
		addSpawns(points, "object", obj)
		name = name or QL.O(obj, "name")
	end
	return points, name
end

local function objectivePoints(id)
	local L = QL.L
	local tasks = QL.QuestTasks(id)
	local live = QL.LiveObjectives(id)
	local points, labels = {}, {}
	for i, t in ipairs(tasks) do
		local done = live and live[i] and live[i].done
		if not done then
			local before = #points
			if t.kind == "npc" then
				addSpawns(points, "npc", t.id)
			elseif t.kind == "object" then
				addSpawns(points, "object", t.id)
			elseif t.kind == "item" then
				for n, npc in ipairs(QL.Ids(QL.I(t.id, "npcDrops"))) do
					if n > 5 then break end
					addSpawns(points, "npc", npc)
				end
				for n, obj in ipairs(QL.Ids(QL.I(t.id, "objectDrops"))) do
					if n > 5 then break end
					addSpawns(points, "object", obj)
				end
			end
			if #points > before then
				local verb = t.kind == "npc" and L("Slay") or (t.kind == "item" and L("Collect") or L("Use"))
				labels[#labels + 1] = verb .. ": " .. (t.text or t.name or "?")
			end
		end
	end
	-- an exploration objective: {text, {[area] = {{x, y}, ...}}}
	if #points == 0 then
		local trigger = QL.Q(id, "triggerEnd")
		if type(trigger) == "table" and type(trigger[2]) == "table" then
			for area, list in pairs(trigger[2]) do
				local map = QL.AreaUiMap(area)
				if map and type(list) == "table" then
					for _, p in ipairs(list) do
						if type(p) == "table" and type(p[1]) == "number" and p[1] >= 0 then
							points[#points + 1] = { map = map, x = p[1] / 100, y = p[2] / 100 }
						end
					end
				end
			end
			if #points > 0 then labels[#labels + 1] = type(trigger[1]) == "string" and trigger[1] or L("Explore") end
		end
	end
	return points, table.concat(labels, " · ")
end

function QL.QuestTarget(id, ctx)
	local L = QL.L
	ctx = ctx or QL.Context()
	local s = QL.NodeStatus(id, ctx)
	if s == "done" then return nil end
	if s == "active" then
		local points, label = objectivePoints(id)
		if #points > 0 then return { kind = "objective", label = label, points = points, questId = id } end
	end
	if s == "active" or s == "ready" then
		local points, name = personPoints("finishedBy", id)
		return { kind = "turnin", label = L("Turn in: ") .. (name or "?"), points = points, questId = id }
	end
	local points, name = personPoints("startedBy", id)
	return { kind = "pickup", label = L("Pick up: ") .. (name or "?"), points = points, questId = id }
end

-- Position and geometry ------------------------------------------------------------------------

function QL.PlayerPosition()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
	local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
	map = ok and plain(map) or nil
	if not map then return nil end
	local got, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
	if not got or not pos then return map end
	local x, y = xyOf(pos)
	if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return map end
	return map, x, y
end

function QL.ProjectToMap(fromMap, x, y, toMap)
	if fromMap == toMap then return x, y end
	if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
	local ok, inst, world = pcall(C_Map.GetWorldPosFromMapPos, fromMap, CreateVector2D(x, y))
	inst = ok and plain(inst) or nil
	if inst == nil or not world then return nil end
	local ok2, map, pos = pcall(C_Map.GetMapPosFromWorldPos, inst, world, toMap)
	if not ok2 or plain(map) ~= toMap then return nil end
	local px, py = xyOf(pos)
	if type(px) ~= "number" or type(py) ~= "number" then return nil end
	return px, py
end

local function mapSize(map)
	if not (C_Map and C_Map.GetMapWorldSize) then return nil end
	local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
	w, h = ok and plain(w) or nil, ok and plain(h) or nil
	if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return nil end
	return w, h
end

-- dx, dy: target minus player on the map (y down). facing: GetPlayerFacing (radians,
-- counter-clockwise, north = 0). The result rotates an up-pointing arrow to the target.
function QL.Bearing(dx, dy, facing)
	return (atan2(-dx, -dy) - (facing or 0)) % TWO_PI
end

-- Projected points are cached per player map until the target changes.
local projCache = setmetatable({}, { __mode = "k" })

function QL.Locate(target)
	if not target or not target.points or #target.points == 0 then return nil end
	local map, px, py = QL.PlayerPosition()
	if not map or not px then return nil end
	local w, h = mapSize(map)
	if not w then return nil end
	local cache = projCache[target]
	if not cache or cache.map ~= map then
		cache = { map = map, pts = {} }
		for _, p in ipairs(target.points) do
			local x, y = QL.ProjectToMap(p.map, p.x, p.y, map)
			if x then cache.pts[#cache.pts + 1] = { x = x, y = y, src = p } end
		end
		projCache[target] = cache
	end
	if #cache.pts == 0 then return { otherMap = target.points[1] } end
	local best, bestD2, bdx, bdy
	for _, p in ipairs(cache.pts) do
		local dx, dy = (p.x - px) * w, (p.y - py) * h
		local d2 = dx * dx + dy * dy
		if not bestD2 or d2 < bestD2 then best, bestD2, bdx, bdy = p, d2, dx, dy end
	end
	return { dist = math.sqrt(bestD2), dx = bdx, dy = bdy, point = best.src, map = map, px = px, py = py }
end

-- Distances for lists: each quest's target is built once and kept until the quest log or the
-- data changes (the projection cache above then makes a re-measure cheap), so the list can
-- refresh distances every second while you move.
--   QL.QuestDistance(id, ctx) -> yards | nil, mapName (when the spot is on another map)
--   QL.DistanceText(id, ctx) -> "120 yd" | "Mulgore" | nil
local targetCache = {}
local function clearTargets() targetCache = {} end
QL.On("STATE_CHANGED", clearTargets)
QL.On("INDEX_READY", clearTargets)

function QL.QuestDistance(id, ctx)
	local t = targetCache[id]
	if t == nil then
		t = QL.QuestTarget(id, ctx) or false
		targetCache[id] = t
	end
	if not t then return nil end
	local loc = QL.Locate(t)
	if not loc then return nil end
	if loc.otherMap then return nil, QL.MapName(loc.otherMap.map) end
	return loc.dist
end

function QL.DistanceText(id, ctx)
	local d, other = QL.QuestDistance(id, ctx)
	if d then
		if d >= 1000 then
			local s = ("%.1f"):format(d / 1000)
			if QL.UseTurkish() then s = s:gsub("%.", ",") end
			return QL.L("%s k yd"):format(s)
		end
		return QL.L("%d yd"):format(math.floor(d + 0.5))
	end
	return other
end

-- Distance with a small arrow mark in front, coloured by how near it is: within 100 yards the
-- accent, farther the text colour, on another map muted.
--   QL.DistanceMarkup(id, ctx, iconSize) -> "|T...|t 191 yd" | nil
local NEAR = 100
function QL.DistanceMarkup(id, ctx, iconSize)
	local text = QL.DistanceText(id, ctx)
	if not text then return nil end
	local T = QL.Theme
	local d = QL.QuestDistance(id, ctx)
	local c = (not d and T.C.muted) or (d < NEAR and T.C.accent) or T.C.text
	local size = iconSize or 11
	local icon = ("|TInterface\\AddOns\\QuestLineage\\Media\\arrow:%d:%d:0:0:128:128:0:128:0:128:%d:%d:%d|t"):format(
		size, size, math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
	return icon .. " " .. T.Hex(c) .. text .. "|r"
end

-- Statuses with somewhere to go: a quest you can take, are on, or can hand in.
local GOES = { available = true, active = true, ready = true }
function QL.HasPlace(status) return GOES[status] or false end

function QL.MapName(map)
	if not (C_Map and C_Map.GetMapInfo) then return nil end
	local ok, info = pcall(C_Map.GetMapInfo, map)
	return ok and type(info) == "table" and info.name or nil
end
