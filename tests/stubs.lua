-- A fake LibQuestieDB with a small quest web, and a loader for the addon's logic files.
-- Usage (from the repo root):  local QL = dofile('tests/stubs.lua')
--
-- The web (Human = race 1, Orc = race 2):
--   5 --breadcrumb--> 4
--   1 --next--> 2 (2 needs any of {1})
--   2, 4 --all--> 3
--   3 --all--> 6, 7 (6 and 7 exclusive to each other)
--   3 --all--> 8 (Orc only)
--   3 --parent--> 9 (must be on 3)
--   11 <-> 12 (a cycle) ; 10 stands alone
--   14 --any--> 15 (in Mulgore = area 215; 14 in its subzone 220)
-- Zones: 1-12 are in Durotar (area 14, uiMap 1411); 1 by its giver Bob's zone, not its own field.

local QUESTS = {
	[1] = { name = "First Steps", questLevel = 2, requiredLevel = 1, nextQuestInChain = 2, startedBy = { { 100 } }, finishedBy = { { 101 } }, objectivesText = { "Talk to Bob." } },
	[2] = { zoneOrSort = 14, name = "Second Steps", questLevel = 3, requiredLevel = 2, preQuestSingle = { 1 } },
	[3] = { zoneOrSort = 14, name = "The Gathering", questLevel = 5, requiredLevel = 4, preQuestGroup = { 2, 4 },
		startedBy = { { 100 } }, finishedBy = { { 101 } }, objectivesText = { "Question Bob and bring ribs." },
		objectives = { { { 100, "Bob questioned" } }, nil, { { 501 } } }, reputationReward = { { 76, 250 } } },
	[4] = { zoneOrSort = 14, name = "Side Road", questLevel = 6, requiredLevel = 6, breadcrumbs = { 5 } },
	[5] = { zoneOrSort = 14, name = "Rumours", questLevel = 4, requiredLevel = 1, breadcrumbForQuestId = 4 },
	[6] = { zoneOrSort = 14, name = "Left Path", questLevel = 7, requiredLevel = 5, preQuestGroup = { 3 }, exclusiveTo = { 7 } },
	[7] = { zoneOrSort = 14, name = "Right Path", questLevel = 7, requiredLevel = 5, preQuestGroup = { 3 }, exclusiveTo = { 6 } },
	[8] = { zoneOrSort = 14, name = "Horde Only", questLevel = 7, requiredLevel = 5, preQuestGroup = { 3 }, requiredRaces = 2 },
	[9] = { zoneOrSort = 14, name = "While You Are There", questLevel = 6, requiredLevel = 5, parentQuest = 3 },
	[10] = { zoneOrSort = 14, name = "Lonely Quest", questLevel = 10, requiredLevel = 8 },
	[11] = { zoneOrSort = 14, name = "Loop A", questLevel = 10, nextQuestInChain = 12, preQuestSingle = { 12 } },
	[12] = { zoneOrSort = 14, name = "Loop B", questLevel = 10, preQuestSingle = { 11 } },
	[14] = { zoneOrSort = 220, name = "Plains Hunt", questLevel = 4, requiredLevel = 1 },
	[20] = { zoneOrSort = 1637, name = "Warrior's Trial", questLevel = 10, requiredLevel = 10, requiredClasses = 1 },
	[21] = { zoneOrSort = 1637, name = "Warrior's Reward", questLevel = 10, requiredLevel = 10, requiredClasses = 1, preQuestSingle = { 20 } },
	[22] = { zoneOrSort = 1637, name = "Shield Lesson", questLevel = 4, requiredLevel = 4, requiredClasses = 1 },
	[23] = { zoneOrSort = 1637, name = "Arcane Study", questLevel = 4, requiredLevel = 4, requiredClasses = 128 },
	[25] = { zoneOrSort = 1581, name = "Into the Mines", questLevel = 18, requiredLevel = 14 },
	[26] = { zoneOrSort = 1637, name = "Captain's Orders", questLevel = 20, requiredLevel = 16, objectives = { { { 103 } } } },
	[24] = { zoneOrSort = 1637, name = "Every Class", questLevel = 4, requiredLevel = 4, requiredClasses = 1535 },
	[15] = { zoneOrSort = 215, name = "Plains Feast", questLevel = 6, requiredLevel = 3, preQuestSingle = { 14 } },
}
local NPCS = {
	[100] = { name = "Bob", questStarts = { 1 }, zoneID = 14, spawns = { [14] = { { 45.2, 63.1 } } } },
	[101] = { name = "Alice", questStarts = { 2, 10 }, spawns = { [215] = { { 10, 10 } }, [14] = { { 50, 50 } } } },
	[102] = { name = "Boar", zoneID = 14 },
	[103] = { name = "Pirate Captain", zoneID = 10029 },
	-- service NPCs in Durotar (area 14); the player stands at 50, 40 in the UI tests
	[200] = { name = "Grezz", subName = "Armorer", npcFlags = 4 + 16384, friendlyToFaction = "H", spawns = { [14] = { { 52, 40 } } } },
	[201] = { name = "Far Smith", subName = "Weaponsmith", npcFlags = 4 + 16384, friendlyToFaction = "H", spawns = { [14] = { { 80, 80 } } } },
	[202] = { name = "Alliance Smith", subName = "Armorer", npcFlags = 4 + 16384, friendlyToFaction = "A", spawns = { [14] = { { 50, 41 } } } },
	[203] = { name = "Thrag", subName = "Warrior Trainer", npcFlags = 16, friendlyToFaction = "H", spawns = { [14] = { { 60, 40 } } } },
	[204] = { name = "Ore Teacher", subName = "Mining Trainer", npcFlags = 16, friendlyToFaction = "AH", spawns = { [14] = { { 55, 45 } } } },
	[205] = { name = "Innkeeper Grosk", subName = "Innkeeper", npcFlags = 4 + 128, friendlyToFaction = "H", spawns = { [14] = { { 51, 42 } } } },
	[206] = { name = "Raging Boar", friendlyToFaction = nil, npcFlags = 0, spawns = { [14] = { { 50, 40 } } } },
	[207] = { name = "Plains Boar", spawns = { [215] = { { 30, 30 }, { 31, 31 } } } },
}

