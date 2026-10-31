extends "res://tools/look_round.gd"
## The look round for a young town: what a player sees in the first three or
## four hours (Nathan, 2026-10-31: "focus on what is (1) least realistic,
## (2) most visible/commonly used and (3) accessible in the first 3 - 4
## hours of the game").
##
## The town is built the way a new game starts (main.gd _starter_road: the
## county highway and its free exit road), then a first player's moves: a
## 2 by 2 block grid off the exit, shops on the row nearest the highway, a
## few factory lots on the east street, homes on the rest, a power line feed
## and a well. The sim then runs GROW_DAYS game days, so the lots grow in as
## they do in play (no lot is filled by hand). Shots are on May 10 (a new
## town opens on April 7) at the heights a player looks from (street level
## to 150 m), and one at dusk. Everything else (the waits, the timing,
## frames.json, the throwaway-HOME check) is the look round's.
##   HOME=$(mktemp -d) godot --resolution 1920x1080 -s tools/early_round.gd -- OUT_DIR [--quality=...]

## The grid off the exit road: corners and block size (metres).
const GRID := [Vector2(-100.0, 100.0), Vector2(180.0, 100.0), Vector2(-100.0, 380.0)]
const GRID_BLOCK := 140.0
## Game days the young town grows before the pictures.
const GROW_DAYS := 3
## The shots' day (month, day of month): a few weeks after a new town opens.
const EARLY := [5, 10]


func _initialize() -> void:
	SHOTS = [
		["01_street", Vector3(-30.0, 0.0, 310.0), 0.0, 10.0, 40.0, "day", FAIR],
		["02_40m", Vector3(40.0, 0.0, 110.0), 0.0, 25.0, 40.0, "day", FAIR],
		["03_80m", Vector3(40.0, 0.0, 210.0), 35.0, 30.0, 80.0, "day", FAIR],
		["04_150m", Vector3(40.0, 0.0, 220.0), 35.0, 40.0, 150.0, "day", FAIR],
		["05_exit_60m", Vector3(-20.0, 0.0, 50.0), 200.0, 25.0, 60.0, "day", FAIR],
		["06_dusk_100m", Vector3(40.0, 0.0, 210.0), 35.0, 22.0, 100.0, "dusk", FAIR],
	]
	super._initialize()


func _town(sim: CitySim) -> void:
	sim.apply({"type": "build_county_road", "a": [-2000, 0], "b": [2000, 0], "links": [0, 1]})
	var money := sim.economy.money
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [-20, 0], "end": [40, 60]})
	sim.economy.money = money
	sim.apply({"type": "build_road", "start": [40, 60], "ctrl": [40, 80], "end": [40, 100]})
	sim.apply({"type": "build_grid", "a": [GRID[0].x, GRID[0].y], "b": [GRID[1].x, GRID[1].y],
		"c": [GRID[2].x, GRID[2].y], "block": GRID_BLOCK})
	for id in sim.network.segments.keys():
		for side in [-1, 1]:
			var c := sim.network.curve_of(id)
			var mid := RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
			var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], 0.5)
			var p: Vector3 = mid + Vector3(-tan.z, 0.0, tan.x).normalized() * float(side) * 15.0
			if p.z < GRID[0].y - 5.0:
				continue  # the highway and the exit road stay rural
			var zone := ZoneMap.Zone.RESIDENTIAL
			if p.x > GRID[1].x + 5.0:
				zone = ZoneMap.Zone.INDUSTRIAL
			elif p.z < GRID[0].y + 30.0:
				zone = ZoneMap.Zone.COMMERCIAL
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": zone, "hold": true})
	sim.apply({"type": "zone_done"})
	for spot in [[Services.Kind.POWER_FEED, Vector3(-60.0, 0.0, 380.0)], [Services.Kind.WELL, Vector3(110.0, 0.0, 380.0)]]:
		var site := Services.site_near(sim.network, spot[0], spot[1])
		if not site.is_empty():
			sim.apply({"type": "place_service", "kind": spot[0], "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	for i in GROW_DAYS * Seasons.TICKS_PER_DAY:
		sim.tick()
	print("early_round: young town after %d days: %d buildings, %d people, $%d" % [GROW_DAYS,
		sim.buildings.size(), sim.stats.population, sim.economy.money])


## The look round's July 15 is May 10 here (the light, the leaves, the clock).
func _set_moment(month: int, day: int, hour: float) -> void:
	if month == DAY[0] and day == DAY[1]:
		month = EARLY[0]
		day = EARLY[1]
	super._set_moment(month, day, hour)


## No tiers set by hand: a young town's lots are as the sim left them.
func _mixed_town(_sim: CitySim) -> void:
	pass
