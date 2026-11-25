-- Quest areas: where the current quest's unfinished objectives are, drawn as soft rings on the
-- minimap and the world map in the window's look.
--
-- Each objective's spots (its creatures, objects, or the creatures dropping its item) are grouped
-- into areas: spots closer than LINK yards join one area; an area is a circle round its spots'
-- centre, padded. Each objective gets its own colour (accent, violet, amber, rose, ...).
--   world map  a filled disc, a ring, a soft glow, and the objective's name and counter above it
--   minimap    the disc and ring, kept inside the minimap's circle; an area beyond the edge shows
--              as a small mark on the rim pointing to it
-- Look (Media/area_*.tga from tools/make_icons.py): the current quest's areas are a soft fill
-- that rises towards the edge and a thin ring, breathing slowly; another quest's area is only a
-- faint dotted circle. The ring under the cursor brightens (another quest's gets a soft fill).
-- Hovering an area on either map shows the quest in a tooltip beside the cursor (no mouse frames
-- are added over the maps, so clicks, pings and map dragging work as before: the cursor is
-- tested against the drawn circles).
-- Settings: questAreas (on/off), hideGameAreas (the game's own blue quest area on the minimap).
--
--   QL.QuestAreas(id, ctx) -> { {map, x, y (0-1), r (yards), color, label, count}, ... }  (pure)
--   QL.RefreshQuestAreas()

local _, QL = ...
local L = QL.L

local MEDIA = "Interface\\AddOns\\QuestLineage\\Media\\"
local LINK = 70          -- yards: spots closer than this form one area
local PAD, MIN_R = 18, 25 -- yards added round an area; smallest radius
local MAX_AREAS = 6      -- per objective, the biggest first
local OUTDOOR = { [0] = 233.33, 200, 166.67, 133.33, 100, 66.67 }
local INDOOR = { [0] = 150, 120, 90, 60, 40, 25 }

local function mapSize(map)
	if not (C_Map and C_Map.GetMapWorldSize) then return nil end
	local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
	if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
	return nil
end

local function palette()
	local C = QL.Theme.C
	return { C.accent, C.accent2, { 0.984, 0.749, 0.141 }, { 0.957, 0.447, 0.714 }, { 0.376, 0.647, 0.980 }, { 0.290, 0.871, 0.502 } }
end

-- Areas ----------------------------------------------------------------------------------------------

-- Greedy single-link grouping of spots on one map (in yards).
local function cluster(points, w, h)
	local groups, seen = {}, {}
	for i, p in ipairs(points) do
		if not seen[i] then
			local g = { p }
			seen[i] = true
			local k = 1
			while k <= #g do
				local a = g[k]
				for j, q in ipairs(points) do
					if not seen[j] then
						local dx, dy = (q.x - a.x) * w, (q.y - a.y) * h
						if dx * dx + dy * dy <= LINK * LINK then
							seen[j] = true
							g[#g + 1] = q
						end
					end
				end
				k = k + 1
			end
			groups[#groups + 1] = g
		end
	end
	return groups
end

local function objectiveSpots(task)
	if task.kind == "npc" or task.kind == "object" then return QL.SpawnPoints(task.kind, task.id) end
	if task.kind == "item" then return QL.SpawnPoints("item", task.id) end
	return {}
end

function QL.QuestAreas(id, ctx)
	local out = {}
	if not id then return out end
	ctx = ctx or QL.Context()
	if QL.NodeStatus(id, ctx) ~= "active" then return out end
	local colors = palette()
	for i, row in ipairs(QL.ObjectiveRows(id, ctx)) do
		if not row.done and row.task then
			local byMap = {}
			for _, p in ipairs(objectiveSpots(row.task)) do
				local list = byMap[p.map]
				if not list then list = {}; byMap[p.map] = list end
				list[#list + 1] = p
			end
			local areas = {}
			for map, points in pairs(byMap) do
				local w, h = mapSize(map)
				if w then
					for _, g in ipairs(cluster(points, w, h)) do
						local cx, cy = 0, 0
						for _, p in ipairs(g) do cx, cy = cx + p.x, cy + p.y end
						cx, cy = cx / #g, cy / #g
						local r = 0
						for _, p in ipairs(g) do
							local dx, dy = (p.x - cx) * w, (p.y - cy) * h
							r = math.max(r, math.sqrt(dx * dx + dy * dy))
						end
						areas[#areas + 1] = { map = map, x = cx, y = cy, r = math.max(MIN_R, r + PAD), size = #g }
					end
				end
			end
			table.sort(areas, function(a, b) return a.size > b.size end)
			local label = row.task.name or row.text
			local count = (row.need and row.need > 0) and ("%d/%d"):format(row.have or 0, row.need) or nil
			for k, a in ipairs(areas) do
				if k > MAX_AREAS then break end
				a.color = colors[(i - 1) % #colors + 1]
				a.label, a.count, a.questId = label, count, id
				out[#out + 1] = a
			end
		end
	end
	return out
end

-- The areas being drawn, recomputed now and then: the other quests' first (soft, one colour per
-- quest, setting questAreasOthers), the current quest's last so they sit on top.
local current = {}
local others, othersAt, othersFor = {}, -999, nil
local OTHERS_EVERY = 10 -- seconds between two rebuilds of the other quests' areas
local OTHER_COLORS = {
	{ 0.96, 0.62, 0.30 }, { 0.40, 0.78, 0.98 }, { 0.93, 0.47, 0.70 }, { 0.62, 0.86, 0.38 },
	{ 0.98, 0.84, 0.36 }, { 0.70, 0.60, 0.98 }, { 0.45, 0.90, 0.80 }, { 0.98, 0.50, 0.45 },
}

local function clock() return (GetTime and GetTime()) or 0 end

local function rebuildOthers(ctx, currentId)
	others = {}
	local ids = {}
	for id in pairs(ctx.log or {}) do
		if id ~= currentId and not (ctx.complete and ctx.complete[id]) then ids[#ids + 1] = id end
	end
	table.sort(ids)
	for k, id in ipairs(ids) do
		local ok, list = pcall(QL.QuestAreas, id, ctx)
		if ok then
			local c = OTHER_COLORS[(k - 1) % #OTHER_COLORS + 1]
			for _, a in ipairs(list or {}) do
				a.color, a.other = c, true
				others[#others + 1] = a
			end
		end
	end
	othersAt, othersFor = clock(), currentId
end

local function recompute(force)
	current = {}
	if QL.DB().questAreas == false then return end
	local ctx = QL.Context()
	local id = QL.CurrentQuest and QL.CurrentQuest(ctx)
	if QL.DB().questAreasOthers ~= false then
		if force or othersFor ~= id or clock() - othersAt > OTHERS_EVERY then rebuildOthers(ctx, id) end
		for _, a in ipairs(others) do current[#current + 1] = a end
	end
	local ok, list = pcall(QL.QuestAreas, id, ctx)
	if ok then for _, a in ipairs(list or {}) do current[#current + 1] = a end end
	QL.drawnAreas = current
end

-- Look ------------------------------------------------------------------------------------------------

local hot = { minimap = {}, world = {} } -- the areas under the cursor, per map

local function lit(a) return hot.minimap[a] or hot.world[a] end

-- Paints one area's parts (disc = soft fill, ring = thin or dotted circle) at a point.
local function style(p, a, size, anchor, point, x, y)
	local c = a.color
	local on = lit(a)
	p.disc:SetSize(size, size)
	p.disc:ClearAllPoints(); p.disc:SetPoint("CENTER", anchor, point, x, y)
	p.ring:SetSize(size, size)
	p.ring:ClearAllPoints(); p.ring:SetPoint("CENTER", anchor, point, x, y)
	if a.other then
		p.ring:SetTexture(MEDIA .. "area_dash")
		p.look = "dotted"
		p.ring:SetVertexColor(c[1], c[2], c[3], on and 0.95 or 0.42)
		p.disc:SetVertexColor(c[1], c[2], c[3], 0.28)
		p.disc:SetShown(on and true or false)
		p.breathe = false
	else
		p.ring:SetTexture(MEDIA .. "area_ring")
		p.look = "ring"
		p.ring:SetVertexColor(c[1], c[2], c[3], on and 1 or 0.7)
		p.disc:SetVertexColor(c[1], c[2], c[3], on and 0.7 or 0.42)
		p.disc:Show()
		p.breathe = not on
	end
	p.disc:SetAlpha(1)
	p.ring:Show()
end

-- the current quest's fills breathe slowly (a gentle rise and fall, never a blink)
local function breathe(parts, t)
	local f = 0.78 + 0.22 * math.sin((t or 0) * 1.4)
	for _, p in ipairs(parts) do
		if p.breathe and p.disc:IsShown() then p.disc:SetAlpha(f) end
	end
end

-- Minimap ---------------------------------------------------------------------------------------------

local mm, mmParts, rimParts = nil, {}, {}

local function indoors()
	local zoom = Minimap:GetZoom() or 0
	local out = tonumber(GetCVar and GetCVar("minimapZoom"))
	local inside = tonumber(GetCVar and GetCVar("minimapInsideZoom"))
	if out and inside and out ~= inside then return zoom == inside end
	return IsIndoors and IsIndoors() and true or false
end

-- The minimap's radius in yards at its zoom.
function QL.MinimapYards()
	local zoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
	return (indoors() and INDOOR or OUTDOOR)[zoom] or 150
end

-- dx, dy in yards (y down) -> minimap offset where the rim is 1 (x right, y up).
function QL.MinimapOffset(dx, dy, facing, rotate, radius)
	local ux, uy = dx, -dy
	if rotate and facing then
		local c, s = math.cos(facing), math.sin(facing)
		ux, uy = ux * c + uy * s, -ux * s + uy * c
	end
	return ux / radius, uy / radius
end

local function mmPart(i)
	local p = mmParts[i]
	if p then return p end
	p = {}
	p.disc = mm:CreateTexture(nil, "ARTWORK")
	p.disc:SetTexture(MEDIA .. "area_soft")
	p.ring = mm:CreateTexture(nil, "ARTWORK", nil, 1)
	p.ring:SetTexture(MEDIA .. "area_ring")
	mmParts[i] = p
	return p
end

local function rimPart(i)
	local d = rimParts[i]
	if d then return d end
	d = mm:CreateTexture(nil, "OVERLAY")
	d:SetTexture(MEDIA .. "disc")
	d:SetSize(7, 7)
	rimParts[i] = d
	return d
end

local function drawMinimap()
	for _, p in ipairs(mmParts) do p.disc:Hide(); p.ring:Hide() end
	for _, d in ipairs(rimParts) do d:Hide() end
	QL.minimapAreasDrawn, QL.minimapRimMarks = 0, 0 -- what was drawn last (tests read it)
	QL.minimapAreaHits = {} -- { {x, y, r, area} } in minimap units from its centre
	if #current == 0 or not Minimap:IsVisible() then return end
	local map, px, py = QL.PlayerPosition()
	if not map or not px then return end
	local w, h = mapSize(map)
	if not w then return end
	local radius = QL.MinimapYards()
	local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
	local facing = GetPlayerFacing and GetPlayerFacing()
	if facing ~= nil and issecretvalue and issecretvalue(facing) then facing = nil end
	local half = (Minimap:GetWidth() or 140) / 2
	local edge = half * 0.96
	local n, rims = 0, 0
	for _, a in ipairs(current) do
		local ax, ay = QL.ProjectToMap(a.map, a.x, a.y, map)
		if ax then
			local nx, ny = QL.MinimapOffset((ax - px) * w, (ay - py) * h, facing, rotate, radius)
			local cx, cy = nx * half, ny * half
			local dist = math.sqrt(cx * cx + cy * cy)
			local r = a.r / radius * half
			local c = a.color
			if dist - r < edge then
				-- inside or overlapping the minimap: keep the circle within the rim
				local fit = math.min(r, edge - dist)
				if fit < 6 then fit = nil end
				if fit then
					n = n + 1
					local p = mmPart(n)
					style(p, a, fit * 2, Minimap, "CENTER", cx, cy)
					QL.minimapAreaHits[#QL.minimapAreaHits + 1] = { x = cx, y = cy, r = fit, area = a }
				end
			end
			if dist > edge * 0.9 and not a.other then
				-- beyond (or at) the edge: a mark on the rim pointing at it
				rims = rims + 1
				local d = rimPart(rims)
				local k = edge * 0.92 / math.max(dist, 1)
				d:ClearAllPoints(); d:SetPoint("CENTER", Minimap, "CENTER", cx * k, cy * k)
				d:SetVertexColor(c[1], c[2], c[3], 0.95)
				d:Show()
			end
		end
	end
	QL.minimapAreasDrawn, QL.minimapRimMarks = n, rims
end

-- World map --------------------------------------------------------------------------------------------

local wm, wmParts = nil, {}

local function wmPart(i)
	local p = wmParts[i]
	if p then return p end
	local T = QL.Theme
	p = {}
	p.glow = wm:CreateTexture(nil, "BORDER") -- kept for older callers; not shown any more
	p.glow:Hide()
	p.disc = wm:CreateTexture(nil, "ARTWORK")
	p.disc:SetTexture(MEDIA .. "area_soft")
	p.ring = wm:CreateTexture(nil, "ARTWORK", nil, 1)
	p.ring:SetTexture(MEDIA .. "area_ring")
	p.label = T.Text(wm, 11, T.C.text, "OVERLAY", true)
	p.label:SetJustifyH("CENTER")
	p.label:SetShadowOffset(1, -1)
	p.label:SetAlpha(0.85)
	wmParts[i] = p
	return p
end

local function canvasScale()
	if WorldMapFrame and WorldMapFrame.GetCanvasScale then
		local ok, s = pcall(WorldMapFrame.GetCanvasScale, WorldMapFrame)
		if ok and type(s) == "number" and s > 0 then return s end
	end
	return 1
end

local function drawWorldMap()
	for _, p in ipairs(wmParts) do p.glow:Hide(); p.disc:Hide(); p.ring:Hide(); p.label:Hide() end
	QL.worldAreaHits = {} -- { {x, y, rx, ry, area} } in the shown map's 0-1 coordinates
	if not wm or #current == 0 then return end
	local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local cw, ch = wm:GetWidth() or 0, wm:GetHeight() or 0
	local mw = mapID and mapSize(mapID)
	if not mapID or cw <= 0 or not mw then return end
	local zoom = canvasScale()
	local n = 0
	local labelled = {}
	for _, a in ipairs(current) do
		local x, y = QL.ProjectToMap(a.map, a.x, a.y, mapID)
		if x and x > -0.1 and x < 1.1 and y > -0.1 and y < 1.1 then
			n = n + 1
			local p = wmPart(n)
			local r = math.max(10 / zoom, a.r / mw * cw)
			local c = a.color
			local px, py = x * cw, -y * ch
			style(p, a, r * 2, wm, "TOPLEFT", px, py)
			p.glow:Hide()
			QL.worldAreaHits[#QL.worldAreaHits + 1] = { x = x, y = y, rx = r / cw, ry = r / ch, area = a }
			-- one label per objective, on its biggest area
			if not a.other and not labelled[a.label or ""] then
				labelled[a.label or ""] = true
				p.label:SetText((a.label or "") .. (a.count and ("  " .. QL.Theme.Hex(c) .. a.count .. "|r") or ""))
				p.label:SetScale(1 / zoom)
				p.label:ClearAllPoints()
				p.label:SetPoint("BOTTOM", wm, "TOPLEFT", px * zoom, (py + r) * zoom + 4)
				p.label:Show()
			end
		end
	end
end

local function ensureWorld()
	if wm or not (WorldMapFrame and WorldMapFrame.GetCanvas) then return end
	local canvas = WorldMapFrame:GetCanvas()
	if not canvas then return end
	wm = CreateFrame("Frame", nil, canvas)
	wm:SetAllPoints(canvas)
	local manager = WorldMapFrame.pinFrameLevelsManager
	local defs = manager and manager.definitions
	local level = defs and defs.PIN_FRAME_LEVEL_DIG_SITE
	if level and level.overrideType then level = defs[level.overrideType] end
	-- just under the route overlay, so the route and its badges stay on top
	wm:SetFrameLevel(((level and level.startLevel) or (canvas:GetFrameLevel() + 2100)) - 1)
	local since = 0
	local hoverT = 0
	wm:SetScript("OnUpdate", function(_, elapsed)
		since = since + (elapsed or 0)
		hoverT = hoverT + (elapsed or 0)
		if since >= 0.5 then since = 0; pcall(drawWorldMap) end
		if hoverT >= 0.05 then hoverT = 0; pcall(QL.HoverWorldAreas); breathe(wmParts, clock()) end
	end)
	if wm.SetScript and WorldMapFrame.HookScript then
		WorldMapFrame:HookScript("OnHide", function() hover("world", wm, nil) end)
	end
	if hooksecurefunc and WorldMapFrame.SetMapID then
		hooksecurefunc(WorldMapFrame, "SetMapID", function() pcall(drawWorldMap) end)
	end
end

-- The game's own quest area on the minimap ---------------------------------------------------------

function QL.ApplyGameAreas()
	if not Minimap then return end
	local hide = QL.DB().hideGameAreas == true
	for _, m in ipairs({ "SetQuestBlobRingAlpha", "SetQuestBlobInsideAlpha", "SetQuestBlobOutsideAlpha", "SetArchBlobRingAlpha", "SetArchBlobInsideAlpha" }) do
		if Minimap[m] then
			-- hidden: 0; shown: the game's usual look (a faint fill, a clear ring)
			local v = hide and 0 or (m:find("Ring") and 1 or (m:find("Inside") and 0.1 or 0))
			pcall(Minimap[m], Minimap, v)
		end
	end
end

-- Hover --------------------------------------------------------------------------------------------------

-- The smallest area under a point. hits: {x, y, r} or {x, y, rx, ry}.
function QL.AreaAt(hits, x, y)
	local best, bestSize
	for _, h in ipairs(hits or {}) do
		local rx, ry = h.rx or h.r, h.ry or h.r
		if rx and ry and rx > 0 and ry > 0 then
			local dx, dy = (x - h.x) / rx, (y - h.y) / ry
			if dx * dx + dy * dy <= 1 and (not bestSize or rx * ry < bestSize) then
				best, bestSize = h.area, rx * ry
			end
		end
	end
	return best
end

-- Every area under a point, smallest first, one per objective (rings of the same objective that
-- overlap count once).
function QL.AreasAt(hits, x, y)
	local found = {}
	for _, h in ipairs(hits or {}) do
		local rx, ry = h.rx or h.r, h.ry or h.r
		if rx and ry and rx > 0 and ry > 0 then
			local dx, dy = (x - h.x) / rx, (y - h.y) / ry
			if dx * dx + dy * dy <= 1 then found[#found + 1] = { area = h.area, size = rx * ry } end
		end
	end
	table.sort(found, function(a, b) return a.size < b.size end)
	local out, seen = {}, {}
	for _, f in ipairs(found) do
		local key = type(f.area) == "table" and ((f.area.questId or "") .. ":" .. (f.area.label or "")) or tostring(f.area)
		if not seen[key] then seen[key] = true; out[#out + 1] = f.area end
	end
	return out
end

local hovered = { minimap = nil, world = nil } -- what each map's tooltip shows (a key)

-- The tooltip leads with the objective(s) under the cursor, each in its ring's colour with its
-- counter; the quest they belong to follows.
local function showAreaTip(owner, list)
	local T, C = QL.Theme, QL.Theme.C
	local tip = QL.Tip()
	tip:SetOwner(owner, "ANCHOR_CURSOR")
	-- the current quest's rings first, then the smallest
	table.sort(list, function(x, y) return (x.other and 1 or 0) < (y.other and 1 or 0) end)
	local first = list[1]
	local several = false
	for _, a in ipairs(list) do if a.questId ~= first.questId then several = true end end
	for _, a in ipairs(list) do
		local c = a.color or C.accent
		local line = "●  " .. (a.label or "?") .. (a.count and ("   " .. a.count) or "")
		if several then line = line .. "   " .. T.Hex(C.muted) .. QL.QuestTitle(a.questId) .. "|r" end
		tip:AddLine(line, c[1], c[2], c[3])
	end
	if not several then
		tip:AddLine(L("Objective of %s"):format(QL.QuestTitle(first.questId)), C.muted[1], C.muted[2], C.muted[3])
	end
	tip:AddLine(" ")
	QL.FillQuestTooltip(tip, first.questId)
	tip:Show()
end

local function keyOf(list)
	local parts = {}
	for _, a in ipairs(list) do parts[#parts + 1] = tostring(a) end
	return table.concat(parts, "|")
end

QL.AreaParts = function() return mmParts, wmParts end -- for tests

local function setHot(which, list)
	hot[which] = {}
	for _, a in ipairs(list or {}) do hot[which][a] = true end
	pcall(drawMinimap)
	pcall(drawWorldMap)
end

local function hover(which, owner, list)
	local tip = QL.Tip()
	if list and #list > 0 then
		local key = keyOf(list)
		if hovered[which] ~= key or tip.owner ~= owner or not tip:IsShown() then
			hovered[which] = key
			setHot(which, list)
			showAreaTip(owner, list)
		else
			tip:PlaceAtCursor() -- follow the cursor
		end
	elseif hovered[which] then
		hovered[which] = nil
		setHot(which, nil)
		if tip.owner == owner then tip:Hide() end
	end
end

local function mouseOver(f)
	if not (f and f.IsMouseOver and f.IsVisible) then return false end
	local ok, over = pcall(f.IsMouseOver, f)
	return ok and over == true and f:IsVisible() == true
end

-- The cursor over the minimap, in minimap units from its centre (x right, y up).
local function minimapCursor()
	local cx, cy = Minimap:GetCenter()
	if type(cx) ~= "number" or type(cy) ~= "number" then return nil end
	local x, y = GetCursorPosition()
	local s = Minimap:GetEffectiveScale() or 1
	return x / s - cx, y / s - cy
end

function QL.HoverMinimapAreas()
	local a
	if #current > 0 and mouseOver(Minimap) and GetCursorPosition then
		local x, y = minimapCursor()
		if x then a = QL.AreasAt(QL.minimapAreaHits, x, y) end
	end
	hover("minimap", Minimap, a)
end

-- The cursor over the world map, in the shown map's 0-1 coordinates.
local function worldCursor()
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	if sc and sc.GetNormalizedCursorPosition then
		local ok, x, y = pcall(sc.GetNormalizedCursorPosition, sc)
		if ok and type(x) == "number" and type(y) == "number" then return x, y end
	end
	return nil
end

function QL.HoverWorldAreas()
	local a
	if wm and #current > 0 and WorldMapFrame and mouseOver(WorldMapFrame.ScrollContainer or WorldMapFrame) then
		local x, y = worldCursor()
		if x then a = QL.AreasAt(QL.worldAreaHits, x, y) end
	end
	hover("world", wm, a)
end

-- Wiring ------------------------------------------------------------------------------------------------

function QL.RefreshQuestAreas()
	recompute()
	pcall(drawMinimap)
	pcall(drawWorldMap)
end

QL.Event("PLAYER_LOGIN", function()
	if Minimap and CreateFrame then
		mm = CreateFrame("Frame", "QuestLineageMinimapAreas", Minimap)
		mm:SetAllPoints()
		mm:SetFrameLevel(Minimap:GetFrameLevel() + 3)
		local since, again = 0, 0
		mm:SetScript("OnUpdate", function(_, elapsed)
			since = since + (elapsed or 0)
			again = again + (elapsed or 0)
			if again >= 2 then again = 0; recompute() end -- objectives move on, the current quest changes
			if since >= 0.05 then
				since = 0
				pcall(drawMinimap)
				pcall(QL.HoverMinimapAreas)
				breathe(mmParts, clock())
			end
		end)
	end
	if WorldMapFrame and WorldMapFrame.HookScript then
		WorldMapFrame:HookScript("OnShow", function() pcall(ensureWorld); pcall(drawWorldMap) end)
	end
	pcall(QL.ApplyGameAreas)
	if C_Timer and C_Timer.After then C_Timer.After(3, function() pcall(QL.RefreshQuestAreas) end) end
end)
for _, m in ipairs({ "STATE_CHANGED", "ARROW_CHANGED", "INDEX_READY" }) do
	QL.On(m, function() pcall(QL.RefreshQuestAreas) end)
end
QL.On("SETTING_CHANGED", function(key)
	if key == "questAreas" or key == "questAreasOthers" then othersAt = -999; pcall(QL.RefreshQuestAreas) end
	if key == "hideGameAreas" then pcall(QL.ApplyGameAreas) end
end)
