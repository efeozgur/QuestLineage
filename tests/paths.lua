-- Your own routes: stops, editing, following.
local QL = dofile("tests/stubs.lua")
assert(loadfile("Paths.lua"))("QuestLineage", QL)
local Check, Eq = QL.Check, QL.Eq

QL.Print = function() end -- messages are not under test

Eq(#QL.PathNames(), 0, "no routes at first")
local name = QL.PathNew()
Eq(QL.PathActive(), name, "a new route becomes the active one")
local second = QL.PathNew()
Check(second ~= name, "names are not reused")
QL.PathDelete(second)
Eq(QL.PathActive(), nil, "deleting the active route clears it")
QL.PathSelect(name)

-- stops
Eq(QL.PathAdd(name, 1411, 0.5, 0.5), 1, "the first stop is number 1")
Eq(QL.PathAdd(name, 1411, 0.6, 0.5), 2, "the second is number 2")
Eq(QL.PathAdd(name, 1411, 0.6, 0.6), 3, "the third is number 3")
Eq(QL.PathAdd(name, "x", 0.6, 0.6), nil, "a bad map is refused")
Eq(#QL.PathPoints(name), 3, "three stops")
Check(QL.PathMove(name, 2, 1411, 0.7, 0.5), "a stop can move")
Eq(QL.PathPoints(name)[2].x, 0.7, "it moved")
Eq(QL.PathMove(name, 9, 1411, 0.1, 0.1), false, "a missing stop cannot")
Check(QL.PathRemove(name, 2), "a stop can go")
Eq(#QL.PathPoints(name), 2, "two stops left")
Check(QL.PathUndo(name), "undo takes the last stop")
Eq(#QL.PathPoints(name), 1, "one stop left")
QL.PathAdd(name, 1411, 0.6, 0.5)
QL.PathAdd(name, 1411, 0.6, 0.6)

-- names
Check(QL.PathRename(name, "Mines"), "renaming works")
Eq(QL.PathActive(), "Mines", "the active route keeps up")
local other = QL.PathNew()
Eq(QL.PathRename(other, "Mines"), false, "a taken name is refused")
Eq(QL.PathRename(other, "   "), false, "an empty name is refused")
QL.PathDelete(other)
QL.PathSelect("Mines")
name = "Mines"

-- drawing: nothing until it is edited, followed or looked at
Eq(QL.PathStops(), nil, "a route nobody looks at is not drawn")

-- following: the arrow points at stop 1, moves on when close, the last stop ends it
local pointed
QL.SetArrowPoint = function(map, x, y, opts) pointed = { map = map, x = x, y = y, opts = opts }; QL.Fire("ARROW_CHANGED", "place") end
QL.ClearArrow = function() pointed = nil; QL.Fire("ARROW_CHANGED", nil) end
local dist = 500
QL.Locate = function() return { dist = dist } end

Check(QL.PathFollow(name), "following starts")
Eq(QL.PathFollowing().index, 1, "at the first stop")
Eq(pointed.x, 0.5, "the arrow points at stop 1")
Eq(pointed.opts.title, "Mines", "titled with the route")
local stops, info = QL.PathStops()
Eq(#stops, 3, "all three stops while at the first")
Eq(info.following, true, "marked as followed")
QL.PathCheck()
Eq(QL.PathFollowing().index, 1, "far away: no move on")
dist = 12
QL.PathCheck()
Eq(QL.PathFollowing().index, 2, "close: the next stop")
Eq(pointed.x, 0.6, "the arrow turned to stop 2")
stops = QL.PathStops()
Eq(#stops, 2, "only the stops ahead are drawn")
Eq(stops[1].n, 3 - 1, "numbered by their place in the route")
QL.PathCheck()
Eq(QL.PathFollowing().index, 3, "and on to the last")
QL.PathCheck()
Eq(QL.PathFollowing(), nil, "the last stop ends the route")
Eq(pointed, nil, "the arrow is cleared")

-- pointing the arrow elsewhere by hand ends following
QL.PathFollow(name)
QL.Fire("ARROW_CHANGED", 4242)
Eq(QL.PathFollowing(), nil, "a hand-picked arrow ends the route")

-- an empty route cannot be followed
local empty = QL.PathNew()
Eq(QL.PathFollow(empty), false, "no stops, nothing to follow")

-- the length (needs the client's map size: none here)
Check(QL.PathLength(name) == nil or QL.PathLength(name) >= 0, "length is a number or unknown")

-- deleting a followed route stops following
QL.PathFollow(name)
QL.PathDelete(name)
Eq(QL.PathFollowing(), nil, "a deleted route is not followed")

-- Detours: stop-over points bent into the line to a spot -------------------------------------------
local spot = { map = 1, x = 0.9, y = 0.9 }
Eq(QL.DetourKey(spot), QL.DetourKey({ map = 1, x = 0.9004, y = 0.8996 }), "the key is the spot rounded to 0.001")
Check(QL.DetourKey({ map = 2, x = 0.9, y = 0.9 }) ~= QL.DetourKey(spot), "another map, another key")
Eq(#QL.DetourPoints(spot), 0, "no detour at first")
Eq(QL.DetourInsert(spot, 1, 1, 0.5, 0.5), 1, "the first point")
Eq(QL.DetourInsert(spot, 1, 1, 0.2, 0.2), 1, "a point put in front")
Eq(QL.DetourPoints(spot)[1].x, 0.2, "it is first now")
Eq(QL.DetourPoints(spot)[2].x, 0.5, "the other follows")
Eq(QL.DetourInsert(spot, 99, 1, 0.7, 0.7), 3, "a far place means the end")
Check(QL.DetourMove(spot, 3, 1, 0.75, 0.75), "a point moves")
Eq(QL.DetourPoints(spot)[3].x, 0.75, "it moved")
Check(QL.DetourRemove(spot, 3), "a point goes")
Eq(#QL.DetourPoints(spot), 2, "two left")
Eq(QL.DetourInsert(spot, 1, "x", 0.1, 0.1), nil, "a bad map is refused")

-- the arrow's next point: a stand-in Locate that measures by the point's x (the spot has its own)
local dists = {}
QL.Locate = function(t)
	local p = t.points[1]
	return { dist = dists[p.x] or 999, point = p }
end
local loc = { dist = 300, point = spot }
dists[0.2], dists[0.5] = 100, 200
local vl, i, n = QL.DetourNext(loc)
Eq(i, 1, "starts at the nearest point")
Eq(n, 2, "of two")
Eq(vl.dist, 100, "and measures it")
Eq(#QL.DetourVias(spot), 2, "both still ahead")
dists[0.2] = 10
vl, i, n = QL.DetourNext(loc)
Eq(i, 1, "close to the first: the second is now the first")
Eq(n, 1, "one point left")
Eq(#QL.DetourPoints(spot), 1, "the walked-through point is deleted")
Eq(QL.DetourPoints(spot)[1].x, 0.5, "the other one stays")
dists[0.5] = 5
Eq(QL.DetourNext(loc), nil, "past the last: straight to the target")
Eq(#QL.DetourPoints(spot), 0, "the whole detour is gone")

-- standing nearer the destination than any point: the detour is behind you
QL.DetourInsert(spot, 1, 1, 0.2, 0.2)
QL.DetourInsert(spot, 2, 1, 0.5, 0.5)
dists[0.2], dists[0.5] = 100, 200
Eq(QL.DetourNext({ dist = 50, point = spot }), nil, "nearer the target than any point: no detour")

-- an edit starts the progress over
QL.Fire("PATH_CHANGED")
vl, i = QL.DetourNext(loc)
Eq(i, 1, "after an edit it starts over at the nearest")
Eq(#QL.DetourVias(spot, true), 2, "all of them while editing")

-- left behind: nearer to the next point than to the current one (no need to come within 15 yd)
QL.DetourClear(spot)
QL.DetourInsert(spot, 1, 1, 0.2, 0.2)
QL.DetourInsert(spot, 2, 1, 0.5, 0.5)
dists[0.2], dists[0.5] = 100, 200
Eq(select(2, QL.DetourNext(loc)), 1, "it starts at the first")
dists[0.2], dists[0.5] = 40, 25
vl, i, n = QL.DetourNext(loc)
Eq(n, 1, "past the first point toward the second: the first is deleted")
Eq(i, 1, "the second leads now")
Eq(QL.DetourPoints(spot)[1].x, 0.5, "only the second is left")

-- the whole detour goes with one call
QL.DetourClear(spot)
Eq(#QL.DetourPoints(spot), 0, "cleared")
Eq(QL.DetourNext(loc), nil, "no detour, no point")
print("paths: ok")
