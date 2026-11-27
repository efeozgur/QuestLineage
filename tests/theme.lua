-- Themes: every palette complete and readable, applying keeps the tables, the default is unchanged.
local QL = { }
QL.handlers = {}
function QL.On() end
function QL.Event() end
function QL.DB() return {} end
function QL.L(s) return s end
local T
do
	local chunk = assert(loadfile("Theme.lua"))
	chunk("QuestLineage", QL)
	T = QL.Theme
end

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local function lum(c)
	local function lin(v) v = v or 0; if v <= 0.03928 then return v / 12.92 end return ((v + 0.055) / 1.055) ^ 2.4 end
	return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3])
end
local function ratio(a, b)
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

local keys = { "bg", "header", "sidebar", "canvas", "card", "cardHover", "cardFocus", "row", "rowHover", "rowActive",
	"line", "lineSoft", "text", "muted", "dim", "accent", "accent2", "heroTop", "danger", "track", "panel", "wash" }

-- the default theme is the look the addon always had
local nightBefore = {}
for _, k in ipairs(keys) do nightBefore[k] = { T.C[k][1], T.C[k][2], T.C[k][3], T.C[k][4] } end
local accentTable, textTable = T.C.accent, T.C.text

for _, th in ipairs(T.THEMES) do
	local colors = T.ThemeColors(th.id)
	for _, k in ipairs(keys) do
		local v = colors[k]
		Check(type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number", th.id .. "." .. k .. " is a colour")
		Check(v == nil or v[4] == nil or type(v[4]) == "number", th.id .. "." .. k .. ": slot 4 only a number")
	end
	-- the text must read on the window ground, the accent on the cards
	Check(ratio(colors.text, colors.bg) >= 7, th.id .. ": text on bg contrast " .. ratio(colors.text, colors.bg))
	Check(ratio(colors.text, colors.card) >= 7, th.id .. ": text on card contrast")
	Check(ratio(colors.muted, colors.bg) >= 3.4, th.id .. ": muted on bg contrast " .. ratio(colors.muted, colors.bg))
	Check(ratio(colors.accent, colors.card) >= 3, th.id .. ": accent on card contrast " .. ratio(colors.accent, colors.card))
end

T.Apply("forest")
Check(T.C.accent == accentTable and T.C.text == textTable, "applying a theme keeps the palette tables (modules hold references)")
Check(T.C.accent[1] < 0.5 and T.C.accent[2] > 0.8, "the forest accent is green")
Check(T.HUD.accent[2] > 0.8, "the floating palette follows the theme")
T.Apply("night")
local same = true
for _, k in ipairs(keys) do
	for i = 1, 4 do if T.C[k][i] ~= nightBefore[k][i] then same = false end end
end
Check(same, "night gives back the original palette exactly")
Check(select(1, T.Wash(0.5)) == 1, "night: the wash is light")
T.Apply("no-such-theme")
Check(T.C.accent[2] > 0.8 and T.C.accent[1] < 0.3, "an unknown id falls back to night")

-- Live switching: a fake frame tree, painted by value ------------------------------------------------
local function region(kind, r, g, b, a)
	local o = { kind = kind, c = { r, g, b, a } }
	function o:GetObjectType() return self.kind end
	function o:GetVertexColor() return self.c[1], self.c[2], self.c[3], self.c[4] end
	function o:SetVertexColor(r2, g2, b2, a2) self.c = { r2, g2, b2, a2 } end
	function o:GetTextColor() return self.c[1], self.c[2], self.c[3], self.c[4] end
	function o:SetTextColor(r2, g2, b2, a2) self.c = { r2, g2, b2, a2 } end
	return o
end
local function frame(regions, children)
	local f = { regions = regions or {}, children = children or {} }
	function f:GetRegions() return unpack(self.regions) end
	function f:GetChildren() return unpack(self.children) end
	return f
end
local function near(c, v) return math.abs(c[1] - v[1]) < 1e-6 and math.abs(c[2] - v[2]) < 1e-6 and math.abs(c[3] - v[3]) < 1e-6 end

T.Apply("night")
local N = T.C
local fill = region("Texture", N.card[1], N.card[2], N.card[3], 1)
local text = region("FontString", N.text[1], N.text[2], N.text[3], 1)
local muted = region("FontString", N.muted[1], N.muted[2], N.muted[3], 1)
local icon = region("Texture", 1, 1, 1, 1)
local wash = region("Texture", 1, 1, 1, 0.03)
local idle = region("Texture", 0, 0, 0, 0)
local grad = region("Texture", N.accent[1], N.accent[2], N.accent[3], 1)
local chip = region("Texture", N.card[1], N.card[2], N.card[3], 1)
T.keepColor[chip] = true
T.Gradient(grad, "HORIZONTAL", T.C.accent, T.C.accent2)
QuestLineageFrame = frame({ fill, text, icon }, { frame({ muted, wash, idle, grad, chip }) })
local hudText = region("FontString", N.text[1], N.text[2], N.text[3], 1)
QuestLineageArrow = frame({ hudText })

T.Switch("forest")
local F = T.C
Check(near(fill.c, F.card), "a fill follows the card colour: " .. table.concat(fill.c, ","))
Check(near(text.c, F.text) and near(muted.c, F.muted), "text colours follow")
Check(icon.c[1] == 1 and icon.c[2] == 1 and icon.c[4] == 1, "a white icon is left alone")
Check(near(chip.c, N_card_night or { 0.094, 0.11, 0.141 }), "a chip kept on purpose is left alone")
Check(near(grad.c, F.accent), "a gradient is painted again from the palette")
Check(idle.c[4] == 0, "an invisible fill stays invisible")

T.Switch("night")
Check(near(fill.c, { 0.094, 0.11, 0.141 }), "back to night: the fill is the original colour")
Check(near(text.c, { 0.925, 0.937, 0.957 }), "back to night: the text too")
Check(math.abs(wash.c[1] - 1) < 1e-6, "back to night: the wash is light again")

if failures > 0 then error(failures .. " theme check(s) failed") end
print("theme: ok")
