# City

A cozy 3D city builder made with [Godot 4.7](https://godotengine.org), in the spirit of Cities: Skylines.

**Play the latest version in your browser:** https://nathanjmetz.github.io/city/

It rebuilds itself every time something is pushed to `main` (see `.github/workflows/web-preview.yml`).

## Playing

An open map where you draw roads, paint zones along them, and buildings grow, like Cities: Skylines.

| Control | What it does |
| --- | --- |
| `1` Road | Click to start, click to finish. Keeps going from the end. Hold Shift to snap angles. |
| `2` Curve | Click start, click where it bends, click the end. |
| `3` Grid | Lay out a whole neighborhood: click a corner, click to set the first street, move out and click. `[` `]` change block length. |
| `4` Roundabout | Click to place. Roads it crosses join it. `[` `]` change size. One-way, counter-clockwise, with a planted island, truck apron and splitter islands (FHWA roundabout guide); one lane for streets, two lanes (150 ft or wider) for bigger roads. |
| Road type buttons | Street (2 lanes), Avenue (4 lanes), Boulevard (6 lanes with a planted median), Highway (3 lanes one way; draw one each way) and Ramp (1 lane one way). Real US sizes, 3.6 m (12 ft) lanes. |
| Page Up / Page Down, or Raise / Lower | Build new roads above or below ground in 2.5 m steps, for bridges, overpasses and tunnels. |
| `U` Upgrade | Click a road to change it to the chosen type. |
| `P` Parallel | Draws a second road alongside. `[` `]` set the gap. |
| `B` Bulldoze | Click a road or service building to remove it. |
| `5` `6` `7` Zones | Homes, shops, industry. Hold the left mouse button and drag over the lots along a road. `[` `]` brush size. |
| Services | Power line feed and a well first (a substation and water tower serve bigger towns): buildings only grow and fill with power and water, which flow along connected roads. Fire, police, clinic and school cover homes within real road distances (green roads while placing). Place beside a street; the building turns to face it. |
| Bus depot (Services > Transit) | Place it beside a street and set its funding level (click it, then − / +). It runs itself: stops 2 to 3 blocks apart where people live and work, routes looping from downtown, buses for a bus every half hour as far as the money goes, and its own fare from its costs and its riders' incomes. It buys the land next door when its yard is full. Schools run yellow buses at bell times. The Buses view shows routes, stops and how full the buses are. See docs/transit.md. |
| Rail depot (Services > Rail) | Place it beside a road with about 420 m of straight frontage. It is a railroad with its own money and leader. The leader plans real track (US curve and grade limits, square road crossings with gates, bridges over water) to the region and to industry that ships by rail, and asks your permission on the bell before building: approve, deny or edit the route. Freight and passenger trains run real trips and come back. Click a depot for its leader, lines and development tree, and set a subsidy; click a train to see what it carries and where it is going. See docs/rail.md. |
| Farming | The Fertility view opens with it (green soil is richest). Place a corn or soybean farmhouse near good soil within 250 m of a road: it gets a winding gravel lane, builds its barn, then the farmer picks the best fields around it, square to its road, buying while they pay and selling losers in bad years. Reserve: outline land with nodes (Enter or click the first node to close) to save it for farming; roads and zoning stay off it. |
| Views (top left) | See the map by fertility, oil, ore and forest (smooth, never run out), service coverage or traffic. Esc closes. |
| `8` Dezone | Erase zones (buildings on them go away). |
| Right click | Stop drawing. |
| Click (no tool in hand) | Select a building, lot, farm or road: a panel shows whether it works, what it serves, its numbers and any problem. Badges over lots show what lacks power or water. |
| Industry | Place an oil, mining or forestry company's main building near the resource (its view opens) and within 250 m of a road. Over time it opens well pads, pits or logging stands wherever the resource is richest; Reserve saves land for it. Every load leaves on a real truck: to a factory in town, or out by the highway. Resources never run out. |
| Names and signs | Every shop, factory, farm and company has a believable southern Indiana name, lettered on its sign in its own style (slab serif feed stores, script diners, condensed garages...), and a family behind it. Click one to see who owns it, since when, and what else the family owns. A family that does well may ask (through the bell) to open on a lot you zoned or to buy out another business, under the family's name and look, up to 4 businesses in a town. Over the years signs add "SINCE 2031", businesses change hands, a new generation takes over, and old families redo their look. |
| Esc | Stop drawing; press again to put every tool away and close panels. |

| Space, or Pause / 1x / 2x / 4x | Pause and game speed. |
| Bell (top right) | Permit requests. Leaders of hubs (the railroad, the bus company...) build freely on their own land, but ask here before they cross your roads, lay track through town or take anything you built. Click one to see its plan on the map, then Approve, Deny, or Edit route (drag the bends; they re-cost your way and go ahead if they can afford it). It never pops up; a request nobody answers is shelved after a week. It works both ways: a hub's info panel lets you tell its leader to grow, use their own judgment, or hold off, and pre-approve permits near it. |
| Advice (top right) | The town's advisor: a few words on what needs fixing and what might come next, based on your town and the tool in hand. A dot means something new. It never pops up unless you turn on "Pop open for problems"; "Tips on their own" turns the dot off. |

The city runs on a clock (a day takes about 2½ minutes at 1x). Homes, shops and industry only grow when there is demand, shown by the bars in the bottom-left corner: homes are wanted while there are jobs, industry while people need work, and shops while residents need places to shop. People move into new homes over time.

Cars drive between homes, jobs and shops: to work in the morning, home in the evening. They keep right, stick to the speed limit (25 mph streets up to 65 mph highways), slow down for curves, respect one-way roads, and queue behind each other. The top-right shows traffic flow, like Cities: Skylines.

The camera uses the Cities: Skylines 2 default keys:

| Control | What it does |
| --- | --- |
| WASD / arrows, or right mouse drag | Move. Hold Shift to go faster. |
| Q / E | Rotate. |
| T / G | Tilt. |
| R / F, scroll, or pinch | Zoom. |
| Middle mouse drag, or Option (Alt) + drag on a Mac trackpad | Rotate and tilt. |

Roads snap to junctions and to other roads, and crossing roads make a junction.
Road rules come from US standards (AASHTO): grades up to 12% on streets, 8% on ramps and 5% on highways, and 16.5 ft (5 m) of clearance where one road passes over another. The drawing label shows the safe speed of each curve.
While drawing, a straight road snaps straight on or at 90° to the road it starts from, with a guide line, and shows its length in metres and feet.
Bends follow real US rules: no curve tighter than 12.8 m (42 ft), the AASHTO turning radius of a box truck.
Each road gets 20 m wide, 32 m deep lots on both sides. Nothing grows until you zone them.
Sizes are real US suburban sizes (1 unit = 1 metre): 9 m curb to curb, a grass strip and a sidewalk each side, 20 m wide house lots.
Your town saves automatically (in the browser too).

## Menus, saves and playing together

The game opens on a title screen like Cities: Skylines 2: **Continue** your latest city, start a **New city**, **Load city** (every city you've made, with its population and money), or **Play together**. In the game, **Esc** (with no tool in hand) opens the pause menu: Resume, Save, Main menu.

**Play together** puts everyone's city on one shared map. Each player has their own city, budget and economy. A new player's city starts on open land about a mile from the others, so neighbors are in sight.

- **Join:** type your name and the invite code. An invite link (`https://nathanjmetz.github.io/city/?join=CODE&server=wss://...`) fills both in for you.
- **Host:** on Mac or Windows, *Host a region* runs one from your computer and shows the code. For an always-on region, run the server on its own (below).
- **Chat:** the panel on the left. **Enter** to type, Enter to send, Esc to go back to building. Click a name to fly over and watch their city grow live; *Home* brings you back. *Invite* copies an invite.
- You see where other players are pointing (a ring with their name), a name tag over each neighbor's city, and a cream dashed **city line** on the ground halfway between neighboring cities' closest buildings and roads.
- Your city is always coral; each neighbor keeps the color they joined with (from the brand kit). A doorbell (E–C) rings when a neighbor joins or writes.
- The region keeps running while you're away, so your city keeps growing.

### Running a region server

The server is the same game with no window. It runs anywhere Godot runs (a Mac mini now, a cheap Linux cloud server later):

```
godot --headless -s scripts/net/server_main.gd -- --port 9080 --data region.json
```

It prints the invite code (made once and kept in the data file; `--code` sets your own). The region saves to the data file every 10 seconds. Options can also be set with the environment variables `CITY_PORT`, `CITY_CODE` and `CITY_DATA`.

Players on the web preview need a secure address (`wss://`), so put the server behind an HTTPS tunnel or proxy (for example a free Cloudflare Tunnel) and share `wss://your-address` as the server. On the same home network, `ws://computer-name:9080` works from the Mac and Windows versions.

How it stays in sync: the server owns the real region. Players send commands for their own city only; every tick (10 a second) the server applies what arrived, steps every city, and sends that tick to everyone, so every copy runs identically. Every 5 seconds players compare a checksum with the server and fetch a fresh copy if theirs drifted.

## The land

The map is a real place: the White River valley around Petersburg, Indiana, built from USGS elevation data and ESA land cover. Your town starts on a bluff above the river, with rolling farmland, wooded hills and creek bottoms, and old strip-mine lakes. Resources sit where they really are: rich soil in the river bottoms, coal under the uplands, oil in the Illinois Basin's pools to the south-west, and timber in the real woods. The land streams in around the camera, and past the real 32 km square it carries on as a mirror image, so it never ends.

Roads follow the land, graded smooth, and cross water on bridges by themselves. Nothing is built in the water or on slopes over 25%. Sources and licenses are in `terrain/LICENSES.md`; `python3 tools/terrain/build_region.py` rebuilds the data.

## Sound

Everything you hear is placed in the world. Each car carries its own engine sound (higher as it speeds up), homes have birds by day and crickets at night, shops have rooftop fans, factories hum, utilities buzz and farm fields rustle. Only the sources nearest the camera play, and they get quieter with distance, so you hear what you are looking at. Zoomed out, you hear wind and the far-off hum of the traffic in view. Interface sounds are wooden mallets and a plucked guitar.

All sounds are built in code by `tools/audio/make_assets.py` (`python3 tools/audio/make_assets.py` rewrites `assets/audio/`). Sources and licenses are listed in `assets/audio/LICENSES.md`.

## Layout

| Path | What's in it |
| --- | --- |
| `scripts/roads/road_network.gd` | The road graph as plain data. All edits are commands, so a server can replay them later. |
| `scripts/roads/` | Road sizes, mesh building and drawing. |
| `scripts/sim/` | The simulation: plain data, fixed ticks, every change is a command (so a headless server can run it later). Lots, zones, growth. |
| `scripts/sim/balance.gd` | Every gameplay number in one place (money, prices, upkeep, taxes, grants, growth, farm yields). Tune the game here. |
| `scripts/sim/inspect.gd`, `scripts/ui/select_tool.gd`, `scripts/ui/info_panel.gd` | Click anything with no tool in hand: CS2-style info panel (status, numbers, problems). |
| `scripts/zones/lot_alerts.gd` | "No power" and "no water" badges over lots. |
| `scripts/sim/industry.gd`, `scripts/sim/logistics.gd`, `scripts/industry/` | Resource companies, and the freight that moves every load (Traffic's `dispatch`). |
| `scripts/zones/zone_view.gd` | Draws lots and zone colours. |
| `scripts/audio/` | Sound: world sources and the nearest-first picker, the spatial players, and interface sounds. |
| `scripts/buildings/building_view.gd` | Draws placeholder homes, shops and factories. |
| `scripts/tools/zone_tool.gd` | The zone brush. |
| `scripts/camera/city_camera.gd` | The orbit camera. |
| `scripts/terrain/` | The land: `terrain.gd` (heights, water, cover and resources from the baked real data), `terrain_view.gd` (streamed ground and water chunks, grading under roads), `terrain_forest.gd` (the woods). |
| `terrain/`, `tools/terrain/` | The baked real-world map data and the script that builds it. |
| `scripts/tools/road_tool.gd` | Mouse tools for drawing and bulldozing. |
| `scripts/ui/hud.gd` | Toolbar and stats. |
| `scripts/shell/` | The title screen, pause menu, save slots (`session.gd`, the Session autoload) and shared scenery. |
| `scripts/net/` | Shared regions: `region.gd` (every city on one map, plus chat), `region_server.gd`, `region_client.gd`, `region_view.gd` (neighbors, name tags, cursors) and `server_main.gd` (headless server). |
| `scripts/ui/chat_panel.gd` | The region chat. |
| `tests/` | Headless tests: `godot --headless -s tests/test_roads.gd` and `tests/test_sim.gd`, `tests/test_traffic.gd`, `tests/test_net.gd` (a real server with two players) |
| `tools/screenshot.gd` | Renders a demo town to a PNG: `godot -s tools/screenshot.gd -- out.png` |

The game uses the Compatibility renderer so the same project runs in browsers and on modest Mac and Windows machines.
Mac and Windows downloads come later.
