-- The look: one dark palette, one font, and the flat widgets the window is built from.
-- Flat surfaces, 1px hairlines, a teal-to-violet accent, colour only where it means something
-- (a quest's state, a link's kind). Every widget paints itself from QL.Theme.
--
--   T.C.<name>                    palette colours {r, g, b[, a]}
--   T.Fill(frame, color, layer)   a solid texture over the frame
--   T.Line(frame, color, side)    a 1px hairline on one side ("TOP", "BOTTOM", "LEFT", "RIGHT")
--   T.Border(frame, color, size)  four hairlines; T.Border(frame, color) again recolours
--   T.Glow(frame, color)          a soft halo round a frame (the focused card)
--   T.Text(parent, size, color)   a font string in the theme font
--   T.Gradient(tex, dir, c1, c2)  a two-colour gradient (falls back to c1)
--   T.Button(parent, w, h)        a flat button: :SetLabel(text), :SetActive(bool)
--   T.CloseButton(parent)
--   T.Bar(parent, h)              a progress bar: :SetValue(0..1, color)
--   T.Input(parent, w, h)         a flat search field with a placeholder: :SetPlaceholder(text)
--   T.Scroll(parent)              a vertical scroll area with a slim thumb: .child, :SetContentHeight(h)

local _, QL = ...

local T = {}
QL.Theme = T

local WHITE = "Interface\\Buttons\\WHITE8X8"
T.WHITE = WHITE
-- Inter (SIL Open Font License 1.1, Media/Fonts/Inter-OFL.txt) ships with the addon: it has every
-- Turkish letter (ş ğ ı İ), which the client's own Arial Narrow does not on every build (it showed
-- broken letters in game). WoWTR's font and the game's Arial are fallbacks if Inter cannot load.
T.FONT = "Interface\\AddOns\\QuestLineage\\Media\\Fonts\\Inter-Regular.ttf"
T.FONT_BOLD = "Interface\\AddOns\\QuestLineage\\Media\\Fonts\\Inter-SemiBold.ttf"
T.FONT_FALLBACKS = {
	"Interface\\AddOns\\WoWTR\\Assets\\Fonts\\Inter.ttf",
	"Fonts\\ARIALN.TTF",
}

-- Set a font, falling back down the list when the client refuses one (SetFont returns false,
-- or errors, for a file it cannot load). Inter runs wide, so sizes come out a touch smaller.
-- The fonts the player can choose (setting fontFace). Inter has every Turkish letter; the game's
-- own faces may lack them on some builds, so Inter stays the default.
T.FONT_FACES = {
	{ id = "inter", label = "Inter (default)" },
	{ id = "arial", label = "Arial Narrow (the game's)", path = "Fonts\\ARIALN.TTF", bold = "Fonts\\ARIALN.TTF" },
	{ id = "friz", label = "Friz Quadrata (the game's)", path = "Fonts\\FRIZQT__.TTF", bold = "Fonts\\FRIZQT__.TTF" },
	{ id = "skurri", label = "Skurri (the game's)", path = "Fonts\\skurri.ttf", bold = "Fonts\\skurri.ttf" },
}

local function chosenFace()
	local id = QL.DB and QL.DB().fontFace
	for _, f in ipairs(T.FONT_FACES) do
		if f.id == id and f.path then return f end
	end
	return nil
end

-- every font string set through SetFont, so a change of font applies to the open windows
local styled = setmetatable({}, { __mode = "k" })

