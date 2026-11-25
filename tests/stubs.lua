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

local QUESTS = {
	[1] = { name = "First Steps", questLevel = 2, requiredLevel = 1, nextQuestInChain = 2, startedBy = { { 100 } }, finishedBy = { { 101 } }, objectivesText = { "Talk to Bob." } },
	[2] = { name = "Second Steps", questLevel = 3, requiredLevel = 2, preQuestSingle = { 1 } },
	[3] = { name = "The Gathering", questLevel = 5, requiredLevel = 4, preQuestGroup = { 2, 4 } },
	[4] = { name = "Side Road", questLevel = 6, requiredLevel = 6, breadcrumbs = { 5 } },
	[5] = { name = "Rumours", questLevel = 4, requiredLevel = 1, breadcrumbForQuestId = 4 },
	[6] = { name = "Left Path", questLevel = 7, requiredLevel = 5, preQuestGroup = { 3 }, exclusiveTo = { 7 } },
	[7] = { name = "Right Path", questLevel = 7, requiredLevel = 5, preQuestGroup = { 3 }, exclusiveTo = { 6 } },
	[8] = { name = "Horde Only", questLevel = 7, requiredLevel = 5, preQuestGroup = { 3 }, requiredRaces = 2 },
	[9] = { name = "While You Are There", questLevel = 6, requiredLevel = 5, parentQuest = 3 },
	[10] = { name = "Lonely Quest", questLevel = 10, requiredLevel = 8 },
	[11] = { name = "Loop A", questLevel = 10, nextQuestInChain = 12, preQuestSingle = { 12 } },
	[12] = { name = "Loop B", questLevel = 10, preQuestSingle = { 11 } },
}
local NPCS = {
	[100] = { name = "Bob", questStarts = { 1 } },
	[101] = { name = "Alice", questStarts = { 2, 10 } },
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
	Object = entity({}),
	Item = entity({}),
}

QuestLineageDB = nil
QTR_QuestData = nil

local QL = {}
for _, file in ipairs({ "Core.lua", "Locale.lua", "Data.lua", "State.lua", "Chain.lua" }) do
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
