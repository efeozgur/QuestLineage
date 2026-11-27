-- The way back to your corpse: while you are dead, a glowing violet path runs from you to your
-- corpse on the minimap and on the world map, dots flowing along it towards a tombstone with a
-- pulsing ring; the arrow points at the corpse ("Your corpse") and returns to its quest once you
-- are alive again.
--
-- Where the corpse is: the client's C_DeathInfo.GetCorpseMapPosition (known once you release),
-- else the spot where you died (saved per character, so a /reload as a ghost keeps it).
-- Setting corpseRoute (on by default).
--
--   QL.CorpsePosition() -> map, x, y | nil      QL.IsDead()      QL.RefreshCorpse()

local _, QL = ...
local L = QL.L

local MEDIA = "Interface\\AddOns\\QuestLineage\\Media\\"
local DOT_GAP = 14  -- pixels between flowing dots
local DOT_SPEED = 22 -- pixels per second

local function color() return QL.Theme.HUD.accent2 end

local function charKey()
	local name = UnitName and UnitName("player") or "?"
	local realm = GetRealmName and GetRealmName() or "?"
	return tostring(name) .. "-" .. tostring(realm)
end

local function savedSpots()
	local db = QL.DB()
	if type(db.deathSpots) ~= "table" then db.deathSpots = {} end
	return db.deathSpots
end

function QL.IsDead()
	if not UnitIsDeadOrGhost then return false end
	local ok, dead = pcall(UnitIsDeadOrGhost, "player")
	return ok and dead == true
end

local function plainNumber(v)
	if type(v) ~= "number" then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- The corpse on the player's current map (the client's own answer), else where you died.
function QL.CorpsePosition()
	local map = QL.PlayerPosition()
	if map and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
		local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, map)
		if ok and pos and pos.GetXY then
			local x, y = pos:GetXY()
			x, y = plainNumber(x), plainNumber(y)
			if x and y and not (x == 0 and y == 0) then return map, x, y end
		end
	end
	local spot = savedSpots()[charKey()]
	if type(spot) == "table" and spot.map and spot.x and spot.y then return spot.map, spot.x, spot.y end
	return nil
end

local function mapSize(map)
	if not (C_Map and C_Map.GetMapWorldSize) then return nil end
	local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
	if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
	return nil
end

-- Clips the segment a-b to a circle of radius r round the origin; nil when it lies outside.
function QL.ClipToCircle(ax, ay, bx, by, r)
	local function inside(x, y) return x * x + y * y <= r * r end
	if inside(ax, ay) and inside(bx, by) then return ax, ay, bx, by end
	local dx, dy = bx - ax, by - ay
	local A = dx * dx + dy * dy
	if A == 0 then return nil end
	local B = 2 * (ax * dx + ay * dy)
	local C = ax * ax + ay * ay - r * r
	local disc = B * B - 4 * A * C
	if disc < 0 then return nil end
	local sq = math.sqrt(disc)
	local s, e = math.max(0, (-B - sq) / (2 * A)), math.min(1, (-B + sq) / (2 * A))
	if s > e then return nil end
	return ax + dx * s, ay + dy * s, ax + dx * e, ay + dy * e
end

local active = false -- the path is shown
local clock = 0      -- drives the flowing dots and the pulse

-- A path's parts on one frame: a soft glow line, a core line, flowing dots, the marker.
local function newPath(parent, level)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)
	if level then f:SetFrameLevel(level) end
	f.glow = f:CreateLine(nil, "BORDER")
	f.core = f:CreateLine(nil, "ARTWORK")
	f.dots = {}
	f.pulse = f:CreateTexture(nil, "ARTWORK", nil, 2)
	f.pulse:SetTexture(MEDIA .. "ring")
	f.halo = f:CreateTexture(nil, "ARTWORK", nil, 1)
	f.halo:SetTexture(MEDIA .. "arrow_glow")
	f.mark = f:CreateTexture(nil, "OVERLAY", nil, 2)
	f.mark:SetTexture(MEDIA .. "corpse")
	return f
end

local function hidePath(f)
	if not f then return end
	f.glow:Hide(); f.core:Hide(); f.pulse:Hide(); f.halo:Hide(); f.mark:Hide()
	for _, d in ipairs(f.dots) do d:Hide() end
	if f.label then f.label:Hide() end
	f.drawn = false
end

