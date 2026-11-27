-- Settings page: in the game's Settings > AddOns list when the client has the Settings API,
-- else in the old Interface Options. `/ql options` opens it.
--
-- A menu on the left, one page on the right (scrolling when long; the game's settings window does
-- not scroll a canvas by itself). Each page is grouped under small headings; every setting has a
-- grey line saying what it does; a setting that depends on another is indented and dimmed while
-- the other is off. The page last shown is remembered (optionsPage).
--   General          language, notifications, the minimap button, quest lists
--   Quest tracking   the current quest window, the quest card at NPCs, tooltips, the quest log
--   Maps             quest areas, the world map route, the way to your corpse
--   Arrow            colour (by direction / the theme's / my own, from the game's colour picker),
--                    size, glow, the "Where?" bar, position reset; while the settings are open
--                    the arrow shows a turning preview (QL.ArrowPreview)
--   Nameplates       on/off, position, colour, size, shift, the counter, item droppers
-- Frame names stay stable for tests: QuestLineageOption<n> (n in ROWS order, 1 = language),
-- QuestLineageArrow*, QuestLineagePlate*, QuestLineageOptionsPage<n> (menu buttons).

local _, QL = ...

local function L(s) return QL.L(s) end

local NAV_W, CONTENT_W = 150, 470
local MEDIA = "Interface/AddOns/QuestLineage/Media/"

local panel, root, category
local checks = {}
local arrowUI, plateUI, fontUI, unitUI, barUI, themeUI = {}, {}, {}, {}, {}, {}
local buildThemeBlock -- forward: the General page's theme group
local buildUnitBlock -- forward: defined with the page builders, used by build()
local pages, navButtons = {}, {}
local texts = {} -- { fontString, englishText, size, bold } re-labelled on refresh

-- Plain settings: one check with its description. parent = the setting it depends on.
local ROWS = {
	{ key = "lang", lang = true, page = "general", group = "Language",
		label = "Use Turkish (needs WoWTR)", note = "Quest titles, objectives and the interface in Turkish, from WoWTR." },
	{ key = "toasts", page = "general", group = "Notifications and buttons",
		label = "Messages in a notification window", note = "Off: results and errors go to the chat instead." },
	{ key = "minimapButton", page = "general", group = "Notifications and buttons",
		label = "Button on the minimap", note = "Click: open QuestLineage. Shift-click: show or hide the \"Where?\" bar." },
	{ key = "hideOther", page = "general", group = "Quest lists",
		label = "Hide quests your race or class can never take", note = "Keeps chains and lists to what this character can do." },

	{ key = "currentQuest", page = "tracking", group = "Current quest window",
		label = "Current quest window", note = "The quest you are on with its objectives, and every other quest in your log under it." },
	{ key = "hideGameTracker", page = "tracking", group = "Current quest window",
		label = "Hide the game's own quest tracker", note = "Use QuestLineage's window instead of the game's list (applied after combat)." },
	{ key = "questCard", page = "tracking", group = "At the NPC",
		label = "Quest card at NPCs", note = "QuestLineage's own window for quests: the NPC's quest list, offers with Accept and Decline, hand-ins with rewards." },
	{ key = "hideGameQuestFrame", parent = "questCard", page = "tracking", group = "At the NPC",
		label = "Hide the game's quest window while the card is open", note = "Only the card shows (also for the NPC's quest list and hand-ins); closing it ends the conversation." },
	{ key = "openOnAccept", page = "tracking", group = "At the NPC",
		label = "Open the QuestLineage window when I accept a quest", note = "The quest opens with its chain tree." },
	{ key = "detailButton", page = "tracking", group = "At the NPC", parentOff = "questCard",
		label = "Chain button and warnings under the game's quest window", note = "Used when the quest card is off." },
	{ key = "tooltip", page = "tracking", group = "Tooltips and the quest log",
		label = "Chain line on NPC tooltips", note = "Hovering a quest giver shows where its quest stands in a chain." },
	{ key = "logButton", page = "tracking", group = "Tooltips and the quest log",
		label = "Chain button in the quest log", note = "Opens the selected quest's chain." },

	{ key = "questAreas", page = "maps", group = "Quests",
		label = "Current quest's areas", note = "Soft rings where the objectives are, on the minimap and world map. Hover one for the quest." },
	{ key = "hideGameAreas", page = "maps", group = "Quests",
		label = "Hide the game's blue quest area on the minimap", note = "Leaves only QuestLineage's rings." },
	{ key = "mapRoute", page = "maps", group = "Quests",
		label = "Route on the world map", note = "The route you build in the Quests list, with numbered stops." },
	{ key = "corpseRoute", page = "maps", group = "When you die",
		label = "The way to my corpse", note = "A glowing path on both maps, and the arrow points at the corpse." },

	{ key = "voiceAutoplay", parent = "questCard", page = "tracking", group = "Turkish voice-over",
		label = "Read the quest aloud as soon as the card opens", note = "Off: nothing plays until you click the speaker on the card. Needs WoWTR Voices." },
	{ key = "acceptedCurrent", page = "tracking", group = "Current quest window",
		label = "A quest I accept becomes the current quest", note = "The arrow turns to it (not while a route runs)." },
	{ key = "currentLogMax", page = "tracking", group = "Current quest window", parent = "currentQuest",
		slider = { min = 1, max = 30, text = "Quests in the list: %d" }, note = "How many of your other quests show under the current one; the rest as \"+N more\"." },
	{ key = "questsHideChains", page = "general", group = "Quest lists",
		label = "Leave chain quests out of the Quests tab", note = "The Quests tab lists standalone quests; chains have their own tab." },
	{ key = "nearbyTarget", page = "tracking", group = "Other quests nearby",
		label = "When I target a creature of another quest", note = "A card names the quest; a click on it makes that quest current." },
	{ key = "nearbyPlates", page = "tracking", group = "Other quests nearby",
		label = "When such a creature comes into view", note = "From its nameplate (the game's nameplates have to be on)." },
	{ key = "nearbyAreas", page = "tracking", group = "Other quests nearby",
		label = "When I walk into another quest's area", note = "The areas the map rings show, for every quest in your log." },
	{ key = "nearbyCooldown", page = "tracking", group = "Other quests nearby",
		slider = { min = 1, max = 15, text = "The same quest's card again after %d min" }, note = "However it came up: target, nameplate or area." },
	{ key = "questAreasOthers", page = "maps", group = "Quests", parent = "questAreas",
		label = "Other quests' areas too", note = "Softer rings, one colour per quest; the current quest's stay bright on top." },
	{ key = "currentScale", page = "tracking", group = "Text and size", parent = "currentQuest",
		slider = { min = 60, max = 160, step = 5, text = "Current quest window size: %d%%" }, note = "Makes the whole window, its text included, smaller or larger." },
	{ key = "cardScale", page = "tracking", group = "Text and size", parent = "questCard",
		slider = { min = 60, max = 160, step = 5, text = "Quest card size: %d%%" }, note = "The window that opens at quest givers." },
	{ key = "flightTimer", page = "tracking", group = "Flights",
		label = "Flight timer", note = "On a flight path a window counts the time left down. A route is timed on its first flight; later ones count down." },
	{ key = "currentZoneTab", page = "tracking", group = "Current quest window", parent = "currentQuest",
		label = "Zone and its level range above the window", note = "A small tab with the zone you are in and the levels of its quests, coloured by how they suit your level." },
	{ key = "quickBar", page = "where", group = "The bar",
		label = "\"Where?\" bar", note = "Icons that point the arrow at the nearest trainer, vendor or service." },
	{ key = "nearbyCurrent", page = "tracking", group = "Other quests nearby", parent = "nearbyAreas",
		label = "Remind me when I reach the current quest's area", note = "A card when you walk into the area where the current quest's objectives are." },
	{ key = "quickBarVertical", page = "where", group = "The bar", parent = "quickBar",
		label = "Vertical bar", note = "Lay the icons out in a column instead of a row. The bar's turn button does the same." },
	{ key = "mapPaths", page = "maps", group = "Your own routes",
		label = "\"My route\" panel on the world map", note = "Put stops on the world map yourself (Shift+click while editing), save the route by name and let the arrow follow it." },
	{ key = "nextQuestOffer", page = "tracking", group = "Other quests nearby",
		label = "Offer the next quest when the current one is handed in", note = "A small card for five seconds; a click switches to that quest, otherwise nothing changes." },	{ key = "minimapRoute", page = "maps", group = "Quests",
		label = "Route on the minimap", note = "The way to the next stop and the stops after it, on the minimap too; the next stop waits on the rim when it is further away." },
	{ key = "worldMapPins", page = "maps", group = "Quests",
		label = "The picked zone's quests on the world map", note = "The zone open on the Zones tab: its quest pins also on the game's world map, on that zone and on its continent." },
	{ key = "currentLocked", parent = "currentQuest", page = "tracking", group = "Current quest window",
		label = "Lock the current quest window", note = "It stays where it stands; the lock in its corner does the same." },
	{ key = "creatureSearch", page = "general", group = "Search",
		label = "Creature search", note = "Creatures by name on the Search tab and /ql find, with their places on the map. Off saves the memory of the name list." },
	{ key = "quickBarLocked", parent = "quickBar", page = "where", group = "The bar",
		label = "Lock the bar in place", note = "It cannot be moved; the padlock on the bar does the same." },
	{ key = "quickBarScale", page = "where", group = "Size and look", parent = "quickBar",
		slider = { min = 60, max = 160, step = 5, text = "Bar size: %d%%" }, note = "Makes the whole bar, its icons included, smaller or larger." },
	{ key = "quickBarAlpha", page = "where", group = "Size and look", parent = "quickBar",
		slider = { min = 20, max = 100, step = 5, text = "Background opacity: %d%%" }, note = "Lower is more see-through; the icons stay clear." },
	{ key = "quickBarTips", page = "where", group = "Tips and clicks", parent = "quickBar",
		label = "List the nearest places when I hover an icon", note = "The tip names them with their distance. Off: icons show no tip." },
	{ key = "quickBarTipCount", page = "where", group = "Tips and clicks", parent = "quickBarTips",
		slider = { min = 1, max = 5, text = "Places listed in the tip: %d" }, note = "How many of the nearest ones the tip shows." },
	{ key = "quickBarCycle", page = "where", group = "Tips and clicks", parent = "quickBar",
		slider = { min = 3, max = 30, text = "Click again within %d s for the next nearest" }, note = "A second click on the same icon in this time points the arrow at the next nearest place." },
}

