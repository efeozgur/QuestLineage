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
	arrowStyle = "theme", -- "theme" (round plate and ring, like the windows) | "classic" (the bare arrow)
	arrowScale = 1,       -- the arrow's size
	arrowGlow = true,     -- the soft glow behind it
	mapPaths = true,      -- your own routes: the "My route" panel on the world map
	mapRoute = true,      -- the route (or the arrow's quest) drawn on the world map
	minimapRoute = true,  -- the route (quest route or your own) drawn on the minimap too
	worldMapPins = true,  -- the Zones tab's picked zone: its quest pins on the world map too
	quickBarLocked = false, -- the "Where?" bar pinned where it stands
	quickBarVertical = false, -- the "Where?" bar laid out as a column
	quickBar = true,      -- the "Where?" quick bar under the arrow
	toasts = true,        -- results and errors as notification cards (off: in the chat)
	fontFace = "inter",   -- the text font: "inter" | "arial" | "friz" | "skurri" (Theme.FONT_FACES)
	currentScale = 100,   -- the current quest window's size in percent (60-160)
	cardScale = 100,      -- the quest card's size in percent (60-160)
	currentZoneTab = true, -- the zone and its level band on a tab above the current quest window
	nextQuestOffer = true, -- a card offering the next quest when the current one is handed in
	flightTimer = true,   -- the flight timer window while you ride a flight path
	currentQuest = true,  -- the current quest window
	currentMinimized = false, -- the whole window folded down to its title and progress line
	currentCollapsed = false, -- its objectives folded
	currentLogCollapsed = false, -- the "Quests" list under it folded
	currentLogMax = 15,   -- how many quests that list shows (1-30)
	currentLogFilter = "all", -- which: "all" | "zone" | "class" | "chain"
	nearbyTarget = true,  -- a card when the creature you target counts for another quest
	nearbyPlates = true,  -- ... when such a creature's nameplate comes into view
	nearbyAreas = true,   -- ... when you walk into another quest's objective area
	nearbyCurrent = true, -- ... and a reminder when you walk into the current quest's own area
	nearbyCooldown = 3,   -- minutes before the same quest's card can come again (1-15)
	logObjectives = true, -- the list's rows show their objectives (each row can be minimised: logFolded)
	questsHideChains = true, -- the main window's Quests tab leaves chain quests to the Chains tab
	currentLocked = false, -- the current quest window pinned in place (its lock button)
	creatureSearch = true, -- creatures by name on the Search tab and /ql find (a name list in the index)
	hideGameTracker = true, -- hide the game's own quest tracker (QuestLineage's window replaces it)
	questAreas = true,    -- the current quest's objective areas on the minimap and world map
	questAreasOthers = true, -- the other logged quests' areas too (soft, one colour per quest)
	hideGameAreas = false, -- hide the game's own (blue) quest area on the minimap
	questCard = true,     -- QuestLineage's quest card when an NPC offers a quest
	questCardStory = false, -- its story section open
	hideGameQuestFrame = false, -- the game's quest window kept out of sight while the card shows
	openOnAccept = false, -- the main window opens on a quest you accept
	acceptedCurrent = true, -- a quest you accept becomes the current quest (the arrow turns to it)
	voiceAutoplay = false, -- the quest card starts WoWTR Voices' Turkish reading by itself
	corpseRoute = true,   -- while dead: a path to the corpse on the minimap and world map, and the arrow
	nameplates = true,    -- quest badges and counters on objective creatures' nameplates
	plateSide = "left",   -- where the badge sits: "left" | "right" | "top"
	plateColorMode = "status", -- "status" (current quest green, others amber) | "accent" | "difficulty" | "custom"
	plateColor = { 0.984, 0.749, 0.141 }, -- the custom colour
	plateScale = 1,
	plateOffsetX = 0,     -- the badge nudged left (-) or right (+), in pixels
	plateCount = true,    -- the "3/8" counter beside the badge
	plateDroppers = true, -- also creatures that drop an item an objective collects
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

