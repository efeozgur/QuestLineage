-- The zone map: when a zone is picked on the Zones tab, the middle of the window shows that zone's
-- map (the game's own map art: the base tiles of the uiMap's art layer and the explored overlays,
-- as the world map draws them) in a framed, softly vignetted box, with a pin for every quest you
-- can do there now: where to pick it up, where its objectives are, where to hand it in.
--
--   QL.ZoneMapPins(area, ctx) -> { { x, y, ids = {...}, status }, ... } (pure; quests at one spot share a pin)
--   QL.ZoneMap.New(parent) -> map; map:Show(area, ctx, focusId, animate), map:Hide()
--
-- Pins: ready to hand in (yellow), in your log (blue), available (accent), level too low (small,
-- grey). Hover: the quests; click: open the quest beside the map (the map stays) and point the
-- arrow. The player's dot pulses while you are in the zone. Map art APIs are not verified on every
-- client build, so every call is guarded; without art the box keeps a plain grid and the pins.

local _, QL = ...

local MEDIA = "Interface\\AddOns\\QuestLineage\\Media\\"
local PIN_ORDER = { ready = 1, active = 2, available = 3, toolow = 4 }
local MERGE = 0.014 -- quests closer than this (map fraction) share a pin

local function L(s) return QL.L(s) end

-- Pins ------------------------------------------------------------------------------------------------

-- The point of a target on this map nearest the middle of its points there (objectives spread
-- over a field get one pin in it, not at its edge).
local function spotOn(target, uiMap)
	if not target or type(target.points) ~= "table" then return nil end
	local on = {}
	for _, p in ipairs(target.points) do
		if p.map == uiMap and p.x >= 0 and p.x <= 1 and p.y >= 0 and p.y <= 1 then on[#on + 1] = p end
	end
	if #on == 0 then return nil end
	local cx, cy = 0, 0
	for _, p in ipairs(on) do cx = cx + p.x; cy = cy + p.y end
	cx, cy = cx / #on, cy / #on
	local best, bd
	for _, p in ipairs(on) do
		local d = (p.x - cx) ^ 2 + (p.y - cy) ^ 2
		if not bd or d < bd then best, bd = p, d end
	end
	return best
end

-- opts.merge: how close (map fraction) two quests must be to share a pin (the map widget passes
-- about 14 pixels' worth); opts.hidden: states left off the map ({ toolow = true }).
-- -> pins, uiMap, counts (quests placed per state, hidden ones too: the legend shows them)
function QL.ZoneMapPins(area, ctx, opts)
	ctx = ctx or QL.Context()
	local merge = opts and opts.merge or MERGE
	local hidden = opts and opts.hidden or {}
	local uiMap = QL.AreaUiMap(area)
	local pins, counts = {}, { ready = 0, active = 0, available = 0, toolow = 0 }
	if not uiMap then return pins, nil, counts end
	for _, row in ipairs(QL.ZoneQuestRows(area, ctx)) do
		if PIN_ORDER[row.status] then
			local ok, target = pcall(QL.QuestTarget, row.id, ctx)
			local p = ok and spotOn(target, uiMap) or nil
			if p then counts[row.status] = counts[row.status] + 1 end
			if p and not hidden[row.status] then
				local into
				for _, pin in ipairs(pins) do
					if math.abs(pin.x - p.x) < merge and math.abs(pin.y - p.y) < merge then into = pin; break end
				end
				if into then
					into.ids[#into.ids + 1] = row.id
					if PIN_ORDER[row.status] < PIN_ORDER[into.status] then into.status = row.status end
				else
					pins[#pins + 1] = { x = p.x, y = p.y, ids = { row.id }, status = row.status }
				end
			end
		end
	end
	-- the important ones drawn last (on top)
	table.sort(pins, function(a, b)
		local oa, ob = PIN_ORDER[a.status], PIN_ORDER[b.status]
		if oa ~= ob then return oa > ob end
		if a.y ~= b.y then return a.y < b.y end
		return a.x < b.x
	end)
	return pins, uiMap, counts
end

-- The states hidden on the map (setting zoneMapHidden; "level too low" hidden until shown).
function QL.ZoneMapHidden()
	local h = QL.DB().zoneMapHidden
	if type(h) ~= "table" then return { toolow = true } end
	return h
end

function QL.ToggleZoneMapState(status)
	local new = {}
	for k, v in pairs(QL.ZoneMapHidden()) do new[k] = v end
	new[status] = not new[status] or nil
	QL.DB().zoneMapHidden = new -- always a new table
	if QL.RenderWindow then QL.RenderWindow(false) end
end

local function pinColor(status)
	local T = QL.Theme
	if status == "available" then return T.C.accent end
	return T.STATUS[status] or T.STATUS.locked
end

-- The widget ------------------------------------------------------------------------------------------

QL.ZoneMap = {}
local Map = {}
Map.__index = Map

local function call(obj, method, ...)
	local fn = obj and obj[method]
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, obj, ...)
	if ok then return a, b end
	return nil
end

function QL.ZoneMap.New(parent)
	local T, C = QL.Theme, QL.Theme.C
	local self = setmetatable({ tiles = {}, pins = {}, legend = {} }, Map)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)
	f:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
	f:EnableMouse(true)
	T.Fill(f, C.canvas)
	self.frame = f

	-- heading: a small label, the zone's name, its level band and counts
	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT")
	head:SetHeight(76)
	T.Line(head, C.line, "BOTTOM")
	self.kicker = T.Text(head, 11, C.accent)
	self.kicker:SetPoint("TOPLEFT", 26, -14)
	self.title = T.Text(head, 19, C.text, nil, true)
	self.title:SetPoint("TOPLEFT", self.kicker, "BOTTOMLEFT", 0, -5)
	self.title:SetPoint("RIGHT", head, "RIGHT", -190, 0)
	self.sub = T.Text(head, 12, C.muted)
	self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -5)
	self.sub:SetPoint("RIGHT", head, "RIGHT", -190, 0)
	-- open the game's world map at this zone (its pins are drawn there too)
	self.worldBtn = T.Button(head, 156, 24)
	self.worldBtn:SetPoint("TOPRIGHT", -20, -12)
	self.worldBtn:SetScript("OnClick", function()
		if self.area and QL.OpenZoneOnWorldMap then QL.OpenZoneOnWorldMap(self.area) end
	end)
	self.treeBtn = T.Button(head, 156, 24)
	self.treeBtn:SetPoint("TOPRIGHT", self.worldBtn, "BOTTOMRIGHT", 0, -4)
	self.treeBtn:Hide()

	-- the map box: framed, clipped, vignetted
	local box = CreateFrame("Frame", nil, f)
	box:SetSize(400, 266)
	call(box, "SetClipsChildren", true)
	self.box = box
	T.Glow(box, C.accent)
	self.art = CreateFrame("Frame", nil, box)
	self.art:SetAllPoints(box)
	self.grid = {}
	for i = 1, 14 do
		local g = box:CreateTexture(nil, "BACKGROUND", nil, 2)
		g:SetTexture(T.WHITE)
		T.Color(g, C.lineSoft)
		self.grid[i] = g
	end
	self.noArt = T.Text(box, 12, C.dim)
	self.noArt:SetPoint("CENTER", 0, 0)
	self.noArt:SetJustifyH("CENTER")
	-- a light tint in the theme's colour over the art, and dark edges
	local over = CreateFrame("Frame", nil, box)
	over:SetAllPoints(box)
	over:SetFrameLevel(box:GetFrameLevel() + 3)
	self.over = over
	self.tint = over:CreateTexture(nil, "BACKGROUND")
	self.tint:SetTexture(T.WHITE)
	self.tint:SetAllPoints(over)
	T.Color(self.tint, { C.canvas[1], C.canvas[2], C.canvas[3], 0.16 })
	local edge = { C.canvas[1], C.canvas[2], C.canvas[3], 0.85 }
	local clear = { C.canvas[1], C.canvas[2], C.canvas[3], 0 }
	local function vignette(p1, p2, horizontal, size, from, to)
		local t = over:CreateTexture(nil, "BORDER")
		t:SetTexture(T.WHITE)
		t:SetPoint(p1); t:SetPoint(p2)
		if horizontal then t:SetWidth(size) else t:SetHeight(size) end
		T.Gradient(t, horizontal and "HORIZONTAL" or "VERTICAL", from, to)
		return t
	end
	vignette("TOPLEFT", "BOTTOMLEFT", true, 46, edge, clear)
	vignette("TOPRIGHT", "BOTTOMRIGHT", true, 46, clear, edge)
	vignette("TOPLEFT", "TOPRIGHT", false, 40, clear, edge)      -- VERTICAL runs bottom to top
	vignette("BOTTOMLEFT", "BOTTOMRIGHT", false, 40, edge, clear)
	T.Border(over, C.line)
	-- pins and the player above everything
	local pinLayer = CreateFrame("Frame", nil, box)
	pinLayer:SetAllPoints(box)
	pinLayer:SetFrameLevel(box:GetFrameLevel() + 6)
	self.pinLayer = pinLayer
	local me = CreateFrame("Frame", nil, pinLayer)
	me:SetSize(30, 30)
	me:SetFrameLevel(pinLayer:GetFrameLevel() + 40)
	me.ring = me:CreateTexture(nil, "ARTWORK")
	me.ring:SetTexture(MEDIA .. "ring")
	me.ring:SetPoint("CENTER")
	me.ring:SetSize(30, 30)
	me.dot = me:CreateTexture(nil, "OVERLAY")
	me.dot:SetTexture(MEDIA .. "disc")
	me.dot:SetPoint("CENTER")
	me.dot:SetSize(11, 11)
	me.dot:SetVertexColor(1, 1, 1, 1)
	me.ring:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
	me:Hide()
	self.me = me

	-- legend under the map
	local foot = CreateFrame("Frame", nil, f)
	foot:SetPoint("BOTTOMLEFT"); foot:SetPoint("BOTTOMRIGHT")
	foot:SetHeight(34)
	self.footFrame = foot
	T.Fill(foot, C.header)
	T.Line(foot, C.line, "TOP")
	-- one switch per state: a dot, the state and how many; a click shows or hides those pins
	self.switches = {}
	local prev
	for _, key in ipairs({ "ready", "active", "available", "toolow" }) do
		local b = CreateFrame("Button", nil, foot)
		b:SetHeight(24)
		b.dot = b:CreateTexture(nil, "ARTWORK")
		b.dot:SetTexture(MEDIA .. "disc")
		b.dot:SetSize(8, 8)
		b.dot:SetPoint("LEFT", 6, 0)
		b.text = T.Text(b, 11, C.muted)
		b.text:SetPoint("LEFT", b.dot, "RIGHT", 6, 0)
		b.bg = T.Fill(b, { 0, 0, 0, 0 })
		b.key = key
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", 14, 0) end
		b:SetScript("OnClick", function(btn) QL.ToggleZoneMapState(btn.key) end)
		b:SetScript("OnEnter", function(btn)
			T.Color(btn.bg, C.rowHover)
			local tip = QL.Tip()
			tip:SetOwner(btn, "ANCHOR_TOP")
			tip:AddLine(QL.ZoneMapHidden()[btn.key] and L("Click: show these on the map") or L("Click: hide these on the map"), 1, 1, 1)
			tip:Show()
		end)
		b:SetScript("OnLeave", function(btn) T.Color(btn.bg, { 0, 0, 0, 0 }); QL.Tip():Hide() end)
		self.switches[key] = b
		prev = b
	end
	self.foot = T.Text(foot, 11, C.dim)
	self.foot:SetPoint("RIGHT", foot, "RIGHT", -16, 0)
	self.foot:SetJustifyH("RIGHT")
	QL.zoneMapWidget = self

	local clock = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		clock = clock + (elapsed or 0)
		self:Animate(clock)
	end)
	self.clockReset = function() clock = 0 end
	f:Hide()
	return self
