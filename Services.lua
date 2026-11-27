-- Services: where to find a trainer, a vendor or a service NPC, nearest first.
--
-- From QuestieDB's NPC rows: npcFlags (Forever: VENDOR 4, FLIGHT_MASTER 8, TRAINER 16,
-- SPIRIT_HEALER 32, INNKEEPER 128, BANKER 256, AUCTIONEER 4096, STABLEMASTER 8192,
-- REPAIR 16384) and subName ("Warrior Trainer", "Blacksmithing Trainer", "Food & Drink", ...),
-- only NPCs friendly to the character's faction (friendlyToFaction "A" / "H" / "AH").
-- Mailboxes are objects named "Mailbox". Data.lua's index pass calls QL.IndexServiceNpc and
-- QL.IndexServiceObject, filling index.services[category] = { {kind, id}, ... }.
--
--   QL.SERVICES                  categories: key, label, icon, group
--   QL.ClassifyNpc(flags, sub, name) -> list of category keys (pure)
--   QL.NearestServices(key, count) -> { {kind, id, name, sub, dist, mapName}, ... }
--   QL.KnownProfessions() -> English profession names the character has
--   QL.ClassTrainerKey() -> "class:Warrior"; QL.ProfessionKey(name) -> "prof:Mining"

local _, QL = ...

local FLAG = {
	VENDOR = 4, FLIGHT_MASTER = 8, TRAINER = 16, SPIRIT_HEALER = 32, INNKEEPER = 128,
	BANKER = 256, AUCTIONEER = 4096, STABLEMASTER = 8192, REPAIR = 16384,
}

local function has(flags, bit)
	if type(flags) ~= "number" or flags <= 0 then return false end
	return math.floor(flags / bit) % 2 == 1
end

-- key, English label (translated by QL.L), icon, group
QL.SERVICES = {
	{ key = "repair", label = "Repair", icon = "repair", group = "vendors" },
	{ key = "inn", label = "Innkeeper", icon = "inn", group = "services" },
	{ key = "flight", label = "Flight master", icon = "flight", group = "services" },
	{ key = "classTrainer", label = "Class trainer", icon = "class", group = "trainers" },
	{ key = "profTrainer", label = "Profession trainer", icon = "book", group = "trainers" },
	{ key = "food", label = "Food & drink", icon = "food", group = "vendors" },
	{ key = "mail", label = "Mailbox", icon = "mail", group = "services" },
	{ key = "weaponmaster", label = "Weapon master", icon = "weaponmaster", group = "trainers" },
	{ key = "riding", label = "Riding trainer", icon = "riding", group = "trainers" },
	{ key = "reagent", label = "Reagents", icon = "reagent", group = "vendors" },
	{ key = "trade", label = "Trade supplies", icon = "trade", group = "vendors" },
	{ key = "weapon", label = "Weapons", icon = "weapon", group = "vendors" },
	{ key = "armor", label = "Armour", icon = "armor", group = "vendors" },
	{ key = "ammo", label = "Ammunition", icon = "ammo", group = "vendors" },
	{ key = "general", label = "General goods", icon = "general", group = "vendors" },
	{ key = "bank", label = "Bank", icon = "bank", group = "services" },
	{ key = "auction", label = "Auction house", icon = "auction", group = "services" },
	{ key = "stable", label = "Stable master", icon = "stable", group = "services" },
	{ key = "spirit", label = "Spirit healer", icon = "spirit", group = "services" },
}
QL.SERVICE_BY_KEY = {}
for _, s in ipairs(QL.SERVICES) do QL.SERVICE_BY_KEY[s.key] = s end

local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local CLASS_BY_FILE = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
QL.PROFESSIONS = {
	"Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking",
	"Mining", "Skinning", "Tailoring", "Jewelcrafting", "Inscription", "Cooking", "First Aid", "Fishing",
}

local function find(text, word) return text:find(word, 1, true) ~= nil end

