-- Getting there: when a quest waits in another zone or on another continent, the quickest way
-- by mount, flight paths, zeppelins, boats, the Deeprun Tram and the hearthstone.
--
--   QL.PlanTrip(start, goals, opts) -> plan | nil     pure: a small graph and Dijkstra
--       start = { inst, x, y } (world yards), goals = { {inst, x, y, point, label}, ... }
--       opts  = { speed, flights = {node...}, transports = { {kind, a = node, b = node, time} },
--                 hearth = node, hearthTime, flightSpeed, unknownPenalty }
--       plan  = { total = seconds, steps = { {kind, from, to, secs, dist, known}, ... }, simple }
--       kinds: ride (on foot or mount), fly, zeppelin, boat, tram, hearth
--   QL.TripFor(questId, ctx) -> plan | nil   live: from where you stand to the quest's target;
--       nil when the target is in your zone (the arrow is enough there)
--   QL.TripNext(questId) -> step | nil       the step the arrow leads to (plans that need more
--       than riding straight); re-planned from your position, so it moves on by itself
--   QL.TripStepText(step) -> text, sub, icon / QL.TripSummary(plan) -> one line
--   QL.LearnTaxiNodes()                      on TAXIMAP_OPENED: the flight points this character has
--   QL.TRANSPORTS                            the zeppelin, boat and tram lines (approximate docks)
-- Settings: travelHints (the whole thing), travelHearth, travelArrow. /ql travel [id] explains.

local _, QL = ...
QL = QL or {}

local function L(s) return QL.L and QL.L(s) or s end

local HEARTHSTONE = 6948
local RIDE_FACTOR = 1.25   -- roads wind: the straight line times this
local FLY_FACTOR = 1.3     -- flight paths go round
local FLY_SPEED = 32       -- yd/s on a flight path
local FLY_OVERHEAD = 20    -- talking to the flight master, take-off and landing
local AT_SPOT = 25         -- yards: you are already at a dock or a flight master

-- The lines between continents and cities (Classic). Docks are spots on their zone's uiMap,
-- read off the map by hand: close, not exact (/ql travel lists them to check in game).
-- faction: "H" Horde, "A" Alliance, "AH" both.
QL.TRANSPORTS = {
	{ kind = "zeppelin", faction = "H", time = 240,
		a = { map = 1411, x = 0.508, y = 0.136, city = "Orgrimmar", place = "the zeppelin tower outside Orgrimmar" },
		b = { map = 1420, x = 0.608, y = 0.588, city = "Undercity", place = "the zeppelin tower outside Undercity" } },
	{ kind = "zeppelin", faction = "H", time = 240,
		a = { map = 1411, x = 0.506, y = 0.126, city = "Orgrimmar", place = "the zeppelin tower outside Orgrimmar" },
		b = { map = 1434, x = 0.316, y = 0.292, city = "Grom'gol", place = "the zeppelin tower at Grom'gol" } },
	{ kind = "zeppelin", faction = "H", time = 240,
		a = { map = 1420, x = 0.616, y = 0.592, city = "Undercity", place = "the zeppelin tower outside Undercity" },
		b = { map = 1434, x = 0.314, y = 0.302, city = "Grom'gol", place = "the zeppelin tower at Grom'gol" } },
	{ kind = "boat", faction = "A", time = 240,
		a = { map = 1437, x = 0.048, y = 0.636, city = "Menethil Harbor", place = "the docks of Menethil Harbor" },
		b = { map = 1445, x = 0.716, y = 0.564, city = "Theramore", place = "the docks of Theramore" } },
	{ kind = "boat", faction = "A", time = 240,
		a = { map = 1437, x = 0.046, y = 0.572, city = "Menethil Harbor", place = "the docks of Menethil Harbor" },
		b = { map = 1439, x = 0.324, y = 0.438, city = "Auberdine", place = "the docks of Auberdine" } },
	{ kind = "boat", faction = "A", time = 180,
		a = { map = 1439, x = 0.332, y = 0.402, city = "Auberdine", place = "the docks of Auberdine" },
		b = { map = 1438, x = 0.550, y = 0.940, city = "Rut'theran Village", place = "the docks of Rut'theran Village" } },
	{ kind = "tram", faction = "A", time = 70,
		a = { map = 1453, x = 0.636, y = 0.084, city = "Stormwind", place = "the Deeprun Tram in Stormwind" },
		b = { map = 1455, x = 0.765, y = 0.512, city = "Ironforge", place = "the Deeprun Tram in Ironforge" } },
	{ kind = "boat", faction = "AH", time = 240,
		a = { map = 1434, x = 0.259, y = 0.731, city = "Booty Bay", place = "the docks of Booty Bay" },
		b = { map = 1413, x = 0.637, y = 0.386, city = "Ratchet", place = "the docks of Ratchet" } },
}

