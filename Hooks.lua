-- Where the chain shows up in the game's own windows:
--   1. the quest log: a Chain button on the selected quest (setting logButton)
--   2. NPC tooltips: "Chain 2/5: <quest> · next: <quest>" for the chained quests the NPC gives (tooltip)
--   3. the quest offer window: a strip under it with a Chain button and what taking the quest
--      closes for good (detailButton)
-- Only post-hooks (hooksecurefunc, HookScript, TooltipDataProcessor); nothing of the game's is replaced.
-- These frames are not verified on every client build, so every lookup is guarded.

local _, QL = ...

local function L(s) return QL.L(s) end

local function hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

-- "Chain 2/5 · next: Second Steps" for a quest, or nil when it has no chain (or the index is
-- still being built: then the build starts and the next hover has it).
function QL.SummaryText(questId, ctx)
	if QL.DataStatus() ~= "ok" then return nil end
	if not QL.IndexReady() then QL.WhenIndexed(); return nil end
	local s = QL.ChainSummary(questId, ctx or QL.Context())
	if not s then return nil end
	local text = L("Chain %d/%d"):format(s.index, s.total)
	if s.nextId then
		text = text .. " · " .. L("next: ") .. QL.QuestTitle(s.nextId)
	elseif s.index >= s.total then
		text = text .. " · " .. L("last step")
	end
	return text
end

local function hasChain(questId)
	if not QL.IndexReady() then return true end -- unknown yet: offer the button, the window builds the index
	return QL.ChainSummary(questId, QL.Context()) ~= nil
end

local function makeButton(parent, name)
	local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
	b:SetSize(80, 22)
	b:SetScript("OnEnter", function(self)
		if not self.questId then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L("Show this quest's chain"), 1, 0.82, 0)
		local text = QL.SummaryText(self.questId)
		if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function(self)
		if self.questId then QL.Open(self.questId) end
	end)
	return b
end

-- 1. Quest log ------------------------------------------------------------------

local logButton

local function showLogButton(parent, questId)
	if not QL.DB().logButton or type(questId) ~= "number" or questId <= 0 or not parent then
		if logButton then logButton:Hide() end
		return
	end
	if not logButton then
		logButton = makeButton(parent, "QuestLineageLogButton")
	end
	if logButton:GetParent() ~= parent then logButton:SetParent(parent) end
	logButton:ClearAllPoints()
	logButton:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -6)
	logButton:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)
	logButton:SetText(L("Chain"))
	logButton.questId = questId
	logButton:SetShown(hasChain(questId))
end

local function hookQuestLog()
	-- Mainline-style quest log (QuestMapFrame)
	if QuestMapFrame_ShowQuestDetails and QuestMapFrame then
		hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questId)
			local details = QuestMapFrame.DetailsFrame
			pcall(showLogButton, details, questId)
		end)
	end
	-- Classic-style quest log (QuestLogFrame)
	if QuestLog_Update and QuestLogFrame and GetQuestLogSelection and GetQuestLogTitle then
		hooksecurefunc("QuestLog_Update", function()
			local index = GetQuestLogSelection()
			local questId = index and index > 0 and select(8, GetQuestLogTitle(index)) or nil
			local parent = QuestLogDetailScrollFrame or QuestLogFrame
			pcall(showLogButton, parent, questId)
		end)
	end
end

-- 2. NPC tooltips ---------------------------------------------------------------

local MAX_LINES = 3

local function npcIdFromGuid(guid)
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "Creature" then return nil end
	return tonumber(id)
end

local function addNpcLines(tooltip, guid)
	if not QL.DB().tooltip then return 0 end
	local npcId = npcIdFromGuid(guid)
	if not npcId then return 0 end
	local starts = QL.Ids(QL.N(npcId, "questStarts"))
	if #starts == 0 then return 0 end
	local ctx = QL.Context()
	local added = 0
	for _, questId in ipairs(starts) do
		if added >= MAX_LINES then break end
		local status = QL.NodeStatus(questId, ctx)
		if status ~= "done" and status ~= "other" and status ~= "closed" then
			local text = QL.SummaryText(questId, ctx)
			if text then
				local xp = QL.QuestXPAt(questId, ctx.level)
				local xpText = xp and ("  " .. hex(0.24, 0.84, 0.78) .. QL.XPText(xp) .. "|r") or ""
				tooltip:AddLine(hex(0.5, 0.83, 1) .. QL.QuestTitle(questId) .. "|r  " .. text .. xpText, 0.85, 0.85, 0.85, true)
				added = added + 1
			end
		end
	end
	return added
end

