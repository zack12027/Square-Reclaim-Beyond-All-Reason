# Square Area Reclaim

A LuaUI widget for [Beyond All Reason](https://www.beyondallreason.info/) that adds a **square** area-reclaim gesture as an alternative to the engine's circular one.

## Install

Drop `cmd_square_area_reclaim.lua` into your local BAR widgets directory:

```
<BAR install>/data/LuaUI/Widgets/
```

Then enable it in-game via the widget list (default hotkey: **F11**) — search for "Square Area Reclaim" and toggle it on.

## Usage

1. Select one or more builders.
2. Press **E** to bring up the Reclaim cursor.
3. **Right-click and drag** to size a square. Drag distance snaps to BAR's 16-elmo build grid.
4. Release the right mouse button — every reclaimable feature and unit inside the square is queued for reclaim, ordered closest-to-center first.

A tiny right-click (drag less than one grid unit) just cancels the Reclaim cursor like normal.

## Modifier keys

Held at release (except **ALT**, which is also captured at press time for unit-type detection):

| Modifier | Effect | Square tint |
|---|---|---|
| (none) | Standard reclaim — features (autoreclaimable only) + units | Green |
| **SHIFT** | Queues all the orders after current commands | (any color) |
| **ALT** + hovering a unit on press | Reclaims **only** units of that type inside the square; ignores features | Orange |
| **CTRL** | Includes non-autoreclaimable features (e.g. dragon's teeth) | Blue |

Combos work the way you'd expect: SHIFT + ALT queues a unit-type sweep, SHIFT + CTRL queues a force-reclaim sweep, and so on.

## Immobile builders

If **every** unit in your selection is an immobile builder (nano turrets, factories — anything with `buildSpeed > 0` and no movement), each one is given only the targets within its own `buildDistance`. This keeps a single nano turret from queueing reclaim orders for the whole square when most of it is out of reach.

If the selection contains **any** mobile builder, this filter is skipped and every selected unit gets every target — the mobile units handle the far stuff and the engine ignores out-of-range orders for the turrets.

## Reloading after edits

In-game, run `/luaui reload` to reload all widgets, or `/widget reload "Square Area Reclaim"` to reload just this one.

## Author

Zack Cheang — GNU GPL v2 or later.
