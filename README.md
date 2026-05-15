# Square Area Reclaim

A LuaUI widget for [Beyond All Reason](https://www.beyondallreason.info/) that adds two grid-snapped area-reclaim gestures as alternatives to the engine's circular one: a **centered square** and a **corner-anchored rectangle**.

## Install

Drop `cmd_square_area_reclaim.lua` into your local BAR widgets directory:

```
<BAR install>/data/LuaUI/Widgets/
```

Then enable it in-game via the widget list (default hotkey: **F11**) — search for "Square Area Reclaim" and toggle it on.

## Modes

The widget has three gesture modes. Pick one via the **in-game settings panel** ("Square Area Reclaim: gesture" dropdown under the Control tab) or with a chat command:

```
/squarereclaim_mode <square|draw|both>
```

| Mode | Right-click-drag | R behavior |
|---|---|---|
| `square` | Centered square | Untouched — R is your normal Repair binding |
| `draw` | Corner-anchored rectangle | Untouched — R is your normal Repair binding |
| `both` *(default)* | Centered square | Hold R for ~200 ms first → rectangle |

The chosen mode is saved (via `Spring.SetConfigString`) and persists across sessions. To turn the gesture off entirely, disable the widget in the F11 panel.

## Usage

All gestures require the Reclaim cursor to be active. Press **E** first to bring it up, select your builders, then right-click-drag.

### Square (centered)
The square is centered on your click; its half-width snaps to BAR's 16-elmo build grid as you drag. Release to reclaim everything inside, ordered closest to your starting cursor first.

### Rectangle (corner-anchored draw)
The first corner is fixed at your click; the opposite corner follows the cursor, scaling X and Y independently and snapping in 16-elmo steps. Release to reclaim everything inside, ordered from your starting corner outward.

In `both` mode, the rectangle gesture additionally requires you to **hold R** for ~200 ms before the right-click. A quick tap of R while in Reclaim mode is intentionally ignored — it won't kick you into Repair, and it won't trigger the rectangle gesture.

A tiny drag (less than one grid unit on either axis) just cancels the Reclaim cursor like a normal right-click.

## Modifier keys

Mirrors BAR's vanilla `E + left-click` area-reclaim semantics: by default only **features** (wrecks / metal chunks / trees) are reclaimed and non-selected live buildings are left alone. Hold **ALT** or **CTRL** to also pull in all units in the area. The same rules apply to both square and rectangle gestures.

| Modifier | Effect | Square tint | Rect tint |
|---|---|---|---|
| (none) | Features (autoreclaimable) + any **currently-selected** units in the area. Non-selected buildings are ignored. | Green | Cyan |
| **SHIFT** | Queues the orders after current commands instead of replacing the queue | (any) | (any) |
| **ALT** + hovering a unit on press | Reclaims **only** units of that type inside the area; ignores features | Orange | Orange |
| **ALT** alone (no hovered unit) | Features + all units (selected and non-selected) | (default) | (default) |
| **CTRL** | Features (incl. non-autoreclaimable like dragon's teeth) + all units | Blue | Blue |

Combos work the way you'd expect: SHIFT + ALT queues a unit-type sweep, SHIFT + CTRL queues a force-reclaim sweep, and so on.

A builder never reclaims itself — but it *can* reclaim any other builder in your selection. So the default-mode "features + selected units only" rule lets you wipe out a group of your own turrets just by selecting them and dragging an area over them.

## Immobile builders

If **every** unit in your selection is an immobile builder (nano turrets, factories — anything with `buildSpeed > 0` and no movement), each one is given only the targets within its own `buildDistance`. This keeps a single nano turret from queueing reclaim orders for the whole area when most of it is out of reach.

If the selection contains **any** mobile builder, this filter is skipped and every selected unit gets every target — the mobile units handle the far stuff and the engine ignores out-of-range orders for the turrets.

## Note on R + Repair

The R key is only ever touched in `both` mode, and only **while the Reclaim cursor is active**. In that state, a quick tap of R is silently ignored (so accidental taps can't drop you into Repair mid-reclaim), and a sustained ~200 ms hold arms rectangle mode for the next right-drag.

In `square` and `draw` modes — and any time the Reclaim cursor is not up — R is left entirely alone and your normal Repair binding works as usual.

## Reloading after edits

In-game, open chat (Enter) and run one of:

- `/luaui reload` — reloads all LuaUI widgets.
- `/luaui reload "Square Area Reclaim"` — reloads just this one widget.
- `/luaui disable "Square Area Reclaim"` then `/luaui enable "Square Area Reclaim"` — fallback if a reload doesn't pick up structural changes.

## Debug output

The widget echoes `[SquareReclaim] ...` lines into the chat console while `DEBUG = true` (set near the top of the file). Useful for verifying the gesture fired, what features/units were found in the area, and which mode was active. Set `DEBUG = false` to silence it once you're happy.

## Author

Zack Cheang — GNU GPL v2 or later.
