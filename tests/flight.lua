-- Flight timer: learning a route's time, counting down, refining, formatting.
local QL = dofile("tests/stubs.lua")
assert(loadfile("Flight.lua"))("QuestLineage", QL)
local Check, Eq = QL.Check, QL.Eq

Eq(QL.FlightFormat(65), "1:05", "minutes and seconds")
Eq(QL.FlightFormat(9.4), "0:09", "under a minute")
Eq(QL.FlightFormat(3725), "1:02:05", "hours when long")
Eq(QL.FlightFormat(-3), "0:00", "never negative")

Eq(QL.FlightStatus(0), nil, "no status off a flight")

-- first flight on a route: learning, counting up
QL.FlightBegin(100, "Orgrimmar", "Crossroads")
local st = QL.FlightStatus(130)
Check(st.learning, "a new route is being learned")
Eq(st.elapsed, 30, "elapsed counts up")
Eq(st.remaining, nil, "no remaining time yet")
Eq(QL.FlightEnd(160), 60, "the landing returns the duration")
Eq(QuestLineageDB.flightTimes["Orgrimmar>Crossroads"], 60, "the time is kept")
Eq(QL.FlightActive(), false, "no longer flying")

-- second flight: counts down
QL.FlightBegin(200, "Orgrimmar", "Crossroads")
st = QL.FlightStatus(215)
Eq(st.remaining, 45, "45 s left after 15 of 60")
Check(math.abs(st.fraction - 0.25) < 1e-9, "a quarter of the way")
Eq(st.over, false, "not late")
st = QL.FlightStatus(275)
Eq(st.remaining, 0, "remaining stops at zero")
Eq(st.over, true, "a late flight is marked")
Eq(st.fraction, 1, "the bar stays full")

-- a close time is averaged, a very different one replaces it
QL.FlightEnd(266) -- 66 s
Eq(QuestLineageDB.flightTimes["Orgrimmar>Crossroads"], 63, "close times average")
QL.FlightBegin(300, "Orgrimmar", "Crossroads")
QL.FlightEnd(400) -- 100 s
Eq(QuestLineageDB.flightTimes["Orgrimmar>Crossroads"], 100, "a different time replaces it")

-- a hop is not kept; other routes are separate
QL.FlightBegin(500, "A", "B")
QL.FlightEnd(502)
Eq(QuestLineageDB.flightTimes["A>B"], nil, "a 2 s ride is not kept")
Eq(QuestLineageDB.flightTimes["Orgrimmar>Crossroads"], 100, "other routes untouched")

-- the demo flight keeps nothing
local s = QL.FlightBegin(600, "Demo", "Orgrimmar")
s.demo, s.expected = true, 20
QL.FlightEnd(700)
Eq(QuestLineageDB.flightTimes["Demo>Orgrimmar"], nil, "the demo is not stored")

print("flight: ok")
