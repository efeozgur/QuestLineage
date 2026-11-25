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

local panel, root, category
local checks = {}
local arrowUI, plateUI = {}, {}
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
	{ key = "quickBar", page = "arrow", group = "\"Where?\" bar",
		label = "\"Where?\" bar", note = "Icons that point the arrow at the nearest trainer, vendor or service." },
}

local PAGES = {
	{ id = "general", title = "General", hint = "Language, notifications and the addon's buttons." },
	{ id = "tracking", title = "Quest tracking", hint = "The current quest window, quests offered by NPCs, tooltips." },
	{ id = "maps", title = "Maps", hint = "What QuestLineage draws on the minimap and the world map." },
	{ id = "arrow", title = "Arrow", hint = "The arrow's look and the \"Where?\" bar under it." },
	{ id = "plates", title = "Nameplates", hint = "A quest badge and counter beside the creatures your quests need." },
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

-- A group heading: small accent capitals with a thin line beside them.
local function groupHeading(y, english)
	local T, C = QL.Theme, QL.Theme.C
	local fs = text(y, english, 10, C.accent, 16, true)
	fs:SetPoint("RIGHT", root, "LEFT", 300, 0)
	local line = root:CreateTexture(nil, "BORDER")
	line:SetTexture(T.WHITE)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 16, y - 16)
	line:SetPoint("RIGHT", root, "RIGHT", -16, 0)
	T.Color(line, C.lineSoft)
	return y - 26
end

-- the old helpers the Arrow and Nameplates pages use
local function label(y)
	local fs = QL.Theme.Text(root, 12, QL.Theme.C.text)
	fs:SetPoint("TOPLEFT", 20, y)
	return fs
end

local function check(name, x, y, onClick)
	local c = CreateFrame("CheckButton", name, root, "UICheckButtonTemplate")
	c:SetPoint("TOPLEFT", x, y)
	c:SetScript("OnClick", onClick)
	return c
end

-- Radio-like checks for one setting: { {mode, label}, ... }
local function radios(prefix, list, key, y)
	local out = {}
	for i, m in ipairs(list) do
		out[i] = check(prefix .. i, 26, y, function() QL.Set(key, m.mode); QL.RefreshOptions() end)
		y = y - 26
	end
	return out, y
end

-- A colour swatch beside a check: picking a colour also selects "custom" for modeKey.
local function swatch(name, beside, colorKey, modeKey)
	local T = QL.Theme
	local sw = CreateFrame("Button", name, root)
	sw:SetSize(22, 22)
	sw:SetPoint("LEFT", beside, "RIGHT", 220, 0)
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
	track:SetVertexColor(1, 1, 1, 0.18)
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	s.low = T.Text(root, 10, T.C.dim)
	s.low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2)
	s.low:SetText(ends(min))
	s.high = T.Text(root, 10, T.C.dim)
	s.high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2)
	s.high:SetText(ends(max))
	s:SetScript("OnValueChanged", function(self, v)
		if self.updating then return end
		v = math.floor(math.max(min, math.min(max, v or 1)) / step + 0.5) * step
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
		panel.scroll:SetVerticalScroll(0)
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

	-- arrow
	local a = arrowUI
	if a.colorLabel then
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
			p.colors[i]:SetChecked((db.plateColorMode or "accent") == m.mode)
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
					{ step = 1, text = function(v) return L(sl.text):format(math.floor(v + 0.5)) end, ends = function(v) return tostring(v) end })
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
			c.note = text(y - 24, row.note, 11, QL.Theme.C.muted, x + 30)
			checks[i] = c
			y = y - 52
			end
		end
	end
	return y
end

local function buildArrowPage(y)
	local a = arrowUI
	y = groupHeading(y, "Look")
	text(y, "The arrow turns here as a preview while the settings are open. Drag it to move it.", 11, QL.Theme.C.muted, 20)
	y = y - 30
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

local function buildPlatePage(y)
	local p = plateUI
	local C = QL.Theme.C
	p.on = check("QuestLineagePlatesOn", 16, y, function(self) QL.Set("nameplates", self:GetChecked() and true or false); refresh() end)
	y = y - 40
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
	p.swatch = swatch("QuestLineagePlateSwatch", p.colors[3], "plateColor", "plateColorMode")
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
		end
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
