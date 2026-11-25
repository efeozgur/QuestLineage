-- The quest chain around one quest, as a layered graph: what comes before it (prerequisites,
-- breadcrumbs, the quest it must be on), what comes after (follow-ups, the quests that need it),
-- and each quest's state for this character.
-- Pure logic over QL.Q / QL.Dependents / a context table (State.lua): no frames, no client calls.
--
--   QL.BuildChain(id, ctx, opts) -> chain | nil
--     chain.nodes[id] = { id, layer, row, status, level, closes = {ids}, dist }
--     chain.order     = ids in the order they were reached (focus first)
--     chain.edges     = { { from, to, kind, back }, ... }   from comes before to
--                       kind: all (one of several required) | any (one of a list is enough)
--                             | next (follow-up) | child (unlocked by) | parent (must be on)
--                             | breadcrumb (optional lead-in)
--     chain.layers    = { { ids of layer 1 }, ... }  left to right
--     chain.focus, chain.truncated, chain.total, chain.doneCount
--   QL.NodeStatus(id, ctx) -> done | ready | active | closed | other | locked | toolow | available
--   QL.ChainSummary(id, ctx) -> { index, total, nextId, doneCount, size } | nil

local _, QL = ...

QL.MAX_NODES = 80

-- Which edge wins when two link the same pair.
local KIND_RANK = { all = 1, any = 2, parent = 3, next = 4, child = 5, breadcrumb = 6 }

local function hasFlag(mask, f)
	if type(mask) ~= "number" or mask <= 0 or not f then return true end
	return math.floor(mask / f) % 2 == 1
end

function QL.Eligible(id, ctx)
	return hasFlag(QL.Q(id, "requiredRaces"), ctx.raceFlag) and hasFlag(QL.Q(id, "requiredClasses"), ctx.classFlag)
end

