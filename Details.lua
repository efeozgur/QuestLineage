-- Everything the detail panel says about one quest, gathered from QuestieDB, its support data,
-- WoWTR and (for quests in the log) the client. No frames here.
--
--   QL.QuestXP(id) -> xp | nil                QuestieDB support "QuestXP": db[id] = {level, xp}
--   QL.QuestReputation(id) -> { {factionId, value, name}, ... }
--   QL.QuestTasks(id) -> { {kind = npc|object|item|rep, id, name, text, npc}, ... }  from the DB
--   QL.LiveObjectives(id) -> { {text, have, need, done}, ... } | nil   quest in the log only
--   QL.QuestPlace(kind, id) -> zoneName, x, y   kind "npc" | "object": its first spawn
--   QL.QuestStarter(id) / QL.QuestFinisher(id) -> { kind, id, name } | nil
--   QL.RewardItems(id) -> item ids             reverse of the items' questRewards (Data.lua index)
--   QL.QuestDescription(id) -> text | nil      WoWTR (Turkish), else the client for a logged quest
--   QL.ItemIcon(id), QL.ItemQuality(id), QL.AreaName(area)

local _, QL = ...

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
	return nil
end

local function support(name)
	local lib = _G.LibQuestieDB
	local s = lib and lib.Support
	if not (s and s.Get) then return nil end
	local m = call(s.Get, name)
	return type(m) == "table" and m or nil
end

function QL.QuestXP(id)
	local m = support("QuestXP")
	local row = m and type(m.db) == "table" and m.db[id]
	if type(row) == "table" and type(row[2]) == "number" and row[2] > 0 then return row[2] end
	return nil
end

function QL.FactionName(factionId)
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local data = call(C_Reputation.GetFactionDataByID, factionId)
		if type(data) == "table" and data.name then return data.name end
	end
	if GetFactionInfoByID then
		local name = call(GetFactionInfoByID, factionId)
		if type(name) == "string" and name ~= "" then return name end
	end
	return nil
end

