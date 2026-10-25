extends VehicleModels
## Prototype close-up cars for the close-up lab: the game's Ultra models with
## the glass split off into its own see-through surface, and a cabin behind
## it (dash, wheel, seats, a driver). Glass tint follows Indiana law
## (IC 9-19-19-4: windshield and front side windows let 30% or more light
## through); SUVs and vans carry factory privacy glass behind the B pillar.
## Not used by the game yet: a proposal to compare.

const People := preload("res://tools/closeup/people.gd")
const SEAT := Color(0.13, 0.13, 0.14, 0.3)
const DASH := Color(0.09, 0.09, 0.1, 0.3)

var _glass := SurfaceTool.new()
var _to_glass := false
var cabin := true


static func build_split(kind: String, cabin_on := true, driver_seed := 0) -> ArrayMesh:
	var b = load("res://tools/closeup/cars.gd").new()
	b._hi = true
	b.cabin = cabin_on
	b._seed = driver_seed
	b._st.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	if b.has_method("_" + kind):
		b.call("_" + kind)
	else:
		b._sedan()
	var mesh: ArrayMesh = b._st.commit()
	b._glass.commit(mesh)
	return mesh

var _seed := 0


func _tri_n(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color) -> void:
	if _is_glass(col) and not _to_glass:
		var keep := _st
		_st = _glass
		_to_glass = true
		super._tri_n(a, b, c, na, nb, nc, col)
		_to_glass = false
		_st = keep
		return
	super._tri_n(a, b, c, na, nb, nc, col)


func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color, inside: Vector3) -> void:
	if _is_glass(col) and not _to_glass:
		var keep := _st
		_st = _glass
		_to_glass = true
		super._tri(a, b, c, col, inside)
		_to_glass = false
		_st = keep
		return
	super._tri(a, b, c, col, inside)


func _car(p: Dictionary) -> void:
	super._car(p)
	if cabin:
		_cabin(p)


## Dash, steering wheel, seats and a driver in the left front seat (-X is
## the left side, the car faces -Z when driven; the mesh runs back along +Z).
func _cabin(p: Dictionary) -> void:
	var hw: float = p.W * 0.5
	var belt: float = p.belt
	var floor_y: float = p.clear + 0.18
	var mid: float = (p.b + p.c) * 0.5
	_box(Vector3(0, belt - 0.12, p.a + 0.32), Vector3(p.W - 0.3, 0.22, 0.45), DASH)
	var dx := -hw * 0.42
	var wheel := Vector3(dx, belt + 0.03, p.a + 0.62)
	_cyl(wheel + Vector3(0, -0.03, 0.03), wheel + Vector3(0, 0.03, -0.03), 0.19, DASH, 10)
	var hp := Vector3(0, floor_y + 0.12, mid - 0.15)  # seat cushion top at the hip
	for x in [dx, -dx]:
		_box(Vector3(x, hp.y - 0.08, hp.z - 0.12), Vector3(0.5, 0.14, 0.5), SEAT)
		_box(Vector3(x, hp.y + 0.3, hp.z + 0.16), Vector3(0.5, 0.62, 0.12), SEAT)
		_box(Vector3(x, hp.y + 0.7, hp.z + 0.17), Vector3(0.26, 0.16, 0.09), SEAT)
	if p.c - mid > 0.45:
		_box(Vector3(0, hp.y - 0.06, p.c + 0.05), Vector3(p.W - 0.35, 0.14, 0.5), SEAT)
		_box(Vector3(0, hp.y + 0.28, p.c + 0.3), Vector3(p.W - 0.35, 0.6, 0.12), SEAT)
	# The driver, built from the lab's people at their seated pose, in the
	# vehicle shader's fixed-colour code.
	var shirts := [Color(0.62, 0.16, 0.14), Color(0.16, 0.3, 0.55), Color(0.35, 0.35, 0.38), Color(0.24, 0.42, 0.26), Color(0.85, 0.82, 0.74)]
	var skins := [Color(0.87, 0.7, 0.58), Color(0.62, 0.45, 0.33), Color(0.42, 0.29, 0.2), Color(0.9, 0.76, 0.66)]
	var body: String = ["man", "woman", "older"][_seed % 3]
	var m: Mesh = People.build(2, body, {"sleeve": "long", "hair": "long" if body == "woman" else "short"}, true)
	var arr: Array = m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var hip_y: float = 1.7 * 0.52
	var at := Vector3(dx, hp.y - hip_y + 0.03, hp.z)
	var hair := Color(0.25, 0.17, 0.1) if _seed % 2 == 0 else Color(0.55, 0.45, 0.3)
	for i in verts.size():
		var c: Color = cols[i]
		var col: Color
		if c.a < 0.1:
			col = shirts[_seed % shirts.size()]
		elif c.a < 0.4:
			col = Color(0.2, 0.22, 0.3)
		elif c.a < 0.6:
			col = skins[(_seed / 3) % skins.size()]
		elif c.a < 0.9:
			col = hair
		else:
			col = Color(c.r, c.g, c.b)
		_st.set_color(Color(col.r, col.g, col.b, 0.4))
		_st.set_normal(norms[i])
		_st.add_vertex(verts[i] + at)