local PAGES = {
	{ id = "general", title = "General", hint = "Language, notifications and the addon's buttons." },
	{ id = "tracking", title = "Quest tracking", hint = "The current quest window, quests offered by NPCs, tooltips." },
	{ id = "maps", title = "Maps", hint = "What QuestLineage draws on the minimap and the world map." },
	{ id = "arrow", title = "Arrow", hint = "The arrow's look, size and position." },
	{ id = "where", title = "\"Where?\" bar", hint = "Icons that point the arrow at the nearest trainer, vendor or service." },
	{ id = "plates", title = "Nameplates", hint = "A quest badge and counter beside the creatures your quests need." },
}

local UNITS = {
	{ mode = "yd", label = "Yards (yd)" },
	{ mode = "m", label = "Metres (m)" },
	{ mode = "km", label = "Kilometres (km)" },
}
local ARROW_STYLES = {
	{ mode = "theme", label = "Theme: on a round plate, like the windows" },
	{ mode = "classic", label = "Classic: the bare arrow" },
}
local ARROW_COLORS = {
	{ mode = "direction", label = "By direction (ahead, to the side, behind)" },
	{ mode = "accent", label = "The theme's colour" },
	{ mode = "custom", label = "My own colour" },
}
local PLATE_SIDES = {
	{ mode = "left", label = "Left of the health bar" },
	{ mode = "right", label = "Right of the health bar" },
	{ mode = "top", label = "Above the name" },
}
local PLATE_COLORS = {
	{ mode = "status", label = "By quest: current one green, others amber" },
	{ mode = "accent", label = "The theme's colour" },
	{ mode = "difficulty", label = "The quest's difficulty colour" },
	{ mode = "custom", label = "My own colour" },
}

local function labelOf(check)
	return check.Text or check.text or (check.GetName and check:GetName() and _G[check:GetName() .. "Text"])
end

local function setLabel(check, text, size)
	local fs = labelOf(check)
	if fs then
		QL.SetFont(fs, size or 12)
		fs:SetText(text)
	end
	return fs
