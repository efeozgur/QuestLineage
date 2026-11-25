-- Services: classifying NPCs, friendly ones only, mailboxes, nearest first, and the quick bar's
-- repeated click moving on to the next nearest.
local QL = dofile("tests/stubs.lua")
assert(loadfile("QuickBar.lua"))("QuestLineage", QL)
local Check, Eq = QL.Check, QL.Eq

local function has(list, k) for _, v in ipairs(list) do if v == k then return true end end return false end

-- classification by flags and subtitle
local c = QL.ClassifyNpc(4 + 16384, "Armorer")
Check(has(c, "repair") and has(c, "armor"), "an armourer who repairs")
c = QL.ClassifyNpc(16, "Warrior Trainer")
Check(has(c, "class:Warrior"), "a class trainer")
c = QL.ClassifyNpc(16, "Blacksmithing Trainer")
Check(has(c, "prof:Blacksmithing"), "a profession trainer")
c = QL.ClassifyNpc(16, "Weapon Master")
Check(has(c, "weaponmaster"), "a weapon master")
c = QL.ClassifyNpc(16, "Riding Trainer")
Check(has(c, "riding"), "a riding trainer")
c = QL.ClassifyNpc(4 + 128, "Innkeeper")
Check(has(c, "inn") and has(c, "food"), "an innkeeper sells food too")
c = QL.ClassifyNpc(4, "Bowyer")
Check(has(c, "ammo"), "a bowyer sells ammunition")
c = QL.ClassifyNpc(4, "Reagents")
Check(has(c, "reagent"), "reagents")
c = QL.ClassifyNpc(8, nil)
Check(has(c, "flight"), "a flight master by flag")
c = QL.ClassifyNpc(0, nil, "Spirit Healer")
Check(has(c, "spirit"), "a spirit healer by name")
Eq(#QL.ClassifyNpc(0, nil, "Raging Boar"), 0, "a creature is no service")

-- the index: Horde character; the Alliance smith and the boar are left out
QL.serviceFaction = "H"
QL.BuildIndexNow()
local repair = {}
for _, e in ipairs(QL.index.services.repair or {}) do repair[e[2]] = true end
Check(repair[200] and repair[201], "Horde repairers indexed")
Check(not repair[202], "the Alliance smith is not")
Eq(#(QL.index.services.mail or {}), 1, "one mailbox (the crate is not)")
Eq(QL.index.services.mail[1][1], "object", "a mailbox is an object")
Check(QL.index.services["prof:Mining"], "the mining trainer (friendly to both)")

-- nearest: the player in Durotar at 50, 40 on a 1000 x 1000 yard map
CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
C_Map = {
	GetBestMapForUnit = function() return 1411 end,
	GetPlayerMapPosition = function() return CreateVector2D(0.5, 0.4) end,
	GetMapWorldSize = function() return 1000, 1000 end,
	GetMapInfo = function(id) return id == 1411 and { name = "Durotar" } or nil end,
}
local near = QL.NearestServices("repair", 5)
Eq(#near, 2, "two repairers")
Eq(near[1].id, 200, "Grezz is nearest")
Check(math.abs(near[1].dist - 20) < 1e-6, "20 yards")
Eq(near[1].sub, "Armorer", "with his subtitle")
Eq(near[1].mapName, "Durotar", "and where")
Eq(near[2].id, 201, "then the far smith")
Eq(QL.NearestServices("mail", 1)[1].id, 300, "the mailbox")

-- class and profession trainers follow the character
UnitClass = function() return "Warrior", "WARRIOR", 1 end
Eq(QL.ClassTrainerKey(), "class:Warrior", "class trainer key")
Eq(QL.NearestServices("classTrainer", 1)[1].id, 203, "Thrag")
GetNumSkillLines = function() return 2 end
GetSkillLineInfo = function(i) if i == 1 then return "Professions", true end return "Mining", false end
Eq(QL.KnownProfessions()[1], "Mining", "known profession from the skill lines")
Eq(QL.NearestServices("profTrainer", 1)[1].id, 204, "the mining trainer")

-- the quick bar: a click points the arrow at the nearest, again at the next
local pointed = {}
QL.SetArrowPlace = function(kind, id, opts) pointed[#pointed + 1] = { kind, id, opts } end
local clock = 100
GetTime = function() return clock end
QL.GoToService("repair")
Eq(pointed[1][2], 200, "first click: nearest")
Check(pointed[1][3].label:find("Nearest", 1, true), "labelled nearest: " .. pointed[1][3].label)
clock = 105
QL.GoToService("repair")
Eq(pointed[2][2], 201, "second click: the next nearest")
clock = 107
QL.GoToService("repair")
Eq(pointed[3][2], 200, "and round again")
clock = 130
QL.GoToService("repair")
Eq(pointed[4][2], 200, "after a pause it starts from the nearest")
Eq(QL.GoToService("auction"), nil, "nothing found: nil")

print("services: ok")
