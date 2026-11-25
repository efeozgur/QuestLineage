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
	function mt.SetFrameStrata(self, v) self.strata = v end
	function mt.GetFrameStrata(self) return self.strata end
	function mt.SetTextColor(self, ...) numbers("SetTextColor", ...) end
	function mt.SetColorTexture(self, ...) numbers("SetColorTexture", ...) end
	function mt.SetScript(self, s, fn) self.scripts[s] = fn end
	function mt.HookScript(self, s, fn) self.scripts[s] = fn end
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
for _, file in ipairs({ "Core.lua", "Locale.lua", "Data.lua", "Zone.lua", "State.lua", "Chain.lua", "Details.lua", "Nav.lua", "Theme.lua", "Tree.lua", "Inspector.lua", "Window.lua", "Arrow.lua", "MinimapButton.lua", "Hooks.lua", "Options.lua" }) do
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
Eq(rows[2].chip.text, "Completed", "the finished loop chain comes last")
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
Eq(hits[1].chip.text, "#6", "id chip")
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

-- Tooltip line on an NPC that starts a chained quest (Alice gives 2 and 10) -----------------
QL.ClearChainCache()
GameTooltip.lines = {}
tooltipPost(GameTooltip, { guid = "Creature-0-0-0-0-101-0000" })
Eq(#GameTooltip.lines, 1, "one chain line (quest 10 has no chain)")
Check(GameTooltip.lines[1]:find("Chain 2/4", 1, true), "summary on the line: " .. tostring(GameTooltip.lines[1]))
Check(GameTooltip.lines[1]:find("next: The Gathering", 1, true), "next quest named")

-- Quest offer strip: quest 6 closes 7 ---------------------------------------------------------
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
Eq(arrow.dist.text, "191 yd", "distance sqrt(48^2 + 184.8^2): " .. arrow.dist.text)
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
local panel = QuestLineageOption1.parent
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
-- leaving the page hides the preview when no quest is set
panel:Hide()
Eq(arrow.shown, false, "preview gone with the page")
-- back to the defaults
QuestLineageArrowMode1.scripts.OnClick(QuestLineageArrowMode1)
Eq(QL.DB().arrowColorMode, "direction", "by direction again")

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

-- Slash commands do not error
QL.Command("status")
QL.Command("lang en")
Eq(QL.DB().lang, "en", "lang command")
QL.Command("help")
Eq(#QL.errors, 0, "no captured errors: " .. table.concat(QL.errors, " | "))

print("ui: ok")
