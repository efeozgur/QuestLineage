-- The character's quest state for Chain.lua: what is done, what is in the log (and complete),
-- level, race and class. Read from the client, cached until the quest log changes.
-- A context is a plain table, so tests build their own:
--   { level = n, raceFlag = bit, classFlag = bit,
--     done = { [id] = true }, log = { [id] = true }, complete = { [id] = true } }

local _, QL = ...

local cache

local function call(fn, ...)
	if not fn then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
	return nil
end

-- 2^(id-1): the bit QuestieDB's race and class masks use for that id.
local function flag(id)
	if type(id) ~= "number" or id < 1 then return nil end
	return 2 ^ (id - 1)
end

local function scanLog(log, complete)
	local Q = C_QuestLog
	if Q and Q.GetNumQuestLogEntries and Q.GetInfo then
		local n = call(Q.GetNumQuestLogEntries) or 0
		for i = 1, n do
			local info = call(Q.GetInfo, i)
			if type(info) == "table" and not info.isHeader and info.questID and info.questID > 0 then
				log[info.questID] = true
				local isComplete = call(Q.IsComplete, info.questID)
				if isComplete then complete[info.questID] = true end
			end
		end
		return
	end
	if GetNumQuestLogEntries and GetQuestLogTitle then
		local n = call(GetNumQuestLogEntries) or 0
		for i = 1, n do
			local _, _, _, isHeader, _, isComplete, _, questId = call(GetQuestLogTitle, i)
			if not isHeader and type(questId) == "number" and questId > 0 then
				log[questId] = true
				if isComplete == 1 or isComplete == true then complete[questId] = true end
			end
		end
	end
end

-- done is asked per quest and remembered (the client has no "all completed" list here).
local function doneTable()
	return setmetatable({}, {
		__index = function(t, id)
			local v = false
			if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
				v = call(C_QuestLog.IsQuestFlaggedCompleted, id) and true or false
			elseif IsQuestFlaggedCompleted then
				v = call(IsQuestFlaggedCompleted, id) and true or false
			end
			rawset(t, id, v)
			return v
		end,
	})
end

function QL.Context()
	if cache then return cache end
	local _, _, raceId = call(UnitRace, "player")
	local _, _, classId = call(UnitClass, "player")
	local ctx = {
		level = call(UnitLevel, "player") or 1,
		raceFlag = flag(raceId),
		classFlag = flag(classId),
		done = doneTable(),
		log = {},
		complete = {},
	}
	scanLog(ctx.log, ctx.complete)
	cache = ctx
	return ctx
end

function QL.ResetContext()
	cache = nil
	QL.Fire("STATE_CHANGED")
end

for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }) do
	QL.Event(e, function() cache = nil; QL.Fire("STATE_CHANGED") end)
end
