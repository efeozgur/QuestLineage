-- Settings page: in the game's Settings > AddOns list when the client has the Settings API,
-- else in the old Interface Options. `/ql options` opens it.
--
-- The page scrolls (the game's settings window does not scroll a long canvas by itself):
--   General      on/off toggles
--   Arrow        colour (by direction / the theme's / my own, from the game's colour picker),
--                size, glow, position reset; while the page is open the arrow shows a turning
--                preview (QL.ArrowPreview)
--   Nameplates   on/off, where the badge sits (left / right / above), colour (the theme's /
--                the quest's difficulty / my own), size, the counter, item droppers too

local _, QL = ...

local function L(s) return QL.L(s) end

local panel, root, category
local checks = {}
local arrowUI, plateUI = {}, {}

local ROWS = {
	{ key = "lang", label = "Use Turkish (needs WoWTR)", note = "Quest titles, objectives and the interface in Turkish, from WoWTR.", lang = true },
	{ key = "minimapButton", label = "Button on the minimap" },
	{ key = "mapRoute", label = "Route on the world map" },
	{ key = "quickBar", label = "\"Where?\" bar under the arrow (trainers, vendors, services)" },
	{ key = "toasts", label = "Messages in a notification window (off: in the chat)" },
	{ key = "currentQuest", label = "Current quest window (stage and objectives)" },
	{ key = "tooltip", label = "Chain line on NPC tooltips" },
	{ key = "logButton", label = "Chain button in the quest log" },
	{ key = "detailButton", label = "Chain button and warnings on the quest offer window" },
	{ key = "hideOther", label = "Hide quests your race or class can never take" },
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

-- Building blocks ---------------------------------------------------------------------------------

local function heading(y)
	local fs = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("TOPLEFT", 16, y)
	return fs
end

local function note(y)
	local fs = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	fs:SetPoint("TOPLEFT", 20, y)
	return fs
end

local function label(y)
	local fs = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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
	local text = opts.text or sizeText
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
	s.low = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	s.low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2)
	s.low:SetText(ends(min))
	s.high = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	s.high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2)
	s.high:SetText(ends(max))
	s:SetScript("OnValueChanged", function(self, v)
		if self.updating then return end
		v = math.floor(math.max(min, math.min(max, v or 1)) / step + 0.5) * step
		if v ~= QL.DB()[key] then
			QL.Set(key, v)
			sizeLabel:SetText(text(v))
		end
	end)
	s.text = text
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

local function refresh()
	if not panel then return end
	local db = QL.DB()
	QL.SetFont(root.title, 16)
	root.title:SetText(L("Quest Lineage") .. "  |cff888888" .. QL.version .. "|r")
	for i, row in ipairs(ROWS) do
		local c = checks[i]
		local text = setLabel(c, L(row.label))
		if row.lang then
			c:SetChecked(db.lang == "tr")
			c:SetEnabled(QL.HasWoWTR())
			local v = QL.HasWoWTR() and 1 or 0.5
			if text then text:SetTextColor(v, v, v) end
			QL.SetFont(c.note, 11)
			c.note:SetText(L(row.note))
		else
			c:SetChecked(db[row.key] and true or false)
		end
	end

	-- arrow
	local a = arrowUI
	if a.heading then
		QL.SetFont(a.heading, 14)
		a.heading:SetText(L("Arrow"))
		QL.SetFont(a.hint, 11)
		a.hint:SetText(L("The arrow turns here as a preview while this page is open. Drag it to move it."))
		QL.SetFont(a.colorLabel, 12)
		a.colorLabel:SetText(L("Colour"))
		for i, m in ipairs(ARROW_COLORS) do
			setLabel(a.modes[i], L(m.label))
			a.modes[i]:SetChecked((db.arrowColorMode or "direction") == m.mode)
		end
		local c = type(db.arrowColor) == "table" and db.arrowColor or { 1, 1, 1 }
		a.swatch.fill:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
		local scale = tonumber(db.arrowScale) or 1
		setSlider(a.slider, scale)
		QL.SetFont(a.sizeLabel, 12)
		a.sizeLabel:SetText(L("Size: %d%%"):format(math.floor(scale * 100 + 0.5)))
		setLabel(a.glow, L("Glow behind the arrow"))
		a.glow:SetChecked(db.arrowGlow ~= false)
		a.reset:SetText(L("Reset position"))
		if a.reset.GetFontString and a.reset:GetFontString() then QL.SetFont(a.reset:GetFontString(), 12) end
	end

	-- nameplates
	local p = plateUI
	if p.heading then
		QL.SetFont(p.heading, 14)
		p.heading:SetText(L("Nameplates"))
		QL.SetFont(p.hint, 11)
		p.hint:SetText(L("A quest badge and counter beside the creatures your quests need."))
		setLabel(p.on, L("Quest counters on nameplates"))
		p.on:SetChecked(db.nameplates ~= false)
		QL.SetFont(p.sideLabel, 12)
		p.sideLabel:SetText(L("Position"))
		for i, m in ipairs(PLATE_SIDES) do
			setLabel(p.sides[i], L(m.label))
			p.sides[i]:SetChecked((db.plateSide or "left") == m.mode)
		end
		QL.SetFont(p.colorLabel, 12)
		p.colorLabel:SetText(L("Colour"))
		for i, m in ipairs(PLATE_COLORS) do
			setLabel(p.colors[i], L(m.label))
			p.colors[i]:SetChecked((db.plateColorMode or "accent") == m.mode)
		end
		local c = type(db.plateColor) == "table" and db.plateColor or { 1, 1, 1 }
		p.swatch.fill:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
		local scale = tonumber(db.plateScale) or 1
		setSlider(p.slider, scale)
		QL.SetFont(p.sizeLabel, 12)
		p.sizeLabel:SetText(L("Size: %d%%"):format(math.floor(scale * 100 + 0.5)))
		local dx = tonumber(db.plateOffsetX) or 0
		setSlider(p.offset, dx)
		QL.SetFont(p.offsetLabel, 12)
		p.offsetLabel:SetText(offsetText(dx))
		setLabel(p.count, L("Show the counter (3/8)"))
		p.count:SetChecked(db.plateCount ~= false)
		setLabel(p.droppers, L("Also on creatures that drop an item you collect"))
		p.droppers:SetChecked(db.plateDroppers ~= false)
	end
end
QL.RefreshOptions = refresh

-- Sections -----------------------------------------------------------------------------------------

local function buildArrowSection(y)
	local a = arrowUI
	a.heading = heading(y); y = y - 24
	a.hint = note(y); y = y - 22
	a.colorLabel = label(y); y = y - 20
	a.modes, y = radios("QuestLineageArrowMode", ARROW_COLORS, "arrowColorMode", y)
	a.swatch = swatch("QuestLineageArrowSwatch", a.modes[3], "arrowColor", "arrowColorMode")
	y = y - 8
	a.sizeLabel = label(y); y = y - 22
	a.slider = slider("QuestLineageArrowScale", "arrowScale", 0.5, 2, y, a.sizeLabel); y = y - 40
	a.glow = check("QuestLineageArrowGlow", 16, y, function(self) QL.Set("arrowGlow", self:GetChecked() and true or false); refresh() end)
	y = y - 36
	local r = CreateFrame("Button", "QuestLineageArrowReset", root, "UIPanelButtonTemplate")
	r:SetSize(160, 24)
	r:SetPoint("TOPLEFT", 20, y)
	r:SetScript("OnClick", function()
		if QL.ResetArrowPosition then QL.ResetArrowPosition() end
		if QL.ResetQuickBarPosition then QL.ResetQuickBarPosition() end
	end)
	a.reset = r
	return y - 40
end

local function buildPlateSection(y)
	local p = plateUI
	p.heading = heading(y); y = y - 24
	p.hint = note(y); y = y - 22
	p.on = check("QuestLineagePlatesOn", 16, y, function(self) QL.Set("nameplates", self:GetChecked() and true or false); refresh() end)
	y = y - 34
	p.sideLabel = label(y); y = y - 20
	p.sides, y = radios("QuestLineagePlateSide", PLATE_SIDES, "plateSide", y)
	y = y - 8
	p.colorLabel = label(y); y = y - 20
	p.colors, y = radios("QuestLineagePlateColor", PLATE_COLORS, "plateColorMode", y)
	p.swatch = swatch("QuestLineagePlateSwatch", p.colors[3], "plateColor", "plateColorMode")
	y = y - 8
	p.sizeLabel = label(y); y = y - 22
	p.slider = slider("QuestLineagePlateScale", "plateScale", 0.5, 2, y, p.sizeLabel); y = y - 40
	p.offsetLabel = label(y); y = y - 22
	p.offset = slider("QuestLineagePlateOffset", "plateOffsetX", -40, 40, y, p.offsetLabel, { step = 1, text = offsetText, ends = pixels })
	y = y - 40
	p.count = check("QuestLineagePlateCount", 16, y, function(self) QL.Set("plateCount", self:GetChecked() and true or false); refresh() end)
	y = y - 30
	p.droppers = check("QuestLineagePlateDroppers", 16, y, function(self) QL.Set("plateDroppers", self:GetChecked() and true or false); refresh() end)
	return y - 40
end

local function build()
	local T = QL.Theme
	panel = CreateFrame("Frame", "QuestLineageOptionsPanel")
	panel.name = "QuestLineage"
	-- everything sits on a scroll child: the page is longer than the settings window
	local scroll = T.Scroll(panel)
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -4, 4)
	root = scroll.child
	root:SetWidth(560)
	root.title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	root.title:SetPoint("TOPLEFT", 16, -12)
	local y = -52
	for i, row in ipairs(ROWS) do
		local c = check("QuestLineageOption" .. i, 16, y, function(self)
			if row.lang then
				QL.Set("lang", self:GetChecked() and "tr" or "en")
			else
				QL.Set(row.key, self:GetChecked() and true or false)
			end
			refresh()
		end)
		if row.note then
			c.note = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			c.note:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 30, 2)
			y = y - 16
		end
		checks[i] = c
		y = y - 34
	end
	y = y - 12
	y = buildArrowSection(y)
	y = buildPlateSection(y)
	scroll:SetContentHeight(-y + 20)
	panel.scroll = scroll
	panel:SetScript("OnShow", function()
		refresh()
		scroll:SetContentHeight(-y + 20)
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

function QL.OpenOptions()
	if not panel then return end
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
