-- Route planning: nearest first from the player, improved by 2-opt; unmeasurable stops last.
local QL = dofile("tests/stubs.lua")
assert(loadfile("Nav.lua"))("QuestLineage", QL)
assert(loadfile("Route.lua"))("QuestLineage", QL)
local Check, Eq = QL.Check, QL.Eq

-- one map, 1000 x 1000 yards; the player in the middle
CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
local px, py = 0.5, 0.5
C_Map = {
	GetBestMapForUnit = function() return 1 end,
	GetPlayerMapPosition = function() return CreateVector2D(px, py) end,
	GetMapWorldSize = function() return 1000, 1000 end,
}
-- every quest's stop comes from this table instead of the database
local SPOTS = {}
QL.QuestTarget = function(id)
	local s = SPOTS[id]
	if not s then return { kind = "pickup", points = {} } end
	local pts = {}
	for _, p in ipairs(s) do pts[#pts + 1] = { map = 1, x = p[1], y = p[2] } end
	return { kind = "pickup", points = pts }
end

-- nearest first would go 2 (100 east), 1, 4, 3 = about 1107 yards; the 2-opt pass finds
-- 2, 4, 1, 3 = about 1090 yards (ending at 1 brings the long last leg north closer)
SPOTS = { [1] = { { 0.9, 0.5 } }, [2] = { { 0.6, 0.5 } }, [3] = { { 0.5, 0.1 } }, [4] = { { 0.95, 0.55 } } }
local plan = QL.PlanRoute({ 1, 2, 3, 4 }, QL.TestContext())
Eq(table.concat(plan.order, ","), "2,4,1,3", "nearest first, improved by 2-opt")
Check(math.abs(plan.total - (100 + math.sqrt(350 ^ 2 + 50 ^ 2) + math.sqrt(50 ^ 2 + 50 ^ 2) + math.sqrt(400 ^ 2 + 400 ^ 2))) < 1e-6, "the shorter total: " .. plan.total)
Check(math.abs(plan.legs[1] - 100) < 1e-6, "first leg 100 yards")
Check(plan.total > 0, "total length")

-- a stop with several spots is measured at the spot nearest to the stop before it
SPOTS = { [1] = { { 0.1, 0.1 }, { 0.55, 0.5 } }, [2] = { { 0.9, 0.9 } } }
plan = QL.PlanRoute({ 2, 1 }, QL.TestContext())
Eq(plan.order[1], 1, "its near spot makes quest 1 the first stop")
Check(math.abs(plan.legs[1] - 50) < 1e-6, "measured at the near spot")

-- a stop that cannot be measured goes last
SPOTS = { [1] = { { 0.6, 0.5 } }, [2] = { { 0.7, 0.5 } } }
plan = QL.PlanRoute({ 9, 2, 1 }, QL.TestContext())
Eq(table.concat(plan.order, ","), "1,2,9", "no location: last")
Eq(plan.unplaced[1], 9, "listed as unplaced")

-- quality: against the best order found by trying them all (6 stops, 720 orders)
local function pathLength(order, pts)
	local x, y, total = px * 1000, py * 1000, 0
	for _, id in ipairs(order) do
		local p = pts[id]
		total = total + math.sqrt((p[1] * 1000 - x) ^ 2 + (p[2] * 1000 - y) ^ 2)
		x, y = p[1] * 1000, p[2] * 1000
	end
	return total
end
local function best(ids, pts)
	local bestLen = math.huge
	local function permute(a, n)
		if n == 0 then
			local l = pathLength(a, pts)
			if l < bestLen then bestLen = l end
			return
		end
		for i = 1, n do
			a[i], a[n] = a[n], a[i]
			permute(a, n - 1)
			a[i], a[n] = a[n], a[i]
		end
	end
	local copy = {}
	for i, v in ipairs(ids) do copy[i] = v end
	permute(copy, #copy)
	return bestLen
end
math.randomseed(7)
local worst = 1
for _ = 1, 25 do
	SPOTS = {}
	local ids, pts = {}, {}
	for i = 1, 6 do
		local p = { math.random(), math.random() }
		SPOTS[i] = { p }
		pts[i] = p
		ids[i] = i
	end
	plan = QL.PlanRoute(ids, QL.TestContext())
	local ratio = plan.total / best(ids, pts)
	if ratio > worst then worst = ratio end
end
Check(worst < 1.2, ("within 20%% of the best order on random layouts (worst %.3f)"):format(worst))

-- selection
QL.RouteSelect(5, true)
QL.RouteSelect(2, true)
QL.RouteSelect(5, false)
Eq(table.concat(QL.RouteSelection(), ","), "2", "ticking and unticking")
Eq(QL.RouteSelected(2), true, "ticked")
QL.ClearRouteSelection()
Eq(#QL.RouteSelection(), 0, "cleared")

print("route: ok")