function T.SetFont(fs, size, bold, flags)
	if type(fs) ~= "table" or not fs.SetFont then return end
	styled[fs] = { size, bold, flags }
	size = math.max(8, math.floor((size or 12) * 0.92 + 0.5))
	flags = flags or ""
	local list = {}
	local face = chosenFace()
	if face then list[1] = bold and face.bold or face.path end
	list[#list + 1] = bold and T.FONT_BOLD or T.FONT
	for _, f in ipairs(T.FONT_FALLBACKS) do list[#list + 1] = f end
	for _, path in ipairs(list) do
		local ok, set = pcall(fs.SetFont, fs, path, size, flags)
		if ok and set ~= false then return path end
	end
end

-- Set the font of every font string again (after the font setting changed).
function T.ReapplyFonts()
	for fs, a in pairs(styled) do T.SetFont(fs, a[1], a[2], a[3]) end
end

T.C = {
	bg        = { 0.051, 0.059, 0.078, 0.97 },
	header    = { 0.067, 0.078, 0.102, 1 },
	sidebar   = { 0.063, 0.074, 0.098, 1 },
	canvas    = { 0.043, 0.050, 0.066, 1 },
	card      = { 0.094, 0.110, 0.141, 1 },
	cardHover = { 0.125, 0.145, 0.188, 1 },
	cardFocus = { 0.110, 0.150, 0.170, 1 },
	row       = { 0, 0, 0, 0 },
	rowHover  = { 1, 1, 1, 0.04 },
	rowActive = { 0.24, 0.84, 0.78, 0.09 },
	line      = { 0.165, 0.192, 0.235, 1 },
	lineSoft  = { 0.165, 0.192, 0.235, 0.6 },
	text      = { 0.925, 0.937, 0.957, 1 },
	muted     = { 0.580, 0.616, 0.678, 1 },
	dim       = { 0.400, 0.435, 0.494, 1 },
	accent    = { 0.239, 0.839, 0.776, 1 }, -- teal
	accent2   = { 0.545, 0.486, 0.965, 1 }, -- violet
	heroTop   = { 0.100, 0.098, 0.165, 1 }, -- the detail panel's backdrop, deep muted indigo
	danger    = { 0.973, 0.443, 0.443, 1 },
	track     = { 1, 1, 1, 0.07 },
	panel     = { 0.055, 0.063, 0.082, 1 }, -- the floating panels' ground
	wash      = { 1, 1, 1, 1 },             -- the overlay colour for hovers, tracks and cards
}

-- A quest's state: colour and label.
T.STATUS = {
	done      = { 0.133, 0.773, 0.369, "Already done" },
	ready     = { 0.980, 0.800, 0.082, "Ready to turn in" },
	active    = { 0.220, 0.741, 0.973, "In your log" },
	available = { 0.898, 0.906, 0.922, "Available" },
	toolow    = { 0.984, 0.573, 0.235, "Level too low" },
	locked    = { 0.420, 0.447, 0.502, "Locked" },
	closed    = { 0.973, 0.443, 0.443, "Closed" },
	other     = { 0.294, 0.333, 0.388, "Not for your character" },
}

-- A link's kind: colour, label, dashed.
T.EDGE = {
	all        = { 0.580, 0.639, 0.722, 0.85, "requires" },
	next       = { 0.580, 0.639, 0.722, 0.85, "requires" },
	child      = { 0.580, 0.639, 0.722, 0.85, "requires" },
	any        = { 0.961, 0.620, 0.043, 0.90, "one of" },
	parent     = { 0.376, 0.647, 0.980, 0.90, "must be on" },
	breadcrumb = { 0.392, 0.455, 0.545, 0.80, "breadcrumb", true },
}

-- Status colours carry their label in slot 4, so only a number there is an alpha.
-- (Passing the label as alpha was a real-client error that stopped the zone list half-way.)
local function color(tex, c)
	local a = c[4]
	if type(a) ~= "number" then a = 1 end
	tex:SetVertexColor(c[1], c[2], c[3], a)
end
T.Color = color

function T.Hex(c)
	return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

function T.Fill(frame, c, layer, sub)
	local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
	t:SetTexture(WHITE)
	t:SetAllPoints()
	color(t, c)
	return t
end

function T.Line(frame, c, side, size)
	local t = frame:CreateTexture(nil, "BORDER")
	t:SetTexture(WHITE)
	size = size or 1
	if side == "TOP" or side == "BOTTOM" then
		t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(size)
	else
		t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(size)
	end
	color(t, c)
	return t
end

function T.Border(frame, c, size)
	local e = frame.qlEdges
	if not e then
		e = {}
		for i = 1, 4 do
			e[i] = frame:CreateTexture(nil, "OVERLAY", nil, 6)
			e[i]:SetTexture(WHITE)
		end
		e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT")
		e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT")
		e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT")
		e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT")
		frame.qlEdges = e
	end
	size = size or 1
	e[1]:SetHeight(size); e[2]:SetHeight(size); e[3]:SetWidth(size); e[4]:SetWidth(size)
	for i = 1, 4 do color(e[i], c) end
end

-- Three widening rings of falling alpha just outside the frame.
function T.Glow(frame, c)
	local g = frame.qlGlow
	if not g then
		g = {}
		for ring = 1, 3 do
			local parts = {}
			for i = 1, 4 do
				parts[i] = frame:CreateTexture(nil, "BACKGROUND", nil, -8 + ring)
				parts[i]:SetTexture(WHITE)
			end
			local o = ring * 2
			parts[1]:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -o, 0); parts[1]:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", o, 0); parts[1]:SetHeight(o)
			parts[2]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -o, 0); parts[2]:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", o, 0); parts[2]:SetHeight(o)
			parts[3]:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, 0); parts[3]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0); parts[3]:SetWidth(o)
			parts[4]:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0); parts[4]:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0); parts[4]:SetWidth(o)
			g[ring] = parts
		end
		frame.qlGlow = g
	end
	for ring, parts in ipairs(g) do
		for _, p in ipairs(parts) do
			if c then
				p:SetVertexColor(c[1], c[2], c[3], 0.16 / ring)
				p:Show()
			else
				p:Hide()
			end
		end
	end
end

function T.Text(parent, size, c, layer, bold)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	T.SetFont(fs, size or 12, bold)
	fs:SetShadowOffset(0, 0)
	if c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
	fs:SetJustifyH("LEFT")
	if fs.SetWordWrap then fs:SetWordWrap(false) end
	return fs
end

-- SetGradient writes the texture's vertex colours, so nothing may call SetVertexColor on it
-- afterwards: a SetVertexColor(1, 1, 1, 1) here once painted every gradient plain white in game.
local gradients = setmetatable({}, { __mode = "k" })
T.gradients = gradients
function T.Gradient(tex, direction, c1, c2)
	gradients[tex] = { direction, c1, c2 }
	local a1 = type(c1[4]) == "number" and c1[4] or 1
	local a2 = type(c2[4]) == "number" and c2[4] or 1
	if CreateColor and tex.SetGradient then
		local ok = pcall(tex.SetGradient, tex, direction, CreateColor(c1[1], c1[2], c1[3], a1), CreateColor(c2[1], c2[2], c2[3], a2))
		if ok then return end
	end
	if tex.SetGradientAlpha then
		local ok = pcall(tex.SetGradientAlpha, tex, direction, c1[1], c1[2], c1[3], a1, c2[1], c2[2], c2[3], a2)
		if ok then return end
	end
	color(tex, c1)
end

