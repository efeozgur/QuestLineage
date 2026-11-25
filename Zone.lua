-- Zones: which zone the player is in, and the quest chains that belong to a zone.
--
-- QuestieDB keeps zones as AreaTable ids; the client gives a uiMapID. The mapping comes from
-- QuestieDB's support data (LibQuestieDB.Support.Get("ZoneDB").private: uiMapIdToAreaId,
-- subZoneToParentZone, each with an Override), stored as Lua source strings ("return {...}").
-- Subzones are folded into their parent zone, so "Valley of Trials" counts as Durotar.
--
--   QL.PlayerZone() -> area, uiMapId, name
--   QL.TopArea(area) -> the zone a subzone belongs to
--   QL.ZoneChains(area, ctx) -> { { head, ids, minLevel, maxLevel, size }, ... } (cached)
--   QL.ChainProgress(entry, ctx) -> { done, inLog, total, state, focus }

local _, QL = ...

local maps

local function asTable(v)
	if type(v) == "table" then return v end
	if type(v) == "string" and loadstring then
		local fn = loadstring(v)
		if fn then
			local ok, t = pcall(fn)
			if ok and type(t) == "table" then return t end
		end
	end
	return {}
end

local function zoneData()
	if maps then return maps end
	maps = { ui = {}, parent = {}, area = {} }
	local lib = _G.LibQuestieDB
	local support = lib and lib.Support
	local zoneDB
	if support and support.Get then
		local ok, m = pcall(support.Get, "ZoneDB")
		if ok then zoneDB = m end
	end
	local private = type(zoneDB) == "table" and zoneDB.private or {}
	for _, key in ipairs({ "uiMapIdToAreaId", "uiMapIdToAreaIdOverride" }) do
		for k, v in pairs(asTable(private[key])) do maps.ui[k] = v end
	end
	for _, key in ipairs({ "subZoneToParentZone", "subZoneToParentZoneOverride" }) do
		for k, v in pairs(asTable(private[key])) do maps.parent[k] = v end
	end
	for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
		for k, v in pairs(asTable(private[key])) do maps.area[k] = v end
	end
	return maps
end

function QL.ResetZones()
	maps = nil
	QL.zoneChainCache = {}
end

-- The uiMapID a spawn's area is drawn on: the area's own map, else its zone's.
function QL.AreaUiMap(area)
	if type(area) ~= "number" then return nil end
	local m = zoneData().area
	return m[area] or m[QL.TopArea(area) or area]
end

function QL.TopArea(area)
	if type(area) ~= "number" or area <= 0 then return nil end
	local parent = zoneData().parent
	for _ = 1, 5 do
		local p = parent[area]
		if not p or p == area then break end
		area = p
	end
	return area
end

local function mapInfo(uiMap)
	if not (C_Map and C_Map.GetMapInfo) then return nil end
	local ok, info = pcall(C_Map.GetMapInfo, uiMap)
	if ok and type(info) == "table" then return info end
	return nil
end

-- A uiMapID's zone area: the mapping, else the nearest parent map that has one.
function QL.AreaForMap(uiMap)
	local ui = zoneData().ui
	for _ = 1, 5 do
		if type(uiMap) ~= "number" then return nil end
		local area = ui[uiMap]
		if area then return QL.TopArea(area) end
		local info = mapInfo(uiMap)
		uiMap = info and info.parentMapID
		if uiMap == 0 then return nil end
	end
	return nil
end

function QL.PlayerZone()
	local uiMap
	if C_Map and C_Map.GetBestMapForUnit then
		local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
		if ok then uiMap = m end
	end
	local area = uiMap and QL.AreaForMap(uiMap)
	local info = uiMap and mapInfo(uiMap)
	local name = info and info.name
	if (not name or name == "") and GetZoneText then
		local ok, z = pcall(GetZoneText)
		if ok then name = z end
	end
	return area, uiMap, name
end

-- Zone chains ------------------------------------------------------------------

QL.zoneChainCache = {}
QL.On("INDEX_READY", function() QL.zoneChainCache = {} end)
QL.On("SETTING_CHANGED", function(key) if key == "hideOther" then QL.zoneChainCache = {} end end)

function QL.ZoneQuests(area)
	local index = QL.index
	return index and index.byZone[area] or {}
end

