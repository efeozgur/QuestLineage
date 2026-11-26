-- Zones: map -> area, subzones folded, the zone index, chains of a zone and their progress.
local QL = dofile("tests/stubs.lua")
local Check, Eq = QL.Check, QL.Eq

-- mapping from QuestieDB's support strings
Eq(QL.AreaForMap(1411), 14, "Durotar's map")
Eq(QL.AreaForMap(1412), 215, "Mulgore's map")
Eq(QL.TopArea(220), 215, "subzone folded into its zone")
Eq(QL.TopArea(14), 14, "a zone is its own top")
Eq(QL.AreaForMap(9999), nil, "unknown map")

-- an unknown map climbs to its parent
C_Map = {
	GetMapInfo = function(id)
		if id == 2000 then return { name = "Valley Cave", parentMapID = 1411 } end
		if id == 1411 then return { name = "Durotar", parentMapID = 1414 } end
		return nil
	end,
	GetBestMapForUnit = function() return 2000 end,
}
Eq(QL.AreaForMap(2000), 14, "cave map climbs to Durotar")
local area, uiMap, name = QL.PlayerZone()
Eq(area, 14, "player area")
Eq(uiMap, 2000, "player map")
Eq(name, "Valley Cave", "player map name")

-- the zone index
QL.BuildIndexNow()
local inDurotar = {}
for _, id in ipairs(QL.ZoneQuests(14)) do inDurotar[id] = true end
Check(inDurotar[1], "quest 1 is in Durotar through its giver")
Check(inDurotar[3] and inDurotar[12], "quests with Durotar as their zone")
Check(not inDurotar[14], "Mulgore quest not in Durotar")
local inMulgore = {}
for _, id in ipairs(QL.ZoneQuests(215)) do inMulgore[id] = true end
Check(inMulgore[14] and inMulgore[15], "subzone quest counted in Mulgore")

-- chains of a zone: the big web and the loop; the lone quest 10 is no chain
local ctx = QL.TestContext()
local chains = QL.ZoneChains(14, ctx)
Eq(#chains, 2, "two chains in Durotar")
local big = chains[1].size > chains[2].size and chains[1] or chains[2]
Eq(big.size, 8, "the web without the Orc quest")
Check(big.head == 1 or big.head == 5, "head is a first-generation quest: " .. tostring(big.head))
Eq(big.minLevel, 2, "lowest level")
Eq(big.maxLevel, 7, "highest level")
Eq(big.ids[1] == 1 or big.ids[1] == 5, true, "ids ordered by generation")
Check(QL.ZoneChains(14, ctx) == chains, "cached")
Eq(#QL.ZoneChains(215, ctx), 1, "one chain in Mulgore")
Eq(#QL.ZoneChains(999, ctx), 0, "nothing in an unknown zone")

-- progress
local p = QL.ChainProgress(big, QL.TestContext())
Eq(p.state, "available", "nothing done yet")
Eq(p.done, 0, "none done")
Eq(p.total, 8, "eight counted")
Check(p.focus == 1 or p.focus == 5, "opens at the first takeable quest")
p = QL.ChainProgress(big, QL.TestContext({ done = { [1] = true }, log = { [2] = true } }))
Eq(p.state, "active", "a quest in the log")
Eq(p.focus, 2, "opens at the quest in the log")
Eq(p.inLog, 1, "one in the log")
local all = {}
for _, id in ipairs(big.ids) do all[id] = true end
all[7] = nil -- closed by 6
p = QL.ChainProgress(big, QL.TestContext({ level = 20, done = all }))
Eq(p.state, "done", "every open quest done (7 closed)")
Eq(p.total, 7, "closed quest not counted")

print("zone: ok")

-- Class quests: a mask naming up to three classes; the warrior's (class bit 1)
QL.ResetData()
QL.BuildIndexNow()
local wq = {}
for _, id in ipairs(QL.ClassQuests(1)) do wq[id] = true end
Check(wq[20] and wq[21] and wq[22], "the warrior's quests")
Check(not wq[23], "a mage quest is not the warrior's")
Check(not wq[24], "a quest open to every class is no class quest")
local cc = QL.ClassChains(QL.TestContext())
Eq(#cc, 2, "a two-quest class chain and a single class quest")
local sizes = {}
for _, e in ipairs(cc) do sizes[e.head] = e.size end
Eq(sizes[20], 2, "Warrior's Trial heads its chain")
Eq(sizes[22], 1, "a single class quest is kept")
Check(QL.ClassChains(QL.TestContext()) == cc, "cached")
Eq(#QL.ClassChains(QL.TestContext({ classFlag = 2 })), 0, "no paladin quests in the fixture")
UnitClass = function() return "Savaşçı", "WARRIOR", 1 end
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
local pc = QL.PlayerClass()
Eq(pc.name, "Savaşçı", "class name from the client")
Eq(pc.color[1], 0.78, "class colour")

-- a zone's level band from its quests
local lo, hi, n = QL.ZoneLevels(14, QL.TestContext())
Check(lo and hi and n, "Durotar has a level band")
Check(lo >= 2 and hi <= 10 and lo <= hi, ("band inside the quest levels: %s-%s"):format(tostring(lo), tostring(hi)))
Check(n >= 8, "counted from its quests: " .. tostring(n))
Eq(QL.ZoneLevels(99999, QL.TestContext()), nil, "no band for a zone without quests")
Eq(QL.ZoneLevels(nil, QL.TestContext()), nil, "no band without a zone")

print("zone (classes): ok")