-- QuestLineage's own tooltip, in the theme's font (the game's tooltip font has no Turkish
-- letters on this client, so quest text there came out broken). The same calls as GameTooltip
-- for what QuestLineage uses: SetOwner(owner, anchor), AddLine(text, r, g, b, wrap), Show, Hide.
-- Item tiles keep the game's tooltip: the game draws items itself.
local TIP_W = 300 -- wrapped lines' width
function T.Tooltip()
	if T.tip then return T.tip end
	local C = T.C
	local tip = CreateFrame("Frame", "QuestLineageTooltip", UIParent)
	T.tip = tip
	local frameShow = tip.Show
	tip:SetFrameStrata("TOOLTIP")
	tip:SetClampedToScreen(true)
	tip:Hide()
	T.Fill(tip, { T.PanelA(0.97) })
	T.Border(tip, C.line)
	local top = tip:CreateTexture(nil, "ARTWORK")
	top:SetTexture(WHITE)
	top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1)
	top:SetHeight(2)
	T.Gradient(top, "HORIZONTAL", C.accent, C.accent2)
	tip.lines, tip.n = {}, 0
	-- never left behind: closes when its owner is hidden (as the game's tooltip does), and a tip
	-- that follows the cursor (map areas) closes once nothing moves it for a moment (whatever
	-- drove it stopped, e.g. its map was closed under the cursor)
	tip.idle = 0
	tip:SetScript("OnUpdate", function(self, elapsed)
		self.idle = (self.idle or 0) + (elapsed or 0)
		local o = self.owner
		if type(o) == "table" and o.IsVisible then
			local ok, vis = pcall(o.IsVisible, o)
			if ok and vis == false then self:Hide(); return end
		end
		if self.anchor == "ANCHOR_CURSOR" and self.idle > 0.4 then self:Hide() end
	end)

	-- anchor "ANCHOR_SIDE" with a third argument `ref` (a window): the tip opens beside that window,
	-- on the side with more room (the window nearer the right edge: to its left), level with the owner,
	-- so it never covers the window.
	function tip:SetOwner(owner, anchor, ref)
		self.owner, self.anchor, self.ref = owner, anchor or "ANCHOR_RIGHT", ref
		for _, fs in ipairs(self.lines) do fs:Hide() end
		self.n = 0
	end
	function tip:AddLine(text, r, g, b, wrap)
		self.n = self.n + 1
		local fs = self.lines[self.n]
		if not fs then
			fs = self:CreateFontString(nil, "OVERLAY")
			fs:SetJustifyH("LEFT")
			fs:SetShadowOffset(0, 0)
			self.lines[self.n] = fs
		end
		local first = self.n == 1
		T.SetFont(fs, first and 14 or 12, first)
		fs:SetTextColor(r or 1, g or 1, b or 1, 1)
		fs:SetText(text or "")
		fs.wrap = wrap and true or false
		if fs.SetWordWrap then fs:SetWordWrap(fs.wrap) end
		fs:Show()
	end
	function tip:NumLines() return self.n end
	-- beside the cursor (bottom-left corner just right of and above it), kept on the screen
	function tip:PlaceAtCursor()
		self.idle = 0
		local x, y = 0, 0
		if GetCursorPosition then x, y = GetCursorPosition() end
		local s = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
		x, y = (x or 0) / s, (y or 0) / s
		local sw = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1920
		local w, h = self:GetWidth() or 0, self:GetHeight() or 0
		if type(sw) == "number" and type(w) == "number" and x + 16 + w > sw then x = x - w - 32 end
		if type(h) == "number" and y - h < 0 then y = h end
		self:ClearAllPoints()
		self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x + 16, y + 8)
	end
	function tip:Show()
		if self.n == 0 then self:Hide(); return end
		-- width: the widest unwrapped line; wrapped lines get a fixed width
		local w = 0
		for i = 1, self.n do
			local fs = self.lines[i]
			local sw = fs.wrap and TIP_W or (fs:GetStringWidth() or 0)
			if sw > w then w = sw end
		end
		w = math.min(math.max(w, 120), 420)
		local y = -12
		for i = 1, self.n do
			local fs = self.lines[i]
			fs:ClearAllPoints()
			fs:SetWidth(w)
			fs:SetPoint("TOPLEFT", self, "TOPLEFT", 12, y)
			y = y - (fs:GetStringHeight() or 12) - (i == 1 and 6 or 3)
		end
		self:SetSize(w + 24, -y + 9)
		self:ClearAllPoints()
		local o, a = self.owner, self.anchor
		if not o then
			self:SetPoint("CENTER")
		elseif a == "ANCHOR_SIDE" then
			local ref = self.ref or o
			local left = false -- opens to the window's left?
			local ok, cx = pcall(function() return (ref:GetCenter() or 0) * ref:GetEffectiveScale() end)
			local okU, sw = pcall(function() return UIParent:GetWidth() * UIParent:GetEffectiveScale() end)
			if ok and okU and type(cx) == "number" and type(sw) == "number" then left = cx > sw / 2 end
			-- level with the owner (a row), measured from the window's top
			local dy = 0
			local okT, d = pcall(function()
				return ((o:GetTop() or 0) - (ref:GetTop() or 0)) * o:GetEffectiveScale() / self:GetEffectiveScale()
			end)
			if okT and type(d) == "number" and d <= 0 then dy = d end
			if left then
				self:SetPoint("TOPRIGHT", ref, "TOPLEFT", -8, dy)
			else
				self:SetPoint("TOPLEFT", ref, "TOPRIGHT", 8, dy)
			end
		elseif a == "ANCHOR_LEFT" then
			self:SetPoint("TOPRIGHT", o, "TOPLEFT", -8, 0)
		elseif a == "ANCHOR_BOTTOM" then
			self:SetPoint("TOP", o, "BOTTOM", 0, -6)
		elseif a == "ANCHOR_TOP" then
			self:SetPoint("BOTTOM", o, "TOP", 0, 6)
		elseif a == "ANCHOR_CURSOR" then
			self:PlaceAtCursor()
		else
			self:SetPoint("TOPLEFT", o, "TOPRIGHT", 8, 0)
		end
		frameShow(self)
	end
	return tip
end
QL.Tip = function() return T.Tooltip() end

-- A square icon button (the quick bar): a glyph tinted muted, lit on hover, the accent when
-- active; an optional small caption under it (w x h grows to fit). :SetActive(on), .icon, .caption
function T.IconButton(parent, icon, size, caption)
	local C = T.C
	local b = CreateFrame("Button", nil, parent)
	size = size or 30
	b:SetSize(caption and size + 26 or size, caption and size + 16 or size)
	b.bg = T.Fill(b, { 0, 0, 0, 0 })
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetTexture(icon)
	b.icon:SetSize(size - 10, size - 10)
	b.icon:SetPoint("TOP", 0, -5)
	if caption then
		b.caption = T.Text(b, 9, C.muted)
		b.caption:SetPoint("BOTTOM", 0, 4)
		b.caption:SetJustifyH("CENTER")
		b.caption:SetText(caption)
	end
	local function paint(self, hover)
		color(self.bg, self.active and C.rowActive or (hover and C.rowHover or { 0, 0, 0, 0 }))
		local ic = self.active and C.accent or (hover and C.text or C.muted)
		self.icon:SetVertexColor(ic[1], ic[2], ic[3], 1)
		if self.caption then
			local tc = hover and C.text or C.muted
			self.caption:SetTextColor(tc[1], tc[2], tc[3], 1)
		end
	end
	function b:SetActive(on) self.active = on and true or false; paint(self, false) end
	b.paint = paint
	b:SetScript("OnEnter", function(self) paint(self, true) end)
	b:SetScript("OnLeave", function(self) paint(self, false) end)
	b:SetActive(false)
	return b