-- Which categories an NPC belongs to: the flags first, then the words of its subtitle.
function QL.ClassifyNpc(flags, sub, name)
	local out = {}
	local function add(k) out[#out + 1] = k end
	sub = type(sub) == "string" and sub or ""
	local s = sub:lower()
	if has(flags, FLAG.REPAIR) then add("repair") end
	if has(flags, FLAG.INNKEEPER) then add("inn") end
	if has(flags, FLAG.FLIGHT_MASTER) then add("flight") end
	if has(flags, FLAG.BANKER) then add("bank") end
	if has(flags, FLAG.AUCTIONEER) then add("auction") end
	if has(flags, FLAG.STABLEMASTER) then add("stable") end
	if has(flags, FLAG.SPIRIT_HEALER) or name == "Spirit Healer" then add("spirit") end
	if has(flags, FLAG.TRAINER) or find(s, "trainer") or find(s, "instructor") then
		local matched = false
		for _, c in ipairs(CLASSES) do
			if find(sub, c .. " Trainer") then add("class:" .. c); matched = true end
		end
		for _, p in ipairs(QL.PROFESSIONS) do
			if find(sub, p) and (find(s, "trainer") or find(s, "master") or find(s, "instructor")) then
				add("prof:" .. p); matched = true
			end
		end
		if find(s, "weapon master") or find(s, "weapon trainer") then add("weaponmaster"); matched = true end
		if find(s, "riding") then add("riding"); matched = true end
	end
	if has(flags, FLAG.VENDOR) then
		if find(s, "food") or find(s, "drink") or find(s, "baker") or find(s, "butcher") or find(s, "innkeeper") or has(flags, FLAG.INNKEEPER) then add("food") end
		if find(s, "reagent") then add("reagent") end
		if find(s, "trade supplies") or find(s, "trade goods") then add("trade") end
		if find(s, "weapon") and not find(s, "master") and not find(s, "trainer") then add("weapon") end
		if find(s, "armor") or find(s, "armour") then add("armor") end
		if find(s, "bowyer") or find(s, "gunsmith") or find(s, "arrow") or find(s, "ammunition") or find(s, "bullet") then add("ammo") end
		if find(s, "general goods") or find(s, "general supplies") then add("general") end
	end
	return out
end

-- Indexing (called from Data.lua's sliced pass) ------------------------------------------------------

local function playerFaction()
	if not UnitFactionGroup then return nil end
	local ok, f = pcall(UnitFactionGroup, "player")
	if not ok then return nil end
	return f == "Alliance" and "A" or (f == "Horde" and "H" or nil)
end

local function friendly(npcId)
	local f = QL.N(npcId, "friendlyToFaction")
	if type(f) ~= "string" or f == "" then return false end
	local mine = QL.serviceFaction or playerFaction()
	if not mine then return true end
	return f:find(mine, 1, true) ~= nil
end

function QL.IndexServiceNpc(index, id)
	local flags = QL.N(id, "npcFlags")
	local sub = QL.N(id, "subName")
	if (type(flags) ~= "number" or flags <= 4) and type(sub) ~= "string" then return end
	local cats = QL.ClassifyNpc(flags, sub, QL.N(id, "name"))
	if #cats == 0 or not friendly(id) then return end
	index.services = index.services or {}
	for _, k in ipairs(cats) do
		local list = index.services[k]
		if not list then list = {}; index.services[k] = list end
		list[#list + 1] = { "npc", id }
	end
end

function QL.IndexServiceObject(index, id)
	if QL.O(id, "name") ~= "Mailbox" then return end
	index.services = index.services or {}
	local list = index.services.mail
	if not list then list = {}; index.services.mail = list end
	list[#list + 1] = { "object", id }
end

-- The character -------------------------------------------------------------------------------------

function QL.ClassTrainerKey()
	local file
	if UnitClass then
		local ok, _, f = pcall(UnitClass, "player")
		if ok then file = f end
	end
	local name = file and CLASS_BY_FILE[file]
	return name and ("class:" .. name) or nil
end

function QL.ProfessionKey(name) return "prof:" .. name end

function QL.KnownProfessions()
	local out, seen = {}, {}
	local function add(name)
		if type(name) ~= "string" or seen[name] then return end
		for _, p in ipairs(QL.PROFESSIONS) do
			if p == name then seen[name] = true; out[#out + 1] = name end
		end
	end
	if GetProfessions and GetProfessionInfo then
		local ok, a, b, c, d, e = pcall(GetProfessions)
		if ok then
			for _, i in ipairs({ a, b, c, d, e }) do
				if i then
					local good, name = pcall(GetProfessionInfo, i)
					if good then add(name) end
				end
			end
		end
	end
	if GetNumSkillLines and GetSkillLineInfo then
		local ok, n = pcall(GetNumSkillLines)
		for i = 1, (ok and n or 0) do
			local good, name, isHeader = pcall(GetSkillLineInfo, i)
			if good and not isHeader then add(name) end
		end
	end
	return out
end

-- Skill of every profession the character has: { Mining = 75, ... } (English names); nil when the
-- client gives no skill list at all (then nothing is judged by skill).
function QL.ProfessionRanks()
	local ranks, listed = {}, false
	local function put(name, rank)
		if type(name) ~= "string" or type(rank) ~= "number" then return end
		for _, p in ipairs(QL.PROFESSIONS) do
			if p == name and rank > (ranks[name] or -1) then ranks[name] = rank end
		end
	end
	if GetProfessions and GetProfessionInfo then
		local ok, a, b, c, d, e, f = pcall(GetProfessions)
		if ok then
			listed = true
			for _, i in ipairs({ a, b, c, d, e, f }) do
				if i then
					local good, name, _, rank = pcall(GetProfessionInfo, i)
					if good then put(name, rank) end
				end
			end
		end
	end
	if GetNumSkillLines and GetSkillLineInfo then
		local ok, n = pcall(GetNumSkillLines)
		if ok and type(n) == "number" then
			listed = true
			for i = 1, n do
				local good, name, isHeader, _, rank = pcall(GetSkillLineInfo, i)
				if good and not isHeader then put(name, rank) end
			end
		end
	end
	return listed and ranks or nil
end

-- Nearest ------------------------------------------------------------------------------------------

-- Projected positions per category, kept for the player's map until it changes.
local projected = {}
QL.On("INDEX_READY", function() projected = {} end)
QL.Event("ZONE_CHANGED_NEW_AREA", function() projected = {} end)

local function mapSize(map)
	if not (C_Map and C_Map.GetMapWorldSize) then return nil end
	local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
	if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
	return nil
end

local function entriesFor(key)
	local index = QL.index
	if not index or not index.services then return {} end
	if key == "classTrainer" then
		local k = QL.ClassTrainerKey()
		return k and index.services[k] or {}
	end
	if key == "profTrainer" then
		-- the trainers of the professions you know; none known yet: any profession trainer
		local profs = QL.KnownProfessions()
		if #profs == 0 then profs = QL.PROFESSIONS end
		local out = {}
		for _, p in ipairs(profs) do
			for _, e in ipairs(index.services[QL.ProfessionKey(p)] or {}) do out[#out + 1] = e end
		end
		return out
	end
	return index.services[key] or {}
end

function QL.NearestServices(key, count)
	count = count or 5
	local map, px, py = QL.PlayerPosition()
	if not map or not px then return {} end
	local w, h
	w, h = mapSize(map)
	if not w then return {} end
	local cacheKey = key .. "@" .. map
	if key == "profTrainer" then cacheKey = cacheKey .. "@" .. table.concat(QL.KnownProfessions(), ",") end
	local list = projected[cacheKey]
	if not list then
		list = {}
		for _, e in ipairs(entriesFor(key)) do
			local best
			for _, p in ipairs(QL.SpawnPoints(e[1], e[2])) do
				local x, y = QL.ProjectToMap(p.map, p.x, p.y, map)
				if x then
					list[#list + 1] = { kind = e[1], id = e[2], x = x * w, y = y * h, srcMap = p.map }
				end
			end
		end
		projected[cacheKey] = list
	end
	-- nearest spot per NPC, then the nearest NPCs
	local me = { px * w, py * h }
	local best = {}
	for _, p in ipairs(list) do
		local d = math.sqrt((p.x - me[1]) ^ 2 + (p.y - me[2]) ^ 2)
		local k = p.kind .. p.id
		if not best[k] or d < best[k].dist then best[k] = { kind = p.kind, id = p.id, dist = d, srcMap = p.srcMap } end
	end
	local out = {}
	for _, b in pairs(best) do out[#out + 1] = b end
	table.sort(out, function(a, b)
		if a.dist ~= b.dist then return a.dist < b.dist end
		return a.id < b.id
	end)
	for i = #out, count + 1, -1 do out[i] = nil end
	for _, b in ipairs(out) do
		local get = b.kind == "npc" and QL.N or QL.O
		b.name = get(b.id, "name") or "?"
		b.sub = b.kind == "npc" and QL.N(b.id, "subName") or nil
		b.mapName = QL.MapName(b.srcMap)
	end
	return out
end