local function entity(rows)
	return {
		Get = function(id, field)
			local row = rows[id]
			if not row then return nil end
			if field == "Bad" then error("decode failed") end
			return row[field]
		end,
		GetAllIds = function()
			local ids = {}
			for id in pairs(rows) do ids[#ids + 1] = id end
			table.sort(ids)
			return ids
		end,
	}
end

LibQuestieDB = {
	contractVersion = 4,
	RequireContract = function(v) return v <= 4, v > 4 and "too new" or nil end,
	Quest = entity(QUESTS),
	Npc = entity(NPCS),
	Object = entity({
		[300] = { name = "Mailbox", spawns = { [14] = { { 53, 40 } } } },
		[301] = { name = "Crate", spawns = { [14] = { { 50, 40 } } } },
	}),
	Item = entity({
		[500] = { name = "Rusty Sword", questRewards = { 3 } },
		[501] = { name = "Boar Ribs", npcDrops = { 102 } },
	}),
	Support = {
		Get = function(name)
			if name == "QuestXP" then return { db = { [3] = { 5, 450 }, [5] = { 4, 220 } } } end
			if name ~= "ZoneDB" then return nil end
			return { private = {
				uiMapIdToAreaId = "return { [1411] = 14, [1412] = 215 }",
				uiMapIdToAreaIdOverride = "return { [1414] = 10073 }",
				subZoneToParentZone = "return { [220] = 215 }",
				dungeons = { [1581] = { "The Deadmines", { 10029 }, 40, {} }, [2717] = { "Molten Core", nil, 51, {} } },
				areaIdToUiMapId = "return { [14] = 1411, [215] = 1412 }",
			} }
		end,
	},
}

QuestLineageDB = nil
QTR_QuestData = nil

local QL = {}
for _, file in ipairs({ "Core.lua", "Locale.lua", "Data.lua", "Zone.lua", "State.lua", "Chain.lua", "Details.lua", "Nav.lua", "Services.lua" }) do
	assert(loadfile(file))("QuestLineage", QL)
end
QL.QUESTS = QUESTS

-- A human character's context.
function QL.TestContext(over)
	local ctx = { level = 5, raceFlag = 1, classFlag = 1, done = {}, log = {}, complete = {} }
	for k, v in pairs(over or {}) do ctx[k] = v end
	return ctx
end

function QL.Check(cond, msg)
	if not cond then error("FAIL: " .. msg, 2) end
end

function QL.Eq(a, b, msg)
	if a ~= b then error(("FAIL: %s (expected %s, got %s)"):format(msg, tostring(b), tostring(a)), 2) end
end

return QL
