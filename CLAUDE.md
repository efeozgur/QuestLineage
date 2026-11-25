# CLAUDE.md

QuestLineage is a WoW addon (Lua 5.1, Interface 16001, client 1.60.1 "World of Warcraft: Forever"): quest chain trees built on the QuestieDB addon. It is independent of ForeverTrail (a separate repo by the same author). No build step; the repo is linked into `Interface\AddOns\QuestLineage` with a junction, so edits take effect on `/reload` (new files need a full game restart).

## Rules

- **Interface language:** English by default. Turkish is an option that only takes effect while WoWTR is loaded (`QL.UseTurkish()`). Every user-facing string goes through `QL.L("English text")`; add its Turkish to the `TR` table in `Locale.lua`. Quest titles/objectives go through `QL.QuestTitle` / `QL.QuestObjectives` (WoWTR's `QTR_QuestData` first when Turkish, else QuestieDB). Font strings showing translated text get `QL.SetFont` (WoWTR's font has the Turkish letters).
- **QuestieDB only through its public API** (`LibQuestieDB.Quest/Npc/Object/Item.Get(id, field)`, `GetAllIds()`, `RequireContract(4)`), via the wrappers in `Data.lua` (`QL.Q/N/O/I`, pcall-guarded). Never read or change QuestieDB's or Questie's files.
- **No third-party code is copied in.** Polestar (GPL) and Queston Forever (All Rights Reserved) may only be looked at for ideas. QuestLineage stays MIT.
- Client calls are guarded (`pcall`, nil checks): frame names and APIs are not verified on every Forever build. Hooks are post-hooks only (`hooksecurefunc`, `HookScript`, `TooltipDataProcessor`).
- Every file must load with a bare namespace table and no client (tests do this).

## Layout (load order = `QuestLineage.toc`)

- `Core.lua`: namespace `QL` (global `QuestLineage`), `QL.DB()` settings with defaults, `QL.On/Fire` internal messages (`SETTING_CHANGED`, `STATE_CHANGED`, `INDEX_READY`, `LOGIN`), `QL.Event` game events, `/ql` commands.
- `Locale.lua`: `QL.L`, `QL.UseTurkish`, `QL.QuestTitle/QuestObjectives`, fonts.
- `Data.lua`: QuestieDB adaptor, reverse index (`QL.Dependents(id)` = quests needing id, kinds all/any/parent; name list for search) built once per session in frame slices (`QL.WhenIndexed(fn)`), `QL.SearchQuests`, `QL.QuestGiver/Ender/Level`.
- `State.lua`: `QL.Context()` = {level, raceFlag, classFlag, done, log, complete}, cached until a quest-log event.
- `Chain.lua`: pure logic. `QL.BuildChain(id, ctx, opts)` (BFS over all links, node cap 80, one edge per pair with the strongest kind, cycles broken by back edges, layers by longest path, rows by barycenter sweeps), `QL.NodeStatus`, `QL.ChainSummary` (cached; cleared on state/index/setting changes).
- `TreeFrame.lua`: the window (`QL.Open`, `QL.ToggleWindow`, `QL.RenderWindow`), `QL.FillQuestTooltip`.
- `Hooks.lua`: quest log button, NPC tooltip line, quest offer strip (`QL.SummaryText`).
- `Options.lua`: settings page (`QL.OpenOptions`).

## Tests

`python tests/run.py` (Python 3 + `pip install lupa`; on this machine use `C:\Users\ahmet\AppData\Local\Programs\Python\Python311\python.exe`, the `python` on PATH is another venv). `tests/stubs.lua` holds a fake LibQuestieDB with a small quest web; `tests/chain.lua` (logic), `tests/locale.lua` (language), `tests/ui.lua` (every file under a mock client: window, search, tooltip line, offer strip, Turkish).
