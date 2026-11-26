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
print("paths: ok")
