-- The quest card: when an NPC offers a quest (QUEST_DETAIL), QuestLineage's own page for it opens
-- beside the game's quest window, or in its place:
--   hero      the NPC you are talking to in 3D over the indigo gradient, "NEW QUEST", the title in
--             its difficulty colour, level / dungeon tags, XP and its share of a level
--   sections  the objective (the game's live text, Turkish via WoWTR), what to do (database tasks
--             with distances), the story (folded), rewards (item tiles with quality borders, money),
--             the chain ("link 2 of 5 · 3,400 XP"), warnings (quests this closes, breadcrumbs)
--   chain     for a chain quest, a violet box right under the hero: the links as dots (done in
--             green, this one lit and ringed, later ones dim), "link 2 of 5 · 6 quests · XP left",
--             the next quest; the hero's kicker says "CHAIN 2/5" too
--   footer    "Show the quest in the quest list" (the main window opens on it, with its chain
--             tree), Decline (DeclineQuest), Accept (AcceptQuest)
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
local W, HERO_H, MAX_H, FOOT_H = 360, 128, 640, 96
local MAX_DOTS = 9
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
	sf:SetPoint("BOTTOMRIGHT", 0, FOOT_H)
	card.scroll = sf
	local body = sf.child
	card.sections = {
		warn = section(body, L("WARNING")),
		objective = section(body, L("OBJECTIVE")),
		tasks = section(body, L("WHAT TO DO")),
		rewards = section(body, L("REWARDS")),
		chain = section(body, L("CHAIN QUEST")),
		story = section(body, L("STORY")),
	}
	card.sections.warn.head:SetTextColor(C.danger[1], C.danger[2], C.danger[3], 1)
	card.sections.tasks.body:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)
	card.sections.story.body:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)
	card.rewards = CreateFrame("Frame", nil, card.sections.rewards)
	local box = CreateFrame("Frame", nil, card.sections.chain)
	box:SetPoint("TOPLEFT", card.sections.chain.head, "BOTTOMLEFT", 0, -6)
	box:SetWidth(W - 32)
	box.bg = T.Fill(box, { C.accent2[1], C.accent2[2], C.accent2[3], 0.08 })
	T.Border(box, { C.accent2[1], C.accent2[2], C.accent2[3], 0.45 })
	box.edge = box:CreateTexture(nil, "ARTWORK")
	box.edge:SetTexture(T.WHITE)
	box.edge:SetPoint("TOPLEFT"); box.edge:SetPoint("BOTTOMLEFT")
	box.edge:SetWidth(3)
	T.Gradient(box.edge, "VERTICAL", C.accent2, C.accent)
	box.dots, box.links = {}, {}
	box.line1 = T.Text(box, 12, C.text, nil, true)
	box.line1:SetPoint("TOPLEFT", 14, -48)
	box.line1:SetPoint("RIGHT", box, "RIGHT", -12, 0)
	box.line2 = T.Text(box, 11, C.muted)
	box.line2:SetPoint("TOPLEFT", box.line1, "BOTTOMLEFT", 0, -5)
	box.line2:SetPoint("RIGHT", box, "RIGHT", -12, 0)
	if box.line2.SetWordWrap then box.line2:SetWordWrap(true) end
	card.chainBox = box
	card.sections.chain.head:SetTextColor(C.accent2[1], C.accent2[2], C.accent2[3], 1)
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
	foot:SetHeight(FOOT_H)
	T.Fill(foot, C.header)
	local line = foot:CreateTexture(nil, "BORDER")
	line:SetTexture(T.WHITE)
	line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT")
	line:SetHeight(1)
	T.Color(line, C.line)
	card.accept = T.Button(foot, 120, 32)
	card.accept:SetPoint("BOTTOMRIGHT", -14, 12)
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
	-- the main window on this quest: its place in the quest list and its chain tree
	card.showList = T.Button(foot, W - 28, 30)
	card.showList:SetPoint("TOPLEFT", 14, -10)
	card.showList:SetLabel(L("Show the quest in the quest list"))
	card.showList:SetScript("OnClick", function() if card.questId then QL.Open(card.questId) end end)
	card.chainButton = card.showList -- older name

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

