-- Notifications: QuestLineage's results and errors as small cards instead of chat lines.
--
--   ┃ ● QuestLineage                ×
--   ┃   Route complete.
--
-- A card slides in, stays about five seconds (longer for errors; hovering holds it), then fades.
-- Up to four stack downward from the anchor, newest on top; a click closes one. The colour of the
-- side bar and the dot says the kind: info (accent), success (green), warn (orange), error (red).
-- Drag any card to move the stack (toastPoint). Setting toasts: off sends messages to the chat.
--
--   QL.Toast(text, kind, opts)   opts = { head = "header text", onClick = function, life = seconds,
--                                         icon = texture path or id, crop = true (an item icon) }
--   kind "quest" (violet) is for the other-quest hints (Nearby.lua): a click runs onClick.

local _, QL = ...

local W = 300
local MAX = 4
local LIFE = { info = 5, success = 5, warn = 6, error = 9, quest = 8 }
local FADE, SLIDE = 0.35, 0.22

local anchor
local cards, pool = {}, {}

local function kindColor(kind)
	local T, C = QL.Theme, QL.Theme.C
	if kind == "success" then return T.STATUS.done end
	if kind == "warn" then return QL.DIFFICULTY and QL.DIFFICULTY.hard or { 0.98, 0.57, 0.24 } end
	if kind == "error" then return C.danger end
	if kind == "quest" then return C.accent2 end
	return C.accent
end

local function savePoint()
	local point, _, relPoint, x, y = anchor:GetPoint(1)
	QL.DB().toastPoint = { point, relPoint, x, y }
end

local function buildAnchor()
	anchor = CreateFrame("Frame", "QuestLineageToasts", UIParent)
	anchor:SetSize(W, 10)
	local p = QL.DB().toastPoint
	if type(p) == "table" and p[1] then
		anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		anchor:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -200)
	end
	anchor:SetFrameStrata("DIALOG")
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)
end

local function layout()
	local y = 0
	for _, c in ipairs(cards) do
		c.targetY = y
		y = y - c:GetHeight() - 6
	end
end

local function remove(card)
	for i, c in ipairs(cards) do
		if c == card then table.remove(cards, i); break end
	end
	card:Hide()
	card:SetScript("OnUpdate", nil)
	pool[#pool + 1] = card
	layout()
end

local function newCard()
	local T, C = QL.Theme, QL.Theme.C
	local card = table.remove(pool)
	if card then return card end
	card = CreateFrame("Button", nil, anchor)
	card:SetWidth(W)
	T.Fill(card, { 0.055, 0.063, 0.082, 0.95 })
	T.Border(card, C.line)
	card.bar = card:CreateTexture(nil, "ARTWORK")
	card.bar:SetTexture(T.WHITE)
	card.bar:SetPoint("TOPLEFT", 1, -1); card.bar:SetPoint("BOTTOMLEFT", 1, 1)
	card.bar:SetWidth(3)
	card.dot = card:CreateTexture(nil, "ARTWORK")
	card.dot:SetTexture("Interface\\AddOns\\QuestLineage\\Media\\disc")
	card.dot:SetSize(8, 8)
	card.dot:SetPoint("TOPLEFT", 14, -12)
	card.head = T.Text(card, 10, C.muted, nil, true)
	card.head:SetPoint("LEFT", card.dot, "RIGHT", 6, 0)
	card.head:SetText("QuestLineage")
	card.close = T.Text(card, 13, C.dim)
	card.close:SetPoint("TOPRIGHT", -10, -7)
	card.close:SetText("×")
	card.text = T.Text(card, 12, C.text)
	card.text:SetPoint("TOPLEFT", 14, -28)
	card.text:SetWidth(W - 28)
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(34, 34)
	card.icon:SetPoint("TOPLEFT", 14, -28)
	card.icon:Hide()
	if card.text.SetWordWrap then card.text:SetWordWrap(true) end
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	card:SetScript("OnClick", function(self, button)
		local fn = self.onClick
		remove(self)
		if fn and button ~= "RightButton" then pcall(fn) end -- right-click only closes
	end)
	card:SetScript("OnEnter", function(self) self.hold = true; self.close:SetTextColor(C.text[1], C.text[2], C.text[3], 1) end)
	card:SetScript("OnLeave", function(self) self.hold = false; self.close:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 1) end)
	-- dragging a card moves the whole stack
	card:RegisterForDrag("LeftButton")
	card:SetScript("OnDragStart", function() anchor:StartMoving() end)
	card:SetScript("OnDragStop", function() anchor:StopMovingOrSizing(); savePoint() end)
	return card
end

function QL.Toast(text, kind, opts)
	if not CreateFrame then error("no frames") end
	kind = LIFE[kind] and kind or "info"
	opts = opts or {}
	if not anchor then buildAnchor() end
	local card = newCard()
	card.onClick = opts.onClick
	card.head:SetText(opts.head or "QuestLineage")
	local c = kindColor(kind)
	card.bar:SetVertexColor(c[1], c[2], c[3], 1)
	card.dot:SetVertexColor(c[1], c[2], c[3], 1)
	local hasIcon = opts.icon ~= nil
	card.text:ClearAllPoints()
	if hasIcon then
		card.icon:SetTexture(opts.icon)
		if opts.crop then card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else card.icon:SetTexCoord(0, 1, 0, 1) end
		card.icon:Show()
		card.text:SetPoint("TOPLEFT", 56, -28)
		card.text:SetWidth(W - 70)
	else
		card.icon:Hide()
		card.text:SetPoint("TOPLEFT", 14, -28)
		card.text:SetWidth(W - 28)
	end
	card.text:SetText(text)
	card:SetHeight(math.max(hasIcon and 74 or 48, (card.text:GetStringHeight() or 14) + 40))
	card.life, card.age, card.hold = opts.life or LIFE[kind], 0, false
	table.insert(cards, 1, card)
	while #cards > MAX do remove(cards[#cards]) end
	layout()
	card.y = card.targetY
	card:SetAlpha(0)
	card:ClearAllPoints()
	card:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, card.y)
	card:Show()
	card:SetScript("OnUpdate", function(self, elapsed)
		elapsed = elapsed or 0.016
		self.age = self.age + (self.hold and 0 or elapsed)
		-- slide in from the right, ease to the stack slot
		local inT = math.min(1, (self.age + (self.hold and SLIDE or 0)) / SLIDE)
		local x = (1 - inT) * 40
		self.y = self.y + (self.targetY - self.y) * math.min(1, elapsed * 12)
		self:ClearAllPoints()
		self:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", x, self.y)
		local alpha = inT
		local left = self.life - self.age
		if left < FADE then alpha = math.max(0, left / FADE) end
		self:SetAlpha(alpha)
		if left <= 0 then remove(self) end
	end)
	return card
end

function QL.ClearToasts()
	while #cards > 0 do remove(cards[1]) end
end
