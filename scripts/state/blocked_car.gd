extends VehicleModels
## A 1990s mid-size sedan (Buick Century, Oldsmobile Cutlass Ciera: 4.8 m
## long, 1.75 m wide, 1.38 m high, 2.66 m wheelbase, a squared-off body and
## chrome grille) up on cinder blocks with its wheels off: the stalled
## repair in a run-down yard (LotState "car_blocks"). Built by the traffic's
## own car builder (VehicleModels._car), so it is drawn and lit like every
## car in town, with the wheels swapped for empty wheel wells and bare brake
## rotors, a stack of two 8 x 8 x 16 in blocks under each corner (the body
## up off the grass, daylight under it), the hood propped open over the
## engine bay, and one of its wheels lying flat on the grass beside it.
##
## The mesh's origin is the middle of the car on the ground, nose at -Z.

const L := 4.8
## The body sits this much higher than on its tyres: up on the stacks.
const LIFT := 0.2
const BLOCK := Color(0.56, 0.56, 0.54, 0.4)
const BLOCK_B := Color(0.5, 0.5, 0.48, 0.4)
const SHIM := Color(0.58, 0.47, 0.33, 0.4)
const ROTOR := Color(0.42, 0.33, 0.27, 0.4)  # rusted bare brake rotor
const WELL := Color(0.03, 0.03, 0.03, 0.3)

var _p := {}


static func make(lod := 0) -> ArrayMesh:
	var b = load("res://scripts/state/blocked_car.gd").new()
	b._lo = lod == VehicleModels.LOD_FAR
	b._st.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._p = {"L": L, "W": 1.75, "H": 1.38, "clear": 0.17, "hood": 0.8, "belt": 0.95, "a": 1.35,
		"b": 2.05, "c": 3.2, "e": 3.9, "tail": 0.98, "wr": 0.33, "axles": [0.98, 3.64], "grille": VehicleModels.CHROME}
	b._car(b._p)
	var mesh: ArrayMesh = b._st.commit()
	# Lifted onto the blocks (which stand on the ground) and centred.
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] += Vector3(0.0, LIFT, -L * 0.5)
	arrays[Mesh.ARRAY_VERTEX] = v
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## No wheels: the empty wells and the bare rotors.
func _wheels(axles: Array, r: float, hw: float, _w: float) -> void:
	for z in axles:
		for s in [-1.0, 1.0]:
			var x: float = s * (hw + 0.004)
			# The well, open from the rocker to over where the tyre was.
			var c := Vector3(x, r, z)
			_arch(c, r + 0.07, s)
			var lo := Vector3(x, float(_p.clear) - 0.02, z)
			_quad(lo + Vector3(0, 0, -r - 0.07), lo + Vector3(0, r - float(_p.clear) + 0.02, -r - 0.07),
				lo + Vector3(0, r - float(_p.clear) + 0.02, r + 0.07), lo + Vector3(0, 0, r + 0.07), WELL,
				c - Vector3(s, 0, 0))
			if not _lo:
				_disc(c + Vector3(s * 0.006, 0, 0), Vector3(s, 0, 0), 0.15, ROTOR)
				_disc(c + Vector3(s * 0.01, 0, 0), Vector3(s, 0, 0), 0.06, Color(0.2, 0.2, 0.2, 0.2))


func _car(p: Dictionary) -> void:
	super._car(p)
	# The stacks, on the ground under each hub (drawn LIFT lower, as the
	# whole mesh is lifted after): two blocks laid flat, holes up, and a
	# wood shim on top.
	var hw: float = float(p.W) * 0.5
	for z in p.axles:
		for s in [-1.0, 1.0]:
			var x: float = s * (hw - 0.16)
			_box(Vector3(x, 0.1 - LIFT, z), Vector3(0.4, 0.2, 0.2), BLOCK)
			_box(Vector3(x, 0.3 - LIFT, z), Vector3(0.2, 0.2, 0.4), BLOCK_B)
			_box(Vector3(x, 0.415 - LIFT, z), Vector3(0.18, 0.03, 0.3), SHIM)
	# The hood propped open on its stay, the dark engine bay under it.
	var hood: float = p.hood
	var a: float = p.a
	_box(Vector3(0, hood + 0.005, a * 0.5 + 0.08), Vector3(float(p.W) - 0.34, 0.03, a - 0.36), Color(0.05, 0.05, 0.05, 0.3))
	_box(Vector3(-0.22, hood + 0.03, a * 0.45), Vector3(0.5, 0.06, 0.45), Color(0.22, 0.22, 0.23, 0.2))
	var pivot := Vector3(0, hood + 0.06, a - 0.12)
	var lid := Basis(Vector3.RIGHT, 0.8)
	_obox(pivot + lid * Vector3(0, 0, -(a - 0.2) * 0.5), Vector3(float(p.W) - 0.3, 0.035, a - 0.2), lid, VehicleModels.PAINT)
	_box(Vector3(0.55, hood + 0.35, 0.45), Vector3(0.02, 0.7, 0.02), VehicleModels.STEEL)
	# A wheel off, lying flat on the grass by the rear corner.
	var t := Vector3(hw + 0.55, -LIFT, float(p.L) - 1.0)
	_cyl(t, t + Vector3(0, 0.2, 0), 0.32, VehicleModels.TIRE, 12)
	_disc(t + Vector3(0, 0.205, 0), Vector3.UP, 0.19, VehicleModels.RIM)


## A box turned by `b` about its centre `c`.
func _obox(c: Vector3, size: Vector3, b: Basis, col: Color) -> void:
	var h := size * 0.5
	var v := []
	for k in 8:
		v.append(c + b * Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
	for f in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		_quad(v[f[0]], v[f[1]], v[f[2]], v[f[3]], col, c)
