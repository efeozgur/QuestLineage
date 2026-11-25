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
UISpecialFrames = {}
GameTooltip = mock("GameTooltip", "GameTooltip")
GameTooltip.lines = {}
function GameTooltip:AddLine(t) table.insert(self.lines, t) end
function GameTooltip:SetOwner() self.lines = {} end
QuestFrame = mock("Frame", "QuestFrame")
C_Timer = { After = function(_, fn) fn() end }
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
	IsQuestFlaggedCompleted = function(id) return id == 1 end,
}
local tooltipPost
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) tooltipPost = fn end }
Enum = { TooltipDataType = { Unit = 2 } }
C_Map = {
	GetBestMapForUnit = function() return 1411 end,
	GetMapInfo = function(id) if id == 1411 then return { name = "Durotar", parentMapID = 1414 } end end,
}
function GetCursorPosition() return 0, 0 end
Settings = { RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end, RegisterAddOnCategory = function() end }

-- Load ------------------------------------------------------------------------------
QuestLineageDB = nil
local QL = {}
for _, file in ipairs({ "Core.lua", "Locale.lua", "Data.lua", "Zone.lua", "State.lua", "Chain.lua", "Theme.lua", "Tree.lua", "Window.lua", "Hooks.lua", "Options.lua" }) do
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
Eq(f.infoTitle.text, "The Gathering", "info bar title is the focused quest")
Check(f.infoDone.text:find("1/8", 1, true), "progress 1/8 done: " .. f.infoDone.text)
Eq(f.infoPct.text, "13%", "percent done")
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
Eq(rows[2].chip.text, "Locked", "the loop chain needs itself, so it is locked")
Check(rows[1].sub.text:find("8 quests", 1, true), "row sub line: " .. rows[1].sub.text)
rows[2].scripts.OnClick(rows[2])
Check(f.infoTitle.text:find("Loop", 1, true), "clicking a row opens its tree: " .. f.infoTitle.text)
Eq(rows[2].selected, true, "clicked row selected")
Eq(rows[1].selected, false, "other row not selected")

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
Eq(f.infoTitle.text, "Left Path", "result opens its tree")
QL.Open("gathering")
Eq(QL.DB().page, "search", "text opens the search page")
Eq(f.infoTitle.text, "The Gathering", "best hit focused")
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
Eq(f.infoTitle.text, "Toplanma", "Turkish title in the window")
Check(f.infoDone.text:find("tamam", 1, true), "Turkish interface text")
Eq(f.zoneTab.label.text, "Bu bölge", "Turkish tab label")

-- Slash commands do not error
QL.Command("status")
QL.Command("lang en")
Eq(QL.DB().lang, "en", "lang command")
QL.Command("help")
Eq(#QL.errors, 0, "no captured errors: " .. table.concat(QL.errors, " | "))

print("ui: ok")
