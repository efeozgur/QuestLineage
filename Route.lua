-- Routes: a set of quests the player ticks, visited nearest-first.
--
-- Each quest is one stop at a time: where it needs you now (QL.QuestTarget: its giver, the
-- nearest spot of its unfinished objectives, its hand-in). The plan orders the stops from the
-- player's position: nearest neighbour first, then 2-opt swaps that shorten the path. Whenever a
-- quest's stop changes (taken, objectives done, handed in) the rest is planned again from where
-- the player stands, so nearby pick-ups, kills and hand-ins of different quests interleave.
-- The arrow is pointed at the first stop; a handed-in quest leaves the route; an empty route ends.
--
--   QL.PlanRoute(ids, ctx) -> { order = {ids}, legs = {yards}, total, unplaced = {ids},
--                                spots = { [i] = {map, x, y} the spot chosen for order[i] } }
--   QL.StartRoute(ids)  QL.StopRoute()  QL.RouteActive()  QL.RouteInfo() -> { index, total, next }
--   QL.RouteSelect(id, on)  QL.RouteSelected(id)  QL.RouteSelection() -> ids  QL.ClearRouteSelection()

local _, QL = ...

local MAX_POINTS = 30 -- per stop, when measuring

local function L(s) return QL.L(s) end

-- Geometry: every stop's points on the player's map, in yards ------------------------------------

local function mapSize(map)
	if not (C_Map and C_Map.GetMapWorldSize) then return nil end
	local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
	if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
	return nil
end