end

-- The game's colour picker: the newer SetupColorPickerAndShow, else the older fields.
local function pickColor(r, g, b, onChange)
	local CPF = ColorPickerFrame
	if not CPF then return end
	local function current()
		local nr, ng, nb = CPF:GetColorRGB()
		onChange(nr, ng, nb)
	end
	local function cancel() onChange(r, g, b) end
	if CPF.SetupColorPickerAndShow then
		CPF:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, swatchFunc = current, cancelFunc = cancel })
	else
		CPF.hasOpacity = false
		CPF.previousValues = { r, g, b }
		CPF.func = current
		CPF.cancelFunc = cancel
		CPF:SetColorRGB(r, g, b)
		CPF:Hide()
		CPF:Show()
	end
end
QL.PickColor = pickColor

-- Building blocks (they draw on `root`, the page being built) ------------------------------------

-- A text kept in the chosen language: re-labelled on every refresh.
local function text(y, english, size, color, x, bold)
	local T = QL.Theme
	local fs = T.Text(root, size, color or T.C.text, nil, bold)
	fs:SetPoint("TOPLEFT", x or 16, y)
	fs:SetPoint("RIGHT", root, "RIGHT", -16, 0)
	if fs.SetWordWrap then fs:SetWordWrap(true) end
	texts[#texts + 1] = { fs = fs, en = english, size = size, bold = bold }
	return fs
end

-- Groups sit on soft cards: a group heading closes the card before it and opens its own; a page
-- builder calls endCard(y) after its last group. Textures on the page (below its widgets).
local card
local function endCard(y)
	if not card then return end
	local T, C = QL.Theme, QL.Theme.C
	local bottom = y + 2
	card.bg:SetPoint("BOTTOMRIGHT", root, "TOPLEFT", CONTENT_W - 8, bottom)
	for _, e in ipairs(card.edges) do T.Color(e, C.lineSoft) end
	card.edges[1]:SetPoint("TOPLEFT", card.bg, "TOPLEFT"); card.edges[1]:SetPoint("TOPRIGHT", card.bg, "TOPRIGHT"); card.edges[1]:SetHeight(1)
	card.edges[2]:SetPoint("BOTTOMLEFT", card.bg, "BOTTOMLEFT"); card.edges[2]:SetPoint("BOTTOMRIGHT", card.bg, "BOTTOMRIGHT"); card.edges[2]:SetHeight(1)
	card.edges[3]:SetPoint("TOPLEFT", card.bg, "TOPLEFT"); card.edges[3]:SetPoint("BOTTOMLEFT", card.bg, "BOTTOMLEFT"); card.edges[3]:SetWidth(1)
	card.edges[4]:SetPoint("TOPRIGHT", card.bg, "TOPRIGHT"); card.edges[4]:SetPoint("BOTTOMRIGHT", card.bg, "BOTTOMRIGHT"); card.edges[4]:SetWidth(1)
	card = nil
end

-- A group heading: small accent capitals with a thin line beside them, on a new card.
local function groupHeading(y, english)
	local T, C = QL.Theme, QL.Theme.C
	endCard(y)
	local top = y - 6
	card = { bg = root:CreateTexture(nil, "BACKGROUND"), edges = {} }
	card.bg:SetTexture(T.WHITE)
	card.bg:SetVertexColor(QL.Theme.Wash(0.03))
	card.bg:SetPoint("TOPLEFT", root, "TOPLEFT", 8, top)
	for i = 1, 4 do
		card.edges[i] = root:CreateTexture(nil, "BORDER")
		card.edges[i]:SetTexture(T.WHITE)
	end
	y = y - 18
	local fs = text(y, english, 10, C.accent, 20, true)
	fs:SetPoint("RIGHT", root, "LEFT", 300, 0)
	local line = root:CreateTexture(nil, "BORDER")
	line:SetTexture(T.WHITE)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 20, y - 16)
	line:SetPoint("RIGHT", root, "RIGHT", -20, 0)
	T.Color(line, C.lineSoft)
	return y - 26
end

-- the old helpers the Arrow and Nameplates pages use
local function label(y)
	local fs = QL.Theme.Text(root, 12, QL.Theme.C.text)
	fs:SetPoint("TOPLEFT", 20, y)
	return fs
end

-- A switch (kind nil) or a radio ("radio"): a CheckButton the whole row wide, with its own look.
-- SetChecked / SetEnabled repaint it; the label is c.Text (setLabel finds it).
local function paintCheck(c)
	local C = QL.Theme.C
	local on = c:GetChecked() and true or false
	local alpha = c.qlDisabled and 0.4 or 1
	local a = C.accent
	if c.qlKind == "radio" then
		local r = on and a or C.muted
		c.ring:SetVertexColor(r[1], r[2], r[3], alpha)
		c.dot:SetVertexColor(a[1], a[2], a[3], alpha)
		c.dot:SetShown(on)
	else
		local t = on and a or { QL.Theme.Wash(0.16) }
		for _, tex in ipairs(c.track) do tex:SetVertexColor(t[1], t[2], t[3], (t[4] or 1) * alpha) end
		c.knob:ClearAllPoints()
		c.knob:SetPoint("LEFT", c, "LEFT", on and 17 or 3, 0)
		local k = on and 1 or 0.72
		c.knob:SetVertexColor(k, k, k, alpha)
	end
end