end

-- A navigation rail button: an icon over a small label; active = accent icon, an accent bar
-- on the left and a tinted ground. Same SetLabel / SetActive / .label / .active as T.Button.
function T.RailButton(parent, icon, w, h)
	local C = T.C
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 64, h or 62)
	b.bg = T.Fill(b, { 0, 0, 0, 0 })
	b.bar = b:CreateTexture(nil, "ARTWORK")
	b.bar:SetTexture(WHITE)
	b.bar:SetPoint("TOPLEFT", 0, -8); b.bar:SetPoint("BOTTOMLEFT", 0, 8)
	b.bar:SetWidth(3)
	T.Gradient(b.bar, "VERTICAL", C.accent2, C.accent)
	b.bar:Hide()
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetTexture(icon)
	b.icon:SetSize(22, 22)
	b.icon:SetPoint("TOP", 0, -11)
	b.label = T.Text(b, 10, C.muted)
	b.label:SetPoint("BOTTOM", 0, 9)
	b.label:SetJustifyH("CENTER")
	function b:SetLabel(text) self.label:SetText(text) end
	local function paint(self, hover)
		local on = self.active
		color(self.bg, on and C.rowActive or (hover and C.rowHover or { 0, 0, 0, 0 }))
		local ic = on and C.accent or (hover and C.text or C.muted)
		self.icon:SetVertexColor(ic[1], ic[2], ic[3], 1)
		local tc = on and C.text or (hover and C.text or C.muted)
		self.label:SetTextColor(tc[1], tc[2], tc[3], 1)
		self.bar:SetShown(on and true or false)
	end
	function b:SetActive(on)
		self.active = on and true or false
		paint(self, false)
	end
	b:SetScript("OnEnter", function(self) paint(self, true) end)
	b:SetScript("OnLeave", function(self) paint(self, false) end)
	b:SetActive(false)
	return b
end

-- Flat button: label, hover lift, an "active" state with an accent underline.
function T.Button(parent, w, h)
	local C = T.C
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 90, h or 26)
	b.bg = T.Fill(b, C.card)
	T.Border(b, C.line)
	b.label = T.Text(b, 12, C.muted)
	b.label:SetPoint("CENTER")
	b.label:SetJustifyH("CENTER")
	b.under = b:CreateTexture(nil, "OVERLAY", nil, 7)
	b.under:SetTexture(WHITE)
	b.under:SetPoint("BOTTOMLEFT", 1, 1); b.under:SetPoint("BOTTOMRIGHT", -1, 1)
	b.under:SetHeight(2)
	color(b.under, C.accent)
	b.under:Hide()
	function b:SetLabel(text) self.label:SetText(text) end
	function b:SetActive(on)
		self.active = on and true or false
		color(self.bg, on and C.rowActive or C.card)
		T.Border(self, on and { C.accent[1], C.accent[2], C.accent[3], 0.45 } or C.line)
		self.label:SetTextColor(unpack(on and C.text or C.muted))
		self.under:SetShown(self.active)
	end
	b:SetScript("OnEnter", function(self)
		if not self.active then color(self.bg, C.cardHover); self.label:SetTextColor(unpack(C.text)) end
	end)
	b:SetScript("OnLeave", function(self)
		if not self.active then color(self.bg, C.card); self.label:SetTextColor(unpack(C.muted)) end
	end)
	return b
end

function T.CloseButton(parent)
	local C = T.C
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(32, 32)
	b.bg = T.Fill(b, { 0, 0, 0, 0 })
	b.x = T.Text(b, 18, C.muted)
	b.x:SetPoint("CENTER", 0, 1)
	b.x:SetText("×")
	b:SetScript("OnEnter", function(self) color(self.bg, { C.danger[1], C.danger[2], C.danger[3], 0.18 }); self.x:SetTextColor(unpack(C.danger)) end)
	b:SetScript("OnLeave", function(self) color(self.bg, { 0, 0, 0, 0 }); self.x:SetTextColor(unpack(C.muted)) end)
	b:SetScript("OnClick", function() parent:Hide() end)
	return b
end

function T.Bar(parent, h)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(h or 3)
	bar.track = T.Fill(bar, T.C.track, "ARTWORK")
	bar.fill = bar:CreateTexture(nil, "ARTWORK", nil, 2)
	bar.fill:SetTexture(WHITE)
	bar.fill:SetPoint("TOPLEFT"); bar.fill:SetPoint("BOTTOMLEFT")
	-- The fill follows the width: a bar laid out after SetValue (width 0 at first) still fills.
	local function layout(self)
		local w = (self:GetWidth() or 0) * (self.value or 0)
		self.fill:SetWidth(math.max(0.01, w))
		self.fill:SetShown((self.value or 0) > 0 and w >= 0.5)
	end
	function bar:SetValue(v, c)
		self.value = math.max(0, math.min(1, v or 0))
		layout(self)
		if c then color(self.fill, c) else T.Gradient(self.fill, "HORIZONTAL", T.C.accent, T.C.accent2) end
	end
	bar:SetScript("OnSizeChanged", layout)
	return bar
end

-- Level bar: where the character is in its level (a muted fill) and what an XP gain adds on
-- top of it (the accent gradient). :Set(gain) takes QL.LevelGain's result; a gain that crosses
-- into the next level fills the rest of the bar and shows a tick per level crossed.
function T.LevelBar(parent, h)
	local C = T.C
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(h or 6)
	bar.track = T.Fill(bar, C.track, "ARTWORK")
	bar.base = bar:CreateTexture(nil, "ARTWORK", nil, 1)
	bar.base:SetTexture(WHITE)
	bar.base:SetPoint("TOPLEFT"); bar.base:SetPoint("BOTTOMLEFT")
	color(bar.base, { C.text[1], C.text[2], C.text[3], 0.28 })
	bar.add = bar:CreateTexture(nil, "ARTWORK", nil, 2)
	bar.add:SetTexture(WHITE)
	bar.add:SetPoint("TOPLEFT", bar.base, "TOPRIGHT")
	bar.add:SetPoint("BOTTOMLEFT", bar.base, "BOTTOMRIGHT")
	T.Gradient(bar.add, "HORIZONTAL", C.accent, C.accent2)
	local function layout(self)
		local w = self:GetWidth() or 0
		local g = self.gain
		if not g then self.base:Hide(); self.add:Hide(); return end
		local from = g.startFrac or 0
		local to = (g.level > g.startLevel) and 1 or (g.frac or from)
		self.base:SetWidth(math.max(0.01, w * from))
		self.base:SetShown(from > 0)
		self.add:SetWidth(math.max(0.01, w * math.max(0, to - from)))
		self.add:SetShown(to > from)
	end
	function bar:Set(gain)
		self.gain = gain
		layout(self)
	end
	bar:SetScript("OnSizeChanged", layout)
	return bar
