-- The route on the world map: the way from you through every stop, in the window's look.
--
--   a soft glow under a crisp line, the leg to the next stop in the accent and later legs in
--   violet, fading as they go; lights flowing along the path; numbered stop badges (the next one
--   pulsing; hover for the quest, click to open it in QuestLineage); your position as a dot; a
--   caption at the bottom of the map. Without a route, the arrow's quest alone is drawn.
--
-- Drawn on a frame over the map canvas (WorldMapFrame:GetCanvas(), the same way ForeverTrail's
-- map trail works in game), with Line objects; points go through QL.ProjectToMap, so a stop on
-- another map of the same continent still lands in the right place. Setting: mapRoute.
--
--   QL.MapRouteStops() -> { {id, spot = {map, x, y}, n}, ... }, routeInfo | nil
--   QL.MapRoutePoints(mapID, w, h) -> { player = {x, y} | nil, stops = { {x, y, id, n}, ... } }
--   QL.RefreshMapRoute()

local _, QL = ...

local MEDIA = "Interface\\AddOns\\QuestLineage\\Media\\"
local REFRESH = 0.25 -- seconds between re-measures while the map is open

local overlay, caption
local glows, cores, dots, badges = {}, {}, {}, {}
local used = { line = 0, dot = 0, badge = 0 }
local segments = {} -- { {x1, y1, x2, y2, len, color}, ... } for the flowing lights
local clock, since = 0, 0

local function L(s) return QL.L(s) end

-- Data -----------------------------------------------------------------------------------------------