function QL.QuestReputation(id)
	local out = {}
	local rep = QL.Q(id, "reputationReward")
	if type(rep) ~= "table" then return out end
	for _, pair in ipairs(rep) do
		if type(pair) == "table" and type(pair[1]) == "number" and type(pair[2]) == "number" and pair[2] ~= 0 then
			out[#out + 1] = { pair[1], pair[2], QL.FactionName(pair[1]) }
		end
	end
	return out
end

function QL.AreaName(area)
	if type(area) ~= "number" then return nil end
	if C_Map and C_Map.GetAreaInfo then
		local name = call(C_Map.GetAreaInfo, area)
		if type(name) == "string" and name ~= "" then return name end
	end
	return nil
end

function QL.ItemIcon(itemId)
	if C_Item and C_Item.GetItemIconByID then
		local icon = call(C_Item.GetItemIconByID, itemId)
		if icon then return icon end
	end
	if GetItemIcon then return call(GetItemIcon, itemId) end
	return nil
end

function QL.ItemQuality(itemId)
	if C_Item and C_Item.GetItemQualityByID then
		local q = call(C_Item.GetItemQualityByID, itemId)
		if type(q) == "number" then return q end
	end
	if GetItemInfo then
		local _, _, q = call(GetItemInfo, itemId)
		if type(q) == "number" then return q end
	end
	return nil
end

-- The first spawn of an NPC or object: zone name and map percentages.
-- A spawn in the player's zone wins, so a giver who also stands elsewhere shows the near one.
function QL.QuestPlace(kind, id)
	local spawns = kind == "npc" and QL.N(id, "spawns") or (kind == "object" and QL.O(id, "spawns"))
	if type(spawns) ~= "table" then return nil end
	local here = QL.PlayerZone and QL.PlayerZone()
	local bestArea, bestPoint
	for area, points in pairs(spawns) do
		if type(points) == "table" and type(points[1]) == "table" then
			local top = QL.TopArea and QL.TopArea(area) or area
			if not bestArea or (here and top == here) then
				bestArea, bestPoint = area, points[1]
				if here and top == here then break end
			end
		end
	end
	if not bestArea then return nil end
	local name = QL.AreaName(bestArea) or QL.AreaName(QL.TopArea and QL.TopArea(bestArea) or bestArea)
	return name, bestPoint[1], bestPoint[2]
end

local function firstOf(by, slot, kind, get)
	if type(by) ~= "table" then return nil end
	for _, id in ipairs(QL.Ids(by[slot])) do
		local name = get(id, "name")
		if type(name) == "string" then return { kind = kind, id = id, name = name } end
	end
	return nil
end

local function person(field, id)
	local by = QL.Q(id, field)
	return firstOf(by, 1, "npc", QL.N) or firstOf(by, 2, "object", QL.O) or (field == "startedBy" and firstOf(by, 3, "item", QL.I)) or nil
end
function QL.QuestStarter(id) return person("startedBy", id) end
function QL.QuestFinisher(id) return person("finishedBy", id) end

-- Objectives from the database: {creatures, objects, items, reputation, killCredit, spell}.
function QL.QuestTasks(id)
	local out = {}
	local obj = QL.Q(id, "objectives")
	if type(obj) ~= "table" then return out end
	local function list(slot, kind, get)
		if type(obj[slot]) ~= "table" then return end
		for _, entry in ipairs(obj[slot]) do
			local oid = type(entry) == "table" and entry[1] or entry
			if type(oid) == "number" then
				local name = get(oid, "name")
				out[#out + 1] = {
					kind = kind, id = oid,
					name = type(name) == "string" and name or nil,
					text = type(entry) == "table" and type(entry[2]) == "string" and entry[2] or nil,
					npc = kind == "npc" and oid or nil,
				}
			end
		end
	end
	list(1, "npc", QL.N)
	list(2, "object", QL.O)
	list(3, "item", QL.I)
	-- kill credit: { {npcIds}, baseNpc, text }
	if type(obj[5]) == "table" then
		for _, kc in ipairs(obj[5]) do
			if type(kc) == "table" and type(kc[2]) == "number" then
				local name = QL.N(kc[2], "name")
				out[#out + 1] = { kind = "npc", id = kc[2], npc = kc[2], name = type(name) == "string" and name or nil, text = type(kc[3]) == "string" and kc[3] or nil }
			end
		end
	end
	if type(obj[4]) == "table" and type(obj[4][1]) == "number" then
		out[#out + 1] = { kind = "rep", id = obj[4][1], name = QL.FactionName(obj[4][1]), value = obj[4][2] }
	end
	-- an item that drops from a creature: show the creature as the picture
	for _, t in ipairs(out) do
		if t.kind == "item" then
			local drops = QL.Ids(QL.I(t.id, "npcDrops"))
			t.npc = drops[1]
		end
	end
	return out
end

function QL.LiveObjectives(id)
	local ctx = QL.Context and QL.Context()
	if not ctx or not ctx.log[id] then return nil end
	if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
	local list = call(C_QuestLog.GetQuestObjectives, id)
	if type(list) ~= "table" or #list == 0 then return nil end
	local out = {}
	for _, o in ipairs(list) do
		if type(o) == "table" then
			out[#out + 1] = { text = o.text or "", have = o.numFulfilled or 0, need = o.numRequired or 0, done = o.finished and true or false }
		end
	end
	return out
end

function QL.RewardItems(id)
	local index = QL.index
	return index and index.rewards and index.rewards[id] or {}
end

-- The quest's story text. WoWTR has it for every translated quest (Turkish); otherwise the
-- client only knows it for quests in the log, read without leaving the log's selection changed.
function QL.QuestDescription(id)
	if QL.UseTurkish() then
		local row = QTR_QuestData[tostring(id)]
		if type(row) == "table" and type(row.Description) == "string" and row.Description ~= "" then
			return (row.Description:gsub("%$[Bb]", "\n"))
		end
	end
	local ctx = QL.Context and QL.Context()
	if not ctx or not ctx.log[id] then return nil end
	if C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.SetSelectedQuest and GetQuestLogQuestText then
		local before = call(C_QuestLog.GetSelectedQuest)
		call(C_QuestLog.SetSelectedQuest, id)
		local text = call(GetQuestLogQuestText)
		if before then call(C_QuestLog.SetSelectedQuest, before) end
		if type(text) == "string" and text ~= "" then return text end
	end
	return nil
end
