-- Quest data from QuestieDB, through its public API only (LibQuestieDB, contract 4):
--   LibQuestieDB.Quest.Get(id, field), LibQuestieDB.Quest.GetAllIds(), the same for Npc/Object/Item.
-- QuestieDB's files are never read or changed. Every read is pcall-guarded: a row that fails to
-- decode reads as nil instead of breaking the window.
--
-- The reverse index (which quests need this one, its breadcrumbs' targets) needs one pass over
-- every quest. It is built once per session, a slice per frame, the first time it is asked for.

local _, QL = ...

local CONTRACT = 4
local PER_FRAME = 300

local lib, libState, libReason

local function resolve()
	if libState then return lib end
	local l = _G.LibQuestieDB
	if type(l) ~= "table" or type(l.Quest) ~= "table" then
		libState = "absent"
		return nil
	end
	if l.RequireContract then
		local ok, good, msg = pcall(l.RequireContract, CONTRACT)
		if not ok or not good then
			libState, libReason = "incompatible", ok and msg or good
			return nil
		end
	end
	lib, libState = l, "ok"
	return lib
end

-- "ok" | "absent" | "incompatible", reason
function QL.DataStatus()
	resolve()
	return libState, libReason
end

-- For tests: forget the cached library and index.
function QL.ResetData()
	lib, libState, libReason = nil, nil, nil
	QL.index = nil
	QL.indexing = nil
	if QL.ResetZones then QL.ResetZones() end
end

local function get(entity, id, field)
	local l = resolve()
	local e = l and l[entity]
	if not e or type(id) ~= "number" then return nil end
	local ok, v = pcall(e.Get, id, field)
	if ok then return v end
	return nil
end

function QL.Q(id, field) return get("Quest", id, field) end
function QL.N(id, field) return get("Npc", id, field) end
function QL.O(id, field) return get("Object", id, field) end
function QL.I(id, field) return get("Item", id, field) end

-- A list field as a plain list of positive ids (QuestieDB returns nil, a number or a list).
function QL.Ids(value)
	local out = {}
	if type(value) == "number" then
		if value > 0 then out[1] = value end
	elseif type(value) == "table" then
		for _, v in ipairs(value) do
			if type(v) == "number" and v > 0 then out[#out + 1] = v end
		end
	end
	return out
end

function QL.QuestExists(id)
	return type(QL.Q(id, "name")) == "string"
end

-- Reverse index -------------------------------------------------------------
-- index.dependents[p] = { {id, kind}, ... }   quests that need p (kind: all | any | parent)
-- index.names = { {id, lowercase name}, ... }  for the search box

local function newIndex()
	return { dependents = {}, names = {}, byZone = {} }
end

-- index.byZone[area] = quest ids: the quest's own zone, and the zones its givers stand in
-- (subzones folded into their zone by QL.TopArea, Zone.lua).
local function indexZones(index, id)
	local seen = {}
	local function add(area)
		area = QL.TopArea and QL.TopArea(area) or area
		if type(area) ~= "number" or area <= 0 or seen[area] then return end
		seen[area] = true
		local list = index.byZone[area]
		if not list then list = {}; index.byZone[area] = list end
		list[#list + 1] = id
	end
	add(QL.Q(id, "zoneOrSort"))
	local by = QL.Q(id, "startedBy")
	if type(by) == "table" then
		for _, npc in ipairs(QL.Ids(by[1])) do add(QL.N(npc, "zoneID")) end
		for _, obj in ipairs(QL.Ids(by[2])) do add(QL.O(obj, "zoneID")) end
	end
end

local function indexOne(index, id)
	local name = QL.Q(id, "name")
	if type(name) ~= "string" then return end
	index.names[#index.names + 1] = { id, name:lower() }
	indexZones(index, id)
	local dep = index.dependents
	local function add(p, kind)
		local list = dep[p]
		if not list then list = {}; dep[p] = list end
		list[#list + 1] = { id, kind }
	end
	for _, p in ipairs(QL.Ids(QL.Q(id, "preQuestGroup"))) do add(p, "all") end
	for _, p in ipairs(QL.Ids(QL.Q(id, "preQuestSingle"))) do add(p, "any") end
	for _, p in ipairs(QL.Ids(QL.Q(id, "parentQuest"))) do add(p, "parent") end
end

local readyCallbacks = {}

local function finish(index)
	QL.index = index
	QL.indexing = nil
	local list = readyCallbacks
	readyCallbacks = {}
	for _, fn in ipairs(list) do pcall(fn) end
	QL.Fire("INDEX_READY")
end

function QL.IndexReady()
	return QL.index ~= nil
end

-- Builds the whole index at once (tests, or when there is no frame to slice on).
function QL.BuildIndexNow()
	local l = resolve()
	local index = newIndex()
	if l then
		local ok, ids = pcall(l.Quest.GetAllIds)
		if ok and type(ids) == "table" then
			for _, id in ipairs(ids) do indexOne(index, id) end
		end
	end
	finish(index)
	return index
end

-- Starts the sliced build if needed; fn (optional) runs once the index is ready.
function QL.WhenIndexed(fn)
	if QL.index then
		if fn then fn() end
		return
	end
	if fn then readyCallbacks[#readyCallbacks + 1] = fn end
	if QL.indexing then return end
	local l = resolve()
	if not l or not CreateFrame then
		QL.BuildIndexNow()
		return
	end
	local ok, ids = pcall(l.Quest.GetAllIds)
	if not ok or type(ids) ~= "table" then
		QL.BuildIndexNow()
		return
	end
	QL.indexing = true
	local index, pos = newIndex(), 1
	local f = CreateFrame("Frame")
	f:SetScript("OnUpdate", function(self)
		local last = math.min(pos + PER_FRAME - 1, #ids)
		for i = pos, last do
			local good, err = pcall(indexOne, index, ids[i])
			if not good then QL.Debug("index " .. tostring(ids[i]) .. ": " .. tostring(err)) end
		end
		pos = last + 1
		if pos > #ids then
			self:SetScript("OnUpdate", nil)
			finish(index)
		end
	end)
end

function QL.Dependents(id)
	local index = QL.index
	return index and index.dependents[id] or {}
end

-- Search by id or by a part of the name. -> list of ids, best first (max 20)
function QL.SearchQuests(text)
	text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local id = tonumber(text)
	if id then
		return QL.QuestExists(id) and { id } or {}
	end
	if text == "" or not QL.index then return {} end
	local needle = text:lower()
	local exact, starts, inside = {}, {}, {}
	for _, row in ipairs(QL.index.names) do
		local name = row[2]
		if name == needle then exact[#exact + 1] = row[1]
		elseif name:sub(1, #needle) == needle then starts[#starts + 1] = row[1]
		elseif name:find(needle, 1, true) then inside[#inside + 1] = row[1] end
	end
	local out = {}
	for _, list in ipairs({ exact, starts, inside }) do
		table.sort(list)
		for _, v in ipairs(list) do
			if #out >= 20 then return out end
			out[#out + 1] = v
		end
	end
	return out
end

-- The first NPC (or object) that starts / ends a quest, by name.
local function starterName(field, questId)
	local by = QL.Q(questId, field)
	if type(by) ~= "table" then return nil end
	for _, npc in ipairs(QL.Ids(by[1])) do
		local n = QL.N(npc, "name")
		if type(n) == "string" then return n end
	end
	for _, obj in ipairs(QL.Ids(by[2])) do
		local n = QL.O(obj, "name")
		if type(n) == "string" then return n end
	end
	if field == "startedBy" then
		for _, item in ipairs(QL.Ids(by[3])) do
			local n = QL.I(item, "name")
			if type(n) == "string" then return n end
		end
	end
	return nil
end

function QL.QuestGiver(questId) return starterName("startedBy", questId) end
function QL.QuestEnder(questId) return starterName("finishedBy", questId) end

function QL.QuestLevel(questId)
	local lvl = QL.Q(questId, "questLevel")
	if type(lvl) == "number" and lvl > 0 then return lvl end
	lvl = QL.Q(questId, "requiredLevel")
	if type(lvl) == "number" and lvl > 0 then return lvl end
	return nil
end

QL.Event("PLAYER_LOGIN", function()
	-- Build in the background shortly after login, so the first tooltip already knows chains.
	if C_Timer and C_Timer.After then
		C_Timer.After(5, function() QL.WhenIndexed() end)
	end
end)
