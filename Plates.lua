-- Nameplates: a small quest badge and the counter ("3/8") beside the nameplate of every creature
-- an unfinished objective of a quest in your log needs: to slay, or that drops an item you still
-- collect. Settings: nameplates (on/off), plateSide (left | right | top), plateColorMode (accent |
-- difficulty | custom) with plateColor, plateScale, plateCount (the counter), plateDroppers (item
-- droppers too).
--
-- Index (rebuilt when the quest log changes): npc id -> the objective rows it counts for
-- (QL.ObjectiveRows; an item objective's droppers from the item's npcDrops). Badges are our own
-- frames on the nameplate, never on a forbidden one, and hidden again when the plate goes.
--
--   QL.PlateIndex() -> { [npcId] = { {questId, row}, ... } }
--   QL.PlateText(npcId) -> "3/8" | "" | nil (nil: no badge)

local _, QL = ...

local MEDIA = "Interface\\AddOns\\QuestLineage\\Media\\"
local MAX_DROPPERS = 10

local index
local badges = setmetatable({}, { __mode = "k" }) -- plate -> badge

local function rebuild()
	index = {}
	local ctx = QL.Context()
	for id in pairs(ctx.log) do
		if not (ctx.complete and ctx.complete[id]) then
			for _, row in ipairs(QL.ObjectiveRows(id, ctx)) do
				if not row.done and row.task then
					local npcs = {}
					if row.task.kind == "npc" then
						npcs[1] = row.task.id
					elseif row.task.kind == "item" and QL.DB().plateDroppers ~= false then
						for n, npc in ipairs(QL.Ids(QL.I(row.task.id, "npcDrops"))) do
							if n > MAX_DROPPERS then break end
							npcs[#npcs + 1] = npc
						end
					end
					for _, npc in ipairs(npcs) do
						local list = index[npc]
						if not list then list = {}; index[npc] = list end
						list[#list + 1] = { id, row }
					end
				end
			end
		end
	end
	return index
end

function QL.PlateIndex()
	return index or rebuild()
end

function QL.PlateText(npcId)
	local list = QL.PlateIndex()[npcId]
	if not list then return nil end
	local row = list[1][2]
	if QL.DB().plateCount == false then return "" end
	if row.need and row.need > 0 then return ("%d/%d"):format(row.have or 0, row.need) end
	return ""
end

-- The badge's colour for an npc: the theme's accent, the difficulty of the quest it counts for,
-- or the player's own.
function QL.PlateColor(npcId)
	local db, C = QL.DB(), QL.Theme.C
	if db.plateColorMode == "custom" and type(db.plateColor) == "table" then
		return db.plateColor[1] or 1, db.plateColor[2] or 1, db.plateColor[3] or 1
	end
	if db.plateColorMode == "difficulty" then
		local list = QL.PlateIndex()[npcId]
		local c
		if list then
			local _, dc = QL.QuestDifficulty(QL.QuestLevel(list[1][1]), QL.Context().level)
			c = dc
		end
		if c then return c[1], c[2], c[3] end
	end
	return C.accent[1], C.accent[2], C.accent[3]
end

local function npcIdOf(unit)
	if not UnitGUID then return nil end
	local ok, guid = pcall(UnitGUID, unit)
	if not ok or type(guid) ~= "string" then return nil end
	if issecretvalue and issecretvalue(guid) then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end

local function plateFor(unit)
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok or not plate then return nil end
	if plate.IsForbidden and plate:IsForbidden() then return nil end
	return plate
end

local function badgeFor(plate)
	local b = badges[plate]
	if b then return b end
	local T, C = QL.Theme, QL.Theme.C
	b = CreateFrame("Frame", nil, plate)
	b:SetSize(16, 16)
	b.icon = b:CreateTexture(nil, "OVERLAY")
	b.icon:SetTexture(MEDIA .. "quest_mark")
	b.icon:SetAllPoints()
	b.text = b:CreateFontString(nil, "OVERLAY")
	T.SetFont(b.text, 11, true, "OUTLINE")
	b.text:SetTextColor(1, 1, 1, 1)
	b.plate = plate
	badges[plate] = b
	return b
end

-- Where the badge sits, by plateSide: left or right of the health bar (the counter on the outer
-- side), or above the name (the counter after the badge).
local function placeBadge(b)
	local plate = b.plate
	local uf = plate.UnitFrame
	local bar = (type(uf) == "table" and type(uf.healthBar) == "table") and uf.healthBar or plate
	local name = (type(uf) == "table" and type(uf.name) == "table") and uf.name or bar
	local side = QL.DB().plateSide or "left"
	b:ClearAllPoints()
	b.text:ClearAllPoints()
	if side == "right" then
		b:SetPoint("LEFT", bar, "RIGHT", 3, 0)
		b.text:SetPoint("LEFT", b, "RIGHT", 2, 0)
	elseif side == "top" then
		b:SetPoint("BOTTOM", name, "TOP", -10, 2)
		b.text:SetPoint("LEFT", b, "RIGHT", 2, 0)
	else
		b:SetPoint("RIGHT", bar, "LEFT", -3, 0)
		b.text:SetPoint("RIGHT", b, "LEFT", -2, 0)
	end
	b.side = side
	b:SetScale(tonumber(QL.DB().plateScale) or 1)
end

function QL.UpdatePlate(unit)
	local plate = plateFor(unit)
	if not plate then return end
	local text = QL.DB().nameplates ~= false and npcIdOf(unit) and QL.PlateText(npcIdOf(unit)) or nil
	if not text then
		if badges[plate] then badges[plate]:Hide() end
		return
	end
	local b = badgeFor(plate)
	placeBadge(b)
	b.icon:SetVertexColor(QL.PlateColor(npcIdOf(unit)))
	b.text:SetText(text)
	b:Show()
end

function QL.RefreshPlates()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not ok or type(plates) ~= "table" then return end
	for _, plate in ipairs(plates) do
		local uf = plate.UnitFrame
		local unit = plate.namePlateUnitToken or (type(uf) == "table" and uf.unit) or nil
		if unit then pcall(QL.UpdatePlate, unit) end
	end
end

QL.Event("NAME_PLATE_UNIT_ADDED", function(_, unit)
	local ok, err = pcall(QL.UpdatePlate, unit)
	if not ok then QL.Debug("plate: " .. tostring(err)) end
end)
QL.Event("NAME_PLATE_UNIT_REMOVED", function(_, unit)
	local plate = plateFor(unit)
	if plate and badges[plate] then badges[plate]:Hide() end
end)
QL.On("STATE_CHANGED", function() index = nil; pcall(QL.RefreshPlates) end)
QL.On("INDEX_READY", function() index = nil; pcall(QL.RefreshPlates) end)
QL.On("SETTING_CHANGED", function(key)
	if key == "nameplates" or (type(key) == "string" and key:sub(1, 5) == "plate") then
		index = nil -- plateDroppers changes what is indexed
		pcall(QL.RefreshPlates)
	end
end)
