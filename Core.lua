-- QuestLineage core: the namespace, saved settings, event dispatch and slash commands.
-- Every file starts with `local ADDON, QL = ...` and hangs its functions off QL.
-- Loadable without the WoW client (tests pass a bare table), so every client global is guarded.

local ADDON, QL = ...
QL = QL or {}
QuestLineage = QL

QL.name = ADDON or "QuestLineage"
QL.version = "dev"
do
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	if getMeta then
		local ok, v = pcall(getMeta, QL.name, "Version")
		if ok and v then QL.version = v end
	end
end

-- Settings ------------------------------------------------------------------

QL.defaults = {
	lang = "en",          -- "en" or "tr" (tr only takes effect while WoWTR is loaded)
	tooltip = true,       -- chain line on NPC tooltips
	logButton = true,     -- Chain button in the quest log
	detailButton = true,  -- Chain button and warnings on the quest offer window
	hideOther = true,     -- leave out quests this race/class can never take
	minimapButton = true, -- the button on the minimap's rim
	minimapAngle = 215,   -- where on the rim, in degrees
	arrowColorMode = "direction", -- "direction" (by facing), "accent" (the theme's), "custom"
	arrowColor = { 0.239, 0.839, 0.776 }, -- the custom colour
	arrowScale = 1,       -- the arrow's size
	arrowGlow = true,     -- the soft glow behind it
}

-- SavedVariables can be missing on a cold start: always go through DB().
function QL.DB()
	if type(QuestLineageDB) ~= "table" then QuestLineageDB = {} end
	local db = QuestLineageDB
	for k, v in pairs(QL.defaults) do
		if db[k] == nil then db[k] = v end
	end
	return db
end

function QL.Set(key, value)
	QL.DB()[key] = value
	QL.Fire("SETTING_CHANGED", key, value)
end

-- Internal messages ---------------------------------------------------------

QL.handlers = {}

function QL.On(message, fn)
	local list = QL.handlers[message]
	if not list then list = {}; QL.handlers[message] = list end
	list[#list + 1] = fn
end

function QL.Fire(message, ...)
	local list = QL.handlers[message]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then QL.Debug(message .. ": " .. tostring(err)) end
	end
end

-- Game events: QL.Event(name, fn) registers on one shared frame.
QL.events = {}
local eventFrame = CreateFrame and CreateFrame("Frame")

function QL.Event(event, fn)
	local list = QL.events[event]
	if not list then
		list = {}
		QL.events[event] = list
		if eventFrame then pcall(eventFrame.RegisterEvent, eventFrame, event) end
	end
	list[#list + 1] = fn
end

if eventFrame then
	eventFrame:SetScript("OnEvent", function(_, event, ...)
		local list = QL.events[event]
		if not list then return end
		for i = 1, #list do
			local ok, err = pcall(list[i], event, ...)
			if not ok then QL.Debug(event .. ": " .. tostring(err)) end
		end
	end)
end

-- Output --------------------------------------------------------------------

local PREFIX = "|cff7fd3ffQuestLineage|r: "

function QL.Print(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
	else
		print("QuestLineage: " .. tostring(msg))
	end
end

QL.errors = {}
function QL.Debug(msg)
	local e = QL.errors
	if #e < 50 then e[#e + 1] = tostring(msg) end
end

-- Slash commands ------------------------------------------------------------

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function QL.Command(msg)
	local L = QL.L
	msg = trim(msg)
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	cmd = cmd and cmd:lower() or ""
	if cmd == "" then
		if QL.ToggleWindow then QL.ToggleWindow() end
	elseif cmd == "status" then
		QL.PrintStatus()
	elseif cmd == "options" or cmd == "config" then
		if QL.OpenOptions then QL.OpenOptions() end
	elseif cmd == "lang" then
		local lang = rest:lower()
		if lang ~= "en" and lang ~= "tr" then
			QL.Print(L("Usage: /ql lang en|tr"))
		else
			QL.Set("lang", lang)
			if lang == "tr" and not QL.HasWoWTR() then
				QL.Print(L("Turkish needs WoWTR; showing English until it is loaded."))
			end
		end
	elseif cmd == "errors" then
		if #QL.errors == 0 then QL.Print(L("No errors.")) end
		for _, e in ipairs(QL.errors) do QL.Print(e) end
	elseif cmd == "arrow" then
		if QL.ArrowDebug then
			QL.ArrowDebug(rest)
		else
			QL.Print(L("The arrow is not loaded: quit the game fully and start it again (new files need a restart)."))
		end
	elseif cmd == "help" then
		QL.Print("/ql  " .. L("open or close the chain window"))
		QL.Print("/ql <id|name>  " .. L("show the chain of a quest"))
		QL.Print("/ql status  " .. L("database and language status"))
		QL.Print("/ql arrow [id]  " .. L("arrow status, or point it at a quest"))
		QL.Print("/ql lang en|tr  " .. L("interface language"))
		QL.Print("/ql options  " .. L("settings"))
	else
		if QL.Open then QL.Open(msg) end
	end
end

function QL.PrintStatus()
	local L = QL.L
	local state, reason = QL.DataStatus()
	QL.Print(L("QuestieDB: ") .. state .. (reason and (" (" .. tostring(reason) .. ")") or ""))
	QL.Print(L("Chain index: ") .. (QL.IndexReady() and L("ready") or L("building")))
	QL.Print(L("WoWTR: ") .. (QL.HasWoWTR() and L("loaded") or L("not loaded")) .. " · " .. L("language: ") .. (QL.UseTurkish() and "tr" or "en"))
	QL.Print(L("Version: ") .. QL.version .. (#QL.errors > 0 and (" · " .. #QL.errors .. L(" errors (/ql errors)")) or ""))
end

if SlashCmdList then
	SLASH_QUESTLINEAGE1 = "/questlineage"
	SLASH_QUESTLINEAGE2 = "/lineage"
	SLASH_QUESTLINEAGE3 = "/ql"
	SlashCmdList.QUESTLINEAGE = function(msg) QL.Command(msg) end
end

QL.Event("PLAYER_LOGIN", function()
	QL.DB()
	QL.Fire("LOGIN")
end)
