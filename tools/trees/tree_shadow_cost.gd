extends SceneTree
## What the grown trees' sun shadows cost on each tier, with no window: a
## built-out test town (PerfTown) in mid-July, the grown trees looked up
## round a street-level camera and from 40 m and 100 m up, every mesh made,
## then the shadow-only groups (GrownTrees.SHADOW_BIT) counted: trees,
## triangles and groups (a draw call each, per shadow-map split they
## touch). The card trees' shadows past the grown trees are not counted
## (no tier's change here touches them). Every tree round the camera is
## counted, behind it too, and a group is drawn once into each split it
## touches (Medium has 2, High and up 4): read the triangles as one split's.
## Run: godot --headless -s tools/trees/tree_shadow_cost.gd -- SAVE [--blocks=5]
## SAVE is a throwaway save path: never a real town (it is cleared).
## 2026-10-29, after #935 grew the yard trees: the leafiest street of a
## 5-block town (31 grown trees within 50 m), from 6 m up: Medium 34 trees
## filed (24 inside its 45 m), 32,590 triangles in 25 groups; Cinematic
## 242 trees, 418,378 in 97.

const TIERS := [GraphicsQuality.LOW, GraphicsQuality.MEDIUM, GraphicsQuality.HIGH, GraphicsQuality.CINEMATIC]
## Camera heights over the street (m).
const HEIGHTS := [6.0, 40.0, 100.0]

var _main: Node
var _frames := 0
var _street := Vector3.ZERO


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=")[1]
	return fallback


func _process(_delta: float) -> bool:
	var a := OS.get_cmdline_user_args()
	if _main == null:
		if FileAccess.file_exists(a[0]):
			DirAccess.remove_absolute(a[0])
		root.get_node("/root/Session").save_path = a[0]
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	if _main.loading:
		return false
	_frames += 1
	if _frames == 2:
		var sim: CitySim = _main.sim
		sim.apply({"type": "clear"})
		Weather.on = false
		DayNight.cycle_on = false
		sim.tick_count = int(fposmod(6.5 - Seasons.START_MONTH, 12.0) * Seasons.TICKS_PER_DAY)
		PerfTown.build(sim, _arg("blocks", "5"))
		for key in sim.buildings:
			sim.buildings[key].built = sim.tick_count
		sim.buildings_changed.emit()
		sim.require_utilities = false
		_main.set_speed(0)
		return false
	if _frames < 120:
		return false  # the views lay out their trees
	_measure()
	quit()
	return true


func _measure() -> void:
	var n := 0
	for f: TreeField in TreeField.fields:
		for key in f._trees:
			n += (f._trees[key] as Array).size()
	_street = _street_point(_main.sim)
	print("town: %d trees in %d fields" % [n, TreeField.fields.size()])
	var was_detail := GraphicsQuality.detail
	var was_shadows := GraphicsQuality.tree_shadows
	var was_budget: Dictionary = GraphicsQuality.budget
	for t in TIERS:
		var tier: Dictionary = GraphicsQuality.TIERS[t]
		GraphicsQuality.detail = tier.detail
		GraphicsQuality.tree_shadows = tier.tree_shadows
		GraphicsQuality.budget = GraphicsQuality.budget_for(t)
		var d := clampf(GraphicsQuality.detail, 0.4, 2.5)
		var r := Vector2(TreeLook.NEAR * d, TreeLook.MID * d)
		for h in HEIGHTS:
			var row := _one(_street + Vector3(0.0, h, 0.0), r)
			print("%-9s %4.0f m up: %s" % [GraphicsQuality.NAMES[t], h, JSON.stringify(row)])
	GraphicsQuality.detail = was_detail
	GraphicsQuality.tree_shadows = was_shadows
	GraphicsQuality.budget = was_budget


## The grown trees round one camera spot, every mesh made: what their
## shadow-only groups hold.
func _one(cam: Vector3, r: Vector2) -> Dictionary:
	var g := GrownTrees.new()
	root.add_child(g)
	g._threads = false
	for pass_i in 6:
		g._start_scan(cam, r)
		var steps := 0
		while g._scanning and steps < 100000:
			g._scan_some(50.0)
			steps += 1
		if g._want.is_empty():
			break
		while not g._want.is_empty():
			g._build_some(200.0)
	var reach := GrownTrees.shadow_reach()
	var trees := 0
	var within := 0
	var tris := 0
	var groups := 0
	var cards := 0
	for key in g._counts:
		if not GrownTrees.is_shadow_group(key):
			continue
		var c: int = g._counts[key]
		groups += 1
		trees += c
		if key >= 0:
			tris += int(g._tris.get(GrownTrees.group_mesh(key), 0)) * c
		else:
			cards += c
	# How many of them are inside the reach itself (the shader thins out
	# the rest, which are filed with the lookup's slack).
	if reach < INF:
		for f: TreeField in TreeField.fields:
			for c in f.chunks_near(cam, reach):
				for i in f.chunk_trees(c).size():
					var rec := f.chunk_record(c, i)
					if not rec.is_empty() and rec[5] and (f.global_transform * (rec[0] as Transform3D)).origin.distance_to(cam) < reach:
						within += 1
	var drawn := 0
	for key in g._counts:
		if key >= 0 and not GrownTrees.is_shadow_group(key):
			drawn += int(g._tris.get(key, 0)) * int(g._counts[key])
	var out := {"reach": reach if reach < INF else "all", "shadow_trees": trees, "within_reach": within if reach < INF else trees,
		"shadow_tris": tris, "shadow_groups": groups, "card_standins": cards, "drawn_tris": drawn}
	root.remove_child(g)
	g.free()
	return out


## The middle of the street with the most grown trees within 50 m: the
## leafiest street in town (the worst case for tree shadows).
func _street_point(sim: CitySim) -> Vector3:
	var spots := PackedVector3Array()
	for f: TreeField in TreeField.fields:
		for c in f.chunks_near(Vector3.ZERO, 20000.0):
			for i in f.chunk_trees(c).size():
				var rec := f.chunk_record(c, i)
				if not rec.is_empty() and rec[5]:
					var o := (f.global_transform * (rec[0] as Transform3D)).origin
					spots.append(o)
	var best := -1
	var out := Vector3.ZERO
	for id in sim.network.segments:
		if sim.network.segments[id].type != RoadStyle.Type.STREET:
			continue
		var pts := sim.network.sample_segment(id)
		var mid := pts[pts.size() / 2]
		var m := Vector2(mid.x, mid.z)
		var n := 0
		var y := 0.0
		for s in spots:
			if Vector2(s.x, s.z).distance_squared_to(m) < 2500.0:
				n += 1
				y += s.y
		if n > best:
			best = n
			# The ground there (the trees stand on it; the road's samples
			# are flat).
			out = Vector3(mid.x, y / maxf(n, 1.0), mid.z)
	print("leafiest street: %d grown trees within 50 m of %s (%d grown trees in town)" % [best, out, spots.size()])
	return out