end

function T.Input(parent, w, h)
	local C = T.C
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(w or 200, h or 30)
	box:SetAutoFocus(false)
	T.SetFont(box, 13)
	box:SetTextColor(unpack(C.text))
	box:SetTextInsets(12, 10, 0, 0)
	box.bg = T.Fill(box, C.canvas)
	T.Border(box, C.line)
	box.hint = T.Text(box, 13, C.dim)
	box.hint:SetPoint("LEFT", 12, 0)
	function box:SetPlaceholder(text) self.hint:SetText(text) end
	box:SetScript("OnEditFocusGained", function(self) T.Border(self, { C.accent[1], C.accent[2], C.accent[3], 0.8 }) end)
	box:SetScript("OnEditFocusLost", function(self) T.Border(self, C.line) end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	return box
end

-- Vertical scroll area: the wheel scrolls, a slim thumb shows where you are.
-- A small confirmation dialog in the theme's look: title, text, a red action and Cancel. One
-- frame, reused; Escape cancels.
function T.Confirm(title, text, action, onYes)
	local C = T.C
	local d = T.confirm
	if not d then
		d = CreateFrame("Frame", "QuestLineageConfirm", UIParent)
		d:SetSize(340, 150)
		d:SetPoint("CENTER", 0, 120)
		d:SetFrameStrata("DIALOG")
		d:SetToplevel(true)
		d:EnableMouse(true)
		T.Fill(d, C.bg)
		T.Border(d, C.line)
		T.Glow(d, C.danger)
		local top = d:CreateTexture(nil, "ARTWORK")
		top:SetTexture(WHITE)
		top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1)
		top:SetHeight(2)
		color(top, C.danger)
		d.title = T.Text(d, 14, C.text, nil, true)
		d.title:SetPoint("TOPLEFT", 18, -18)
		d.text = T.Text(d, 12, C.muted)
		d.text:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -10)
		d.text:SetWidth(304)
		if d.text.SetWordWrap then d.text:SetWordWrap(true) end
		d.yes = T.Button(d, 120, 30)
		d.yes:SetPoint("BOTTOMRIGHT", -16, 14)
		d.yes.label:SetTextColor(C.danger[1], C.danger[2], C.danger[3], 1)
		T.Border(d.yes, { C.danger[1], C.danger[2], C.danger[3], 0.6 })
		d.yes:SetScript("OnLeave", function(self) color(self.bg, C.card); self.label:SetTextColor(C.danger[1], C.danger[2], C.danger[3], 1) end)
		d.no = T.Button(d, 100, 30)
		d.no:SetPoint("RIGHT", d.yes, "LEFT", -8, 0)
		d.no:SetScript("OnClick", function() d:Hide() end)
		d.yes:SetScript("OnClick", function()
			local fn = d.onYes
			d:Hide()
			if fn then fn() end
		end)
		if UISpecialFrames then table.insert(UISpecialFrames, "QuestLineageConfirm") end
		T.confirm = d
	end
	d.onYes = onYes
	d.title:SetText(title)
	d.text:SetText(text)
	d.yes:SetLabel(action)
	d.no:SetLabel(QL.L("Cancel"))
	d:SetHeight(18 + 20 + 10 + (d.text:GetStringHeight() or 30) + 60)
	d:Show()
	return d
end

-- A small themed popup holding one text, selected, for Ctrl+C. The game's clipboard call
-- (CopyToClipboard) is restricted to Blizzard's own UI: calling it from an addon raises the
-- "blocked from an action only available to the Blizzard UI" dialog (pcall cannot stop that), so
-- this popup is the only way.
-- It closes by itself after the copy, on Escape or when the box loses focus. One frame, reused.
function T.CopyText(text, owner, title)
	local C = T.C
	local d = T.copyBox
	if not d then
		d = CreateFrame("Frame", "QuestLineageCopy", UIParent)
		d:SetSize(230, 78)
		d:SetFrameStrata("FULLSCREEN_DIALOG")
		d:SetToplevel(true)
		d:SetClampedToScreen(true)
		d:EnableMouse(true)
		T.Fill(d, C.bg)
		T.Border(d, C.line)
		local top = d:CreateTexture(nil, "ARTWORK")
		top:SetTexture(WHITE)
		top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1)
		top:SetHeight(2)
		T.Gradient(top, "HORIZONTAL", C.accent, C.accent2)
		d.title = T.Text(d, 11, C.muted, nil, true)
		d.title:SetPoint("TOPLEFT", 12, -12)
		d.box = T.Input(d, 206, 28)
		d.box:SetPoint("TOPLEFT", 12, -30)
		d.hint = T.Text(d, 10, C.dim)
		d.hint:SetPoint("TOPLEFT", d.box, "BOTTOMLEFT", 0, -6)
		d.box:SetScript("OnKeyDown", function(_, key)
			local ctrl = (IsControlKeyDown and IsControlKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown())
			if ctrl and (key == "C" or key == "X") then
				local copied = d.text
				if C_Timer and C_Timer.After then
					C_Timer.After(0.12, function() d:Hide() end)
				else
					d:Hide()
				end
				QL.Print(QL.L("Copied: ") .. tostring(copied), "success")
			end
		end)
		-- read only: whatever is typed goes back to the text
		d.box:SetScript("OnTextChanged", function(self, user)
			if user and d.text and self:GetText() ~= d.text then
				self:SetText(d.text)
				self:HighlightText()
			end
		end)
		d.box:SetScript("OnEscapePressed", function() d:Hide() end)
		d.box:SetScript("OnEditFocusLost", function() d:Hide() end)
		d:Hide()
		T.copyBox = d
	end
	d.text = tostring(text or "")
	d.title:SetText(title or "")
	d.hint:SetText(QL.L("Ctrl+C to copy, Esc to close"))
	d.box:SetText(d.text)
	d:ClearAllPoints()
	if owner then d:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -6) else d:SetPoint("CENTER", 0, 120) end
	d:Show()
	d.box:SetFocus()
	d.box:HighlightText()
	return d
