-- Settings page: in the game's Settings > AddOns list when the client has the Settings API,
-- else in the old Interface Options. `/ql options` opens it.

local _, QL = ...

local function L(s) return QL.L(s) end

local panel, category
local checks = {}

local ROWS = {
	{ key = "lang", label = "Use Turkish (needs WoWTR)", note = "Quest titles, objectives and the interface in Turkish, from WoWTR.", lang = true },
	{ key = "minimapButton", label = "Button on the minimap" },
	{ key = "tooltip", label = "Chain line on NPC tooltips" },
	{ key = "logButton", label = "Chain button in the quest log" },
	{ key = "detailButton", label = "Chain button and warnings on the quest offer window" },
	{ key = "hideOther", label = "Hide quests your race or class can never take" },
}

local function labelOf(check)
	return check.Text or check.text or (check.GetName and check:GetName() and _G[check:GetName() .. "Text"])
end

local function refresh()
	if not panel then return end
	QL.SetFont(panel.title, 16)
	panel.title:SetText(L("Quest Lineage") .. "  |cff888888" .. QL.version .. "|r")
	for i, row in ipairs(ROWS) do
		local c = checks[i]
		local text = labelOf(c)
		if text then
			QL.SetFont(text, 12)
			text:SetText(L(row.label))
		end
		if row.lang then
			c:SetChecked(QL.DB().lang == "tr")
			c:SetEnabled(QL.HasWoWTR())
			if text then text:SetTextColor(QL.HasWoWTR() and 1 or 0.5, QL.HasWoWTR() and 1 or 0.5, QL.HasWoWTR() and 1 or 0.5) end
			QL.SetFont(c.note, 11)
			c.note:SetText(L(row.note))
		else
			c:SetChecked(QL.DB()[row.key] and true or false)
		end
	end
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
	panel:SetScript("OnShow", refresh)

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
