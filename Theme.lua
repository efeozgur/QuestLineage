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
function T.SetFont(fs, size, bold, flags)
	if type(fs) ~= "table" or not fs.SetFont then return end
	size = math.max(8, math.floor((size or 12) * 0.92 + 0.5))
	flags = flags or ""
	local list = { bold and T.FONT_BOLD or T.FONT }
	for _, f in ipairs(T.FONT_FALLBACKS) do list[#list + 1] = f end
	for _, path in ipairs(list) do
		local ok, set = pcall(fs.SetFont, fs, path, size, flags)
		if ok and set ~= false then return path end
	end
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
}

-- A quest's state: colour and label.
T.STATUS = {
	done      = { 0.133, 0.773, 0.369, "Done" },
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
function T.Gradient(tex, direction, c1, c2)
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
