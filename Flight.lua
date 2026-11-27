-- The flight timer: while you ride a flight path, a small window counts the time left down to 0:00
-- (the landing) with one slim line that runs out.
--
-- The game has no call that says how long a flight takes, so the timer learns it: the first flight
-- on a route is timed (the window then counts up and says it is learning), the time is kept per
-- route (QuestLineageDB.flightTimes["Origin>Destination"]), and every later flight counts down from
-- it. A flight that runs long shows 0:00 and waits for the landing; each landing refines the stored
-- time (the old and the new averaged when they are close, else the new one).
--
-- A route never flown has no stored time: the window then estimates one from the straight distance
-- between the two flight masters over your flying speed (marked "~" and "estimate"); if the client
-- gives neither, it counts up and says it is timing the route.
--
-- The route comes from the taxi map: the node of type CURRENT when it opens is where you are, and a
-- post-hook on TakeTaxiNode(slot) gives the destination (TaxiNodeName). Riding is read from
-- UnitOnTaxi("player"), polled every 0.2 s.
--
-- Setting: flightTimer (on), flightPoint (where the window was dragged to).
--   QL.FlightBegin(now, origin, dest)  QL.FlightEnd(now)  QL.FlightStatus(now)  QL.FlightFormat(sec)
--   QL.FlightDemo()  (/ql flight: a 20 s sample to see the window)

local _, QL = ...
local L = QL.L

local W, H = 232, 64
local LINGER = 3.2      -- seconds the window stays after landing
local MIN_TRIP = 5      -- shorter rides are not kept (a hop, or a glitch)

local state             -- { key, origin, dest, start, expected }
local lastDone          -- { at, key, dest } after a landing (the window's farewell)
local pending           -- { origin, dest, at } from the taxi map
local originName, originPos, mapSize
local frame

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a = pcall(fn, ...)
	if ok then return a end
	return nil
end

local function call2(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
	return nil
end

local function times()
	local db = QL.DB()
	if type(db.flightTimes) ~= "table" then db.flightTimes = {} end
	return db.flightTimes
end

function QL.FlightKey(origin, dest)
	return tostring(origin or "?") .. ">" .. tostring(dest or "?")
end

-- "1:05", "0:09"; hours when long
function QL.FlightFormat(sec)
	sec = math.max(0, math.floor((sec or 0) + 0.5))
	if sec >= 3600 then return ("%d:%02d:%02d"):format(math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60) end
	return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

function QL.FlightBegin(now, origin, dest)
	local key = QL.FlightKey(origin, dest)
	state = { key = key, origin = origin, dest = dest, start = now, expected = times()[key] }
	lastDone = nil
	return state
end

-- The landing: keep the time (refined) and remember it for the farewell. Returns the duration.
function QL.FlightEnd(now)
	if not state then return nil end
	local s = state
	state = nil
	local dur = now - s.start
	if dur >= MIN_TRIP and s.dest and not s.demo then
		local t = times()
		local old = t[s.key]
		if old and math.abs(dur - old) <= old * 0.3 then
			t[s.key] = math.floor((old + dur) / 2 * 10 + 0.5) / 10
		else
			t[s.key] = math.floor(dur * 10 + 0.5) / 10
		end
	end
	lastDone = { at = now, key = s.key, dest = s.dest, duration = dur }
	return dur
end

-- What the window shows now: nil off a flight, else
-- { elapsed, remaining (nil while learning), fraction (0-1, nil while learning), learning, over, dest, origin }.
function QL.FlightStatus(now)
	if not state then return nil end
	local elapsed = math.max(0, now - state.start)
	local out = { elapsed = elapsed, dest = state.dest, origin = state.origin }
	if state.expected and state.expected > 0 then
		out.remaining = math.max(0, state.expected - elapsed)
		out.fraction = math.min(1, elapsed / state.expected)
		out.over = elapsed > state.expected
		out.guessed = state.guessed
	else
		out.learning = true
	end
	return out
end

function QL.FlightActive() return state ~= nil end

-- The window ------------------------------------------------------------------------------------------
-- A small pill: the destination, the time left counting down to 0:00 in big figures, and one slim
-- line that runs out as you near the landing, a soft light riding its end. Landing: "Arrived" in
-- green with a small pop, then it fades.

local MEDIA = "Interface\\AddOns\\QuestLineage\\Media\\"

local function savePoint()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	QL.DB().flightPoint = { point, relPoint, x, y }
end

local function build()
	local T, C = QL.Theme, QL.Theme.HUD
	frame = CreateFrame("Frame", "QuestLineageFlight", UIParent)
	frame:SetSize(W, H)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePoint() end)
	T.Fill(frame, { QL.Theme.PanelA(0.92) })
	T.Border(frame, C.line)
	frame.title = T.Text(frame, 11, C.muted)
	frame.title:SetPoint("TOPLEFT", 16, -11)
	frame.title:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
	frame.big = T.Text(frame, 24, C.text, nil, true)
	frame.big:SetPoint("TOPLEFT", 16, -24)
	frame.sub = T.Text(frame, 10, C.dim)
	frame.sub:SetPoint("BOTTOMLEFT", frame.big, "BOTTOMRIGHT", 8, 4)
	frame.bar = T.Bar(frame, 3)
	frame.bar:SetPoint("BOTTOMLEFT", 16, 11)
	frame.bar:SetPoint("BOTTOMRIGHT", -16, 11)
	-- a soft light at the head of the line
	frame.head = frame:CreateTexture(nil, "OVERLAY")
	frame.head:SetTexture(MEDIA .. "disc")
	frame.head:SetSize(9, 9)
	frame.head:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
	-- while learning, a lit stretch sweeps the line
	frame.sweep = frame.bar:CreateTexture(nil, "OVERLAY", nil, 1)
	frame.sweep:SetTexture(T.WHITE)
	T.Gradient(frame.sweep, "HORIZONTAL", C.accent, C.accent2)
	frame.sweep:Hide()
	frame:Hide()
end

local function place(offset)
	local p = QL.DB().flightPoint
	frame:ClearAllPoints()
	if type(p) == "table" and p[1] then
		frame:SetPoint(p[1], UIParent, p[2], p[3], (p[4] or 0) + offset)
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -36 + offset)
	end
