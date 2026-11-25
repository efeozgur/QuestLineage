-- QuestLineage's own direction arrow: a heads-up arrow that turns toward the quest's current
-- spot (its giver, the nearest creature or object for its unfinished objectives, or where it is
-- handed in), with the quest's name, the distance and what to do there.
--
--   QL.SetArrowTarget(questId)   point at a quest (kept per character across reloads)
--   QL.ClearArrow()
--   QL.ArrowQuest() -> questId | nil
--
-- Colour (setting arrowColorMode): by direction (the accent when you face it, amber to the side,
-- red behind; the default), the theme's accent, or a colour of your own (arrowColor).
-- Size: arrowScale. Glow: arrowGlow. While the settings page is open the arrow shows a turning
-- preview when it has no quest (QL.ArrowPreview).
-- Left-drag moves it (arrowPoint), right-click stops it. It follows the quest: once the
-- objectives are done it turns to the hand-in; when the quest is handed in it says so and stops.

local _, QL = ...

local MEDIA = "Interface\\AddOns\\QuestLineage\\Media\\"
local ARRIVED = 10      -- yards
local UPDATE = 0.03     -- seconds between updates

local frame, target, questId
local elapsedSince = 0

local function L(s) return QL.L(s) end

local function charKey()
	local name = UnitName and UnitName("player") or "?"
	local realm = GetRealmName and GetRealmName() or "?"
	return tostring(name) .. "-" .. tostring(realm)
end

local function saved()
	local db = QL.DB()
	if type(db.arrowTargets) ~= "table" then db.arrowTargets = {} end
	return db.arrowTargets
end

local function blend(a, b, t)
	return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

-- Facing accuracy -> colour: 1 ahead (accent), 0.5 to the side (amber), 0 behind (red).
local AMBER = { 0.984, 0.749, 0.141 }
function QL.ArrowColor(rotation)
	local C = QL.Theme.C
	local err = math.abs(((rotation + math.pi) % (2 * math.pi)) - math.pi)
	local accuracy = 1 - err / math.pi
	if accuracy >= 0.5 then return blend(AMBER, C.accent, (accuracy - 0.5) * 2) end
	return blend(C.danger, AMBER, accuracy * 2)
end

-- The arrow's colour for a rotation, by the colour setting.
function QL.ArrowTint(rotation)
	local db, C = QL.DB(), QL.Theme.C
	if db.arrowColorMode == "accent" then return C.accent[1], C.accent[2], C.accent[3] end
	if db.arrowColorMode == "custom" and type(db.arrowColor) == "table" then
		return db.arrowColor[1] or 1, db.arrowColor[2] or 1, db.arrowColor[3] or 1
	end
	return QL.ArrowColor(rotation or 0)
end

local preview = false

-- Size and glow from the settings; called on build and on every setting change.
function QL.ApplyArrowSettings()
	if not frame then return end
	local db = QL.DB()
	local scale = tonumber(db.arrowScale) or 1
	if scale < 0.4 then scale = 0.4 elseif scale > 2.5 then scale = 2.5 end
	frame:SetScale(scale)
	frame.glow:SetShown(db.arrowGlow ~= false)
end

