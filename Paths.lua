-- Your own routes: stops you put on the world map yourself, with no quests behind them.
--
--   * Data: QuestLineageDB.paths[name] = { points = { {map, x, y}, ... } } (x, y = 0-1 on the map the
--     stop was put on; every stop carries its own map, so a route can cross maps of one continent).
--     Shared by all characters. The one you work with is QuestLineageDB.pathActive.
--   * Drawing: MapRoute.lua draws the active path (QL.PathStops) when it is being edited, followed or
--     looked at (the map's own panel, below).
--   * Editing: the panel's Edit button; then Shift + left click on the map adds a stop, a stop's badge
--     can be dragged, and right-click on a badge removes it.
--   * Following: the arrow points at the next stop (QL.SetArrowPoint) and moves on when you are within
--     ADVANCE yards; the last stop ends the route. Saved per character in QuestLineageDB.pathFollow.
--
--   QL.PathNames() QL.PathNew() QL.PathAdd(name, map, x, y) QL.PathMove(name, i, map, x, y)
--   QL.PathRemove(name, i) QL.PathUndo(name) QL.PathClear(name) QL.PathDelete(name)
--   QL.PathRename(old, new) QL.PathPoints(name) QL.PathLength(name) QL.PathStops()
--   QL.PathFollow(name) QL.PathStopFollow() QL.PathFollowing()

local _, QL = ...
local L = function(s) return QL.L(s) end

local ADVANCE = 20     -- yards: close enough to a stop to move on
local TICK = 0.5       -- seconds between two looks at where you are

local editing, viewing = false, false
local follow            -- { name, index }
local steering = false  -- true while this file moves the arrow
local locTargets = {}   -- one fixed target per followed stop (QL.Locate caches by table)
local detourEdit = false -- true while a detour is being edited (QL.PathStops reads it, so it lives up here)

-- Data ---------------------------------------------------------------------------------------------

local function store()
	local db = QL.DB()
	if type(db.paths) ~= "table" then db.paths = {} end
	return db.paths
end

local function changed() QL.Fire("PATH_CHANGED") end

function QL.PathNames()
	local out = {}
	for name in pairs(store()) do out[#out + 1] = name end
	table.sort(out, function(a, b) return a:lower() < b:lower() end)
	return out
end

function QL.PathPoints(name)
	local p = name and store()[name]
	return p and p.points or {}
end

function QL.PathActive()
	local name = QL.DB().pathActive
	if name and store()[name] then return name end
	return nil
end

function QL.PathSelect(name)
	if name and not store()[name] then return end
	QL.DB().pathActive = name
	changed()
end

-- A new empty route named "Route n" (the first free number); it becomes the active one.
function QL.PathNew()
	local paths = store()
	local n = 1
	while paths[L("Route") .. " " .. n] do n = n + 1 end
	local name = L("Route") .. " " .. n
	paths[name] = { points = {} }
	QL.DB().pathActive = name
	changed()
	return name
end

function QL.PathAdd(name, map, x, y)
	local p = name and store()[name]
	if not p or type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return nil end
	p.points[#p.points + 1] = { map = map, x = x, y = y }
	changed()
	return #p.points
end

function QL.PathMove(name, i, map, x, y)
	local p = name and store()[name]
	if not p or not p.points[i] then return false end
	p.points[i] = { map = map, x = x, y = y }
	changed()
	return true
end

function QL.PathRemove(name, i)
	local p = name and store()[name]
	if not p or not p.points[i] then return false end
	table.remove(p.points, i)
	if follow and follow.name == name then
		if #p.points == 0 then QL.PathStopFollow(true)
		elseif follow.index > #p.points then follow.index = #p.points end
	end
	changed()
	return true
end

function QL.PathUndo(name)
	local p = name and store()[name]
	if not p or #p.points == 0 then return false end
	return QL.PathRemove(name, #p.points)
end

function QL.PathClear(name)
	local p = name and store()[name]
	if not p then return end
	p.points = {}
	if follow and follow.name == name then QL.PathStopFollow(true) end
	changed()
end

function QL.PathDelete(name)
	local paths = store()
	if not paths[name] then return end
	if follow and follow.name == name then QL.PathStopFollow(true) end
	paths[name] = nil
	if QL.DB().pathActive == name then QL.DB().pathActive = nil end
	changed()
end

-- A new name: not empty, not taken. Returns true on success.
function QL.PathRename(old, new)
	new = tostring(new or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local paths = store()
	if new == "" or not paths[old] then return false end
	if new == old then return true end
	if paths[new] then return false end
	paths[new], paths[old] = paths[old], nil
	if QL.DB().pathActive == old then QL.DB().pathActive = new end
	if follow and follow.name == old then follow.name = new end
	changed()
	return true
end

-- yards between two points (each {map, x, y}); nil when the client cannot say
function QL.PathGap(a, b)
	local w, h = nil, nil
	if C_Map and C_Map.GetMapWorldSize and a and b then
		local ok, ww, hh = pcall(C_Map.GetMapWorldSize, a.map)
		if ok and type(ww) == "number" and type(hh) == "number" and ww > 0 and hh > 0 then w, h = ww, hh end
	end
	if not w then return nil end
	local x, y = QL.ProjectToMap(b.map, b.x, b.y, a.map)
	if not x then return nil end
	return math.sqrt(((x - a.x) * w) ^ 2 + ((y - a.y) * h) ^ 2)
end

-- yards between two points of a route: both go to the first one's map when they differ
local function worldSize(map)
	if not (C_Map and C_Map.GetMapWorldSize) then return nil end
	local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
	if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
	return nil
end

function QL.PathLength(name)
	local pts = QL.PathPoints(name)
	if #pts < 2 then return 0 end
	local base = pts[1].map
	local w, h = worldSize(base)
	if not w then return nil end
	local total, prev = 0, nil
	for _, p in ipairs(pts) do
		local x, y = QL.ProjectToMap(p.map, p.x, p.y, base)
		if x then
			if prev then total = total + math.sqrt(((x - prev[1]) * w) ^ 2 + ((y - prev[2]) * h) ^ 2) end
			prev = { x, y }
		end
	end
	return total
end

-- The stops MapRoute.lua draws: the active route while it is edited, followed or looked at; from the
-- stop being followed on. -> stops, info | nil
function QL.PathStops()
	if QL.DB().mapPaths == false then return nil end
	local name = follow and follow.name or QL.PathActive()
	if detourEdit or not name or not (editing or follow or viewing) then return nil end
	local pts = QL.PathPoints(name)
	if #pts == 0 and not editing then return nil end
	local first = follow and follow.index or 1
	local stops = {}
	for i = first, #pts do
		local p = pts[i]
		stops[#stops + 1] = { custom = true, n = i, spot = { map = p.map, x = p.x, y = p.y }, title = name }
	end
	return stops, { custom = true, name = name, index = first, total = #pts, following = follow ~= nil, editing = editing,
		length = QL.PathLength(name) }
end

function QL.PathEditing() return editing end

-- Following -----------------------------------------------------------------------------------------

local function charKey()
	local name = UnitName and UnitName("player") or "?"
	local realm = GetRealmName and GetRealmName() or "?"
	return tostring(name) .. "-" .. tostring(realm)
end

local function saveFollow()
	local db = QL.DB()
	if type(db.pathFollow) ~= "table" then db.pathFollow = {} end
	db.pathFollow[charKey()] = follow and { name = follow.name, index = follow.index } or nil
end

local function pointArrow()
	if not follow then return end
	local pts = QL.PathPoints(follow.name)
	local p = pts[follow.index]
	if not p then return end
	steering = true
	QL.SetArrowPoint(p.map, p.x, p.y, { title = follow.name, label = L("Stop %d/%d"):format(follow.index, #pts) })
	steering = false
	locTargets[follow.index] = locTargets[follow.index] or { kind = "place", fixed = true, points = { p } }
	locTargets[follow.index].points = { p }
end

function QL.PathFollowing() return follow and { name = follow.name, index = follow.index } or nil end

function QL.PathFollow(name, startAt)
	name = name or QL.PathActive()
	local pts = QL.PathPoints(name)
	if #pts == 0 then
		QL.Print(L("Put at least one stop on the map first."), "warn")
		return false
	end
	if QL.StopRoute then QL.StopRoute() end
	locTargets = {}
	follow = { name = name, index = math.max(1, math.min(#pts, tonumber(startAt) or 1)) }
	QL.DB().pathActive = name
	saveFollow()
	pointArrow()
	changed()
	return true
end

-- quiet: no arrow clearing (the arrow already points elsewhere)
function QL.PathStopFollow(quiet)
	if not follow then return end
	follow = nil
	locTargets = {}
	saveFollow()
	if not quiet and QL.ClearArrow then
		steering = true
		QL.ClearArrow()
		steering = false
	end
	changed()
end

-- One look at where you stand: close enough to the stop = the next one (the last one ends it).
function QL.PathCheck()
	if not follow then return end
	local pts = QL.PathPoints(follow.name)
	local p = pts[follow.index]
	if not p then QL.PathStopFollow(); return end
	local t = locTargets[follow.index]
	if not t then t = { kind = "place", fixed = true, points = { p } }; locTargets[follow.index] = t end
	local loc = QL.Locate(t)
	if not loc or loc.otherMap or loc.dist > ADVANCE then return end
	if follow.index >= #pts then
		local name = follow.name
		QL.PathStopFollow()
		QL.Print(L("Route complete: ") .. name, "success")
		return
	end
	follow.index = follow.index + 1
	saveFollow()
	pointArrow()
	changed()
end

-- the arrow was pointed elsewhere by hand: the route ends, as a quest route does
QL.On("ARROW_CHANGED", function()
	if follow and not steering then
		QL.PathStopFollow(true)
		QL.Print(L("Route stopped: you pointed the arrow elsewhere."), "warn")
	end
end)

-- Detours -------------------------------------------------------------------------------------------
-- A line to a spot goes straight; where a mountain is in the way, you bend it with stop-over points
-- (QuestLineageDB.detours[key] = { dest, points }, key = the destination spot rounded to 0.001 of its
-- map, so every arrow that goes to that spot uses them, whatever quest it is). The arrow then leads
-- you through them in order (QL.DetourNext) and the map draws the bent line (MapRoute.lua). A point
-- you have walked through is deleted (the detour is for one trip); nothing is deleted while it is edited.

local ADVANCE_VIA = 15 -- yards: close enough to a stop-over point to move on
local det             -- { key, n, idx, targets } progress along the detour being followed

local function detours()
	local db = QL.DB()
	if type(db.detours) ~= "table" then db.detours = {} end
	return db.detours
end

local function round3(v) return math.floor(v * 1000 + 0.5) end

function QL.DetourKey(spot)
	if type(spot) ~= "table" or not spot.map then return nil end
	return tostring(spot.map) .. ":" .. round3(spot.x or 0) .. ":" .. round3(spot.y or 0)
end

function QL.DetourPoints(spot)
	local key = QL.DetourKey(spot)
	local d = key and detours()[key]
	return d and d.points or {}
end

local function detourOf(spot)
	local key = QL.DetourKey(spot)
	if not key then return nil end
	local d = detours()[key]
	if not d then
		d = { dest = { map = spot.map, x = spot.x, y = spot.y }, points = {} }
		detours()[key] = d
	end
	return d, key
end

-- A point at place i (1 = the first stop-over; #points + 1 = the last).
function QL.DetourInsert(spot, i, map, x, y)
	local d = detourOf(spot)
	if not d or type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return nil end
	i = math.max(1, math.min(#d.points + 1, math.floor(tonumber(i) or (#d.points + 1))))
	table.insert(d.points, i, { map = map, x = x, y = y })
	changed()
	return i
end

function QL.DetourMove(spot, i, map, x, y)
	local pts = QL.DetourPoints(spot)
	if not pts[i] then return false end
	pts[i] = { map = map, x = x, y = y }
	changed()
	return true
end

function QL.DetourRemove(spot, i)
	local pts = QL.DetourPoints(spot)
	if not pts[i] then return false end
	table.remove(pts, i)
	if #pts == 0 then detours()[QL.DetourKey(spot)] = nil end
	changed()
	return true
end

function QL.DetourClear(spot)
	local key = QL.DetourKey(spot)
	if not key or not detours()[key] then return end
	detours()[key] = nil
	changed()
end

-- The spot the arrow is going to now (the nearest of its target's spots), or nil.
function QL.DetourSpot()
	local t = QL.ArrowTarget and QL.ArrowTarget()
	if not t then return nil end
	local loc = QL.Locate(t)
	return loc and loc.point or nil
end

function QL.DetourEditing() return detourEdit end

-- The stop-over points still ahead (all of them while editing, or when nothing is followed yet):
-- { {map, x, y, i}, ... }, i = the place in the full list.
function QL.DetourVias(spot, all)
	local pts = QL.DetourPoints(spot)
	local first = 1
	if not all and det and det.key == QL.DetourKey(spot) and det.idx then first = det.idx end
	local out = {}
	for i = first, #pts do out[#out + 1] = { map = pts[i].map, x = pts[i].x, y = pts[i].y, i = i } end
	return out
end

-- The arrow's next stop-over point for a located target (loc from QL.Locate): returns the measure of
-- that point (like QL.Locate's result), its place and the count, or nil when the line is straight (no
-- detour, passed it, or it cannot be measured). It starts at the point nearest to you, unless you are
-- nearer to the destination than to any point (then the detour is behind you).
function QL.DetourNext(loc)
	if not loc or loc.otherMap or not loc.point then return nil end
	local pts = QL.DetourPoints(loc.point)
	if #pts == 0 then det = nil; return nil end
	local key = QL.DetourKey(loc.point)
	if not det or det.key ~= key or det.n ~= #pts then det = { key = key, n = #pts, targets = {} } end
	local function target(i)
		local t = det.targets[i]
		if not t then t = { kind = "place", fixed = true, points = { pts[i] } }; det.targets[i] = t end
		return t
	end
	if not det.idx then
		local best, bestD
		for i = 1, #pts do
			local l = QL.Locate(target(i))
			if l and not l.otherMap and (not bestD or l.dist < bestD) then best, bestD = i, l.dist end
		end
		det.idx = (best and bestD < loc.dist) and best or (#pts + 1)
	end
	while det.idx <= #pts do
		local l = QL.Locate(target(det.idx))
		if not l or l.otherMap then return nil end
		-- reached it, or left it behind: nearer to the next point than to this one, and between them
		local passed = l.dist < ADVANCE_VIA
		if not passed and pts[det.idx + 1] then
			local nl = QL.Locate(target(det.idx + 1))
			local gap = QL.PathGap and QL.PathGap(pts[det.idx], pts[det.idx + 1])
			passed = nl and not nl.otherMap and nl.dist < l.dist and (not gap or nl.dist < gap)
		end
		if not passed then return l, det.idx, #pts end
		if detourEdit then
			det.idx = det.idx + 1 -- being edited: nothing is thrown away
		else
			-- walked through: that point and the ones before it are deleted, so the line does not
			-- lead you back to an old detour next time
			for _ = 1, det.idx do table.remove(pts, 1) end
			if #pts == 0 then detours()[key] = nil end
			changed() -- (clears det)
			if #pts == 0 then return nil end
			det = { key = key, n = #pts, idx = 1, targets = {} }
		end
	end
	return nil
end

-- an edit or another route: the progress is worked out again
QL.On("PATH_CHANGED", function() det = nil end)

-- Map panel and editing -----------------------------------------------------------------------------

local panel, dragIndex, dragKind

local function worldCursor()
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	if sc and sc.GetNormalizedCursorPosition then
		local ok, x, y = pcall(sc.GetNormalizedCursorPosition, sc)
		if ok and type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
	end
	return nil
end

local function shownMap()
	if WorldMapFrame and WorldMapFrame.GetMapID then
		local ok, id = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
		if ok and type(id) == "number" then return id end
	end
	return nil
end

-- Called by a stop's badge (MapRoute.lua) while editing.
function QL.PathBadgeDown(i) if editing then dragIndex, dragKind = i, "path" end end
function QL.PathBadgeRemove(i)
	if editing then QL.PathRemove(QL.PathActive(), i) end
end

-- Detour editing: a stop-over point's badge or a line's handle was pressed (MapRoute.lua).
function QL.DetourViaDown(i)
	if detourEdit then dragIndex, dragKind = i, "detour" end
end
function QL.DetourViaRemove(i)
	if not detourEdit then return end
	local spot = QL.DetourSpot()
	if spot then QL.DetourRemove(spot, i) end
end
-- a handle on a line: a new point at the cursor, picked up at once (insert place i)
function QL.DetourHandleDown(i)
	if not detourEdit then return end
	local spot, map, x, y = QL.DetourSpot(), shownMap(), worldCursor()
	if spot and map and x then
		local at = QL.DetourInsert(spot, i, map, x, y)
		if at then dragIndex, dragKind = at, "detour" end
	end
end
-- Shift+click on the map: a new point on the line piece nearest to the cursor
local function nearestPiece(map, cx, cy)
	local spot = QL.DetourSpot()
	if not spot then return nil end
	local chain = {}
	local pm, px, py = QL.PlayerPosition()
	if pm and px then
		local x, y = QL.ProjectToMap(pm, px, py, map)
		if x then chain[#chain + 1] = { x = x, y = y, v = 0 } end
	end
	for _, v in ipairs(QL.DetourVias(spot, true)) do
		local x, y = QL.ProjectToMap(v.map, v.x, v.y, map)
		if x then chain[#chain + 1] = { x = x, y = y, v = v.i } end
	end
	local dx, dy = QL.ProjectToMap(spot.map, spot.x, spot.y, map)
	if dx then chain[#chain + 1] = { x = dx, y = dy } end
	if #chain < 2 then return nil end
	local best, bestD
	for k = 1, #chain - 1 do
		local a, b = chain[k], chain[k + 1]
		-- distances in a 3:2 plane (the map is wider than tall)
		local ax, ay, bx, by, qx, qy = a.x * 1.5, a.y, b.x * 1.5, b.y, cx * 1.5, cy
		local vx, vy = bx - ax, by - ay
		local len2 = vx * vx + vy * vy
		local t = len2 > 0 and math.max(0, math.min(1, ((qx - ax) * vx + (qy - ay) * vy) / len2)) or 0
		local ex, ey = ax + vx * t - qx, ay + vy * t - qy
		local d = ex * ex + ey * ey
		if not bestD or d < bestD then best, bestD = (a.v or 0) + 1, d end
	end
	return best, spot
end
QL.DetourNearestPiece = nearestPiece

local function refreshPanel()
	if not panel then return end
	local name = QL.PathActive()
	panel.name:SetText(name or "")
	panel.edit:SetActive(editing)
	panel.detour:SetActive(detourEdit)
	local dspot = QL.DetourSpot()
	local dn = dspot and #QL.DetourPoints(dspot) or 0
	panel.go:SetLabel(follow and L("Stop") or L("Follow"))
	panel.go:SetActive(follow ~= nil)
	local n = name and #QL.PathPoints(name) or 0
	local len = name and QL.PathLength(name)
	if detourEdit then
		panel.info:SetText(L("Detour"):gsub("^%l", string.upper) .. "  ·  " .. L("%d points"):format(dn))
	else
	panel.info:SetText(name and (L("%d stops"):format(n) .. ((len and len > 0 and QL.DistanceTextYards) and ("  ·  " .. QL.DistanceTextYards(len)) or "")) or L("No route yet: press New"))
	end
	for _, b in ipairs({ panel.prev, panel.next, panel.edit, panel.undo, panel.go, panel.del, panel.detour, panel.reset }) do b:SetShown(panel.open) end
	panel.nameBox:SetShown(panel.open)
	panel.info:SetShown(panel.open)
	panel.toggle:SetActive(panel.open)
	panel.new:SetShown(panel.open)
end

local function cycle(step)
	local names = QL.PathNames()
	if #names == 0 then return end
	local cur, idx = QL.PathActive(), 1
	for i, n in ipairs(names) do if n == cur then idx = i end end
	idx = (idx - 1 + step) % #names + 1
	viewing = true
	QL.PathSelect(names[idx])
end

local function buildPanel()
	if panel or not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return end
	local T, C = QL.Theme, QL.Theme.C
	local holder = WorldMapFrame.ScrollContainer
	panel = CreateFrame("Frame", "QuestLineagePathPanel", holder)
	panel:SetPoint("TOPLEFT", holder, "TOPLEFT", 12, -12)
	panel:SetFrameLevel((holder:GetFrameLevel() or 1) + 40)
	panel:SetSize(262, 26)
	panel.open = false
	local function button(w, text, x, y, onClick)
		local b = T.Button(panel, w, 24)
		b:SetPoint("TOPLEFT", x, y)
		b:SetLabel(text)
		b:SetScript("OnClick", onClick)
		return b
	end
	panel.toggle = button(86, L("My route"), 0, 0, function()
		panel.open = not panel.open
		if panel.open then viewing = true else editing = false end
		if not panel.open then detourEdit = false end
		panel:SetHeight(panel.open and 118 or 26)
		refreshPanel(); changed()
	end)
	-- row 1: previous, name (editable), next, new
	panel.prev = button(24, "<", 0, -30, function() cycle(-1) end)
	panel.nameBox = T.Input(panel, 150, 24)
	panel.nameBox:SetPoint("LEFT", panel.prev, "RIGHT", 4, 0)
	panel.name = panel.nameBox
	panel.nameBox:SetScript("OnEnterPressed", function(self)
		local name = QL.PathActive()
		if name and not QL.PathRename(name, self:GetText()) then self:SetText(name) end
		self:ClearFocus()
	end)
	panel.nameBox:SetScript("OnEscapePressed", function(self) self:SetText(QL.PathActive() or ""); self:ClearFocus() end)
	panel.next = button(24, ">", 182, -30, function() cycle(1) end)
	panel.new = button(50, L("New"), 210, -30, function() viewing = true; QL.PathNew() end)
	-- row 2: edit, undo, follow, delete
	panel.edit = button(60, L("Edit"), 0, -58, function()
		if not QL.PathActive() then QL.PathNew() end
		editing = not editing
		if editing then detourEdit = false end
		viewing = true
		refreshPanel(); changed()
	end)
	panel.undo = button(60, L("Undo"), 64, -58, function() QL.PathUndo(QL.PathActive()) end)
	panel.go = button(70, L("Follow"), 128, -58, function()
		if follow then QL.PathStopFollow() else editing = false; QL.PathFollow(QL.PathActive()) end
		refreshPanel()
	end)
	panel.del = button(60, L("Delete"), 202, -58, function()
		local name = QL.PathActive()
		if not name then return end
		if QL.Theme.Confirm then
			QL.Theme.Confirm(L("Delete route"), L("Delete the route \"%s\"?"):format(name), L("Delete"), function() QL.PathDelete(name) end)
		else
			QL.PathDelete(name)
		end
	end)
	-- row 3: detour of the arrow's line (bend it round an obstacle), and its reset
	panel.detour = button(120, L("Detour"), 0, -86, function()
		if not detourEdit and not QL.DetourSpot() then
			QL.Print(L("Point the arrow at something first."), "warn")
			return
		end
		detourEdit = not detourEdit
		if detourEdit then editing = false end
		refreshPanel(); changed()
	end)
	panel.reset = button(120, L("Reset detour"), 124, -86, function()
		local spot = QL.DetourSpot()
		if not spot or #QL.DetourPoints(spot) == 0 then return end
		if QL.Theme.Confirm then
			QL.Theme.Confirm(L("Reset detour"), L("Remove this detour and go straight again?"), L("Reset detour"), function() QL.DetourClear(spot) end)
		else
			QL.DetourClear(spot)
		end
	end)
	panel.info = T.Text(panel, 10, C.muted)
	panel.info:SetPoint("TOPLEFT", 4, -114)
	panel:SetHeight(26)
	-- Shift + left click on the map puts a stop there (a plain click keeps its job: moving the map)
	holder:HookScript("OnMouseUp", function(_, button)
		if not (button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown()) then return end
		local map, x, y = shownMap(), worldCursor()
		if not (map and x) then return end
		if detourEdit then
			local at, spot = nearestPiece(map, x, y)
			if at then QL.DetourInsert(spot, at, map, x, y) end
		elseif editing then
			local name = QL.PathActive()
			if name then QL.PathAdd(name, map, x, y) end
		end
	end)
	WorldMapFrame:HookScript("OnHide", function() editing = false; viewing = false; detourEdit = false; dragIndex = nil; refreshPanel(); changed() end)
	-- dragging a stop's badge
	panel:SetScript("OnUpdate", function()
		if not dragIndex then return end
		if IsMouseButtonDown and IsMouseButtonDown("LeftButton") then
			local map, x, y = shownMap(), worldCursor()
			if map and x then
				if dragKind == "detour" then
					local spot = QL.DetourSpot()
					if spot then QL.DetourMove(spot, dragIndex, map, x, y) end
				else
					QL.PathMove(QL.PathActive(), dragIndex, map, x, y)
				end
			end
		else
			dragIndex = nil
		end
	end)
	QL.On("PATH_CHANGED", refreshPanel)
	refreshPanel()
end

local function hookMap()
	if QL.pathsHooked or not WorldMapFrame then return end
	QL.pathsHooked = true
	WorldMapFrame:HookScript("OnShow", function() pcall(buildPanel) end)
	if WorldMapFrame:IsShown() then pcall(buildPanel) end
end

-- the route settings: mapPaths hides the panel and the drawing
QL.On("SETTING_CHANGED", function(key)
	if key == "mapPaths" and panel then panel:SetShown(QL.DB().mapPaths ~= false) end
end)

QL.Event("PLAYER_LOGIN", function()
	pcall(hookMap)
	if CreateFrame then
		local f = CreateFrame("Frame")
		local since = 0
		f:SetScript("OnUpdate", function(_, dt)
			since = since + (dt or 0)
			if since < TICK then return end
			since = 0
			if follow then pcall(QL.PathCheck) end
		end)
		QL.pathWatcher = f
	end
	-- a followed route survives a reload
	local saved = type(QL.DB().pathFollow) == "table" and QL.DB().pathFollow[charKey()]
	if saved and saved.name and #QL.PathPoints(saved.name) > 0 then
		local function restore() pcall(QL.PathFollow, saved.name, saved.index) end
		if C_Timer and C_Timer.After then C_Timer.After(3, restore) else restore() end
	end
end)
QL.Event("ADDON_LOADED", function(_, name) if name == "Blizzard_WorldMap" then pcall(hookMap) end end)
