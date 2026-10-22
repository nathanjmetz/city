extends SceneTree
## Draws a top-down plat of surveyed lots to a PNG, to compare against real
## parcel maps. Run: godot --headless -s tools/lot_map.gd -- <scene> <out.png>
## Scenes: grid, curves, mixed.

const SCALE := 2.0  # pixels per metre


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: String = args[0] if args.size() > 0 else "grid"
	var out: String = args[1] if args.size() > 1 else "user://lots.png"
	var sim := CitySim.new()
	build(sim, scene.trim_suffix("-old"))
	if scene.ends_with("-old"):
		# The fixed 20 x 32 m lots from before natural lots, for comparison.
		sim.lots.clear()
		# (The old planner dropped lots that hit a road or an earlier lot.)
		var placed := []
		for lot in LotPlanner.legacy_plan(sim.network):
			var ok := true
			for id in sim.network.segments:
				var pts := sim.network.sample_segment(id, 16)
				var line := PackedVector2Array()
				for q in pts:
					line.append(Vector2(q.x, q.z))
				for row in Geometry2D.offset_polyline(line, RoadStyle.right_of_way_half(sim.network.segments[id].type)):
					ok = ok and Geometry2D.intersect_polygons(lot.corners, row).is_empty()
			for o in placed:
				ok = ok and Geometry2D.intersect_polygons(Geometry2D.offset_polygon(lot.corners, -0.8)[0], o.corners).is_empty()
			if ok:
				placed.append(lot)
				sim.lots[lot.key] = lot
	var img := render(sim)
	img.save_png(out)
	print("%s: %d lots -> %s" % [scene, sim.lots.size(), out])
	quit()


static func build(sim: CitySim, scene: String) -> void:
	match scene:
		"grid":
			sim.apply({"type": "build_grid", "a": [0, 0], "b": [360, 0], "c": [360, 240], "block": 120.0})
		"curves":
			sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [150, -60], "end": [300, 0]})
			sim.apply({"type": "build_road", "start": [0, 0], "ctrl": [-20, 120], "end": [80, 200]})
			sim.apply({"type": "build_road", "start": [80, 200], "ctrl": [200, 260], "end": [300, 160]})
			sim.apply({"type": "build_road", "start": [300, 160], "ctrl": [330, 80], "end": [300, 0]})
			sim.apply({"type": "build_road", "start": [150, -30], "ctrl": [150, 60], "end": [150, 120]})
		"mixed":
			sim.apply({"type": "build_grid", "a": [0, 0], "b": [240, 0], "c": [240, 200], "block": 100.0})
			sim.apply({"type": "build_road", "start": [0, 200], "ctrl": [120, 330], "end": [240, 200], "road": 1})
			sim.apply({"type": "build_road", "start": [120, 0], "ctrl": [160, -80], "end": [260, -60]})
	for id in sim.network.segments.keys():
		for side in [-1, 1]:
			var zone := ZoneMap.Zone.RESIDENTIAL
			if scene == "mixed" and sim.network.segments[id].type == 1:
				zone = ZoneMap.Zone.COMMERCIAL
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": zone})


static func render(sim: CitySim) -> Image:
	var box := Rect2()
	var first := true
	for id in sim.network.segments:
		for p in sim.network.sample_segment(id, 16):
			var q := Vector2(p.x, p.z)
			box = Rect2(q, Vector2.ZERO) if first else box.expand(q)
			first = false
	box = box.grow(70.0)
	var w := int(box.size.x * SCALE)
	var h := int(box.size.y * SCALE)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color("#9bb07a"))
	var keys := sim.lots.keys()
	keys.sort()
	var k := 0
	for key in keys:
		var lot: Dictionary = sim.lots[key]
		var c: PackedVector2Array = lot.corners
		var r := LotPlanner._box(c)
		var tint := Color.from_hsv(fposmod(k * 0.13, 1.0), 0.25, 0.92)
		if lot.flag:
			tint = Color("#e8c9a0")
		elif lot.corner:
			tint = Color("#c9d8f0")
		k += 1
		for py in range(int((r.position.y - box.position.y) * SCALE), int((r.end.y - box.position.y) * SCALE) + 1):
			for px in range(int((r.position.x - box.position.x) * SCALE), int((r.end.x - box.position.x) * SCALE) + 1):
				if px < 0 or py < 0 or px >= w or py >= h:
					continue
				var p := Vector2(px / SCALE + box.position.x, py / SCALE + box.position.y)
				if Geometry2D.is_point_in_polygon(p, c):
					var prev := img.get_pixel(px, py)
					img.set_pixel(px, py, Color.RED if prev != Color("#9bb07a") else tint)
		for i in c.size():
			_line(img, (c[i] - box.position) * SCALE, (c[(i + 1) % c.size()] - box.position) * SCALE, Color("#3a3a3a"))
	for id in sim.network.segments:
		var pts := sim.network.sample_segment(id, 24)
		var half := RoadStyle.half_width(sim.network.segments[id].type)
		for i in range(pts.size() - 1):
			var a := (Vector2(pts[i].x, pts[i].z) - box.position) * SCALE
			var b := (Vector2(pts[i + 1].x, pts[i + 1].z) - box.position) * SCALE
			for o in range(-int(half * SCALE), int(half * SCALE) + 1):
				var d := (b - a).normalized()
				var n := Vector2(-d.y, d.x) * o
				_line(img, a + n, b + n, Color("#555555"))
	return img


static func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var n := int(maxf(a.distance_to(b), 1.0))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
			img.set_pixel(int(p.x), int(p.y), col)
