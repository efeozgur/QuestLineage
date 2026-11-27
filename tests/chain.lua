-- Chain building, layout, states and the tooltip summary over the fake web in stubs.lua.
local QL = dofile("tests/stubs.lua")
local Check, Eq = QL.Check, QL.Eq

QL.BuildIndexNow()
Check(QL.IndexReady(), "index ready")
Eq(QL.DataStatus(), "ok", "QuestieDB status")

-- reverse index
local deps = {}
for _, d in ipairs(QL.Dependents(3)) do deps[d[1]] = d[2] end
Eq(deps[6], "all", "6 needs 3")
Eq(deps[9], "parent", "9 must be on 3")

-- the whole connected web for a human, the Orc quest and the strangers left out
local ctx = QL.TestContext()
local chain = QL.BuildChain(3, ctx)
Check(chain, "chain built")
for _, id in ipairs({ 1, 2, 3, 4, 5, 6, 7, 9 }) do Check(chain.nodes[id], "node " .. id) end
Check(not chain.nodes[8], "Orc-only quest hidden for a human")
Check(not chain.nodes[10], "unrelated quest left out")
Eq(chain.total, 8, "node count")
Eq(chain.focus, 3, "focus")

-- a quest that needs a profession: locked until the character has it with enough skill
local skillCtx = QL.TestContext()
QL.ProfessionRanks = function() return {} end
skillCtx.level = 10
Eq(QL.NodeStatus(27, skillCtx), "locked", "no Skinning: the quest is locked, not available")
Eq(QL.StatusLabel(27, "locked", skillCtx), "Needs Skinning", "and says which profession")
local lowCtx = QL.TestContext(); lowCtx.level = 10
QL.ProfessionRanks = function() return { Skinning = 5 } end
Eq(QL.StatusLabel(27, QL.NodeStatus(27, lowCtx), lowCtx), "Needs Skinning 20", "too little skill names the number")
local okCtx = QL.TestContext(); okCtx.level = 10
QL.ProfessionRanks = function() return { Skinning = 20 } end
Eq(QL.NodeStatus(27, okCtx), "available", "enough Skinning: available")
local blindCtx = QL.TestContext(); blindCtx.level = 10
QL.ProfessionRanks = function() return nil end
Eq(QL.NodeStatus(27, blindCtx), "available", "a client with no skill list never blocks a quest")
QL.ProfessionRanks = nil

-- the Orc quest shows when hiding is off
local all = QL.BuildChain(3, ctx, { hideOther = false })
Check(all.nodes[8], "Orc quest shown with hideOther = false")
Eq(all.nodes[8].status, "other", "Orc quest is not for a human")

-- layers: sources left, the gathering in the middle, the branches right
Eq(chain.nodes[1].layer, 1, "1 is a source")
Eq(chain.nodes[5].layer, 1, "5 (breadcrumb) is a source")
Eq(chain.nodes[2].layer, 2, "2 after 1")
Eq(chain.nodes[4].layer, 2, "4 after its breadcrumb")
Eq(chain.nodes[3].layer, 3, "3 after 2 and 4")
Eq(chain.nodes[6].layer, 4, "6 after 3")
Eq(chain.nodes[9].layer, 4, "9 after 3")
Eq(#chain.layers, 4, "four layers")
Eq(chain.height, 3, "widest layer")

-- one edge per pair, strongest kind
local kinds = {}
for _, e in ipairs(chain.edges) do kinds[e.from .. ">" .. e.to] = e.kind end
Eq(kinds["1>2"], "any", "1>2: preQuestSingle beats nextQuestInChain")
Eq(kinds["5>4"], "breadcrumb", "5>4 breadcrumb")
Eq(kinds["2>3"], "all", "2>3 all")
Eq(kinds["3>9"], "parent", "3>9 parent")
Check(not kinds["6>7"] and not kinds["7>6"], "exclusive quests are not linked by an edge")
Eq(chain.nodes[6].closes[1], 7, "6 closes 7")

-- states
ctx = QL.TestContext({ done = { [1] = true }, log = { [2] = true } })
Eq(QL.NodeStatus(1, ctx), "done", "done")
Eq(QL.NodeStatus(2, ctx), "active", "in the log")
Eq(QL.NodeStatus(3, ctx), "locked", "3 waits for 2 and 4")
Eq(QL.NodeStatus(4, ctx), "toolow", "4 needs level 6")
Eq(QL.NodeStatus(5, ctx), "available", "breadcrumb takeable")
ctx.complete[2] = true
Eq(QL.NodeStatus(2, ctx), "ready", "complete in the log")
ctx = QL.TestContext({ done = { [1] = true, [2] = true, [4] = true, [3] = true, [6] = true } })
Eq(QL.NodeStatus(7, ctx), "closed", "7 closed once 6 is done")
Eq(QL.NodeStatus(5, ctx), "closed", "breadcrumb closed once its target is done")
Eq(QL.NodeStatus(9, ctx), "locked", "9 needs 3 in the log")
ctx = QL.TestContext({ log = { [3] = true } })
Eq(QL.NodeStatus(9, ctx), "available", "9 available while on 3")
ctx = QL.TestContext({ level = 8, done = { [2] = true } })
Eq(QL.NodeStatus(3, ctx), "locked", "group needs every prerequisite")
ctx.done[4] = true
Eq(QL.NodeStatus(3, ctx), "available", "group complete")

-- a cycle must not hang and must still lay out
local loop = QL.BuildChain(11, QL.TestContext())
Check(loop and loop.total == 2, "cycle chain")
local back = 0
for _, e in ipairs(loop.edges) do if e.back then back = back + 1 end end
Eq(back, 1, "one back edge breaks the cycle")

-- a quest with no links
local alone = QL.BuildChain(10, QL.TestContext())
Eq(alone.total, 1, "single quest")
Eq(QL.ChainSummary(10, QL.TestContext()), nil, "no summary for a lone quest")

-- summary: 2 is in layer 2 of 4, next is 3
QL.ClearChainCache()
local s = QL.ChainSummary(2, QL.TestContext({ done = { [1] = true } }))
Check(s, "summary for 2")
Eq(s.index, 2, "summary index")
Eq(s.total, 4, "summary total")
Eq(s.nextId, 3, "summary next")
Eq(s.doneCount, 1, "summary done count")

-- the node limit
local small = QL.BuildChain(3, QL.TestContext(), { max = 4 })
Eq(small.total, 4, "limited to 4")
Check(small.truncated, "marked truncated")
Check(small.nodes[3], "focus kept")

-- search
Eq(QL.SearchQuests("3")[1], 3, "search by id")
Eq(#QL.SearchQuests("999"), 0, "unknown id")
Eq(QL.SearchQuests("path")[1], 6, "search by part of a name")
Eq(QL.SearchQuests("the gathering")[1], 3, "exact name first")

-- givers
Eq(QL.QuestGiver(1), "Bob", "giver")
Eq(QL.QuestEnder(1), "Alice", "ender")
Eq(QL.QuestGiver(2), nil, "no giver data")

-- a missing database
LibQuestieDB = nil
QL.ResetData()
Eq(QL.DataStatus(), "absent", "absent")
Eq(QL.BuildChain(3, QL.TestContext()), nil, "no chain without data")

print("chain: ok")
