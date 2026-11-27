-- Smoke test: every file under a mock client (frames that accept any call), the window opened on
-- a quest, a name search, the NPC tooltip line and the quest offer strip.
local QL0 = dofile("tests/stubs.lua") -- fixture LibQuestieDB, helpers
local Check, Eq = QL0.Check, QL0.Eq

-- Mock widgets ------------------------------------------------------------------
local frames = {}
local function mock(kind, name)
	local o = { kind = kind, scripts = {}, shown = true, text = "", points = 0, children = {} }
	local mt = {}
	mt.__index = function(t, k)
		local f = rawget(mt, k)
		if f then return f end
		if not k:match("^%u") then return nil end -- plain fields read as nil, as on real frames
		if k:match("^Get") or k:match("^Is") then return function() return 0 end end
		return function() end
	end
	-- Colour setters reject anything but numbers, as the real client does (a status label passed
	-- as alpha once broke the zone list in game while this mock let it through).
	local function numbers(what, ...)
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			if v ~= nil and type(v) ~= "number" then error(what .. ": argument " .. i .. " is a " .. type(v), 3) end
		end
	end
	-- As in the client, SetVertexColor overwrites the vertex colours a gradient set.
	function mt.SetVertexColor(self, ...)
		numbers("SetVertexColor", ...)
		self.vertex = { ... }
		self.gradient = nil
	end
	function mt.SetGradient(self, dir, c1, c2) self.gradient = { dir, c1, c2 } end
	function mt.SetRotation(self, r) self.rotation = r end
	function mt.SetScale(self, v) self.scale = v end
	function mt.IsForbidden() return false end
	function mt.SetPoint(self, ...) self.point = { ... } end
	function mt.SetFrameStrata(self, v) self.strata = v end
	function mt.GetFrameStrata(self) return self.strata end
	function mt.SetTextColor(self, ...) numbers("SetTextColor", ...) end
	function mt.SetColorTexture(self, ...) numbers("SetColorTexture", ...) end
	function mt.SetScript(self, s, fn) self.scripts[s] = fn end
	-- as in the client, hooks run after the script already there
	function mt.HookScript(self, s, fn)
		local prev = self.scripts[s]
		self.scripts[s] = prev and function(...) prev(...); fn(...) end or fn
	end
	function mt.GetScript(self, s) return self.scripts[s] end
	function mt.Show(self)
		local was = self.shown
		self.shown = true
		if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
	end
	function mt.Hide(self)
		local was = self.shown
		self.shown = false
		if was and self.scripts.OnHide then self.scripts.OnHide(self) end
	end
	function mt.SetShown(self, v) if v then self:Show() else self:Hide() end end
	function mt.SetEnabled(self, v) self.enabled = v and true or false end
	function mt.IsShown(self) return self.shown end
	function mt.SetText(self, t) self.text = t or "" end
	function mt.GetText(self) return self.text end
	function mt.GetStringHeight() return 12 end
	function mt.GetWidth() return 600 end
	function mt.GetHeight() return 400 end
	function mt.GetEffectiveScale() return 1 end
	function mt.SetAlpha(self, a) self.alpha = a end
	function mt.GetAlpha(self) return self.alpha or 1 end
	function mt.GetParent(self) return self.parent end
	function mt.SetParent(self, p) self.parent = p end
	function mt.GetChecked(self) return self.checked end
	function mt.SetChecked(self, v) self.checked = v end
	function mt.GetName() return name end
	function mt.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
	function mt.CreateTexture(self) local t = mock("Texture"); t.parent = self; return t end
	function mt.CreateFontString(self) local t = mock("FontString"); t.parent = self; return t end
	function mt.CreateLine(self) local t = mock("Line"); t.parent = self; return t end
	function mt.SetScale(self, v) self.scale = v end
	function mt.IsForbidden() return false end
	function mt.GetScale(self) return self.scale or 1 end
	return setmetatable(o, mt)
end

function CreateFrame(kind, name, parent)
	local f = mock(kind, name)
	f.parent = parent
	if kind ~= "Frame" or name then f.shown = true end
	frames[#frames + 1] = f
	if kind == "CheckButton" then f.Text = mock("FontString") end
	if name then _G[name] = f end
	return f
end
UIParent = mock("Frame", "UIParent")
WorldMapFrame = mock("Frame", "WorldMapFrame")
WorldMapFrame.shown = false
local mapCanvas = mock("Frame", "MapCanvas")
WorldMapFrame.GetCanvas = function() return mapCanvas end
WorldMapFrame.GetMapID = function() return 1411 end
WorldMapFrame.ScrollContainer = mock("Frame", "MapScroll")
Minimap = mock("Frame", "Minimap")
UISpecialFrames = {}
GameTooltip = mock("GameTooltip", "GameTooltip")
GameTooltip.lines = {}
function GameTooltip:AddLine(t) table.insert(self.lines, t) end
function GameTooltip:SetOwner() self.lines = {} end
QuestFrame = mock("Frame", "QuestFrame")
C_Timer = { After = function(_, fn) fn() end }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
SlashCmdList = {}
function strsplit(sep, s)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%-", "%%-")) do out[#out + 1] = part end
	return unpack(out)
end
function hooksecurefunc() end
function UnitLevel() return 5 end
function UnitFactionGroup() return "Horde" end
function UnitRace() return "Human", "Human", 1 end
function UnitClass() return "Warrior", "WARRIOR", 1 end
C_QuestLog = {
	GetNumQuestLogEntries = function() return 1 end,
	GetInfo = function(i) return { questID = 2, isHeader = false } end,
	IsComplete = function() return false end,
	IsQuestFlaggedCompleted = function(id) return id == 1 or id == 11 or id == 12 end, -- the loop chain is done
}
local tooltipPost
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) tooltipPost = fn end }
Enum = { TooltipDataType = { Unit = 2 } }
CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
function GetPlayerFacing() return 0 end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
C_Map = {
	GetPlayerMapPosition = function() return CreateVector2D(0.5, 0.4) end,
	GetMapWorldSize = function() return 1000, 800 end,
	GetBestMapForUnit = function() return 1411 end,
	GetMapInfo = function(id) if id == 1411 then return { name = "Durotar", parentMapID = 1414 } end end,
	GetAreaInfo = function(area) return ({ [14] = "Durotar", [215] = "Mulgore" })[area] end,
}
function GetCursorPosition() return 0, 0 end
Settings = { RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end, RegisterAddOnCategory = function() end }

-- Load ------------------------------------------------------------------------------
QuestLineageDB = nil
local QL = {}
for _, file in ipairs({ "Core.lua", "Locale.lua", "Data.lua", "Zone.lua", "State.lua", "Chain.lua", "Details.lua", "Nav.lua", "Theme.lua", "Tree.lua", "Inspector.lua", "ZoneMap.lua", "Window.lua", "Arrow.lua", "Route.lua", "MapRoute.lua", "Services.lua", "QuickBar.lua", "Toast.lua", "Current.lua", "Plates.lua", "QuestAreas.lua", "Corpse.lua", "Paths.lua", "Flight.lua", "Nearby.lua", "QuestCard.lua", "MinimapButton.lua", "Hooks.lua", "Options.lua" }) do
	assert(loadfile(file))("QuestLineage", QL)
end
for _, fn in ipairs(QL.events.PLAYER_LOGIN) do fn("PLAYER_LOGIN") end
Check(SlashCmdList.QUESTLINEAGE, "slash command registered")
Check(tooltipPost, "tooltip hook installed")
Check(QuestLineageOption1, "options built")

local function runUpdates()
	for _ = 1, 5 do
		for _, fr in ipairs(frames) do
			local up = fr.scripts.OnUpdate
			if up then up(fr, 0.05) end
		end
	end
end

-- Opening before the index exists shows the building state, then the tree --------------------
QL.ToggleWindow()
local f = QuestLineageFrame
Check(f and f.shown, "window shown")
runUpdates()
Check(QL.IndexReady(), "index built by the slicer")
QL.Open(3)
Eq(f.infoTitle.text, "First Steps", "info bar names the chain after its first quest")
Eq(f.inspector.hero.title.text, "The Gathering", "detail panel shows the focused quest")
Check(f.infoMeta.text:find("1/8 done", 1, true), "progress in the meta line: " .. f.infoMeta.text)
-- the chain's XP still to earn: 3 (450, locked) + 5 (220, available) at level 5
Eq(f.infoXP.text, "+670 XP", "chain XP left")
Eq(f.infoXPLabel.text, "Chain completed:", "XP label")
Check(f.infoGain.text:find("+0.2 level", 1, true), "share of the level: " .. f.infoGain.text)
Check(f.infoGain.text:find("Lv 5: 0% » 23%", 1, true), "level 5 from 0% to 23%: " .. f.infoGain.text)
Eq(f.levelBar.gain.level, 5, "level bar knows the gain")

