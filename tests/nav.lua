-- Navigation: where a quest sends you, the player's place, the nearest spot, the bearing.
local QL = dofile("tests/stubs.lua")
assert(loadfile("Nav.lua"))("QuestLineage", QL)
local Check, Eq = QL.Check, QL.Eq
QL.BuildIndexNow()

-- spawn areas map to uiMaps through QuestieDB's areaIdToUiMapId
Eq(QL.AreaUiMap(14), 1411, "Durotar's map")
Eq(QL.AreaUiMap(220), 1412, "a subzone uses its zone's map")

-- not in the log: go to the giver
local t = QL.QuestTarget(3, QL.TestContext())
Eq(t.kind, "pickup", "pick up first")
Check(t.label:find("Bob", 1, true), "giver named: " .. t.label)
Eq(#t.points, 1, "Bob's one spawn")
Eq(t.points[1].map, 1411, "on Durotar's map")
Check(math.abs(t.points[1].x - 0.452) < 1e-9 and math.abs(t.points[1].y - 0.631) < 1e-9, "percent -> 0-1")

-- in the log: the objectives' creatures (Bob; the ribs' boar has no spawns)
t = QL.QuestTarget(3, QL.TestContext({ log = { [3] = true } }))
Eq(t.kind, "objective", "objectives while in the log")
Check(t.label:find("Bob questioned", 1, true), "objective label: " .. t.label)
Eq(#t.points, 1, "Bob's spawn")

-- complete: hand it in to Alice (spawns in Mulgore and Durotar)
t = QL.QuestTarget(3, QL.TestContext({ log = { [3] = true }, complete = { [3] = true } }))
Eq(t.kind, "turnin", "hand in when complete")
Check(t.label:find("Alice", 1, true), "turn-in NPC: " .. t.label)
Eq(#t.points, 2, "both of Alice's spawns")

-- done: nothing to point at
Eq(QL.QuestTarget(3, QL.TestContext({ done = { [3] = true } })), nil, "done quest")

-- a quest in the log with no objective data falls back to its hand-in
t = QL.QuestTarget(1, QL.TestContext({ log = { [1] = true } }))
Eq(t.kind, "turnin", "no objectives: hand in")

-- bearing: up-pointing arrow, facing north (0)
local function near(a, b) return math.abs(a - b) < 1e-9 end
Check(near(QL.Bearing(0, -10, 0), 0), "target north, facing north: straight up")
Check(near(QL.Bearing(10, 0, 0), 3 * math.pi / 2), "target east: turn right (clockwise)")
Check(near(QL.Bearing(-10, 0, 0), math.pi / 2), "target west: turn left")
Check(near(QL.Bearing(0, 10, 0), math.pi), "target south: behind")
Check(near(QL.Bearing(0, -10, math.pi / 2), 3 * math.pi / 2), "facing west, target north: to the right")

-- locating: the player in Durotar at 50,50 (a 1000 x 800 yard map); Alice's Durotar spawn wins
CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
C_Map = {
	GetBestMapForUnit = function() return 1411 end,
	GetPlayerMapPosition = function() return CreateVector2D(0.5, 0.4) end,
	GetMapWorldSize = function() return 1000, 800 end,
	-- Mulgore lies far away on the same continent
	GetWorldPosFromMapPos = function(map, pos) return 1, { x = pos.x + (map == 1412 and 5 or 0), y = pos.y } end,
	GetMapPosFromWorldPos = function(inst, world, map) return map, CreateVector2D(world.x, world.y) end,
}
t = QL.QuestTarget(3, QL.TestContext({ log = { [3] = true }, complete = { [3] = true } }))
local loc = QL.Locate(t)
Check(loc and not loc.otherMap, "located")
Eq(loc.point.map, 1411, "the Durotar spawn is the nearest")
Check(near(loc.dx, 0) and near(loc.dy, 80), "10% of 800 yards south: " .. loc.dx .. ", " .. loc.dy)
Check(near(loc.dist, 80), "80 yards")

-- a target only on a map that cannot be projected: say where to go
C_Map.GetWorldPosFromMapPos = function() return nil end
local far = { kind = "pickup", points = { { map = 1412, x = 0.1, y = 0.1 } } }
loc = QL.Locate(far)
Eq(loc.otherMap.map, 1412, "another map")

-- no position (an instance): nil
C_Map.GetPlayerMapPosition = function() return nil end
Eq(QL.Locate(t == nil and far or { points = { { map = 1411, x = 0.1, y = 0.1 } } }), nil, "no player position")

print("nav: ok")