-- Draws a path on f from (ax, ay) to (bx, by), relative to anchor's point; the marker at b when
-- showMark. zoom scales the sizes back on a zoomed map canvas.
local function drawPath(f, anchor, point, ax, ay, bx, by, showMark, zoom)
	zoom = zoom or 1
	local c = color()
	local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
	if len > 1 then
		f.glow:SetThickness(7 / zoom)
		f.glow:SetColorTexture(c[1], c[2], c[3], 0.22)
		f.glow:SetStartPoint(point, anchor, ax, ay); f.glow:SetEndPoint(point, anchor, bx, by)
		f.glow:Show()
		f.core:SetThickness(2.2 / zoom)
		f.core:SetColorTexture(c[1], c[2], c[3], 0.9)
		f.core:SetStartPoint(point, anchor, ax, ay); f.core:SetEndPoint(point, anchor, bx, by)
		f.core:Show()
	else
		f.glow:Hide(); f.core:Hide()
	end
	-- dots flowing from you to the corpse
	local gap = DOT_GAP / zoom
	local n = 0
	if len > gap then
		local ux, uy = (bx - ax) / len, (by - ay) / len
		local t = (clock * DOT_SPEED / zoom) % gap
		while t < len - 4 / zoom do
			n = n + 1
			local d = f.dots[n]
			if not d then
				d = f:CreateTexture(nil, "ARTWORK", nil, 3)
				d:SetTexture(MEDIA .. "disc")
				f.dots[n] = d
			end
			d:SetSize(4 / zoom, 4 / zoom)
			d:ClearAllPoints(); d:SetPoint("CENTER", anchor, point, ax + ux * t, ay + uy * t)
			-- brighter towards the corpse
			d:SetVertexColor(1, 1, 1, 0.45 + 0.5 * (t / len))
			d:Show()
			t = t + gap
		end
	end
	for i = n + 1, #f.dots do f.dots[i]:Hide() end
	if showMark then
		local wave = (math.sin(clock * 3) + 1) / 2
		local ps = (18 + 14 * ((clock * 0.8) % 1)) / zoom
		f.pulse:SetSize(ps, ps)
		f.pulse:ClearAllPoints(); f.pulse:SetPoint("CENTER", anchor, point, bx, by)
		f.pulse:SetVertexColor(c[1], c[2], c[3], 0.8 * (1 - (clock * 0.8) % 1))
		f.halo:SetSize(34 / zoom, 34 / zoom)
		f.halo:ClearAllPoints(); f.halo:SetPoint("CENTER", anchor, point, bx, by)
		f.halo:SetVertexColor(c[1], c[2], c[3], 0.25 + 0.2 * wave)
		f.mark:SetSize(16 / zoom, 16 / zoom)
		f.mark:ClearAllPoints(); f.mark:SetPoint("CENTER", anchor, point, bx, by)
		f.mark:SetVertexColor(0.92 + 0.08 * wave, 0.9 + 0.1 * wave, 1, 1)
		f.pulse:Show(); f.halo:Show(); f.mark:Show()
	else
		f.pulse:Hide(); f.halo:Hide(); f.mark:Hide()
	end
	f.drawn = true
end

-- Minimap -------------------------------------------------------------------------------------------

local mmPath

local function drawMinimap()
	if not mmPath then return end
	hidePath(mmPath)
	if not active or not Minimap:IsVisible() then return end
	local map, px, py = QL.PlayerPosition()
	if not map or not px then return end
	local cmap, cx, cy = QL.CorpsePosition()
	if not cmap then return end
	local x, y = QL.ProjectToMap(cmap, cx, cy, map)
	local w, h = mapSize(map)
	if not x or not w then return end
	local radius = QL.MinimapYards and QL.MinimapYards() or 150
	local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
	local facing = GetPlayerFacing and GetPlayerFacing()
	if facing ~= nil and issecretvalue and issecretvalue(facing) then facing = nil end
	local nx, ny = QL.MinimapOffset((x - px) * w, (y - py) * h, facing, rotate, radius)
	local half = (Minimap:GetWidth() or 140) / 2
	local bx, by = nx * half, ny * half
	local edge = half * 0.94
	local dist = math.sqrt(bx * bx + by * by)
	local inside = dist <= edge
	if not inside then bx, by = bx / dist * edge, by / dist * edge end -- the marker waits on the rim
	local ax, ay, ex, ey = QL.ClipToCircle(0, 0, bx, by, edge)
	if not ax then return end
	drawPath(mmPath, Minimap, "CENTER", ax, ay, ex, ey, true, 1)
	mmPath.mark:SetAlpha(inside and 1 or 0.75)
	QL.corpseOnMinimap = { x = bx, y = by, inside = inside }
end

-- World map ---------------------------------------------------------------------------------------------

local wmPath

local function canvasScale()
	if WorldMapFrame and WorldMapFrame.GetCanvasScale then
		local ok, s = pcall(WorldMapFrame.GetCanvasScale, WorldMapFrame)
		if ok and type(s) == "number" and s > 0 then return s end
	end
	return 1
end

local function drawWorld()
	if not wmPath then return end
	hidePath(wmPath)
	if not active then return end
	local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local cw, ch = wmPath:GetWidth() or 0, wmPath:GetHeight() or 0
	if not mapID or cw <= 0 then return end
	local cmap, cx, cy = QL.CorpsePosition()
	if not cmap then return end
	local x, y = QL.ProjectToMap(cmap, cx, cy, mapID)
	if not x or x < 0 or x > 1 or y < 0 or y > 1 then return end
	local zoom = canvasScale()
	local bx, by = x * cw, -y * ch
	local map, px, py = QL.PlayerPosition()
	local ax, ay = bx, by
	if map and px then
		local qx, qy = QL.ProjectToMap(map, px, py, mapID)
		if qx then ax, ay = qx * cw, -qy * ch end
	end
	drawPath(wmPath, wmPath, "TOPLEFT", ax, ay, bx, by, true, zoom)
	-- "Your corpse · 230 yd" above the tombstone
	local lbl = wmPath.label
	local text = L("Your corpse")
	local w, h = mapSize(mapID)
	if w and map and px then
		local qx, qy = QL.ProjectToMap(map, px, py, mapID)
		if qx then
			local d = math.sqrt(((x - qx) * w) ^ 2 + ((y - qy) * h) ^ 2)
			text = text .. "  ·  " .. QL.FormatDistance(d)
		end
	end
	lbl:SetText(text)
	lbl:SetScale(1 / zoom)
	lbl:ClearAllPoints()
	lbl:SetPoint("BOTTOM", wmPath, "TOPLEFT", bx * zoom, by * zoom + 14)
	lbl:Show()