end

-- Map art ---------------------------------------------------------------------------------------------

function Map:Tile(i)
	local t = self.tiles[i]
	if not t then
		t = self.art:CreateTexture(nil, "BACKGROUND", nil, 1)
		self.tiles[i] = t
	end
	t:ClearAllPoints()
	t:SetVertexColor(1, 1, 1, 1)
	call(t, "SetDesaturation", 0.2)
	t:Show()
	return t
end

-- A C_ namespace function (called plainly, not as a method): its first result, or nil when it is
-- missing or fails.
local function api(ns, name, ...)
	local fn = type(ns) == "table" and ns[name]
	if type(fn) ~= "function" then return nil end
	local ok, a = pcall(fn, ...)
	if ok then return a end
	return nil
end

-- The classic world map's files (Interface\WorldMap\<name>\<name>1..12: 4 x 3 tiles of 256 over a
-- 1002 x 668 map), for a client whose C_Map gives no art.
local MAP_FILES = {
	[1411] = "Durotar", [1412] = "Mulgore", [1413] = "Barrens", [1416] = "Alterac", [1417] = "Arathi",
	[1418] = "Badlands", [1419] = "BlastedLands", [1420] = "Tirisfal", [1421] = "Silverpine",
	[1422] = "WesternPlaguelands", [1423] = "EasternPlaguelands", [1424] = "Hilsbrad", [1425] = "Hinterlands",
	[1426] = "DunMorogh", [1427] = "SearingGorge", [1428] = "BurningSteppes", [1429] = "Elwynn",
	[1430] = "DeadwindPass", [1431] = "Duskwood", [1432] = "LochModan", [1433] = "Redridge",
	[1434] = "Stranglethorn", [1435] = "SwampOfSorrows", [1436] = "Westfall", [1437] = "Wetlands",
	[1438] = "Teldrassil", [1439] = "Darkshore", [1440] = "Ashenvale", [1441] = "ThousandNeedles",
	[1442] = "StonetalonMountains", [1443] = "Desolace", [1444] = "Feralas", [1445] = "Dustwallow",
	[1446] = "Tanaris", [1447] = "Aszhara", [1448] = "Felwood", [1449] = "UngoroCrater", [1450] = "Moonglade",
	[1451] = "Silithus", [1452] = "Winterspring", [1453] = "Stormwind", [1454] = "Ogrimmar",
	[1455] = "Ironforge", [1456] = "ThunderBluff", [1457] = "Darnassis", [1458] = "Undercity",
	[1459] = "AlteracValley", [1460] = "WarsongGulch", [1461] = "ArathiBasin",
}
local CLASSIC_LAYER = { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 }