end

local shownAt, clock, wasShown, settled, shownV = 0, 0, false, false, 1

-- Draw the window for a moment: fade and slide in, tick, farewell and fade out.
local function render(now, dt)
	if not frame then return end
	local T, C = QL.Theme, QL.Theme.HUD
	clock = clock + dt
	local st = QL.FlightStatus(now)
	local farewell = (not st) and lastDone and (now - lastDone.at) < LINGER + 0.6
	if not st and not farewell then
		if frame:IsShown() then frame:Hide() end
		wasShown = false
		return
	end
	if not wasShown then
		wasShown = true
		shownAt = now
		settled = false
		shownV = 1
		frame:Show()
		frame:SetScale(1)
	end
	-- in: fade and slide down over 0.35 s
	local k = math.min(1, (now - shownAt) / 0.35)
	local ease = 1 - (1 - k) * (1 - k) * (1 - k)
	local alpha = ease
	local since = 0
	if farewell then
		since = now - lastDone.at
		if since > LINGER then alpha = alpha * math.max(0, 1 - (since - LINGER) / 0.6) end
	end
	frame:SetAlpha(alpha)
	if k < 1 or not settled then place((1 - ease) * 14); settled = k >= 1 end

	local done = T.STATUS.done
	local barW = frame.bar:GetWidth() or 268
	if st then
		frame:SetScale(1)
		frame.title:SetText(st.dest and (L("To ") .. st.dest) or L("In the air"))
		if st.learning then
			-- no time known yet: it counts up and says so, the line sweeps
			frame.big:SetText(QL.FlightFormat(math.floor(st.elapsed)))
			frame.big:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
			frame.sub:SetText(L("timing this route"))
			frame.bar:SetValue(0)
			local w = barW * 0.28
			local ph = (clock * 0.55) % 2
			ph = ph > 1 and 2 - ph or ph
			ph = ph * ph * (3 - 2 * ph)
			frame.sweep:ClearAllPoints()
			frame.sweep:SetPoint("LEFT", frame.bar, "LEFT", ph * (barW - w), 0)
			frame.sweep:SetSize(w, 3)
			frame.sweep:Show()
			frame.head:Hide()
		else
			frame.sweep:Hide()
			local left = math.ceil(st.remaining - 0.001) -- a countdown rounds up
			frame.big:SetText((st.guessed and "~" or "") .. QL.FlightFormat(left))
			frame.sub:SetText(st.guessed and L("estimate") or "")
			if st.over then
				-- late: 0:00 breathes until the landing
				frame.big:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.65 + 0.35 * math.sin(clock * 5))
			else
				frame.big:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
			end
			-- the line runs out towards 0:00 (eased, so it glides)
			local target = 1 - st.fraction
			shownV = shownV + (target - shownV) * math.min(1, dt * 8)
			if math.abs(target - shownV) < 0.002 then shownV = target end
			frame.bar:SetValue(shownV)
			frame.head:ClearAllPoints()
			frame.head:SetPoint("CENTER", frame.bar, "LEFT", barW * shownV, 0)
			frame.head:SetAlpha(0.6 + 0.4 * math.sin(clock * 4))
			frame.head:Show()
		end
	else
		-- landed: "Arrived" in green, a small pop, the line gone
		frame.sweep:Hide()
		frame.head:Hide()
		frame.title:SetText(lastDone.dest and (L("To ") .. lastDone.dest) or L("In the air"))
		frame.big:SetText(L("Arrived"))
		frame.big:SetTextColor(done[1], done[2], done[3], 1)
		frame.sub:SetText(QL.FlightFormat(lastDone.duration))
		frame.bar:SetValue(0)
		local pop = since < 0.4 and (1 + 0.07 * math.sin(since / 0.4 * math.pi)) or 1
		frame:SetScale(pop)
	end
