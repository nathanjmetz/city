class_name WaterView
extends Node3D
## Draws each water utility's yard as it grows (wells, the tower, plants,
## the lagoon) and, while the utility is selected or being placed, its pipes
## under the streets: water mains in blue, sewers in brown.

const MAIN_COLOR := Color(0.25, 0.55, 1.0, 0.85)
const SEWER_COLOR := Color(0.6, 0.42, 0.22, 0.85)

var sim: CitySim
var select_tool: SelectTool
var service_tool: ServiceTool

var _pieces := {}  # "id:key:x:y" -> Node3D
var _pipes := MeshInstance3D.new()
var _pipe_for := -2
var _mats := {}


func setup(s: CitySim, select: SelectTool, tool: ServiceTool) -> void:
	sim = s
	select_tool = select
	service_tool = tool
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	_pipes.material_override = m
	_pipes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pipes)
	sim.water_changed.connect(_sync)
	sim.lots_changed.connect(_sync)
	select.selected.connect(func(_sel): _pipe_for = -2)
	_sync()


func _process(_delta: float) -> void:
	var want := -1
	var sel: Dictionary = select_tool.selection
	if sel.get("type", "") == "water":
		want = int(sel.id)
	elif service_tool.kind == Services.Kind.WATER_UTILITY:
		want = 0  # placing one: show every utility's pipes
	if want != _pipe_for:
		_pipe_for = want
		_draw_pipes()


func _sync() -> void:
	var want := {}
	var w := sim.services.water
	for id in w.utilities:
		if not sim.services.buildings.has(id):
			continue
		var b: Dictionary = sim.services.buildings[id]
		for wk in w.utilities[id].works:
			var c: Vector2i = wk[1]
			if c == Vector2i.ZERO or c.x <= -99:
				continue
			var built: Array = w.utilities[id].get("built", [])
			want["%d:%s:%d:%d:%d" % [id, wk[0], c.x, c.y, built.size()]] = [b, wk[0], c, built]
	for k in _pieces.keys():
		if not want.has(k):
			_pieces[k].queue_free()
			_pieces.erase(k)
	for k in want:
		if not _pieces.has(k):
			_pieces[k] = _spawn(want[k][0], want[k][1], want[k][2], want[k][3])
	_pipe_for = -2


