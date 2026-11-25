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

MIT (see `LICENSE`). Quest data comes from the QuestieDB addon at run time and is not bundled.
