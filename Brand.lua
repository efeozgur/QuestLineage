-- The author's mark: every OzgurX addon carries the same violet "OX" sign and name, so players
-- recognise them. This file is meant to be copied as it is into each addon (only ADDON changes);
-- nothing is shared between addons at run time.
--
--   QL.Brand.name / color / hex / icon   the mark's name, violet colour and 64x64 "OX" disc
--   QL.Brand.Tag()                       "[OX]" in the brand colour (chat, lists)
--   QL.Brand.Signed()                    "by OzgurX" (localised), the name in the brand colour
--   QL.Brand.Badge(parent)               a small button: the disc + "by OzgurX", own tooltip
local ADDON, QL = ...
QL = QL or {}

local B = {
	name = "OzgurX",
	color = { 0.545, 0.486, 0.965 }, -- #8B7CF6
	hex = "8b7cf6",
	icon = "Interface\\AddOns\\" .. (ADDON or "QuestLineage") .. "\\Media\\ozgurx",
}
QL.Brand = B

local function L(s) return QL.L and QL.L(s) or s end

function B.Tag()
	return "|cff" .. B.hex .. "[OX]|r"
end

function B.Signed()
	return (L("by %s"):gsub("%%s", "|cff" .. B.hex .. B.name .. "|r"))
end

function B.Badge(parent)
	local T = QL.Theme
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(90, 18)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(B.icon)
	icon:SetSize(14, 14)
	icon:SetPoint("LEFT")
	b.icon = icon
	local text = T and T.Text(b, 10, T.C.dim) or b:CreateFontString(nil, "OVERLAY")
	text:SetPoint("LEFT", icon, "RIGHT", 5, 0)
	b.text = text
	function b:Refresh()
		self.text:SetText(B.Signed())
		local w = self.text.GetStringWidth and self.text:GetStringWidth()
		if type(w) == "number" and w > 0 then self:SetWidth(w + 19) end
	end
	b:Refresh()
	b:SetScript("OnEnter", function(self)
		self.icon:SetAlpha(1)
		if not QL.Tip then return end
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_BOTTOM")
		tip:AddLine(B.name, B.color[1], B.color[2], B.color[3])
		tip:AddLine(L("Made by OzgurX. Look for the [OX] mark in your AddOns list."), 0.8, 0.8, 0.85)
		tip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.icon:SetAlpha(0.85)
		if QL.Tip then QL.Tip():Hide() end
	end)
	icon:SetAlpha(0.85)
	return b
end