local function check(name, x, y, onClick, kind)
	local T, C = QL.Theme, QL.Theme.C
	local c = CreateFrame("CheckButton", name, root)
	c:SetPoint("TOPLEFT", x, y)
	c:SetSize(CONTENT_W - x - 20, 24)
	c:SetScript("OnClick", function(self, ...)
		onClick(self, ...)
		paintCheck(self)
	end)
	c.qlKind = kind
	c.hover = c:CreateTexture(nil, "BACKGROUND")
	c.hover:SetTexture(T.WHITE)
	c.hover:SetAllPoints()
	c.hover:SetVertexColor(QL.Theme.Wash(0))
	if kind == "radio" then
		c.ring = c:CreateTexture(nil, "ARTWORK")
		c.ring:SetTexture(MEDIA .. "ring")
		c.ring:SetSize(16, 16)
		c.ring:SetPoint("LEFT", 4, 0)
		c.dot = c:CreateTexture(nil, "OVERLAY")
		c.dot:SetTexture(MEDIA .. "disc")
		c.dot:SetSize(8, 8)
		c.dot:SetPoint("CENTER", c.ring, "CENTER")
		c.Text = T.Text(c, 12, C.text)
		c.Text:SetPoint("LEFT", 28, 0)
	else
		local capL = c:CreateTexture(nil, "ARTWORK")
		local capR = c:CreateTexture(nil, "ARTWORK")
		local mid = c:CreateTexture(nil, "ARTWORK")
		capL:SetTexture(MEDIA .. "disc")
		capR:SetTexture(MEDIA .. "disc")
		mid:SetTexture(T.WHITE)
		capL:SetSize(16, 16); capR:SetSize(16, 16); mid:SetSize(14, 16)
		capL:SetPoint("LEFT", 0, 0)
		capR:SetPoint("LEFT", 16, 0)
		mid:SetPoint("LEFT", 8, 0)
		c.track = { capL, capR, mid }
		c.knob = c:CreateTexture(nil, "OVERLAY")
		c.knob:SetTexture(MEDIA .. "disc")
		c.knob:SetSize(12, 12)
		c.Text = T.Text(c, 12, C.text)
		c.Text:SetPoint("LEFT", 42, 0)
	end
	c.Text:SetPoint("RIGHT", c, "RIGHT", -4, 0)
	local setChecked, setEnabled = c.SetChecked, c.SetEnabled
	c.SetChecked = function(self, v) setChecked(self, v); paintCheck(self) end
	c.SetEnabled = function(self, v)
		setEnabled(self, v)
		self.qlDisabled = not v
		paintCheck(self)
	end
	c:SetScript("OnEnter", function(self) if not self.qlDisabled then self.hover:SetVertexColor(QL.Theme.Wash(0.05)) end end)
	c:SetScript("OnLeave", function(self) self.hover:SetVertexColor(QL.Theme.Wash(0)) end)
	paintCheck(c)
	return c
end

-- Radio-like checks for one setting: { {mode, label}, ... }
local function radios(prefix, list, key, y)
	local out = {}
	for i, m in ipairs(list) do
		out[i] = check(prefix .. i, 26, y, function() QL.Set(key, m.mode); QL.RefreshOptions() end, "radio")
		y = y - 26
	end
	return out, y
end

-- A colour swatch beside a check: picking a colour also selects "custom" for modeKey.
local function swatch(name, beside, colorKey, modeKey)
	local T = QL.Theme
	local sw = CreateFrame("Button", name, root)
	sw:SetSize(22, 22)
	sw:SetPoint("LEFT", beside, "LEFT", 170, 0)
	T.Fill(sw, { 0.8, 0.8, 0.8, 1 }, "BACKGROUND")
	sw.fill = sw:CreateTexture(nil, "ARTWORK")
	sw.fill:SetTexture(T.WHITE)
	sw.fill:SetPoint("TOPLEFT", 2, -2); sw.fill:SetPoint("BOTTOMRIGHT", -2, 2)
	sw:SetScript("OnClick", function()
		local cur = type(QL.DB()[colorKey]) == "table" and QL.DB()[colorKey] or { 1, 1, 1 }
		pickColor(cur[1] or 1, cur[2] or 1, cur[3] or 1, function(r, g, b)
			QL.DB()[modeKey] = "custom"
			QL.Set(colorKey, { r, g, b }) -- a new table: never write into the defaults
			QL.RefreshOptions()
		end)
	end)
	sw:SetScript("OnEnter", function(self)
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_RIGHT")
		tip:AddLine(L("Pick a colour"), 1, 1, 1)
		tip:Show()
	end)
	sw:SetScript("OnLeave", function() QL.Tip():Hide() end)
	return sw
end

-- A slider for a numeric setting, showing its value in the label above it. Sizes by default
-- (5% steps, "Size: 120%"); opts = { step, text = function(v) -> label, ends = function(v) -> "" }.
local function sizeText(v) return L("Size: %d%%"):format(math.floor(v * 100 + 0.5)) end
local function percent(v) return ("%d%%"):format(v * 100) end

local function slider(name, key, min, max, y, sizeLabel, opts)
	local T = QL.Theme
	opts = opts or {}
	local step = opts.step or 0.05
	local textOf = opts.text or sizeText
	local ends = opts.ends or percent
	local s = CreateFrame("Slider", name, root)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(240, 16)
	s:SetPoint("TOPLEFT", 26, y)
	s:SetMinMaxValues(min, max)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:EnableMouse(true)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetTexture(T.WHITE)
	track:SetPoint("LEFT"); track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetVertexColor(QL.Theme.Wash(0.18))
	s.fill = s:CreateTexture(nil, "ARTWORK")
	s.fill:SetTexture(T.WHITE)
	s.fill:SetPoint("LEFT")
	s.fill:SetSize(1, 4)
	local ac = T.C.accent
	s.fill:SetVertexColor(ac[1], ac[2], ac[3], 1)
	s:SetThumbTexture("Interface\\AddOns\\QuestLineage\\Media\\disc")
	local thumb = s.GetThumbTexture and s:GetThumbTexture()
	if type(thumb) == "table" then
		thumb:SetSize(14, 14)
		thumb:SetVertexColor(0.95, 0.97, 1, 1)
	end
	if s.SetHitRectInsets then s:SetHitRectInsets(0, 0, -8, -8) end
	local function paintFill(v)
		local frac = (max > min) and math.max(0, math.min(1, (v - min) / (max - min))) or 0
		s.fill:SetWidth(math.max(1, 240 * frac))
	end
	s.paintFill = paintFill
	s.low = T.Text(root, 10, T.C.dim)
	s.low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2)
	s.low:SetText(ends(min))
	s.high = T.Text(root, 10, T.C.dim)
	s.high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2)
	s.high:SetText(ends(max))
	s:SetScript("OnValueChanged", function(self, v)
		if self.updating then return end
		v = math.floor(math.max(min, math.min(max, v or 1)) / step + 0.5) * step
		paintFill(v)
		if v ~= QL.DB()[key] then
			QL.Set(key, v)
			sizeLabel:SetText(textOf(v))
		end
	end)
	s.text = textOf
	return s
end

