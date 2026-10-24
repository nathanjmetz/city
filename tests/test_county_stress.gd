extends SceneTree
## Stress test for joining county roads (Brawn 2026-10-24: "county roads
## disconnecting from each other and from the roads I build to meet them").
## Draws many random streets and grids to, across, along and near the
## section-line county roads around a crossing, the way the road tool does
## (join: true), and after each checks the network stays whole:
## - no loose end lying on a road it isn't joined to,
## - no two roads doubled along each other,
## - no two separate nodes on the same spot,
## - every joined county road is connected to the town's own roads.

const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8]
const STEPS := 30
const ORIGINS := [Vector2.ZERO, Vector2(3217.0, -2411.0), Vector2(-5120.0, 4410.0), Vector2(1800.5, 6100.25)]

var _failed := 0
var _counts := {}
var _built := 0
var _tried := 0


func _init() -> void:
	# Towns sit anywhere in the region, so each run is a town at its own
	# origin (local coordinates = region - origin).
	for s in SEEDS:
		var origin: Vector2 = ORIGINS[s % ORIGINS.size()]
		var spot := _corner(origin)
		_check(spot.is_finite(), "found a dry crossing of county roads near %s" % str(origin))
		if spot.is_finite():
			_run(s, origin, spot.x - origin.x, spot.y - origin.y)
	print("  %d of %d builds went ahead" % [_built, _tried])
	for k in _counts:
		print("  %s: %d" % [k, _counts[k]])
	_check(_counts.is_empty(), "the network stayed whole through %d random builds" % (SEEDS.size() * STEPS))
	_finish()