local function artLayer(uiMap)
	local layers = api(C_Map, "GetMapArtLayers", uiMap)
	local l = type(layers) == "table" and layers[1]
	if type(l) == "table" and type(l.layerWidth) == "number" and type(l.layerHeight) == "number"
		and type(l.tileWidth) == "number" and type(l.tileHeight) == "number"
		and l.layerWidth > 0 and l.layerHeight > 0 and l.tileWidth > 0 and l.tileHeight > 0 then
		return l
	end
	return nil
end

-- A map's base art: its layer and tile files, from the client (file ids) or else the classic
-- file paths. -> layer, files | nil, source ("client" | "path" | nil)
function QL.ZoneMapArt(uiMap)
	local layer = artLayer(uiMap)
	local files = api(C_Map, "GetMapArtLayerTextures", uiMap, 1)
	if type(files) == "table" and #files > 0 then return layer or CLASSIC_LAYER, files, "client" end
	local name = MAP_FILES[uiMap]
	if not name then return layer or CLASSIC_LAYER, nil, nil end
	files = {}
	for i = 1, 12 do files[i] = "Interface\\WorldMap\\" .. name .. "\\" .. name .. i end
	return CLASSIC_LAYER, files, "path"
end

-- Draws the map's art scaled to the box. Returns true when there was any.
function Map:DrawArt(uiMap, w, h)
	for _, t in ipairs(self.tiles) do t:Hide() end
	local n = 0
	local layer, files = QL.ZoneMapArt(uiMap)
	if not files then return false end
	local lw, lh = layer.layerWidth, layer.layerHeight
	local tw, th = layer.tileWidth, layer.tileHeight
	local s = w / lw
	local cols, rows = math.ceil(lw / tw), math.ceil(lh / th)
	for r = 1, rows do
		for c = 1, cols do
			local file = files[(r - 1) * cols + c]
			if file then
				n = n + 1
				local t = self:Tile(n)
				t:SetTexture(file)
				t:SetTexCoord(0, 1, 0, 1)
				t:SetSize(tw * s, th * s)
				t:SetPoint("TOPLEFT", self.art, "TOPLEFT", (c - 1) * tw * s, -(r - 1) * th * s)
			end
		end
	end
	-- explored areas, laid out as the world map lays them (tiles of the layer's tile size; the
	-- last row and column are cut from a power-of-two file)
	local explored = api(C_MapExplorationInfo, "GetExploredMapTextures", uiMap)
	if type(explored) == "table" then
		for _, info in ipairs(explored) do
			local ids = type(info) == "table" and info.fileDataIDs
			local wide = type(info) == "table" and info.numTexturesWide or 0
			local tall = type(info) == "table" and info.numTexturesTall or 0
			if type(ids) == "table" and wide > 0 and tall > 0 then
				for j = 1, tall do
					local ph, fh = th, th
					if j == tall then
						ph = (info.textureHeight or th) % th
						if ph == 0 then ph = th end
						fh = 16
						while fh < ph do fh = fh * 2 end
					end
					for k = 1, wide do
						local pw, fw = tw, tw
						if k == wide then
							pw = (info.textureWidth or tw) % tw
							if pw == 0 then pw = tw end
							fw = 16
							while fw < pw do fw = fw * 2 end
						end
						local file = ids[(j - 1) * wide + k]
						if file then
							n = n + 1
							local t = self:Tile(n)
							t:SetTexture(file)
							t:SetTexCoord(0, pw / fw, 0, ph / fh)
							t:SetSize(pw * s, ph * s)
							t:SetPoint("TOPLEFT", self.art, "TOPLEFT", ((info.offsetX or 0) + tw * (k - 1)) * s, -((info.offsetY or 0) + th * (j - 1)) * s)
							call(t, "SetDrawLayer", "BACKGROUND", 3)
						end
					end
				end
			end
		end
	end
	self.aspect = lw / lh
	return n > 0
end

-- The aspect of a map's art (the world map's 1002 x 668 when unknown).
local function artAspect(uiMap)
	local layer = QL.ZoneMapArt(uiMap)
	return layer.layerWidth / layer.layerHeight
end

