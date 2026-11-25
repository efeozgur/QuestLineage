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

-- Dungeons ---------------------------------------------------------------------------------------
--   QL.QuestDungeon(id) -> { area, name, kind = dungeon|raid|battleground } | nil
-- From QuestieDB's support data (ZoneDB.private.dungeons: [area] = {name, altAreas, parent, ...}):
-- a quest is a dungeon quest when its zone is one, or a creature it needs lives in one.

local RAIDS = { [1977] = true, [2159] = true, [2677] = true, [2717] = true, [3428] = true, [3429] = true, [3456] = true, [3606] = true }
local BATTLEGROUNDS = { [2597] = true, [3277] = true, [3358] = true }

local dungeonAreas -- area (or alternative area) -> main area
local function dungeonTable()
	local m = support("ZoneDB")
	local d = m and m.private and m.private.dungeons
	return type(d) == "table" and d or nil
end

local function dungeonArea(area)
	if type(area) ~= "number" or area <= 0 then return nil end
	if not dungeonAreas then
		dungeonAreas = {}
		for main, entry in pairs(dungeonTable() or {}) do
			dungeonAreas[main] = main
			if type(entry) == "table" and type(entry[2]) == "table" then
				for _, alt in ipairs(entry[2]) do dungeonAreas[alt] = main end
			end
		end
	end
	return dungeonAreas[area]
end

local dungeonCache = {}
QL.On("INDEX_READY", function() dungeonCache = {}; dungeonAreas = nil end)

function QL.QuestDungeon(id)
	local cached = dungeonCache[id]
	if cached ~= nil then return cached or nil end
	local main = dungeonArea(QL.Q(id, "zoneOrSort"))
	if not main then
		for _, t in ipairs(QL.QuestTasks(id)) do
			if t.npc then
				main = dungeonArea(QL.N(t.npc, "zoneID"))
				if main then break end
			end
		end
	end
	local result = false
	if main then
		local entry = (dungeonTable() or {})[main]
		result = {
			area = main,
			name = QL.AreaName(main) or (type(entry) == "table" and entry[1]) or ("#" .. main),
			kind = RAIDS[main] and "raid" or (BATTLEGROUNDS[main] and "battleground" or "dungeon"),
		}
	end
	dungeonCache[id] = result
	return result or nil
end

-- Difficulty ------------------------------------------------------------------------------------
--   QL.QuestDifficulty(questLevel, playerLevel) -> key, { r, g, b, label }
-- The game's own scale: 5+ levels above you very hard, 3-4 hard, within 2 normal, below that
-- easy while it still gives full-ish XP, trivial at the grey level.

QL.DIFFICULTY = {
	impossible = { 0.973, 0.443, 0.443, "Very hard" },
	hard       = { 0.984, 0.573, 0.235, "Hard" },
	normal     = { 0.980, 0.800, 0.082, "Normal" },
	easy       = { 0.290, 0.871, 0.502, "Easy" },
	trivial    = { 0.500, 0.530, 0.580, "Trivial" },
}