end

-- A quest id as a small pill ("#6306"): hover lights it, a click opens the copy popup.
-- tag:SetId(id) fits the pill to the number.
function T.IdTag(parent)
	local C = T.C
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(15)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetTexture(WHITE)
	b.bg:SetAllPoints()
	b.bg:SetVertexColor(T.Wash(0.07))
	b.text = T.Text(b, 10, C.dim)
	b.text:SetPoint("CENTER", 0, 0)
	b.text:SetJustifyH("CENTER")
	function b:SetId(id)
		self.id = id
		self.text:SetText("#" .. tostring(id))
		self:SetWidth((self.text:GetStringWidth() or 30) + 12)
	end
	b:SetScript("OnEnter", function(self)
		self.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
		self.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.16)
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_TOP")
		tip:AddLine(QL.L("Quest ID") .. ": " .. tostring(self.id), 1, 1, 1)
		tip:AddLine(QL.L("Click to copy"), C.accent[1], C.accent[2], C.accent[3])
		tip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 1)
		self.bg:SetVertexColor(T.Wash(0.07))
		QL.Tip():Hide()
	end)
	b:SetScript("OnClick", function(self)
		QL.Tip():Hide()
		if self.id then T.CopyText(self.id, self, QL.L("Quest ID")) end
	end)
	return b
end

function T.Scroll(parent)
	local C = T.C
	local sf = CreateFrame("ScrollFrame", nil, parent)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(1, 1)
	sf:SetScrollChild(child)
	sf.child = child
	local thumb = sf:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(WHITE)
	thumb:SetWidth(3)
	color(thumb, { C.muted[1], C.muted[2], C.muted[3], 0.35 })
	sf.thumb = thumb
	local function update()
		local viewH = sf:GetHeight() or 0
		local contentH = child:GetHeight() or 0
		if contentH <= viewH + 1 or viewH <= 0 then thumb:Hide(); return end
		local range = contentH - viewH
		local h = math.max(24, viewH * viewH / contentH)
		local y = (sf:GetVerticalScroll() or 0) / range * (viewH - h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -2, -y)
		thumb:SetHeight(h)
		thumb:Show()
	end
	sf.UpdateThumb = update
	function sf:SetContentHeight(h)
		child:SetHeight(math.max(1, h))
		child:SetWidth(self:GetWidth() or 1)
		local range = math.max(0, h - (self:GetHeight() or 0))
		if (self:GetVerticalScroll() or 0) > range then self:SetVerticalScroll(range) end
		update()
	end
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(self, delta)
		local range = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
		local v = math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 48))
		self:SetVerticalScroll(v)
		update()
	end)
	sf:SetScript("OnSizeChanged", function(self) child:SetWidth(self:GetWidth() or 1); update() end)
	return sf
end

-- A change of font applies to every open window at once.
QL.On("SETTING_CHANGED", function(key)
	if key == "fontFace" then pcall(T.ReapplyFonts) end
end)


-- Themes ----------------------------------------------------------------------------------------------
-- T.C is the palette of the windows; T.HUD holds the same colours for what floats over the world (arrow,
-- current quest window, quick bar, toasts, flight timer, map overlays; kept apart so it can differ
-- from the windows again). T.Apply(id) writes a theme's numbers INTO those tables (modules keep
-- `local C = QL.Theme.C`, so the tables themselves never change) and runs before the windows are
-- built (ADDON_LOADED); T.Switch(id) changes the theme live: it repaints every region of
-- QuestLineage's frames by value (old palette colour -> the same key of the new palette). Setting: theme.
-- T.PanelA(a) -> r, g, b, a of the floating panels; T.Wash(a) -> the hover/track overlay colour.

local function rgb(r, g, b, a) return { r, g, b, a } end

local function snapshot(src)
	local out = {}
	for k, v in pairs(src) do out[k] = { v[1], v[2], v[3], v[4] } end
	return out
end
-- the night theme is the palette above: the base every other theme starts from
local NIGHT = snapshot(T.C)

local function extend(over)
	local out = snapshot(NIGHT)
	for k, v in pairs(over) do out[k] = v end
	return out
end

