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
Settings = { RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end, RegisterAddOnCategory = function() end }

-- Load ------------------------------------------------------------------------------
QuestLineageDB = nil
local QL = {}
for _, file in ipairs({ "Core.lua", "Locale.lua", "Data.lua", "State.lua", "Chain.lua", "TreeFrame.lua", "Hooks.lua", "Options.lua" }) do
	assert(loadfile(file))("QuestLineage", QL)
end
for _, fn in ipairs(QL.events.PLAYER_LOGIN) do fn("PLAYER_LOGIN") end
Check(SlashCmdList.QUESTLINEAGE, "slash command registered")
Check(tooltipPost, "tooltip hook installed")
Check(QuestLineageOption1, "options built")

-- The window on quest 3 (the index builds through the frame slicer) --------------------
QL.Open(3)
local f = QuestLineageFrame
Check(f and f.shown, "window shown")
for _ = 1, 5 do
	for _, fr in ipairs(frames) do
		local up = fr.scripts.OnUpdate
		if up then up(fr) end
	end
end

Check(QL.IndexReady(), "index built by the slicer")
QL.RenderWindow()
Eq(f.title.text:find("The Gathering", 1, true) ~= nil, true, "title is the focused quest")
Check(f.sub.text:find("1/8", 1, true), "progress 1/8 done: " .. f.sub.text)
Eq(f.message.shown, false, "no message over a chain")

-- a search with several hits shows the result list
QL.Open("path")
Check(f.results.shown, "results list for several matches")
Check(f.title.text:find("Left Path", 1, true), "first match focused")
QL.Open("no such quest")
Check(f.message.text:find("No quest found", 1, true), "not found message")

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
Check(f.title.text:find("Toplanma", 1, true), "Turkish title in the window")
Check(f.sub.text:find("tamam", 1, true), "Turkish interface text")

-- Slash commands do not error
QL.Command("status")
QL.Command("lang en")
Eq(QL.DB().lang, "en", "lang command")
QL.Command("help")
Eq(#QL.errors, 0, "no captured errors: " .. table.concat(QL.errors, " | "))

print("ui: ok")
