-- Nameplates: a small quest badge and the counter ("3/8") beside the nameplate of every creature
-- an unfinished objective of a quest in your log needs: to slay, or that drops an item you still
-- collect. Setting nameplates.
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
					elseif row.task.kind == "item" then
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
	if row.need and row.need > 0 then return ("%d/%d"):format(row.have or 0, row.need) end
	return ""
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
	-- beside the health bar when the plate has the usual parts, else beside the plate
	local uf = plate.UnitFrame
	local anchor = (type(uf) == "table" and type(uf.healthBar) == "table") and uf.healthBar or plate
	b:SetPoint("RIGHT", anchor, "LEFT", -3, 0)
	b.icon = b:CreateTexture(nil, "OVERLAY")
	b.icon:SetTexture(MEDIA .. "quest_mark")
	b.icon:SetAllPoints()
	b.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
	b.text = b:CreateFontString(nil, "OVERLAY")
	T.SetFont(b.text, 11, true, "OUTLINE")
	b.text:SetPoint("RIGHT", b, "LEFT", -2, 0)
	b.text:SetTextColor(1, 1, 1, 1)
	badges[plate] = b
	return b
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
QL.On("SETTING_CHANGED", function(key) if key == "nameplates" then pcall(QL.RefreshPlates) end end)