func _run(seed_value: int, origin: Vector2, x: float, z: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.terrain_offset = origin
	sim.economy.money = 1_000_000_000
	var S := CountyGrid.SECTION
	for step in STEPS:
		# A line near the crossing: north-south at x (+/- a mile), or
		# east-west at z.
		var ns := rng.randf() < 0.5
		var shift := float(rng.randi_range(-1, 0)) * S if rng.randf() < 0.3 else 0.0
		var lx := x + (shift if ns else 0.0)
		var lz := z + (0.0 if ns else shift)
		var along := rng.randf_range(-S * 0.45, S * 0.45)
		var on := Vector2(lx, z + along) if ns else Vector2(x + along, lz)
		var across := Vector2(1, 0) if ns else Vector2(0, 1)
		var dir := Vector2(0, 1) if ns else Vector2(1, 0)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var len := rng.randf_range(60.0, 300.0)
		var kind := rng.randi_range(0, 6)
		var cmd := {}
		var what := ""
		match kind:
			0:  # up to the line, mid-mile
				var a := on + across * side * len
				cmd = _road(a, on)
				what = "street to the line"
			1:  # across the line
				var a := on + across * side * len * 0.5
				var b := on - across * side * len * 0.5
				cmd = _road(a, b)
				what = "street across the line"
			2:  # ending a few metres short
				var short := rng.randf_range(2.0, 14.0)
				cmd = _road(on + across * side * len, on + across * side * short)
				what = "street ending %.0f m short" % short
			3:  # to the crossing itself
				var c := Vector2(lx, lz)
				# Not skimming in along a road at a shallow angle (a
				# junction that sharp is the player's to avoid).
				var ang := float(rng.randi_range(0, 3)) * PI * 0.5 + rng.randf_range(0.35, PI * 0.5 - 0.35)
				cmd = _road(c + Vector2(cos(ang), sin(ang)) * len, c)
				what = "street to the crossing"
			4:  # along the line
				cmd = _road(on, on + dir * len)
				what = "street along the line"
			5:  # curved across the line
				var a := on + across * side * len * 0.5 + dir * len * 0.3
				var b := on - across * side * len * 0.5 - dir * len * 0.3
				var ctrl := on + dir * rng.randf_range(-60.0, 60.0)
				cmd = {"type": "build_road", "start": [a.x, a.y], "ctrl": [ctrl.x, ctrl.y], "end": [b.x, b.y],
					"road": RoadStyle.Type.STREET, "join": true}
				what = "curved street across the line"
			6:  # a grid over or beside the line
				var off := rng.randf_range(-40.0, 40.0)
				var g0 := on + across * off - dir * 120.0
				var g1 := g0 + across * side * 240.0
				var g2 := g0 + dir * 240.0
				cmd = {"type": "build_grid", "a": [g0.x, g0.y], "b": [g1.x, g1.y], "c": [g2.x, g2.y], "block": 120.0,
					"join": true}
				what = "grid %.0f m off the line" % off
		_tried += 1
		if not sim.apply(cmd):
			continue
		_built += 1
		var problems := _problems(sim)
		for p in problems:
			var key := "%s after %s" % [p, what]
			_counts[key] = _counts.get(key, 0) + 1
			if _counts[key] == 1:
				print("  seed %d step %d: %s (%s)" % [seed_value, step, key, str(cmd)])


func _road(a: Vector2, b: Vector2) -> Dictionary:
	return {"type": "build_road", "start": [a.x, a.y], "ctrl": [(a.x + b.x) * 0.5, (a.y + b.y) * 0.5],
		"end": [b.x, b.y], "road": RoadStyle.Type.STREET, "join": true}


## What's wrong with the network now, as short labels.
static func _problems(sim: CitySim) -> Array:
	var net := sim.network
	var out := {}
	# Loose ends lying on a road they aren't joined to.
	for n in net.nodes:
		var segs := net.segments_at(n)
		if segs.size() != 1:
			continue
		var p: Vector3 = net.nodes[n]
		var hit := net.find_segment_near(p, 2.0)
		if not hit.is_empty() and not hit.seg in segs:
			var other: Dictionary = net.segments[hit.seg]
			if other.a != n and other.b != n:
				out["loose end on a road"] = true
	# Two separate nodes on the same spot.
	var keys := net.nodes.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if (net.nodes[keys[i]] as Vector3).distance_to(net.nodes[keys[j]]) < 1.0:
				out["two nodes on one spot"] = true
	# Roads doubled along each other: three points along one lie on
	# another running the same way.
	var ids := net.segments.keys()
	var lines := {}
	for id in ids:
		var c := net.curve_of(id)
		var pts := []
		for k in 9:
			pts.append(RoadNetwork.bezier(c[0], c[1], c[2], k / 8.0))
		lines[id] = pts
	for id in ids:
		var c := net.curve_of(id)
		if c[0].distance_to(c[2]) < 10.0:
			continue
		for other in ids:
			if other == id:
				continue
			var on_it := true
			for t in [0.25, 0.5, 0.75]:
				var p := RoadNetwork.bezier(c[0], c[1], c[2], t)
				var dir := RoadNetwork.bezier_tangent(c[0], c[1], c[2], t)
				var hit := false
				var pts: Array = lines[other]
				for k in pts.size() - 1:
					var q := Geometry3D.get_closest_point_to_segment(p, pts[k], pts[k + 1])
					var d: Vector3 = pts[k + 1] - pts[k]
					if q.distance_to(p) < 2.0 and absf(Vector2(dir.x, dir.z).normalized().dot(Vector2(d.x, d.z).normalized())) > 0.97:
						hit = true
				on_it = on_it and hit
			if on_it:
				out["doubled road"] = true
				if OS.has_environment("STRESS_DEBUG"):
					print("    doubled %d %s %s / %d %s %s" % [id, RoadStyle.Type.keys()[net.segments[id].type], str(c),
						other, RoadStyle.Type.keys()[net.segments[other].type], str(net.curve_of(other))])
	# Every joined gravel road reaches the town's own roads.
	var comp := {}
	for n in net.nodes:
		comp[n] = n
	for id in ids:
		var s: Dictionary = net.segments[id]
		_union(comp, s.a, s.b)
	var paved := {}
	for id in ids:
		if net.segments[id].type != RoadStyle.Type.GRAVEL:
			paved[_find(comp, net.segments[id].a)] = true
	for id in ids:
		if net.segments[id].type == RoadStyle.Type.GRAVEL and not paved.has(_find(comp, net.segments[id].a)):
			out["gravel cut off from town"] = true
	return out.keys()


static func _find(comp: Dictionary, n: int) -> int:
	while comp[n] != n:
		comp[n] = comp[comp[n]]
		n = comp[n]
	return n


static func _union(comp: Dictionary, a: int, b: int) -> void:
	comp[_find(comp, a)] = _find(comp, b)


## A crossing of two county roads on dry, level land, all four miles there.
func _corner(origin: Vector2) -> Vector2:
	var S := CountyGrid.SECTION
	var ox := roundi(origin.x / S)
	var oz := roundi(origin.y / S)
	for lx in range(ox - 4, ox + 4):
		for lz in range(oz - 4, oz + 4):
			if not (CountyGrid.has_mile(lx, lz) and CountyGrid.has_mile(lx, lz - 1)
					and CountyGrid.has_mile(lz + (1 << 20), lx) and CountyGrid.has_mile(lz + (1 << 20), lx - 1)):
				continue
			var dry := true
			for k in range(-25, 26):
				dry = dry and CountyGrid.clears(lx * S + k * 30, lz * S) and CountyGrid.clears(lx * S, lz * S + k * 30)
			if dry:
				return Vector2(lx * S, lz * S)
	return Vector2(INF, INF)


func _finish() -> void:
	print("ALL TESTS PASSED" if _failed == 0 else "SOME TESTS FAILED")
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		_failed += 1
		print("FAIL ", what)