T.THEMES = {
	{ id = "night", label = "Night", group = "Dark", colors = extend({}) },
	{ id = "graphite", label = "Graphite", group = "Dark", colors = extend({
		bg = rgb(0.078, 0.078, 0.082, 0.97), header = rgb(0.094, 0.094, 0.098, 1), sidebar = rgb(0.086, 0.086, 0.09, 1),
		canvas = rgb(0.059, 0.059, 0.063, 1), card = rgb(0.129, 0.129, 0.137, 1), cardHover = rgb(0.165, 0.165, 0.176, 1),
		cardFocus = rgb(0.15, 0.157, 0.169, 1), line = rgb(0.2, 0.2, 0.212, 1), lineSoft = rgb(0.2, 0.2, 0.212, 0.6),
		rowActive = rgb(0.62, 0.75, 0.95, 0.09), accent = rgb(0.62, 0.75, 0.95, 1), accent2 = rgb(0.78, 0.62, 0.95, 1),
		heroTop = rgb(0.13, 0.13, 0.17, 1), panel = rgb(0.068, 0.068, 0.073, 1) }) },
	{ id = "black", label = "Black", group = "Dark", colors = extend({
		bg = rgb(0.0, 0.0, 0.0, 0.98), header = rgb(0.03, 0.03, 0.035, 1), sidebar = rgb(0.02, 0.02, 0.025, 1),
		canvas = rgb(0.0, 0.0, 0.0, 1), card = rgb(0.07, 0.07, 0.08, 1), cardHover = rgb(0.1, 0.1, 0.115, 1),
		cardFocus = rgb(0.09, 0.105, 0.115, 1), line = rgb(0.13, 0.13, 0.15, 1), lineSoft = rgb(0.13, 0.13, 0.15, 0.6),
		heroTop = rgb(0.045, 0.045, 0.08, 1), panel = rgb(0.01, 0.01, 0.014, 1) }) },
	{ id = "forest", label = "Forest", group = "Dark", colors = extend({
		bg = rgb(0.047, 0.075, 0.063, 0.97), header = rgb(0.06, 0.092, 0.078, 1), sidebar = rgb(0.055, 0.085, 0.07, 1),
		canvas = rgb(0.04, 0.065, 0.052, 1), card = rgb(0.085, 0.13, 0.108, 1), cardHover = rgb(0.115, 0.17, 0.14, 1),
		cardFocus = rgb(0.1, 0.17, 0.13, 1), line = rgb(0.16, 0.23, 0.19, 1), lineSoft = rgb(0.16, 0.23, 0.19, 0.6),
		rowActive = rgb(0.4, 0.85, 0.5, 0.09), accent = rgb(0.4, 0.85, 0.5, 1), accent2 = rgb(0.85, 0.8, 0.35, 1),
		heroTop = rgb(0.06, 0.13, 0.1, 1), panel = rgb(0.04, 0.065, 0.052, 1) }) },
	{ id = "sunset", label = "Sunset", group = "Dark", colors = extend({
		bg = rgb(0.09, 0.059, 0.06, 0.97), header = rgb(0.11, 0.07, 0.072, 1), sidebar = rgb(0.1, 0.065, 0.067, 1),
		canvas = rgb(0.075, 0.048, 0.05, 1), card = rgb(0.15, 0.1, 0.1, 1), cardHover = rgb(0.19, 0.125, 0.125, 1),
		cardFocus = rgb(0.19, 0.12, 0.11, 1), line = rgb(0.26, 0.18, 0.18, 1), lineSoft = rgb(0.26, 0.18, 0.18, 0.6),
		rowActive = rgb(1.0, 0.62, 0.3, 0.09), accent = rgb(1.0, 0.62, 0.3, 1), accent2 = rgb(0.96, 0.36, 0.42, 1),
		heroTop = rgb(0.19, 0.09, 0.11, 1), panel = rgb(0.075, 0.05, 0.052, 1) }) },
	{ id = "violet", label = "Violet", group = "Dark", colors = extend({
		bg = rgb(0.067, 0.055, 0.098, 0.97), header = rgb(0.085, 0.07, 0.12, 1), sidebar = rgb(0.08, 0.065, 0.11, 1),
		canvas = rgb(0.055, 0.045, 0.082, 1), card = rgb(0.12, 0.1, 0.17, 1), cardHover = rgb(0.155, 0.13, 0.215, 1),
		cardFocus = rgb(0.15, 0.12, 0.22, 1), line = rgb(0.21, 0.18, 0.29, 1), lineSoft = rgb(0.21, 0.18, 0.29, 0.6),
		rowActive = rgb(0.7, 0.55, 1.0, 0.09), accent = rgb(0.7, 0.55, 1.0, 1), accent2 = rgb(0.95, 0.5, 0.8, 1),
		heroTop = rgb(0.14, 0.09, 0.24, 1), panel = rgb(0.06, 0.05, 0.09, 1) }) },
	{ id = "alliance", label = "Alliance", group = "Faction", colors = extend({
		bg = rgb(0.045, 0.06, 0.11, 0.97), header = rgb(0.06, 0.078, 0.14, 1), sidebar = rgb(0.055, 0.07, 0.13, 1),
		canvas = rgb(0.04, 0.05, 0.095, 1), card = rgb(0.09, 0.12, 0.2, 1), cardHover = rgb(0.12, 0.16, 0.26, 1),
		cardFocus = rgb(0.12, 0.17, 0.27, 1), line = rgb(0.17, 0.22, 0.36, 1), lineSoft = rgb(0.17, 0.22, 0.36, 0.6),
		rowActive = rgb(0.95, 0.78, 0.3, 0.09), accent = rgb(0.95, 0.78, 0.3, 1), accent2 = rgb(0.35, 0.58, 1.0, 1),
		heroTop = rgb(0.08, 0.12, 0.26, 1), panel = rgb(0.04, 0.055, 0.1, 1) }) },
	{ id = "horde", label = "Horde", group = "Faction", colors = extend({
		bg = rgb(0.075, 0.047, 0.047, 0.97), header = rgb(0.095, 0.058, 0.058, 1), sidebar = rgb(0.09, 0.055, 0.055, 1),
		canvas = rgb(0.06, 0.038, 0.038, 1), card = rgb(0.14, 0.09, 0.09, 1), cardHover = rgb(0.18, 0.115, 0.115, 1),
		cardFocus = rgb(0.18, 0.11, 0.1, 1), line = rgb(0.26, 0.17, 0.17, 1), lineSoft = rgb(0.26, 0.17, 0.17, 0.6),
		rowActive = rgb(0.9, 0.25, 0.22, 0.09), accent = rgb(0.9, 0.25, 0.22, 1), accent2 = rgb(0.95, 0.62, 0.25, 1),
		heroTop = rgb(0.19, 0.07, 0.07, 1), panel = rgb(0.065, 0.04, 0.04, 1) }) },
	-- worked out when applied: your faction's palette, and the night palette in your class colour
	{ id = "faction", label = "My faction", group = "Faction" },
	{ id = "class", label = "Class colour", group = "Faction" },
}
T.THEME_BY_ID = {}
for _, th in ipairs(T.THEMES) do T.THEME_BY_ID[th.id] = th end

-- the same keys for what floats over the world: a copy of the palette
T.HUD = snapshot(T.C)

local function write(dst, src)
	for k, v in pairs(src) do
		local d = dst[k]
		if type(d) ~= "table" then d = {}; dst[k] = d end
		d[1], d[2], d[3], d[4] = v[1], v[2], v[3], v[4]
	end
end

local function mix(a, b, t) return a + (b - a) * t end

