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

-- XP at the player's level (Classic's reduction), chain XP, level gain, numbers
Eq(QL.XPFactor(10, 5), 1, "5 levels above: full")
Eq(QL.XPFactor(11, 5), 0.8, "6 above: 80%")
Eq(QL.XPFactor(14, 5), 0.2, "9 above: 20%")
Eq(QL.XPFactor(20, 5), 0.1, "10+ above: 10%")
local xp, full = QL.QuestXPAt(3, 12)
Eq(full, 450, "full XP")
Eq(xp, 270, "7 levels above: 60% of 450")
local cx = QL.ChainXP({ 1, 2, 3, 4, 5 }, QL.TestContext({ done = { [5] = true } }))
Eq(cx.done, 220, "done quests count full XP")
Eq(cx.remaining, 450, "quests left at your level")
Eq(cx.unknown, 3, "quests without XP data")
local g = QL.LevelGain(500, 5, 2000, 2800)
Eq(g.level, 5, "stays in level 5")
Check(math.abs(g.frac - 2500 / 2800) < 1e-9, "fraction after")
Check(math.abs(g.levels - 500 / 2800) < 1e-9, "share of a level")
Eq(g.approx, false, "within the level: exact")
g = QL.LevelGain(5000, 5, 2000, 2800) -- 800 to level 6, then 4200 of 3600 -> level 7, 600 into it
Eq(g.level, 7, "two levels up")
Check(math.abs(g.frac - 600 / 4500) < 1e-9, "into level 7")
Eq(g.approx, true, "past the current level: approximate")
Check(QL.GainText(g):find("reaches Lv 7", 1, true), "gain text: " .. QL.GainText(g))
Eq(QL.FormatNumber(1234567), "1,234,567", "thousands")
Eq(QL.FormatNumber(450), "450", "small number")
Eq(QL.XPText(2450), "2,450 XP", "xp text")

-- normal quest list: available Durotar quests for a level 5 human, most XP first
QL.zoneChainCache = {}
local list = QL.ZoneQuestList(14, QL.TestContext({ done = { [1] = true }, log = { [2] = true } }))
Eq(list[1].id, 5, "most XP first")
Eq(list[1].xp, 220, "its XP")
Eq(list[2].id, 2, "the logged quest")
Eq(list[2].inLog, true, "marked as logged")
Eq(#list, 2, "locked and too-high quests left out")

-- dungeons: by the quest's zone, or by a creature it needs living in one (an alternative area)
local dz = QL.QuestDungeon(25)
Eq(dz and dz.name, "The Deadmines", "dungeon by zone")
Eq(dz.kind, "dungeon", "a dungeon, not a raid")
Eq(QL.QuestDungeon(26) and QL.QuestDungeon(26).area, 1581, "dungeon by its creature's alternative area")
Eq(QL.QuestDungeon(3), nil, "a field quest")

-- difficulty against the player's level
Eq((QL.QuestDifficulty(15, 10)), "impossible", "5 above: very hard")
Eq((QL.QuestDifficulty(13, 10)), "hard", "3 above: hard")
Eq((QL.QuestDifficulty(12, 10)), "normal", "2 above: normal")
Eq((QL.QuestDifficulty(8, 10)), "normal", "2 below: normal")
Eq((QL.QuestDifficulty(7, 10)), "easy", "3 below: easy")
Eq(QL.GreyLevel(10), 4, "grey at 4 for level 10")
Eq((QL.QuestDifficulty(4, 10)), "trivial", "grey: trivial")
Eq((QL.QuestDifficulty(3, 5)), "normal", "low levels have no grey")
local tc = QL.TitleColor(25, QL.TestContext({ level = 10 }))
Eq(#tc, 3, "a title colour is r, g, b only")
Eq(QL.TitleColor(3, QL.TestContext({ level = 5 })), nil, "a normal quest keeps the default colour")

-- live objectives only for a quest in the log
Eq(QL.LiveObjectives(3), nil, "not in the log")

print("details: ok")
