-- Quest details: XP, reputation, tasks with pictures, people and places, reward items, story.
local QL = dofile("tests/stubs.lua")
local Check, Eq = QL.Check, QL.Eq

C_Map = {
	GetAreaInfo = function(area) return ({ [14] = "Durotar", [215] = "Mulgore" })[area] end,
	GetBestMapForUnit = function() return 1411 end,
	GetMapInfo = function() return nil end,
}
C_Item = {
	GetItemIconByID = function(id) return 1000 + id end,
	GetItemQualityByID = function(id) return id == 500 and 2 or 1 end,
}
C_Reputation = { GetFactionDataByID = function(id) return id == 76 and { name = "Orgrimmar" } or nil end }
QL.BuildIndexNow()

Eq(QL.QuestXP(3), 450, "xp from QuestieDB's support data")
Eq(QL.QuestXP(2), nil, "no xp row")

local rep = QL.QuestReputation(3)
Eq(#rep, 1, "one reputation reward")
Eq(rep[1][2], 250, "reputation value")
Eq(rep[1][3], "Orgrimmar", "faction name from the client")

local tasks = QL.QuestTasks(3)
Eq(#tasks, 2, "a creature and an item")
Eq(tasks[1].kind, "npc", "creature first")
Eq(tasks[1].npc, 100, "creature picture")
Eq(tasks[1].text, "Bob questioned", "objective text from the database")
Eq(tasks[2].kind, "item", "item")
Eq(tasks[2].name, "Boar Ribs", "item name")
Eq(tasks[2].npc, 102, "the creature that drops it is its picture")
Eq(#QL.QuestTasks(2), 0, "no objectives")

local s = QL.QuestStarter(3)
Eq(s.kind, "npc", "started by an NPC")
Eq(s.name, "Bob", "giver name")
Eq(QL.QuestFinisher(3).name, "Alice", "turn-in NPC")
Eq(QL.QuestStarter(2), nil, "no giver data")

local zone, x, y = QL.QuestPlace("npc", 100)
Eq(zone, "Durotar", "giver's zone")
Eq(x, 45.2, "x")
Eq(y, 63.1, "y")
zone = QL.QuestPlace("npc", 101)
Eq(zone, "Durotar", "the spawn in the player's zone wins")

local items = QL.RewardItems(3)
Eq(#items, 1, "one reward item")
Eq(items[1], 500, "reward from the item's questRewards")
Eq(QL.ItemIcon(500), 1500, "item icon")
Eq(QL.ItemQuality(500), 2, "item quality")

-- story: Turkish from WoWTR ($B is WoWTR's line break)
Eq(QL.QuestDescription(3), nil, "no story outside the log in English")
QL.Set("lang", "tr")
QTR_QuestData = { ["3"] = { Title = "Toplanma", Description = "Uzun bir hikaye.$BYeni satir." } }
Eq(QL.QuestDescription(3), "Uzun bir hikaye.\nYeni satir.", "story from WoWTR")
QL.Set("lang", "en")

-- live objectives only for a quest in the log
Eq(QL.LiveObjectives(3), nil, "not in the log")

print("details: ok")