-- The colours of a theme id (the faction and class themes are worked out here) and its entry.
function T.ThemeColors(id)
	local th = T.THEME_BY_ID[id] or T.THEME_BY_ID.night
	if th.id == "faction" then
		local f = UnitFactionGroup and select(1, UnitFactionGroup("player"))
		th = T.THEME_BY_ID[f == "Horde" and "horde" or "alliance"]
	elseif th.id == "class" then
		local c = QL.PlayerClass and QL.PlayerClass().color or { 1, 1, 1 }
		local colors = snapshot(NIGHT)
		local a = { mix(c[1], 1, 0.12), mix(c[2], 1, 0.12), mix(c[3], 1, 0.12), 1 }
		colors.accent = a
		colors.accent2 = { mix(a[1], 1, 0.3), mix(a[2], 1, 0.3), mix(a[3], 1, 0.3), 1 }
		colors.rowActive = { a[1], a[2], a[3], 0.09 }
		return colors, T.THEME_BY_ID.night
	end
	return th.colors, th
end

function T.Apply(id)
	local colors, th = T.ThemeColors(id)
	write(T.C, colors)
	write(T.HUD, colors)
	T.themeId = T.THEME_BY_ID[id] and id or "night"
	T.applied = true
end

function T.PanelA(a)
	local p = T.HUD.panel
	return p[1], p[2], p[3], a or 1
end

function T.Wash(a)
	local w = T.C.wash
	return w[1], w[2], w[3], a or 1
end

-- Live switching ----------------------------------------------------------------------------------------
-- Colours were baked into textures and font strings when the frames were built, so a switch walks
-- every frame QuestLineage owns (named roots, then their children and regions) and maps each
-- region's colour from the OLD palette to the same key of the NEW one. Washes (low alpha) only
-- match the overlay keys, so a white icon never turns black. Gradients are painted again from the
-- palette tables they were made with.

local HUD_ROOTS = {
	QuestLineageArrow = true, QuestLineageCurrent = true, QuestLineageQuickBar = true,
	QuestLineageFlight = true, QuestLineageToasts = true, QuestLineageTooltip = true,
}
local LOW_ALPHA = { wash = true, rowHover = true, rowActive = true, track = true, lineSoft = false }

local function entriesOf(pal)
	local list = {}
	for key, v in pairs(pal) do
		list[#list + 1] = { key = key, r = v[1], g = v[2], b = v[3], a = type(v[4]) == "number" and v[4] or 1 }
	end
	return list
end

local TOL = 0.002
local function find(list, r, g, b, a)
	local best, bestD
	for _, e in ipairs(list) do
		if math.abs(e.r - r) <= TOL and math.abs(e.g - g) <= TOL and math.abs(e.b - b) <= TOL then
			local ok = true
			if e.key == "row" then ok = a < 0.01 end
			if LOW_ALPHA[e.key] then ok = a < 0.35 end
			if ok then
				local d = math.abs(e.a - a)
				if not bestD or d < bestD then best, bestD = e, d end
			end
		end
	end
	return best
end

local function remap(list, newPal, r, g, b, a)
	local e = find(list, r, g, b, a)
	if not e then return nil end
	local n = newPal[e.key]
	if not n then return nil end
	local na = type(n[4]) == "number" and n[4] or 1
	if math.abs(e.a - a) > 0.003 then na = a end -- the region has its own alpha: keep it
	return n[1], n[2], n[3], na
end

-- regions that show a fixed colour on purpose (the theme chips in the settings)
T.keepColor = setmetatable({}, { __mode = "k" })

local function paintRegion(region, lists, pals, hud)
	if T.keepColor[region] then return end
	local kind = region.GetObjectType and region:GetObjectType()
	local list, pal = lists[hud and 2 or 1], pals[hud and 2 or 1]
	if kind == "FontString" then
		local r, g, b, a = region:GetTextColor()
		if type(r) ~= "number" then return end
		local nr, ng, nb, na = remap(list, pal, r, g, b, a or 1)
		if nr then region:SetTextColor(nr, ng, nb, na) end
	elseif kind == "Texture" then
		if gradients[region] then return end
		local r, g, b, a = region:GetVertexColor()
		if type(r) ~= "number" then return end
		local nr, ng, nb, na = remap(list, pal, r, g, b, a or 1)
		if nr then region:SetVertexColor(nr, ng, nb, na) end
	end
end

local function walk(frame, lists, pals, hud, seen)
	if seen[frame] then return end
	seen[frame] = true
	if frame.GetRegions then
		for _, region in ipairs({ frame:GetRegions() }) do pcall(paintRegion, region, lists, pals, hud) end
	end
	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			if type(child) == "table" then walk(child, lists, pals, hud, seen) end
		end
	end
end

-- Change the theme now: palette, every open (and hidden) QuestLineage frame, then a redraw.
function T.Switch(id)
	local oldC, oldH = snapshot(T.C), snapshot(T.HUD)
	local lists = { entriesOf(oldC), entriesOf(oldH) }
	T.Apply(id)
	local pals = { T.C, T.HUD }
	local seen = {}
	local names = {}
	for name, v in pairs(_G) do
		if type(name) == "string" and name:sub(1, 12) == "QuestLineage" and type(v) == "table" and v.GetChildren and v.GetRegions then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	for _, name in ipairs(names) do
		pcall(walk, _G[name], lists, pals, HUD_ROOTS[name] and true or false, seen)
	end
	for tex, g in pairs(gradients) do pcall(T.Gradient, tex, g[1], g[2], g[3]) end
	if QL.Fire then QL.Fire("THEME_CHANGED", id) end
end

QL.Event("ADDON_LOADED", function(_, name)
	if name ~= "QuestLineage" or T.applied then return end
	local db = QL.DB()
	if not T.THEME_BY_ID[db.theme] then db.theme = "night" end -- a theme that no longer exists
	pcall(T.Apply, db.theme)
end)
QL.Event("PLAYER_LOGIN", function()
	if not T.applied then pcall(T.Apply, QL.DB().theme or "night") end
end)

QL.On("SETTING_CHANGED", function(key, value)
	if key == "theme" and T.applied and T.themeId ~= value then
		pcall(T.Switch, value or "night")
	end
end)
QL.On("THEME_CHANGED", function()
	if QL.RenderWindow then pcall(QL.RenderWindow, false) end
	if QL.RefreshCurrent then pcall(QL.RefreshCurrent) end
	if QL.UpdateArrow then pcall(QL.UpdateArrow) end
	if QL.RefreshOptions then pcall(QL.RefreshOptions) end
end)
