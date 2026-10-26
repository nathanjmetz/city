class_name TelecomView
extends Node3D
## Draws the phone company: its central office and each block of land it
## has bought, every cell tower with its fenced compound and gravel drive,
## and the orange marker posts that show where fiber runs along a street
## (real buried and aerial fiber is marked with "CAUTION FIBER OPTIC CABLE"
## posts). Rebuilt only for what changed; TelecomBuilder makes the art.

## Spacing of fiber marker posts along a street, metres.
const POST_EVERY := 150.0

var sim: CitySim
var _nodes := {}  # key -> Node3D
var _trees := TreeField.new()
var _posts := MultiMeshInstance3D.new()
var _post_sig := ""


func setup(s: CitySim) -> void:
	sim = s
	add_child(_trees)
	var post := BoxMesh.new()
	post.size = Vector3(0.1, 1.3, 0.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#e8711c")  # safety orange
	mat.roughness = 0.7
	post.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post
	_posts.multimesh = mm
	_posts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_posts)
	sim.telecom_changed.connect(_sync)
	_sync()


func _sync() -> void:
	var want := {}
	for id in sim.telecom.companies:
		var c: Dictionary = sim.telecom.companies[id]
		want["%d:main:%.1f:%.1f" % [id, c.pos.x, c.pos.z]] = [c, null, null]
		for blk in c.blocks:
			want["%d:%d,%d:%s:%d:%.1f:%.1f" % [id, blk.c.x, blk.c.y, blk.use, blk.levels, c.pos.x, c.pos.z]] = [c, blk, null]
		for t in c.towers:
			want["%d:tower:%s:%.1f:%.1f:%s" % [id, t.kind, t.pos[0], t.pos[1], ",".join(c.built)]] = [c, null, t]
		# Its edge pieces up to the sidewalk (BlockEdges), drawn together.
		if not c.get("edge", {}).is_empty():
			want["%d:edge:%d:%.1f:%.1f" % [id, hash([c.edge, c.blocks]), c.pos.x, c.pos.z]] = [c, "edge", null]
		if "small_cells" in c.built:
			for q in small_cells(c):
				want["%d:cell:%.1f:%.1f" % [id, q[0].x, q[0].z]] = [c, null, q]
	for key in _nodes.keys():
		if not want.has(key):
			_trees.remove(key)
			_nodes[key].queue_free()
			_nodes.erase(key)
	for key in want:
		if not _nodes.has(key):
			var w: Array = want[key]
			if w[1] is String:
				var c: Dictionary = w[0]
				var cells := [Vector2i.ZERO]
				for blk in c.blocks:
					cells.append(blk.c)
				_nodes[key] = EdgeGrounds.place(self, _trees, key, c, Telecom.CELL,
					TelecomBuilder.build_edge(c.edge, cells, absi(hash(key))))
			elif w[2] is Array:
				_nodes[key] = _spawn_cell(key, w[2])
			else:
				_nodes[key] = _spawn_tower(key, w[0], w[2]) if w[2] != null else _spawn(key, w[0], w[1])
	_sync_posts()


func _spawn(key: String, c: Dictionary, blk) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	# Local -Z faces the office's street.
	root.basis = Basis.looking_at(c.dir, Vector3.UP)
	var cell: Vector2i = Vector2i.ZERO if blk == null else blk.c
	root.position = Terrain.lift(Telecom.block_center(c, cell))
	var seed := absi(hash(key))
	var built: Array
	if blk == null:
		var to_curb := Services.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
		built = TelecomBuilder.build_office(seed, to_curb, c.built)
	else:
		built = TelecomBuilder.build_block(Telecom.dev(blk.use).get("land", "garage"), blk.levels, seed)
	_finish(key, root, built)
	return root


