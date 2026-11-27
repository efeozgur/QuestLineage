-- QuestLineage's own direction arrow: a heads-up arrow that turns toward the quest's current
-- spot (its giver, the nearest creature or object for its unfinished objectives, or where it is
-- handed in), with the quest's name, the distance and what to do there.
--
--   QL.SetArrowTarget(questId)   point at a quest (kept per character across reloads)
--   QL.ClearArrow()
--   QL.ArrowQuest() -> questId | nil
--   QL.SetArrowPlace(kind, id, { title, label, questId })   point at an NPC, object or an item's
--       drop spots instead of a quest's current stage (a fixed target: it does not follow the quest)
--
-- Colour (setting arrowColorMode): by direction (the accent when you face it, amber to the side,
-- red behind; the default), the theme's accent, or a colour of your own (arrowColor).
-- Look (setting arrowStyle): "theme" (default; the arrow sits on a dark round plate with a thin ring in
-- the arrow's colour, like the windows) or "classic" (the bare arrow).
-- Size: arrowScale. Glow: arrowGlow. While the settings page is open the arrow shows a turning
-- preview when it has no quest (QL.ArrowPreview).
-- Left-drag moves it (arrowPoint), right-click stops it. It follows the quest: once the
-- objectives are done it turns to the hand-in; when the quest is handed in it says so and stops.

local _, QL = ...

local MEDIA = "Interface\\AddOns\\QuestLineage\\Media\\"
local ARRIVED = 10      -- yards
local UPDATE = 0.03     -- seconds between updates
local ARROW_SIZE = 62   -- the arrow's size in the classic look (the theme look: THEME_ARROW on a PLATE)
local THEME_ARROW, PLATE = 40, 82
local arrowPx = ARROW_SIZE -- the arrow's size now (set by the style)
local coreSize = ARROW_SIZE -- the visual size of the arrow with its plate (the text sits below it)

local frame, target, questId
local hopTarget -- the travel step the arrow leads to (Travel.lua), kept so its projection is cached
local HOP_AT = 25
local hopSpot -- where the arrow leads now on the way (a travel step's place), nil otherwise

-- The place the arrow leads to on the way (flight master, dock, tram), for detours drawn to it.
function QL.ArrowHop() return hopSpot end
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
	local C = QL.Theme.HUD
	local err = math.abs(((rotation + math.pi) % (2 * math.pi)) - math.pi)
	local accuracy = 1 - err / math.pi
	if accuracy >= 0.5 then return blend(AMBER, C.accent, (accuracy - 0.5) * 2) end
	return blend(C.danger, AMBER, accuracy * 2)
end

-- The arrow's colour for a rotation, by the colour setting.
function QL.ArrowTint(rotation)
	local db, C = QL.DB(), QL.Theme.HUD
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
	local themed = db.arrowStyle ~= "classic"
	arrowPx = themed and THEME_ARROW or ARROW_SIZE
	coreSize = themed and PLATE or ARROW_SIZE
	frame.plate:SetShown(themed)
	frame.rim:SetShown(themed)
	frame.core:SetSize(coreSize, coreSize)
	frame.plate:SetSize(PLATE, PLATE)
	frame.rim:SetSize(PLATE, PLATE)
	frame.glow:SetSize(themed and 116 or 104, themed and 116 or 104)
	frame.arrow:SetSize(arrowPx, arrowPx)
	frame.ring:SetSize(coreSize, coreSize)
end

local function build()
	local T, C = QL.Theme, QL.Theme.HUD
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

	-- soft dark bands behind the two text lines (fading at both ends) keep them readable on bright ground
	local function band()
		local b = { left = f:CreateTexture(nil, "BACKGROUND", nil, -2), right = f:CreateTexture(nil, "BACKGROUND", nil, -2) }
		for _, t in pairs(b) do t:SetTexture(T.WHITE) end
		T.Gradient(b.left, "HORIZONTAL", { 0.03, 0.04, 0.06, 0 }, { 0.03, 0.04, 0.06, 0.62 })
		T.Gradient(b.right, "HORIZONTAL", { 0.03, 0.04, 0.06, 0.62 }, { 0.03, 0.04, 0.06, 0 })
		return b
	end
	f.titleBand, f.labelBand = band(), band()
	f.title = T.Text(f, 13, C.text, nil, true)
	f.title:SetPoint("TOP", 0, 0)
	f.title:SetJustifyH("CENTER")
	f.title:SetWidth(240)
	f.title:SetShadowOffset(1, -1)

	-- the arrow's footprint: the text lines hang below it
	f.core = f:CreateTexture(nil, "BACKGROUND")
	f.core:SetSize(ARROW_SIZE, ARROW_SIZE)
	f.core:SetPoint("CENTER", 0, 6)
	f.glow = f:CreateTexture(nil, "BACKGROUND")
	f.glow:SetTexture(MEDIA .. "arrow_glow")
	f.glow:SetSize(104, 104)
	f.glow:SetPoint("CENTER", 0, 6)
	-- the theme look: a dark round plate and a thin ring in the arrow's colour
	f.plate = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.plate:SetTexture(MEDIA .. "disc")
	f.plate:SetVertexColor(QL.Theme.PanelA(0.9))
	f.plate:SetPoint("CENTER", f.core, "CENTER", 0, 0)
	f.rim = f:CreateTexture(nil, "BACKGROUND", nil, 2)
	f.rim:SetTexture(MEDIA .. "ring")
	f.rim:SetPoint("CENTER", f.core, "CENTER", 0, 0)
	f.arrow = f:CreateTexture(nil, "ARTWORK")
	f.arrow:SetTexture(MEDIA .. "arrow")
	f.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
	f.arrow:SetPoint("CENTER", f.core, "CENTER", 0, 0)
	-- the arrival ring (the quest-marker ring texture), grown and faded once on arrival
	f.ring = f:CreateTexture(nil, "ARTWORK", nil, -1)
	f.ring:SetTexture(MEDIA .. "ring")
	f.ring:SetSize(ARROW_SIZE, ARROW_SIZE)
	f.ring:SetPoint("CENTER", f.arrow, "CENTER", 0, 0)
	f.ring:Hide()
	f.shade = f:CreateTexture(nil, "ARTWORK", nil, 1)
	f.shade:SetTexture(MEDIA .. "arrow_shade")
	f.shade:SetAllPoints(f.arrow)

	f.dist = T.Text(f, 19, C.text, nil, true)
	f.dist:SetPoint("TOP", f.arrow, "BOTTOM", 0, -6)
	f.dist:SetJustifyH("CENTER")
	f.dist:SetShadowOffset(1, -1)
	-- the unit ("yd") small and muted beside the number
	f.unit = T.Text(f, 10, C.muted, nil, true)
	f.unit:SetShadowOffset(1, -1)
	f.unit:Hide()
	f.eta = T.Text(f, 10, C.muted, nil, true)
	f.eta:SetShadowOffset(1, -1)
	f.eta:Hide()
	f.label = T.Text(f, 11, C.muted)
	f.label:SetPoint("TOP", f.dist, "BOTTOM", 0, -3)
	f.label:SetJustifyH("CENTER")
	f.label:SetWidth(240)
	f.label:SetShadowOffset(1, -1)

	f:SetScript("OnEnter", function(self)
		local tip = QL.Tip()
		tip:SetOwner(self, "ANCHOR_BOTTOM")
		if questId then
			QL.FillQuestTooltip(tip, questId)
		elseif target and target.title then
			tip:AddLine(target.title, 1, 1, 1)
			if target.label then tip:AddLine(target.label, 0.7, 0.7, 0.7, true) end
		end
		tip:AddLine(L("Drag: move · Right-click: stop"), 0.6, 0.6, 0.6)
		tip:Show()
	end)
	f:SetScript("OnLeave", function() QL.Tip():Hide() end)
	QL.ApplyArrowSettings()
	f:SetScript("OnUpdate", function(_, elapsed)
		pcall(QL.StepArrow, elapsed or 0)
		elapsedSince = elapsedSince + (elapsed or 0)
		if elapsedSince < UPDATE then return end
		elapsedSince = 0
		local ok, err = pcall(QL.UpdateArrow)
		if not ok then QL.Debug("arrow: " .. tostring(err)) end
	end)
	f:Hide()
end

-- Motion ----------------------------------------------------------------------------------------------
-- UpdateArrow (every 0.03 s) decides where the arrow should point (goalRot), what it is doing
-- (mode) and the numbers; StepArrow (every frame) eases the turn, pulses the arrow when you are
-- close and plays the arrival flourish. Without a frame loop (tests) the goal is applied at once.
local PULSE_NEAR = 60      -- yards: the arrow starts to breathe
local curRot, goalRot = 0, 0
local mode = "idle"        -- idle | go | arrived
local nearness = 0         -- 0 far .. 1 on top of it
local arrivedAt            -- GetTime() when the arrow arrived
local animClock = 0

-- the arrow's colour, and the theme ring's with it
local function paint(r, g, b, a)
	frame.arrow:SetVertexColor(r, g, b, a)
	if frame.rim then frame.rim:SetVertexColor(r, g, b, math.min(a or 1, 0.85)) end
end

local function applyRotation(r)
	frame.arrow:SetRotation(r)
	frame.shade:SetRotation(r)
end

local function setRotation(r, snap)
	goalRot = r
	if snap or not frame.stepped then
		curRot = r
		applyRotation(r)
	end
end

local function angleDiff(a, b) -- shortest way from b to a
	return ((a - b + math.pi) % (2 * math.pi)) - math.pi
end

-- Estimated time to the target: yards over the speed you move at now (else your run speed, or your
-- flying speed while flying). nil when the client gives no speed.
local avgSpeed
function QL.TravelSeconds(yards)
	if not GetUnitSpeed or type(yards) ~= "number" then return nil end
	local ok, cur, run, fly, swim = pcall(GetUnitSpeed, "player")
	if not ok then return nil end
	for _, v in ipairs({ cur or 0, run or 0, fly or 0, swim or 0 }) do
		if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
	end
	-- your own speed, smoothed so the estimate does not jump (mount, flying, swimming and speed buffs
	-- all show up in it); standing still: your run speed
	local speed
	if (cur or 0) > 0 then
		avgSpeed = avgSpeed and (avgSpeed + (cur - avgSpeed) * 0.08) or cur
		speed = avgSpeed
	else
		avgSpeed = nil -- standing still: your top speed now (it follows the mount you sit on)
		speed = run or 0
		if IsFlying and IsFlying() and (fly or 0) > 0 then speed = fly end
		if IsSwimming and IsSwimming() and (swim or 0) > 0 then speed = swim end
	end
	if speed <= 0 then return nil end
	return yards / speed
end

function QL.TravelText(secs)
	if not secs or secs < 3 then return nil end
	secs = math.floor(secs + 0.5)
	if secs < 60 then return "~" .. secs .. " " .. QL.L("sec") end
	if secs >= 3600 then return "~" .. math.floor(secs / 3600) .. ":" .. ("%02d"):format(math.floor(secs % 3600 / 60)) .. " " .. QL.L("h") end
	return ("~%d:%02d"):format(math.floor(secs / 60), secs % 60)
end

local function setDistance(num, unit, eta)
	local f = frame
	f.dist:SetText(num)
	f.dist:ClearAllPoints()
	if eta then f.eta:SetText("· " .. eta); f.eta:Show() else f.eta:Hide() end
	if unit then
		f.unit:SetText(unit)
		f.unit:Show()
		local total = (f.dist:GetStringWidth() or 0) + 3 + (f.unit:GetStringWidth() or 0)
		if eta then total = total + 6 + (f.eta:GetStringWidth() or 0) end
		f.dist:SetPoint("TOPLEFT", f.core, "BOTTOM", -total / 2, -6)
		f.unit:ClearAllPoints()
		f.unit:SetPoint("BOTTOMLEFT", f.dist, "BOTTOMRIGHT", 3, 2)
		f.eta:ClearAllPoints()
		f.eta:SetPoint("BOTTOMLEFT", f.unit, "BOTTOMRIGHT", 6, 0)
	else
		f.unit:Hide()
		f.dist:SetPoint("TOP", f.core, "BOTTOM", 0, -6)
	end
end

-- a soft band behind a text line, sized to it (hidden while the line is empty)
local function fitBand(b, fs)
	local w = fs:GetStringWidth() or 0
	local show = (fs:GetText() or "") ~= "" and w > 0
	for _, t in pairs(b) do t:SetShown(show) end
	if not show then return end
	local pad = 22
	b.left:ClearAllPoints(); b.right:ClearAllPoints()
	b.left:SetPoint("TOPLEFT", fs, "TOPLEFT", -pad, 3); b.left:SetPoint("BOTTOMRIGHT", fs, "BOTTOM", 0, -3)
	b.right:SetPoint("TOPLEFT", fs, "TOP", 0, 3); b.right:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", pad, -3)
end

function QL.StepArrow(dt)
	local f = frame
	if not f or not f:IsShown() then return end
	f.stepped = true
	animClock = animClock + dt
	-- ease the turn: a fast, damped approach, no snapping on every position update
	local d = angleDiff(goalRot, curRot)
	if math.abs(d) < 0.002 then curRot = goalRot else curRot = curRot + d * (1 - math.exp(-dt * 12)) end
	applyRotation(curRot)
	-- size: a slow breath when close, a pop on arrival
	local scale = 1
	if mode == "go" and nearness > 0 then
		scale = scale + 0.035 * nearness * (0.5 + 0.5 * math.sin(animClock * (3 + 3 * nearness)))
	elseif mode == "arrived" and arrivedAt then
		local t = (GetTime and GetTime() or 0) - arrivedAt
		if t < 0.7 then
			local k = 1 - t / 0.7
			scale = scale + 0.32 * k * k * (0.5 + 0.5 * math.cos(t * 14))
			f.glow:SetAlpha(0.55 + 0.45 * k)
		else
			scale = scale + 0.025 * math.sin(animClock * 2.4)
		end
	end
	f.arrow:SetSize(arrowPx * scale, arrowPx * scale)
	if f.plate:IsShown() then
		f.plate:SetSize(PLATE * scale, PLATE * scale)
		f.rim:SetSize(PLATE * scale, PLATE * scale)
	end
	-- the glow breathes with it when close
	if mode == "go" and nearness > 0 and f.glow:IsShown() then
		f.glow:SetAlpha(0.32 + 0.18 * nearness * (0.5 + 0.5 * math.sin(animClock * (3 + 3 * nearness))))
	end
	-- the arrival ring: grows and fades once
	if f.ring then
		if mode == "arrived" and arrivedAt then
			local t = (GetTime and GetTime() or 0) - arrivedAt
			if t < 0.9 then
				local k = t / 0.9
				f.ring:SetSize(coreSize * (0.9 + 1.7 * k), coreSize * (0.9 + 1.7 * k))
				f.ring:SetAlpha((1 - k) * 0.85)
				f.ring:Show()
			else
				f.ring:Hide()
			end
		else
			f.ring:Hide()
		end
	end
end

-- A slowly turning sample for the settings page.
local function drawPreview()
	local t = GetTime and GetTime() or 0
	local rot = (t * 0.9) % (2 * math.pi)
	mode, nearness = "idle", 0
	setRotation(rot, true)
	local r, g, b = QL.ArrowTint(rot)
	paint(r, g, b, 1)
	frame.glow:SetVertexColor(r, g, b, 1)
	frame.glow:SetAlpha(0.32)
	frame.title:SetText(L("Arrow preview"))
	local pn, pu = QL.DistanceParts(120)
	setDistance(pn, pu)
	frame.label:SetText(L("Drag: move · Right-click: stop"))
	fitBand(frame.titleBand, frame.title)
	fitBand(frame.labelBand, frame.label)
end

function QL.UpdateArrow()
	if not frame then return end
	if not target then
		if preview then drawPreview() end
		return
	end
	local loc = QL.Locate(target)
	frame.title:SetText(target.title or QL.QuestTitle(questId))
	local ri = QL.RouteInfo and QL.RouteInfo()
	if ri and ri.next == questId then
		frame.label:SetText(QL.Theme.Hex(QL.Theme.HUD.accent) .. L("Route %d/%d"):format(ri.index, ri.total) .. "|r  ·  " .. (target.label or ""))
	else
		frame.label:SetText(target.label or "")
	end
	local function bands()
		fitBand(frame.titleBand, frame.title)
		fitBand(frame.labelBand, frame.label)
	end
	-- getting there (Travel.lua): the quest is in another zone or on another continent and a
	-- flight, a boat, a zeppelin or the hearthstone is quicker; the arrow leads to that step first
	local hopped, hopText = false, nil
	hopSpot = nil
	if QL.TripNext and questId and not target.corpse and not (QL.RouteActive and QL.RouteActive()) then
		local ok, hop = pcall(QL.TripNext, questId)
		if ok and hop then
			local A = QL.Theme.HUD.accent
			frame.label:SetText(QL.Theme.Hex(A) .. L("Way") .. "|r  ·  " .. hop.text)
			local hl
			if hop.kind ~= "hearth" and hop.point then
				if not hopTarget or hopTarget.points[1] ~= hop.point then hopTarget = { points = { hop.point } } end
				hl = QL.Locate(hopTarget)
			end
			-- the hearthstone is only a hint on the label: the arrow keeps pointing at the quest
			if hop.kind ~= "hearth" and hl and not hl.otherMap and hl.dist < HOP_AT then
				-- here: what to do (use the hearthstone, talk to the flight master, board)
				mode, nearness, arrivedAt = "idle", 0, nil
				setRotation(0)
				paint(A[1], A[2], A[3], 0.9)
				frame.glow:SetAlpha(0)
				setDistance(hop.text)
				bands()
				-- there: a detour drawn to this place has done its job
				if QL.DetourClear and hl.point then pcall(QL.DetourClear, hl.point) end
				return
			end
			if hl and not hl.otherMap then loc, hopped, hopText, hopSpot = hl, true, hop.text, hl.point end
		end
	end
	if not loc then
		mode, nearness, arrivedAt = "idle", 0, nil
		setRotation(0)
		paint(0.5, 0.5, 0.5, 0.5)
		frame.glow:SetAlpha(0)
		setDistance(#target.points == 0 and L("No location data") or L("No position here"))
		bands()
		return
	end
	if loc.otherMap then
		mode, nearness, arrivedAt = "idle", 0, nil
		setRotation(0)
		paint(0.6, 0.6, 0.65, 0.45)
		frame.glow:SetAlpha(0)
		setDistance(L("Head to %s"):format(QL.MapName(loc.otherMap.map) or "?"))
		bands()
		return
	end
	local C = QL.Theme.HUD
	-- a detour drawn on the map (Paths.lua): the arrow leads through its points before the target
	-- (on the way to a travel step, the detour drawn to that step's place)
	local via = hopped
	if QL.DetourNext then
		local ok, vl, vi, vn = pcall(QL.DetourNext, loc)
		if ok and vl then
			via, loc = true, vl
			frame.label:SetText(L("Detour %d/%d"):format(vi, vn) .. "  ·  " .. (hopText or target.label or ""))
		end
	end
	if loc.dist < ARRIVED and not via then
		if mode ~= "arrived" then
			arrivedAt = GetTime and GetTime() or 0
			-- arrived: the detour drawn to this spot has done its job, whatever is left of it
			if QL.DetourClear and loc.point then pcall(QL.DetourClear, loc.point) end
		end
		mode, nearness = "arrived", 1
		setRotation(0)
		local g = QL.Theme.STATUS.done
		paint(g[1], g[2], g[3], 0.9)
		frame.glow:SetVertexColor(g[1], g[2], g[3], 1)
		if frame.ring then frame.ring:SetVertexColor(g[1], g[2], g[3], 1) end
		if not frame.stepped then frame.glow:SetAlpha(0.55) end
		setDistance(target.kind == "objective" and L("You are there: look around") or L("Arrived"))
		bands()
		return
	end
	mode = "go"
	arrivedAt = nil
	nearness = math.max(0, math.min(1, 1 - (loc.dist - ARRIVED) / (PULSE_NEAR - ARRIVED)))
	local facing = GetPlayerFacing and GetPlayerFacing()
	if facing ~= nil and issecretvalue and issecretvalue(facing) then facing = nil end
	local r, g, b = QL.ArrowTint(0)
	if facing then
		local rot = QL.Bearing(loc.dx, loc.dy, facing)
		setRotation(rot)
		r, g, b = QL.ArrowTint(rot)
	end
	paint(r, g, b, 1)
	frame.glow:SetVertexColor(r, g, b, 1)
	if nearness == 0 or not frame.stepped then frame.glow:SetAlpha(0.32) end
	local dn, du = QL.DistanceParts(loc.dist)
	setDistance(dn, du, QL.TravelText(QL.TravelSeconds(loc.dist)))
	bands()
end

-- Rebuild the target from the quest's state (pick up -> objectives -> hand in).
local function refreshTarget()
	if not questId then return end
	local ctx = QL.Context()
	if QL.NodeStatus(questId, ctx) == "done" then
		QL.Print(L("Quest handed in: ") .. QL.QuestTitle(questId), "success")
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
		if not ok then QL.Debug("arrow build: " .. tostring(err)); QL.Print(L("The arrow could not be built: /ql errors"), "error"); return end
	end
	questId = id
	target = nil
	refreshTarget()
	if not target then
		if not quiet then QL.Print(L("Nothing to point at for: ") .. QL.QuestTitle(id), "warn") end
		return
	end
	saved()[charKey()] = id
	if frame then
		frame:Show()
		pcall(QL.UpdateArrow)
	end
	-- no notification here: the arrow itself shows the quest and what to do (a card on every
	-- click was noise); only problems are reported
	QL.Fire("ARROW_CHANGED", id)
end

-- /ql arrow: what the arrow knows, step by step, to find why it does not show.
function QL.ArrowDebug(arg)
	local id = tonumber(arg)
	if id then QL.SetArrowTarget(id) end
	QL.Chat(L("Arrow quest: ") .. tostring(questId) .. (questId and (" (" .. QL.QuestTitle(questId) .. ")") or ""))
	if not frame then QL.Chat(L("Arrow frame: not built yet (pick a quest in the Quests list)")); return end
	local point, _, relPoint, x, y = frame:GetPoint(1)
	QL.Chat(("frame: shown=%s visible=%s strata=%s alpha=%.2f scale=%.2f point=%s %s %.0f,%.0f"):format(
		tostring(frame:IsShown()), tostring(frame:IsVisible()), tostring(frame:GetFrameStrata()),
		frame:GetAlpha() or -1, frame:GetEffectiveScale() or -1, tostring(point), tostring(relPoint), x or 0, y or 0))
	QL.Chat("texture: " .. tostring(frame.arrow:GetTexture()))
	if not target then QL.Chat(L("No target.")); return end
	QL.Chat(("target: %s · %d points · %s"):format(target.kind, #target.points, tostring(target.label)))
	local p1 = target.points[1]
	if p1 then QL.Chat(("first point: map %s at %.3f, %.3f"):format(tostring(p1.map), p1.x, p1.y)) end
	local map, px, py = QL.PlayerPosition()
	QL.Chat(("player: map %s at %s, %s · facing %s"):format(tostring(map), tostring(px), tostring(py), tostring(GetPlayerFacing and GetPlayerFacing())))
	local loc = QL.Locate(target)
	if not loc then QL.Chat("locate: nil")
	elseif loc.otherMap then QL.Chat("locate: other map " .. tostring(loc.otherMap.map))
	else QL.Chat(("locate: %.0f yd (dx %.0f, dy %.0f)"):format(loc.dist, loc.dx, loc.dy)) end
end

function QL.SetArrowPlace(kind, id, opts)
	opts = opts or {}
	if not frame and CreateFrame then
		local ok, err = pcall(build)
		if not ok then QL.Debug("arrow build: " .. tostring(err)); return end
	end
	questId = nil
	target = {
		kind = "place", fixed = true, points = QL.SpawnPoints(kind, id),
		title = opts.title, label = opts.label, questId = opts.questId,
	}
	saved()[charKey()] = nil
	if frame then
		frame:Show()
		pcall(QL.UpdateArrow)
	end
	-- the arrow names the place itself; only say something when there is nowhere to point
	if #target.points == 0 then QL.Print(L("No location data") .. ": " .. (opts.title or "?"), "warn") end
	QL.Fire("ARROW_CHANGED", "place")
end

-- A single spot (the corpse): opts = { title, label, corpse }.
function QL.SetArrowPoint(map, x, y, opts)
	opts = opts or {}
	if not frame and CreateFrame then
		local ok, err = pcall(build)
		if not ok then QL.Debug("arrow build: " .. tostring(err)); return end
	end
	questId = nil
	target = {
		kind = "place", fixed = true, points = { { map = map, x = x, y = y } },
		title = opts.title, label = opts.label, corpse = opts.corpse,
	}
	saved()[charKey()] = nil
	if frame then
		frame:Show()
		pcall(QL.UpdateArrow)
	end
	QL.Fire("ARROW_CHANGED", "place")
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

-- The arrow's frame, built (hidden) on demand: the quick bar sits under it.
function QL.ArrowFrame()
	if not frame and CreateFrame then
		local ok, err = pcall(build)
		if not ok then QL.Debug("arrow build: " .. tostring(err)) end
	end
	return frame
end
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
		QL.Print(L("Quest handed in: ") .. QL.QuestTitle(questId), "success")
		QL.ClearArrow()
		QL.Fire("ARROW_QUEST_DONE", id)
	end
end)

QL.Event("PLAYER_LOGIN", function()
	local id = saved()[charKey()]
	if id then QL.WhenIndexed(function() QL.SetArrowTarget(id, true) end) end
end)