-- The chains with at least one quest in the zone, each once. The grouping is cached per zone
-- (it only depends on the data and the character's race/class); progress is computed apart.
-- Group quests into chains, each once: the first quest not yet placed starts a chain and every
-- quest it reaches is placed. inSet marks the quests the list is about (a zone's, a class's):
-- the head is one of them when it can be. keepSingles keeps one-quest "chains" too.
--   -> { { head, ids (by generation), minLevel, maxLevel, size, generations }, ... }
function QL.GroupChains(questIds, ctx, keepSingles)
	local hide = QL.DB().hideOther
	local quests, inSet = {}, {}
	for _, id in ipairs(questIds) do
		if not inSet[id] and (not hide or QL.Eligible(id, ctx)) then
			quests[#quests + 1] = id
			inSet[id] = true
		end
	end
	table.sort(quests, function(a, b)
		local la, lb = QL.QuestLevel(a) or 0, QL.QuestLevel(b) or 0
		if la ~= lb then return la < lb end
		return a < b
	end)
	local assigned, list = {}, {}
	for _, q in ipairs(quests) do
		if not assigned[q] then
			local chain = QL.BuildChain(q, ctx)
			if chain then
				for _, id in ipairs(chain.order) do assigned[id] = true end
				if chain.total >= 2 or keepSingles then
					-- head: a first-generation quest, one of the set's if there is one
					local head
					for _, id in ipairs(chain.layers[1]) do
						if inSet[id] and (not head or (QL.QuestLevel(id) or 0) < (QL.QuestLevel(head) or 0)) then head = id end
					end
					head = head or chain.layers[1][1]
					local lo, hi
					local ids = {}
					for _, id in ipairs(chain.order) do
						ids[#ids + 1] = id
						local l = QL.QuestLevel(id)
						if l then
							if not lo or l < lo then lo = l end
							if not hi or l > hi then hi = l end
						end
					end
					table.sort(ids, function(a, b)
						local na, nb = chain.nodes[a], chain.nodes[b]
						if na.layer ~= nb.layer then return na.layer < nb.layer end
						return na.row < nb.row
					end)
					list[#list + 1] = { head = head, ids = ids, minLevel = lo, maxLevel = hi, size = chain.total, generations = #chain.layers }
				end
			end
		end
	end
	return list
end

function QL.ZoneChains(area, ctx)
	if not area or not QL.IndexReady() then return {} end
	local cached = QL.zoneChainCache[area]
	if cached then return cached end
	local list = QL.GroupChains(QL.ZoneQuests(area), ctx)
	QL.zoneChainCache[area] = list
	return list
end

-- Class quests -------------------------------------------------------------------------------------
-- A class quest is one whose class mask names at most three classes, the character's among them
-- (Data.lua indexes them as index.byClass[class bit]).
--   QL.ClassQuests(classFlag) -> quest ids
--   QL.ClassChains(ctx) -> the class's quests grouped into chains (single quests kept), cached
--   QL.PlayerClass() -> { name, file, color = {r, g, b}, coords = {l, r, t, b} | nil }

function QL.ClassQuests(classFlag)
	local index = QL.index
	return index and index.byClass and classFlag and index.byClass[classFlag] or {}
end

local classCache = {}
QL.On("INDEX_READY", function() classCache = {} end)
QL.On("SETTING_CHANGED", function(key) if key == "hideOther" then classCache = {} end end)

function QL.ClassChains(ctx)
	if not QL.IndexReady() or not ctx.classFlag then return {} end
	local cached = classCache[ctx.classFlag]
	if cached then return cached end
	local list = QL.GroupChains(QL.ClassQuests(ctx.classFlag), ctx, true)
	classCache[ctx.classFlag] = list
	return list
end

function QL.PlayerClass()
	local name, file = nil, nil
	if UnitClass then
		local ok, n, f = pcall(UnitClass, "player")
		if ok then name, file = n, f end
	end
	local color = { 1, 1, 1 }
	local c = file and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(file)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]))
	if type(c) == "table" and c.r then color = { c.r, c.g, c.b } end
	local coords = file and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[file]
	return { name = name or "?", file = file, color = color, coords = coords }
end

-- Normal quests: every quest in the log (wherever it is) and every quest of the zone this
-- character can take now, most XP first (at its level; quests without XP data last).
--   QL.ZoneQuestList(area, ctx) -> { { id, status, xp, inLog }, ... }
function QL.ZoneQuestList(area, ctx)
	local seen, out = {}, {}
	local function add(id)
		if seen[id] then return end
		seen[id] = true
		local s = QL.NodeStatus(id, ctx)
		if s == "active" or s == "ready" or s == "available" then
			out[#out + 1] = { id = id, status = s, xp = QL.QuestXPAt and QL.QuestXPAt(id, ctx.level) or nil, inLog = s ~= "available" }
		end
	end
	for id in pairs(ctx.log or {}) do
		if QL.QuestExists(id) then add(id) end
	end
	if area then
		for _, id in ipairs(QL.ZoneQuests(area)) do add(id) end
	end
	table.sort(out, function(a, b)
		local xa, xb = a.xp or -1, b.xp or -1
		if xa ~= xb then return xa > xb end
		local la, lb = QL.QuestLevel(a.id) or 0, QL.QuestLevel(b.id) or 0
		if la ~= lb then return la < lb end
		return a.id < b.id
	end)
	return out
end

local STATE_ORDER = { active = 1, available = 2, toolow = 3, locked = 4, done = 5 }
QL.CHAIN_STATE_ORDER = STATE_ORDER

-- Where the character stands in one chain, and which quest to open it at.
function QL.ChainProgress(entry, ctx)
	local done, inLog, total, counted = 0, 0, 0, 0
	local firstLog, firstAvail, firstOpen, anyLow
	for _, id in ipairs(entry.ids) do
		local s = QL.NodeStatus(id, ctx)
		if s ~= "other" then
			total = total + 1
			if s ~= "closed" then counted = counted + 1 end
		end
		if s == "done" then done = done + 1
		elseif s == "active" or s == "ready" then
			inLog = inLog + 1
			firstLog = firstLog or id
		elseif s == "available" then firstAvail = firstAvail or id
		elseif s == "toolow" then anyLow = true; firstOpen = firstOpen or id
		elseif s == "locked" then firstOpen = firstOpen or id end
	end
	local state
	if inLog > 0 then state = "active"
	elseif firstAvail then state = "available"
	elseif done >= counted then state = "done"
	elseif anyLow then state = "toolow"
	else state = "locked" end
	return {
		done = done,
		inLog = inLog,
		total = math.max(counted, 1),
		state = state,
		focus = firstLog or firstAvail or firstOpen or entry.head,
	}
end