## A tower stands square to the road its drive comes in from.
func _spawn_tower(key: String, c: Dictionary, t: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var p := Vector3(t.pos[0], 0.0, t.pos[1])
	var drive := 0.0
	var dir := Vector3.FORWARD
	var near := sim.network.find_segment_near(p, Balance.TELECOM_TOWER_ROAD + 20.0)
	if not near.is_empty():
		var to: Vector3 = near.point - p
		to.y = 0.0
		if to.length() > 1.0:
			dir = to.normalized()
			drive = maxf(0.0, to.length() - Balance.TELECOM_COMPOUND * 0.5
				- RoadStyle.half_width(sim.network.segments[near.seg].type))
	# The yard tower sits behind the office, which has its own drive.
	var yt := Telecom.yard_tower(c)
	if yt.distance_to(Vector2(p.x, p.z)) < 1.0:
		dir = c.dir
		drive = 0.0
	root.basis = Basis.looking_at(dir, Vector3.UP)
	root.position = Terrain.lift(p)
	var kind: String = t.kind
	if kind == "monopole" and "stealth" in c.built and sim.telecom._homes_within(sim, Vector2(p.x, p.z), 250.0):
		# Stealth retrofit: branch kits dress the old pole near homes as a pine.
		kind = "monopine"
	if kind != "monopine" and "lte_5g" in c.built:
		kind += "_5g"
	_finish(key, root, TelecomBuilder.build_tower(kind, absi(hash(key)), drive, "fixed_wireless" in c.built))
	return root


## Where a company's small cells stand: on its fiber streets nearest its
## office (downtown), one between each pair of marker posts, up to eight. Each is
## [foot of the pole, toward the street].
static func small_cells(c: Dictionary) -> Array:
	var out := []
	for f in c.fiber:
		var pts: Array = f.pts
		for i in range(1, pts.size()):
			var a := Vector3(pts[i - 1][0], 0, pts[i - 1][1])
			var b := Vector3(pts[i][0], 0, pts[i][1])
			var len := a.distance_to(b)
			if len < 1.0:
				continue
			var run := POST_EVERY
			while run <= len:
				var q := a.lerp(b, run / len)
				if q.distance_to(c.pos) < 600.0:
					var along := (b - a) / len
					out.append([q, Vector3(along.z, 0, -along.x)])
				run += POST_EVERY
	out.sort_custom(func(x, y): return x[0].distance_squared_to(c.pos) < y[0].distance_squared_to(c.pos))
	return out.slice(0, 8)


func _spawn_cell(key: String, q: Array) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var side: Vector3 = q[1]
	var seg := sim.network.find_segment_near(q[0], 40.0)
	var off := 6.0
	if not seg.is_empty():
		off = RoadStyle.right_of_way_half(sim.network.segments[seg.seg].type) - 0.6
	root.basis = Basis.looking_at(side, Vector3.UP)
	root.position = Terrain.lift(q[0] - side * off)
	_finish(key, root, TelecomBuilder.build_small_cell(absi(hash(key))))
	return root


func _finish(key: String, root: Node3D, built: Array) -> void:
	var building := MeshInstance3D.new()
	building.mesh = built[0]
	root.add_child(building)
	var ground := MeshInstance3D.new()
	ground.mesh = Terrain.drape_local(built[1], Transform3D(root.basis, root.position))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	var frame := Transform3D(root.basis, root.position)
	var trees := []
	for t in built[2]:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		var at: Transform3D = frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0])
		at.origin.y = Terrain.ground_y(at.origin.x, at.origin.z)
		trees.append([at, t[1], t[2]])
	_trees.set_trees(key, trees)
	root.scale = Vector3(1.0, 0.01, 1.0)
	create_tween().tween_property(root, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Orange marker posts along every fiber street, at the edge of its right
## of way, one side only (where the line runs).
func _sync_posts() -> void:
	var xforms := []
	for id in sim.telecom.companies:
		for f in sim.telecom.companies[id].fiber:
			if not sim.network.segments.has(int(f.seg)):
				continue
			var off := RoadStyle.right_of_way_half(sim.network.segments[int(f.seg)].type) - 0.4
			var pts: Array = f.pts
			var run := POST_EVERY * 0.5
			for i in range(1, pts.size()):
				var a := Vector2(pts[i - 1][0], pts[i - 1][1])
				var b := Vector2(pts[i][0], pts[i][1])
				var len := a.distance_to(b)
				if len < 0.01:
					continue
				var side := Vector2(-(b - a).y, (b - a).x) / len
				while run <= len:
					var q := a.lerp(b, run / len) + side * off
					xforms.append(Transform3D(Basis.IDENTITY, Vector3(q.x, Terrain.ground_y(q.x, q.y) + 0.65, q.y)))
					run += POST_EVERY
				run -= len
	var sig := str(xforms.size()) + ":" + (str(xforms[0].origin) if not xforms.is_empty() else "")
	if sig == _post_sig:
		return
	_post_sig = sig
	var mm := _posts.multimesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
