-- Quest areas: where the current quest's unfinished objectives are, drawn as soft rings on the
-- minimap and the world map in the window's look.
--
-- Each objective's spots (its creatures, objects, or the creatures dropping its item) are grouped
-- into areas: spots closer than LINK yards join one area; an area is a circle round its spots'
-- centre, padded. Each objective gets its own colour (accent, violet, amber, rose, ...).
--   world map  a filled disc, a ring, a soft glow, and the objective's name and counter above it
--   minimap    the disc and ring, kept inside the minimap's circle; an area beyond the edge shows
--              as a small mark on the rim pointing to it
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

local current = {} -- the areas being drawn, recomputed now and then

local function recompute()
	current = {}
	if QL.DB().questAreas == false then return end
	local ok, list = pcall(QL.QuestAreas, QL.CurrentQuest and QL.CurrentQuest())
	if ok then current = list end
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
	p.disc:SetTexture(MEDIA .. "disc")
	p.ring = mm:CreateTexture(nil, "ARTWORK", nil, 1)
	p.ring:SetTexture(MEDIA .. "ring")
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
					p.disc:SetSize(fit * 2, fit * 2)
					p.disc:ClearAllPoints(); p.disc:SetPoint("CENTER", Minimap, "CENTER", cx, cy)
					p.disc:SetVertexColor(c[1], c[2], c[3], 0.16)
					p.ring:SetSize(fit * 2, fit * 2)
					p.ring:ClearAllPoints(); p.ring:SetPoint("CENTER", Minimap, "CENTER", cx, cy)
					p.ring:SetVertexColor(c[1], c[2], c[3], 0.8)
					p.disc:Show(); p.ring:Show()
					QL.minimapAreaHits[#QL.minimapAreaHits + 1] = { x = cx, y = cy, r = fit, area = a }
				end
			end
			if dist > edge * 0.9 then
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
	p.glow = wm:CreateTexture(nil, "BORDER")
	p.glow:SetTexture(MEDIA .. "arrow_glow")
	p.disc = wm:CreateTexture(nil, "ARTWORK")
	p.disc:SetTexture(MEDIA .. "disc")
	p.ring = wm:CreateTexture(nil, "ARTWORK", nil, 1)
	p.ring:SetTexture(MEDIA .. "ring")
	p.label = T.Text(wm, 12, T.C.text, "OVERLAY", true)
	p.label:SetJustifyH("CENTER")
	p.label:SetShadowOffset(1, -1)
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
			p.glow:SetSize(r * 2.6, r * 2.6)
			p.glow:ClearAllPoints(); p.glow:SetPoint("CENTER", wm, "TOPLEFT", px, py)
			p.glow:SetVertexColor(c[1], c[2], c[3], 0.22)
			p.disc:SetSize(r * 2, r * 2)
			p.disc:ClearAllPoints(); p.disc:SetPoint("CENTER", wm, "TOPLEFT", px, py)
			p.disc:SetVertexColor(c[1], c[2], c[3], 0.18)
			p.ring:SetSize(r * 2, r * 2)
			p.ring:ClearAllPoints(); p.ring:SetPoint("CENTER", wm, "TOPLEFT", px, py)
			p.ring:SetVertexColor(c[1], c[2], c[3], 0.9)
			p.glow:Show(); p.disc:Show(); p.ring:Show()
			QL.worldAreaHits[#QL.worldAreaHits + 1] = { x = x, y = y, rx = r / cw, ry = r / ch, area = a }
			-- one label per objective, on its biggest area
			if not labelled[a.label or ""] then
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
		if hoverT >= 0.05 then hoverT = 0; pcall(QL.HoverWorldAreas) end
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
	local first = list[1]
	for _, a in ipairs(list) do
		local c = a.color or C.accent
		tip:AddLine("●  " .. (a.label or "?") .. (a.count and ("   " .. a.count) or ""), c[1], c[2], c[3])
	end
	tip:AddLine(L("Objective of %s"):format(QL.QuestTitle(first.questId)), C.muted[1], C.muted[2], C.muted[3])
	tip:AddLine(" ")
	QL.FillQuestTooltip(tip, first.questId)
	tip:Show()
end

local function keyOf(list)
	local parts = {}
	for _, a in ipairs(list) do parts[#parts + 1] = tostring(a) end
	return table.concat(parts, "|")
end

local function hover(which, owner, list)
	local tip = QL.Tip()
	if list and #list > 0 then
		local key = keyOf(list)
		if hovered[which] ~= key or tip.owner ~= owner or not tip:IsShown() then
			hovered[which] = key
			showAreaTip(owner, list)
		else
			tip:PlaceAtCursor() -- follow the cursor
		end
	elseif hovered[which] then
		hovered[which] = nil
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
			if since >= 0.05 then since = 0; pcall(drawMinimap); pcall(QL.HoverMinimapAreas) end
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
	if key == "questAreas" then pcall(QL.RefreshQuestAreas) end
	if key == "hideGameAreas" then pcall(QL.ApplyGameAreas) end
end)