function QL.MapRouteStops()
	-- your own route (Paths.lua) while it is edited, followed or looked at
	if QL.PathStops then
		local ps, pinfo = QL.PathStops()
		if ps then return ps, pinfo end
	end
	local stops = {}
	local info = QL.RouteInfo and QL.RouteInfo()
	if info then
		for i, id in ipairs(info.order) do
			local spot = info.spots[i]
			if spot then stops[#stops + 1] = { id = id, spot = spot, n = i } end
		end
		return stops, info
	end
	local q = QL.ArrowQuest and QL.ArrowQuest()
	local target = QL.ArrowTarget and QL.ArrowTarget()
	if target then
		local loc = QL.Locate(target)
		if loc and loc.point then stops[1] = { id = q or target.questId, title = target.title, spot = loc.point, n = 1 } end
	end
	return stops, nil
end

function QL.MapRoutePoints(mapID, w, h)
	local out = { stops = {} }
	local stops, info = QL.MapRouteStops()
	out.info = info
	if #stops == 0 then return out end
	local map, px, py = QL.PlayerPosition()
	-- a route only looked at or edited starts at its first stop, not at you
	if map and px and not (info and info.custom and not info.following) then
		local x, y = QL.ProjectToMap(map, px, py, mapID)
		if x then out.player = { x * w, -y * h } end
	end
	for _, s in ipairs(stops) do
		local x, y = QL.ProjectToMap(s.spot.map, s.spot.x, s.spot.y, mapID)
		if x then out.stops[#out.stops + 1] = { x * w, -y * h, id = s.id, n = s.n, title = s.title, custom = s.custom } end
	end
	-- the stop-over points of a detour drawn to the arrow's spot (Paths.lua), for the first leg
	if QL.DetourVias and not (info and info.custom) then
		local spot = QL.DetourSpot and QL.DetourSpot()
		if spot then
			out.vias = {}
			for _, v in ipairs(QL.DetourVias(spot, QL.DetourEditing and QL.DetourEditing())) do
				local x, y = QL.ProjectToMap(v.map, v.x, v.y, mapID)
				if x then out.vias[#out.vias + 1] = { x * w, -y * h, i = v.i } end
			end
		end
	end
	return out
end

-- Drawing ------------------------------------------------------------------------------------------

local function canvasScale()
	if WorldMapFrame and WorldMapFrame.GetCanvasScale then
		local ok, s = pcall(WorldMapFrame.GetCanvasScale, WorldMapFrame)
		if ok and type(s) == "number" and s > 0 then return s end
	end
	return 1
end

-- Badges and dots keep their screen size while the map zooms: scaled by 1 / canvas scale,
-- their offsets divided by the same.
local function place(frame, x, y)
	local s = frame:GetScale() or 1
	if s <= 0 then s = 1 end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", overlay, "TOPLEFT", x / s, y / s)
end

local function line(kind)
	local pool = kind == "glow" and glows or cores
	used.line = used.line + 1
	local n = used.line
	local l = pool[n]
	if not l then
		l = overlay:CreateLine(nil, kind == "glow" and "BORDER" or "ARTWORK")
		pool[n] = l
	end
	l:Show()
	return l
end

local function segment(x1, y1, x2, y2, c, alpha, zoom)
	local g = line("glow")
	g:SetThickness(12 / zoom)
	g:SetColorTexture(c[1], c[2], c[3], 0.16 * alpha)
	g:SetStartPoint("TOPLEFT", overlay, x1, y1)
	g:SetEndPoint("TOPLEFT", overlay, x2, y2)
	used.line = used.line - 1 -- glow and core share an index
	local k = line("core")
	k:SetThickness(3 / zoom)
	k:SetColorTexture(c[1], c[2], c[3], 0.95 * alpha)
	k:SetStartPoint("TOPLEFT", overlay, x1, y1)
	k:SetEndPoint("TOPLEFT", overlay, x2, y2)
	local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
	segments[#segments + 1] = { x1, y1, x2, y2, len, c, alpha }
end

local function dot()
	used.dot = used.dot + 1
	local d = dots[used.dot]
	if not d then
		d = overlay:CreateTexture(nil, "OVERLAY")
		d:SetTexture(MEDIA .. "disc")
		d:SetSize(7, 7)
		dots[used.dot] = d
	end
	d:Show()
	return d
end

local function badge()
	local T, C = QL.Theme, QL.Theme.C
	used.badge = used.badge + 1
	local b = badges[used.badge]
	if not b then
		b = CreateFrame("Button", nil, overlay)
		b:SetSize(26, 26)
		b.halo = b:CreateTexture(nil, "BACKGROUND")
		b.halo:SetTexture(MEDIA .. "arrow_glow")
		b.halo:SetPoint("CENTER")
		b.halo:SetSize(60, 60)
		b.disc = b:CreateTexture(nil, "ARTWORK")
		b.disc:SetTexture(MEDIA .. "disc")
		b.disc:SetAllPoints()
		b.disc:SetVertexColor(0.055, 0.063, 0.082, 0.95)
		b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
		b.ring:SetTexture(MEDIA .. "ring")
		b.ring:SetAllPoints()
		b.num = T.Text(b, 12, C.text, nil, true)
		b.num:SetPoint("CENTER", 0, 0)
		b.num:SetJustifyH("CENTER")
		b:SetScript("OnEnter", function(self)
			local tip = QL.Tip()
			tip:SetOwner(self, "ANCHOR_RIGHT")
			if self.title then tip:AddLine(self.pathIndex and (self.title .. "  ·  " .. L("stop %d"):format(self.pathIndex)) or self.title, 1, 1, 1) end
			if self.questId then QL.FillQuestTooltip(tip, self.questId) end
			if self.pathIndex then
				if QL.PathEditing and QL.PathEditing() then tip:AddLine(L("Drag: move · Right-click: remove"), 0.5, 0.5, 0.5) end
			else
				tip:AddLine(L("Click: open in QuestLineage"), 0.5, 0.5, 0.5)
			end
			tip:Show()
		end)
		b:SetScript("OnLeave", function() QL.Tip():Hide() end)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(self, button)
			if self.pathIndex then
				if button == "RightButton" and QL.PathBadgeRemove then QL.PathBadgeRemove(self.pathIndex) end
			elseif self.questId then
				QL.Open(self.questId)
			end
		end)
		b:SetScript("OnMouseDown", function(self, button)
			if self.pathIndex and button == "LeftButton" and QL.PathBadgeDown then QL.PathBadgeDown(self.pathIndex) end
		end)
		badges[used.badge] = b
	end
	b:Show()
	return b
end

local viaBadges, handles = {}, {}

-- a small round badge for a stop-over point (draggable while a detour is edited)
local function viaBadge(n)
	local T, C = QL.Theme, QL.Theme.C
	local b = viaBadges[n]
	if not b then
		b = CreateFrame("Button", nil, overlay)
		b:SetSize(18, 18)
		b.disc = b:CreateTexture(nil, "ARTWORK")
		b.disc:SetTexture(MEDIA .. "disc")
		b.disc:SetAllPoints()
		b.disc:SetVertexColor(0.055, 0.063, 0.082, 0.95)
		b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
		b.ring:SetTexture(MEDIA .. "ring")
		b.ring:SetAllPoints()
		b.ring:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnEnter", function(self)
			local tip = QL.Tip()
			tip:SetOwner(self, "ANCHOR_RIGHT")
			tip:AddLine(L("Detour point %d"):format(self.viaIndex or 0), 1, 1, 1)
			if QL.DetourEditing and QL.DetourEditing() then tip:AddLine(L("Drag: move · Right-click: remove"), 0.5, 0.5, 0.5) end
			tip:Show()
		end)
		b:SetScript("OnLeave", function() QL.Tip():Hide() end)
		b:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" and QL.DetourViaDown then QL.DetourViaDown(self.viaIndex) end
		end)
		b:SetScript("OnClick", function(self, button)
			if button == "RightButton" and QL.DetourViaRemove then QL.DetourViaRemove(self.viaIndex) end
		end)
		viaBadges[n] = b
	end
	b:Show()
	return b
end

-- a faint handle in the middle of a line piece: drag it to bend the line there
local function handle(n)
	local C = QL.Theme.C
	local h = handles[n]
	if not h then
		h = CreateFrame("Button", nil, overlay)
		h:SetSize(16, 16)
		h.ring = h:CreateTexture(nil, "ARTWORK")
		h.ring:SetTexture(MEDIA .. "ring")
		h.ring:SetAllPoints()
		h.ring:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
		h.ring:SetAlpha(0.55)
		h:SetScript("OnEnter", function(self) self.ring:SetAlpha(1) end)
		h:SetScript("OnLeave", function(self) self.ring:SetAlpha(0.55) end)
		h:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" and QL.DetourHandleDown then QL.DetourHandleDown(self.at) end
		end)
		handles[n] = h
	end
	h:Show()
	return h