local function build()
	local T, C = QL.Theme, QL.Theme.C
	local f = CreateFrame("Frame", "QuestLineageArrow", UIParent)
	frame = f
	f:SetSize(150, 150)
	local p = QL.DB().arrowPoint
	if type(p) == "table" and p[1] then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end
	-- Above the QuestLineage window (HIGH, nearly full screen): in MEDIUM the arrow sat behind it
	-- and never showed while the window was open.
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(50)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint(1)
		QL.DB().arrowPoint = { point, relPoint, x, y }
	end)
	f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then QL.ClearArrow() end end)

	f.title = T.Text(f, 13, C.text)
	f.title:SetPoint("TOP", 0, 0)
	f.title:SetJustifyH("CENTER")
	f.title:SetWidth(240)
	f.title:SetShadowOffset(1, -1)

	f.glow = f:CreateTexture(nil, "BACKGROUND")
	f.glow:SetTexture(MEDIA .. "arrow_glow")
	f.glow:SetSize(104, 104)
	f.glow:SetPoint("CENTER", 0, 6)
	f.arrow = f:CreateTexture(nil, "ARTWORK")
	f.arrow:SetTexture(MEDIA .. "arrow")
	f.arrow:SetSize(62, 62)
	f.arrow:SetPoint("CENTER", 0, 6)
	f.shade = f:CreateTexture(nil, "ARTWORK", nil, 1)
	f.shade:SetTexture(MEDIA .. "arrow_shade")
	f.shade:SetAllPoints(f.arrow)

	f.dist = T.Text(f, 17, C.text)
	f.dist:SetPoint("TOP", f.arrow, "BOTTOM", 0, -6)
	f.dist:SetJustifyH("CENTER")
	f.dist:SetShadowOffset(1, -1)
	f.label = T.Text(f, 11, C.muted)
	f.label:SetPoint("TOP", f.dist, "BOTTOM", 0, -3)
	f.label:SetJustifyH("CENTER")
	f.label:SetWidth(240)
	f.label:SetShadowOffset(1, -1)

	f:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		if questId then QL.FillQuestTooltip(GameTooltip, questId) end
		GameTooltip:AddLine(L("Drag: move · Right-click: stop"), 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	QL.ApplyArrowSettings()
	f:SetScript("OnUpdate", function(_, elapsed)
		elapsedSince = elapsedSince + (elapsed or 0)
		if elapsedSince < UPDATE then return end
		elapsedSince = 0
		local ok, err = pcall(QL.UpdateArrow)
		if not ok then QL.Debug("arrow: " .. tostring(err)) end
	end)
	f:Hide()
end

local function setRotation(r)
	frame.arrow:SetRotation(r)
	frame.shade:SetRotation(r)
end

-- A slowly turning sample for the settings page.
local function drawPreview()
	local t = GetTime and GetTime() or 0
	local rot = (t * 0.9) % (2 * math.pi)
	frame.arrow:SetRotation(rot)
	frame.shade:SetRotation(rot)
	local r, g, b = QL.ArrowTint(rot)
	frame.arrow:SetVertexColor(r, g, b, 1)
	frame.glow:SetVertexColor(r, g, b, 1)
	frame.glow:SetAlpha(0.32)
	frame.title:SetText(L("Arrow preview"))
	frame.dist:SetText(L("%d yd"):format(120))
	frame.label:SetText(L("Drag: move · Right-click: stop"))
end

function QL.UpdateArrow()
	if not frame then return end
	if not target then
		if preview then drawPreview() end
		return
	end
	local loc = QL.Locate(target)
	frame.title:SetText(QL.QuestTitle(questId))
	frame.label:SetText(target.label or "")
	if not loc then
		setRotation(0)
		frame.arrow:SetVertexColor(0.5, 0.5, 0.5, 0.5)
		frame.glow:SetAlpha(0)
		frame.dist:SetText(#target.points == 0 and L("No location data") or L("No position here"))
		return
	end
	if loc.otherMap then
		setRotation(0)
		frame.arrow:SetVertexColor(0.6, 0.6, 0.65, 0.45)
		frame.glow:SetAlpha(0)
		frame.dist:SetText(L("Head to %s"):format(QL.MapName(loc.otherMap.map) or "?"))
		return
	end
	local C = QL.Theme.C
	if loc.dist < ARRIVED then
		setRotation(0)
		local g = QL.Theme.STATUS.done
		frame.arrow:SetVertexColor(g[1], g[2], g[3], 0.9)
		frame.glow:SetVertexColor(g[1], g[2], g[3], 1)
		frame.glow:SetAlpha(0.55)
		frame.dist:SetText(target.kind == "objective" and L("You are there: look around") or L("Arrived"))
		return
	end
	local facing = GetPlayerFacing and GetPlayerFacing()
	if facing ~= nil and issecretvalue and issecretvalue(facing) then facing = nil end
	local r, g, b = QL.ArrowTint(0)
	if facing then
		local rot = QL.Bearing(loc.dx, loc.dy, facing)
		setRotation(rot)
		r, g, b = QL.ArrowTint(rot)
	end
	frame.arrow:SetVertexColor(r, g, b, 1)
	frame.glow:SetVertexColor(r, g, b, 1)
	frame.glow:SetAlpha(0.32)
	frame.dist:SetText(L("%d yd"):format(math.floor(loc.dist + 0.5)))
end

-- Rebuild the target from the quest's state (pick up -> objectives -> hand in).
local function refreshTarget()
	if not questId then return end
	local ctx = QL.Context()
	if QL.NodeStatus(questId, ctx) == "done" then
		QL.Print(L("Quest handed in: ") .. QL.QuestTitle(questId))
		QL.ClearArrow()
		QL.Fire("ARROW_QUEST_DONE")
		return
	end
	local new = QL.QuestTarget(questId, ctx)
	if not new then QL.ClearArrow(); return end
	if not target or new.kind ~= target.kind or new.label ~= target.label then target = new end
end

function QL.SetArrowTarget(id, quiet)
	id = tonumber(id)
	if not id then return end
	if not frame and CreateFrame then
		local ok, err = pcall(build)
		if not ok then QL.Debug("arrow build: " .. tostring(err)); QL.Print(L("The arrow could not be built: /ql errors")); return end
	end
	local changed = questId ~= id
	questId = id
	target = nil
	refreshTarget()
	if not target then
		if not quiet then QL.Print(L("Nothing to point at for: ") .. QL.QuestTitle(id)) end
		return
	end
	saved()[charKey()] = id
	if frame then
		frame:Show()
		pcall(QL.UpdateArrow)
	end
	if changed and not quiet then
		QL.Print(L("Arrow: ") .. QL.QuestTitle(id) .. "  ·  " .. (target.label or ""))
	end
	QL.Fire("ARROW_CHANGED", id)
end

-- /ql arrow: what the arrow knows, step by step, to find why it does not show.
function QL.ArrowDebug(arg)
	local id = tonumber(arg)
	if id then QL.SetArrowTarget(id) end
	QL.Print(L("Arrow quest: ") .. tostring(questId) .. (questId and (" (" .. QL.QuestTitle(questId) .. ")") or ""))
	if not frame then QL.Print(L("Arrow frame: not built yet (pick a quest in the Quests list)")); return end
	local point, _, relPoint, x, y = frame:GetPoint(1)
	QL.Print(("frame: shown=%s visible=%s strata=%s alpha=%.2f scale=%.2f point=%s %s %.0f,%.0f"):format(
		tostring(frame:IsShown()), tostring(frame:IsVisible()), tostring(frame:GetFrameStrata()),
		frame:GetAlpha() or -1, frame:GetEffectiveScale() or -1, tostring(point), tostring(relPoint), x or 0, y or 0))
	QL.Print("texture: " .. tostring(frame.arrow:GetTexture()))
	if not target then QL.Print(L("No target.")); return end
	QL.Print(("target: %s · %d points · %s"):format(target.kind, #target.points, tostring(target.label)))
	local p1 = target.points[1]
	if p1 then QL.Print(("first point: map %s at %.3f, %.3f"):format(tostring(p1.map), p1.x, p1.y)) end
	local map, px, py = QL.PlayerPosition()
	QL.Print(("player: map %s at %s, %s · facing %s"):format(tostring(map), tostring(px), tostring(py), tostring(GetPlayerFacing and GetPlayerFacing())))
	local loc = QL.Locate(target)
	if not loc then QL.Print("locate: nil")
	elseif loc.otherMap then QL.Print("locate: other map " .. tostring(loc.otherMap.map))
	else QL.Print(("locate: %.0f yd (dx %.0f, dy %.0f)"):format(loc.dist, loc.dx, loc.dy)) end
end

function QL.ClearArrow()
	questId, target = nil, nil
	saved()[charKey()] = nil
	if frame and not preview then frame:Hide() end
	QL.Fire("ARROW_CHANGED", nil)
end

-- The settings page shows the arrow while it is open, so size and colour changes can be seen.
function QL.ArrowPreview(on)
	preview = on and true or false
	if preview then
		if not frame and CreateFrame then
			local ok, err = pcall(build)
			if not ok then QL.Debug("arrow build: " .. tostring(err)); preview = false; return end
		end
		frame:Show()
		pcall(QL.UpdateArrow)
	elseif frame and not target then
		frame:Hide()
	end
end

function QL.ResetArrowPosition()
	QL.DB().arrowPoint = nil
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
	end
end

function QL.ArrowQuest() return questId end
function QL.ArrowTarget() return target end

QL.On("SETTING_CHANGED", function(key)
	if type(key) == "string" and key:sub(1, 5) == "arrow" then
		QL.ApplyArrowSettings()
		if frame and frame:IsShown() then pcall(QL.UpdateArrow) end
	end
end)

-- quest log changes move the arrow along (objectives done -> hand in; handed in -> stop)
QL.On("STATE_CHANGED", function()
	if questId then
		local ok, err = pcall(refreshTarget)
		if not ok then QL.Debug("arrow target: " .. tostring(err)) end
	end
end)

-- A handed-in quest leaves the log before the client may report it completed; without this it
-- could read as "available" for a moment and the arrow would turn back to its giver.
QL.Event("QUEST_TURNED_IN", function(_, id)
	if id and id == questId then
		QL.Print(L("Quest handed in: ") .. QL.QuestTitle(questId))
		QL.ClearArrow()
		QL.Fire("ARROW_QUEST_DONE", id)
	end
end)

QL.Event("PLAYER_LOGIN", function()
	local id = saved()[charKey()]
	if id then QL.WhenIndexed(function() QL.SetArrowTarget(id, true) end) end
end)