-- /ql map [area]: what the client gives for a zone's map art (the player's zone without an area).
function QL.ZoneMapDebug(arg)
	local area = tonumber(arg) or QL.PlayerZone()
	local uiMap = area and QL.AreaUiMap(area)
	QL.Chat(("zone map: area %s · uiMap %s"):format(tostring(area), tostring(uiMap)))
	if not uiMap then return end
	local function has(ns, name) return (type(ns) == "table" and type(ns[name]) == "function") and "yes" or "no" end
	QL.Chat("C_Map.GetMapArtLayers: " .. has(C_Map, "GetMapArtLayers")
		.. " · C_Map.GetMapArtLayerTextures: " .. has(C_Map, "GetMapArtLayerTextures")
		.. " · C_MapExplorationInfo.GetExploredMapTextures: " .. has(C_MapExplorationInfo, "GetExploredMapTextures"))
	local layers = api(C_Map, "GetMapArtLayers", uiMap)
	local l = type(layers) == "table" and layers[1]
	QL.Chat("layers: " .. (type(layers) == "table" and #layers or tostring(layers))
		.. (type(l) == "table" and (" · first %sx%s, tiles %sx%s"):format(tostring(l.layerWidth), tostring(l.layerHeight), tostring(l.tileWidth), tostring(l.tileHeight)) or ""))
	local files = api(C_Map, "GetMapArtLayerTextures", uiMap, 1)
	QL.Chat("textures: " .. (type(files) == "table" and (#files .. " · first " .. tostring(files[1])) or tostring(files)))
	local explored = api(C_MapExplorationInfo, "GetExploredMapTextures", uiMap)
	QL.Chat("explored overlays: " .. (type(explored) == "table" and #explored or tostring(explored)))
	local _, used, source = QL.ZoneMapArt(uiMap)
	QL.Chat("drawn from: " .. tostring(source) .. (source == "path" and (" (" .. tostring(used[1]) .. ")") or ""))
	if QL.WorldPinDebug then QL.WorldPinDebug() end
end

function Map:Grid(on, w, h)
	for i, g in ipairs(self.grid) do
		g:ClearAllPoints()
		if not on then
			g:Hide()
		elseif i <= 7 then
			g:SetPoint("TOPLEFT", self.box, "TOPLEFT", w * i / 8, 0)
			g:SetSize(1, h)
			g:Show()
		else
			g:SetPoint("TOPLEFT", self.box, "TOPLEFT", 0, -h * (i - 7) / 8)
			g:SetSize(w, 1)
			g:Show()
		end
	end
end

-- Pins ------------------------------------------------------------------------------------------------

local function pinTip(pin)
	local tip = QL.Tip()
	tip:SetOwner(pin, "ANCHOR_RIGHT")
	if #pin.ids == 1 then
		QL.FillQuestTooltip(tip, pin.ids[1])
	else
		local T = QL.Theme
		local ctx = QL.Context()
		tip:AddLine(L("%d quests here"):format(#pin.ids), 1, 1, 1)
		for _, id in ipairs(pin.ids) do
			local s = QL.NodeStatus(id, ctx)
			local c = pinColor(s)
			local lvl = QL.QuestLevel(id)
			tip:AddLine((lvl and ("[" .. lvl .. "] ") or "") .. QL.QuestTitle(id) .. "  " .. T.Hex(c) .. L((T.STATUS[s] or T.STATUS.locked)[4]) .. "|r", 0.9, 0.9, 0.9)
		end
	end
	tip:AddLine(L("Click: open the quest beside the map"), 0.5, 0.55, 0.6)
	tip:Show()
end

-- A pin: a small dot in the state's colour on a dark edge (readable on any map art); a white
-- ring and a soft halo only while hovered or selected; a tiny count bubble when quests share it.
-- The button is larger than the dot so it is easy to hit.
function Map:Pin(i)
	local p = self.pins[i]
	if p then return p end
	local T, C = QL.Theme, QL.Theme.C
	p = CreateFrame("Button", nil, self.pinLayer)
	p:SetSize(18, 18)
	p.halo = p:CreateTexture(nil, "BACKGROUND")
	p.halo:SetTexture(MEDIA .. "disc")
	p.halo:SetPoint("CENTER")
	p.edge = p:CreateTexture(nil, "BORDER")
	p.edge:SetTexture(MEDIA .. "disc")
	p.edge:SetPoint("CENTER")
	p.edge:SetVertexColor(0.04, 0.05, 0.07, 0.9)
	p.core = p:CreateTexture(nil, "ARTWORK")
	p.core:SetTexture(MEDIA .. "disc")
	p.core:SetPoint("CENTER")
	p.ring = p:CreateTexture(nil, "OVERLAY")
	p.ring:SetTexture(MEDIA .. "ring")
	p.ring:SetPoint("CENTER")
	p.ring:SetVertexColor(1, 1, 1, 0.95)
	local badge = CreateFrame("Frame", nil, p)
	badge:SetSize(13, 13)
	badge:SetPoint("CENTER", p, "CENTER", 7, 6)
	badge.bg = badge:CreateTexture(nil, "ARTWORK")
	badge.bg:SetTexture(MEDIA .. "disc")
	badge.bg:SetAllPoints(badge)
	badge.bg:SetVertexColor(0.04, 0.05, 0.07, 0.92)
	badge.text = T.Text(badge, 9, C.text, nil, true)
	badge.text:SetPoint("CENTER", 0, 0)
	badge.text:SetJustifyH("CENTER")
	p.badge = badge
	p:SetScript("OnEnter", function(btn) btn.owner:Spotlight(btn); pinTip(btn) end)
	p:SetScript("OnLeave", function(btn) btn.owner:Spotlight(nil); QL.Tip():Hide() end)
	p:SetScript("OnClick", function(btn)
		local id = btn.ids and btn.ids[1]
		if not id then return end
		if btn.status ~= "toolow" and QL.SetArrowTarget and not (QL.RouteActive and QL.RouteActive()) then
			pcall(QL.SetArrowTarget, id)
		end
		QL.Open(id, { keepMap = true })
	end)
	p.owner = self
	self.pins[i] = p
	return p
end

function Map:SizePin(p)
	local base = (p.status == "toolow") and 5 or 7
	local lit = p.hover or p.selected
	local k = (p.hover and 1.4 or 1) * (p.pop or 1)
	p.core:SetSize(base * k, base * k)
	p.edge:SetSize((base + 3) * k, (base + 3) * k)
	p.ring:SetSize((base + 7) * k, (base + 7) * k)
	p.ring:SetShown(lit and true or false)
	p.halo:SetSize((base + 16) * k, (base + 16) * k)
	p.halo:SetShown(lit and true or false)
	p.badge:SetScale(math.max(0.01, p.pop or 1))
end

-- One pin in front (hovered here, or its quest hovered in the list), the others faded back; nil
-- brings them all back.
function Map:Spotlight(pin)
	for i = 1, self.shownPins or 0 do
		local p = self.pins[i]
		p.hover = (p == pin)
		p:SetAlpha((pin and p ~= pin) and 0.3 or 1)
		if p.hover then p:SetFrameLevel(self.pinLayer:GetFrameLevel() + 80) else p:SetFrameLevel(p.level or p:GetFrameLevel()) end
		self:SizePin(p)
	end
end

function Map:SpotlightQuest(id)
	local hit
	if id then
		for i = 1, self.shownPins or 0 do
			for _, q in ipairs(self.pins[i].ids or {}) do
				if q == id then hit = self.pins[i] end
			end
		end
	end
	self:Spotlight(hit)
end

-- The list beside the map calls this as the cursor moves over a quest row.
function QL.ZoneMapSpotlight(id)
	local m = QL.zoneMapWidget
	if m and m.frame:IsShown() and not m.animating then m:SpotlightQuest(id) end
end

-- Show / animate --------------------------------------------------------------------------------------

-- Fit the box between heading and legend (the art's aspect kept) and draw the map's art.
function Map:Fit(uiMap)
	local f = self.frame
	local aspect = uiMap and artAspect(uiMap) or (1002 / 668)
	local fw, fh = f:GetWidth() or 0, f:GetHeight() or 0
	if fw <= 0 then fw = 620 end
	if fh <= 0 then fh = 680 end
	local availW, availH = fw - 48, fh - 76 - 34 - 40
	local w = math.max(120, availW)
	local h = w / aspect
	if h > availH then h = math.max(80, availH); w = h * aspect end
	self.box:SetSize(w, h)
	self.box:ClearAllPoints()
	self.box:SetPoint("TOP", f, "TOP", 0, -76 - 20 - math.max(0, (availH - h) / 2))
	self.w, self.h = w, h
	local hasArt = uiMap and self:DrawArt(uiMap, w, h) or false
	self:Grid(not hasArt, w, h)
	self.noArt:SetText(hasArt and "" or L("No map picture for this zone on this client"))
	self.uiMap = uiMap
	return w, h
end

function Map:Show(area, ctx, focusId, animate)
	local T, C = QL.Theme, QL.Theme.C
	ctx = ctx or QL.Context()
	local f = self.frame
	f:Show()
	-- the zone's summary
	local z
	for _, e in ipairs(QL.ZoneOverview(ctx)) do if e.area == area then z = e; break end end
	self.kicker:SetText(L("Zone map"))
	self.area = area
	self.worldBtn:SetLabel(L("Open on the world map"))
	self.title:SetText(z and z.name or (QL.AreaName(area) or ("#" .. tostring(area))))
	if z then
		local parts = {}
		if z.minLevel then
			local c = QL.ZoneBand(z.minLevel, z.maxLevel, ctx.level)
			parts[#parts + 1] = T.Hex(c) .. (z.minLevel == z.maxLevel and L("Lv %d"):format(z.minLevel) or L("Lv %d–%d"):format(z.minLevel, z.maxLevel)) .. "|r"
		end
		parts[#parts + 1] = L("%d/%d done"):format(z.done, z.total)
		if z.active > 0 then parts[#parts + 1] = T.Hex(T.STATUS.active) .. L("%d in your log"):format(z.active) .. "|r" end
		parts[#parts + 1] = L("%d to take"):format(z.available)
		self.sub:SetText(table.concat(parts, "  ·  "))
	else
		self.sub:SetText("")
	end

	self:SpotMode(false)
	local uiMap = QL.AreaUiMap(area)
	local w, h = self:Fit(uiMap)

	-- pins: quests closer than about 14 pixels on this box share one
	local hidden = QL.ZoneMapHidden()
	local pins, _, counts = QL.ZoneMapPins(area, ctx, { merge = 14 / w, hidden = hidden })
	local n = 0
	for i, pin in ipairs(pins) do
		n = i
		local p = self:Pin(i)
		p.ids, p.status = pin.ids, pin.status
		local c = pinColor(pin.status)
		local on = false
		for _, id in ipairs(pin.ids) do if id == focusId then on = true end end
		p.selected = on
		p.core:SetVertexColor(c[1], c[2], c[3], pin.status == "toolow" and 0.8 or 1)
		p.halo:SetVertexColor(c[1], c[2], c[3], 0.3)
		p.halo:SetAlpha(1)
		p.badge:SetShown(#pin.ids > 1)
		p.badge.text:SetText(#pin.ids > 1 and tostring(#pin.ids) or "")
		p:ClearAllPoints()
		p:SetPoint("CENTER", self.box, "TOPLEFT", pin.x * w, -pin.y * h)
		p.level = self.pinLayer:GetFrameLevel() + i + (on and 60 or 0)
		p:SetFrameLevel(p.level)
		p:SetAlpha(1)
		p.delay = animate and (0.2 + math.min(i, 40) * 0.018) or nil
		p.pop = animate and 0 or 1
		p.hover = false
		self:SizePin(p)
		p:SetShown(not animate)
	end
	for i = n + 1, #self.pins do self.pins[i]:Hide() end
	self.shownPins = n

	-- the player, while on this map
	self:PlacePlayer()

	-- the state switches under the map
	for _, key in ipairs({ "ready", "active", "available", "toolow" }) do
		local b = self.switches[key]
		local c = pinColor(key)
		local off = hidden[key] and true or false
		b.dot:SetVertexColor(c[1], c[2], c[3], off and 0.25 or 1)
		local tc = off and C.dim or C.muted
		b.text:SetText(L((T.STATUS[key])[4]) .. "  " .. T.Hex(off and C.dim or C.text) .. counts[key] .. "|r")
		b.text:SetTextColor(tc[1], tc[2], tc[3], 1)
		b:SetWidth(6 + 8 + 6 + (b.text:GetStringWidth() or 60) + 10)
	end
	local placed = counts.ready + counts.active + counts.available + counts.toolow
	self.foot:SetText(placed == 0 and L("No quests to place on this map right now.") or "")

	if animate then
		self.clockReset()
		self.box:SetAlpha(0)
		self.animating = true
	else
		self.box:SetAlpha(1)
		self.animating = false
	end
end

function Map:PlacePlayer()
	local me = self.me
	local map, px, py = QL.PlayerPosition()
	local x, y
	if map and px and self.uiMap then x, y = QL.ProjectToMap(map, px, py, self.uiMap) end
	if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 and self.w then
		me:ClearAllPoints()
		me:SetPoint("CENTER", self.box, "TOPLEFT", x * self.w, -y * self.h)
		me:Show()
	else
		me:Hide()
	end
end

local function ease(t) t = math.max(0, math.min(1, t)); return 1 - (1 - t) ^ 3 end

function Map:Animate(clock)
	-- the map fades in, then the pins pop up one after the other with a small overshoot
	if self.animating then
		self.box:SetAlpha(ease(clock / 0.35))
		local all = true
		for i = 1, self.shownPins or 0 do
			local p = self.pins[i]
			if p.delay then
				local t = (clock - p.delay) / 0.28
				if t > 0 then
					p:Show()
					local e = ease(t)
					p.pop = e + math.sin(math.min(1, t) * math.pi) * 0.25
					if t >= 1 then p.pop = 1; p.delay = nil end
					self:SizePin(p)
				end
				if p.delay then all = false end
			end
		end
		if all and clock > 0.35 then self.animating = false; self.box:SetAlpha(1) end
	end
	-- the player's ring breathes; ready and selected pins pulse softly
	local pulse = 0.5 + 0.5 * math.sin(clock * 3)
	if self.me:IsShown() then
		local s = 22 + 12 * pulse
		self.me.ring:SetSize(s, s)
		self.me.ring:SetAlpha(1 - pulse * 0.7)
	end
	for i = 1, self.shownPins or 0 do
		local p = self.pins[i]
		if not p.delay and p.selected and not p.hover then
			p.halo:SetAlpha(0.3 + 0.7 * pulse)
		end
	end
	-- re-measure the player about twice a second
	self.nextMe = self.nextMe or 0
	if clock >= self.nextMe or clock < self.nextMe - 1 then
		self.nextMe = clock + 0.5
		self:PlacePlayer()
	end
end

function Map:Hide()
	self.frame:Hide()
	self.animating = false
end

-- On the world map ---------------------------------------------------------------------------------
-- The zone picked on the Zones tab also shows its pins on the game's world map (setting
-- worldMapPins): on that zone's map, and on a continent map the zone lies on (points projected
-- with QL.ProjectToMap). Same look and switches as the window's map; pins keep their screen size
-- while the map zooms (scaled by 1 / canvas scale) and quests closer than 14 screen pixels share
-- one. An overlay on WorldMapFrame:GetCanvas() just under the route's (MapRoute.lua).
--   QL.WorldPinSpots(mapID, area) -> { { x, y, ids, status }, ... } (0-1 on mapID, before merging)
--   QL.RefreshWorldPins(), QL.OpenZoneOnWorldMap(area)

local world = { pins = {}, spots = nil }
QL.worldPins = world -- for tests

-- the zone whose pins go on the world map: the one open on the Zones tab
local function pickedZone()
	local db = QL.DB()
	if db.worldMapPins == false then return nil end
	if type(db.zonesArea) ~= "number" then return nil end
	return db.zonesArea
end

function QL.WorldPinSpots(mapID, area)
	area = area or pickedZone()
	if not area or not mapID then return {} end
	local pins, uiMap = QL.ZoneMapPins(area, QL.Context(), { merge = 0.002, hidden = QL.ZoneMapHidden() })
	if not uiMap then return {} end
	local out = {}
	for _, p in ipairs(pins) do
		local x, y = p.x, p.y
		if mapID ~= uiMap then x, y = QL.ProjectToMap(uiMap, p.x, p.y, mapID) end
		if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			out[#out + 1] = { x = x, y = y, ids = p.ids, status = p.status }
		end
	end
	return out
end

local function canvasScale()
	if WorldMapFrame and WorldMapFrame.GetCanvasScale then
		local ok, s = pcall(WorldMapFrame.GetCanvasScale, WorldMapFrame)
		if ok and type(s) == "number" and s > 0 then return s end
	end
	return 1
end

function world.Size(p)
	local base = (p.status == "toolow") and 5 or 7
	local k = p.hover and 1.4 or 1
	p.core:SetSize(base * k, base * k)
	p.edge:SetSize((base + 3) * k, (base + 3) * k)
	p.ring:SetSize((base + 7) * k, (base + 7) * k)
	p.ring:SetShown(p.hover and true or false)
	p.halo:SetSize((base + 16) * k, (base + 16) * k)
	p.halo:SetShown(p.hover and true or false)
end

local function worldPin(i)
	local p = world.pins[i]
	if p then return p end
	local T, C = QL.Theme, QL.Theme.C
	p = CreateFrame("Button", nil, world.overlay)
	p:SetSize(18, 18)
	p.halo = p:CreateTexture(nil, "BACKGROUND")
	p.halo:SetTexture(MEDIA .. "disc")
	p.halo:SetPoint("CENTER")
	p.edge = p:CreateTexture(nil, "BORDER")
	p.edge:SetTexture(MEDIA .. "disc")
	p.edge:SetPoint("CENTER")
	p.edge:SetVertexColor(0.04, 0.05, 0.07, 0.9)
	p.core = p:CreateTexture(nil, "ARTWORK")
	p.core:SetTexture(MEDIA .. "disc")
	p.core:SetPoint("CENTER")
	p.ring = p:CreateTexture(nil, "OVERLAY")
	p.ring:SetTexture(MEDIA .. "ring")
	p.ring:SetPoint("CENTER")
	p.ring:SetVertexColor(1, 1, 1, 0.95)
	local badge = CreateFrame("Frame", nil, p)
	badge:SetSize(13, 13)
	badge:SetPoint("CENTER", p, "CENTER", 7, 6)
	badge.bg = badge:CreateTexture(nil, "ARTWORK")
	badge.bg:SetTexture(MEDIA .. "disc")
	badge.bg:SetAllPoints(badge)
	badge.bg:SetVertexColor(0.04, 0.05, 0.07, 0.92)
	badge.text = T.Text(badge, 9, C.text, nil, true)
	badge.text:SetPoint("CENTER", 0, 0)
	badge.text:SetJustifyH("CENTER")
	p.badge = badge
	p:SetScript("OnEnter", function(btn) btn.hover = true; world.Size(btn); pinTip(btn) end)
	p:SetScript("OnLeave", function(btn) btn.hover = false; world.Size(btn); QL.Tip():Hide() end)
	p:SetScript("OnClick", function(btn)
		local id = btn.ids and btn.ids[1]
		if not id then return end
		if btn.status ~= "toolow" and QL.SetArrowTarget and not (QL.RouteActive and QL.RouteActive()) then
			pcall(QL.SetArrowTarget, id)
		end
		QL.Open(id, { keepMap = true })
	end)
	world.pins[i] = p
	return p
end

local function hideWorldPins(from)
	from = from or 1
	for i = from, #world.pins do world.pins[i]:Hide() end
	world.shown = from - 1
end

-- Lay the spots out at the canvas's current size and zoom (cheap: called as the map zooms).
local function placeWorldPins()
	local o = world.overlay
	local spots = world.spots or {}
	local w, h = o:GetWidth() or 0, o:GetHeight() or 0
	if w <= 0 or h <= 0 or #spots == 0 then hideWorldPins(1); return end
	local s = canvasScale()
	world.scale = s
	local merge = 14 / s -- 14 screen pixels, in canvas units
	local groups = {}
	for _, sp in ipairs(spots) do
		local px, py = sp.x * w, sp.y * h
		local into
		for _, g in ipairs(groups) do
			if math.abs(g.px - px) < merge and math.abs(g.py - py) < merge then into = g; break end
		end
		if into then
			for _, id in ipairs(sp.ids) do into.ids[#into.ids + 1] = id end
			if PIN_ORDER[sp.status] < PIN_ORDER[into.status] then into.status = sp.status end
		else
			local ids = {}
			for _, id in ipairs(sp.ids) do ids[#ids + 1] = id end
			groups[#groups + 1] = { px = px, py = py, ids = ids, status = sp.status }
		end
	end
	-- the important ones on top
	table.sort(groups, function(a, b) return PIN_ORDER[a.status] > PIN_ORDER[b.status] end)
	for i, g in ipairs(groups) do
		local p = worldPin(i)
		p.ids, p.status = g.ids, g.status
		local c = pinColor(g.status)
		p.core:SetVertexColor(c[1], c[2], c[3], g.status == "toolow" and 0.8 or 1)
		p.halo:SetVertexColor(c[1], c[2], c[3], 0.3)
		p.badge:SetShown(#g.ids > 1)
		p.badge.text:SetText(#g.ids > 1 and tostring(#g.ids) or "")
		-- scaled by 1 / zoom so it keeps its size; offsets are then in the pin's own units
		p:SetScale(1 / s)
		p:ClearAllPoints()
		p:SetPoint("CENTER", o, "TOPLEFT", g.px * s, -g.py * s)
		p:SetFrameLevel(o:GetFrameLevel() + 1 + math.min(i, 8))
		p.hover = false
		world.Size(p)
		p:Show()
	end
	hideWorldPins(#groups + 1)
end

-- Recompute the spots (map changes, quest-log changes, a new zone picked) and lay them out.
function QL.RefreshWorldPins()
	local o = world.overlay
	if not o then return end
	local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local shown = WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()
	if not shown or type(mapID) ~= "number" or not pickedZone() or not (QL.IndexReady and QL.IndexReady()) then
		world.spots = nil
		hideWorldPins(1)
		return
	end
	world.spots = QL.WorldPinSpots(mapID)
	placeWorldPins()
end

local function ensureWorldOverlay()
	if world.overlay or not (WorldMapFrame and WorldMapFrame.GetCanvas) then return end
	local canvas = WorldMapFrame:GetCanvas()
	if not canvas then return end
	local o = CreateFrame("Frame", nil, canvas)
	o:SetAllPoints(canvas)
	local manager = WorldMapFrame.pinFrameLevelsManager
	local defs = manager and manager.definitions
	local level = defs and defs.PIN_FRAME_LEVEL_DIG_SITE
	if level and level.overrideType then level = defs[level.overrideType] end
	-- at the route's level (MapRoute.lua): any lower and the explored-area art of the map, a pin
	-- layer of its own, covered the pins wherever the zone was explored
	o:SetFrameLevel((level and level.startLevel) or (canvas:GetFrameLevel() + 2100))
	world.overlay = o
	local since = 0
	o:SetScript("OnUpdate", function(_, elapsed)
		since = since + (elapsed or 0)
		if since < 0.15 then return end
		since = 0
		if world.spots and #world.spots > 0 and canvasScale() ~= world.scale then pcall(placeWorldPins) end
	end)
	o:SetScript("OnSizeChanged", function() pcall(placeWorldPins) end)
	if hooksecurefunc and WorldMapFrame.SetMapID then
		hooksecurefunc(WorldMapFrame, "SetMapID", function() pcall(QL.RefreshWorldPins) end)
	end
end

local function hookWorld()
	if not WorldMapFrame or world.hooked then return end
	world.hooked = true
	WorldMapFrame:HookScript("OnShow", function()
		local ok, err = pcall(ensureWorldOverlay)
		if not ok then QL.Debug("world pins: " .. tostring(err)) end
		pcall(QL.RefreshWorldPins)
	end)
	WorldMapFrame:HookScript("OnHide", function() hideWorldPins(1) end)
	if WorldMapFrame:IsShown() then pcall(ensureWorldOverlay); pcall(QL.RefreshWorldPins) end
end

QL.Event("PLAYER_LOGIN", function() pcall(hookWorld) end)
QL.Event("ADDON_LOADED", function(_, name) if name == "Blizzard_WorldMap" then pcall(hookWorld) end end)
for _, m in ipairs({ "STATE_CHANGED", "SETTING_CHANGED", "INDEX_READY" }) do
	QL.On(m, function() if world.overlay then pcall(QL.RefreshWorldPins) end end)
end

-- Open the game's world map at a zone (the window's zone map has a button for it).
function QL.OpenZoneOnWorldMap(area)
	local uiMap = QL.AreaUiMap(area)
	if not uiMap or not WorldMapFrame then return false end
	if InCombatLockdown and InCombatLockdown() and not WorldMapFrame:IsShown() then
		QL.Print(L("The world map cannot be opened in combat."), "warn")
		return false
	end
	if not WorldMapFrame:IsShown() then
		local ok = false
		if OpenWorldMap then ok = pcall(OpenWorldMap, uiMap) end
		if not ok and ShowUIPanel then ok = pcall(ShowUIPanel, WorldMapFrame) end
		if not ok then pcall(WorldMapFrame.Show, WorldMapFrame) end
	end
	if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, uiMap) end
	pcall(hookWorld)
	pcall(ensureWorldOverlay)
	pcall(QL.RefreshWorldPins)
	return true
end

-- /ql map also tells what the world map pins do: the map shown, the zone picked, spots and pins,
-- and the frame levels around them (pins under the explored-area art were the first suspect).
function QL.WorldPinDebug()
	local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local area = pickedZone()
	QL.Chat(("world map pins: setting %s · picked zone %s (uiMap %s) · world map %s, map %s"):format(
		tostring(QL.DB().worldMapPins ~= false), tostring(QL.DB().zonesArea), tostring(area and QL.AreaUiMap(area)),
		(WorldMapFrame and WorldMapFrame:IsShown()) and "open" or "closed", tostring(mapID)))
	local spots = (mapID and area) and QL.WorldPinSpots(mapID) or {}
	local placed = 0
	for i = 1, #world.pins do if world.pins[i]:IsShown() then placed = placed + 1 end end
	QL.Chat(("spots %d · pins shown %d · canvas scale %.2f"):format(#spots, placed, canvasScale()))
	local manager = WorldMapFrame and WorldMapFrame.pinFrameLevelsManager
	local defs = manager and manager.definitions
	if type(defs) == "table" then
		local function lv(name) local d = defs[name]; return d and d.startLevel and tostring(d.startLevel) or "-" end
		QL.Chat("levels: overlay " .. tostring(world.overlay and world.overlay:GetFrameLevel()) .. " · exploration " .. lv("PIN_FRAME_LEVEL_MAP_EXPLORATION")
			.. " · dig site " .. lv("PIN_FRAME_LEVEL_DIG_SITE") .. " · area POI " .. lv("PIN_FRAME_LEVEL_AREA_POI"))
	end
end

-- Where a task's target is found ---------------------------------------------------------------------
-- A click on a task in the detail panel (an item to collect, a creature to slay, an object to use)
-- shows on the window's map every place it can be had: for an item, the spawns of the creatures that
-- drop it and the objects it comes from; for a creature or an object, its own spawns. One colour per
-- source, named under the map; the map with the most places first (the player's own map when it has
-- any), the others a click away under the map. A spot's tooltip names its source; a click points
-- the arrow there.
--   QL.TaskSources(kind, id) -> { sources = { {kind, id, name, points = {{map, x, y}, ...}}, ... },
--                                 maps = { {map, count}, ... } (most places first) }
--   map:ShowSpots(view, ctx, animate)  view = { kind, id, name, questId, map }

local SPOT_CAP = 300 -- spawns per source (some creatures stand in hundreds of places)

local function sourceColors()
	local C, S = QL.Theme.C, QL.Theme.STATUS
	return { C.accent, S.toolow, C.accent2, S.ready, S.active, { 0.95, 0.45, 0.70 }, S.done, { 0.85, 0.85, 0.85 } }
end

function QL.TaskSources(kind, id)
	local sources = {}
	local function add(k, sid)
		local get = k == "npc" and QL.N or QL.O
		local name = get(sid, "name")
		local spawns = get(sid, "spawns")
		local pts = {}
		if type(spawns) == "table" then
			for area, list in pairs(spawns) do
				local map = QL.AreaUiMap(area)
				if map and type(list) == "table" then
					for _, p in ipairs(list) do
						if #pts >= SPOT_CAP then break end
						if type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number" and p[1] >= 0 and p[2] >= 0 then
							pts[#pts + 1] = { map = map, x = p[1] / 100, y = p[2] / 100 }
						end
					end
				end
			end
		end
		if #pts > 0 then
			sources[#sources + 1] = { kind = k, id = sid, name = type(name) == "string" and name or ("#" .. sid), points = pts }
		end
	end
	if kind == "item" then
		for n, npc in ipairs(QL.Ids(QL.I(id, "npcDrops"))) do
			if n > 12 then break end
			add("npc", npc)
		end
		for n, obj in ipairs(QL.Ids(QL.I(id, "objectDrops"))) do
			if n > 8 then break end
			add("object", obj)
		end
	elseif kind == "npc" or kind == "object" then
		add(kind, id)
	elseif kind == "name" and QL.SearchNpcs then
		-- every creature matching a name (the creature search): those in your zone first, 8 colours
		for n, row in ipairs(QL.SearchNpcs(id)) do
			if n > 8 then break end
			add("npc", row.id)
		end
	end
	table.sort(sources, function(a, b)
		if #a.points ~= #b.points then return #a.points > #b.points end
		return a.id < b.id
	end)
	local count = {}
	for _, src in ipairs(sources) do
		for _, p in ipairs(src.points) do count[p.map] = (count[p.map] or 0) + 1 end
	end
	local maps = {}
	for m, c in pairs(count) do maps[#maps + 1] = { map = m, count = c } end
	table.sort(maps, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.map < b.map
	end)
	return { sources = sources, maps = maps }
end

local function spotTip(dot)
	local tip = QL.Tip()
	tip:SetOwner(dot, "ANCHOR_RIGHT")
	local c = dot.color
	tip:AddLine(dot.sourceName or "?", c[1], c[2], c[3])
	if dot.what then tip:AddLine(dot.what, 0.8, 0.8, 0.8) end
	tip:AddLine(("%.1f, %.1f"):format(dot.x * 100, dot.y * 100), 0.6, 0.6, 0.6)
	tip:AddLine(L("Click: point the arrow here"), 0.24, 0.84, 0.78)
	tip:Show()
end

function Map:Spot(i)
	self.spots = self.spots or {}
	local d = self.spots[i]
	if d then return d end
	d = CreateFrame("Button", nil, self.pinLayer)
	d:SetSize(12, 12)
	d.edge = d:CreateTexture(nil, "BORDER")
	d.edge:SetTexture(MEDIA .. "disc")
	d.edge:SetPoint("CENTER")
	d.edge:SetSize(8, 8)
	d.edge:SetVertexColor(0.04, 0.05, 0.07, 0.85)
	d.core = d:CreateTexture(nil, "ARTWORK")
	d.core:SetTexture(MEDIA .. "disc")
	d.core:SetPoint("CENTER")
	d.core:SetSize(5, 5)
	d:SetScript("OnEnter", function(btn)
		btn.core:SetSize(8, 8); btn.edge:SetSize(11, 11)
		spotTip(btn)
	end)
	d:SetScript("OnLeave", function(btn)
		btn.core:SetSize(5, 5); btn.edge:SetSize(8, 8)
		QL.Tip():Hide()
	end)
	d:SetScript("OnClick", function(btn)
		if QL.SetArrowPoint then
			QL.SetArrowPoint(btn.map, btn.x, btn.y, { title = btn.sourceName, label = btn.label })
		end
	end)
	self.spots[i] = d
	return d
end

-- Under the map in the sources view: one button per other map with places, "Name (12)".
function Map:MapButton(i)
	self.mapButtons = self.mapButtons or {}
	local b = self.mapButtons[i]
	if b then return b end
	local T = QL.Theme
	b = T.Button(self.footFrame, 110, 22)
	b:SetScript("OnClick", function(btn)
		if self.view then
			self.view.map = btn.map
			if QL.RenderWindow then QL.RenderWindow(false) end
		end
	end)
	self.mapButtons[i] = b
	return b
end

-- The zone view's parts (pins, state switches, world map button) off while places are shown.
function Map:SpotMode(on)
	self.spotMode = on
	for _, b in pairs(self.switches or {}) do b:SetShown(not on) end
	if self.worldBtn then self.worldBtn:SetShown(not on) end
	if on then
		for i = 1, #self.pins do self.pins[i]:Hide() end
		self.shownPins = 0
	else
		for _, d in ipairs(self.spots or {}) do d:Hide() end
		for _, b in ipairs(self.mapButtons or {}) do b:Hide() end
		if self.srcLegend then self.srcLegend:SetText("") end
		self.view = nil
	end
end

function Map:ShowSpots(view, ctx, animate)
	local T, C = QL.Theme, QL.Theme.C
	local f = self.frame
	f:Show()
	self:SpotMode(true)
	self.view = view
	view.data = view.data or QL.TaskSources(view.kind, view.id)
	local data = view.data
	-- the map: the one picked under the map, else the player's own when it has places, else the fullest
	local map = view.map
	if not map then
		local here = QL.PlayerPosition()
		for _, m in ipairs(data.maps) do if m.map == here then map = here end end
		map = map or (data.maps[1] and data.maps[1].map)
	end
	view.map = map
	local what = view.kind == "item" and L("Collect") or (view.kind == "npc" or view.kind == "name") and L("Slay") or L("Use")
	self.kicker:SetText(view.kind == "name" and L("Creatures") or L("Where to find"))
	self.title:SetText(view.name or "?")
	local names = {}
	for i, src in ipairs(data.sources) do
		if i > 3 then names[#names + 1] = L("+%d more"):format(#data.sources - 3); break end
		names[#names + 1] = src.name
	end
	local here = 0
	for _, m in ipairs(data.maps) do if m.map == map then here = m.count end end
	if #data.sources == 0 then
		self.sub:SetText(L("No known places for this in the database."))
	else
		local lead = view.kind == "item" and L("Drops from: ") or ""
		self.sub:SetText(lead .. table.concat(names, ", ") .. "  ·  " .. L("%d places on this map"):format(here))
	end

	local w, h = self:Fit(map)
	-- the places, one colour per source; the first sources drawn last (on top)
	local colors = sourceColors()
	local n = 0
	local label = view.questId and (what .. ": " .. QL.QuestTitle(view.questId)) or what
	for si = #data.sources, 1, -1 do
		local src = data.sources[si]
		local c = colors[(si - 1) % #colors + 1]
		src.color = c
		for _, p in ipairs(src.points) do
			if p.map == map then
				n = n + 1
				local d = self:Spot(n)
				d.map, d.x, d.y = p.map, p.x, p.y
				d.sourceName, d.color, d.label = src.name, c, label
				d.what = src.kind == "object" and L("Object") or (view.kind == "item" and L("Drops it") or nil)
				d.core:SetVertexColor(c[1], c[2], c[3], 1)
				d:ClearAllPoints()
				d:SetPoint("CENTER", self.box, "TOPLEFT", p.x * w, -p.y * h)
				d:SetFrameLevel(self.pinLayer:GetFrameLevel() + 1 + math.min(#data.sources - si, 20))
				d:Show()
			end
		end
	end
	for i = n + 1, #(self.spots or {}) do self.spots[i]:Hide() end
	self.shownSpots = n
	self:PlacePlayer()

	-- under the map: the sources in their colours, and the other maps with places
	if not self.srcLegend then
		self.srcLegend = T.Text(self.footFrame, 11, C.muted)
		self.srcLegend:SetPoint("LEFT", 18, 0)
	end
	local parts = {}
	for i, src in ipairs(data.sources) do
		if i > 4 then break end
		local c = src.color
		parts[#parts + 1] = ("|T%sdisc:9:9:0:0:64:64:0:64:0:64:%d:%d:%d|t "):format(MEDIA, math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) .. src.name
	end
	self.srcLegend:SetText(table.concat(parts, "    "))
	local bi = 0
	local prev
	for _, m in ipairs(data.maps) do
		if m.map ~= map and bi < 3 then
			bi = bi + 1
			local b = self:MapButton(bi)
			b.map = m.map
			b:SetLabel(((QL.MapName and QL.MapName(m.map)) or ("#" .. m.map)) .. " (" .. m.count .. ")")
			b:SetWidth(math.max(70, (b.label and b.label.GetStringWidth and b.label:GetStringWidth() or 90) + 20))
			b:ClearAllPoints()
			if prev then b:SetPoint("RIGHT", prev, "LEFT", -6, 0) else b:SetPoint("RIGHT", self.footFrame, "RIGHT", -12, 0) end
			b:Show()
			prev = b
		end
	end
	for i = bi + 1, #(self.mapButtons or {}) do self.mapButtons[i]:Hide() end
	self.foot:SetText("")

	if animate then
		self.clockReset()
		self.box:SetAlpha(0)
		self.animating = true
	else
		self.box:SetAlpha(1)
	end
end