local function stopPoints(target, map, w, h)
	local pts = {}
	for i, p in ipairs(target.points) do
		if i > MAX_POINTS * 4 or #pts >= MAX_POINTS then break end
		local x, y = QL.ProjectToMap(p.map, p.x, p.y, map)
		if x then pts[#pts + 1] = { x * w, y * h, src = p } end
	end
	return pts
end

local function d2(a, b)
	local dx, dy = a[1] - b[1], a[2] - b[2]
	return dx * dx + dy * dy
end

local function nearestOf(pts, from)
	local best, bd
	for _, p in ipairs(pts) do
		local d = d2(p, from)
		if not bd or d < bd then best, bd = p, d end
	end
	return best, bd
end

-- 2-opt on an open path that starts at `start`: reverse any segment that makes it shorter.
local function twoOpt(seq, start)
	local n = #seq
	if n < 3 then return seq end
	local function at(i) return i == 0 and start or seq[i].at end
	local improved, passes = true, 0
	while improved and passes < 50 do
		improved, passes = false, passes + 1
		for i = 1, n - 1 do
			for j = i + 1, n do
				-- edges (i-1, i) and (j, j+1) become (i-1, j) and (i, j+1)
				local a, b, c = at(i - 1), at(i), at(j)
				local dBefore = math.sqrt(d2(a, b))
				local dAfter = math.sqrt(d2(a, c))
				if j < n then
					local e = at(j + 1)
					dBefore = dBefore + math.sqrt(d2(c, e))
					dAfter = dAfter + math.sqrt(d2(b, e))
				end
				if dAfter + 1e-6 < dBefore then
					local lo, hi = i, j
					while lo < hi do seq[lo], seq[hi] = seq[hi], seq[lo]; lo, hi = lo + 1, hi - 1 end
					improved = true
				end
			end
		end
	end
	return seq
end

function QL.PlanRoute(ids, ctx)
	ctx = ctx or QL.Context()
	local result = { order = {}, legs = {}, total = 0, unplaced = {}, spots = {} }
	local map, px, py = QL.PlayerPosition()
	local w, h
	if map then w, h = mapSize(map) end -- (`map and mapSize(map)` would keep only the width)
	local stops = {}
	for _, id in ipairs(ids) do
		local t = QL.QuestTarget(id, ctx)
		local pts = (t and map and px and w) and stopPoints(t, map, w, h) or {}
		if #pts > 0 then stops[#stops + 1] = { id = id, pts = pts } else result.unplaced[#result.unplaced + 1] = id end
	end
	if #stops > 0 then
		-- nearest neighbour from the player, each stop at its point nearest to the stop before
		local cur = { px * w, py * h }
		local start = cur
		local left, seq = {}, {}
		for _, s in ipairs(stops) do left[#left + 1] = s end
		while #left > 0 do
			local bi, bp, bd
			for i, s in ipairs(left) do
				local p, d = nearestOf(s.pts, cur)
				if not bd or d < bd then bi, bp, bd = i, p, d end
			end
			local s = table.remove(left, bi)
			s.at = bp
			seq[#seq + 1] = s
			cur = bp
		end
		twoOpt(seq, start)
		local prev = start
		for _, s in ipairs(seq) do
			result.order[#result.order + 1] = s.id
			result.spots[#result.order] = s.at.src
			local leg = math.sqrt(d2(prev, s.at))
			result.legs[#result.legs + 1] = leg
			result.total = result.total + leg
			prev = s.at
		end
	end
	-- stops that cannot be measured from here (another continent, no data) go last
	for _, id in ipairs(result.unplaced) do result.order[#result.order + 1] = id end
	return result
end

-- Selection ------------------------------------------------------------------------------------------

local selected, selOrder = {}, {}

function QL.RouteSelect(id, on)
	if on and not selected[id] then
		selected[id] = true
		selOrder[#selOrder + 1] = id
	elseif not on and selected[id] then
		selected[id] = nil
		for i, v in ipairs(selOrder) do if v == id then table.remove(selOrder, i); break end end
	end
	QL.Fire("ROUTE_CHANGED")
end

function QL.RouteSelected(id) return selected[id] and true or false end
function QL.RouteSelection()
	local out = {}
	for _, id in ipairs(selOrder) do out[#out + 1] = id end
	return out
end
function QL.ClearRouteSelection()
	selected, selOrder = {}, {}
	QL.Fire("ROUTE_CHANGED")
end

-- Following ------------------------------------------------------------------------------------------

local route -- { ids = {..}, plan = {..}, startCount, signature }

local function charKey()
	local name = UnitName and UnitName("player") or "?"
	local realm = GetRealmName and GetRealmName() or "?"
	return tostring(name) .. "-" .. tostring(realm)
end

local function store()
	local db = QL.DB()
	if type(db.routes) ~= "table" then db.routes = {} end
	if route then
		db.routes[charKey()] = { ids = route.ids, startCount = route.startCount }
	else
		db.routes[charKey()] = nil
	end
end

-- What each route quest needs right now; a change means: plan again.
local function signature(ids, ctx)
	local parts = {}
	for _, id in ipairs(ids) do
		local s = QL.NodeStatus(id, ctx)
		local live = QL.LiveObjectives(id)
		local done = 0
		for _, o in ipairs(live or {}) do if o.done then done = done + 1 end end
		parts[#parts + 1] = id .. ":" .. s .. ":" .. done
	end
	return table.concat(parts, ",")
end

local function replan(quiet)
	if not route then return end
	local ctx = QL.Context()
	local keep = {}
	for _, id in ipairs(route.ids) do
		if QL.NodeStatus(id, ctx) ~= "done" and not route.gone[id] then keep[#keep + 1] = id end
	end
	route.ids = keep
	if #keep == 0 then
		QL.Print(L("Route complete."))
		route = nil
		store()
		if QL.ClearArrow then QL.ClearArrow() end
		QL.Fire("ROUTE_CHANGED")
		return
	end
	local plan = QL.PlanRoute(keep, ctx)
	route.plan = plan.order
	route.spots = plan.spots
	route.total = plan.total
	route.signature = signature(keep, ctx)
	local first = plan.order[1]
	local was = QL.ArrowQuest and QL.ArrowQuest()
	if QL.SetArrowTarget and first ~= was then
		route.steering = true
		QL.SetArrowTarget(first, true)
		route.steering = nil
		if not quiet then QL.Print(L("Route, next: ") .. QL.QuestTitle(first)) end
	end
	store()
	QL.Fire("ROUTE_CHANGED")
end

function QL.StartRoute(ids, quiet)
	local list = {}
	for _, id in ipairs(ids or QL.RouteSelection()) do list[#list + 1] = id end
	if #list == 0 then return end
	route = { ids = list, startCount = #list, gone = {} }
	replan(true)
	if route and not quiet then
		QL.Print(L("Route: %d stops · about %s"):format(#route.plan, QL.DistanceTextYards(route.total)))
	end
end

function QL.StopRoute()
	if not route then return end
	route = nil
	store()
	if QL.ClearArrow then QL.ClearArrow() end
	QL.Fire("ROUTE_CHANGED")
end

function QL.RouteActive() return route ~= nil end
function QL.RouteSteering() return route and route.steering or false end

-- { index = stop number now, total = stops at the start, next = quest id, order = planned ids }
function QL.RouteInfo()
	if not route or not route.plan then return nil end
	local done = route.startCount - #route.ids
	return { index = done + 1, total = route.startCount, next = route.plan[1], order = route.plan, spots = route.spots or {}, length = route.total }
end

-- The position of a quest in the current plan (1 = next), or nil.
function QL.RouteStop(id)
	if not route or not route.plan then return nil end
	for i, v in ipairs(route.plan) do if v == id then return i end end
	return nil
end

function QL.DistanceTextYards(y)
	if not y or y <= 0 then return L("%d yd"):format(0) end
	if y >= 1000 then
		local s = ("%.1f"):format(y / 1000)
		if QL.UseTurkish() then s = s:gsub("%.", ",") end
		return L("%s k yd"):format(s)
	end
	return L("%d yd"):format(math.floor(y + 0.5))
end

-- A quest's stage changed (taken, objectives done): plan the rest again from here.
QL.On("STATE_CHANGED", function()
	if not route then return end
	local ok, err = pcall(function()
		local sig = signature(route.ids, QL.Context())
		if sig ~= route.signature then replan() end
	end)
	if not ok then QL.Debug("route: " .. tostring(err)) end
end)

-- Handed in: it leaves the route at once (the log may not say "completed" yet).
QL.Event("QUEST_TURNED_IN", function(_, id)
	if route and id then
		route.gone[id] = true
		local ok, err = pcall(replan)
		if not ok then QL.Debug("route: " .. tostring(err)) end
	end
end)

-- Picking another quest by hand ends the route (the arrow follows the player's choice).
QL.On("ARROW_CHANGED", function(id)
	if route and not route.steering and id and id ~= (route.plan and route.plan[1]) then
		QL.Print(L("Route stopped: you pointed the arrow elsewhere."))
		route = nil
		store()
		QL.Fire("ROUTE_CHANGED")
	end
end)

QL.Event("PLAYER_LOGIN", function()
	local db = QL.DB()
	local saved = type(db.routes) == "table" and db.routes[charKey()]
	if saved and type(saved.ids) == "table" and #saved.ids > 0 then
		QL.WhenIndexed(function()
			route = { ids = saved.ids, startCount = saved.startCount or #saved.ids, gone = {} }
			local ok, err = pcall(replan, true)
			if not ok then QL.Debug("route restore: " .. tostring(err)) end
		end)
	end
end)