-- Every link of one quest: { other, kind, up } (up = other comes before id).
local function neighbours(id)
	local out = {}
	local function add(other, kind, up) out[#out + 1] = { other, kind, up } end
	for _, p in ipairs(QL.Ids(QL.Q(id, "preQuestGroup"))) do add(p, "all", true) end
	for _, p in ipairs(QL.Ids(QL.Q(id, "preQuestSingle"))) do add(p, "any", true) end
	for _, p in ipairs(QL.Ids(QL.Q(id, "parentQuest"))) do add(p, "parent", true) end
	for _, b in ipairs(QL.Ids(QL.Q(id, "breadcrumbs"))) do add(b, "breadcrumb", true) end
	for _, n in ipairs(QL.Ids(QL.Q(id, "nextQuestInChain"))) do add(n, "next", false) end
	for _, c in ipairs(QL.Ids(QL.Q(id, "childQuests"))) do add(c, "child", false) end
	for _, t in ipairs(QL.Ids(QL.Q(id, "breadcrumbForQuestId"))) do add(t, "breadcrumb", false) end
	for _, d in ipairs(QL.Dependents(id)) do add(d[1], d[2], false) end
	return out
end
QL.Neighbours = neighbours

function QL.NodeStatus(id, ctx)
	local done, log = ctx.done or {}, ctx.log or {}
	if done[id] then return "done" end
	if log[id] then return (ctx.complete and ctx.complete[id]) and "ready" or "active" end
	for _, e in ipairs(QL.Ids(QL.Q(id, "exclusiveTo"))) do
		if done[e] or log[e] then return "closed" end
	end
	for _, t in ipairs(QL.Ids(QL.Q(id, "breadcrumbForQuestId"))) do
		if done[t] or log[t] then return "closed" end
	end
	if not QL.Eligible(id, ctx) then return "other" end
	for _, p in ipairs(QL.Ids(QL.Q(id, "preQuestGroup"))) do
		if not done[p] then return "locked" end
	end
	local single = QL.Ids(QL.Q(id, "preQuestSingle"))
	if #single > 0 then
		local any = false
		for _, p in ipairs(single) do
			if done[p] then any = true; break end
		end
		if not any then return "locked" end
	end
	for _, p in ipairs(QL.Ids(QL.Q(id, "parentQuest"))) do
		if not log[p] then return "locked" end
	end
	local req = QL.Q(id, "requiredLevel")
	if type(req) == "number" and req > (ctx.level or 1) then return "toolow" end
	return "available"
end

-- Layout ----------------------------------------------------------------------

local function layout(chain)
	local nodes, edges = chain.nodes, chain.edges
	local succ, pred = {}, {}
	for id in pairs(nodes) do succ[id] = {}; pred[id] = {} end

	-- Break cycles: depth-first from every node (lowest id first); an edge back into the
	-- current path is marked back and left out of the layering.
	local outEdges = {}
	for id in pairs(nodes) do outEdges[id] = {} end
	for _, e in ipairs(edges) do table.insert(outEdges[e.from], e) end
	local ids = {}
	for id in pairs(nodes) do ids[#ids + 1] = id end
	table.sort(ids)
	local state = {}
	local function visit(id)
		state[id] = 1
		for _, e in ipairs(outEdges[id]) do
			local s = state[e.to]
			if s == 1 then e.back = true
			elseif not s then visit(e.to) end
		end
		state[id] = 2
	end
	for _, id in ipairs(ids) do
		if not state[id] then visit(id) end
	end
	for _, e in ipairs(edges) do
		if not e.back then
			table.insert(succ[e.from], e.to)
			table.insert(pred[e.to], e.from)
		end
	end

	-- Longest path from the sources (Kahn's order).
	local indeg, queue, layer = {}, {}, {}
	for _, id in ipairs(ids) do
		indeg[id] = #pred[id]
		if indeg[id] == 0 then queue[#queue + 1] = id; layer[id] = 0 end
	end
	local head = 1
	while head <= #queue do
		local id = queue[head]; head = head + 1
		for _, s in ipairs(succ[id]) do
			if layer[s] == nil or layer[s] < layer[id] + 1 then layer[s] = layer[id] + 1 end
			indeg[s] = indeg[s] - 1
			if indeg[s] == 0 then queue[#queue + 1] = s end
		end
	end

	local layers = {}
	for _, id in ipairs(ids) do
		local l = (layer[id] or 0) + 1
		layers[l] = layers[l] or {}
		table.insert(layers[l], id)
	end
	for i = 1, #layers do layers[i] = layers[i] or {} end

	-- Rows: by level first, then a few barycenter sweeps to cut crossings.
	local row = {}
	local function number(list)
		for i, id in ipairs(list) do row[id] = i end
	end
	for _, list in ipairs(layers) do
		table.sort(list, function(a, b)
			local la, lb = nodes[a].level or 0, nodes[b].level or 0
			if la ~= lb then return la < lb end
			return a < b
		end)
		number(list)
	end
	local function sweep(list, neighbourList)
		local key = {}
		for _, id in ipairs(list) do
			local sum, n = 0, 0
			for _, o in ipairs(neighbourList[id]) do sum = sum + row[o]; n = n + 1 end
			key[id] = n > 0 and (sum / n) or row[id]
		end
		table.sort(list, function(a, b)
			if key[a] ~= key[b] then return key[a] < key[b] end
			if row[a] ~= row[b] then return row[a] < row[b] end
			return a < b
		end)
		number(list)
	end
	for _ = 1, 4 do
		for i = 2, #layers do sweep(layers[i], pred) end
		for i = #layers - 1, 1, -1 do sweep(layers[i], succ) end
	end

	for l, list in ipairs(layers) do
		for _, id in ipairs(list) do
			nodes[id].layer = l
			nodes[id].row = row[id]
		end
	end
	chain.layers = layers
	chain.height = 0
	for _, list in ipairs(layers) do
		if #list > chain.height then chain.height = #list end
	end
end

-- Build -----------------------------------------------------------------------

function QL.BuildChain(focus, ctx, opts)
	focus = tonumber(focus)
	if not focus or not QL.QuestExists(focus) then return nil end
	opts = opts or {}
	local hide = opts.hideOther
	if hide == nil then hide = QL.DB().hideOther end
	local max = opts.max or QL.MAX_NODES

	local nodes, order = {}, {}
	local links = {}
	local function addNode(id, dist)
		nodes[id] = { id = id, dist = dist }
		order[#order + 1] = id
	end
	addNode(focus, 0)
	local truncated = false
	local head = 1
	while head <= #order do
		local id = order[head]; head = head + 1
		links[id] = neighbours(id)
		for _, l in ipairs(links[id]) do
			local other = l[1]
			if not nodes[other] and QL.QuestExists(other) and (not hide or QL.Eligible(other, ctx)) then
				if #order >= max then
					truncated = true
				else
					addNode(other, nodes[id].dist + 1)
				end
			end
		end
	end

	-- Edges between kept nodes, one per pair, the strongest kind winning.
	local byPair, edges = {}, {}
	for _, id in ipairs(order) do
		for _, l in ipairs(links[id] or {}) do
			local other, kind, up = l[1], l[2], l[3]
			if nodes[other] and other ~= id then
				local from, to = id, other
				if up then from, to = other, id end
				local key = from .. ">" .. to
				local e = byPair[key]
				if not e then
					e = { from = from, to = to, kind = kind }
					byPair[key] = e
					edges[#edges + 1] = e
				elseif KIND_RANK[kind] < KIND_RANK[e.kind] then
					e.kind = kind
				end
			end
		end
	end

	local chain = { focus = focus, nodes = nodes, order = order, edges = edges, truncated = truncated }
	local doneCount = 0
	for _, id in ipairs(order) do
		local n = nodes[id]
		n.level = QL.QuestLevel(id)
		n.status = QL.NodeStatus(id, ctx)
		n.closes = QL.Ids(QL.Q(id, "exclusiveTo"))
		if n.status == "done" then doneCount = doneCount + 1 end
	end
	chain.total = #order
	chain.doneCount = doneCount
	layout(chain)
	return chain
end

-- Summary for tooltips --------------------------------------------------------

local PREFER = { available = 1, active = 2, ready = 3, toolow = 4, locked = 5, other = 6, closed = 7, done = 8 }

local summaryCache = {}

function QL.ClearChainCache() summaryCache = {} end
QL.On("STATE_CHANGED", QL.ClearChainCache)
QL.On("INDEX_READY", QL.ClearChainCache)
QL.On("SETTING_CHANGED", QL.ClearChainCache)

function QL.ChainSummary(id, ctx)
	local cached = summaryCache[id]
	if cached ~= nil then return cached or nil end
	local chain = QL.BuildChain(id, ctx)
	local result = false
	if chain and chain.total >= 2 then
		local node = chain.nodes[id]
		local nextId, best
		for _, e in ipairs(chain.edges) do
			if e.from == id and not e.back and e.kind ~= "breadcrumb" then
				local p = PREFER[chain.nodes[e.to].status] or 9
				if p < 8 and (not best or p < best or (p == best and e.to < nextId)) then
					nextId, best = e.to, p
				end
			end
		end
		result = {
			index = node.layer,
			total = #chain.layers,
			nextId = nextId,
			doneCount = chain.doneCount,
			size = chain.total,
		}
	end
	summaryCache[id] = result
	return result or nil
end