-- The chain box: one dot per link (layer) of the chain, joined by lines; done links green, this
-- quest's link lit with a ring, links still ahead dim. More than MAX_DOTS links: a window round
-- this one, with faded ends. Returns the box's height.
function QL.DrawCardChain(id, ctx, summary)
	local T, C = QL.Theme, QL.Theme.C
	local box = card.chainBox
	local chain = QL.BuildChain(id, ctx)
	local layers = chain and chain.layers or {}
	local here = summary.index
	local first, last = 1, #layers
	if #layers > MAX_DOTS then
		first = math.max(1, math.min(here - math.floor(MAX_DOTS / 2), #layers - MAX_DOTS + 1))
		last = first + MAX_DOTS - 1
	end
	local n = last - first + 1
	local inner = W - 32 - 40
	local gap = n > 1 and inner / (n - 1) or 0
	local done = T.STATUS.done
	for _, d in ipairs(box.dots) do d.ring:Hide(); d.fill:Hide() end
	for _, l in ipairs(box.links) do l:Hide() end
	local prevX
	box.lit = nil
	for k = 1, n do
		local li = first + k - 1
		local status = "later"
		if li == here then
			status = "here"
		else
			local allDone = #layers[li] > 0
			for _, nid in ipairs(layers[li]) do
				if chain.nodes[nid].status ~= "done" then allDone = false end
			end
			if allDone then status = "done" elseif li < here then status = "before" end
		end
		local d = box.dots[k]
		if not d then
			d = { ring = box:CreateTexture(nil, "OVERLAY"), fill = box:CreateTexture(nil, "OVERLAY", nil, 1) }
			d.ring:SetTexture(MEDIA .. "ring")
			d.fill:SetTexture(MEDIA .. "disc")
			box.dots[k] = d
		end
		local x = 20 + (k - 1) * gap
		if n == 1 then x = (W - 32) / 2 end
		local size = status == "here" and 22 or 12
		d.ring:SetSize(size, size)
		d.ring:ClearAllPoints(); d.ring:SetPoint("CENTER", box, "TOPLEFT", x, -24)
		d.fill:SetSize(status == "here" and 12 or 8, status == "here" and 12 or 8)
		d.fill:ClearAllPoints(); d.fill:SetPoint("CENTER", box, "TOPLEFT", x, -24)
		local fade = ((k == 1 and first > 1) or (k == n and last < #layers)) and 0.4 or 1
		if status == "here" then
			d.ring:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
			d.fill:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
			box.lit = k
		elseif status == "done" then
			d.ring:SetVertexColor(done[1], done[2], done[3], 0.9 * fade)
			d.fill:SetVertexColor(done[1], done[2], done[3], 0.9 * fade)
		else
			d.ring:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], 0.7 * fade)
			d.fill:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], (status == "before" and 0.5 or 0) * fade)
		end
		d.ring:Show(); d.fill:Show()
		d.status = status
		if prevX then
			local l = box.links[k - 1]
			if not l then
				l = box:CreateTexture(nil, "ARTWORK")
				l:SetTexture(T.WHITE)
				l:SetHeight(2)
				box.links[k - 1] = l
			end
			l:ClearAllPoints()
			l:SetPoint("LEFT", box, "TOPLEFT", prevX + 7, -24)
			l:SetPoint("RIGHT", box, "TOPLEFT", x - 7, -24)
			local before = li <= here
			local c = before and C.accent2 or C.line
			l:SetVertexColor(c[1], c[2], c[3], before and 0.8 or 0.9)
			l:Show()
		end
		prevX = x
	end
	-- the lines under the dots
	local ids = {}
	for nid in pairs(chain and chain.nodes or {}) do ids[#ids + 1] = nid end
	local cx = QL.ChainXP(ids, ctx)
	local line1 = L("Link %d of %d"):format(summary.index, summary.total) .. "  ·  " .. L("%d quests"):format(summary.size)
	if cx.remaining > 0 then line1 = line1 .. "  ·  " .. hex(C.accent) .. QL.XPText(cx.remaining) .. "|r" end
	T.SetFont(box.line1, 12, true)
	box.line1:SetText(line1)
	local more = {}
	if summary.doneCount and summary.doneCount > 0 then
		more[#more + 1] = hex(done) .. L("%d done"):format(summary.doneCount) .. "|r"
	end
	if summary.nextId then
		more[#more + 1] = L("Next: ") .. hex(C.text) .. QL.QuestTitle(summary.nextId) .. "|r"
	elseif summary.index == summary.total then
		more[#more + 1] = hex(C.accent) .. L("The last link of the chain") .. "|r"
	end
	box.line2:SetWidth(W - 32 - 26)
	box.line2:SetText(table.concat(more, "  ·  "))
	local h = 48 + (box.line1:GetStringHeight() or 14) + 5 + ((#more > 0) and (box.line2:GetStringHeight() or 13) or 0) + 12
	box:SetHeight(h)
	box:Show()
	return h
end

-- The "what to do" lines: the database's tasks, else the client's objectives for the quest.
function QL.CardTasks(id, known)
	local C = QL.Theme.C
	local out = {}
	if known then
		for _, t in ipairs(QL.QuestTasks(id)) do
			if t.kind ~= "rep" then
				local verb = t.kind == "npc" and L("Kill: ") or (t.kind == "item" and L("Collect: ") or L("Use: "))
				local name = t.name or t.text
				if name then out[#out + 1] = hex(C.accent) .. "•|r  " .. verb .. hex(C.text) .. name .. "|r" end
			end
		end
	end
	if #out == 0 and C_QuestLog and C_QuestLog.GetQuestObjectives then
		local list = call(C_QuestLog.GetQuestObjectives, id)
		if type(list) == "table" then
			for _, o in ipairs(list) do
				if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then
					out[#out + 1] = hex(C.accent) .. "•|r  " .. hex(C.text) .. o.text .. "|r"
				end
			end
		end
	end
	return table.concat(out, "\n")
end

-- /ql kart: what the open card holds, to find why something does not show.
function QL.CardDebug()
	if not card or not card:IsShown() then QL.Chat(L("The quest card is not open: talk to an NPC offering a quest first.")); return end
	local id = card.questId
	QL.Chat(("card: quest %s · known %s · %dx%d · strata %s"):format(tostring(id), tostring(QL.QuestExists(id or 0)),
		card:GetWidth() or 0, card:GetHeight() or 0, tostring(card:GetFrameStrata())))
	for _, k in ipairs({ "accept", "decline", "showList" }) do
		local b = card[k]
		local fs = b.label
		QL.Chat(("%s: shown %s · text '%s' · width %.0f · font %s · alpha %.2f"):format(k, tostring(b:IsVisible()), tostring(fs:GetText()),
			fs:GetStringWidth() or -1, tostring((fs:GetFont())), fs:GetAlpha() or -1))
	end
	local tasks = QL.QuestTasks(id or 0)
	QL.Chat(("tasks from the database: %d"):format(#tasks))
	for i, t in ipairs(tasks) do
		if i > 6 then break end
		QL.Chat(("  %s %s: %s"):format(t.kind, tostring(t.id), tostring(t.name or t.text)))
	end
	local obj = QL.Q(id or 0, "objectives")
	QL.Chat("objectives field: " .. type(obj) .. (type(obj) == "table" and (" · slots " .. tostring(obj[1] and #obj[1]) .. "/" .. tostring(obj[2] and #obj[2]) .. "/" .. tostring(obj[3] and #obj[3])) or ""))
	for name, sec in pairs(card.sections) do
		QL.Chat(("section %s: shown %s · height %.0f · text %d chars · text height %.0f"):format(name, tostring(sec:IsShown()),
			sec:GetHeight() or 0, #(sec.body:GetText() or ""), sec.body:GetStringHeight() or 0))
	end
	QL.Chat(("scroll: %.0fx%.0f · child %.0fx%.0f"):format(card.scroll:GetWidth() or 0, card.scroll:GetHeight() or 0,
		card.scroll.child:GetWidth() or 0, card.scroll.child:GetHeight() or 0))
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
	local summary = known and QL.ChainSummary(id, ctx)
	card.kicker:SetText(L("NEW QUEST") .. (summary and ("  " .. hex(C.accent2) .. "·  " .. L("CHAIN %d/%d"):format(summary.index, summary.total) .. "|r") or ""))
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
	local s = card.sections
	local function place(sec, text, extra)
		if not text or text == "" then sec:Hide(); return end
		sec:ClearAllPoints()
		sec:SetPoint("TOPLEFT", 16, -y)
		sec:SetWidth(width)
		if sec ~= s.rewards then sec.body:SetWidth(width) end
		if text ~= true then sec.body:SetText(text) end
		local h = 16 + (extra or 0) + ((sec.body:GetText() or "") ~= "" and (sec.body:GetStringHeight() or 12) or 0)
		sec:SetHeight(h)
		sec:Show()
		y = y + h + 14
	end
	local warns = {}
	for _, w in ipairs(QL.OfferWarnings(id, ctx)) do
		warns[#warns + 1] = (w.danger and hex(C.danger) or hex(C.text)) .. w.text .. "|r"
	end
	place(s.warn, table.concat(warns, "\n"))
	if summary then
		s.chain.head:SetText(L("CHAIN QUEST"))
		place(s.chain, true, QL.DrawCardChain(id, ctx, summary) + 6)
	else
		s.chain:Hide()
	end
	local objective = (known and QL.UseTurkish() and QL.QuestObjectives(id)) or call(GetObjectiveText) or (known and QL.QuestObjectives(id))
	place(s.objective, objective)
	local tasks = QL.CardTasks(id, known)
	place(s.tasks, tasks)
	local any, extra = rewards(s.rewards)
	if any then
		s.rewards.body:SetWidth(width)
		place(s.rewards, true, extra)
	else
		s.rewards:Hide()
	end
	local story = (known and QL.QuestDescription(id)) or call(GetQuestText)
	if story and story ~= "" then
		local open = QL.DB().questCardStory
		s.story.head:SetText(L("STORY") .. "  " .. hex(C.muted) .. (open and "–" or "+") .. "|r")
		s.story.body:SetText(open and story or "")
		place(s.story, true)
	else
		s.story:Hide()
	end

	card.accept:SetLabel(L("Accept"))
	card.decline:SetLabel(L("Decline"))
	card.showList:SetLabel(L("Show the quest in the quest list"))
	for _, b in ipairs({ card.accept, card.decline, card.showList }) do
		T.SetFont(b.label, 12, true)
		b.label:SetTextColor(unpack(b == card.accept and C.text or C.muted))
		b.label:Show()
	end
	card.scroll.child:SetWidth(W)
	card.scroll:SetContentHeight(y)
	card:SetHeight(math.min(MAX_H, HERO_H + 12 + y + FOOT_H))
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
				pcall(QL.ShowQuestCard, id) -- measured again now that the card is laid out
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
