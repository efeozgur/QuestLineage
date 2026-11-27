# Changelog

## 0.1.1 (not released yet)

### New
- **Quest item buttons and creatures to target.** A small panel for the current quest: a button for
  each item the quest has you use (click, or bind a key), and the creatures it still needs with
  your count (for an item to collect, the creatures that drop it); a click targets one when it is near. Both can be bound to keys (Key Bindings >
  AddOns). Shift+drag moves the panel. (Setting: Quest tracking > Quest item buttons.)
- **Quest items in tooltips and bags.** An item's tooltip names the quests in your log that need
  it, with your count, and bag slots holding a quest item get a small quest mark (amber while
  needed, green when that objective is done), so nothing gets sold by mistake.
- `/ql here` prints where you stand (map and coordinates); `/ql actions` explains the quest item and target panel.

### Fixes
- **Boats as they run on WoW Forever.** The Menethil boat runs a one-way loop: Menethil Harbor ->
  Southshore -> Auberdine -> Menethil Harbor. Directions no longer send you back the wrong way.
- **The arrow points at nearby quests again.** Travel directions took over even for quests down
  the road: the arrow could say "use your hearthstone" or send you to a flight master instead of
  pointing at the quest giver. Now a quest closer than about 1500 yards always gets a straight
  arrow; a flight, boat or zeppelin is only suggested when it saves at least a minute, and the
  hearthstone only when it saves several minutes. A suggested hearthstone is a hint on the label;
  the arrow keeps pointing at the quest.
- **Detours work on the way to a travel step.** A detour drawn on the map now belongs to the place
  the arrow is leading to (flight master, dock, tram), and the arrow follows it there.

### Changes
- **The flight timer is removed.** The game does not tell addons how long a flight takes, and
  its estimates for routes not flown yet were too far off to be useful.
- **The map shows the way one step at a time.** On a trip with a flight, boat, zeppelin or the
  tram, the world map line goes to the next step only (e.g. the Deeprun Tram in Ironforge), then
  to the step after it once you get there, and finally to the quest.
- **Route on the minimap for the arrow's target.** The minimap now also draws the way to whatever
  the arrow points at (a quest or the next travel step), not only planned routes: a glowing line
  with flowing lights and a pulsing marker that waits on the rim when the target is further away.
  (Setting: Maps > Route on the minimap.)

### Tip after updating
- Detours drawn before the update toward a far quest belong to the quest's own spot; draw them
  again on the way to the travel step.

## 0.1.0 (2026-11-27)

First release on CurseForge.
- Quest chain trees with a detail panel (giver in 3D, objectives, story, tasks, rewards).
- Quests, Chains, Class, Zones (with zone map) and Search tabs.
- Getting there: the quickest way to a quest in another zone or continent (ride, flight paths,
  zeppelins, boats, Deeprun Tram, hearthstone), as a clickable timeline.
- Quest arrow, routes over ticked quests, own routes and detours on the world map.
- Current quest window, quest card, nameplate badges, "Where?" bar, flight timer, hints.
- OzgurX brand.
