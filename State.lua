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

-- Abandoning a quest ----------------------------------------------------------------------------------

-- The quest's line in the quest log, or nil.
function QL.QuestLogIndex(id)
	local Q = C_QuestLog
	local i = Q and call(Q.GetLogIndexForQuestID, id)
	if type(i) == "number" and i > 0 then return i end
	i = call(GetQuestLogIndexByID, id)
	if type(i) == "number" and i > 0 then return i end
	if GetNumQuestLogEntries and GetQuestLogTitle then
		for n = 1, call(GetNumQuestLogEntries) or 0 do
			local _, _, _, isHeader, _, _, _, questId = call(GetQuestLogTitle, n)
			if not isHeader and questId == id then return n end
		end
	end
	return nil
end

-- Drops a quest from the log (the quest log's own Abandon, without its confirmation: callers ask
-- with QL.ConfirmAbandon). The classic calls first (select the line, mark it, abandon), as
-- Questie does on this client; else C_QuestLog's. true when the client took it.
function QL.AbandonQuest(id)
	id = tonumber(id)
	if not id then return false end
	local index = QL.QuestLogIndex(id)
	if index and SelectQuestLogEntry and SetAbandonQuest and AbandonQuest then
		local before = call(GetQuestLogSelection)
		call(SelectQuestLogEntry, index)
		call(SetAbandonQuest)
		call(AbandonQuest)
		if type(before) == "number" and before > 0 and before ~= index then call(SelectQuestLogEntry, before) end
	else
		local Q = C_QuestLog
		if not (Q and Q.SetSelectedQuest and Q.SetAbandonQuest and Q.AbandonQuest) then return false end
		call(Q.SetSelectedQuest, id)
		call(Q.SetAbandonQuest)
		call(Q.AbandonQuest)
	end
	-- the arrow and the window let go of it at once
	if QL.ArrowQuest and QL.ArrowQuest() == id and QL.ClearArrow then QL.ClearArrow() end
	QL.Print(QL.L("Quest abandoned: ") .. QL.QuestTitle(id), "info")
	QL.Fire("QUEST_ABANDONED", id)
	return true
end

-- Asks first (the theme's own dialog; it reads Turkish where the game's popups may not).
function QL.ConfirmAbandon(id)
	id = tonumber(id)
	if not id then return end
	local L = QL.L
	QL.Theme.Confirm(L("Abandon quest?"),
		L("%s leaves your quest log; what you collected for it may be lost. You can take it again from its giver."):format(QL.Theme.Hex(QL.Theme.C.text) .. QL.QuestTitle(id) .. "|r"),
		L("Abandon"), function() QL.AbandonQuest(id) end)
end

-- The context is dropped at once on every quest-log event, but STATE_CHANGED (which makes plates,
-- the current quest window, quest areas, routes and the window recompute) fires once per burst:
-- QUEST_LOG_UPDATE comes several times a second in combat (every kill and loot), and each one
-- used to redo all of it. Rare events (accepted, turned in, removed, level up) fire at once.
local pending = false
local function fireState()
	pending = false
	QL.Fire("STATE_CHANGED")
end
QL.Event("QUEST_LOG_UPDATE", function()
	cache = nil
	if pending then return end
	if C_Timer and C_Timer.After then
		pending = true
		C_Timer.After(0.15, fireState)
	else
		fireState()
	end
end)
for _, e in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED" }) do
	QL.Event(e, function() cache = nil; QL.Fire("STATE_CHANGED") end)
end
