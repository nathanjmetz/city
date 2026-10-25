extends Node3D
## The town's buildings drawn the new way (a measuring prototype for
## tools/scale/new_drawing_lab.gd; the game itself still draws with
## BuildingView): small facts per building (facts.gd), every building as
## instanced shapes with the lighter middle version's pieces near enough
## (town_layer.gd), and real-size grown detail within about 100 m
## (near_ring.gd). Yard and street trees go to a TreeField as today.
##
## The town changes while it plays: a change marks the view, and the next
## frames look the buildings over in slices, re-deriving the facts of any
## that changed and rebuilding their squares a few a frame.

const Facts := preload("res://tools/scale/new_drawing/facts.gd")
const TownLayer := preload("res://tools/scale/new_drawing/town_layer.gd")
const NearRing := preload("res://tools/scale/new_drawing/near_ring.gd")

var sim: CitySim
var facts := {}  # key -> facts
var layer: Node3D
var near: Node3D
var trees := TreeField.new()
var _dirty := false
var _scan: Array = []  # keys still to look over
## Work per frame on keeping up with the town (ms).
const SYNC_MS := 1.5


func setup(s: CitySim) -> void:
	sim = s
	layer = TownLayer.new()
	layer.facts = facts
	add_child(layer)
	near = NearRing.new()
	near.facts = facts
	near.layer = layer
	add_child(near)
	add_child(trees)
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		near.budget_ms = 2.0
	for key in sim.buildings:
		_add(key)
	layer.rebuild_all()
	sim.buildings_changed.connect(func(): _dirty = true)
	sim.lots_changed.connect(func(): _dirty = true)


func _add(key: String) -> void:
	var f := Facts.of(sim, key)
	if f.is_empty():
		return
	facts[key] = f
	layer.add(key)
	near.index(key)
	_plant(key, f)


func _remove(key: String) -> void:
	near.unindex(key)
	layer.remove(key)
	facts.erase(key)
	trees.remove(key)


func _process(_d: float) -> void:
	var t := Perf.now()
	_sync()
	Perf.add("frame.nd_sync", t)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		t = Perf.now()
		near.update(cam.global_position)
		Perf.add("frame.nd_near", t)
	Perf.count("nd.grown", near.grown_count())


func _sync() -> void:
	var start := Time.get_ticks_usec()
	var limit := int(SYNC_MS * 1000.0)
	if _dirty and _scan.is_empty():
		_dirty = false
		_scan = sim.buildings.keys()
		for key in facts:
			if not sim.buildings.has(key) or not sim.lots.has(key):
				_scan.append(key)
	while not _scan.is_empty() and Time.get_ticks_usec() - start < limit:
		var key: String = _scan.pop_back()
		var have := facts.has(key)
		var there: bool = sim.buildings.has(key) and sim.lots.has(key)
		if have and not there:
			_remove(key)
		elif there and not have:
			_add(key)
		elif have and facts[key].look != Facts.look(sim.buildings[key]):
			_remove(key)
			_add(key)
	if layer.has_dirty():
		layer.rebuild_some(maxi(limit - (Time.get_ticks_usec() - start), 300))


## A front-yard tree, a street tree and one or two out back for a home; a
## street tree for a shop (HouseBuilder's yard rules, kept clear of walls).
func _plant(key: String, f: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f.seed) ^ 0x7ee5
	var spots := []
	var half: float = f.lot_w * 0.5 - 2.0
	var lot_front: float = f.front_z - f.setback
	var type: String = f.type
	if type in ["house", "row_home", "apartments"]:
		if rng.randf() < 0.7 and f.setback > 5.0:
			spots.append([Vector3(rng.randf_range(-half, half), 0, rng.randf_range(lot_front + 1.5, f.front_z - 3.5)), true])
		if rng.randf() < 0.55:
			spots.append([Vector3(rng.randf_range(-half, half), 0, lot_front - f.to_curb + 1.2), false])
		var back: float = f.d * 0.5 + 3.0
		var lot_back: float = lot_front + f.lot_d - 2.0
		if lot_back > back + 1.0:
			for i in rng.randi_range(1, 2):
				spots.append([Vector3(rng.randf_range(-half, half), 0, rng.randf_range(back, lot_back)), false])
	elif type in ["shop", "mixed_use", "office"] and rng.randf() < 0.5:
		spots.append([Vector3(rng.randf_range(-half, half), 0, lot_front - f.to_curb + 1.2), false])
	var out := []
	for s in spots:
		var p: Vector3 = s[0]
		if absf(p.x - f.drive_x) < 3.5 and p.z < f.front_z + 6.0:
			continue
		var pick := TreeField.pick(rng, s[1])
		var size := rng.randf_range(0.75, 1.15)
		var gap := maxf(absf(p.x) - f.w * 0.5, absf(p.z) - f.d * 0.5)
		if gap < TreeField.SPREAD[pick[0]] * size * 0.9:
			if not s[1]:
				continue
			pick[0] = TreeField.Species.CRABAPPLE
			pick[1] = TreeField.LEAF[pick[0]]
			size = minf(size, 0.9)
			if gap < TreeField.SPREAD[pick[0]] * size * 0.9:
				continue
		var w: Vector3 = f.centre + f.basis * p
		w.y = Terrain.ground_y(w.x, w.z)
		var yaw := Basis(Vector3.UP, fposmod(w.x * 7.3 + w.z * 3.1, TAU))
		out.append([Transform3D(yaw.scaled(Vector3.ONE * size), w), pick[0], pick[1]])
	if not out.is_empty():
		trees.set_trees(key, out)
