-- The quest card: when an NPC offers a quest (QUEST_DETAIL), QuestLineage's own page for it opens
-- beside the game's quest window, or in its place:
--   hero      the NPC you are talking to in 3D over the indigo gradient, "NEW QUEST", the title in
--             its difficulty colour, level / dungeon tags, XP and its share of a level
--   sections  the objective (the game's live text, Turkish via WoWTR), what to do (database tasks
--             with distances), the story (folded), rewards (item tiles with quality borders, money),
--             the chain ("link 2 of 5 · 3,400 XP"), warnings (quests this closes, breadcrumbs)
--   footer    Accept (AcceptQuest), Decline (DeclineQuest), Chain (opens the main window)
--
-- Settings: questCard (on), hideGameQuestFrame (the game's window moved off screen and made
-- invisible while the card shows: Hide() would end the NPC conversation through its OnHide),
-- openOnAccept (the main window opens on the quest you accept), questCardPoint (where the card
-- sits when the game's window is hidden). Turn-in screens are left to the game.
--
--   QL.ShowQuestCard(id)  QL.HideQuestCard()  QL.OfferWarnings(id, ctx)  QL.questCard (the frame)

local _, QL = ...
local L = QL.L

local MEDIA = "Interface\\AddOns\\QuestLineage\\Media\\"
local W, HERO_H, MAX_H = 360, 128, 600
local QUALITY = {
	[0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
	[4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}

local card

local function hex(c) return QL.Theme.Hex(c) end

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f = pcall(fn, ...)
	if ok then return a, b, c, d, e, f end
	return nil
end

-- Warnings about taking a quest: the quests it closes for good, the quest it is a breadcrumb to.
function QL.OfferWarnings(id, ctx)
	local out = {}
	if not QL.QuestExists(id) then return out end
	ctx = ctx or QL.Context()
	local closes = {}
	for _, e in ipairs(QL.Ids(QL.Q(id, "exclusiveTo"))) do
		if not ctx.done[e] then closes[#closes + 1] = QL.QuestTitle(e) end
	end
	if #closes > 0 then
		out[#out + 1] = { danger = true, text = L("Taking this quest closes for good: ") .. table.concat(closes, ", ") }
	end
	local target = QL.Ids(QL.Q(id, "breadcrumbForQuestId"))
	if #target > 0 then
		out[#out + 1] = { text = L("This is a breadcrumb to: ") .. QL.QuestTitle(target[1]) }
	end
	return out
end

-- The game's quest window ------------------------------------------------------------------------

local hiddenGame -- the game's window's saved state while we keep it out of sight

local function hideGameFrame()
	if not QuestFrame then return end
	if not hiddenGame then
		local points = {}
		for i = 1, (QuestFrame.GetNumPoints and QuestFrame:GetNumPoints() or 0) do
			points[i] = { QuestFrame:GetPoint(i) }
		end
		hiddenGame = { alpha = QuestFrame:GetAlpha() or 1, mouse = QuestFrame.IsMouseEnabled and QuestFrame:IsMouseEnabled(), points = points }
	end
	-- applied again each time: the game's panel layout may have put it back
	QuestFrame:SetAlpha(0)
	if QuestFrame.EnableMouse then QuestFrame:EnableMouse(false) end
	-- off screen as well, so its buttons cannot be clicked while invisible
	QuestFrame:ClearAllPoints()
	QuestFrame:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -4000, 0)
	QL.gameQuestFrameHidden = true
end

local function restoreGameFrame()
	if not hiddenGame or not QuestFrame then return end
	local s = hiddenGame
	hiddenGame = nil
	QuestFrame:SetAlpha(s.alpha or 1)
	if QuestFrame.EnableMouse then QuestFrame:EnableMouse(s.mouse ~= false) end
	QuestFrame:ClearAllPoints()
	if #s.points > 0 then
		for _, p in ipairs(s.points) do QuestFrame:SetPoint(unpack(p)) end
	else
		QuestFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
	end
	QL.gameQuestFrameHidden = false
end

-- Building --------------------------------------------------------------------------------------------

local function savePoint()
	local p, _, rp, x, y = card:GetPoint(1)
	QL.DB().questCardPoint = { p, rp, x, y }
end

local function section(parent, title)
	local T, C = QL.Theme, QL.Theme.C
	local s = CreateFrame("Frame", nil, parent)
	s.head = T.Text(s, 10, C.accent, nil, true)
	s.head:SetPoint("TOPLEFT", 0, 0)
	s.head:SetText(title)
	s.body = T.Text(s, 12, C.text)
	s.body:SetPoint("TOPLEFT", 0, -16)
	s.body:SetPoint("RIGHT", s, "RIGHT", 0, 0)
	s.body:SetJustifyH("LEFT")
	s.body:SetJustifyV("TOP")
	if s.body.SetWordWrap then s.body:SetWordWrap(true) end
	return s
end

local function rewardTile(i)
	local T, C = QL.Theme, QL.Theme.C
	local t = card.tiles[i]
	if t then return t end
	t = CreateFrame("Button", nil, card.rewards)
	t:SetSize(36, 36)
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.icon:SetPoint("TOPLEFT", 2, -2); t.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	t.count = T.Text(t, 11, C.text, "OVERLAY", true)
	t.count:SetPoint("BOTTOMRIGHT", -2, 2)
	t:SetScript("OnEnter", function(self)
		if GameTooltip and GameTooltip.SetQuestItem then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			pcall(GameTooltip.SetQuestItem, GameTooltip, self.kind, self.index)
			GameTooltip:Show()
		end
	end)
	t:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	card.tiles[i] = t
	return t
end

local function build()
	local T, C = QL.Theme, QL.Theme.C
	card = CreateFrame("Frame", "QuestLineageQuestCard", UIParent)
	card:SetSize(W, 400)
	card:SetFrameStrata("HIGH")
	card:SetToplevel(true)
	card:SetClampedToScreen(true)
	card:SetMovable(true)
	card:EnableMouse(true)
	card:RegisterForDrag("LeftButton")
	card:SetScript("OnDragStart", function(self) self:StartMoving() end)
	card:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePoint() end)
	T.Fill(card, C.bg)
	T.Border(card, C.line)
	T.Glow(card, C.accent)

	-- hero
	local hero = CreateFrame("Frame", nil, card)
	hero:SetPoint("TOPLEFT"); hero:SetPoint("TOPRIGHT")
	hero:SetHeight(HERO_H)
	local bg = hero:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(T.WHITE)
	bg:SetAllPoints()
	T.Gradient(bg, "VERTICAL", C.sidebar, C.heroTop)
	local ok, model = pcall(CreateFrame, "PlayerModel", nil, hero)
	if ok and model then
		model:SetPoint("TOPRIGHT", -6, -6)
		model:SetSize(120, HERO_H - 6)
		card.model = model
	end
	card.mark = hero:CreateTexture(nil, "ARTWORK")
	card.mark:SetTexture(MEDIA .. "quest_mark")
	card.mark:SetSize(54, 54)
	card.mark:SetPoint("CENTER", hero, "RIGHT", -66, 0)
	card.mark:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.85)
	local shade = hero:CreateTexture(nil, "OVERLAY")
	shade:SetTexture(T.WHITE)
	shade:SetPoint("BOTTOMLEFT"); shade:SetPoint("BOTTOMRIGHT")
	shade:SetHeight(1)
	T.Color(shade, C.line)
	card.kicker = T.Text(hero, 10, C.accent, nil, true)
	card.kicker:SetPoint("TOPLEFT", 16, -16)
	card.title = T.Text(hero, 16, C.text, nil, true)
	card.title:SetPoint("TOPLEFT", card.kicker, "BOTTOMLEFT", 0, -6)
	card.title:SetWidth(W - 160)
	card.title:SetJustifyH("LEFT")
	if card.title.SetWordWrap then card.title:SetWordWrap(true) end
	card.meta = T.Text(hero, 11, C.muted)
	card.meta:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
	card.meta:SetWidth(W - 160)
	card.meta:SetJustifyH("LEFT")
	card.xp = T.Text(hero, 12, C.accent, nil, true)
	card.xp:SetPoint("TOPLEFT", card.meta, "BOTTOMLEFT", 0, -6)
	card.xp:SetWidth(W - 160)
	card.xp:SetJustifyH("LEFT")
	local close = T.CloseButton(card)
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetFrameLevel(hero:GetFrameLevel() + 10)
	card.close = close

	-- body (scrolls when long)
	local sf = T.Scroll(card)
	sf:SetPoint("TOPLEFT", 0, -HERO_H - 12)
	sf:SetPoint("BOTTOMRIGHT", 0, 56)
	card.scroll = sf
	local body = sf.child
	card.sections = {
		warn = section(body, L("WARNING")),
		objective = section(body, L("OBJECTIVE")),
		tasks = section(body, L("WHAT TO DO")),
		rewards = section(body, L("REWARDS")),
		chain = section(body, L("CHAIN")),
		story = section(body, L("STORY")),
	}
	card.sections.warn.head:SetTextColor(C.danger[1], C.danger[2], C.danger[3], 1)
	card.sections.tasks.body:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)
	card.sections.story.body:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)
	card.rewards = CreateFrame("Frame", nil, card.sections.rewards)
	card.tiles = {}
	-- the story folds: its header toggles it
	local fold = CreateFrame("Button", nil, card.sections.story)
	fold:SetPoint("TOPLEFT", card.sections.story.head, "TOPLEFT", 0, 2)
	fold:SetSize(W - 32, 16)
	fold:SetScript("OnClick", function()
		QL.Set("questCardStory", not QL.DB().questCardStory)
		if card.questId then QL.ShowQuestCard(card.questId) end
	end)

	-- footer
	local foot = CreateFrame("Frame", nil, card)
	foot:SetPoint("BOTTOMLEFT"); foot:SetPoint("BOTTOMRIGHT")
	foot:SetHeight(56)
	T.Fill(foot, C.header)
	local line = foot:CreateTexture(nil, "BORDER")
	line:SetTexture(T.WHITE)
	line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT")
	line:SetHeight(1)
	T.Color(line, C.line)
	card.accept = T.Button(foot, 120, 32)
	card.accept:SetPoint("RIGHT", -14, 0)
	card.accept:SetLabel(L("Accept"))
	card.accept:SetActive(true)
	card.accept:SetScript("OnClick", function()
		card.answered = true
		call(AcceptQuest)
		QL.HideQuestCard()
	end)
	card.decline = T.Button(foot, 96, 32)
	card.decline:SetPoint("RIGHT", card.accept, "LEFT", -8, 0)
	card.decline:SetLabel(L("Decline"))
	card.decline:SetScript("OnClick", function()
		card.answered = true
		call(DeclineQuest)
		QL.HideQuestCard()
	end)
	card.chainButton = T.Button(foot, 96, 32)
	card.chainButton:SetPoint("LEFT", 14, 0)
	card.chainButton:SetLabel(L("Chain"))
	card.chainButton:SetScript("OnClick", function() if card.questId then QL.Open(card.questId) end end)

	-- closing the card while the game's window is hidden ends the conversation (nothing else
	-- would be left on screen to answer the NPC)
	card:SetScript("OnHide", function()
		if not card.answered and not card.closing and QL.gameQuestFrameHidden then call(CloseQuest) end
		restoreGameFrame()
	end)
	if UISpecialFrames then table.insert(UISpecialFrames, "QuestLineageQuestCard") end
	card:Hide()
	QL.questCard = card