local function offsetText(v)
	v = math.floor(v + 0.5)
	if v == 0 then return L("Horizontal shift: none") end
	return L("Horizontal shift: %+d px"):format(v)
end
local function pixels(v) return ("%+d"):format(v) end

local function setSlider(s, value)
	s.updating = true
	s:SetValue(value)
	s.updating = nil
	if s.paintFill then s.paintFill(tonumber(value) or 0) end
end

-- Refresh ------------------------------------------------------------------------------------------

local function enabled(row, db)
	if row.parent then return db[row.parent] ~= false end
	if row.parentOff then return db[row.parentOff] == false end
	return true
end

local function showPage(id)
	local C = QL.Theme.C
	for pid, page in pairs(pages) do page:SetShown(pid == id) end
	for _, b in ipairs(navButtons) do
		local on = b.pageId == id
		b.active = on
		QL.Theme.Color(b.bg, on and C.rowActive or { 0, 0, 0, 0 })
		b.bar:SetShown(on)
		b.label:SetTextColor(unpack(on and C.text or C.muted))
	end
	local page = pages[id]
	if page and panel and panel.scroll then
		-- back to the top only when the page changes: a refresh (a slider moving) keeps the place
		if panel.shownPage ~= id then panel.scroll:SetVerticalScroll(0) end
		panel.shownPage = id
		panel.scroll:SetContentHeight(page.contentHeight or 400)
	end
end

local function refresh()
	if not panel then return end
	local db = QL.DB()
	local T, C = QL.Theme, QL.Theme.C
	QL.SetFont(panel.title, 15)
	panel.title:SetText(L("Quest Lineage"))
	panel.version:SetText(QL.version or "")
	for _, t in ipairs(texts) do
		T.SetFont(t.fs, t.size, t.bold)
		t.fs:SetText(L(t.en))
	end
	for _, b in ipairs(navButtons) do b.label:SetText(L(b.title)) end
	for i, row in ipairs(ROWS) do
		local c = checks[i]
		if row.slider then
			local v = math.floor(tonumber(db[row.key]) or QL.defaults[row.key] or row.slider.min)
			setSlider(c, v)
			c.label:SetText(L(row.slider.text):format(v))
			local on = enabled(row, db)
			c:SetEnabled(on)
			c.label:SetTextColor(unpack(on and C.text or C.dim))
			c.note:SetTextColor(unpack(on and C.muted or C.dim))
		else
		local fs = setLabel(c, L(row.label))
		if row.lang then
			c:SetChecked(db.lang == "tr")
			c:SetEnabled(QL.HasWoWTR())
			local v = QL.HasWoWTR() and 1 or 0.5
			if fs then fs:SetTextColor(v, v, v) end
		else
			c:SetChecked(db[row.key] and true or false)
			local on = enabled(row, db)
			c:SetEnabled(on)
			if fs then fs:SetTextColor(unpack(on and C.text or C.dim)) end
			if c.note then c.note:SetTextColor(unpack(on and C.muted or C.dim)) end
		end
		end
	end

	-- theme
	if themeUI.radios then
		for i, th in ipairs(QL.Theme.THEMES) do
			setLabel(themeUI.radios[i], L(th.label))
			themeUI.radios[i]:SetChecked((db.theme or "night") == th.id)
		end
		themeUI.note:SetText(L("The colours of every QuestLineage window; they change as you click."))
	end

	-- the "Where?" bar's icons
	if barUI.icons then
		local active = QL.QuickBarActive()
		local on = db.quickBar ~= false
		for i, svc in ipairs(QL.SERVICES) do
			local c = barUI.icons[i]
			local fs = setLabel(c, L(svc.label))
			c:SetChecked(active[svc.key] and true or false)
			c:SetEnabled(on)
			if fs then fs:SetTextColor(unpack(on and C.text or C.dim)) end
		end
		barUI.reset:SetLabel(L("Reset position"))
	end

	-- length unit
	if unitUI.radios then
		for i, m in ipairs(UNITS) do
			setLabel(unitUI.radios[i], L(m.label))
			unitUI.radios[i]:SetChecked(QL.DistanceUnit() == m.mode)
		end
	end

	-- font
	if fontUI.radios then
		for i, m in ipairs(fontUI.list) do
			setLabel(fontUI.radios[i], L(m.label))
			fontUI.radios[i]:SetChecked((db.fontFace or "inter") == m.mode)
		end
	end

	-- arrow
	local a = arrowUI
	if a.colorLabel then
		for i, m in ipairs(ARROW_STYLES) do
			setLabel(a.styles[i], L(m.label))
			a.styles[i]:SetChecked((db.arrowStyle or "theme") == m.mode)
		end
		for i, m in ipairs(ARROW_COLORS) do
			setLabel(a.modes[i], L(m.label))
			a.modes[i]:SetChecked((db.arrowColorMode or "direction") == m.mode)
		end
		local c = type(db.arrowColor) == "table" and db.arrowColor or { 1, 1, 1 }
		a.swatch.fill:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
		local scale = tonumber(db.arrowScale) or 1
		setSlider(a.slider, scale)
		a.sizeLabel:SetText(L("Size: %d%%"):format(math.floor(scale * 100 + 0.5)))
		setLabel(a.glow, L("Glow behind the arrow"))
		a.glow:SetChecked(db.arrowGlow ~= false)
		a.reset:SetLabel(L("Reset positions"))
	end

	-- nameplates
	local p = plateUI
	if p.on then
		local on = db.nameplates ~= false
		setLabel(p.on, L("Quest counters on nameplates"))
		p.on:SetChecked(on)
		for i, m in ipairs(PLATE_SIDES) do
			setLabel(p.sides[i], L(m.label))
			p.sides[i]:SetChecked((db.plateSide or "left") == m.mode)
			p.sides[i]:SetEnabled(on)
		end
		for i, m in ipairs(PLATE_COLORS) do
			setLabel(p.colors[i], L(m.label))
			p.colors[i]:SetChecked((db.plateColorMode or "status") == m.mode)
			p.colors[i]:SetEnabled(on)
		end
		local c = type(db.plateColor) == "table" and db.plateColor or { 1, 1, 1 }
		p.swatch.fill:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
		local scale = tonumber(db.plateScale) or 1
		setSlider(p.slider, scale)
		p.sizeLabel:SetText(L("Size: %d%%"):format(math.floor(scale * 100 + 0.5)))
		local dx = tonumber(db.plateOffsetX) or 0
		setSlider(p.offset, dx)
		p.offsetLabel:SetText(offsetText(dx))
		setLabel(p.count, L("Show the counter (3/8)"))
		p.count:SetChecked(db.plateCount ~= false)
		p.count:SetEnabled(on)
		setLabel(p.droppers, L("Also on creatures that drop an item you collect"))
		p.droppers:SetChecked(db.plateDroppers ~= false)
		p.droppers:SetEnabled(on)
		if p.previewUpdate then p.previewUpdate() end
	end
	showPage(db.optionsPage or "general")