func _spawn(b: Dictionary, key: String, c: Vector2i, built := []) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = Terrain.lift(WaterUtility.cell_center(b, c))
	root.basis = Basis.looking_at(b.dir, Vector3.UP)
	var size := Vector2(WaterUtility.CELL, WaterUtility.CELL)
	var seed := int(root.position.x * 31.0) ^ int(root.position.z * 17.0)
	match key:
		"well":
			_civic(root, Services.Kind.WELL, seed, Vector2(20, 20))
		"tower":
			_civic(root, Services.Kind.WATER_TOWER, seed, Vector2(30, 30))
			if "meters" in built:
				# Smart meters read by radio (AMI): the collector's antenna on
				# the tank's catwalk rail and its cabinet at the foot.
				_box(root, Vector3(0.12, 3.0, 0.12), Vector3(10.3, 37.0, 0), Color("#9ea3a6"))
				_box(root, Vector3(0.5, 0.7, 0.3), Vector3(10.3, 35.4, 0.3), Color("#d8dadb"))
				_box(root, Vector3(0.8, 1.4, 0.5), Vector3(3.0, 0.7, -3.0), Color("#8d918f"))
			if "industrial_main" in built:
				# The big main to industry leaves through a valve vault and an
				# above-ground backflow preventer in an insulated "hot box".
				_box(root, Vector3(2.6, 0.12, 2.0), Vector3(-9.0, 0.06, -11.0), Color("#8d8f8c"))
				_box(root, Vector3(3.6, 1.6, 1.6), Vector3(-9.0, 0.9, -7.5), Color("#c9b98f"))
				_box(root, Vector3(0.8, 0.8, 9.0), Vector3(-9.0, 0.4, -1.5), Color("#3a5a8a"))
		"lagoon":
			# Two cells of a facultative lagoon behind a grassed berm.
			_box(root, Vector3(36, 1.2, 36), Vector3(0, 0.6, 0), Color("#6f8a4a"))
			_box(root, Vector3(16, 0.05, 32), Vector3(-8.5, 1.21, 0), Color("#4d6a5e"))
			_box(root, Vector3(16, 0.05, 32), Vector3(8.5, 1.21, 0), Color("#5a7356"))
		"plant":
			# Activated sludge: aeration basins and two round clarifiers.
			_box(root, Vector3(36, 0.2, 36), Vector3(0, 0.1, 0), Color("#b9b5ab"))
			_box(root, Vector3(22, 2.5, 10), Vector3(-5, 1.25, -10), Color("#a9a59a"))
			_box(root, Vector3(21, 0.05, 9), Vector3(-5, 2.52, -10), Color("#5d6e5a"))
			for x in [-10.0, 8.0]:
				_cyl(root, 6.5, 2.2, Vector3(x, 1.1, 8), Color("#aaa69c"))
				_cyl(root, 6.0, 0.05, Vector3(x, 2.22, 8), Color("#62746a"))
			_box(root, Vector3(7, 4, 6), Vector3(13, 2, -11), Color("#c9c2b2"))
			if "nutrient" in built:
				# Nutrient removal: an anoxic tank ahead of the aeration
				# basins, and a covered UV disinfection channel at the outfall.
				_box(root, Vector3(22, 2.5, 3.4), Vector3(-5, 1.25, -3.2), Color("#a9a59a"))
				_box(root, Vector3(21, 0.05, 2.8), Vector3(-5, 2.52, -3.2), Color("#4f6a5e"))
				_box(root, Vector3(1.8, 1.4, 8.0), Vector3(15.5, 0.7, -2.0), Color("#b9b5ab"))
				_box(root, Vector3(2.0, 0.15, 8.2), Vector3(15.5, 1.5, -2.0), Color("#7d8a93"))
			if "biosolids" in built:
				# Biosolids: a covered sludge holding tank with a truck
				# loading spout, for the farms' spreader trucks.
				_cyl(root, 2.4, 5.0, Vector3(15.0, 2.5, 14.0), Color("#c9c6bb"))
				_cyl(root, 2.5, 0.4, Vector3(15.0, 5.2, 14.0), Color("#8e9aa3"))
				_box(root, Vector3(0.4, 0.4, 3.0), Vector3(15.0, 3.6, 10.8), Color("#6b6f73"))
		"filtration", "intake":
			# A brick treatment building with filter tanks beside it.
			_box(root, Vector3(36, 0.2, 36), Vector3(0, 0.1, 0), Color("#b9b5ab"))
			_box(root, Vector3(20, 7, 14), Vector3(-6, 3.5, -6), Color("#8a4a38"))
			_box(root, Vector3(20.6, 0.4, 14.6), Vector3(-6, 7.2, -6), Color("#4a4a48"))
			for i in (3 if key == "filtration" else 4):
				_cyl(root, 2.4, 6.0, Vector3(10, 3, -12 + i * 7), Color("#d8dadb"))
			if key == "intake":
				_cyl(root, 9.0, 3.0, Vector3(-6, 1.5, 11), Color("#aaa69c"))
		"training":
			_box(root, Vector3(18, 4.5, 12), Vector3(0, 2.25, -6), Color("#b8b2a4"))
			_box(root, Vector3(30, 0.1, 14), Vector3(0, 0.05, 10), Color("#3a3c3e"))
		"wholesale":
			# The interconnect: a meter vault, a booster pump house and the line out.
			_box(root, Vector3(8, 3.2, 6), Vector3(0, 1.6, 0), Color("#a8775c"))
			_box(root, Vector3(4, 0.4, 4), Vector3(8, 0.2, 0), Color("#8d8f8c"))
			_box(root, Vector3(1.2, 1.2, 30), Vector3(-6, 0.6, 0), Color("#3a5a8a"))
		"reuse":
			_box(root, Vector3(30, 0.2, 30), Vector3(0, 0.1, 0), Color("#b9b5ab"))
			_cyl(root, 7.0, 7.0, Vector3(-6, 3.5, 0), Color("#7d9cb0"))
			_box(root, Vector3(9, 4, 7), Vector3(9, 2, -6), Color("#c9c2b2"))
	return root


func _civic(root: Node3D, kind: int, seed: int, size: Vector2) -> void:
	var built := CivicBuilder.build_service(kind, seed, size, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = built[0]
	root.add_child(mi)
	var ground := MeshInstance3D.new()
	ground.mesh = Terrain.drape_local(built[1], Transform3D(root.basis, root.position))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	root.tree_exiting.connect(ground.queue_free)


func _mat(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_mats[c] = m
	return _mats[c]


func _box(root: Node3D, size: Vector3, at: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = _mat(c)
	root.add_child(mi)


func _cyl(root: Node3D, r: float, h: float, at: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 24
	mi.mesh = cm
	mi.position = at
	mi.material_override = _mat(c)
	root.add_child(mi)


## Pipes as thin coloured lines down the street, mains on one side of the
## centre line and sewers on the other, as utilities lay them.
func _draw_pipes() -> void:
	var w := sim.services.water
	_pipes.visible = _pipe_for != -1
	if not _pipes.visible:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for id in w.utilities:
		if _pipe_for > 0 and id != _pipe_for:
			continue
		for entry in [["mains", MAIN_COLOR, -2.2], ["sewers", SEWER_COLOR, 2.2]]:
			st.set_color(entry[1])
			for line in w.utilities[id][entry[0]]:
				var pts := PackedVector3Array()
				for p in line:
					pts.append(Vector3(p.x, 0.0, p.y))
				RoadMesh.add_strip(st, pts, entry[2] - 0.6, entry[2] + 0.6, 0.45)
				any = true
	_pipes.visible = any
	if any:
		_pipes.mesh = Terrain.drape(st.commit())