end

local function hideAll()
	for _, b in ipairs(viaBadges) do b:Hide() end
	for _, h in ipairs(handles) do h:Hide() end
	for _, l in ipairs(glows) do l:Hide() end
	for _, l in ipairs(cores) do l:Hide() end
	for _, d in ipairs(dots) do d:Hide() end
	for _, b in ipairs(badges) do b:Hide() end
	used.line, used.dot, used.badge = 0, 0, 0
	segments = {}
	if overlay and overlay.player then overlay.player:Hide(); overlay.playerRing:Hide() end
	if caption then caption:Hide(); caption.bg:Hide() end
end

-- Lerp between the accent (the next leg) and violet (the legs after), fading with distance.
local function legColor(k)
	local C = QL.Theme.C
	if k == 1 then return C.accent, 1 end
	local fade = math.max(0.45, 1 - (k - 2) * 0.12)
	return C.accent2, fade
end

function QL.RefreshMapRoute()
	if not overlay then return end
	hideAll()
	if QL.DB().mapRoute == false then return end
	local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local w, h = overlay:GetWidth() or 0, overlay:GetHeight() or 0
	if not mapID or w <= 0 or h <= 0 then return end
	local pts = QL.MapRoutePoints(mapID, w, h)
	if #pts.stops == 0 then return end
	local zoom = canvasScale()
	local C = QL.Theme.C

	-- the path: you -> stop 1 -> stop 2 ...
	local prev = pts.player
	local editingDetour = QL.DetourEditing and QL.DetourEditing()
	local piece = 0
	for k, s in ipairs(pts.stops) do
		if k == 1 and pts.vias then
			-- the first leg bends through the detour's points
			for vn, v in ipairs(pts.vias) do
				if prev then
					local c, alpha = legColor(1)
					segment(prev[1], prev[2], v[1], v[2], c, alpha, zoom)
					piece = piece + 1
					if editingDetour then
						local hd = handle(piece)
						hd:SetScale(1 / zoom)
						hd:SetFrameLevel(overlay:GetFrameLevel() + 12)
						hd.at = (pts.vias[vn - 1] and pts.vias[vn - 1].i or (v.i - 1)) + 1
						place(hd, (prev[1] + v[1]) / 2, (prev[2] + v[2]) / 2)
					end
				end
				local b = viaBadge(vn)
				b:SetScale(1 / zoom)
				b:SetFrameLevel(overlay:GetFrameLevel() + 14)
				b.viaIndex = v.i
				b:EnableMouse(editingDetour and true or false)
				place(b, v[1], v[2])
				prev = v
			end
		end
		if prev then
			local c, alpha = legColor(k)
			segment(prev[1], prev[2], s[1], s[2], c, alpha, zoom)
			if k == 1 and editingDetour then
				piece = piece + 1
				local hd = handle(piece)
				hd:SetScale(1 / zoom)
				hd:SetFrameLevel(overlay:GetFrameLevel() + 12)
				local last = pts.vias and pts.vias[#pts.vias]
				hd.at = (last and last.i or 0) + 1
				place(hd, (prev[1] + s[1]) / 2, (prev[2] + s[2]) / 2)
			end
		end
		prev = s
	end

	-- stop badges, the next one first and pulsing
	for k, s in ipairs(pts.stops) do
		local b = badge()
		b:SetScale(1 / zoom)
		b:SetFrameLevel(overlay:GetFrameLevel() + 20 - math.min(k, 19))
		place(b, s[1], s[2])
		b.questId = s.id
		b.title = s.title
		b.pathIndex = s.custom and s.n or nil
		b.num:SetText(tostring(s.n))
		-- the next stop leads (accent, pulsing); a route only looked at or edited has no "next"
		local lead = k == 1 and not (pts.info and pts.info.custom and not pts.info.following)
		local c = lead and C.accent or C.accent2
		b.ring:SetVertexColor(c[1], c[2], c[3], 1)
		b.halo:SetVertexColor(c[1], c[2], c[3], 1)
		b.halo:SetShown(lead)
		b.pulse = lead
	end

	-- you
	if pts.player then
		local p = overlay.player
		p:SetSize(12 / zoom, 12 / zoom)
		p:ClearAllPoints()
		p:SetPoint("CENTER", overlay, "TOPLEFT", pts.player[1], pts.player[2])
		p:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
		p:Show()
		local r = overlay.playerRing
		r:SetSize(18 / zoom, 18 / zoom)
		r:ClearAllPoints()
		r:SetPoint("CENTER", overlay, "TOPLEFT", pts.player[1], pts.player[2])
		r:Show()
	end

	-- caption
	local info = pts.info
	local first = pts.stops[1]
	local text
	if info and info.custom then
		text = QL.Theme.Hex(C.accent) .. "QuestLineage|r  ·  " .. info.name
		if info.following then text = text .. "  ·  " .. L("Stop %d/%d"):format(info.index, info.total) end
		if info.length and info.length > 0 and QL.DistanceTextYards then text = text .. "  ·  " .. L("about %s in all"):format(QL.DistanceTextYards(info.length)) end
		if info.editing then text = text .. "  ·  " .. L("Shift+click: add a stop") end
	elseif info then
		text = QL.Theme.Hex(C.accent) .. "QuestLineage|r  ·  " .. L("Route %d/%d"):format(info.index, info.total) .. "  ·  " .. QL.QuestTitle(info.next)
		if info.length and info.length > 0 then text = text .. "  ·  " .. L("about %s in all"):format(QL.DistanceTextYards(info.length)) end
	elseif first then
		text = QL.Theme.Hex(C.accent) .. "QuestLineage|r  ·  " .. (first.title or QL.QuestTitle(first.id))
	end
	local d = first and not first.title and first.id and QL.DistanceText and QL.DistanceText(first.id)
	if d and text then text = text .. "  ·  " .. d end
	if editingDetour then
		text = QL.Theme.Hex(C.accent) .. "QuestLineage|r  ·  " .. L("Detour") .. "  ·  " .. L("%d points"):format(pts.vias and #pts.vias or 0) .. "  ·  " .. L("Shift+click: add a point · drag the line: bend it")
	end
	if caption and text then
		caption:SetText(text)
		caption.bg:SetWidth((caption:GetStringWidth() or 200) + 28)
		caption:Show(); caption.bg:Show()
	end
end

-- Flowing lights and the pulse: every frame, from the segments drawn last.
local function animate(elapsed)
	clock = clock + (elapsed or 0)
	used.dot = 0
	for _, d in ipairs(dots) do d:Hide() end
	local zoom = canvasScale()
	for _, s in ipairs(segments) do
		local x1, y1, x2, y2, len, c, alpha = s[1], s[2], s[3], s[4], s[5], s[6], s[7]
		if len > 1 then
			local count = math.max(1, math.min(6, math.floor(len / 70)))
			for j = 0, count - 1 do
				local f = ((clock * 55 / len) + j / count) % 1
				local d = dot()
				d:SetSize(7 / zoom, 7 / zoom)
				d:SetVertexColor(c[1], c[2], c[3], alpha * (0.35 + 0.65 * math.sin(f * math.pi)))
				d:ClearAllPoints()
				d:SetPoint("CENTER", overlay, "TOPLEFT", x1 + (x2 - x1) * f, y1 + (y2 - y1) * f)
			end
		end
	end
	local wave = 0.5 + 0.5 * math.sin(clock * 4)
	for i = 1, used.badge do
		local b = badges[i]
		if b.pulse then
			b.halo:SetSize(52 + 16 * wave, 52 + 16 * wave)
			b.halo:SetAlpha(0.35 + 0.35 * wave)
		end
	end
end

local function ensureOverlay()
	if overlay or not (WorldMapFrame and WorldMapFrame.GetCanvas) then return end
	local canvas = WorldMapFrame:GetCanvas()
	if not canvas then return end
	local T, C = QL.Theme, QL.Theme.C
	overlay = CreateFrame("Frame", nil, canvas)
	overlay:SetAllPoints(canvas)
	local manager = WorldMapFrame.pinFrameLevelsManager
	local defs = manager and manager.definitions
	local level = defs and defs.PIN_FRAME_LEVEL_DIG_SITE
	if level and level.overrideType then level = defs[level.overrideType] end
	overlay:SetFrameLevel((level and level.startLevel) or (canvas:GetFrameLevel() + 2100))
	if not overlay.CreateLine then QL.Debug("map route: no Line objects on this client"); overlay = nil; return end

	overlay.playerRing = overlay:CreateTexture(nil, "OVERLAY")
	overlay.playerRing:SetTexture(MEDIA .. "ring")
	overlay.playerRing:SetVertexColor(1, 1, 1, 0.9)
	overlay.player = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
	overlay.player:SetTexture(MEDIA .. "disc")

	-- caption: on the map frame itself, so it keeps its size and place while you zoom
	local holder = WorldMapFrame.ScrollContainer or WorldMapFrame
	caption = T.Text(holder, 13, C.text, "OVERLAY", false)
	caption:SetPoint("BOTTOM", holder, "BOTTOM", 0, 14)
	caption:SetJustifyH("CENTER")
	caption:SetShadowOffset(1, -1)
	caption.bg = holder:CreateTexture(nil, "ARTWORK")
	caption.bg:SetTexture(T.WHITE)
	caption.bg:SetVertexColor(0.055, 0.063, 0.082, 0.82)
	caption.bg:SetHeight(26)
	caption.bg:SetPoint("CENTER", caption, "CENTER")

	overlay:SetScript("OnUpdate", function(_, elapsed)
		since = since + (elapsed or 0)
		if since >= REFRESH then
			since = 0
			local ok, err = pcall(QL.RefreshMapRoute)
			if not ok then QL.Debug("map route: " .. tostring(err)) end
		end
		local ok, err = pcall(animate, elapsed)
		if not ok then QL.Debug("map route animate: " .. tostring(err)) end
	end)
	overlay:SetScript("OnSizeChanged", function() pcall(QL.RefreshMapRoute) end)
	if WorldMapFrame.HookScript then
		WorldMapFrame:HookScript("OnHide", function() if caption then caption:Hide(); caption.bg:Hide() end end)
	end
	if hooksecurefunc and WorldMapFrame.SetMapID then
		hooksecurefunc(WorldMapFrame, "SetMapID", function() pcall(QL.RefreshMapRoute) end)
	end
	pcall(QL.RefreshMapRoute)
end
QL.EnsureMapRoute = ensureOverlay

local function hook()
	if not WorldMapFrame or QL.mapRouteHooked then return end
	QL.mapRouteHooked = true
	WorldMapFrame:HookScript("OnShow", function()
		local ok, err = pcall(ensureOverlay)
		if not ok then QL.Debug("map route: " .. tostring(err)) end
		pcall(QL.RefreshMapRoute)
	end)
	if WorldMapFrame:IsShown() then pcall(ensureOverlay) end
end

QL.Event("PLAYER_LOGIN", function() pcall(hook) end)
-- the world map may load later on some clients
QL.Event("ADDON_LOADED", function(_, name) if name == "Blizzard_WorldMap" then pcall(hook) end end)
for _, m in ipairs({ "ROUTE_CHANGED", "ARROW_CHANGED", "SETTING_CHANGED", "PATH_CHANGED" }) do
	QL.On(m, function() if overlay then pcall(QL.RefreshMapRoute) end end)
end