end

-- Filling ----------------------------------------------------------------------------------------------

local function placeCard()
	card:ClearAllPoints()
	if QL.gameQuestFrameHidden or not (QuestFrame and QuestFrame:IsShown()) then
		local p = QL.DB().questCardPoint
		if type(p) == "table" and p[1] then
			card:SetPoint(p[1], UIParent, p[2], p[3], p[4])
		else
			card:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -116)
		end
	else
		card:SetPoint("TOPLEFT", QuestFrame, "TOPRIGHT", 6, 0)
	end
end

local function setModel()
	local m = card.model
	card.mark:Show()
	if not m then return end
	m:Hide()
	local shown = false
	if UnitExists and UnitExists("npc") and m.SetUnit then
		shown = pcall(m.SetUnit, m, "npc") and true or false
	end
	if shown then
		if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, 1) end
		if m.SetCamDistanceScale then pcall(m.SetCamDistanceScale, m, 1.5) end
		if m.SetPosition then pcall(m.SetPosition, m, 0, 0, 0) end
		m:Show()
		card.mark:Hide()
	end
end

local function rewards(sec)
	local T, C = QL.Theme, QL.Theme.C
	local n = 0
	local function add(kind, count)
		for i = 1, count do
			local name, tex, num, quality = call(GetQuestItemInfo, kind, i)
			if name or tex then
				n = n + 1
				local t = rewardTile(n)
				t.kind, t.index = kind, i
				t.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
				t.count:SetText((num and num > 1) and num or "")
				local q = QUALITY[quality or 1] or QUALITY[1]
				T.Border(t, { q[1], q[2], q[3], 0.9 })
				t:ClearAllPoints()
				t:SetPoint("TOPLEFT", ((n - 1) % 7) * 42, -math.floor((n - 1) / 7) * 42)
				t:Show()
			end
		end
	end
	add("reward", tonumber(call(GetNumQuestRewards)) or 0)
	local choices = tonumber(call(GetNumQuestChoices)) or 0
	local firstChoice = n + 1
	add("choice", choices)
	for i = n + 1, #card.tiles do card.tiles[i]:Hide() end
	local lines = {}
	local money = tonumber(call(GetRewardMoney)) or 0
	if money > 0 then
		lines[#lines + 1] = GetCoinTextureString and GetCoinTextureString(money) or (("%dg %ds %dc"):format(money / 10000, (money / 100) % 100, money % 100))
	end
	if choices > 0 then lines[#lines + 1] = hex(C.muted) .. L("Choose one of %d when you hand it in (from tile %d)"):format(choices, firstChoice) .. "|r" end
	local rows = math.ceil(n / 7)
	card.rewards:ClearAllPoints()
	card.rewards:SetPoint("TOPLEFT", sec.head, "BOTTOMLEFT", 0, -6)
	card.rewards:SetSize(W - 32, rows * 42)
	sec.body:ClearAllPoints()
	sec.body:SetPoint("TOPLEFT", card.rewards, "BOTTOMLEFT", 0, rows > 0 and -4 or 0)
	sec.body:SetPoint("RIGHT", sec, "RIGHT", 0, 0)
	sec.body:SetText(table.concat(lines, "\n"))
	return n > 0 or #lines > 0, rows * 42 + (rows > 0 and 4 or 0)
end

function QL.ShowQuestCard(id)
	if not card then
		local ok, err = pcall(build)
		if not ok then QL.Debug("quest card: " .. tostring(err)); card = nil; return end
	end
	local T, C = QL.Theme, QL.Theme.C
	local ctx = QL.Context()
	local known = QL.QuestExists(id)
	card.questId = id
	card.answered = false

	-- hero
	card.kicker:SetText(L("NEW QUEST"))
	local title = known and QL.QuestTitle(id) or (call(GetTitleText) or "?")
	card.title:SetText(title)
	card.title:SetTextColor(unpack(known and (QL.TitleColor(id, ctx) or C.text) or C.text))
	local meta = {}
	if known then
		meta[#meta + 1] = QL.LevelMarkup(id, ctx)
		local dungeon = QL.DungeonMarkup(id, true)
		if dungeon then meta[#meta + 1] = dungeon end
	end
	local giver = UnitName and call(UnitName, "npc")
	if giver then meta[#meta + 1] = hex(C.muted) .. giver .. "|r" end
	card.meta:SetText(table.concat(meta, "  ·  "))
	local xp = known and QL.QuestXPAt(id, ctx.level)
	card.xp:SetText(xp and (QL.XPText(xp) .. "  " .. hex(C.muted) .. QL.GainText(QL.LevelGain(xp)) .. "|r") or "")
	setModel()

	-- sections, stacked
	local y = 0
	local width = W - 32
	local function place(sec, text, extra)
		if not text or text == "" then sec:Hide(); return end
		sec:ClearAllPoints()
		sec:SetPoint("TOPLEFT", 16, -y)
		sec:SetWidth(width)
		if text ~= true then sec.body:SetText(text) end
		local h = 16 + (extra or 0) + ((sec.body:GetText() or "") ~= "" and (sec.body:GetStringHeight() or 12) or 0)
		sec:SetHeight(h)
		sec:Show()
		y = y + h + 14
	end
	local s = card.sections
	local warns = {}
	for _, w in ipairs(QL.OfferWarnings(id, ctx)) do
		warns[#warns + 1] = (w.danger and hex(C.danger) or hex(C.text)) .. w.text .. "|r"
	end
	place(s.warn, table.concat(warns, "\n"))
	local objective = (known and QL.UseTurkish() and QL.QuestObjectives(id)) or call(GetObjectiveText) or (known and QL.QuestObjectives(id))
	place(s.objective, objective)
	local tasks = {}
	if known then
		for _, t in ipairs(QL.QuestTasks(id)) do
			if t.kind ~= "rep" then
				local verb = t.kind == "npc" and L("Kill: ") or (t.kind == "item" and L("Collect: ") or L("Use: "))
				tasks[#tasks + 1] = hex(C.accent) .. "•|r  " .. verb .. hex(C.text) .. (t.name or "?") .. "|r"
			end
		end
	end
	place(s.tasks, table.concat(tasks, "\n"))
	local any, extra = rewards(s.rewards)
	if any then
		s.rewards.body:SetWidth(width)
		place(s.rewards, true, extra)
	else
		s.rewards:Hide()
	end
	local chainText
	local summary = known and QL.ChainSummary(id, ctx)
	if summary then
		local chain = QL.BuildChain(id, ctx)
		local ids = {}
		for nid in pairs(chain and chain.nodes or {}) do ids[#ids + 1] = nid end
		local cx = QL.ChainXP(ids, ctx)
		chainText = L("Link %d of %d"):format(summary.index, summary.total) .. "  ·  " .. L("%d quests"):format(summary.size)
		if cx.remaining > 0 then chainText = chainText .. "  ·  " .. hex(C.accent) .. QL.XPText(cx.remaining) .. "|r" end
	end
	place(s.chain, chainText)
	card.chainButton:SetShown(summary and true or false)
	local story = (known and QL.QuestDescription(id)) or call(GetQuestText)
	if story and story ~= "" then
		local open = QL.DB().questCardStory
		s.story.head:SetText(L("STORY") .. "  " .. hex(C.muted) .. (open and "–" or "+") .. "|r")
		s.story.body:SetText(open and story or "")
		place(s.story, true)
	else
		s.story:Hide()
	end

	card.scroll.child:SetWidth(W)
	card.scroll:SetContentHeight(y)
	card:SetHeight(math.min(MAX_H, HERO_H + 12 + y + 56))
	if QL.DB().hideGameQuestFrame then hideGameFrame() else restoreGameFrame() end
	placeCard()
	card.closing = false
	card:Show()
end

function QL.HideQuestCard()
	if not card then return end
	card.closing = true
	card:Hide()
	card.closing = false
	card.questId = nil
	restoreGameFrame()
end

-- Events ---------------------------------------------------------------------------------------------

QL.Event("QUEST_DETAIL", function()
	if QL.DB().questCard == false then return end
	local id = call(GetQuestID)
	if type(id) ~= "number" or id <= 0 then return end
	local ok, err = pcall(QL.ShowQuestCard, id)
	if not ok then QL.Debug("quest card: " .. tostring(err)); restoreGameFrame(); return end
	-- the game shows and lays out its own window on the same event, perhaps after us: once more
	-- on the next frame
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			if card and card:IsShown() and card.questId == id then
				if QL.DB().hideGameQuestFrame then hideGameFrame() end
				placeCard()
			end
		end)
	end
end)

-- the conversation ended, or moved on to another screen (progress / reward): the game's again
for _, e in ipairs({ "QUEST_FINISHED", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING" }) do
	QL.Event(e, function() pcall(QL.HideQuestCard) end)
end

QL.Event("QUEST_ACCEPTED", function(_, a, b)
	if not QL.DB().openOnAccept then return end
	local id = type(b) == "number" and b or a
	if type(id) == "number" and id > 0 then pcall(QL.Open, id) end
end)

QL.On("SETTING_CHANGED", function(key)
	if key == "questCard" and QL.DB().questCard == false then pcall(QL.HideQuestCard) end
	if key == "hideGameQuestFrame" and card and card:IsShown() then
		if QL.DB().hideGameQuestFrame then hideGameFrame() else restoreGameFrame() end
		placeCard()
	end
end)