-- Chat: always the chat frame (answers to slash commands, the player typed them there).
function QL.Chat(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
	else
		print("QuestLineage: " .. tostring(msg))
	end
end

-- Print: results and errors. A notification card (Toast.lua) while the setting toasts is on,
-- else the chat. kind: "info" (default) | "success" | "warn" | "error".
function QL.Print(msg, kind)
	if QL.DB().toasts ~= false and QL.Toast then
		local ok = pcall(QL.Toast, tostring(msg), kind)
		if ok then return end
	end
	QL.Chat(msg)
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
			QL.Chat(L("Usage: /ql lang en|tr"))
		else
			QL.Set("lang", lang)
			if lang == "tr" and not QL.HasWoWTR() then
				QL.Chat(L("Turkish needs WoWTR; showing English until it is loaded."))
			end
		end
	elseif cmd == "errors" then
		if #QL.errors == 0 then QL.Chat(L("No errors.")) end
		for _, e in ipairs(QL.errors) do QL.Chat(e) end
	elseif cmd == "arrow" then
		if QL.ArrowDebug then
			QL.ArrowDebug(rest)
		else
			QL.Chat(L("The arrow is not loaded: quit the game fully and start it again (new files need a restart)."))
		end
	elseif cmd == "hedef" or cmd == "objectives" then
		if QL.ObjectiveDebug then QL.ObjectiveDebug(rest) end
	elseif cmd == "kart" or cmd == "card" then
		if QL.CardDebug then QL.CardDebug() else QL.Chat(L("The arrow is not loaded: quit the game fully and start it again (new files need a restart).")) end
	elseif cmd == "map" or cmd == "harita" then
		if QL.ZoneMapDebug then QL.ZoneMapDebug(rest) else QL.Chat(L("The arrow is not loaded: quit the game fully and start it again (new files need a restart).")) end
	elseif cmd == "bul" or cmd == "find" then
		if QL.FindCreatures then QL.FindCreatures(rest) end
	elseif cmd == "plate" or cmd == "plaka" then
		if QL.PlateDebug then QL.PlateDebug() end
	elseif cmd == "flight" or cmd == "ucus" then
		if QL.FlightDemo then QL.FlightDemo() else QL.Chat(L("The arrow is not loaded: quit the game fully and start it again (new files need a restart).")) end
	elseif cmd == "help" then
		QL.Chat("/ql  " .. L("open or close the chain window"))
		QL.Chat("/ql <id|name>  " .. L("show the chain of a quest"))
		QL.Chat("/ql find <name>  " .. L("where a creature stands, on the map (e.g. /ql find boar)"))
		QL.Chat("/ql plate  " .. L("why the target has a quest badge on its nameplate, or not"))
		QL.Chat("/ql status  " .. L("database and language status"))
		QL.Chat("/ql arrow [id]  " .. L("arrow status, or point it at a quest"))
		QL.Chat("/ql lang en|tr  " .. L("interface language"))
		QL.Chat("/ql kart  " .. L("what the open quest card holds"))
		QL.Chat("/ql hedef [id]  " .. L("where a quest's objectives come from"))
		QL.Chat("/ql map [area]  " .. L("what the client gives for a zone's map picture"))
		QL.Chat("/ql flight  " .. L("a sample flight to see the flight timer"))
		QL.Chat("/ql options  " .. L("settings"))
	else
		if QL.Open then QL.Open(msg) end
	end
end

function QL.PrintStatus()
	local L = QL.L
	local state, reason = QL.DataStatus()
	QL.Chat(L("QuestieDB: ") .. state .. (reason and (" (" .. tostring(reason) .. ")") or ""))
	QL.Chat(L("Chain index: ") .. (QL.IndexReady() and L("ready") or L("building")))
	QL.Chat(L("WoWTR: ") .. (QL.HasWoWTR() and L("loaded") or L("not loaded")) .. " · " .. L("language: ") .. (QL.UseTurkish() and "tr" or "en"))
	QL.Chat(L("Version: ") .. QL.version .. (#QL.errors > 0 and (" · " .. #QL.errors .. L(" errors (/ql errors)")) or ""))
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