-- The level at and below which a quest is grey for a player (Classic's grey-level rule).
function QL.GreyLevel(p)
	if p <= 5 then return 0 end
	if p <= 39 then return p - math.floor(p / 10) - 5 end
	if p <= 59 then return p - math.floor(p / 5) - 1 end
	return p - 9
end

function QL.QuestDifficulty(level, player)
	if type(level) ~= "number" then return nil end
	player = player or QL.PlayerLevel()
	local d = level - player
	local key
	if d >= 5 then key = "impossible"
	elseif d >= 3 then key = "hard"
	elseif d >= -2 then key = "normal"
	elseif level > QL.GreyLevel(player) then key = "easy"
	else key = "trivial" end
	return key, QL.DIFFICULTY[key]
end

-- "Lv 12" in the quest's difficulty colour.
function QL.LevelMarkup(id, ctx, fmt)
	local level = QL.QuestLevel(id)
	if not level then return "" end
	local _, c = QL.QuestDifficulty(level, ctx and ctx.level)
	local text = QL.L(fmt or "Lv %d"):format(level)
	return c and (QL.Theme.Hex(c) .. text .. "|r") or text
end

-- The colour a quest's title takes: hard and very hard stand out, trivial fades; nil = default.
function QL.TitleColor(id, ctx)
	local key, c = QL.QuestDifficulty(QL.QuestLevel(id), ctx and ctx.level)
	-- r, g, b only: the label in slot 4 must never reach SetTextColor as alpha
	if key == "impossible" or key == "hard" or key == "trivial" then return { c[1], c[2], c[3] } end
	return nil
end

-- "Dungeon: The Deadmines" in violet, or nil.
function QL.DungeonMarkup(id, short)
	local d = QL.QuestDungeon(id)
	if not d then return nil end
	local L = QL.L
	local label = d.kind == "raid" and L("Raid") or (d.kind == "battleground" and L("Battleground") or L("Dungeon"))
	return QL.Theme.Hex(QL.Theme.C.accent2) .. (short and label or (label .. ": " .. d.name)) .. "|r"
end

-- XP and levels --------------------------------------------------------------------------------
--   QL.QuestXPAt(id, playerLevel) -> xp, full   the XP the quest gives at that level (Classic's
--                                            reduction for quests far below you), and its full XP
--   QL.ChainXP(ids, ctx) -> { total, done, remaining, unknown, count }
--   QL.LevelGain(xp) -> { levels, level, frac, startLevel, startFrac, approx, capped }
--   QL.FormatNumber(n) -> "12,450" ("12.450" in Turkish)

-- XP to the next level, levels 1-59 (Classic's table). The current level uses the client's own
-- UnitXPMax; later levels use this table, so a projection past the current level is approximate.
local XP_TO_LEVEL = {
	400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
	16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400,
	44300, 47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800,
	101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400,
	167100, 173900, 180800, 187900, 195000, 202300, 209800,
}
QL.XP_TO_LEVEL = XP_TO_LEVEL

-- Classic: full XP up to 5 levels above the quest, then 80/60/40/20%, and 10% from 10 above.
local XP_FACTOR = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }

function QL.XPFactor(playerLevel, questLevel)
	if not playerLevel or not questLevel then return 1 end
	local over = playerLevel - questLevel
	if over <= 5 then return 1 end
	return XP_FACTOR[over] or 0.1
end

local function roundXP(xp)
	-- the client rounds rewards to 5 below 100 XP, to 10 above
	if xp >= 100 then return math.floor(xp / 10 + 0.5) * 10 end
	return math.floor(xp / 5 + 0.5) * 5
end

function QL.QuestXPAt(id, playerLevel)
	local full = QL.QuestXP(id)
	if not full then return nil end
	local f = QL.XPFactor(playerLevel, QL.QuestLevel(id))
	if f >= 1 then return full, full end
	return roundXP(full * f), full
end

function QL.PlayerLevel()
	local lvl = UnitLevel and call(UnitLevel, "player")
	return type(lvl) == "number" and lvl > 0 and lvl or 1
end

function QL.MaxLevel()
	for _, fn in ipairs({ GetMaxLevelForPlayerExpansion, GetMaxPlayerLevel }) do
		local v = call(fn)
		if type(v) == "number" and v > 0 then return v end
	end
	return 60
end

-- The XP of a chain's quests for this character: those it can still do (at its level now),
-- those already done (full XP), and how many quests have no XP data.
function QL.ChainXP(ids, ctx)
	local level = ctx and ctx.level or QL.PlayerLevel()
	local r = { total = 0, done = 0, remaining = 0, unknown = 0, count = 0 }
	for _, id in ipairs(ids) do
		local s = QL.NodeStatus(id, ctx)
		if s ~= "other" and s ~= "closed" then
			r.count = r.count + 1
			if s == "done" then
				local full = QL.QuestXP(id)
				if full then r.done = r.done + full; r.total = r.total + full else r.unknown = r.unknown + 1 end
			else
				local xp = QL.QuestXPAt(id, level)
				if xp then r.remaining = r.remaining + xp; r.total = r.total + xp else r.unknown = r.unknown + 1 end
			end
		end
	end
	return r
end

-- Where xp more would take the character: whole and fractional levels gained, the level and
-- fraction it ends at. approx when it runs past the current level (table thresholds).
function QL.LevelGain(xp, level, have, need)
	level = level or QL.PlayerLevel()
	have = have or (UnitXP and call(UnitXP, "player")) or 0
	need = need or (UnitXPMax and call(UnitXPMax, "player")) or 0
	if type(need) ~= "number" or need <= 0 then need = XP_TO_LEVEL[level] or 1 end
	local startFrac = math.min(1, have / need)
	local maxLevel = QL.MaxLevel()
	local r = { startLevel = level, startFrac = startFrac, approx = false, capped = false }
	local lvl, cur, gain = level, have, xp or 0
	if lvl >= maxLevel then
		r.level, r.frac, r.levels, r.capped = lvl, startFrac, 0, true
		return r
	end
	while gain > 0 do
		if cur + gain < need then
			cur = cur + gain
			gain = 0
		else
			gain = gain - (need - cur)
			lvl, cur = lvl + 1, 0
			r.approx = true
			if lvl >= maxLevel then r.capped = true; break end
			need = XP_TO_LEVEL[lvl] or math.floor(need * 1.07)
		end
	end
	r.level = lvl
	r.frac = (lvl >= maxLevel) and 0 or (cur / need)
	r.levels = (lvl - level) + r.frac - startFrac
	return r
end

function QL.FormatNumber(n)
	n = math.floor((n or 0) + 0.5)
	local sep = QL.UseTurkish() and "." or ","
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
	if out:sub(1, 1) == sep then out = out:sub(2) end
	return (n < 0 and "-" or "") .. out
end

-- "+2,450 XP"
function QL.XPText(xp)
	return QL.L("%s XP"):format(QL.FormatNumber(xp))
end

-- "~+1.4 level · reaches Lv 12 (40%)" / "+0.3 level · Lv 11: 20% » 50%" / "max level"
function QL.GainText(gain)
	local L = QL.L
	if gain.capped and gain.levels <= 0 then return L("max level") end
	local parts = {}
	local lv = ("%.1f"):format(gain.levels)
	if QL.UseTurkish() then lv = lv:gsub("%.", ",") end
	parts[1] = (gain.approx and "~" or "") .. L("+%s level"):format(lv)
	if gain.level > gain.startLevel then
		parts[2] = L("reaches Lv %d (%d%%)"):format(gain.level, math.floor(gain.frac * 100))
	else
		parts[2] = L("Lv %d: %d%% » %d%%"):format(gain.level, math.floor(gain.startFrac * 100), math.floor(gain.frac * 100))
	end
	return table.concat(parts, "  ·  ")
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