end

-- Watching the ride -----------------------------------------------------------------------------------

local function onTaxi()
	local v = call(rawget(_G, "UnitOnTaxi"), "player")
	if issecretvalue and v ~= nil and issecretvalue(v) then return nil end
	return v and true or false
end

local sincePoll = 0

-- An estimated flight time for a route without a stored one: the straight line between the origin
-- and destination flight masters (their taxi-map positions) over the speed you fly at now.
local function guessDuration(s)
	local o, d = s.originPos, s.destPos
	if not (o and d and s.mapSize) then return nil end
	local speed = call(rawget(_G, "GetUnitSpeed"), "player")
	if type(speed) ~= "number" or speed <= 0 or (issecretvalue and issecretvalue(speed)) then return nil end
	local dx, dy = (d[1] - o[1]) * s.mapSize[1], (d[2] - o[2]) * s.mapSize[2]
	local yards = math.sqrt(dx * dx + dy * dy)
	if yards < 50 then return nil end
	return yards * 1.15 / speed -- flight paths bend: a little extra
end

local function watch(dt)
	local now = GetTime and GetTime() or 0
	sincePoll = sincePoll + dt
	if sincePoll >= 0.2 then
		sincePoll = 0
		if QL.DB().flightTimer ~= false then
			local riding = onTaxi()
			if riding == true and not state then
				local o, d
				local pending0
				if pending and now - pending.at < 120 then o, d = pending.origin, pending.dest; pending0 = pending end
				pending = nil
				QL.FlightBegin(now, o, d)
				if state and pending0 then state.originPos, state.destPos, state.mapSize = pending0.originPos, pending0.destPos, pending0.mapSize end
				if not frame then
					local ok, err = pcall(build)
					if not ok then QL.Debug("flight: " .. tostring(err)); frame = nil end
				end
			elseif riding == false and state and not state.demo then
				QL.FlightEnd(now)
			end
		end
	end
	if state and not state.expected and not state.guessTried and now - state.start > 1.5 then
		state.guessTried = true
		local g = guessDuration(state)
		if g then state.expected, state.guessed = g, true end
	end
	if state and state.demo and now - state.start >= state.expected + 0.4 then QL.FlightEnd(now) end
	render(now, dt)
end

-- /ql flight: a sample flight of 20 s to see the window (and its landing)
function QL.FlightDemo()
	if not frame then
		local ok, err = pcall(build)
		if not ok then QL.Debug("flight: " .. tostring(err)); return end
	end
	local s = QL.FlightBegin(GetTime and GetTime() or 0, "Demo", "Orgrimmar")
	s.expected, s.demo = 20, true
	s.key = nil
end

QL.Event("TAXIMAP_OPENED", function()
	originName, originPos, mapSize = nil, nil, nil
	do
		local map = call(rawget(_G, "GetTaxiMapID"))
		if map and C_Map and C_Map.GetMapWorldSize then
			local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
			if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then mapSize = { w, h } end
		end
	end
	local n = tonumber(call(rawget(_G, "NumTaxiNodes"))) or 0
	for i = 1, n do
		if call(rawget(_G, "TaxiNodeGetType"), i) == "CURRENT" then
			originName = call(rawget(_G, "TaxiNodeName"), i)
			local x, y = call2(rawget(_G, "TaxiNodePosition"), i)
			originPos = (type(x) == "number" and type(y) == "number") and { x, y } or nil
			break
		end
	end
end)

QL.Event("PLAYER_LOGIN", function()
	if hooksecurefunc and rawget(_G, "TakeTaxiNode") then
		pcall(hooksecurefunc, "TakeTaxiNode", function(slot)
			pending = {
				origin = originName,
				dest = call(rawget(_G, "TaxiNodeName"), slot),
				at = GetTime and GetTime() or 0,
				originPos = originPos, mapSize = mapSize,
				destPos = (function()
					local x, y = call2(rawget(_G, "TaxiNodePosition"), slot)
					if type(x) == "number" and type(y) == "number" then return { x, y } end
				end)(),
			}
		end)
	end
	if CreateFrame then
		local f = CreateFrame("Frame")
		f:SetScript("OnUpdate", function(_, dt) local ok, err = pcall(watch, dt or 0); if not ok then QL.Debug("flight: " .. tostring(err)) end end)
		QL.flightWatcher = f
	end
end)
