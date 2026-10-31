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
		# Aimed at the most skewed town street crossing of the county
		# railroad once the town is built (_skew_aim).
		["07_skew_35m", Vector3(-20.0, 0.0, 50.0), 0.0, 55.0, 35.0, "day", FAIR],
		# From the front (added 2026-10-31, round early3): the first shops on
		# the street nearest the highway, at street level and 60 m, and the
		# fronts of a block of homes at 45 m.
		["08_shops_street", Vector3(40.0, 0.0, 122.0), 180.0, 8.0, 30.0, "day", FAIR],
		["09_shops_60m", Vector3(40.0, 0.0, 125.0), 160.0, 30.0, 60.0, "day", FAIR],
		["10_homes_front_45m", Vector3(110.0, 0.0, 258.0), 200.0, 25.0, 45.0, "day", FAIR],
		# The shop street's curb between the 4-way and the T, close (its
		# painted stalls; early-fix-5).
		["11_main_curb_20m", Vector3(20.0, 0.0, 104.0), 180.0, 50.0, 20.0, "day", FAIR],
		# A fire hydrant in a home street's grass strip, close (added
		# 2026-10-31, early-fix-9; aimed at the one nearest shot 01).
		["12_hydrant_6m", Vector3(-30.0, 0.0, 310.0), 180.0, 12.0, 5.0, "day", FAIR],
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
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": zone, "hold": true, "single": true})
	sim.apply({"type": "zone_done"})
	for spot in [[Services.Kind.POWER_FEED, Vector3(-60.0, 0.0, 380.0)], [Services.Kind.WELL, Vector3(110.0, 0.0, 380.0)]]:
		var site := Services.site_near(sim.network, spot[0], spot[1])
		if not site.is_empty():
			sim.apply({"type": "place_service", "kind": spot[0], "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	for i in GROW_DAYS * Seasons.TICKS_PER_DAY:
		sim.tick()
	_skew_aim(sim)
	_hydrant_aim(sim)
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


## Shot 07: the town street crossing the county track at the sharpest
## angle, looked at from beside the street.
func _skew_aim(sim: CitySim) -> void:
	var best := -1.0
	for c in sim.county_trains.crossings:
		var pos: Vector3 = c.pos
		var q := Vector2(pos.x, pos.z) + sim.terrain_offset
		var n := CountyRail.near(q.x, q.y, 8.0)
		if n.is_empty() or not sim.network.segments.has(c.seg):
			continue
		var t := (CountyRail.point(n.route, n.along + 2.0) - CountyRail.point(n.route, n.along - 2.0)).normalized()
		var pts := sim.network.sample_segment(c.seg)
		var k := 0
		for i in pts.size():
			if pts[i].distance_to(pos) < pts[k].distance_to(pos):
				k = i
		var r := pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]
		var road := Vector2(r.x, r.z).normalized()
		var skew := absf(road.dot(t))  # 0 square, toward 1 sharp
		if skew > best:
			best = skew
			for s in SHOTS:
				if s[0] == "07_skew_35m":
					s[1] = Vector3(pos.x, 0.0, pos.z)
					s[2] = rad_to_deg(atan2(-road.x, -road.y)) + 40.0
	print("early_round: shot 07 at the crossing %.0f degrees off square" % rad_to_deg(asin(clampf(best, 0.0, 1.0))))


## Shot 12: the hydrant nearest shot 01, seen from the street, beside the
## curb (also says how many the town has).
func _hydrant_aim(sim: CitySim) -> void:
	var count := 0
	var best := INF
	var spot := Vector3.ZERO
	var plan := TreatmentView.plan(sim)
	for sq in plan.props:
		for e in plan.props[sq]:
			if e[0] != "hydrant":
				continue
			count += 1
			var p: Vector3 = e[1].origin
			var d := Vector2(p.x, p.z).distance_to(Vector2(-30.0, 310.0))
			if d < best:
				best = d
				spot = p
	for s in SHOTS:
		if s[0] == "12_hydrant_6m" and count > 0:
			s[1] = Vector3(spot.x, 0.0, spot.z)
	print("early_round: %d hydrants in the young town" % count)