end

local function ensureWorld()
	if wmPath or not (WorldMapFrame and WorldMapFrame.GetCanvas) then return end
	local canvas = WorldMapFrame:GetCanvas()
	if not canvas then return end
	local manager = WorldMapFrame.pinFrameLevelsManager
	local defs = manager and manager.definitions
	local level = defs and defs.PIN_FRAME_LEVEL_DIG_SITE
	if level and level.overrideType then level = defs[level.overrideType] end
	-- above the quest route and areas: while dead the corpse matters most
	wmPath = newPath(canvas, ((level and level.startLevel) or (canvas:GetFrameLevel() + 2100)) + 40)
	if not wmPath.glow then wmPath = nil; return end
	local T = QL.Theme
	wmPath.label = T.Text(wmPath, 12, T.HUD.text, "OVERLAY", true)
	wmPath.label:SetShadowOffset(1, -1)
	local since = 0
	wmPath:SetScript("OnUpdate", function(_, elapsed)
		since = since + (elapsed or 0)
		if since >= 0.03 then since = 0; pcall(drawWorld) end
	end)
end

-- Arrow ---------------------------------------------------------------------------------------------

local arrowBefore -- the quest the arrow showed before you died (restored on coming back)

local function pointArrow()
	if not QL.SetArrowPoint then return end
	local cmap, cx, cy = QL.CorpsePosition()
	if not cmap then return end
	local t = QL.ArrowTarget and QL.ArrowTarget()
	if t and t.corpse and t.points[1] and t.points[1].map == cmap and t.points[1].x == cx and t.points[1].y == cy then return end
	if not (t and t.corpse) then arrowBefore = QL.ArrowQuest and QL.ArrowQuest() end
	QL.SetArrowPoint(cmap, cx, cy, { title = L("Your corpse"), label = L("Back to your body"), corpse = true })
end

local function releaseArrow()
	local t = QL.ArrowTarget and QL.ArrowTarget()
	if not (t and t.corpse) then arrowBefore = nil; return end
	local back = arrowBefore
	arrowBefore = nil
	if back and QL.SetArrowTarget then QL.SetArrowTarget(back, true) else QL.ClearArrow() end
end

-- Wiring --------------------------------------------------------------------------------------------

function QL.RefreshCorpse()
	local was = active
	active = QL.DB().corpseRoute ~= false and QL.IsDead() and QL.CorpsePosition() ~= nil
	if active then
		pcall(pointArrow)
	elseif was or (QL.ArrowTarget and QL.ArrowTarget() and QL.ArrowTarget().corpse) then
		pcall(releaseArrow)
	end
	if not QL.IsDead() then savedSpots()[charKey()] = nil end
	pcall(drawMinimap)
	pcall(drawWorld)
	if not active then hidePath(mmPath); hidePath(wmPath) end
	QL.corpseActive = active
end

QL.Event("PLAYER_DEAD", function()
	local map, x, y = QL.PlayerPosition()
	if map and x then savedSpots()[charKey()] = { map = map, x = x, y = y } end
	pcall(QL.RefreshCorpse)
end)
for _, e in ipairs({ "PLAYER_ALIVE", "PLAYER_UNGHOST", "ZONE_CHANGED_NEW_AREA", "CORPSE_POSITION_UPDATE" }) do
	QL.Event(e, function() pcall(QL.RefreshCorpse) end)
end
QL.On("SETTING_CHANGED", function(key) if key == "corpseRoute" then pcall(QL.RefreshCorpse) end end)

QL.Event("PLAYER_LOGIN", function()
	if Minimap and CreateFrame then
		mmPath = newPath(Minimap, Minimap:GetFrameLevel() + 6)
		local since, check = 0, 0
		mmPath:SetScript("OnUpdate", function(_, elapsed)
			elapsed = elapsed or 0
			clock = clock + elapsed
			since, check = since + elapsed, check + elapsed
			if check >= 1 then check = 0; pcall(QL.RefreshCorpse) end -- released, revived, the corpse known
			if active and since >= 0.03 then since = 0; pcall(drawMinimap) end
		end)
	end
	if WorldMapFrame and WorldMapFrame.HookScript then
		WorldMapFrame:HookScript("OnShow", function() pcall(ensureWorld); pcall(drawWorld) end)
	end
	pcall(QL.RefreshCorpse)
end)