local function hookTooltips()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
			if tooltip ~= GameTooltip then return end
			local guid = data and data.guid
			if not guid and UnitGUID then guid = UnitGUID("mouseover") end
			local ok, err = pcall(addNpcLines, tooltip, guid)
			if not ok then QL.Debug("tooltip: " .. tostring(err)) end
		end)
	elseif GameTooltip and GameTooltip.HookScript then
		GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
			local _, unit = tooltip:GetUnit()
			local guid = unit and UnitGUID and UnitGUID(unit)
			local ok, added = pcall(addNpcLines, tooltip, guid)
			if ok and added and added > 0 then tooltip:Show() end
		end)
	end
end

-- 3. Quest offer window -----------------------------------------------------------

local strip

local function buildStrip()
	strip = CreateFrame("Frame", "QuestLineageOfferStrip", QuestFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
	strip:SetPoint("TOPLEFT", QuestFrame, "BOTTOMLEFT", 0, -2)
	strip:SetPoint("TOPRIGHT", QuestFrame, "BOTTOMRIGHT", 0, -2)
	strip:SetHeight(40)
	if strip.SetBackdrop then
		strip:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		strip:SetBackdropColor(0.05, 0.06, 0.08, 0.92)
		strip:SetBackdropBorderColor(0.3, 0.45, 0.6, 0.9)
	end
	strip.button = makeButton(strip, "QuestLineageOfferButton")
	strip.button:SetPoint("TOPRIGHT", -8, -8)
	strip.text = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	strip.text:SetPoint("TOPLEFT", 10, -10)
	strip.text:SetPoint("RIGHT", strip.button, "LEFT", -8, 0)
	strip.text:SetJustifyH("LEFT")
	strip.text:SetJustifyV("TOP")
	strip:Hide()
	QuestFrame:HookScript("OnHide", function() strip:Hide() end)
end

local function showOffer()
	if not QuestFrame or not GetQuestID then return end
	if not QL.DB().detailButton then
		if strip then strip:Hide() end
		return
	end
	local questId = GetQuestID()
	if type(questId) ~= "number" or questId <= 0 or not QL.QuestExists(questId) then
		if strip then strip:Hide() end
		return
	end
	if not strip then buildStrip() end
	local ctx = QL.Context()
	local lines = {}
	local xp = QL.QuestXPAt(questId, ctx.level)
	if xp then
		lines[#lines + 1] = hex(0.24, 0.84, 0.78) .. QL.XPText(xp) .. "|r  " .. hex(0.6, 0.62, 0.68) .. QL.GainText(QL.LevelGain(xp)) .. "|r"
	end
	local summary = QL.SummaryText(questId, ctx)
	if summary then lines[#lines + 1] = summary end
	local closes = {}
	for _, e in ipairs(QL.Ids(QL.Q(questId, "exclusiveTo"))) do
		if not ctx.done[e] then closes[#closes + 1] = QL.QuestTitle(e) end
	end
	if #closes > 0 then
		lines[#lines + 1] = hex(1, 0.4, 0.4) .. L("Taking this quest closes for good: ") .. table.concat(closes, ", ") .. "|r"
	end
	local target = QL.Ids(QL.Q(questId, "breadcrumbForQuestId"))
	if #target > 0 then
		lines[#lines + 1] = hex(0.75, 0.75, 0.75) .. L("This is a breadcrumb to: ") .. QL.QuestTitle(target[1]) .. "|r"
	end
	if #lines == 0 and not hasChain(questId) then
		strip:Hide()
		return
	end
	QL.SetFont(strip.text, 11)
	strip.text:SetText(table.concat(lines, "\n"))
	strip.button:SetText(L("Chain"))
	strip.button.questId = questId
	strip.button:SetShown(hasChain(questId))
	strip:SetHeight(math.max(38, (strip.text:GetStringHeight() or 12) + 20))
	strip:Show()
end

QL.Event("QUEST_DETAIL", function() pcall(showOffer) end)
QL.Event("QUEST_FINISHED", function() if strip then strip:Hide() end end)

QL.Event("PLAYER_LOGIN", function()
	local ok, err = pcall(hookQuestLog)
	if not ok then QL.Debug("quest log hook: " .. tostring(err)) end
	ok, err = pcall(hookTooltips)
	if not ok then QL.Debug("tooltip hook: " .. tostring(err)) end
end)

-- Settings that change what the hooks show take effect on the next hover or window.
QL.On("SETTING_CHANGED", function(key)
	if key == "logButton" and logButton and not QL.DB().logButton then logButton:Hide() end
	if key == "detailButton" and strip and not QL.DB().detailButton then strip:Hide() end
end)
