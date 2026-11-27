-- Getting there: the trip planner (pure part of Travel.lua) on made-up points.
local QL = dofile("tests/stubs.lua")
assert(loadfile("Travel.lua"))("QuestLineage", QL)
local Check, Eq = QL.Check, QL.Eq

local KALIMDOR, EK = 1, 0
local function at(inst, x, y, extra)
	local n = { inst = inst, x = x, y = y, point = { map = 1, x = 0, y = 0 } }
	for k, v in pairs(extra or {}) do n[k] = v end
	return n
end
local function kinds(plan)
	local out = {}
	for _, s in ipairs(plan.steps) do out[#out + 1] = s.kind end
	return table.concat(out, ",")
end

-- close by on the same continent: ride straight
local plan = QL.PlanTrip(at(KALIMDOR, 0, 0), { at(KALIMDOR, 700, 0) }, { speed = 7 })
Eq(kinds(plan), "ride", "near: just ride")
Check(plan.simple, "a plain ride is simple")
Check(math.abs(plan.total - 700 * 1.25 / 7) < 1e-6, "ride time: winding factor over speed")

-- far on the same continent with flight masters at both ends: fly
local fmHere = at(KALIMDOR, 40, 0, { known = true, npc = "Here" })
local fmThere = at(KALIMDOR, 9000, 0, { known = true, npc = "There" })
plan = QL.PlanTrip(at(KALIMDOR, 0, 0), { at(KALIMDOR, 9100, 0) }, { speed = 7, flights = { fmHere, fmThere } })
Eq(kinds(plan), "ride,fly,ride", "far: ride to the flight master, fly, ride on")
Eq(plan.steps[2].known, true, "both flight points known")
Check(not plan.simple, "a flight is not simple")

-- standing at the flight master: no walk to it
plan = QL.PlanTrip(at(KALIMDOR, 30, 0), { at(KALIMDOR, 9100, 0) }, { speed = 7, flights = { fmHere, fmThere } })
Eq(kinds(plan), "fly,ride", "already at the flight master")

-- an unknown flight point is flagged, and a big penalty sends you riding when that is close
local fmUnknown = at(KALIMDOR, 9000, 0, { known = false, npc = "There" })
plan = QL.PlanTrip(at(KALIMDOR, 0, 0), { at(KALIMDOR, 9100, 0) }, { speed = 7, flights = { fmHere, fmUnknown }, unknownPenalty = 45 })
Eq(plan.steps[2].kind, "fly", "a maybe-known flight still wins over a long ride")
Eq(plan.steps[2].known, false, "flagged as not known")
plan = QL.PlanTrip(at(KALIMDOR, 0, 0), { at(KALIMDOR, 1500, 0) }, { speed = 7, flights = { fmHere, at(KALIMDOR, 1400, 0, { known = false }) }, unknownPenalty = 300 })
Eq(kinds(plan), "ride", "a short way rides rather than an unknown flight")

-- another continent: only a transport gets there
local zep = { kind = "zeppelin", time = 240, a = at(KALIMDOR, 100, 0, { city = "Orgrimmar", place = "tower" }), b = at(EK, 0, 0, { city = "Undercity", place = "tower" }) }
local boat = { kind = "boat", time = 240, a = at(KALIMDOR, 5000, 0, { city = "Theramore" }), b = at(EK, 3000, 0, { city = "Menethil Harbor" }) }
plan = QL.PlanTrip(at(KALIMDOR, 0, 0), { at(EK, 500, 0) }, { speed = 7, transports = { zep, boat } })
Eq(kinds(plan), "ride,zeppelin,ride", "the nearer line: the zeppelin")
Eq(plan.steps[2].to.city, "Undercity", "lands in Undercity")
plan = QL.PlanTrip(at(KALIMDOR, 0, 0), { at(EK, 500, 0) }, { speed = 7, transports = { boat } })
Eq(kinds(plan), "ride,boat,ride", "without the zeppelin (other faction): the boat")
Eq(QL.PlanTrip(at(KALIMDOR, 0, 0), { at(EK, 500, 0) }, { speed = 7 }), nil, "no line: no plan")

-- the hearthstone, when it lands near the quest
local hearth = at(EK, 600, 0, { label = "Tarren Mill" })
plan = QL.PlanTrip(at(KALIMDOR, 0, 0), { at(EK, 500, 0) }, { speed = 7, transports = { zep }, hearth = hearth })
Eq(kinds(plan), "hearth,ride", "hearthstone first")
local text, sub = QL.TripStepText(plan.steps[1])
Eq(text, "Use your hearthstone", "hearth text")
Eq(sub, "Tarren Mill", "where it takes you")

-- texts
plan = QL.PlanTrip(at(KALIMDOR, 0, 0), { at(EK, 500, 0) }, { speed = 7, transports = { zep } })
Eq((QL.TripStepText(plan.steps[2])), "Take the zeppelin to Undercity", "zeppelin text")
Eq(QL.TripSummary(plan), "Zeppelin → Undercity", "summary skips the rides")
local fly = QL.PlanTrip(at(KALIMDOR, 0, 0), { at(KALIMDOR, 9100, 0) }, { speed = 7, flights = { fmHere, fmUnknown } })
local ft, fs = QL.TripStepText(fly.steps[2])
Check(fs and fs:find("if you have that flight point", 1, true), "an unknown flight point says so")
Check(ft:find("Fly to", 1, true) == 1, "fly text")

-- the transport table: every line has both ends on a map
for i, t in ipairs(QL.TRANSPORTS) do
	Check(t.a.map and t.b.map and t.a.city and t.b.city and t.faction, "transport line " .. i .. " complete")
end

print("travel: ok")
