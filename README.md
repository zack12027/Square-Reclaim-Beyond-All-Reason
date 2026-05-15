# BAR LuaUI Widgets

A small collection of LuaUI widgets for [Beyond All Reason](https://www.beyondallreason.info/).

## Install

Drop any `.lua` file into your local BAR widgets directory:

```
<BAR install>/data/LuaUI/Widgets/
```

Then enable it in-game via the widget list (default hotkey: **F11**) — search for the widget name and toggle it on.

## Widgets

| File | Description |
|---|---|
| `cmd_square_area_reclaim.lua` | While the Reclaim cursor (E) is active, **right-click-drag** to reclaim everything inside a grid-snapped square. Targets are reclaimed closest-to-center first. Modifiers: `SHIFT` queues orders, `ALT` (while hovering a unit on press) restricts to that unit-type, `CTRL` includes non-autoreclaimable features. If the entire selection is immobile builders (nano turrets / factories), each one only gets targets within its own build range. |
| `cmd_smart_resurrect.lua` | Reclaims heaps and resurrects wrecks using TSP-optimized pathing. |
| `cmd_protective_guard_v2.2.lua` | Selected units guard rather than follow vulnerable units. |
| `cmd_area_rep_ignore_comm.lua` | Area repair excluding commanders. |
| `ImprovedTargeting.lua` | Auto-target priority — keeps high-value units (snipers, Banth, etc.) from wasting shots on cheap chaff. |
| `Overwatch (pausereclaim).lua` | Pauses the game when allied units are reclaimed, dgunned, or mass self-destructed. |
| `buildpower_radius.lua` | Draws build-range circles for selected builders. |
| `gui_selected_weapon_range.lua` | Weapon range overlay for selected units. |
| `nano_check.lua` | Nano turret coverage helper. |
| `pingwheel.lua` | Hold a hotkey (default Alt+F) to bring up a radial ping menu for commands and chat messages. |
| `reclaim_field_highlight.lua` | Visualizes nearby reclaimable fields. |
| `shadow_cursors.lua` | Shows ally cursor positions. |
| `unit_firing_angle.lua` | Displays firing-angle indicators. |
| `unit_last_com_tracker.lua` | Tracks last known commander positions. |

## Notes

Widgets in this folder come from a mix of authors and licenses (GPL, public domain, etc.). See each widget's `widget:GetInfo()` block for author and license info.

## Reloading after edits

In-game, run `/luaui reload` to reload all widgets, or `/widget reload "Widget Name"` to reload just one.
