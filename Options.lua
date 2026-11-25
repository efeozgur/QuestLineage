-- Settings page: in the game's Settings > AddOns list when the client has the Settings API,
-- else in the old Interface Options. `/ql options` opens it.
--
-- General toggles, then the Arrow section: colour (by direction / the theme's accent / a colour
-- of your own, picked with the game's colour picker), size, glow, and a position reset. While
-- the page is open the arrow shows a turning preview (QL.ArrowPreview), so changes are visible.

local _, QL = ...

local function L(s) return QL.L(s) end

local panel, category
local checks = {}
local arrowUI = {}

local ROWS = {
	{ key = "lang", label = "Use Turkish (needs WoWTR)", note = "Quest titles, objectives and the interface in Turkish, from WoWTR.", lang = true },
	{ key = "minimapButton", label = "Button on the minimap" },
	{ key = "mapRoute", label = "Route on the world map" },
	{ key = "tooltip", label = "Chain line on NPC tooltips" },
	{ key = "logButton", label = "Chain button in the quest log" },
	{ key = "detailButton", label = "Chain button and warnings on the quest offer window" },
	{ key = "hideOther", label = "Hide quests your race or class can never take" },
}

local COLOR_MODES = {
	{ mode = "direction", label = "By direction (ahead, to the side, behind)" },
	{ mode = "accent", label = "The theme's colour" },
	{ mode = "custom", label = "My own colour" },
}

local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.5, 2, 0.05

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

local function round(v)
	return math.floor(v / SCALE_STEP + 0.5) * SCALE_STEP
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

local function refresh()
	if not panel then return end
	local db = QL.DB()
	QL.SetFont(panel.title, 16)
	panel.title:SetText(L("Quest Lineage") .. "  |cff888888" .. QL.version .. "|r")
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
	if not a.heading then return end
	QL.SetFont(a.heading, 14)
	a.heading:SetText(L("Arrow"))
	QL.SetFont(a.colorLabel, 12)
	a.colorLabel:SetText(L("Colour"))
	for i, m in ipairs(COLOR_MODES) do
		setLabel(a.modes[i], L(m.label))
		a.modes[i]:SetChecked((db.arrowColorMode or "direction") == m.mode)
	end
	local c = type(db.arrowColor) == "table" and db.arrowColor or { 1, 1, 1 }
	a.swatch.fill:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
	local scale = tonumber(db.arrowScale) or 1
	a.slider.updating = true
	a.slider:SetValue(scale)
	a.slider.updating = nil
	QL.SetFont(a.sizeLabel, 12)
	a.sizeLabel:SetText(L("Size: %d%%"):format(math.floor(scale * 100 + 0.5)))
	setLabel(a.glow, L("Glow behind the arrow"))
	a.glow:SetChecked(db.arrowGlow ~= false)
	a.reset:SetText(L("Reset position"))
	if a.reset.GetFontString and a.reset:GetFontString() then QL.SetFont(a.reset:GetFontString(), 12) end
	QL.SetFont(a.hint, 11)
	a.hint:SetText(L("The arrow turns here as a preview while this page is open. Drag it to move it."))
end
QL.RefreshOptions = refresh

local function buildArrowSection(y)
	local T = QL.Theme
	local a = arrowUI
	a.heading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	a.heading:SetPoint("TOPLEFT", 16, y)
	y = y - 24
	a.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	a.hint:SetPoint("TOPLEFT", 20, y)
	y = y - 22

	a.colorLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	a.colorLabel:SetPoint("TOPLEFT", 20, y)
	y = y - 20
	a.modes = {}
	for i, m in ipairs(COLOR_MODES) do
		local c = CreateFrame("CheckButton", "QuestLineageArrowMode" .. i, panel, "UICheckButtonTemplate")
		c:SetPoint("TOPLEFT", 26, y)
		c:SetScript("OnClick", function()
			QL.Set("arrowColorMode", m.mode)
			refresh()
		end)
		a.modes[i] = c
		if m.mode == "custom" then
			-- the swatch: click to pick the colour (choosing one also selects this mode)
			local sw = CreateFrame("Button", "QuestLineageArrowSwatch", panel)
			sw:SetSize(22, 22)
			sw:SetPoint("LEFT", c, "RIGHT", 220, 0)
			sw.fill = sw:CreateTexture(nil, "ARTWORK")
			sw.fill:SetTexture(T.WHITE)
			sw.fill:SetPoint("TOPLEFT", 2, -2); sw.fill:SetPoint("BOTTOMRIGHT", -2, 2)
			T.Fill(sw, { 0.8, 0.8, 0.8, 1 }, "BACKGROUND")
			sw:SetScript("OnClick", function()
				local cur = type(QL.DB().arrowColor) == "table" and QL.DB().arrowColor or { 1, 1, 1 }
				pickColor(cur[1] or 1, cur[2] or 1, cur[3] or 1, function(r, g, b)
					QL.DB().arrowColorMode = "custom"
					QL.Set("arrowColor", { r, g, b }) -- a new table: never write into the defaults
					refresh()
				end)
			end)
			sw:SetScript("OnEnter", function(self)
				local tip = QL.Tip()
				tip:SetOwner(self, "ANCHOR_RIGHT")
				tip:AddLine(L("Pick a colour"), 1, 1, 1)
				tip:Show()
			end)
			sw:SetScript("OnLeave", function() QL.Tip():Hide() end)
			a.swatch = sw
		end
		y = y - 26
	end
	y = y - 8

	a.sizeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	a.sizeLabel:SetPoint("TOPLEFT", 20, y)
	y = y - 22
	local s = CreateFrame("Slider", "QuestLineageArrowScale", panel)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(240, 16)
	s:SetPoint("TOPLEFT", 26, y)
	s:SetMinMaxValues(SCALE_MIN, SCALE_MAX)
	s:SetValueStep(SCALE_STEP)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:EnableMouse(true)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetTexture(T.WHITE)
	track:SetPoint("LEFT"); track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetVertexColor(1, 1, 1, 0.18)
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	s.low = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	s.low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2)
	s.low:SetText(("%d%%"):format(SCALE_MIN * 100))
	s.high = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	s.high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2)
	s.high:SetText(("%d%%"):format(SCALE_MAX * 100))
	s:SetScript("OnValueChanged", function(self, v)
		if self.updating then return end
		v = round(math.max(SCALE_MIN, math.min(SCALE_MAX, v or 1)))
		if v ~= QL.DB().arrowScale then
			QL.Set("arrowScale", v)
			a.sizeLabel:SetText(L("Size: %d%%"):format(math.floor(v * 100 + 0.5)))
		end
	end)
	a.slider = s
	y = y - 40

	local g = CreateFrame("CheckButton", "QuestLineageArrowGlow", panel, "UICheckButtonTemplate")
	g:SetPoint("TOPLEFT", 16, y)
	g:SetScript("OnClick", function(self) QL.Set("arrowGlow", self:GetChecked() and true or false); refresh() end)
	a.glow = g
	y = y - 36

	local r = CreateFrame("Button", "QuestLineageArrowReset", panel, "UIPanelButtonTemplate")
	r:SetSize(160, 24)
	r:SetPoint("TOPLEFT", 20, y)
	r:SetScript("OnClick", function() if QL.ResetArrowPosition then QL.ResetArrowPosition() end end)
	a.reset = r
	return y - 30
end

local function build()
	panel = CreateFrame("Frame")
	panel.name = "QuestLineage"
	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.title:SetPoint("TOPLEFT", 16, -16)
	local y = -56
	for i, row in ipairs(ROWS) do
		local c = CreateFrame("CheckButton", "QuestLineageOption" .. i, panel, "UICheckButtonTemplate")
		c:SetPoint("TOPLEFT", 16, y)
		c:SetScript("OnClick", function(self)
			if row.lang then
				QL.Set("lang", self:GetChecked() and "tr" or "en")
			else
				QL.Set(row.key, self:GetChecked() and true or false)
			end
			refresh()
		end)
		if row.note then
			c.note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			c.note:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 30, 2)
			y = y - 16
		end
		checks[i] = c
		y = y - 34
	end
	y = y - 12
	buildArrowSection(y)
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
