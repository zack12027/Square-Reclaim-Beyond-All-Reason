# Square Area Reclaim

A LuaUI widget for [Beyond All Reason](https://www.beyondallreason.info/) that adds two grid-snapped area-reclaim gestures as alternatives to the engine's circular one: a **centered square** and a **corner-anchored rectangle**.

## Install

Drop `cmd_square_area_reclaim.lua` into your local BAR widgets directory:

```
<BAR install>/data/LuaUI/Widgets/
```

Then enable it in-game via the widget list (default hotkey: **F11**) — search for "Square Area Reclaim" and toggle it on.

## Modes

The widget has three gesture modes. Pick one via the **in-game settings panel** ("Square Area Reclaim: gesture" dropdown) or with a chat command:

```
/squarereclaim_mode <square|draw|both>
```

| Mode | Right-click-drag | R-hold |
|---|---|---|
| `square` | Centered square | — |
| `draw` | Corner-anchored rectangle | — |
| `both` *(default)* | Centered square | Hold R first → rectangle |

The chosen mode is saved and persists across sessions. To turn the widget off entirely, disable it in the F11 widget panel.

## Usage

All gestures require the Reclaim cursor to be active. Press **E** first to bring it up, select your builders, then right-click-drag.

### Square (centered)
The square is centered on your click; its half-width snaps to BAR's 16-elmo build grid as you drag. Release to reclaim everything inside, ordered closest to your starting cursor first.

### Rectangle (corner-anchored draw)
The first corner is fixed at your click; the opposite corner follows the cursor, scaling X and Y independently and snapping in 16-elmo steps. Release to reclaim everything inside, ordered from your starting corner outward.

In `both` mode, the rectangle gesture also requires you to **hold R** for ~200 ms before the right-click. A quick tap of R while in Reclaim mode is intentionally ignored — it won't kick you into Repair, and it won't trigger the rectangle gesture.

A tiny drag (less than one grid unit on either axis) just cancels the Reclaim cursor.

A tiny drag (less than one grid unit on either axis) just cancels the Reclaim cursor like normal.

## Modifier keys

Mirrors BAR's vanilla `E + left-click` area-reclaim semantics: by default only features (wrecks / metal chunks / trees) are reclaimed and live buildings/units are left alone. Hold **ALT** or **CTRL** to also include units. Held at release (except **ALT**, which is also captured at press time for unit-type detection). The same rules apply to both square and rectangle gestures.

| Modifier | Effect | Tint |
|---|---|---|
| (none, square) | Features (autoreclaimable) + any **currently-selected** units in the area. Non-selected buildings are ignored. | Green |
| (none, rectangle) | Same, just rectangle-shaped | Cyan |
| **SHIFT** | Queues all the orders after current commands | (any color) |
| **ALT** + hovering a unit on press | Reclaims **only** units of that type inside the area; ignores features | Orange |
| **ALT** alone (no hovered unit) | Features + all units (selected and non-selected) | (default tint) |
| **CTRL** | Features (incl. non-autoreclaimable like dragon's teeth) + all units | Blue |

A builder never reclaims itself — but it *can* reclaim any other builder in your selection, so the default-mode "selected-only" rule lets you wipe out a group of your own turrets just by selecting them and dragging an area over them.

Combos work the way you'd expect: SHIFT + ALT queues a unit-type sweep, SHIFT + CTRL queues a force-reclaim sweep, and so on.

## Immobile builders

If **every** unit in your selection is an immobile builder (nano turrets, factories — anything with `buildSpeed > 0` and no movement), each one is given only the targets within its own `buildDistance`. This keeps a single nano turret from queueing reclaim orders for the whole area when most of it is out of reach.

If the selection contains **any** mobile builder, this filter is skipped and every selected unit gets every target — the mobile units handle the far stuff and the engine ignores out-of-range orders for the turrets.

## Note on R + Repair

The widget only intercepts R **while the Reclaim cursor is active**. In that state, a quick tap of R is silently ignored (so accidental taps can't drop you into Repair mid-reclaim), and a sustained ~200 ms hold arms rectangle mode for the next right-drag. Outside the Reclaim cursor (i.e. you haven't pressed E), R is left entirely alone and your normal Repair binding works as usual.

## Reloading after edits

In-game, run `/luaui reload` to reload all widgets, or `/widget reload "Square Area Reclaim"` to reload just this one.

## Author

Zack Cheang — GNU GPL v2 or later.