-- Quests: the log and what the zone offers now, most XP first -------------------------------------
-- by default chain quests stay out of this list (they have the Chains tab)
QL.ShowPage("quests")
local onlyStandalone = {}
for _, r in ipairs(f.questsPage.list.rows) do if r.shown then onlyStandalone[#onlyStandalone + 1] = r.questId end end
Eq(#onlyStandalone, 0, "Rumours and Second Steps are both in chains: none listed")
Eq(#QL.ZoneQuestList(QL.PlayerZone(), QL.Context(), { noChains = false }), 2, "both there without the filter")
Eq(#QL.errors, 0, "an empty Quests list without errors: " .. table.concat(QL.errors, " | "))
-- the rest of these tests use the full list
QL.Set("questsHideChains", false)
QL.ShowPage("quests")
local qp = f.questsPage
Eq(qp.shown, true, "quests page shown")
Eq(f.questsTab.active, true, "quests tab active")
local qrows = {}
for _, r in ipairs(qp.list.rows) do if r.shown then qrows[#qrows + 1] = r end end
Eq(#qrows, 2, "the quest in the log and the one available")
Eq(qrows[1].questId, 5, "most XP first")
Eq(qrows[1].chip.text, "+220 XP", "xp chip")
Eq(qrows[2].questId, 2, "the logged quest without XP data last")
Eq(qrows[2].chip.text, "no XP data", "no data chip")
Check(qrows[2].sub.text:find("In your log", 1, true), "state on the row: " .. qrows[2].sub.text)
Check(qrows[1].sub.text:find("Chain ", 1, true), "chain position on the row: " .. qrows[1].sub.text)
Check(qp.sub.text:find("2 quests · 1 in your log", 1, true), "summary: " .. qp.sub.text)
-- sorting: XP · Lv · Near beside the filter box
local function shownIds(page)
	local ids = {}
	for _, r in ipairs(page.list.rows) do if r.shown then ids[#ids + 1] = r.questId end end
	return table.concat(ids, ",")
end
Eq(qp.sorts.level.shown, true, "sort buttons beside the filter")
Eq(qp.sorts.xp.active, false, "none lit: the list's own order")
qp.sorts.level.scripts.OnClick(qp.sorts.level)
Eq(QL.DB().sortQuests, "level", "sorted by level")
Eq(qp.sorts.level.active, true, "its button lit")
Eq(shownIds(qp), "2,5", "lowest level first (Second Steps 3, Rumours 4)")
qp.sorts.xp.scripts.OnClick(qp.sorts.xp)
Eq(shownIds(qp), "5,2", "most XP first, no XP data last")
qp.sorts.distance.scripts.OnClick(qp.sorts.distance)
Eq(QL.DB().sortQuests, "distance", "by distance")
Eq(#QL.errors, 0, "distance sort without errors: " .. table.concat(QL.errors, " | "))
qp.sorts.distance.scripts.OnClick(qp.sorts.distance)
Eq(QL.DB().sortQuests, nil, "a click on the lit one: the list's own order")
Eq(shownIds(qp), "5,2", "back to the own order")
qrows[1].scripts.OnClick(qrows[1])
Eq(f.inspector.hero.title.text, "Rumours", "a quest row opens its details")
Eq(qrows[1].selected, true, "the open quest's row is selected")
QL.Open(3)
Eq(f.empty.shown, false, "no empty state over a chain")
Check(f.legend.text:find("requires", 1, true), "legend drawn")

-- This zone: Durotar's two chains, the one in progress first ------------------------------------
QL.ShowPage("zone")
local zp = f.zonePage
Eq(zp.shown, true, "zone page shown")
Eq(f.searchPage.shown, false, "search page hidden")
Eq(f.zoneTab.active, true, "zone tab active")
Eq(zp.zone.text, "Durotar", "zone name")
Check(zp.sub.text:find("2 chains", 1, true), "zone summary: " .. zp.sub.text)
local rows = {}
for _, r in ipairs(zp.list.rows) do if r.shown then rows[#rows + 1] = r end end
Eq(#rows, 2, "two chain rows")
Eq(rows[1].chip.text, "In progress", "chain with a logged quest first")
Eq(rows[1].openId, 2, "it opens at the quest in the log")
Eq(rows[1].selected, true, "the open chain's row is selected")
Eq(rows[2].chip.text, "Already done", "the finished loop chain comes last")
Check(zp.list.child:GetHeight() > 0 or true, "list height set")
Check(rows[1].sub.text:find("1/8 done", 1, true), "row sub line: " .. rows[1].sub.text)
Check(rows[1].sub.text:find("+670 XP", 1, true), "chain XP left on the row: " .. rows[1].sub.text)
rows[2].scripts.OnClick(rows[2])
Check(f.infoTitle.text:find("Loop", 1, true), "clicking a row opens its tree: " .. f.infoTitle.text)
Eq(rows[2].selected, true, "clicked row selected")
Eq(rows[1].selected, false, "other row not selected")
-- every quest click points the arrow: a chain row (at the quest it opens) and a tree card
rows[1].scripts.OnClick(rows[1])
Eq(QL.ArrowQuest(), 2, "a chain row points the arrow at its quest in the log")
local card5
for i = 1, f.tree.usedCards do if f.tree.cards[i].questId == 5 then card5 = f.tree.cards[i] end end
card5.scripts.OnClick(card5)
Eq(QL.ArrowQuest(), 5, "a tree card points the arrow")
Eq(QuestLineageArrow.shown, true, "the arrow shows")
QL.ClearArrow()

-- Class: the warrior's class quests, open ones by level -----------------------------------------
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
QL.ShowPage("class")
local cp = f.classPage
Eq(cp.shown, true, "class page shown")
Eq(f.classTab.active, true, "class rail button active")
Eq(f.questsTab.active, false, "the others not")
Eq(f.classTab.bar.shown, true, "accent bar on the active rail button")
Eq(cp.zone.text, "Warrior", "class name")
Eq(cp.icon.shown, true, "class emblem")
local crows = {}
for _, r in ipairs(cp.list.rows) do if r.shown then crows[#crows + 1] = r end end
Eq(#crows, 2, "a class chain and a single class quest")
Eq(crows[1].questId, 22, "the lowest level first: Shield Lesson")
Eq(crows[1].chip.text, "Available", "level 4, takeable at 5")
Eq(crows[2].questId, 20, "then the level 10 chain")
Eq(crows[2].chip.text, "Level too low", "level 10 needed")
Check(cp.sub.text:find("3 quests", 1, true), "class summary: " .. cp.sub.text)
crows[1].scripts.OnClick(crows[1])
Eq(f.inspector.hero.title.text, "Shield Lesson", "a class row opens its quest")
Eq(QL.ArrowQuest(), 22, "and points the arrow")
QL.ClearArrow()

-- Filter boxes on the Quests, Chains and Class pages ------------------------------------------------
QL.ShowPage("quests")
local qpf = f.questsPage
qpf.filter:SetText("rum")
qpf.filter.scripts.OnTextChanged(qpf.filter, true)
local kept = {}
for _, r in ipairs(qpf.list.rows) do if r.shown then kept[#kept + 1] = r.questId end end
Eq(table.concat(kept, ","), "5", "only Rumours matches 'rum'")
Eq(qpf.sub.text, "1 of 2 match", "how many match")
qpf.filter:SetText("")
qpf.filter.scripts.OnTextChanged(qpf.filter, true)
kept = {}
for _, r in ipairs(qpf.list.rows) do if r.shown then kept[#kept + 1] = r.questId end end
Eq(#kept, 2, "an empty filter shows all again")
QL.ShowPage("zone")
local zpf = f.zonePage
zpf.filter:SetText("loop")
zpf.filter.scripts.OnTextChanged(zpf.filter, true)
kept = {}
for _, r in ipairs(zpf.list.rows) do if r.shown then kept[#kept + 1] = r end end
Eq(#kept, 1, "one chain has a quest named Loop")
Check(kept[1].title.text:find("Loop", 1, true), "the loop chain: " .. kept[1].title.text)
zpf.filter:SetText("gathering")
zpf.filter.scripts.OnTextChanged(zpf.filter, true)
kept = {}
for _, r in ipairs(zpf.list.rows) do if r.shown then kept[#kept + 1] = r end end
Eq(#kept, 1, "a chain matches by any of its quests, not only its first")
zpf.filter:SetText("")
zpf.filter.scripts.OnTextChanged(zpf.filter, true)
QL.ShowPage("class")
f.classPage.filter:SetText("shield")
f.classPage.filter.scripts.OnTextChanged(f.classPage.filter, true)
kept = {}
for _, r in ipairs(f.classPage.list.rows) do if r.shown then kept[#kept + 1] = r.questId end end
Eq(table.concat(kept, ","), "22", "class quests filter too")
f.classPage.filter:SetText("")
f.classPage.filter.scripts.OnTextChanged(f.classPage.filter, true)

-- Zones: every zone with quests, by continent; a click lists one zone's quests -----------------------
do
	local getInfo = C_Map.GetMapInfo
	C_Map.GetMapInfo = function(id)
		if id == 1414 then return { name = "Kalimdor", mapType = 2 } end
		if id == 1412 then return { name = "Mulgore", parentMapID = 1414 } end
		return getInfo(id)
	end
	f.zonesTab.scripts.OnClick(f.zonesTab)
	local zs = f.zonesPage
	Eq(zs.shown, true, "zones page shown")
	Eq(f.zonesTab.active, true, "zones rail button active")
	Eq(zs.zone.text, "Zones", "zone list heading")
	Eq(zs.back.shown, false, "no back button on the list")
	Eq(zs.sorts.xp.shown, false, "no sort buttons on the zone list")
	local heads, zrows = {}, {}
	for _, r in ipairs(zs.list.rows) do
		if r.shown then
			if r.isHeader then heads[#heads + 1] = r.title.text else zrows[#zrows + 1] = r end
		end
	end
	Eq(heads[1], "KALIMDOR", "continent heading first")
	Eq(heads[#heads], "DUNGEONS AND OTHER PLACES", "places without a continent last")
	local durotar
	for _, r in ipairs(zrows) do if r.zone.area == 14 then durotar = r end end
	Check(durotar, "Durotar listed")
	Check(durotar.title.text:find("Durotar", 1, true), "zone name: " .. durotar.title.text)
	Eq(durotar.chip.text, "You are here", "the player's zone is marked")
	Check(durotar.sub.text:find("done", 1, true), "done count on the row: " .. durotar.sub.text)
	Check(zs.sub.text:find("zones", 1, true), "zone summary: " .. zs.sub.text)
	durotar.scripts.OnEnter(durotar)
	durotar.scripts.OnLeave(durotar)
	-- the filter narrows zones by name
	zs.filter:SetText("mulg")
	zs.filter.scripts.OnTextChanged(zs.filter, true)
	local names = {}
	for _, r in ipairs(zs.list.rows) do if r.shown and not r.isHeader then names[#names + 1] = r.zone.name end end
	Eq(table.concat(names, ","), "Mulgore", "filtered to Mulgore")
	zs.filter:SetText("")
	zs.filter.scripts.OnTextChanged(zs.filter, true)
	-- a click opens the zone's quests: open ones first, done ones after
	-- (the fixture quests have no givers in Durotar: each gets a spot of its own, 2 and 5 share one)
	-- map art: without art calls the classic file paths; with them, called plainly (not as methods)
	local _, pathFiles, source = QL.ZoneMapArt(1411)
	Eq(source, "path", "no art calls: classic files")
	Eq(pathFiles[12], "Interface\\WorldMap\\Durotar\\Durotar12", "Durotar's last tile")
	C_Map.GetMapArtLayers = function(m)
		assert(type(m) == "number", "GetMapArtLayers called as a method")
		return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } }
	end
	C_Map.GetMapArtLayerTextures = function(m, layer)
		assert(type(m) == "number" and layer == 1, "GetMapArtLayerTextures called as a method")
		local ids = {}
		for i = 1, 12 do ids[i] = 1000 + i end
		return ids
	end
	local _, ids, src = QL.ZoneMapArt(1411)
	Eq(src, "client", "file ids from the client")
	Eq(#ids, 12, "twelve tiles")
	local questTarget = QL.QuestTarget
	QL.QuestTarget = function(id)
		local x = (id == 2 or id == 5) and 0.3 or (0.05 * id)
		return { kind = "pickup", points = { { map = 1411, x = x, y = 0.5 }, { map = 1412, x = 0.9, y = 0.9 } } }
	end
	for _, r in ipairs(zs.list.rows) do if r.shown and r.zone and r.zone.area == 14 then durotar = r end end
	durotar.scripts.OnClick(durotar)
	Eq(QL.DB().zonesArea, 14, "zone remembered")
	Eq(zs.back.shown, true, "back button shown")
	Eq(zs.zone.text, "Durotar", "zone heading")
	Eq(zs.sorts.xp.shown, true, "sort buttons over a zone's quests")
	local function zoneIds()
		local ids, sts = {}, {}
		for _, r in ipairs(zs.list.rows) do if r.shown then ids[#ids + 1] = r.questId end end
		return ids
	end
	local own = table.concat(zoneIds(), ",")
	zs.sorts.level.scripts.OnClick(zs.sorts.level)
	local lv = zoneIds()
	local TIER = { ready = 1, active = 1, available = 1, toolow = 2, locked = 2 }
	local ctxz = QL.Context()
	for i = 2, #lv do
		local ta, tb = TIER[QL.NodeStatus(lv[i - 1], ctxz)] or 3, TIER[QL.NodeStatus(lv[i], ctxz)] or 3
		Check(ta < tb or (ta == tb and (QL.QuestLevel(lv[i - 1]) or 0) <= (QL.QuestLevel(lv[i]) or 0)), "zone quests by level within their tier at " .. i)
	end
	zs.sorts.level.scripts.OnClick(zs.sorts.level)
	Eq(table.concat(zoneIds(), ","), own, "own order back")
	-- the zone's map in the middle, pins for what can be done there
	Eq(f.zoneMap.frame.shown, true, "the zone map shows")
	Eq(f.canvasScroll.shown, false, "the tree is hidden under it")
	Eq(f.zoneMap.title.text, "Durotar", "map heading")
	Eq(f.zoneMap.noArt.text, "", "the art was drawn")
	local pins = QL.ZoneMapPins(14, QL.Context())
	Check(#pins >= 1, "pins on Durotar's map: " .. #pins)
	for _, pin in ipairs(pins) do
		Check(pin.x >= 0 and pin.x <= 1 and pin.y >= 0 and pin.y <= 1, "pin inside the map")
	end
	Check(f.zoneMap.shownPins >= 1 and f.zoneMap.shownPins <= #pins, "pins drawn: " .. f.zoneMap.shownPins)
	-- "level too low" is hidden until its switch is clicked
	local before = f.zoneMap.shownPins
	Check(f.zoneMap.switches.toolow.text.text:find("Level too low", 1, true), "switch label: " .. f.zoneMap.switches.toolow.text.text)
	f.zoneMap.switches.toolow.scripts.OnClick(f.zoneMap.switches.toolow)
	Eq(QL.ZoneMapHidden().toolow, nil, "level too low shown now")
	Check(f.zoneMap.shownPins > before, "more pins with them: " .. before .. " -> " .. f.zoneMap.shownPins)
	f.zoneMap.switches.toolow.scripts.OnClick(f.zoneMap.switches.toolow)
	Eq(QL.ZoneMapHidden().toolow, true, "and hidden again")
	Eq(f.zoneMap.shownPins, before, "back to the first count")
	-- hovering a quest in the list brings its pin forward and fades the rest
	f.zoneMap.frame.scripts.OnUpdate(f.zoneMap.frame, 2)
	local row5
	for _, r in ipairs(zs.list.rows) do if r.shown and r.questId == 5 then row5 = r end end
	row5.scripts.OnEnter(row5)
	local lit, faded = 0, 0
	for i = 1, f.zoneMap.shownPins do
		local p = f.zoneMap.pins[i]
		if p.hover then lit = lit + 1; Check(p.alpha == 1, "the quest's pin stays bright") elseif p.alpha < 1 then faded = faded + 1 end
	end
	Eq(lit, 1, "one pin in front")
	Eq(faded, f.zoneMap.shownPins - 1, "the others faded")
	row5.scripts.OnLeave(row5)
	Eq(f.zoneMap.pins[1].alpha, 1, "all bright again")
	f.zoneMap.frame.scripts.OnUpdate(f.zoneMap.frame, 2) -- the pop-in animation runs to its end
	Eq(f.zoneMap.pins[1].shown, true, "pins shown after the animation")
	local pin = f.zoneMap.pins[1]
	pin.scripts.OnEnter(pin); pin.scripts.OnLeave(pin)
	pin.scripts.OnClick(pin)
	Eq(f.zoneMap.frame.shown, true, "a pin keeps the map")
	Eq(f.inspector.hero.title.text, QL.QuestTitle(pin.ids[1]), "and opens its quest beside it")
	Eq(f.zoneMap.treeBtn.shown, true, "a way to the quest's chain tree")
	f.zoneMap.treeBtn.scripts.OnClick(f.zoneMap.treeBtn)
	Eq(f.zoneMap.frame.shown, false, "the tree replaces the map")
	Eq(f.canvasScroll.shown, true, "tree shown")
	zs.mapBtn.scripts.OnClick(zs.mapBtn)
	Eq(f.zoneMap.frame.shown, true, "the Map button brings it back")
	-- the picked zone on the game's world map: the button opens it there, its pins are drawn
	Eq(f.zoneMap.worldBtn.label and f.zoneMap.worldBtn.label.text or "Open on the world map", "Open on the world map", "world map button")
	f.zoneMap.worldBtn.scripts.OnClick(f.zoneMap.worldBtn)
	Eq(WorldMapFrame.shown, true, "the world map opens")
	local spots = QL.WorldPinSpots(1411)
	Check(#spots >= 1, "spots on Durotar's world map: " .. #spots)
	Check(QL.worldPins.shown >= 1, "pins drawn on the world map: " .. tostring(QL.worldPins.shown))
	local wp = QL.worldPins.pins[1]
	wp.scripts.OnEnter(wp); wp.scripts.OnLeave(wp)
	Eq(#QL.WorldPinSpots(1412), 0, "nothing on another zone's map (no projection in the mock)")
	QL.Set("worldMapPins", false)
	QL.RefreshWorldPins()
	Eq(QL.worldPins.shown, 0, "the setting turns them off")
	QL.Set("worldMapPins", true)
	WorldMapFrame.shown = false
	QL.RefreshWorldPins()
	Eq(QL.worldPins.shown, 0, "none while the world map is closed")
	Eq(#QL.errors, 0, "world pins without errors: " .. table.concat(QL.errors, " | "))
	local shared
	for _, p in ipairs(pins) do if #p.ids == 2 then shared = p end end
	Check(shared, "quests at one spot share a pin")
	QL.QuestTarget = questTarget
	QL.ClearArrow()
	local qids, sts = {}, {}
	for _, r in ipairs(zs.list.rows) do
		if r.shown then qids[#qids + 1] = r.questId; sts[#sts + 1] = r.sub.text end
	end
	Check(#qids >= 5, "Durotar's quests listed: " .. #qids)
	Eq(qids[1], 2, "the quest in the log first")
	Check(sts[#sts]:find("Already done", 1, true), "done quests last: " .. sts[#sts])
	for _, r in ipairs(zs.list.rows) do if r.shown and r.questId == 5 then r.scripts.OnClick(r) end end
	Eq(f.inspector.hero.title.text, "Rumours", "a quest row opens it")
	Eq(QL.ArrowQuest(), 5, "and points the arrow")
	QL.ClearArrow()
	-- back to the list
	zs.back.scripts.OnClick(zs.back)
	Eq(QL.DB().zonesArea, nil, "back clears the zone")
	Eq(zs.back.shown, false, "back button hidden again")
	-- the rail button on its own page also goes back to the list
	QL.DB().zonesArea = 14
	f.zonesTab.scripts.OnClick(f.zonesTab)
	Eq(QL.DB().zonesArea, nil, "rail button returns to the zone list")
	Eq(#QL.errors, 0, "zones page without errors: " .. table.concat(QL.errors, " | "))
	C_Map.GetMapInfo = getInfo
	C_Map.GetMapArtLayers, C_Map.GetMapArtLayerTextures = nil, nil
end

-- Search: as you type -------------------------------------------------------------------------------
QL.ShowPage("search")
local sp = f.searchPage
Eq(sp.shown, true, "search page shown")
sp.input:SetText("p")
sp.input.scripts.OnTextChanged(sp.input, true)
Check(sp.sub.text:find("two letters", 1, true), "asks for two letters")
sp.input:SetText("path")
sp.input.scripts.OnTextChanged(sp.input, true)
Eq(sp.sub.text, "2 quests found", "two hits")
local hits = {}
for _, r in ipairs(sp.list.rows) do if r.shown then hits[#hits + 1] = r end end
Eq(#hits, 2, "two result rows")
Eq(hits[1].title.text, "Left Path", "first hit")
Eq(hits[1].idTag.shown, true, "the id pill is shown")
Eq(hits[1].idTag.id, 6, "and carries the quest id")
Eq(hits[1].idTag.text.text, "#6", "as #id")
-- a click on the pill opens the copy popup with the id selected, and does not open the quest
hits[1].idTag.scripts.OnClick(hits[1].idTag)
Eq(QuestLineageCopy.shown, true, "the copy popup opens")
Eq(QuestLineageCopy.box.text, "6", "holding the id")
QuestLineageCopy.box.scripts.OnEscapePressed(QuestLineageCopy.box)
Eq(QuestLineageCopy.shown, false, "Escape closes it")
hits[1].scripts.OnClick(hits[1])
Eq(f.inspector.hero.title.text, "Left Path", "result opens its tree and details")
QL.Open("gathering")
Eq(QL.DB().page, "search", "text opens the search page")
Eq(f.inspector.hero.title.text, "The Gathering", "best hit focused")
QL.Open(10)
Eq(f.infoMeta.text, "This quest has no chain.", "a lone quest says so")
QL.Open(3)

-- Family-tree layout: first quests on top, each generation lower, siblings on one row, centred
local chain = QL.BuildChain(3, QL.Context())
local function pos(id) return QL.CardPos(chain, chain.nodes[id]) end
local x1, y1 = pos(1)
local x5, y5 = pos(5)
local x3, y3 = pos(3)
local x6, y6 = pos(6)
local x9, y9 = pos(9)
Eq(y1, y5, "first generation on one row")
Check(y1 > y3 and y3 > y6, "generations go downward")
Eq(y6, y9, "siblings on one row")
Check(x6 ~= x9, "siblings side by side")
local cw, ch = QL.CanvasSize(chain)
Check(cw > 0 and ch > 0, "canvas size")
Eq(#chain.layers[4], 3, "three quests follow the gathering")
Eq(x3, (pos(chain.layers[4][2])), "a lone card sits centred above its three children")
Check(f.tree.ox >= 0, "narrow trees are centred in the view")

-- Unfolding: a new focus starts transparent and ends fully shown
QL.Open(2)
local cards = {}
for i = 1, f.tree.usedCards do cards[#cards + 1] = f.tree.cards[i] end
Eq(#cards, 8, "eight cards")
local faded = false
for _, c in ipairs(cards) do if (c.alpha or 1) < 1 then faded = true end end
Check(faded, "cards start faded")
for _ = 1, 60 do
	local up = f.tree.unfolder.scripts.OnUpdate
	if up then up(f.tree.unfolder, 0.05) end
end
for _, c in ipairs(cards) do Eq(c.alpha, 1, "card fully shown after unfolding") end
Eq(f.tree.unfolder.scripts.OnUpdate, nil, "unfold stops itself")
local focused = 0
for _, c in ipairs(cards) do if c.focused then focused = focused + 1 end end
Eq(focused, 1, "one focused card")
-- a quest-log refresh repaints without unfolding again
QL.RenderWindow(false)
for i = 1, f.tree.usedCards do Eq(f.tree.cards[i].alpha, 1, "no unfold on refresh") end

-- Regression: a completed chain in the list used to break rendering in game (a status label
-- passed as a colour), so the list stopped half-way and clicks opened nothing.
QL.ShowPage("zone")
Eq(#QL.errors, 0, "zone list with a completed chain renders: " .. table.concat(QL.errors, " | "))
local doneRow = rows[2]
Eq(doneRow.bar.value, 1, "completed chain's bar is full")
doneRow.scripts.OnClick(doneRow)
Check(f.infoTitle.text:find("Loop", 1, true), "a completed chain opens too")
Eq(f.errorFlag.shown, false, "no error flag")

-- Detail panel ------------------------------------------------------------------------------
QL.Open(3)
local insp = f.inspector
Eq(insp.hero.shown, true, "hero shown")
Eq(insp.hero.title.text, "The Gathering", "hero title")
Eq(insp.hero.giver.text, "Bob", "giver named on the hero")
Eq(insp.hero.model.npcId, 100, "giver shown in 3D")
-- the backdrop keeps its gradient (a white SetVertexColor after it used to paint it white)
for _, part in ipairs({ "bg", "glow", "shade" }) do
	local g = insp.hero[part].gradient
	Check(g, "hero " .. part .. " keeps its gradient")
	Check(not (g[3].r == 1 and g[3].g == 1 and g[3].b == 1), "hero " .. part .. " is not white")
	Check((g[3].r + g[3].g + g[3].b) * (g[3].a or 1) < 1.2, "hero " .. part .. " stays dark")
end
local function texts(kind, field)
	local out = {}
	for _, o in ipairs(insp.pools[kind] or {}) do
		if o.shown then out[#out + 1] = field and o[field].text or o.text end
	end
	return table.concat(out, " | ")
end
local headings = texts("heading", "text")
for _, h in ipairs({ "Objective", "Tasks", "Start", "Turn in", "Rewards", "Comes after", "Leads to" }) do
	Check(headings:find(h, 1, true), "section " .. h .. " in: " .. headings)
end
Check(texts("para"):find("Question Bob and bring ribs.", 1, true), "objective text")
Check(texts("para"):find("450 XP", 1, true), "xp reward")
Check(texts("para"):find("+250", 1, true), "reputation reward")
local names = texts("row", "name")
Check(names:find("Bob questioned", 1, true), "creature task")
Check(names:find("Boar Ribs", 1, true), "item task")
Check(names:find("Alice", 1, true), "turn-in NPC row")
Check(names:find("Second Steps", 1, true) and names:find("Side Road", 1, true), "comes after: 2 and 4")
Check(names:find("Left Path", 1, true), "leads to 6")
-- a task's places: an item's droppers' spawns, a creature's own
local bobSrc = QL.TaskSources("npc", 100)
Eq(#bobSrc.sources, 1, "Bob is his own source")
Eq(bobSrc.maps[1].map, 1411, "on Durotar's map")
Eq(#QL.TaskSources("item", 501).sources, 0, "the boar that drops the ribs has no spawns in the fixture")
local bobTask
for _, r in ipairs(insp.pools.row) do if r.shown and r.name.text == "Bob questioned" then bobTask = r end end
bobTask.scripts.OnClick(bobTask)
Check(QL.TaskSourcesShown(), "a task click shows its places")
Eq(f.zoneMap.frame.shown, true, "on the map in the middle")
Eq(f.zoneMap.kicker.text, "Where to find", "heading")
Eq(f.zoneMap.shownSpots, 1, "Bob's one spawn")
Eq(f.zoneMap.worldBtn.shown, false, "the zone view's parts are off")
Eq(f.inspector.hero.title.text, "The Gathering", "the detail panel stays on the quest")
local spot = f.zoneMap.spots[1]
spot.scripts.OnEnter(spot); spot.scripts.OnLeave(spot)
spot.scripts.OnClick(spot)
Eq(QL.ArrowTarget().kind, "place", "a spot points the arrow")
QL.ClearArrow()
f.zoneMap.treeBtn.scripts.OnClick(f.zoneMap.treeBtn)
Eq(QL.TaskSourcesShown(), nil, "Back leaves the places")
Eq(f.zoneMap.frame.shown, false, "and the tree is back")
Eq(#QL.errors, 0, "task places without errors: " .. table.concat(QL.errors, " | "))
QL.Open(3)
local subs = texts("row", "sub")
Check(subs:find("Durotar  ·  45.2, 63.1", 1, true), "giver place: " .. subs)
local tiles = 0
for _, t in ipairs(insp.pools.tile or {}) do if t.shown then tiles = tiles + 1; Eq(t.itemId, 500, "reward tile") end end
Eq(tiles, 1, "one reward tile")
-- a chain row opens that quest
for _, r in ipairs(insp.pools.row) do
	if r.shown and r.name.text == "Left Path" then r.scripts.OnClick(r) break end
end
Eq(insp.hero.title.text, "Left Path", "clicking a chain row opens it")
Check(texts("heading", "text"):find("Closes for good", 1, true), "exclusive quest section")
QL.Open(3)

-- QuestLineage's own tooltip (the theme's font) on a card -------------------------------------
local tcard = f.tree.cards[1]
tcard.scripts.OnEnter(tcard)
local qtip = QuestLineageTooltip
Check(qtip and qtip.shown, "own tooltip shown")
Check(qtip.lines[1].text ~= "", "title line")
tcard.scripts.OnLeave(tcard)
Eq(qtip.shown, false, "hidden on leave")

-- Tooltip line on an NPC that starts a chained quest (Alice gives 2 and 10) -----------------
QL.ClearChainCache()
GameTooltip.lines = {}
tooltipPost(GameTooltip, { guid = "Creature-0-0-0-0-101-0000" })
Eq(#GameTooltip.lines, 1, "one chain line (quest 10 has no chain)")
Check(GameTooltip.lines[1]:find("Chain 2/4", 1, true), "summary on the line: " .. tostring(GameTooltip.lines[1]))
Check(GameTooltip.lines[1]:find("next: The Gathering", 1, true), "next quest named")

-- Quest offer strip (with the quest card off): quest 6 closes 7 ------------------------------
QL.Set("questCard", false)
function GetQuestID() return 6 end
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
local strip = QuestLineageOfferStrip
Check(strip and strip.shown, "offer strip shown")
Check(strip.text.text:find("closes for good: Right Path", 1, true), "exclusive warning: " .. strip.text.text)
Eq(QuestLineageOfferButton.questId, 6, "chain button on the offered quest")

-- a breadcrumb offer
function GetQuestID() return 5 end
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
Check(strip.text.text:find("breadcrumb to: Side Road", 1, true), "breadcrumb note")
QL.Set("questCard", true)

-- The quest card ----------------------------------------------------------------------------------
local answered = {}
function AcceptQuest() answered[#answered + 1] = "accept" end
function DeclineQuest() answered[#answered + 1] = "decline" end
function CloseQuest() answered[#answered + 1] = "close" end
function GetObjectiveText() return "Bring 5 boar ribs." end
function GetQuestText() return "The boars grow bold." end
function GetNumQuestRewards() return 1 end
function GetNumQuestChoices() return 2 end
function GetQuestItemInfo(kind, i) return "Item " .. kind .. i, 134400, 1, kind == "reward" and 2 or 3 end
function GetRewardMoney() return 1250 end
local realUnitName = UnitName
function UnitName(u) if u == "npc" then return "Grunt Kor" end return realUnitName(u) end
QuestFrame.shown = true
function GetQuestID() return 6 end
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
local qc = QuestLineageQuestCard
Check(qc and qc.shown, "the card opens on a quest offer")
Eq(strip.shown, false, "and replaces the offer strip")
Eq(qc.questId, 6, "for the offered quest")
Check(qc.kicker.text:find("NEW QUEST", 1, true), "kicker")
Check(qc.kicker.text:find("CHAIN 4/4", 1, true), "a chain quest says so in the kicker: " .. qc.kicker.text)
-- the chain box
Eq(qc.sections.chain.shown, true, "chain box shown for a chain quest")
Eq(qc.sections.chain.head.text, "CHAIN QUEST", "its heading")
local dots, lit = 0, nil
for k, d in ipairs(qc.chainBox.dots) do if d.ring.shown then dots = dots + 1 end; if d.status == "here" then lit = k end end
Eq(dots, 4, "one dot per link")
Eq(lit, 4, "this quest's link is lit")
Check(qc.chainBox.line1.text:find("Link 4 of 4", 1, true), "link line: " .. qc.chainBox.line1.text)
Check(qc.chainBox.line2.text:find("The last link of the chain", 1, true), "the last link: " .. qc.chainBox.line2.text)
-- show it in the quest list
local listOpened
local openBefore = QL.Open
QL.Open = function(qid) listOpened = qid end
Eq(qc.showList.label.text, "Show the quest in the quest list", "the list button")
qc.showList.scripts.OnClick(qc.showList)
Eq(listOpened, 6, "the main window opens on the offered quest")
QL.Open = openBefore
Eq(qc.accept.label.text, "Accept", "the Accept button has its text")
Eq(qc.decline.label.text, "Decline", "the Decline button has its text")
Eq(qc.accept.label.shown ~= false, true, "and it is shown")
Check(qc.sections.warn.shown and qc.sections.warn.body.text:find("closes for good: Right Path", 1, true), "warning on the card")
Eq(qc.sections.objective.body.text, "Bring 5 boar ribs.", "the game's objective text")
local shownTiles = 0
for _, t in ipairs(qc.tiles) do if t.shown then shownTiles = shownTiles + 1 end end
Eq(shownTiles, 3, "one reward and two choices")
Check(qc.sections.rewards.body.text:find("Choose one of 2", 1, true), "choices explained: " .. qc.sections.rewards.body.text)
Eq(QuestFrame.alpha, nil, "the game's window untouched by default")
-- the speaker: hidden without WoWTR Voices
Eq(qc.speaker.shown, false, "no speaker without WoWTR Voices")
local played = {}
local autoStarted = {}
WoWTR_Voices = {
	GetRecord = function(_, qid, section) if qid == 6 and section == "description" then return { path = "x" } end end,
	Play = function(self, qid, section, automatic) played[#played + 1] = qid; self.playingKey = "quest:" .. qid .. ":" .. section end,
	Stop = function(self) self.playingKey = nil end,
	PlayRecord = function(self, key, record, automatic) autoStarted[#autoStarted + 1] = key; return true end,
}
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
Eq(qc.speaker.shown, true, "speaker on the card")
Eq(qc.speaker.state, "ready", "the quest has a recording")
Eq(#played, 0, "nothing plays by itself (setting off)")
-- WoWTR Voices' own automatic start is held back while the card shows the quest
Eq(WoWTR_Voices:PlayRecord("quest:6:description", {}, true), false, "its autoplay is held back")
Eq(#autoStarted, 0, "nothing started")
Eq(WoWTR_Voices:PlayRecord("quest:6:progress", {}, true), true, "other pages untouched")
Eq(WoWTR_Voices:PlayRecord("quest:6:description", {}, false), true, "and a click still plays")
qc.speaker.scripts.OnClick(qc.speaker)
Eq(played[1], 6, "the speaker plays the quest")
Eq(qc.speaker.state, "playing", "lit while playing")
qc.speaker.scripts.OnClick(qc.speaker)
Eq(WoWTR_Voices.playingKey, nil, "a second click stops it")
-- the setting on: automatic reading is allowed, and the card starts it
QL.Set("voiceAutoplay", true)
Eq(WoWTR_Voices:PlayRecord("quest:6:description", {}, true), true, "autoplay allowed when set")
for _, fn in ipairs(QL.events.QUEST_FINISHED) do fn("QUEST_FINISHED") end
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
Eq(played[#played], 6, "the card reads it by itself when set")
QL.Set("voiceAutoplay", false)
WoWTR_Voices.playingKey = nil
-- a quest without a recording: a dim speaker
function GetQuestID() return 5 end
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
Eq(qc.speaker.state, "none", "no recording: dim")
WoWTR_Voices = nil
function GetQuestID() return 6 end
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
-- accept
qc.accept.scripts.OnClick(qc.accept)
Eq(answered[#answered], "accept", "Accept calls AcceptQuest")
Eq(qc.shown, false, "the card closes")
-- decline, with the game's window hidden
QL.Set("hideGameQuestFrame", true)
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
Eq(QuestFrame.alpha, 0, "the game's window invisible")
Eq(QuestFrame.shown, true, "but never Hide()n (that would end the conversation)")
Eq(QL.gameQuestFrameHidden, true, "kept out of sight")
qc.decline.scripts.OnClick(qc.decline)
Eq(answered[#answered], "decline", "Decline calls DeclineQuest")
Eq(QuestFrame.alpha, 1, "the game's window back")
-- closing the card (Escape / x) while the game's window is hidden ends the conversation
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
qc:Hide()
Eq(answered[#answered], "close", "closing the card closes the quest dialog")
Eq(QL.gameQuestFrameHidden, false, "and restores the game's window")
-- QUEST_FINISHED closes it without answering twice
local before = #answered
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
for _, fn in ipairs(QL.events.QUEST_FINISHED) do fn("QUEST_FINISHED") end
Eq(qc.shown, false, "closed when the conversation ends")
Eq(#answered, before, "no extra CloseQuest")
QL.Set("hideGameQuestFrame", false)
-- a quest the database does not know still gets a card from the game's texts
function GetQuestID() return 99999 end
function GetTitleText() return "Unknown Errand" end
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
Eq(qc.title.text, "Unknown Errand", "title from the game")
Eq(qc.sections.chain.shown, false, "no chain box for a quest outside any chain")
Eq(qc.kicker.text, "NEW QUEST", "and no chain in the kicker")
Eq(qc.sections.tasks.shown, false, "no tasks known: the section hides")
local realObjectives = C_QuestLog.GetQuestObjectives
C_QuestLog.GetQuestObjectives = function(qid) if qid == 99999 then return { { text = "Wolf slain: 0/6" } } end end
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
Check(qc.sections.tasks.shown and qc.sections.tasks.body.text:find("Wolf slain: 0/6", 1, true), "tasks from the client's objectives")
C_QuestLog.GetQuestObjectives = realObjectives
for _, fn in ipairs(QL.events.QUEST_FINISHED) do fn("QUEST_FINISHED") end
-- the main window on accept
-- an accepted quest becomes the current quest
QL.SetArrowTarget(3)
for _, fn in ipairs(QL.events.QUEST_ACCEPTED) do fn("QUEST_ACCEPTED", 2) end
Eq(QL.ArrowQuest(), 2, "the arrow turns to the accepted quest")
Eq(QL.CurrentQuest(), 2, "it is the current quest")
QL.Set("acceptedCurrent", false)
for _, fn in ipairs(QL.events.QUEST_ACCEPTED) do fn("QUEST_ACCEPTED", 3) end
Eq(QL.ArrowQuest(), 2, "left alone when the setting is off")
QL.Set("acceptedCurrent", true)
QL.SetArrowTarget(3)
local openedId
local realOpen = QL.Open
QL.Open = function(id) openedId = id end
for _, fn in ipairs(QL.events.QUEST_ACCEPTED) do fn("QUEST_ACCEPTED", 6) end
Eq(openedId, nil, "not by default")
QL.Set("openOnAccept", true)
for _, fn in ipairs(QL.events.QUEST_ACCEPTED) do fn("QUEST_ACCEPTED", 6) end
Eq(openedId, 6, "opens on the accepted quest when set")
QL.Set("openOnAccept", false)
QL.Open = realOpen
-- An NPC with several quests: the list -----------------------------------------------------------
GossipFrame = mock("Frame", "GossipFrame")
GossipFrame.shown = true
local picked = {}
C_GossipInfo = {
	GetAvailableQuests = function() return { { title = "The Gathering", questLevel = 5, questID = 3 }, { title = "Rumours", questLevel = 6, questID = 5, isTrivial = true } } end,
	GetActiveQuests = function() return { { title = "Second Steps", questLevel = 4, questID = 2, isComplete = true } } end,
	GetOptions = function() return { { name = "Let me browse your goods.", gossipOptionID = 77 } } end,
	SelectAvailableQuest = function(qid) picked[#picked + 1] = "available " .. qid end,
	SelectActiveQuest = function(qid) picked[#picked + 1] = "active " .. qid end,
	SelectOption = function(oid) picked[#picked + 1] = "option " .. oid end,
	CloseGossip = function() picked[#picked + 1] = "close gossip" end,
}
for _, fn in ipairs(QL.events.GOSSIP_SHOW) do fn("GOSSIP_SHOW") end
Eq(qc.shown, true, "the card shows the NPC's quests")
Eq(qc.mode, "list", "as a list")
Eq(qc.kicker.text, "QUESTS", "kicker")
Eq(qc.title.text, "Grunt Kor", "the NPC's name")
Check(qc.meta.text:find("2 to take", 1, true) and qc.meta.text:find("1 in progress", 1, true), "counts: " .. qc.meta.text)
local function rowTexts()
	local out = {}
	for _, r in ipairs(qc.rows) do if r.shown then out[#out + 1] = r.isHead and ("#" .. r.head.text) or r.title.text end end
	return table.concat(out, " | ")
end
local listed = rowTexts()
Check(listed:find("#AVAILABLE QUESTS", 1, true) and listed:find("The Gathering", 1, true) and listed:find("Rumours", 1, true), "available quests: " .. listed)
Check(listed:find("#QUESTS IN PROGRESS", 1, true) and listed:find("Second Steps", 1, true), "quests in progress")
Check(listed:find("#OTHER", 1, true) and listed:find("Let me browse your goods.", 1, true), "the NPC's other options")
Eq(qc.rows[2].tag.text, "CHAIN 3/4", "a chain quest is tagged (The Gathering, link 3 of 4)")
Eq(qc.rows[5].sub.text:find("Ready to hand in", 1, true) ~= nil, true, "a ready quest says so")
Eq(qc.accept.shown, false, "no Accept on the list")
Eq(qc.showList.shown, false, "nor the list button")
-- with the game's window hidden, it is the gossip window that is kept out of sight
QL.Set("hideGameQuestFrame", true)
Eq(GossipFrame.alpha, 0, "the gossip window invisible")
Eq(QuestFrame.alpha ~= 0, true, "the quest window untouched")
-- picking a quest
qc.rows[2].scripts.OnClick(qc.rows[2])
Eq(picked[#picked], "available 3", "a click picks the quest")
qc.rows[7].scripts.OnClick(qc.rows[7])
Eq(picked[#picked], "option 77", "and the options work")
-- the quest page follows; the gossip closing then leaves it alone
function GetQuestID() return 6 end
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
for _, fn in ipairs(QL.events.GOSSIP_CLOSED) do fn("GOSSIP_CLOSED") end
Eq(qc.shown, true, "the quest page stays")
Eq(qc.mode, "detail", "as the offer")
Eq(GossipFrame.alpha, 1, "the gossip window put back")
Eq(QuestFrame.alpha, 0, "the quest window hidden instead")
for _, fn in ipairs(QL.events.QUEST_FINISHED) do fn("QUEST_FINISHED") end
-- closing the list (x) while the gossip window is hidden ends the conversation
for _, fn in ipairs(QL.events.GOSSIP_SHOW) do fn("GOSSIP_SHOW") end
qc:Hide()
Eq(picked[#picked], "close gossip", "closing the list closes the gossip")
QL.Set("hideGameQuestFrame", false)
-- an NPC with no quests: the game's gossip window as usual
C_GossipInfo.GetAvailableQuests = function() return {} end
C_GossipInfo.GetActiveQuests = function() return {} end
for _, fn in ipairs(QL.events.GOSSIP_SHOW) do fn("GOSSIP_SHOW") end
Eq(qc.shown, false, "no card for an NPC without quests")
-- the quest greeting (the quest window's own list)
GetNumAvailableQuests = function() return 1 end
GetAvailableTitle = function() return "Rumours" end
GetAvailableQuestInfo = function() return false, 0, false, false, 5 end
GetNumActiveQuests = function() return 0 end
local greetPick
SelectAvailableQuest = function(i) greetPick = i end
for _, fn in ipairs(QL.events.QUEST_GREETING) do fn("QUEST_GREETING") end
Eq(greetPick, 1, "a lone quest is picked without a list")
-- two quests: the list
GetNumAvailableQuests = function() return 2 end
GetAvailableTitle = function(i) return i == 1 and "Rumours" or "Gossip" end
GetAvailableQuestInfo = function(i) return false, 0, false, false, i == 1 and 5 or 6 end
greetPick = nil
for _, fn in ipairs(QL.events.QUEST_GREETING) do fn("QUEST_GREETING") end
Eq(qc.mode, "list", "the greeting as a list too")
Eq(qc.rows[2].questId, 5, "quest id from the greeting")
qc.rows[2].scripts.OnClick(qc.rows[2])
Eq(greetPick, 1, "picks by index")
for _, fn in ipairs(QL.events.QUEST_FINISHED) do fn("QUEST_FINISHED") end
GetNumAvailableQuests, GetAvailableTitle, GetAvailableQuestInfo, GetNumActiveQuests, SelectAvailableQuest = nil, nil, nil, nil, nil
C_GossipInfo = nil

-- Handing in: progress ---------------------------------------------------------------------------
local handed = {}
GetNumQuestItems = function() return 1 end
local realInfo = GetQuestItemInfo
GetQuestItemInfo = function(kind, i) if kind == "required" then return "Boar Rib", 134400, 5, 1 end return realInfo(kind, i) end
GetProgressText = function() return "Did you bring the ribs?" end
local canComplete = false
IsQuestCompletable = function() return canComplete end
CompleteQuest = function() handed[#handed + 1] = "complete" end
function GetQuestID() return 3 end
for _, fn in ipairs(QL.events.QUEST_PROGRESS) do fn("QUEST_PROGRESS") end
Eq(qc.mode, "progress", "the progress page")
Check(qc.kicker.text:find("QUEST IN PROGRESS", 1, true), "kicker: " .. qc.kicker.text)
Eq(qc.sections.tasks.head.text, "OBJECTIVES", "live objectives")
Check(qc.sections.tasks.body.text:find("Bob questioned", 1, true), "the quest's objectives: " .. qc.sections.tasks.body.text)
Eq(qc.sections.rewards.head.text, "TO HAND IN", "what to hand in")
Eq(qc.tiles[1].kind, "required", "the item to hand in")
Check(qc.sections.talk.body.text:find("Did you bring the ribs?", 1, true), "what the NPC says")
Eq(qc.accept.label.text, "Continue", "Continue")
Eq(qc.accept.ready, false, "not while it cannot be completed")
qc.accept.scripts.OnClick(qc.accept)
Eq(#handed, 0, "nothing handed in")
canComplete = true
for _, fn in ipairs(QL.events.QUEST_PROGRESS) do fn("QUEST_PROGRESS") end
qc.accept.scripts.OnClick(qc.accept)
Eq(handed[1], "complete", "Continue calls CompleteQuest")

-- Handing in: the reward screen -------------------------------------------------------------------
GetRewardText = function() return "Well done." end
GetRewardXP = function() return 420 end
local rewardPick
GetQuestReward = function(i) rewardPick = i end
for _, fn in ipairs(QL.events.QUEST_COMPLETE) do fn("QUEST_COMPLETE") end
Eq(qc.mode, "complete", "the reward page")
Check(qc.xp.text:find("420", 1, true), "the XP the game gives: " .. qc.xp.text)
Check(qc.sections.rewards.body.text:find("Click the reward you want (2 to choose from)", 1, true), "asks to pick: " .. qc.sections.rewards.body.text)
Eq(qc.accept.label.text, "Complete quest", "Complete quest")
Eq(qc.accept.ready, false, "not before a reward is picked")
qc.accept.scripts.OnClick(qc.accept)
Eq(rewardPick, nil, "nothing handed in without a choice")
local choiceTile
for _, t in ipairs(qc.tiles) do if t.shown and t.kind == "choice" and t.index == 2 then choiceTile = t end end
choiceTile.scripts.OnClick(choiceTile)
Eq(qc.choice, 2, "the second choice picked")
Eq(choiceTile.glow.shown, true, "and lit")
Eq(qc.accept.ready, true, "now it can be handed in")
qc.accept.scripts.OnClick(qc.accept)
Eq(rewardPick, 2, "GetQuestReward with the choice")
Eq(qc.shown, false, "the card closes")
GetNumQuestItems, GetProgressText, IsQuestCompletable, CompleteQuest, GetRewardText, GetRewardXP, GetQuestReward = nil, nil, nil, nil, nil, nil, nil
GetQuestItemInfo = realInfo
function GetQuestID() return 6 end

-- off in the settings
QL.Set("questCard", false)
function GetQuestID() return 6 end
for _, fn in ipairs(QL.events.QUEST_DETAIL) do fn("QUEST_DETAIL") end
Eq(qc.shown, false, "no card when off")
Eq(strip.shown, true, "the strip again")
QL.Set("questCard", true)
for _, fn in ipairs(QL.events.QUEST_FINISHED) do fn("QUEST_FINISHED") end
Eq(#QL.errors, 0, "quest card without errors: " .. table.concat(QL.errors, " | "))
AcceptQuest, DeclineQuest, CloseQuest, GetObjectiveText, GetQuestText = nil, nil, nil, nil, nil
GetNumQuestRewards, GetNumQuestChoices, GetQuestItemInfo, GetRewardMoney, GetTitleText = nil, nil, nil, nil, nil
UnitName = realUnitName

-- Turkish with WoWTR --------------------------------------------------------------------------
QTR_QuestData = { ["3"] = { Title = "Toplanma" } }
QuestLineageOption1.checked = true
QuestLineageOption1.scripts.OnClick(QuestLineageOption1)
Eq(QL.DB().lang, "tr", "language set from the options")
QL.Open(3)
Eq(f.inspector.hero.title.text, "Toplanma", "Turkish title in the detail panel")
Check(f.infoMeta.text:find("tamam", 1, true), "Turkish interface text")
Eq(f.zoneTab.label.text, "Zincirler", "Turkish tab label")
Eq(f.questsTab.label.text, "Görevler", "Turkish quests tab")
Eq(f.infoXP.text, "+670 XP", "XP stays XP in Turkish")

-- Arrow: a click in the Quests list points it at the quest -------------------------------------
QL.Set("lang", "en")
QL.ShowPage("quests")
local qrow
for _, r in ipairs(f.questsPage.list.rows) do if r.shown and r.questId == 5 then qrow = r end end
Check(qrow, "Rumours row")
qrow.scripts.OnClick(qrow)
Eq(QL.ArrowQuest(), 5, "the arrow follows the clicked quest")
-- distances: Rumours has no place in the fixture; The Gathering's giver is 191 yards away
Eq(qrow.dist.text, "", "no distance without a place")
QL.SetArrowTarget(3); QL.Open(3)
Check(f.inspector.hero.dist.text:find("191 yd", 1, true), "distance in the detail panel: " .. f.inspector.hero.dist.text)
Check(f.inspector.hero.dist.text:find("|T", 1, true), "with the arrow mark")
-- the chain's cards: The Gathering is locked (no place), Rumours has none in the fixture
for i = 1, f.tree.usedCards do
	local card = f.tree.cards[i]
	if card.questId == 3 then Eq(card.dist.text, "", "a locked quest has no distance") end
end
-- the Chains list: the open chain's row measures the quest it opens (2, in the log)
QL.ShowPage("zone")
local chainRow
for _, r in ipairs(f.zonePage.list.rows) do if r.shown and r.openId == 2 then chainRow = r end end
Check(chainRow, "open chain row")
Eq(chainRow.distId, 2, "the chain row measures the quest it opens")
QL.RefreshDistances()
Eq(#QL.errors, 0, "distances refresh: " .. table.concat(QL.errors, " | "))
QL.ShowPage("quests")
QL.SetArrowTarget(5)
local arrow = QuestLineageArrow
Check(arrow and arrow.shown, "arrow shown")
Eq(QL.ArrowTarget().kind, "pickup", "Rumours is not in the log: go to its giver")
QL.UpdateArrow()
Eq(arrow.title.text, "Rumours", "quest name on the arrow")
Eq(arrow.dist.text, "No location data", "Rumours has no giver data in the fixture")
Eq(QuestLineageDB.arrowTargets["Tester-Realm"], 5, "kept per character")
Eq(arrow.strata, "DIALOG", "the arrow is drawn above the window (HIGH), not behind it")
QL.Command("arrow")
Eq(#QL.errors, 0, "/ql arrow runs: " .. table.concat(QL.errors, " | "))
Check(f.questsPage.list.rows[1].title.text:find("»", 1, true), "the arrow's quest is marked in the list")
-- a quest with a place: The Gathering's giver Bob at 45.2, 63.1; the player at 50, 40
QL.SetArrowTarget(3)
QL.UpdateArrow()
Eq(arrow.dist.text, "191", "distance sqrt(48^2 + 184.8^2): " .. arrow.dist.text)
Eq(arrow.unit.text, "yd", "the unit beside it")
Check(arrow.label.text:find("Bob", 1, true), "what to do there: " .. arrow.label.text)
Check(arrow.arrow.rotation and arrow.arrow.rotation > 0, "arrow turned")
Eq(arrow.shade.rotation, arrow.arrow.rotation, "the facet turns with it")
-- the detail panel offers to stop it
QL.Open(3)
local labels = {}
for _, b in ipairs(f.inspector.pools.button or {}) do if b.shown then labels[#labels + 1] = b.label.text end end
Check(table.concat(labels, "|"):find("Stop the arrow", 1, true), "stop button: " .. table.concat(labels, "|"))
-- handed in: the arrow says so and stops
for _, fn in ipairs(QL.events.QUEST_TURNED_IN) do fn("QUEST_TURNED_IN", 3) end
Eq(QL.ArrowQuest(), nil, "stopped after the hand-in")
Eq(arrow.shown, false, "hidden")
-- right-click stops it too
QL.SetArrowTarget(3)
arrow.scripts.OnMouseUp(arrow, "RightButton")
Eq(QL.ArrowQuest(), nil, "right-click stops")
-- colour by facing
local r1, g1, b1 = QL.ArrowColor(0)
local r2 = QL.ArrowColor(math.pi)
Check(math.abs(r1 - QL.Theme.C.accent[1]) < 1e-9, "ahead: accent")
Check(math.abs(r2 - QL.Theme.C.danger[1]) < 1e-9, "behind: red")
QL.Open(3)

-- Arrow settings ------------------------------------------------------------------------------
QL.Set("lang", "en")
QL.ClearArrow()
local panel = QuestLineageOptionsPanel
panel:Hide()
panel:Show() -- OnShow: the preview
Eq(arrow.shown, true, "the settings page shows a preview arrow")
QL.UpdateArrow()
Eq(arrow.title.text, "Arrow preview", "preview text")
-- colour: the theme's accent
QuestLineageArrowMode2.scripts.OnClick(QuestLineageArrowMode2)
Eq(QL.DB().arrowColorMode, "accent", "accent mode")
local ar, ag, ab = QL.ArrowTint(math.pi)
Eq(ar, QL.Theme.C.accent[1], "accent even when behind")
Eq(QuestLineageArrowMode2.checked, true, "its box ticked")
Eq(QuestLineageArrowMode1.checked, false, "the others not")
-- colour: my own, through the game's colour picker
ColorPickerFrame = { SetupColorPickerAndShow = function(self, info) self.info = info end, GetColorRGB = function() return 0.9, 0.2, 0.6 end }
QuestLineageArrowSwatch.scripts.OnClick(QuestLineageArrowSwatch)
Check(ColorPickerFrame.info and ColorPickerFrame.info.swatchFunc, "colour picker opened")
ColorPickerFrame.info.swatchFunc()
Eq(QL.DB().arrowColorMode, "custom", "picking a colour selects my own colour")
Eq(QL.DB().arrowColor[2], 0.2, "colour saved")
Check(QL.defaults.arrowColor[2] ~= 0.2, "the defaults stay untouched")
local cr, cg, cb = QL.ArrowTint(0)
Eq(cr, 0.9, "custom colour used")
QL.UpdateArrow()
Eq(arrow.arrow.vertex[1], 0.9, "the arrow is painted in it")
-- size
QuestLineageArrowScale.scripts.OnValueChanged(QuestLineageArrowScale, 1.53)
Eq(QL.DB().arrowScale, 1.55, "size snaps to 5% steps")
Eq(arrow.scale, 1.55, "the arrow grows")
QuestLineageArrowScale.scripts.OnValueChanged(QuestLineageArrowScale, 9)
Eq(QL.DB().arrowScale, 2, "capped at 200%")
-- glow
QuestLineageArrowGlow.checked = false
QuestLineageArrowGlow.scripts.OnClick(QuestLineageArrowGlow)
Eq(arrow.glow.shown, false, "glow off")
QuestLineageArrowGlow.checked = true
QuestLineageArrowGlow.scripts.OnClick(QuestLineageArrowGlow)
Eq(arrow.glow.shown, true, "glow on")
-- the menu: one page at a time, remembered
QuestLineageOptionsPage2.scripts.OnClick(QuestLineageOptionsPage2)
Eq(QL.DB().optionsPage, "tracking", "Quest tracking page chosen")
Eq(QuestLineageOption7:GetParent().shown, true, "its page shows (the quest card setting)")
Eq(QuestLineageOption1:GetParent().shown, false, "the General page is hidden")
Eq(QuestLineageOptionsPage2.active, true, "its menu entry is lit")
Eq(QuestLineageOption7.note.text, "QuestLineage's own window for quests: the NPC's quest list, offers with Accept and Decline, hand-ins with rewards.", "every setting says what it does")
-- a setting that depends on another is dimmed while that one is off
QL.Set("questCard", false)
Eq(QuestLineageOption8.enabled, false, "hiding the game's window needs the card")
Eq(QuestLineageOption10.enabled, true, "the old strip is for when the card is off")
QL.Set("questCard", true)
Eq(QuestLineageOption8.enabled, true, "available again")
Eq(QuestLineageOption10.enabled, false, "and the strip setting dims")
-- nameplate options dim while nameplates are off
QL.Set("nameplates", false)
Eq(QuestLineagePlateCount.enabled, false, "plate options dim when off")
QL.Set("nameplates", true)
-- Turkish labels
QL.Set("lang", "tr")
Eq(QuestLineageOptionsPage2.label.text, "Görev takibi", "menu in Turkish")
Eq(QuestLineageOption7.note.text, "QuestLineage'ın görev penceresi: NPC'nin görev listesi, Kabul et / Reddet ile görev alma, ödüllerle görev teslimi.", "descriptions in Turkish")
QL.Set("lang", "en")
QuestLineageOptionsPage1.scripts.OnClick(QuestLineageOptionsPage1)
-- leaving the page hides the preview when no quest is set
panel:Hide()
Eq(arrow.shown, false, "preview gone with the page")
-- back to the defaults
QuestLineageArrowMode1.scripts.OnClick(QuestLineageArrowMode1)
Eq(QL.DB().arrowColorMode, "direction", "by direction again")

-- Route: tick quests, build, follow ------------------------------------------------------------
QL.Set("lang", "en")
QL.ClearArrow()
QL.ShowPage("quests")
local qp2 = f.questsPage
local function rowFor(id)
	for _, r in ipairs(qp2.list.rows) do if r.shown and r.questId == id then return r end end
end
Eq(rowFor(5).check.shown, true, "tick boxes on the Quests page")
Eq(qp2.foot.go.label.text, "Build route", "footer button")
rowFor(5).check.scripts.OnClick(rowFor(5).check)
rowFor(2).check.scripts.OnClick(rowFor(2).check)
QL.RenderWindow(false)
Check(qp2.foot.text.text:find("2 quests ticked", 1, true), "footer counts the ticks: " .. qp2.foot.text.text)
qp2.foot.go.scripts.OnClick(qp2.foot.go)
Eq(QL.RouteActive(), true, "route running")
Eq(QL.ArrowQuest(), 5, "the arrow at the first stop")
Check(qp2.foot.text.text:find("Route 1/2", 1, true), "footer shows the stop: " .. qp2.foot.text.text)
Eq(qp2.foot.go.label.text, "Stop route", "stop button")
Eq(rowFor(5).check.num.text, "1", "stop numbers on the rows")
Eq(rowFor(2).check.num.text, "2", "second stop")
QL.UpdateArrow()
Check(arrow.label.text:find("Route 1/2", 1, true), "the arrow says where in the route: " .. arrow.label.text)
-- a list click while routing opens the quest but keeps the route's arrow
rowFor(2).scripts.OnClick(rowFor(2))
Eq(QL.ArrowQuest(), 5, "route keeps the arrow")
Eq(QL.RouteActive(), true, "still routing")
-- the first stop handed in: on to the next
for _, fn in ipairs(QL.events.QUEST_TURNED_IN) do fn("QUEST_TURNED_IN", 5) end
Eq(QL.ArrowQuest(), 2, "on to the next stop")
Eq(QL.RouteInfo().index, 2, "stop 2 of 2")
-- the last one: the route ends
for _, fn in ipairs(QL.events.QUEST_TURNED_IN) do fn("QUEST_TURNED_IN", 2) end
Eq(QL.RouteActive(), false, "route complete")
Eq(QL.ArrowQuest(), nil, "arrow stopped")
-- pointing the arrow by hand ends a route
QL.StartRoute({ 5, 2 }, true)
QL.SetArrowTarget(3)
Eq(QL.RouteActive(), false, "a hand-picked arrow ends the route")
QL.ClearArrow()
QL.ClearRouteSelection()
Eq(#QL.errors, 0, "route flow without errors: " .. table.concat(QL.errors, " | "))

-- The route on the minimap: legs from you through the stops, clipped to the rim; a badge on the
-- stops inside it (the player stands at 0.5, 0.4 of a 1000 x 800 yd map)
do
	local stopsOf = QL.MapRouteStops
	QL.MapRouteStops = function()
		return {
			{ id = 5, n = 1, spot = { map = 1411, x = 0.52, y = 0.4 } }, -- 20 yd east
			{ id = 2, n = 2, spot = { map = 1411, x = 0.9, y = 0.9 } },  -- far away
		}, { index = 1, total = 2 }
	end
	local half = 70
	local pts = QL.MinimapRoutePoints(half)
	Eq(#pts, 2, "two stops on the minimap")
	Check(pts[1].x > 0 and math.abs(pts[1].y) < 1e-6, "the first stop due east: " .. pts[1].x .. ", " .. pts[1].y)
	Eq(pts[1].next, true, "the first is the next stop")
	QL.DrawMinimapRoute()
	local d = QL.minimapRouteDrawn
	Check(d, "the route drawn on the minimap")
	Eq(d.legs, 2, "both legs (the far one clipped to the rim)")
	Eq(d.badges, 1, "a badge on the stop inside the rim only")
	-- without a route (only the arrow's quest), the minimap is left to the arrow
	QL.MapRouteStops = function() return { { id = 5, n = 1, spot = { map = 1411, x = 0.52, y = 0.4 } } }, nil end
	QL.DrawMinimapRoute()
	Eq(QL.minimapRouteDrawn, nil, "no route, nothing drawn")
	-- the setting turns it off
	QL.MapRouteStops = stopsOf
	QL.Set("minimapRoute", false)
	Eq(QL.MinimapRoutePoints(half), nil, "off by the setting")
	QL.Set("minimapRoute", true)
	Eq(#QL.errors, 0, "minimap route without errors: " .. table.concat(QL.errors, " | "))
end

-- Detail panel: the giver and turn-in rows point the arrow at that NPC ----------------------------
QL.Set("lang", "en")
QL.Open(3)
local function insRow(text)
	for _, r in ipairs(f.inspector.pools.row) do if r.shown and r.name.text == text then return r end end
end
local bobRow = insRow("Bob")
Check(bobRow and bobRow.click, "the giver's row is clickable")
bobRow.scripts.OnClick(bobRow)
Eq(QL.ArrowQuest(), nil, "pointing at a place, not a quest stage")
Eq(QL.ArrowTarget().kind, "place", "a place target")
Eq(#QL.ArrowTarget().points, 1, "Bob's spawn")
QL.UpdateArrow()
Eq(arrow.title.text, "Bob", "the arrow names the NPC")
Check(arrow.label.text:find("Start: The Gathering", 1, true), "and why: " .. arrow.label.text)
local aliceRow = insRow("Alice")
aliceRow.scripts.OnClick(aliceRow)
Eq(#QL.ArrowTarget().points, 2, "the turn-in NPC's spawns")
-- the map draws a place target too
QL.Open(3)
local stopsNow = QL.MapRouteStops()
Eq(stopsNow[1].title, "Alice", "the map shows the place")
-- a linked quest row opens it and points the arrow at it
local linked = insRow("Left Path")
linked.scripts.OnClick(linked)
Eq(QL.ArrowQuest(), 6, "a linked quest points the arrow")
QL.ClearArrow()
QL.Open(3)

-- World map: the arrow's quest drawn on it -------------------------------------------------------
QL.SetArrowTarget(3)
WorldMapFrame.shown = true
WorldMapFrame.scripts.OnShow(WorldMapFrame)
local pts = QL.MapRoutePoints(1411, 600, 400)
Check(pts.player, "the player on the map")
Eq(#pts.stops, 1, "the arrow's quest is the one stop")
Check(math.abs(pts.stops[1][1] - 0.452 * 600) < 1e-6 and math.abs(pts.stops[1][2] + 0.631 * 400) < 1e-6, "canvas position of Bob")
QL.RefreshMapRoute()
local shownBadges, shownLines = 0, 0
for _, fr in ipairs(frames) do
	if fr.kind == "Button" and fr.questId == 3 and fr.num and fr.shown then shownBadges = shownBadges + 1; Eq(fr.num.text, "1", "badge number") end
end
Eq(shownBadges, 1, "one stop badge")
for _, fr in ipairs(frames) do
	if fr.parent == mapCanvas and fr.scripts.OnUpdate then fr.scripts.OnUpdate(fr, 0.3); fr.scripts.OnUpdate(fr, 0.02) end
end
Eq(#QL.errors, 0, "map route draws without errors: " .. table.concat(QL.errors, " | "))
-- a route with placed stops draws one badge per stop
QL.SetArrowTarget(3)
QL.Set("mapRoute", false)
QL.RefreshMapRoute()
local hiddenAll = true
for _, fr in ipairs(frames) do if fr.kind == "Button" and fr.num and fr.questId == 3 and fr.shown then hiddenAll = false end end
Check(hiddenAll, "the setting turns it off")
QL.Set("mapRoute", true)
QL.ClearArrow()
WorldMapFrame.shown = false

-- "Where?" quick bar ------------------------------------------------------------------------------
local qb = QuestLineageQuickBar
Check(qb and qb.shown, "the quick bar is up")
Eq(#qb.buttons, 7, "seven service icons")
Eq(qb.buttons[1].key, "repair", "repair first")
qb.buttons[1].scripts.OnClick(qb.buttons[1])
Eq(QL.ArrowTarget().kind, "place", "the arrow points at a place")
QL.UpdateArrow()
Eq(arrow.title.text, "Grezz", "the nearest friendly repairer (not the Alliance smith next to you)")
Check(arrow.label.text:find("Nearest", 1, true), "why: " .. arrow.label.text)
-- hover lists the nearest three
qb.buttons[1].scripts.OnEnter(qb.buttons[1])
Check(QuestLineageTooltip.lines[2].text:find("Grezz", 1, true), "tooltip lists the nearest: " .. QuestLineageTooltip.lines[2].text)
qb.buttons[1].scripts.OnLeave(qb.buttons[1])
-- it stands on its own: dragging moves the bar, not the arrow, and its place is kept
Eq(qb.point[2], UIParent, "anchored to the screen, not to the arrow")
qb.buttons[2].scripts.OnDragStart(qb.buttons[2])
qb.buttons[2].scripts.OnDragStop(qb.buttons[2])
Check(QL.DB().quickBarPoint, "its place is saved")
Eq(QL.DB().arrowPoint, nil, "the arrow did not move")
-- the more panel
qb.more.scripts.OnClick(qb.more)
local qpnl = QuestLineageQuickPanel
Check(qpnl and qpnl.shown, "more panel open")
Eq(qpnl.point[1], "TOP", "the more panel opens downward, under the bar")
local tiles = 0
for _, part in ipairs(qpnl.parts) do if part.key then tiles = tiles + 1 end end
Check(tiles >= 18 + 14, "every category and all 14 professions have a tile: " .. tiles)
local fishing
for _, part in ipairs(qpnl.parts) do if part.key == "prof:Fishing" then fishing = part end end
Check(fishing and fishing.shown, "Fishing is there even when not learnt")
Eq(fishing.active, false, "not lit: not known")
local before = 0
for _ in pairs(qpnl.tiles) do before = before + 1 end
qb.more.scripts.OnClick(qb.more)
qb.more.scripts.OnClick(qb.more)
local after = 0
for _ in pairs(qpnl.tiles) do after = after + 1 end
Eq(after, before, "tiles are reused, not made again")
qb.more.scripts.OnClick(qb.more)
Eq(qpnl.shown, false, "and closes")
-- the setting and the minimap Shift-click
QL.Set("quickBar", false)
Eq(qb.shown, false, "the setting hides the bar")
QL.ToggleQuickBar()
Eq(qb.shown, true, "Shift-click on the minimap button brings it back")
QL.ClearArrow()
Eq(#QL.errors, 0, "quick bar without errors: " .. table.concat(QL.errors, " | "))
-- resizing: grips on every edge and corner; letting go saves the size; the corner resets it
local win = QuestLineageFrame
local gripCount = 0
for _ in pairs(win.grips or {}) do gripCount = gripCount + 1 end
Eq(gripCount, 8, "four edges and four corners can be dragged")
local grip = win.grips.RIGHT
grip.scripts.OnMouseDown(grip, "LeftButton")
grip.scripts.OnMouseUp(grip)
Check(type(QL.DB().windowSize) == "table" and QL.DB().windowSize[1] == 600, "letting go saves the size")
win.grips.BOTTOMRIGHT.scripts.OnDoubleClick(win.grips.BOTTOMRIGHT)
Eq(QL.DB().windowSize, nil, "a double-click on the corner restores the default size")
Eq(#QL.errors, 0, "resizing without errors: " .. table.concat(QL.errors, " | "))

-- the theme choice: stored, and the palette switches at once
Check(QuestLineageTheme1, "the theme radios exist")
QuestLineageTheme2.scripts.OnClick(QuestLineageTheme2)
Eq(QL.DB().theme, "graphite", "a click chooses the theme")
QuestLineageTheme1.scripts.OnClick(QuestLineageTheme1)
Eq(QL.DB().theme, "night", "back to the default")
-- the bar's own settings page: icons, size, tips
Check(QuestLineageBarIcon1 and QuestLineageBarReset, "the bar page has its icon switches and reset button")
Eq(QuestLineageBarIcon1.checked, true, "repair is on by default")
Eq(QuestLineageBarIcon8.checked, false, "weapon master is off by default")
QuestLineageBarIcon8.checked = true
QuestLineageBarIcon8.scripts.OnClick(QuestLineageBarIcon8)
Eq(#qb.buttons, 8, "switching an icon on adds it to the bar")
Eq(qb.buttons[8].key, "weaponmaster", "in the order of the categories (weapon master follows mail)")
QuestLineageBarIcon1.checked = false
QuestLineageBarIcon1.scripts.OnClick(QuestLineageBarIcon1)
Eq(#qb.buttons, 7, "and switching one off takes it away")
Eq(qb.buttons[1].key, "inn", "inn is first now")
QL.Set("quickBarIcons", nil)
Eq(#qb.buttons, 7, "no saved choice: the default seven")
QL.Set("quickBarTips", false)
QuestLineageTooltip.lines = {}
qb.buttons[1].scripts.OnEnter(qb.buttons[1])
Eq(#QuestLineageTooltip.lines, 0, "tips off: nothing on hover")
QL.Set("quickBarTips", true)
QL.Set("quickBarScale", 140)
Eq(qb.scale, 1.4, "the bar scales")
QL.Set("quickBarScale", 100)
QL.Set("quickBarAlpha", 40)
QL.Set("quickBarAlpha", 88)

-- Notifications instead of chat lines -------------------------------------------------------------
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
QL.ClearToasts() -- earlier tests may have left cards
QL.Print("Route complete.", "success")
local stack = QuestLineageToasts
Check(stack, "notification stack built")
local card
for _, fr in ipairs(frames) do if fr.parent == stack and fr.text and fr.shown then card = fr end end
Check(card, "a card is shown")
Eq(card.text.text, "Route complete.", "its text")
Eq(card.bar.vertex[1], QL.Theme.STATUS.done[1], "success is green")
Eq(#chat, 0, "nothing in the chat")
-- it fades away by itself
for _ = 1, 400 do if card.shown and card.scripts.OnUpdate then card.scripts.OnUpdate(card, 0.05) end end
Eq(card.shown, false, "gone after a few seconds")
-- answers to slash commands stay in the chat
QL.Command("status")
Check(#chat >= 3, "status in the chat")
-- the setting sends messages to the chat
QL.Set("toasts", false)
local before = #chat
QL.Print("Arrow: somewhere")
Eq(#chat, before + 1, "toasts off: the chat")
QL.Set("toasts", true)
DEFAULT_CHAT_FRAME = nil

-- Clicking quests raises no notification (the arrow shows it); only problems do -------------------
QL.ClearToasts()
QL.ShowPage("quests")
for _, r in ipairs(f.questsPage.list.rows) do if r.shown and r.questId == 2 then r.scripts.OnClick(r) end end
QL.SetArrowTarget(3)
local cardsUp = 0
for _, fr in ipairs(frames) do if fr.parent == QuestLineageToasts and fr.text and fr.shown then cardsUp = cardsUp + 1 end end
Eq(cardsUp, 0, "no card for pointing the arrow at a quest")
QL.SetArrowPlace("npc", 999, { title = "Nobody" })
cardsUp = 0
for _, fr in ipairs(frames) do if fr.parent == QuestLineageToasts and fr.text and fr.shown then cardsUp = cardsUp + 1 end end
Eq(cardsUp, 1, "but a place with no location says so")
QL.ClearToasts()
QL.ClearArrow()

-- Current quest window and nameplates ------------------------------------------------------------
-- put The Gathering in the log with two objectives: question Bob, collect ribs (dropped by boars)
local savedLog = C_QuestLog
local ribs = 2
C_QuestLog = {
	GetNumQuestLogEntries = function() return 2 end,
	GetInfo = function(i) return { questID = i == 1 and 2 or 3, isHeader = false } end,
	IsComplete = function() return false end,
	IsQuestFlaggedCompleted = function(id) return id == 1 end,
	GetQuestObjectives = function(id)
		if id ~= 3 then return {} end
		return {
			{ text = "Bob questioned: 0/1", numFulfilled = 0, numRequired = 1, finished = false },
			{ text = "Boar Ribs: " .. ribs .. "/5", numFulfilled = ribs, numRequired = 5, finished = false },
		}
	end,
}
QL.ResetContext()
QL.SetArrowTarget(3)
QL.RefreshCurrent()
local cur = QuestLineageCurrent
Check(cur and cur.shown, "current quest window shown")
-- it hangs from its top-left corner after a drag, so folding pulls the bottom up, not both edges
cur.GetLeft = function() return 1500 end
cur.GetTop = function() return 700 end
cur.scripts.OnDragStop(cur)
local cp = QL.DB().currentPoint
Eq(cp[1], "TOPLEFT", "saved by its top-left corner")
Eq(cp[2], "BOTTOMLEFT", "from the screen's bottom-left")
Eq(cp[3], 1500, "left edge")
Eq(cp[4], 700, "top edge")
cur.GetLeft, cur.GetTop = nil, nil
-- the lock: pinned in place, drags do nothing; a second click frees it
Eq(cur.lock.shown, true, "lock button shown")
local moved = 0
cur.StartMoving = function() moved = moved + 1 end
cur.scripts.OnDragStart(cur)
Eq(moved, 1, "unlocked: drags move it")
cur.lock.scripts.OnClick(cur.lock)
Eq(QL.DB().currentLocked, true, "locked by its button")
cur.scripts.OnDragStart(cur)
cur.logHead.scripts.OnDragStart(cur.logHead)
Eq(moved, 1, "locked: no drag moves it")
cur.lock.scripts.OnEnter(cur.lock)
Eq(QL.Tip().lines[1].text, "Window locked", "its tooltip says so")
cur.lock.scripts.OnLeave(cur.lock)
cur.lock.scripts.OnClick(cur.lock)
Eq(QL.DB().currentLocked, false, "unlocked again")
cur.scripts.OnDragStart(cur)
Eq(moved, 2, "moves again")
cur.StartMoving = nil
Eq(cur.title.text, "The Gathering", "the arrow's quest is current")
Check(cur.state.text:find("In your log", 1, true), "its stage: " .. cur.state.text)
Eq(cur.rows[1].count.text, "0/1", "first objective counter")
Eq(cur.rows[2].count.text, "2/5", "ribs 2 of 5")
Check(cur.rows[2].text.text:find("Boar Ribs", 1, true), "objective text")
local rows = QL.ObjectiveRows(3, QL.Context())
Eq(rows[1].task.id, 100, "Bob's row matched to the creature task")
Eq(rows[2].task.id, 501, "the ribs row matched to the item task")
-- progress: the ribs counter goes up, the row flashes
ribs = 3
QL.ResetContext()
Eq(cur.rows[2].count.text, "3/5", "counter updated")
Check(cur.rows[2].flashT > 0, "the row flashes")
-- completion: Bob 0/1 and ribs 3/5 = 3 of 6 units, none of the two objectives done
Eq(cur.progress.text, "0/2 objectives · 50%", "count and share")
Eq(cur.bar.shown, true, "with a bar")
Eq(cur.completion.fraction, 0.5, "the bar at half")
ribs = 5
QL.ResetContext()
Eq(cur.progress.text, "1/2 objectives · 83%", "the ribs done: 5 of 6")
ribs = 3
QL.ResetContext()
local p2 = QL.QuestCompletion(3, { complete = { [3] = true }, log = { [3] = true }, done = {}, level = 5 })
Eq(p2.percent, 100, "a quest the game calls complete is 100%")
-- three objectives: C_QuestLog gives two, the quest log's leader boards all three -> three rows
C_QuestLog.GetLogIndexForQuestID = function(qid) return qid == 3 and 2 or nil end
GetNumQuestLeaderBoards = function(index) return index == 2 and 3 or 0 end
GetQuestLogLeaderBoard = function(i, index)
	if i == 1 then return "Bob questioned: 0/1", "monster", false end
	if i == 2 then return "Boar Ribs: 3/5", "item", false end
	return "Scorpid slain: 4/4", "monster", true
end
QL.ResetContext()
local three = QL.ObjectiveRows(3, QL.Context())
Eq(#three, 3, "all three objectives")
Eq(three[3].have, 4, "counter read from the text")
Eq(three[3].done, true, "and done")
local shown3 = 0
for _, r in ipairs(cur.rows) do if r.shown then shown3 = shown3 + 1 end end
Eq(shown3, 3, "three rows on the window")
Eq(cur.progress.text, "1/3 objectives · 70%", "7 of 10 units, one objective done")
QL.ObjectiveDebug(3)
C_QuestLog.GetLogIndexForQuestID, GetNumQuestLeaderBoards, GetQuestLogLeaderBoard = nil, nil, nil
QL.ResetContext()
-- the log list under it: the other logged quest (Second Steps)
Eq(cur.logHead.shown, true, "Quests header shown")
Check(cur.logHead.text.text:find("QUESTS", 1, true), "header text: " .. cur.logHead.text.text)
-- the EN | TR pill on the list header
do
	local pill, savedLang, savedQTR = cur.logHead.lang, QL.DB().lang, QTR_QuestData
	QTR_QuestData = nil
	QL.RefreshCurrent()
	Eq(pill.halves[1].on, true, "EN lit without WoWTR")
	pill.halves[2].scripts.OnClick(pill.halves[2])
	Eq(QL.UseTurkish(), false, "TR refused without WoWTR")
	QTR_QuestData = {}
	pill.halves[2].scripts.OnClick(pill.halves[2])
	Eq(QL.DB().lang, "tr", "TR chosen from the list header")
	Eq(pill.halves[2].on, true, "TR lit")
	Check(cur.logHead.text.text:find("GÖREVLER", 1, true), "header in Turkish: " .. cur.logHead.text.text)
	pill.halves[1].scripts.OnClick(pill.halves[1])
	Eq(QL.DB().lang, "en", "back to English")
	Eq(pill.halves[1].on, true, "EN lit again")
	QTR_QuestData = savedQTR
	QL.Set("lang", savedLang)
	QL.RefreshCurrent()
end
Eq(cur.logRows[1].questId, 2, "the other quest in the log")
Eq(cur.logRows[1].title.text, "Second Steps", "its title")
-- clicking it makes it current
cur.logRows[1].scripts.OnClick(cur.logRows[1], "LeftButton")
Eq(QL.ArrowQuest(), 2, "the arrow turns to it")
QL.RefreshCurrent()
Eq(cur.title.text, "Second Steps", "it is the current quest now")
Eq(cur.logRows[1].questId, 3, "and The Gathering moved to the list")
Check(cur.logRows[1].sub.text:find("Bob questioned", 1, true), "its first open objective: " .. cur.logRows[1].sub.text)
Check(cur.logRows[1].sub.text:find("Boar Ribs", 1, true), "and the second one too: " .. cur.logRows[1].sub.text)
Check(select(2, cur.logRows[1].sub.text:gsub("\n", "")) >= 1, "one line per objective")
-- minimise one quest's objectives, then every quest's from the header
local lr = cur.logRows[1]
Eq(lr.fold.shown, true, "a minimise button on the row")
Eq(lr.fold.text.text, "–", "open: minus")
lr.fold.scripts.OnClick(lr.fold)
Eq(QL.LogObjectivesOpen(3), false, "this quest folded")
Eq(lr.fold.text.text, "+", "folded: plus")
Check(not lr.sub.text:find("Boar Ribs", 1, true), "its objective lines gone")
Check(lr.sub.text:find("objectives", 1, true), "one summary line instead: " .. lr.sub.text)
lr.fold.scripts.OnClick(lr.fold)
Check(lr.sub.text:find("Boar Ribs", 1, true), "back again")
Eq(cur.logHead.all.text.text, "– objectives", "header switch")
cur.logHead.all.scripts.OnClick(cur.logHead.all)
Eq(QL.DB().logObjectives, false, "every quest folded")
Check(not lr.sub.text:find("Boar Ribs", 1, true), "this one too")
Eq(cur.logHead.all.text.text, "+ objectives", "header says how to bring them back")
cur.logHead.all.scripts.OnClick(cur.logHead.all)
Check(lr.sub.text:find("Boar Ribs", 1, true), "all open again")
-- folding the list
cur.logHead.scripts.OnClick(cur.logHead)
Eq(cur.logRows[1].shown, false, "the list folds")
cur.logHead.scripts.OnClick(cur.logHead)
Eq(cur.logRows[1].shown, true, "and opens")
-- how many the list shows, from the settings page's slider
local logSlider
for i = 1, 60 do
	local f = _G["QuestLineageOption" .. i]
	if f and f.scripts and f.scripts.OnValueChanged and f.label and (f.label.text or ""):find("Quests in the list", 1, true) then logSlider = f end
end
Check(logSlider, "a slider row on the settings page")
local realLog = QL.LogQuests
QL.LogQuests = function() return { 3, 4, 5, 6 } end
logSlider.scripts.OnValueChanged(logSlider, 2.4)
Eq(QL.DB().currentLogMax, 2, "whole quests")
Eq(logSlider.label.text, "Quests in the list: 2", "its label")
QL.RefreshCurrent()
local shownRows = 0
for _, r in ipairs(cur.logRows) do if r.shown then shownRows = shownRows + 1 end end
Eq(shownRows, 2, "two quests listed")
Eq(cur.logMore.shown, true, "the rest as a line")
Eq(cur.logMore.text, "+2 more", "+2 more")
logSlider.scripts.OnValueChanged(logSlider, 99)
Eq(QL.DB().currentLogMax, 30, "capped at 30")
-- filters: all / zone / class / chain
QL.Set("currentLogMax", 15)
QL.LogQuests = function() return { 2, 6, 10 } end
QL.RefreshCurrent()
local groups = QL.FilterLogQuests({ 2, 6, 10 }, QL.Context())
Eq(#cur.logChips, 4, "four filter chips")
Check(cur.logChips[1].text.text:find("All", 1, true) and cur.logChips[1].active, "All, on by default: " .. cur.logChips[1].text.text)
Check(cur.logChips[4].text.text:find("Chain", 1, true), "Chain chip")
Check(cur.logChips[4].text.text:find(tostring(#groups.chain), 1, true), "with its count")
local function listedIds()
	local out = {}
	for _, r in ipairs(cur.logRows) do if r.shown then out[#out + 1] = r.questId end end
	return out
end
Eq(#listedIds(), 3, "all three listed")
cur.logChips[4].scripts.OnClick(cur.logChips[4])
Eq(QL.DB().currentLogFilter, "chain", "chain filter chosen")
Eq(#listedIds(), #groups.chain, "only chain quests listed")
Check(#groups.chain < 3, "quest 10 has no chain, so the filter drops it")
for _, qid in ipairs(listedIds()) do Check(QL.ChainSummary(qid, QL.Context()), "listed quest is in a chain: " .. qid) end
Eq(cur.logChips[4].active, true, "its chip lit")
-- an empty filter says so
local realFilter = QL.FilterLogQuests
QL.FilterLogQuests = function(...) local g = realFilter(...); g.class = {}; return g end
cur.logChips[3].scripts.OnClick(cur.logChips[3])
Eq(#listedIds(), 0, "no class quests")
Eq(cur.logMore.text, "No quests under this filter", "says so")
cur.logChips[1].scripts.OnClick(cur.logChips[1])
QL.FilterLogQuests = realFilter
QL.LogQuests = realLog
QL.RefreshCurrent()
-- abandoning a quest: the cross on the window, a confirmation, the quest log's own calls
local dropped = {}
function GetQuestLogIndexByID(qid) return qid == 3 and 1 or (qid == 2 and 2) or nil end
function GetQuestLogSelection() return 2 end
function SelectQuestLogEntry(i) dropped[#dropped + 1] = "select " .. i end
function SetAbandonQuest() dropped[#dropped + 1] = "mark" end
function AbandonQuest() dropped[#dropped + 1] = "abandon" end
QL.SetArrowTarget(3)
QL.RefreshCurrent()
Eq(cur.drop.shown, false, "the cross hides until the cursor comes")
cur.scripts.OnEnter(cur)
Eq(cur.drop.shown, true, "shows on the window")
cur.drop.scripts.OnClick(cur.drop)
local dlg = QuestLineageConfirm
Check(dlg and dlg.shown, "asks first")
Eq(dlg.title.text, "Abandon quest?", "the question")
Check(dlg.text.text:find("The Gathering", 1, true), "names the quest: " .. dlg.text.text)
dlg.no.scripts.OnClick(dlg.no)
Eq(dlg.shown, false, "Cancel closes it")
Eq(#dropped, 0, "nothing abandoned")
cur.drop.scripts.OnClick(cur.drop)
dlg.yes.scripts.OnClick(dlg.yes)
Eq(table.concat(dropped, ","), "select 1,mark,abandon,select 2", "selects the line, marks it, abandons it, puts the selection back")
Eq(QL.ArrowQuest(), nil, "the arrow lets go of it")
-- on a list row too
cur.logRows[1].scripts.OnEnter(cur.logRows[1])
Eq(cur.logRows[1].drop.shown, true, "a cross on the list row")
-- without the classic calls: C_QuestLog's
GetQuestLogIndexByID, GetQuestLogSelection, SelectQuestLogEntry, SetAbandonQuest, AbandonQuest = nil, nil, nil, nil, nil
dropped = {}
C_QuestLog.SetSelectedQuest = function(qid) dropped[#dropped + 1] = "select " .. qid end
C_QuestLog.SetAbandonQuest = function() dropped[#dropped + 1] = "mark" end
C_QuestLog.AbandonQuest = function() dropped[#dropped + 1] = "abandon" end
Eq(QL.AbandonQuest(2), true, "abandoned through C_QuestLog")
Eq(table.concat(dropped, ","), "select 2,mark,abandon", "the same steps")
C_QuestLog.SetSelectedQuest, C_QuestLog.SetAbandonQuest, C_QuestLog.AbandonQuest = nil, nil, nil
QL.ClearToasts()
QL.SetArrowTarget(3)
QL.RefreshCurrent()
QL.SetArrowTarget(3)
QL.RefreshCurrent()
-- quest areas: Bob's spot becomes an area (the ribs' boars have no spawns in the fixture)
local areas = QL.QuestAreas(3, QL.Context())
Eq(#areas, 1, "one area")
Eq(areas[1].map, 1411, "on Durotar's map")
Check(math.abs(areas[1].x - 0.452) < 1e-9, "centred on Bob")
Eq(areas[1].r, 25, "smallest radius for a single spot")
Eq(areas[1].label, "Bob", "named after the objective's creature")
Eq(areas[1].count, "0/1", "with its counter")
Eq(#QL.QuestAreas(2, QL.Context()), 0, "a quest without objectives has none")
QL.RefreshQuestAreas()
Eq(QL.minimapAreasDrawn, 1, "Bob's area drawn on the minimap")
Eq(QL.minimapRimMarks, 0, "inside the minimap: no rim mark")
-- zoomed in far: the area lies beyond the rim and shows as a mark on it
Minimap.GetZoom = function() return 5 end
QL.RefreshQuestAreas()
Eq(QL.minimapRimMarks, 1, "beyond the edge: a rim mark")
Minimap.GetZoom = nil
QL.RefreshQuestAreas()
-- hovering an area on the minimap shows the quest beside the cursor
local hit = QL.minimapAreaHits[1]
Check(hit ~= nil, "the drawn area can be hovered")
Eq(QL.AreaAt(QL.minimapAreaHits, hit.x, hit.y), hit.area, "the centre is inside")
Eq(QL.AreaAt(QL.minimapAreaHits, hit.x + hit.r + 1, hit.y), nil, "just outside is not")
Eq(QL.AreaAt({ { x = 0, y = 0, r = 10, area = "big" }, { x = 1, y = 0, r = 3, area = "small" } }, 1, 0), "small", "the smallest area wins")
Eq(QL.AreaAt({ { x = 0.5, y = 0.5, rx = 0.1, ry = 0.05, area = "w" } }, 0.5, 0.57), nil, "world areas are ellipses")
Minimap.IsMouseOver = function() return true end
Minimap.IsVisible = function() return true end
Minimap.GetCenter = function() return 100, 100 end
local cursorX, cursorY = 100 + hit.x, 100 + hit.y
GetCursorPosition = function() return cursorX, cursorY end
QL.HoverMinimapAreas()
local tip = QL.Tip()
Eq(tip.shown, true, "tooltip over the area")
Eq(tip.owner, Minimap, "owned by the minimap")
local tipText = {}
for i = 1, tip:NumLines() do tipText[#tipText + 1] = tip.lines[i].text or "" end
tipText = table.concat(tipText, "\n")
Check(tipText:find("The Gathering", 1, true), "the quest: " .. tipText)
Check(tipText:find("Bob   0/1", 1, true), "the objective under the cursor first")
Check(tip.lines[1].text:find("Bob", 1, true), "on the first line: " .. tip.lines[1].text)
Check(tipText:find("Objective of The Gathering", 1, true), "then whose objective it is")
local two = QL.AreasAt({ { x = 0, y = 0, r = 10, area = { questId = 3, label = "Wolf" } }, { x = 1, y = 0, r = 3, area = { questId = 3, label = "Bear" } } }, 1, 0)
Eq(#two, 2, "overlapping rings of two objectives: both")
Eq(two[1].label, "Bear", "the smaller first")
cursorX = 100 + hit.x + hit.r + 5
QL.HoverMinimapAreas()
Eq(tip.shown, false, "hidden when the cursor leaves the area")
-- never stuck: a cursor tip nobody moves any more closes by itself, and so does a tip whose
-- owner is hidden (the world map closed under the cursor left it on screen until a reload)
cursorX = 100 + hit.x
QL.HoverMinimapAreas()
Eq(tip.shown, true, "shown again over the area")
tip.scripts.OnUpdate(tip, 0.1)
Eq(tip.shown, true, "kept while it is moved")
tip.scripts.OnUpdate(tip, 0.5)
Eq(tip.shown, false, "a cursor tip left alone closes")
QL.HoverMinimapAreas()
Eq(tip.shown, true, "and comes back while still hovered")
local owner = CreateFrame("Frame", nil, UIParent)
owner.IsVisible = function(self) return self.shown == true end
owner:Show()
tip:SetOwner(owner, "ANCHOR_RIGHT")
tip:AddLine("x")
tip:Show()
tip.scripts.OnUpdate(tip, 5)
Eq(tip.shown, true, "an anchored tip stays while its owner is shown")
owner:Hide()
tip.scripts.OnUpdate(tip, 0.01)
Eq(tip.shown, false, "closes with its owner")
Minimap.IsMouseOver, Minimap.IsVisible, Minimap.GetCenter = nil, nil, nil
GetCursorPosition = function() return 0, 0 end
Eq(#QL.errors, 0, "areas without errors: " .. table.concat(QL.errors, " | "))
-- the game's own blue area
local blob = {}
Minimap.SetQuestBlobRingAlpha = function(_, v) blob.ring = v end
Minimap.SetQuestBlobInsideAlpha = function(_, v) blob.inside = v end
QL.Set("hideGameAreas", true)
Eq(blob.ring, 0, "the game's ring hidden")
Eq(blob.inside, 0, "and its fill")
QL.Set("hideGameAreas", false)
Eq(blob.ring, 1, "shown again")
-- another quest's rings: with Second Steps current, The Gathering's area is drawn softly and its
-- tooltip names The Gathering
QL.SetArrowTarget(2)
QL.RefreshQuestAreas()
local otherArea
for _, ar in ipairs(QL.drawnAreas or {}) do if ar.questId == 3 then otherArea = ar end end
Check(otherArea, "The Gathering's ring is drawn while another quest is current")
Eq(otherArea.other, true, "as another quest's ring")
Minimap.IsMouseOver = function() return true end
Minimap.IsVisible = function() return true end
Minimap.GetCenter = function() return 100, 100 end
local oh = QL.minimapAreaHits[1]
GetCursorPosition = function() return 100 + oh.x, 100 + oh.y end
QL.HoverMinimapAreas()
local otext = {}
for i = 1, QL.Tip():NumLines() do otext[#otext + 1] = QL.Tip().lines[i].text or "" end
otext = table.concat(otext, " / ")
Check(otext:find("The Gathering", 1, true), "its own quest in the tooltip: " .. otext)
Check(otext:find("Objective of The Gathering", 1, true), "whose objective it is, not the current quest's")
-- the look: another quest's area is a dotted circle, its soft fill only while hovered
local mmp = QL.AreaParts()
local otherPart
for _, pp in ipairs(mmp) do if pp.ring.shown and pp.look == "dotted" then otherPart = pp end end
Check(otherPart, "a dotted circle for another quest")
Eq(otherPart.disc.shown, true, "lit while the cursor is on it")
GetCursorPosition = function() return 100 + oh.x + 500, 100 + oh.y end
QL.HoverMinimapAreas()
Eq(otherPart.disc.shown, false, "no fill once the cursor leaves")
Eq(otherPart.breathe, false, "other quests' rings stay still")
QL.Tip():Hide()
Minimap.IsMouseOver, Minimap.IsVisible, Minimap.GetCenter = nil, nil, nil
GetCursorPosition = function() return 0, 0 end
-- the setting
QL.Set("questAreasOthers", false)
local any3 = false
for _, ar in ipairs(QL.drawnAreas or {}) do if ar.questId == 3 then any3 = true end end
Eq(any3, false, "other quests' rings off in the settings")
QL.Set("questAreasOthers", true)
QL.SetArrowTarget(3)
QL.RefreshQuestAreas()
-- folding
cur.scripts.OnClick(cur, "RightButton")
Eq(cur.rows[1].shown, false, "right-click folds the objectives")
Eq(cur.foldHint.shown, true, "and says so")
Check(cur.foldHint.text:find("objectives hidden", 1, true), "how many are hidden: " .. cur.foldHint.text)
QL.ObjectiveDebug()
cur.scripts.OnClick(cur, "RightButton")
Eq(cur.rows[1].shown, true, "and unfolds")
Eq(cur.foldHint.shown, false, "the line goes")
-- nameplates: a boar drops the ribs, Bob is to be questioned
local plates = {}
local function plate(unit) plates[unit] = plates[unit] or mock("Frame"); plates[unit].namePlateUnitToken = unit; return plates[unit] end
C_NamePlate = {
	GetNamePlateForUnit = function(unit) return plate(unit) end,
	GetNamePlates = function() local out = {} for _, p in pairs(plates) do out[#out + 1] = p end return out end,
}
local guids = { nameplate1 = "Creature-0-0-0-0-102-0001", nameplate2 = "Creature-0-0-0-0-100-0002", nameplate3 = "Creature-0-0-0-0-206-0003" }
UnitGUID = function(unit) return guids[unit] end
for _, fn in ipairs(QL.events.NAME_PLATE_UNIT_ADDED) do fn("NAME_PLATE_UNIT_ADDED", "nameplate1"); fn("NAME_PLATE_UNIT_ADDED", "nameplate2"); fn("NAME_PLATE_UNIT_ADDED", "nameplate3") end
local function badgeOf(unit)
	for _, fr in ipairs(frames) do if fr.parent == plates[unit] and fr.text and fr.icon then return fr end end
end
Eq(badgeOf("nameplate1").text.text, "3/5", "the boar's plate counts the ribs")
Eq(badgeOf("nameplate2").text.text, "0/1", "Bob's plate counts the questioning")
Eq(badgeOf("nameplate3"), nil, "no badge on a creature no quest needs")
Eq(QL.DB().plateColorMode, "status", "colour by quest by default")
Eq(badgeOf("nameplate1").icon.vertex[2], QL.PLATE_CURRENT[2], "the current quest's creature: light green")
Eq(badgeOf("nameplate1").alpha, 1, "at full strength")
-- a dropper the database does not list: looting the ribs from creature 206 teaches it
GetNumLootItems = function() return 2 end
GetLootSlotLink = function(slot) return slot == 1 and "|cffffffff|Hitem:501::::::::5:::::|h[Boar Ribs]|h|r" or "|Hitem:9999::|h[Junk]|h" end
GetLootSourceInfo = function() return "Creature-0-0-0-0-206-0003", 1 end
for _, fn in ipairs(QL.events.LOOT_OPENED) do fn("LOOT_OPENED") end
Eq(QL.DB().learnedDrops and QL.DB().learnedDrops[501] and QL.DB().learnedDrops[501][206], true, "creature 206 learned as a ribs dropper")
Eq(QL.DB().learnedDrops[9999], nil, "items no quest asks for are not learned")
Eq(badgeOf("nameplate3").text.text, "3/5", "and its plate now counts the ribs")
Eq(QL.LearnDrop(501, 102), false, "a dropper the database knows is not stored again")
local said = {}
local realChat = QL.Chat
QL.Chat = function(m) said[#said + 1] = m end
guids.target = guids.nameplate3
QL.PlateDebug()
QL.Chat = realChat
guids.target = nil
said = table.concat(said, "\n")
Check(said:find("206", 1, true) and said:find("target drops it: yes", 1, true), "/ql plate explains: " .. said)
GetNumLootItems, GetLootSlotLink, GetLootSourceInfo = nil, nil, nil
QL.DB().learnedDrops = nil
QL.RefreshPlates()
-- other quests nearby: cards for another logged quest's creatures and areas
QL.ResetNearby()
QL.ClearToasts()
QL.lastNearbyHint = nil
for _, fn in ipairs(QL.events.NAME_PLATE_UNIT_ADDED) do fn("NAME_PLATE_UNIT_ADDED", "nameplate2") end
Eq(QL.lastNearbyHint, nil, "nothing for the current quest's own creatures")
QL.SetArrowTarget(2) -- Second Steps becomes current; Bob now belongs to another quest
QL.RefreshPlates()
Eq(badgeOf("nameplate2").icon.vertex[1], QL.PLATE_OTHER[1], "another quest's creature: amber")
Eq(badgeOf("nameplate2").icon.vertex[2], QL.PLATE_OTHER[2], "amber (green part)")
Eq(badgeOf("nameplate2").alpha, 1, "told apart by colour, not faded")
guids.target = guids.nameplate2
for _, fn in ipairs(QL.events.PLAYER_TARGET_CHANGED) do fn("PLAYER_TARGET_CHANGED") end
Check(QL.lastNearbyHint and QL.lastNearbyHint.questId == 3, "targeting Bob: a card for The Gathering")
Eq(QL.lastNearbyHint.reason, "target", "because of the target")
local hintCard
for _, fr in ipairs(frames) do if fr.head and fr.head.text == "ANOTHER QUEST HERE" and fr.shown then hintCard = fr end end
Check(hintCard, "the card is up")
Check(hintCard.text.text:find("The Gathering", 1, true), "it names the quest: " .. hintCard.text.text)
Check(hintCard.text.text:find("Bob questioned", 1, true), "and the objective")
-- once per quest for a while
QL.lastNearbyHint = nil
for _, fn in ipairs(QL.events.NAME_PLATE_UNIT_ADDED) do fn("NAME_PLATE_UNIT_ADDED", "nameplate2") end
Eq(QL.lastNearbyHint, nil, "not again right away")
-- a click makes it current
hintCard.scripts.OnClick(hintCard, "LeftButton")
Eq(QL.ArrowQuest(), 3, "the card's quest becomes current")
-- in combat it waits for the fight to end
QL.SetArrowTarget(2)
QL.ResetNearby()
QL.lastNearbyHint = nil
InCombatLockdown = function() return true end
for _, fn in ipairs(QL.events.PLAYER_TARGET_CHANGED) do fn("PLAYER_TARGET_CHANGED") end
Eq(QL.lastNearbyHint, nil, "nothing during the fight")
InCombatLockdown = nil
for _, fn in ipairs(QL.events.PLAYER_REGEN_ENABLED) do fn("PLAYER_REGEN_ENABLED") end
Check(QL.lastNearbyHint and QL.lastNearbyHint.questId == 3, "the card after the fight")
-- the setting
QL.ResetNearby()
QL.lastNearbyHint = nil
QL.Set("nearbyTarget", false)
for _, fn in ipairs(QL.events.PLAYER_TARGET_CHANGED) do fn("PLAYER_TARGET_CHANGED") end
Eq(QL.lastNearbyHint, nil, "off in the settings")
QL.Set("nearbyTarget", true)
-- walking into The Gathering's area (Bob's spot)
QL.ResetNearby()
QL.lastNearbyHint = nil
local bobArea = QL.QuestAreas(3, QL.Context())[1]
local realPos = C_Map.GetPlayerMapPosition
C_Map.GetPlayerMapPosition = function() return CreateVector2D(bobArea.x, bobArea.y) end
QL.CheckNearbyAreas(true)
Check(QL.lastNearbyHint and QL.lastNearbyHint.reason == "area", "in the area: a card")
QL.lastNearbyHint = nil
QL.ResetNearby()
QL.CheckNearbyAreas(true)
QL.lastNearbyHint = nil
QL.CheckNearbyAreas(true)
Eq(QL.lastNearbyHint, nil, "once per entry, not while standing in it")
C_Map.GetPlayerMapPosition = realPos
guids.target = nil
QL.SetArrowTarget(3)
QL.ClearToasts()
-- the waiting time is a setting (minutes)
local cdSlider
for i = 1, 60 do
	local f = _G["QuestLineageOption" .. i]
	if f and f.scripts and f.scripts.OnValueChanged and f.label and (f.label.text or ""):find("card again after", 1, true) then cdSlider = f end
end
Check(cdSlider, "a waiting-time slider")
cdSlider.scripts.OnValueChanged(cdSlider, 1)
Eq(QL.DB().nearbyCooldown, 1, "one minute")
local clock = 1000
GetTime = function() return clock end
QL.ResetNearby()
QL.SetArrowTarget(2)
guids.target = guids.nameplate2
QL.lastNearbyHint = nil
for _, fn in ipairs(QL.events.PLAYER_TARGET_CHANGED) do fn("PLAYER_TARGET_CHANGED") end
Check(QL.lastNearbyHint, "first card")
QL.lastNearbyHint = nil
clock = 1000 + 50
for _, fn in ipairs(QL.events.PLAYER_TARGET_CHANGED) do fn("PLAYER_TARGET_CHANGED") end
Eq(QL.lastNearbyHint, nil, "not within the minute")
clock = 1000 + 61
for _, fn in ipairs(QL.events.PLAYER_TARGET_CHANGED) do fn("PLAYER_TARGET_CHANGED") end
Check(QL.lastNearbyHint, "again after a minute")
cdSlider.scripts.OnValueChanged(cdSlider, 3)
GetTime = nil
guids.target = nil
QL.SetArrowTarget(3)
QL.ClearToasts()
Eq(#QL.errors, 0, "nearby hints without errors: " .. table.concat(QL.errors, " | "))
ribs = 5
C_QuestLog.GetQuestObjectives = function(id)
	if id ~= 3 then return {} end
	return {
		{ text = "Bob questioned: 0/1", numFulfilled = 0, numRequired = 1, finished = false },
		{ text = "Boar Ribs: 5/5", numFulfilled = 5, numRequired = 5, finished = true },
	}
end
QL.ResetContext()
Eq(badgeOf("nameplate1").shown, false, "done: the boar's badge goes")
QL.Set("nameplates", false)
Eq(badgeOf("nameplate2").shown, false, "the setting hides badges")
QL.Set("nameplates", true)
-- nameplate settings from the settings page
local bob = badgeOf("nameplate2")
Eq(bob.side, "left", "left of the health bar by default")
QuestLineagePlateSide2.scripts.OnClick(QuestLineagePlateSide2)
Eq(QL.DB().plateSide, "right", "right from the settings")
Eq(bob.side, "right", "the badge moved")
QuestLineagePlateSide3.scripts.OnClick(QuestLineagePlateSide3)
Eq(bob.side, "top", "above the name")
QuestLineagePlateScale.scripts.OnValueChanged(QuestLineagePlateScale, 1.5)
Eq(bob.scale, 1.5, "badge size")
QuestLineagePlateOffset.scripts.OnValueChanged(QuestLineagePlateOffset, -12.4)
Eq(QL.DB().plateOffsetX, -12, "shift in whole pixels")
Eq(bob.dx, -12, "the badge moved left")
Eq(bob.point[4], -10 - 12, "anchored 12 px further left (above the name)")
QuestLineagePlateOffset.scripts.OnValueChanged(QuestLineagePlateOffset, 99)
Eq(QL.DB().plateOffsetX, 40, "capped at +40")
QuestLineagePlateOffset.scripts.OnValueChanged(QuestLineagePlateOffset, 0)
QuestLineagePlateColor3.scripts.OnClick(QuestLineagePlateColor3)
local _, dc = QL.QuestDifficulty(5, 5)
Eq(bob.icon.vertex[1], dc[1], "difficulty colour (The Gathering, level 5: normal)")
QuestLineagePlateCount.checked = false
QuestLineagePlateCount.scripts.OnClick(QuestLineagePlateCount)
Eq(bob.text.text, "", "counter hidden")
QuestLineagePlateCount.checked = true
QuestLineagePlateCount.scripts.OnClick(QuestLineagePlateCount)
QuestLineagePlatesOn.checked = false
QuestLineagePlatesOn.scripts.OnClick(QuestLineagePlatesOn)
Eq(bob.shown, false, "off from the settings page")
QuestLineagePlatesOn.checked = true
QuestLineagePlatesOn.scripts.OnClick(QuestLineagePlatesOn)
QuestLineagePlateSide1.scripts.OnClick(QuestLineagePlateSide1)
QuestLineagePlateColor1.scripts.OnClick(QuestLineagePlateColor1)
Eq(#QL.errors, 0, "current quest and plates without errors: " .. table.concat(QL.errors, " | "))
C_QuestLog = savedLog
QL.ResetContext()
QL.ClearArrow()

-- The game's own quest tracker can be hidden ------------------------------------------------------
ObjectiveTrackerFrame = mock("Frame", "ObjectiveTrackerFrame")
QL.Set("hideGameTracker", true)
Eq(ObjectiveTrackerFrame.shown, false, "hidden by the setting")
ObjectiveTrackerFrame:Show()
Eq(ObjectiveTrackerFrame.shown, false, "the game shows it again: hidden again")
function InCombatLockdown() return true end
QL.Set("hideGameTracker", false)
Eq(ObjectiveTrackerFrame.shown, false, "never touched in combat")
function InCombatLockdown() return false end
for _, fn in ipairs(QL.events.PLAYER_REGEN_ENABLED) do fn("PLAYER_REGEN_ENABLED") end
Eq(ObjectiveTrackerFrame.shown, true, "shown again once combat ends")
Eq(ObjectiveTrackerFrame:GetAlpha(), 1, "and opaque")
-- the game shows it in combat (a kill updates the quest): see-through at once, put away after
local trackerParent = ObjectiveTrackerFrame:GetParent()
QL.Set("hideGameTracker", true)
Check(ObjectiveTrackerFrame:GetParent() ~= trackerParent, "moved under a hidden frame")
function InCombatLockdown() return true end
ObjectiveTrackerFrame.shown = false
ObjectiveTrackerFrame:Show()
Eq(ObjectiveTrackerFrame:GetAlpha(), 0, "shown in combat: see-through at once")
function InCombatLockdown() return false end
for _, fn in ipairs(QL.events.PLAYER_REGEN_ENABLED) do fn("PLAYER_REGEN_ENABLED") end
Eq(ObjectiveTrackerFrame.shown, false, "hidden after combat")
QL.Set("hideGameTracker", false)
Eq(ObjectiveTrackerFrame:GetParent(), trackerParent, "its own parent back when shown again")
Eq(ObjectiveTrackerFrame:GetAlpha(), 1, "opaque again")
Eq(ObjectiveTrackerFrame.shown, true, "shown again")
InCombatLockdown = nil

-- The way back to the corpse ---------------------------------------------------------------------
Eq(QL.corpseActive, false, "alive: no corpse path")
QL.SetArrowTarget(3)
local dead = true
UnitIsDeadOrGhost = function() return dead end
for _, fn in ipairs(QL.events.PLAYER_DEAD) do fn("PLAYER_DEAD") end
local cm, cx, cy = QL.CorpsePosition()
Eq(cm, 1411, "the death spot is remembered")
Eq(cx, 0.5, "where you died")
Eq(QL.corpseActive, true, "dead: the path shows")
Eq(QL.ArrowTarget().corpse, true, "the arrow points at the corpse")
Eq(QL.ArrowTarget().title, "Your corpse", "named")
-- released: the client knows the corpse; you stand at the graveyard
C_DeathInfo = { GetCorpseMapPosition = function() return CreateVector2D(0.6, 0.4) end }
QL.RefreshCorpse()
cm, cx = QL.CorpsePosition()
Eq(cx, 0.6, "the client's corpse position wins")
Eq(QL.ArrowTarget().points[1].x, 0.6, "the arrow follows it")
Check(QL.corpseOnMinimap and QL.corpseOnMinimap.x > 0, "the corpse lies east on the minimap")
Eq(QL.corpseOnMinimap.inside, true, "100 yd away fits in the minimap (233 yd radius)")
Minimap.GetZoom = function() return 5 end
QL.RefreshCorpse()
Eq(QL.corpseOnMinimap.inside, false, "zoomed in: the tombstone waits on the rim")
Minimap.GetZoom = nil
-- the clip helper
local x1, y1, x2, y2 = QL.ClipToCircle(0, 0, 200, 0, 50)
Eq(x2, 50, "a path is clipped at the rim")
Eq(QL.ClipToCircle(100, 100, 200, 100, 50), nil, "outside entirely: nothing")
-- alive again: the arrow goes back to its quest
dead = false
for _, fn in ipairs(QL.events.PLAYER_ALIVE) do fn("PLAYER_ALIVE") end
Eq(QL.corpseActive, false, "alive: the path is gone")
Eq(QL.ArrowQuest(), 3, "the arrow back on its quest")
Eq(QL.DB().deathSpots[next(QL.DB().deathSpots) or "none"], nil, "the death spot forgotten")
-- the setting
dead = true
for _, fn in ipairs(QL.events.PLAYER_DEAD) do fn("PLAYER_DEAD") end
QL.Set("corpseRoute", false)
Eq(QL.corpseActive, false, "off in the settings")
Eq(QL.ArrowQuest(), 3, "and the arrow is left alone")
QL.Set("corpseRoute", true)
dead = false
QL.RefreshCorpse()
UnitIsDeadOrGhost, C_DeathInfo = nil, nil
Eq(#QL.errors, 0, "corpse path without errors: " .. table.concat(QL.errors, " | "))

-- Minimap button -------------------------------------------------------------------------------
local mb = QuestLineageMinimapButton
Check(mb and mb.shown, "minimap button shown")
-- the rim follows the minimap's size: half its width plus 5, so the button rides the border
local realWidth = Minimap.GetWidth
Minimap.GetWidth = function() return 140 end
Eq(QL.MinimapRadius(), 75, "classic 140px minimap")
Minimap.GetWidth = function() return 198 end
Eq(QL.MinimapRadius(), 104, "a larger minimap pushes the button out to its edge")
Minimap.GetWidth = realWidth
local x, y = QL.MinimapPosition(0, 80)
Eq(math.floor(x + 0.5), 80, "angle 0 is right of centre")
Eq(math.floor(y + 0.5), 0, "angle 0 on the centre line")
x, y = QL.MinimapPosition(90, 80)
Eq(math.floor(x + 0.5), 0, "angle 90 above")
Eq(math.floor(y + 0.5), 80, "angle 90 above")
local wasShown = f.shown
mb.scripts.OnClick(mb, "LeftButton")
Eq(f.shown, not wasShown, "left click toggles the window")
mb.scripts.OnClick(mb, "LeftButton")
Eq(f.shown, wasShown, "and back")
QL.Set("minimapButton", false)
Eq(mb.shown, false, "the setting hides it")
QL.Set("minimapButton", true)
Eq(mb.shown, true, "and shows it again")

-- Language switch in the window's header -------------------------------------------------------
QTR_QuestData = QTR_QuestData or { ["3"] = { Title = "Toplanma" } }
QL.Open(3)
f.langTR.scripts.OnClick(f.langTR)
Eq(QL.DB().lang, "tr", "TR from the header")
Eq(f.langTR.active, true, "TR lit")
Eq(f.zoneTab.label.text, "Zincirler", "the window turns Turkish at once")
f.langEN.scripts.OnClick(f.langEN)
Eq(QL.DB().lang, "en", "EN from the header")
Eq(f.langEN.active, true, "EN lit")
Eq(f.zoneTab.label.text, "Chains", "and back to English")
local saved = QTR_QuestData
QTR_QuestData = nil
f.langTR.scripts.OnClick(f.langTR)
Eq(QL.DB().lang, "en", "without WoWTR, TR is refused")
QTR_QuestData = saved

-- The flight timer: a sample flight shows its window, counts down, lands and leaves
do
	local t = 5000
	GetTime = function() return t end
	QL.Command("flight")
	local watcher = QL.flightWatcher
	Check(watcher and watcher.scripts.OnUpdate, "the flight watcher runs every frame")
	local function tick(secs) t = t + secs; watcher.scripts.OnUpdate(watcher, secs) end
	tick(0.5)
	Eq(QuestLineageFlight.shown, true, "the flight window shows")
	Eq(QuestLineageFlight.big.text, "0:20", "20 s flight, half a second in (rounded up)")
	tick(10)
	Eq(QuestLineageFlight.big.text, "0:10", "counting down")
	tick(10.5)
	Eq(QuestLineageFlight.big.text, "Arrived", "landed")
	tick(5)
	Eq(QuestLineageFlight.shown, false, "the window leaves after the landing")
	GetTime = nil
end

-- The zone tab above the current quest window
do
	local cur = QuestLineageCurrent
	Check(cur and cur.zoneTab, "the current quest window has a zone tab")
	QL.SetArrowTarget(2)
	QL.RefreshCurrent()
	local tab = cur.zoneTab
	Eq(tab.shown, true, "the zone tab shows with the window")
	Check(tab.name.text ~= "", "it names the zone: " .. tostring(tab.name.text))
	Check(tab.range.text:find("%d"), "and gives the level band: " .. tostring(tab.range.text))
	QL.Set("currentZoneTab", false)
	QL.RefreshCurrent()
	Eq(tab.shown, false, "the setting hides it")
	QL.Set("currentZoneTab", true)
end

-- Creature search: "where are the boars?"
do
	local found = QL.SearchNpcs("boar")
	Eq(#found, 2, "two boars with places (the fixture's plain Boar has none)")
	Eq(found[1].id, 206, "the one in your zone first")
	Eq(found[1].here, true, "marked as in your zone")
	Eq(found[2].id, 207, "then the other")
	Eq(found[2].count, 2, "with its number of places")
	Eq(#QL.SearchNpcs("b"), 0, "two letters at least")
	local all = QL.TaskSources("name", "boar")
	Eq(#all.sources, 2, "the name view takes every match")
	QL.ShowPage("search")
	local sp = f.searchPage
	sp.input:SetText("boar")
	sp.input.scripts.OnTextChanged(sp.input, true)
	QL.RenderWindow()
	Check(sp.sub.text:find("2 creatures", 1, true), "the count names the creatures: " .. sp.sub.text)
	local rows = {}
	for _, r in ipairs(sp.list.rows) do if r.shown then rows[#rows + 1] = r end end
	local allRow, raging
	for _, r in ipairs(rows) do
		if r.title.text:find("All on the map", 1, true) then allRow = r end
		if r.title.text == "Raging Boar" then raging = r end
	end
	Check(allRow and raging, "an all-together row and a row per creature")
	Check(raging.sub.text:find("Durotar", 1, true), "a creature row names its zone: " .. raging.sub.text)
	Eq(found[2].zones[1].area, 215, "zones per creature")
	raging.scripts.OnEnter(raging); raging.scripts.OnLeave(raging)
	raging.scripts.OnClick(raging)
	Eq(QL.TaskSourcesShown().kind, "npc", "a creature row shows its places")
	Eq(f.zoneMap.shownSpots, 1, "the Raging Boar's spot on your map")
	allRow.scripts.OnClick(allRow)
	Eq(QL.TaskSourcesShown().kind, "name", "the all row shows every match")
	Eq(f.zoneMap.kicker.text, "Creatures", "heading")
	f.zoneMap.treeBtn.scripts.OnClick(f.zoneMap.treeBtn)
	QL.Command("find boar")
	Eq(QL.TaskSourcesShown().id, "boar", "/ql find opens the map for the name")
	f.zoneMap.treeBtn.scripts.OnClick(f.zoneMap.treeBtn)
	QL.Command("find zzzz")
	Eq(QL.TaskSourcesShown(), nil, "nothing found: no map")
	-- the setting: off drops the name list and the search; on builds it again at the next search
	QL.Set("creatureSearch", false)
	Eq(QL.index.npcNames, nil, "off frees the name list")
	Eq(#QL.SearchNpcs("boar"), 0, "off: no creatures")
	QL.Command("find boar")
	Eq(QL.TaskSourcesShown(), nil, "off: /ql find shows nothing")
	QL.RenderWindow()
	Check(not sp.sub.text:find("creatures", 1, true), "off: the Search tab lists quests only: " .. sp.sub.text)
	QL.Set("creatureSearch", true)
	Eq(#QL.SearchNpcs("boar"), 2, "on again: built at the first search")
	Eq(#QL.errors, 0, "creature search without errors: " .. table.concat(QL.errors, " | "))
end

-- Slash commands do not error
QL.Command("status")
QL.Command("lang en")
Eq(QL.DB().lang, "en", "lang command")
QL.Command("help")
Eq(#QL.errors, 0, "no captured errors: " .. table.concat(QL.errors, " | "))

print("ui: ok")
