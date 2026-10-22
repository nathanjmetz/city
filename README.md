# City

A cozy 3D city builder made with [Godot 4.7](https://godotengine.org), in the spirit of Cities: Skylines.

**Play the latest version in your browser:** https://nathanjmetz.github.io/city/

It rebuilds itself every time something is pushed to `main` (see `.github/workflows/web-preview.yml`).

## Playing

An open map where you draw roads, paint zones along them, and buildings grow, like Cities: Skylines.

| Control | What it does |
| --- | --- |
| `1` Straight road | Click to start, click to finish. Keeps going from the end. Hold Shift to snap angles. |
| `2` Curved road | Click start, click where it bends, click the end. |
| `3` Bulldoze | Click a road to remove it. |
| `4` `5` `6` Zones | Homes, shops, industry. Hold the left mouse button and drag over the lots along a road. |
| `7` Dezone | Erase zones (buildings on them go away). |
| `[` `]` | Brush size. |
| Right click / Esc | Stop drawing. |
| WASD / arrows | Move the camera. |
| Q / E, R / F | Rotate, tilt. Middle mouse drag does both. |
| Scroll / pinch | Zoom. |

Roads snap to junctions and to other roads, and crossing roads make a junction.
Each road gets 20 m wide, 32 m deep lots on both sides. Nothing grows until you zone them.
Sizes are real US suburban sizes (1 unit = 1 metre): 9 m curb to curb, a grass strip and a sidewalk each side, 20 m wide house lots.
Your town saves automatically in the browser.

## Layout

| Path | What's in it |
| --- | --- |
| `scripts/roads/road_network.gd` | The road graph as plain data. All edits are commands, so a server can replay them later. |
| `scripts/roads/` | Road sizes, mesh building and drawing. |
| `scripts/sim/` | The simulation: plain data, fixed ticks, every change is a command (so a headless server can run it later). Lots, zones, growth. |
| `scripts/zones/zone_view.gd` | Draws lots and zone colours. |
| `scripts/buildings/building_view.gd` | Draws placeholder homes, shops and factories. |
| `scripts/tools/zone_tool.gd` | The zone brush. |
| `scripts/camera/city_camera.gd` | The orbit camera. |
| `scripts/tools/road_tool.gd` | Mouse tools for drawing and bulldozing. |
| `scripts/ui/hud.gd` | Toolbar and stats. |
| `tests/` | Headless tests: `godot --headless -s tests/test_roads.gd` and `tests/test_sim.gd` |
| `tools/screenshot.gd` | Renders a demo town to a PNG: `godot -s tools/screenshot.gd -- out.png` |

The game uses the Compatibility renderer so the same project runs in browsers and on modest Mac and Windows machines.
Mac and Windows exports and multiplayer (each player's own city in a shared region, hosted on a Mac mini) come later.