end
QL.RefreshOptions = refresh

-- Pages -------------------------------------------------------------------------------------------

-- The plain rows of one page, under their group headings.
local function buildRows(pageId, y)
	-- rows grouped by group, the groups in the order they first appear (rows can be added at the
	-- end of ROWS without renumbering the frames)
	local groups, byGroup = {}, {}
	for i, row in ipairs(ROWS) do
		if row.page == pageId then
			if not byGroup[row.group] then byGroup[row.group] = {}; groups[#groups + 1] = row.group end
			table.insert(byGroup[row.group], i)
		end
	end
	local order = {}
	for _, g in ipairs(groups) do for _, i in ipairs(byGroup[g]) do order[#order + 1] = i end end
	local group
	for _, i in ipairs(order) do
		local row = ROWS[i]
		do
			if row.group ~= group then
				if group then y = y - 8 end
				group = row.group
				y = groupHeading(y, group)
			end
			local x = (row.parent or row.parentOff) and 40 or 16
			if row.slider then
				local sl = row.slider
				local lbl = label(y)
				lbl:SetPoint("TOPLEFT", x + 4, y)
				local s = slider("QuestLineageOption" .. i, row.key, sl.min, sl.max, y - 22, lbl,
					{ step = sl.step or 1, text = function(v) return L(sl.text):format(math.floor(v + 0.5)) end, ends = function(v) return tostring(v) end })
				s:ClearAllPoints()
				s:SetPoint("TOPLEFT", x + 10, y - 22)
				s.label = lbl
				s.note = text(y - 56, row.note, 11, QL.Theme.C.muted, x + 4)
				checks[i] = s
				y = y - 84
			else
			local c = check("QuestLineageOption" .. i, x, y, function(self)
				if row.lang then
					QL.Set("lang", self:GetChecked() and "tr" or "en")
				else
					QL.Set(row.key, self:GetChecked() and true or false)
				end
				refresh()
			end)
			c.note = text(y - 24, row.note, 11, QL.Theme.C.muted, x + 42)
			checks[i] = c
			y = y - 52
			end
		end
	end
	return y
end

-- The theme: one radio per theme with a three-colour chip beside it; a click repaints every
-- QuestLineage window at once (QL.Theme.Switch, from the SETTING_CHANGED handler in Theme.lua).
buildThemeBlock = function(y)
	local T, C = QL.Theme, QL.Theme.C
	y = groupHeading(y - 8, "Theme")
	themeUI.note = text(y, "The colours of every QuestLineage window; they change as you click.", 11, C.muted, 20)
	y = y - 24
	local list = {}
	for i, th in ipairs(T.THEMES) do list[i] = { mode = th.id, label = th.label } end
	themeUI.radios, y = radios("QuestLineageTheme", list, "theme", y)
	-- a chip of three colours beside each radio
	for i, th in ipairs(T.THEMES) do
		local colors = T.ThemeColors(th.id)
		local r = themeUI.radios[i]
		local x = 210
		for _, k in ipairs({ "card", "accent", "accent2" }) do
			local chip = r:CreateTexture(nil, "ARTWORK")
			chip:SetTexture(T.WHITE)
			T.keepColor[chip] = true
			chip:SetSize(14, 14)
			chip:SetPoint("LEFT", r, "LEFT", x, 0)
			local v = colors[k]
			chip:SetVertexColor(v[1], v[2], v[3], 1)
			x = x + 18
		end
	end
	return y - 44
end

-- The length unit: yards, metres or kilometres (General page, last group).
buildUnitBlock = function(y)
	y = groupHeading(y - 8, "Length unit")
	text(y, "Distances on the arrow, in lists and on the map; 1 yd is 0.91 m.", 11, QL.Theme.C.muted, 20)
	y = y - 24
	unitUI.radios, y = radios("QuestLineageUnit", UNITS, "distanceUnit", y)
	return y - 8
end

-- The text font: one radio per face (the theme's list), under the "Text and size" group.
local function buildFontBlock(y)
	y = groupHeading(y - 4, "Text font")
	local list = {}
	for i, f in ipairs(QL.Theme.FONT_FACES) do list[i] = { mode = f.id, label = f.label } end
	fontUI.list = list
	fontUI.radios, y = radios("QuestLineageFont", list, "fontFace", y)
	fontUI.note = text(y - 2, "Inter has every Turkish letter; the game's own fonts may show broken letters in Turkish.", 11, QL.Theme.C.muted, 20)
	return y - 40
end

local function buildArrowPage(y)
	local a = arrowUI
	y = groupHeading(y, "Look")
	text(y, "The arrow turns here as a preview while the settings are open. Drag it to move it.", 11, QL.Theme.C.muted, 20)
	y = y - 30
	a.styleLabel = text(y, "Style", 12, QL.Theme.C.text, 20)
	y = y - 20
	a.styles, y = radios("QuestLineageArrowStyle", ARROW_STYLES, "arrowStyle", y)
	y = y - 8
	a.colorLabel = text(y, "Colour", 12, QL.Theme.C.text, 20)
	y = y - 20
	a.modes, y = radios("QuestLineageArrowMode", ARROW_COLORS, "arrowColorMode", y)
	a.swatch = swatch("QuestLineageArrowSwatch", a.modes[3], "arrowColor", "arrowColorMode")
	y = y - 8
	a.sizeLabel = label(y); y = y - 22
	a.slider = slider("QuestLineageArrowScale", "arrowScale", 0.5, 2, y, a.sizeLabel); y = y - 40
	a.glow = check("QuestLineageArrowGlow", 16, y, function(self) QL.Set("arrowGlow", self:GetChecked() and true or false); refresh() end)
	y = y - 44
	y = buildRows("arrow", y)
	y = groupHeading(y - 4, "Position")
	text(y, "Puts the arrow and the \"Where?\" bar back at the top of the screen.", 11, QL.Theme.C.muted, 20)
	y = y - 24
	local r = QL.Theme.Button(root, 170, 26)
	r:SetPoint("TOPLEFT", 20, y)
	r:SetScript("OnClick", function()
		if QL.ResetArrowPosition then QL.ResetArrowPosition() end
		if QL.ResetQuickBarPosition then QL.ResetQuickBarPosition() end
	end)
	a.reset = r
	_G.QuestLineageArrowReset = r
	return y - 44
end

-- A sample nameplate pair (the current quest's creature and another quest's) that follows the
-- settings below it: side, shift, colour, size, counter. Positions as Plates.lua's placeBadge.
local function buildBarExtras(y)
	local T = QL.Theme
	y = groupHeading(y, "Icons on the bar")
	text(y, "Pick up to 12 icons. They keep this order; the \"...\" button always shows every category.", 11, T.C.muted, 20)
	y = y - 34
	barUI.icons = {}
	for i, svc in ipairs(QL.SERVICES) do
		barUI.icons[i] = check("QuestLineageBarIcon" .. i, 26, y, function(self)
			QL.SetQuickBarIcon(svc.key, self:GetChecked() and true or false)
			refresh()
		end)
		y = y - 26
	end
	y = groupHeading(y - 4, "Position")
	text(y, "Puts the bar back at the top of the screen.", 11, T.C.muted, 20)
	y = y - 24
	local r = T.Button(root, 170, 26)
	r:SetPoint("TOPLEFT", 20, y)
	r:SetScript("OnClick", function() if QL.ResetQuickBarPosition then QL.ResetQuickBarPosition() end end)
	barUI.reset = r
	_G.QuestLineageBarReset = r
	return y - 44
end

local function buildPlatePreview(y)
	local T, C = QL.Theme, QL.Theme.C
	y = groupHeading(y, "Preview")
	local box = CreateFrame("Frame", nil, root)
	box:SetSize(CONTENT_W - 40, 100)
	box:SetPoint("TOPLEFT", 20, y)
	T.Fill(box, C.canvas)
	T.Border(box, C.line)
	local samples = {}
	local function sample(cx, name, counter, caption, current)
		local sm = { current = current, counter = counter }
		sm.name = box:CreateFontString(nil, "OVERLAY")
		T.SetFont(sm.name, 11, false, "OUTLINE")
		sm.name:SetTextColor(1, 0.35, 0.3, 1)
		sm.name:SetPoint("CENTER", box, "TOPLEFT", cx, -30)
		sm.name:SetText(name)
		sm.bar = CreateFrame("Frame", nil, box)
		sm.bar:SetSize(100, 10)
		sm.bar:SetPoint("TOP", sm.name, "BOTTOM", 0, -3)
		T.Fill(sm.bar, { 0.04, 0.04, 0.04, 1 })
		local hp = sm.bar:CreateTexture(nil, "ARTWORK")
		hp:SetTexture(T.WHITE)
		hp:SetVertexColor(0.78, 0.16, 0.14, 1)
		hp:SetPoint("TOPLEFT", 1, -1)
		hp:SetSize(72, 8)
		sm.badge = CreateFrame("Frame", nil, box)
		sm.badge:SetSize(16, 16)
		sm.badge.icon = sm.badge:CreateTexture(nil, "OVERLAY")
		sm.badge.icon:SetTexture(MEDIA .. "quest_mark")
		sm.badge.icon:SetAllPoints()
		sm.badge.text = sm.badge:CreateFontString(nil, "OVERLAY")
		T.SetFont(sm.badge.text, 11, true, "OUTLINE")
		sm.badge.text:SetTextColor(1, 1, 1, 1)
		local cap = T.Text(box, 10, C.dim)
		cap:SetPoint("CENTER", box, "TOPLEFT", cx, -82)
		cap:SetJustifyH("CENTER")
		texts[#texts + 1] = { fs = cap, en = caption, size = 10 }
		samples[#samples + 1] = sm
	end
	sample(110, "Murloc Tidehunter", "3/8", "Current quest", true)
	sample(320, "Murloc Warrior", "1/4", "Another quest", false)
	plateUI.previewUpdate = function()
		local db = QL.DB()
		local mode = db.plateColorMode or "status"
		local side = db.plateSide or "left"
		local dx = tonumber(db.plateOffsetX) or 0
		local scale = tonumber(db.plateScale) or 1
		box:SetAlpha(db.nameplates ~= false and 1 or 0.4)
		for _, sm in ipairs(samples) do
			local r, g, b, alpha = C.accent[1], C.accent[2], C.accent[3], 1
			if mode == "status" then
				local c = sm.current and QL.PLATE_CURRENT or QL.PLATE_OTHER
				r, g, b = c[1], c[2], c[3]
			else
				if mode == "custom" and type(db.plateColor) == "table" then
					r, g, b = db.plateColor[1] or 1, db.plateColor[2] or 1, db.plateColor[3] or 1
				elseif mode == "difficulty" then
					local lvl = (QL.Context() or {}).level or 10
					local ok, _, dc = pcall(QL.QuestDifficulty, lvl + (sm.current and 0 or 4), lvl)
					if ok and type(dc) == "table" then r, g, b = dc[1], dc[2], dc[3] end
				end
				if not sm.current then alpha = 0.4 end
			end
			local bd = sm.badge
			bd.icon:SetVertexColor(r, g, b, 1)
			bd:SetAlpha(alpha)
			bd:SetScale(scale)
			bd:ClearAllPoints()
			bd.text:ClearAllPoints()
			if side == "right" then
				bd:SetPoint("LEFT", sm.bar, "RIGHT", 3 + dx, 0)
				bd.text:SetPoint("LEFT", bd, "RIGHT", 2, 0)
			elseif side == "top" then
				bd:SetPoint("BOTTOM", sm.name, "TOP", -10 + dx, 2)
				bd.text:SetPoint("LEFT", bd, "RIGHT", 2, 0)
			else
				bd:SetPoint("RIGHT", sm.bar, "LEFT", -3 + dx, 0)
				bd.text:SetPoint("RIGHT", bd, "LEFT", -2, 0)
			end
			bd.text:SetText(db.plateCount ~= false and sm.counter or "")
		end
	end
	plateUI.previewUpdate()
	return y - 112
end

local function buildPlatePage(y)
	local p = plateUI
	local C = QL.Theme.C
	p.on = check("QuestLineagePlatesOn", 16, y, function(self) QL.Set("nameplates", self:GetChecked() and true or false); refresh() end)
	y = y - 40
	y = buildPlatePreview(y)
	y = groupHeading(y, "Position")
	p.sides, y = radios("QuestLineagePlateSide", PLATE_SIDES, "plateSide", y)
	y = y - 6
	p.offsetLabel = label(y); y = y - 22
	p.offset = slider("QuestLineagePlateOffset", "plateOffsetX", -40, 40, y, p.offsetLabel, { step = 1, text = offsetText, ends = pixels })
	y = y - 44
	y = groupHeading(y, "Look")
	p.colorLabel = text(y, "Colour", 12, C.text, 20)
	y = y - 20
	p.colors, y = radios("QuestLineagePlateColor", PLATE_COLORS, "plateColorMode", y)
	p.swatch = swatch("QuestLineagePlateSwatch", p.colors[4], "plateColor", "plateColorMode")
	y = y - 8
	p.sizeLabel = label(y); y = y - 22
	p.slider = slider("QuestLineagePlateScale", "plateScale", 0.5, 2, y, p.sizeLabel); y = y - 44
	y = groupHeading(y, "What shows")
	p.count = check("QuestLineagePlateCount", 16, y, function(self) QL.Set("plateCount", self:GetChecked() and true or false); refresh() end)
	y = y - 30
	p.droppers = check("QuestLineagePlateDroppers", 16, y, function(self) QL.Set("plateDroppers", self:GetChecked() and true or false); refresh() end)
	return y - 44
end

local function navButton(i, def)
	local T, C = QL.Theme, QL.Theme.C
	local b = CreateFrame("Button", "QuestLineageOptionsPage" .. i, panel)
	b:SetSize(NAV_W - 16, 30)
	b:SetPoint("TOPLEFT", 8, -64 - (i - 1) * 34)
	b.bg = T.Fill(b, { 0, 0, 0, 0 })
	b.bar = b:CreateTexture(nil, "OVERLAY")
	b.bar:SetTexture(T.WHITE)
	b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT")
	b.bar:SetWidth(3)
	T.Gradient(b.bar, "VERTICAL", C.accent2, C.accent)
	b.label = T.Text(b, 12, C.muted, nil, true)
	b.label:SetPoint("LEFT", 14, 0)
	b.pageId, b.title = def.id, def.title
	b:SetScript("OnClick", function(self)
		QL.DB().optionsPage = self.pageId
		showPage(self.pageId)
	end)
	b:SetScript("OnEnter", function(self) if not self.active then T.Color(self.bg, C.rowHover); self.label:SetTextColor(unpack(C.text)) end end)
	b:SetScript("OnLeave", function(self) if not self.active then T.Color(self.bg, { 0, 0, 0, 0 }); self.label:SetTextColor(unpack(C.muted)) end end)
	navButtons[i] = b
	return b
end

local function build()
	local T, C = QL.Theme, QL.Theme.C
	panel = CreateFrame("Frame", "QuestLineageOptionsPanel")
	panel.name = "QuestLineage"

	-- the menu
	local nav = CreateFrame("Frame", nil, panel)
	nav:SetPoint("TOPLEFT"); nav:SetPoint("BOTTOMLEFT")
	nav:SetWidth(NAV_W)
	T.Fill(nav, C.sidebar)
	T.Line(nav, C.line, "RIGHT")
	local logo = nav:CreateTexture(nil, "ARTWORK")
	logo:SetTexture("Interface\\AddOns\\QuestLineage\\Media\\icon")
	logo:SetSize(26, 26)
	logo:SetPoint("TOPLEFT", 12, -14)
	panel.title = T.Text(nav, 15, C.text, nil, true)
	panel.title:SetPoint("LEFT", logo, "RIGHT", 8, 5)
	panel.version = T.Text(nav, 10, C.dim)
	panel.version:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -2)
	for i, def in ipairs(PAGES) do navButton(i, def) end

	-- the page area
	local scroll = T.Scroll(panel)
	scroll:SetPoint("TOPLEFT", NAV_W, -4)
	scroll:SetPoint("BOTTOMRIGHT", -4, 4)
	panel.scroll = scroll
	for _, def in ipairs(PAGES) do
		local page = CreateFrame("Frame", nil, scroll.child)
		page:SetPoint("TOPLEFT")
		page:SetWidth(CONTENT_W)
		page:SetHeight(1)
		root = page
		text(-14, def.title, 16, C.text, 16, true)
		text(-36, def.hint, 11, C.muted, 16)
		local y = -66
		if def.id == "arrow" then
			y = buildArrowPage(y)
		elseif def.id == "plates" then
			y = buildPlatePage(y)
		else
			y = buildRows(def.id, y)
			if def.id == "general" then y = buildUnitBlock(y); y = buildThemeBlock(y) end
			if def.id == "where" then y = buildBarExtras(y) end
		end
		endCard(y)
		page.contentHeight = -y + 20
		page:SetHeight(page.contentHeight)
		page:Hide()
		pages[def.id] = page
	end
	scroll.child:SetWidth(CONTENT_W)

	panel:SetScript("OnShow", function()
		refresh()
		if QL.ArrowPreview then QL.ArrowPreview(true) end
	end)
	panel:SetScript("OnHide", function()
		if QL.ArrowPreview then QL.ArrowPreview(false) end
	end)

	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, "QuestLineage")
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

function QL.OpenOptions(pageId)
	if not panel then return end
	if pageId then QL.DB().optionsPage = pageId end
	if category and Settings and Settings.OpenToCategory then
		local id = category.GetID and category:GetID() or category.ID
		Settings.OpenToCategory(id)
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

QL.Event("PLAYER_LOGIN", function()
	local ok, err = pcall(build)
	if not ok then QL.Debug("options: " .. tostring(err)) end
end)
QL.On("SETTING_CHANGED", function() if panel and panel:IsShown() then refresh() end end)
