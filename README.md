# QuestLineage

Quest chain trees for **World of Warcraft: Forever** (client 1.60.1, Interface 16001).

Pick any quest and QuestLineage draws its whole lineage as a family tree, unfolding from the first quests at the top down to the last: the quests that must come
before it, the breadcrumbs that lead to it, the follow-ups it opens, and the quests that taking it
closes for good. Each card shows the quest's state for your character.

## Requirements

- **QuestieDB** (required): QuestLineage reads all quest data through QuestieDB's public API
  (`LibQuestieDB`, contract 4). QuestieDB's files are never changed.
- **WoWTR** (optional): when loaded, a Turkish option appears. Quest titles and objectives then
  come from WoWTR's translations, and the interface is in Turkish.

## Where it shows up

| Place | What you get |
|---|---|
| `/ql` window | **This zone**: every quest chain with a quest in the zone you are in, the ones in progress first, with progress bars; it follows you from zone to zone. **Search**: any quest by name or id, as you type. Picking one opens its family tree in the middle and its details on the right: the quest giver in 3D, objective, story, tasks with creature portraits and item icons, who gives and takes it and where, rewards (XP, reputation, item icons), and the quests before and after it. Click a card to recentre on it, Shift-click to link it in chat. Mouse wheel scrolls, Shift+wheel scrolls sideways, drag the background to pan. |
| Arrow | QuestLineage's own arrow: click a quest in the **Quests** list (or **Point the arrow** in its details) and it turns toward the giver, the nearest creature or object you still need, or where to hand it in, with the distance. Drag to move, right-click to stop. |
| Route | Tick quests in the **Quests** list and press **Build route**: they are ordered nearest first from where you stand, and the arrow leads you stop by stop. When a quest moves on (taken, objectives done, handed in) the rest is planned again from where you are, so nearby pick-ups, kills and hand-ins mix. |
| World map | The route (or the arrow's quest) on the world map: a glowing path from you through every stop with lights flowing along it, numbered stop badges (hover for the quest, click to open it) and a caption. |
| "Where?" bar | A slim icon bar you can put anywhere (drag it): repair, innkeeper, flight master, your class trainer, your profession trainers, food, mailbox, and a "more" panel with every trainer, vendor and service. Click: the arrow turns to the nearest; click again: the next nearest; hover: the three nearest with distances. Shift-click the minimap button to show or hide it. |
| Current quest | A small window with the quest you are doing: its stage, objectives with counters and bars (they flash when they go up), XP and distance. |
| Nameplates | A quest badge and counter ("3/8") beside the nameplate of every creature an unfinished objective needs, including those that drop an item you collect. |
| Quest log | A **Chain** button on the selected quest. |
| NPC tooltips | For each chained quest the NPC gives: `Chain 2/5 · next: <quest>`. |
| Quest offer window | A strip under the window: the chain position, a **Chain** button, and a warning when taking the quest closes other quests for good (exclusive quests), or when it is only a breadcrumb. |

Card states: Done, In your log, Ready to turn in, Available, Level too low, Locked (prerequisites
missing), Closed (an exclusive quest or the breadcrumb's target was taken), Not for your character.

Line kinds: requires (all of these), one of (any one is enough), must be on (the parent quest must
be in your log), breadcrumb (optional lead-in, dashed).

## Commands

```
/ql                 open or close the window   (also /lineage, /questlineage)
/ql <id|name>       show the chain of a quest
/ql status          QuestieDB, index and language status
/ql lang en|tr      interface language (tr needs WoWTR)
/ql options         settings
/ql errors          errors caught so far
```

## Install (development)

The repository is linked into the game with a junction:

```
New-Item -ItemType Junction -Path "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\QuestLineage" -Target "C:\Users\ahmet\Desktop\QuestLineage"
```

A new addon folder needs a full game restart; after that `/reload` picks up edits.

## Tests

Plain Lua 5.1, no game client: `python tests/run.py` (needs `pip install lupa`), or a single one
with `python tests/run.py chain`.

## Türkçe

QuestLineage, bir görevin tüm zincirini (ön koşullar, yönlendirme görevleri, takip görevleri ve
alınca kalıcı olarak kapanan görevler) ağaç olarak gösterir. Arayüz İngilizcedir; **WoWTR** kuruluysa
ayarlardan (`/ql options` veya `/ql lang tr`) Türkçe seçilebilir; görev adları ve hedefler WoWTR
çevirisinden gelir.

## License

MIT (see `LICENSE`). The Inter font in `Media/Fonts` is by The Inter Project Authors under the SIL Open Font License 1.1 (`Media/Fonts/Inter-OFL.txt`). Quest data comes from the QuestieDB addon at run time and is not bundled.
