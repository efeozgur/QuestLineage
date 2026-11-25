-- Language choice: English by default, Turkish only while WoWTR is loaded.
local QL = dofile("tests/stubs.lua")
local Check, Eq = QL.Check, QL.Eq

Eq(QL.DB().lang, "en", "English by default")
Eq(QL.L("Chain"), "Chain", "English string")
Eq(QL.QuestTitle(1), "First Steps", "title from QuestieDB")
Eq(QL.QuestObjectives(1), "Talk to Bob.", "objectives from QuestieDB")
Eq(QL.QuestTitle(999), "Quest #999", "unknown quest")

-- Turkish chosen but WoWTR missing: stays English
QL.Set("lang", "tr")
Check(not QL.HasWoWTR(), "no WoWTR")
Check(not QL.UseTurkish(), "Turkish needs WoWTR")
Eq(QL.L("Chain"), "Chain", "still English")
Eq(QL.FontPath(), "Fonts\\FRIZQT__.TTF", "game font")

-- WoWTR loaded
QTR_QuestData = { ["1"] = { Title = "İlk Adımlar", Objectives = "Bob ile konuş." } }
Check(QL.UseTurkish(), "Turkish on")
Eq(QL.L("Chain"), "Zincir", "Turkish string")
Eq(QL.L("Some untranslated text"), "Some untranslated text", "missing key falls back")
Eq(QL.QuestTitle(1), "İlk Adımlar", "title from WoWTR")
Eq(QL.QuestObjectives(1), "Bob ile konuş.", "objectives from WoWTR")
Eq(QL.QuestTitle(2), "Second Steps", "untranslated quest keeps its English title")
Eq(QL.L("Quest #%d"):format(5), "Görev #5", "format string")
Check(QL.FontPath():find("WoWTR", 1, true), "WoWTR font for Turkish letters")

-- back to English with WoWTR still loaded
QL.Set("lang", "en")
Eq(QL.QuestTitle(1), "First Steps", "English again")

print("locale: ok")