-- The planner (pure) --------------------------------------------------------------------------

local function dist(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

function QL.PlanTrip(start, goals, opts)
	if not start or not start.inst or not goals or #goals == 0 then return nil end
	opts = opts or {}
	local speed = opts.speed or 7
	local flySpeed = opts.flightSpeed or FLY_SPEED
	local penalty = opts.unknownPenalty or 60
	local nodes = { { inst = start.inst, x = start.x, y = start.y, start = true } }
	for _, g in ipairs(goals) do
		if g.inst then nodes[#nodes + 1] = { inst = g.inst, x = g.x, y = g.y, goal = true, point = g.point, label = g.label } end
	end
	for _, f in ipairs(opts.flights or {}) do
		if f.inst then
			nodes[#nodes + 1] = { inst = f.inst, x = f.x, y = f.y, flight = true, known = f.known, point = f.point, label = f.label, zone = f.zone, npc = f.npc }
		end
	end
	for _, t in ipairs(opts.transports or {}) do
		if t.a and t.b and t.a.inst and t.b.inst then
			local a = { inst = t.a.inst, x = t.a.x, y = t.a.y, dock = t, point = t.a.point, label = t.a.place, city = t.a.city }
			local b = { inst = t.b.inst, x = t.b.x, y = t.b.y, dock = t, point = t.b.point, label = t.b.place, city = t.b.city }
			a.other, b.other = b, a
			nodes[#nodes + 1] = a
			nodes[#nodes + 1] = b
		end
	end
	local hearthNode
	if opts.hearth and opts.hearth.inst then
		hearthNode = { inst = opts.hearth.inst, x = opts.hearth.x, y = opts.hearth.y, hearth = true, point = opts.hearth.point, label = opts.hearth.label }
		nodes[#nodes + 1] = hearthNode
	end

	-- the cost of going from u to v, and how
	local function edge(u, v)
		if v.start or u.goal then return nil end
		local best, kind
		if u.inst == v.inst then
			best, kind = dist(u, v) * RIDE_FACTOR / speed, "ride"
		end
		if u.flight and v.flight and u.inst == v.inst and u ~= v then
			local c = dist(u, v) * FLY_FACTOR / flySpeed + FLY_OVERHEAD
			if not u.known then c = c + penalty end
			if not v.known then c = c + penalty end
			if not best or c < best then best, kind = c, "fly" end
		end
		if u.other == v then
			local c = v.dock.time or 240
			if not best or c < best then best, kind = c, v.dock.kind end
		end
		if u.start and v == hearthNode then
			local c = opts.hearthTime or 25
			if not best or c < best then best, kind = c, "hearth" end
		end
		return best, kind
	end

	-- Dijkstra, dense (a few dozen nodes)
	local n = #nodes
	local cost, done, prev, how = {}, {}, {}, {}
	cost[1] = 0
	local reached
	for _ = 1, n do
		local u, uc
		for i = 1, n do
			if not done[i] and cost[i] and (not uc or cost[i] < uc) then u, uc = i, cost[i] end
		end
		if not u then break end
		done[u] = true
		if nodes[u].goal then reached = u; break end
		for v = 1, n do
			if not done[v] then
				local c, kind = edge(nodes[u], nodes[v])
				if c and (not cost[v] or uc + c < cost[v]) then
					cost[v], prev[v], how[v] = uc + c, u, kind
				end
			end
		end
	end
	if not reached then return nil end

	local chain = {}
	local v = reached
	while prev[v] do
		table.insert(chain, 1, { from = nodes[prev[v]], to = nodes[v], kind = how[v], secs = cost[v] - cost[prev[v]] })
		v = prev[v]
	end
	local steps, simple = {}, true
	for i, s in ipairs(chain) do
		s.dist = s.from.inst == s.to.inst and dist(s.from, s.to) or nil
		if s.kind == "fly" then s.known = s.from.known and s.to.known end
		if s.kind ~= "ride" then simple = false end
		-- already standing at the dock or the flight master: no walk to it
		if not (i == 1 and s.kind == "ride" and s.dist and s.dist < AT_SPOT and #chain > 1) then
			steps[#steps + 1] = s
		end
	end
	return { total = cost[reached], steps = steps, simple = simple, goal = nodes[reached] }
end

-- Texts -----------------------------------------------------------------------------------------

-- The game's own coloured icons. Not every client has every file, so each kind lists a few and
-- the first the client knows (GetFileIDFromPath) is used; without that call, the first one.
local ICON_DIR = "Interface\\Icons\\"
local ICON_CHOICES = {
	ride = { "Ability_Mount_RidingHorse", "Ability_Mount_WhiteTiger", "Spell_Nature_Swiftness" },
	flyH = { "Ability_Mount_Wyvern_01", "Ability_Hunter_Pet_Vulture", "Spell_Magic_FeatherFall" },
	flyA = { "Ability_Mount_Gryphon_01", "Ability_Hunter_Pet_Owl", "Spell_Magic_FeatherFall" },
	zeppelin = { "INV_Misc_Zeppelin", "INV_Gizmo_08", "INV_Gizmo_02", "Trade_Engineering" },
	boat = { "INV_Misc_Anchor", "Spell_Frost_SummonWaterElemental", "INV_Misc_Map_01" },
	tram = { "INV_Gizmo_02", "Trade_Engineering" },
	hearth = { "INV_Misc_Rune_01" },
	goal = { "INV_Misc_Note_01", "INV_Letter_01" },
}
local iconPick = {}

function QL.TripIcon(kind)
	if kind == "fly" then
		local ok, f = pcall(rawget(_G, "UnitFactionGroup") or function() end, "player")
		kind = (ok and f == "Alliance") and "flyA" or "flyH"
	end
	if iconPick[kind] then return iconPick[kind] end
	if kind == "hearth" and QL.ItemIcon then
		local ok, icon = pcall(QL.ItemIcon, 6948) -- the Hearthstone item's own icon
		if ok and icon then iconPick[kind] = icon; return icon end
	end
	local list = ICON_CHOICES[kind]
	if not list then return nil end
	local pick = ICON_DIR .. list[1]
	local find = rawget(_G, "GetFileIDFromPath")
	if type(find) == "function" then
		for _, name in ipairs(list) do
			local ok, fid = pcall(find, ICON_DIR .. name)
			if ok and fid then pick = ICON_DIR .. name; break end
		end
	end
	iconPick[kind] = pick
	return pick
end

local function zoneOf(node)
	return node and (node.zone or (node.point and QL.MapName and QL.MapName(node.point.map))) or nil
end

-- text, sub, icon of one step
function QL.TripStepText(s)
	local to = s.to
	local text, sub
	if s.kind == "ride" then
		if to.goal then
			text = L("Head to the quest")
			sub = zoneOf(to)
		elseif to.flight then
			text = L("Go to the flight master %s"):format(to.npc or "?")
			sub = zoneOf(to)
		elseif to.dock then
			text = L("Go to %s"):format(L(to.label or "?"))
			sub = zoneOf(to)
		else
			text = L("Go to %s"):format(zoneOf(to) or "?")
		end
	elseif s.kind == "fly" then
		text = L("Fly to %s"):format(zoneOf(to) or "?")
		sub = to.npc
		if not s.known then sub = (sub and (sub .. " · ") or "") .. L("if you have that flight point") end
	elseif s.kind == "zeppelin" then
		text = L("Take the zeppelin to %s"):format(L(to.city or "?"))
	elseif s.kind == "boat" then
		text = L("Take the boat to %s"):format(L(to.city or "?"))
	elseif s.kind == "tram" then
		text = L("Take the Deeprun Tram to %s"):format(L(to.city or "?"))
	elseif s.kind == "hearth" then
		text = L("Use your hearthstone")
		sub = to.label
	end
	return text or "?", sub, QL.TripIcon((to.goal and s.kind == "ride") and "goal" or s.kind)
end

local SHORT = { ride = "Ride", fly = "Fly", zeppelin = "Zeppelin", boat = "Boat", tram = "Tram", hearth = "Hearthstone" }

-- "Zeppelin → Undercity · Fly → Hillsbrad Foothills"
function QL.TripSummary(plan)
	if not plan then return nil end
	local parts = {}
	for _, s in ipairs(plan.steps) do
		if s.kind ~= "ride" or plan.simple then
			local where = (s.to.dock and L(s.to.city or "?")) or (s.kind == "hearth" and s.to.label) or zoneOf(s.to) or "?"
			parts[#parts + 1] = L(SHORT[s.kind] or s.kind) .. " → " .. where
		end
	end
	return table.concat(parts, " · ")
end

-- The live part ---------------------------------------------------------------------------------

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c
end

local function charKey()
	local name = call(rawget(_G, "UnitName"), "player") or "?"
	local realm = call(rawget(_G, "GetRealmName")) or "?"
	return tostring(name) .. "-" .. tostring(realm)
end

local function playerFaction()
	local f = call(rawget(_G, "UnitFactionGroup"), "player")
	return f == "Alliance" and "A" or (f == "Horde" and "H" or nil)
end

local function charTable(key)
	local db = QL.DB()
	if type(db[key]) ~= "table" then db[key] = {} end
	local k = charKey()
	if type(db[key][k]) ~= "table" then db[key][k] = {} end
	return db[key][k]
end

local function world(map, x, y)
	if not QL.WorldPoint then return nil end
	local inst, wx, wy = QL.WorldPoint(map, x, y)
	if not inst then return nil end
	return { inst = inst, x = wx, y = wy, point = { map = map, x = x, y = y } }
end

-- flight masters friendly to you, with their spot in the world (once per session)
local flightCache
local function flightMasters()
	if flightCache then return flightCache end
	local index = QL.index
	if not index or not index.services then return {} end
	local list = {}
	for _, e in ipairs(index.services.flight or {}) do
		if e[1] == "npc" then
			local p = QL.SpawnPoints("npc", e[2])[1]
			local w = p and world(p.map, p.x, p.y)
			if w then
				w.npcId = e[2]
				w.npc = QL.N(e[2], "name")
				w.zone = QL.MapName and QL.MapName(p.map)
				list[#list + 1] = w
			end
		end
	end
	if #list > 0 then flightCache = list end
	return list
end

local transportCache
local function transports()
	if transportCache then return transportCache end
	local mine = QL.travelFaction or playerFaction()
	local list = {}
	for _, t in ipairs(QL.TRANSPORTS) do
		if not mine or t.faction:find(mine, 1, true) then
			local a, b = world(t.a.map, t.a.x, t.a.y), world(t.b.map, t.b.x, t.b.y)
			if a and b then
				a.city, a.place, b.city, b.place = t.a.city, t.a.place, t.b.city, t.b.place
				list[#list + 1] = { kind = t.kind, time = t.time, a = a, b = b }
			end
		end
	end
	if #list > 0 then transportCache = list end -- nothing placed yet (no map data): try again later
	return list
end

local function resetCaches() flightCache, transportCache = nil, nil end
QL.On("INDEX_READY", resetCaches)
QL.Event("PLAYER_ENTERING_WORLD", resetCaches)

-- Flight points this character has: read from the flight map, matched to the nearest flight
-- master. Nothing learned yet: every flight master is "maybe" (a small penalty).
function QL.LearnTaxiNodes()
	local known = charTable("knownTaxi")
	local spots = {}
	local map = call(rawget(_G, "GetTaxiMapID"))
	local all = C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and map and call(C_TaxiMap.GetAllTaxiNodes, map)
	if type(all) == "table" and #all > 0 then
		for _, n in ipairs(all) do
			-- state: 0 current, 1 reachable, 2 not known
			if type(n) == "table" and n.state ~= 2 and n.position then
				local x, y = n.position.x, n.position.y
				if n.position.GetXY then x, y = n.position:GetXY() end
				spots[#spots + 1] = { x, y }
			end
		end
	else
		local count = tonumber(call(rawget(_G, "NumTaxiNodes"))) or 0
		for i = 1, count do
			local kind = call(rawget(_G, "TaxiNodeGetType"), i)
			if kind == "CURRENT" or kind == "REACHABLE" or kind == "DISTANT" then
				local x, y = call(rawget(_G, "TaxiNodePosition"), i)
				spots[#spots + 1] = { x, y }
			end
		end
	end
	if not map then return 0 end
	local added = 0
	for _, s in ipairs(spots) do
		local w = type(s[1]) == "number" and type(s[2]) == "number" and world(map, s[1], s[2])
		if w then
			local best, bestD
			for _, f in ipairs(flightMasters()) do
				if f.inst == w.inst then
					local d = dist(f, w)
					if d < 150 and (not bestD or d < bestD) then best, bestD = f, d end
				end
			end
			if best and not known[best.npcId] then known[best.npcId] = true; added = added + 1 end
		end
	end
	if added > 0 then QL.Fire("TRIP_CHANGED") end
	return added
end
QL.Event("TAXIMAP_OPENED", function() QL.LearnTaxiNodes() end)

-- Where the hearthstone takes you: the spot where you bound it (HEARTHSTONE_BOUND), else an
-- innkeeper in the zone of that name (cities).
QL.Event("HEARTHSTONE_BOUND", function()
	local map, x, y = QL.PlayerPosition()
	if not map or not x then return end
	local db = QL.DB()
	if type(db.bindSpots) ~= "table" then db.bindSpots = {} end
	db.bindSpots[charKey()] = { map = map, x = x, y = y, name = call(rawget(_G, "GetBindLocation")) }
	QL.Fire("TRIP_CHANGED")
end)

local function hearthReady()
	local count = call(rawget(_G, "GetItemCount"), HEARTHSTONE)
	if type(count) == "number" and count < 1 then return false end
	local cd = rawget(_G, "GetItemCooldown") or (C_Container and C_Container.GetItemCooldown)
	local start, dur = call(cd, HEARTHSTONE)
	if type(start) ~= "number" or type(dur) ~= "number" then return true end
	if start == 0 or dur == 0 then return true end
	local now = call(rawget(_G, "GetTime")) or 0
	return start + dur - now <= 0
end

function QL.HearthSpot()
	local name = call(rawget(_G, "GetBindLocation"))
	local db = QL.DB()
	local saved = type(db.bindSpots) == "table" and db.bindSpots[charKey()]
	if type(saved) == "table" and (not name or saved.name == nil or saved.name == name) then
		local w = world(saved.map, saved.x, saved.y)
		if w then w.label = name or saved.name; return w end
	end
	if type(name) ~= "string" or name == "" then return nil end
	local index = QL.index
	for _, e in ipairs(index and index.services and index.services.inn or {}) do
		local spawns = e[1] == "npc" and QL.N(e[2], "spawns")
		if type(spawns) == "table" then
			for area in pairs(spawns) do
				if QL.AreaName and QL.AreaName(area) == name then
					local p = QL.SpawnPoints("npc", e[2])[1]
					local w = p and world(p.map, p.x, p.y)
					if w then w.label = name; return w end
				end
			end
		end
	end
	return nil
end

local function groundSpeed(ctx)
	local level = ctx and ctx.level or 1
	return level >= 40 and 11.2 or 7
end

local cache = {}
local function clearCache() cache = {} end
QL.On("STATE_CHANGED", clearCache)
QL.On("INDEX_READY", clearCache)
QL.On("SETTING_CHANGED", function(key) if key and key:sub(1, 6) == "travel" then clearCache() end end)
local function refreshShown()
	clearCache()
	if QL.RefreshCurrent then pcall(QL.RefreshCurrent) end
end
QL.Event("ZONE_CHANGED_NEW_AREA", refreshShown)
QL.On("TRIP_CHANGED", refreshShown)

local function now() return call(rawget(_G, "GetTime")) or 0 end

-- the live plan for a quest (kept 3 s: you move)
function QL.TripFor(id, ctx)
	if not id or QL.DB().travelHints == false then return nil end
	local hit = cache[id]
	if hit and now() - hit.at < 3 then return hit.plan or nil end
	local plan = nil
	ctx = ctx or QL.Context()
	local map, px, py = QL.PlayerPosition()
	local target = map and px and QL.QuestTarget(id, ctx)
	local start = target and world(map, px, py)
	if start and target.points and #target.points > 0 then
		local here = false
		local goals = {}
		for i, p in ipairs(target.points) do
			if p.map == map then here = true end
			if i <= 40 then
				local g = world(p.map, p.x, p.y)
				if g then g.label = target.label; goals[#goals + 1] = g end
			end
		end
		if not here and #goals > 0 then
			local known = charTable("knownTaxi")
			local anyKnown = next(known) ~= nil
			local flights = {}
			for _, f in ipairs(flightMasters()) do
				flights[#flights + 1] = { inst = f.inst, x = f.x, y = f.y, point = f.point, npc = f.npc, zone = f.zone,
					known = known[f.npcId] and true or false }
			end
			local hearth = QL.DB().travelHearth ~= false and hearthReady() and QL.HearthSpot() or nil
			plan = QL.PlanTrip(start, goals, {
				speed = groundSpeed(ctx), flights = flights, transports = transports(), hearth = hearth,
				unknownPenalty = anyKnown and 300 or 45,
			})
		end
	end
	cache[id] = { at = now(), plan = plan or false }
	return plan
end

-- the step the arrow leads to now (nil: straight to the quest is fine)
function QL.TripNext(id)
	if QL.DB().travelArrow == false then return nil end
	if call(rawget(_G, "UnitOnTaxi"), "player") then return nil end
	local plan = QL.TripFor(id)
	if not plan or plan.simple then return nil end
	local s = plan.steps[1]
	if not s then return nil end
	-- the step's place: where you go (riding) or where it leaves from (flight, boat, zeppelin)
	local point = (s.kind == "ride" and s.to.point) or s.from.point
	return { kind = s.kind, step = s, point = point, text = (QL.TripStepText(s)), count = #plan.steps }
end

-- /ql travel [id]
function QL.TripDebug(arg)
	local id = tonumber(arg) or (QL.ArrowQuest and QL.ArrowQuest()) or (QL.CurrentQuest and QL.CurrentQuest(QL.Context()))
	QL.Chat("travel: faction " .. tostring(playerFaction()) .. ", flight masters " .. #flightMasters()
		.. ", known " .. (function() local n = 0; for _ in pairs(charTable("knownTaxi")) do n = n + 1 end; return n end)())
	local h = QL.HearthSpot()
	QL.Chat("hearthstone: " .. tostring(call(rawget(_G, "GetBindLocation"))) .. (h and " (spot found)" or " (no spot)") .. ", ready " .. tostring(hearthReady()))
	for _, t in ipairs(transports()) do
		QL.Chat(("  %s %s (%d %.3f %.3f) <-> %s (%d %.3f %.3f)"):format(t.kind, t.a.city, t.a.point.map, t.a.point.x, t.a.point.y,
			t.b.city, t.b.point.map, t.b.point.x, t.b.point.y))
	end
	if not id then QL.Chat("travel: no quest"); return end
	cache[id] = nil
	local plan = QL.TripFor(id)
	if not plan then QL.Chat("travel: quest " .. id .. ": no plan (same zone, no position or no target)"); return end
	QL.Chat(("travel: quest %d, %s total"):format(id, QL.TravelText and QL.TravelText(plan.total) or tostring(plan.total)))
	for i, s in ipairs(plan.steps) do
		local text, sub = QL.TripStepText(s)
		QL.Chat(("  %d. %s%s  (%ds)"):format(i, text, sub and (" · " .. sub) or "", math.floor(s.secs + 0.5)))
	end
end
