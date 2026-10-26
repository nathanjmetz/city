class_name NearMeshes
extends RefCounted
## The unit pieces the close-up detail (NearDetail) is laid with, made once
## and shared by every building: 16 in masonry cells (brick by brick), a
## lap siding board, a course of shingles and a flat backing quad. Each
## building is then only instance transforms of these
## (docs/scale-test-2026-10-25.md, "The new drawing style, measured"; from
## the lab in tools/scale/new_drawing/meshes.gd).

## Modular brick (ASTM C216 / BIA): 7 5/8 x 2 1/4 x 3 5/8 in, laid so three
## courses rise 8 in; walls lay out on the mason's 16 in module.
const BRICK_H := 0.05715
const BRICK_D := 0.092075
const HEAD_J := 0.009525          # 3/8 in head joint
const COURSE := 0.0677333         # 8 in / 3
const CELL := 0.4064              # 16 in: two bricks across, six courses up
## Lap siding, 4 in to the weather; asphalt shingles, 5 in.
const LAP := 0.1016
const SHINGLE := 0.127

static var _cache := {}


## Collects one surface: positions, normals, UV2, indices (and, for a
## masonry cell, a lighter index list of just the faces).
class Builder:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var lite := PackedInt32Array()

	## A flat quad a, b, c, d (counter-clockwise seen from its front).
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t2 := Vector2.ZERO, face := false) -> void:
		var nn := (b - a).cross(d - a).normalized()
		var base := v.size()
		for p in [a, b, c, d]:
			v.append(p)
			n.append(nn)
			uv2.append(t2)
		# Godot's front faces wind clockwise as seen from the front.
		for k in [0, 2, 1, 0, 3, 2]:
			idx.append(base + k)
			if face:
				lite.append(base + k)

	func commit(lods := {}) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if v.is_empty():
			return mesh
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TEX_UV2] = uv2
		a[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], lods)
		return mesh


## A masonry cell, 16 x 16 in of brick in running bond (two across, six
## courses). variant: "inner" (its offset courses reach half a brick into
## the cell to the left), "start" (cut square at its left: the wall's
## start), "end" (filled to its right edge), "solo" (both), "inner2" (other
## chips). Front face at z = 0, back into the wall (-z). UV2 is each
## brick's middle, so the shader can give every brick its own colour.
static func masonry(variant: String) -> ArrayMesh:
	var key := "m_" + variant
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var P := CELL
	var unit_l := P * 0.5
	var j := HEAD_J
	var start := variant in ["start", "solo"]
	var fill_end := variant in ["end", "solo"]
	for r in 6:
		var y := r * COURSE
		var xs := []  # [x0, x1]
		if r % 2 == 0:
			var x := 0.0
			while x < P - 0.001:
				var x1 := x + unit_l - j
				if fill_end and x + unit_l >= P - 0.001:
					x1 = P
				xs.append([x, x1])
				x += unit_l
		else:
			var x := -unit_l * 0.5
			if start:
				xs.append([0.0, unit_l * 0.5 - j])
				x = unit_l * 0.5
			while x < P - unit_l * 0.5 - 0.001:
				xs.append([x, x + unit_l - j])
				x += unit_l
			if fill_end:
				xs.append([P - unit_l * 0.5, P])
		for s in xs:
			_unit(b, rng, Vector3(s[0], y, 0.0), Vector3(s[1] - s[0], BRICK_H, BRICK_D))
	# Past a few pixels a brick, only the faces: the joints' shadows are gone.
	var mesh := b.commit({0.012: b.lite})
	_cache[key] = mesh
	return mesh


## One brick: a beveled unit a hair off square, a corner chipped now and
## then (as in the brick lab, 2026-10-25). Only what shows from outside:
## the face, the bevels and the sides as deep as the joints are.
static func _unit(b: Builder, rng: RandomNumberGenerator, at: Vector3, size: Vector3) -> void:
	var jit := Vector3(rng.randf_range(-0.0012, 0.0012), rng.randf_range(-0.0008, 0.0008), rng.randf_range(-0.0015, 0.001))
	var s := size + Vector3(rng.randf_range(-0.002, 0.0015), rng.randf_range(-0.001, 0.001), 0)
	var o := at + jit
	var bv := 0.003
	var back := 0.012  # the mortar sits this far back of the face
	var f := [Vector3(o.x + bv, o.y + bv, o.z), Vector3(o.x + s.x - bv, o.y + bv, o.z),
		Vector3(o.x + s.x - bv, o.y + s.y - bv, o.z), Vector3(o.x + bv, o.y + s.y - bv, o.z)]
	var e := [Vector3(o.x, o.y, o.z - bv), Vector3(o.x + s.x, o.y, o.z - bv), Vector3(o.x + s.x, o.y + s.y, o.z - bv),
		Vector3(o.x, o.y + s.y, o.z - bv)]
	var k := [Vector3(o.x, o.y, o.z - back), Vector3(o.x + s.x, o.y, o.z - back),
		Vector3(o.x + s.x, o.y + s.y, o.z - back), Vector3(o.x, o.y + s.y, o.z - back)]
	for i in 4:
		if rng.randf() < 0.18:
			f[i] = f[i].lerp(e[i], 0.9) + Vector3(0, 0, -rng.randf_range(0.001, 0.004))
	for i in 4:
		f[i].z += rng.randf_range(-0.0007, 0.0007)
	var mid := Vector2(o.x + s.x * 0.5, o.y + s.y * 0.5)
	b.quad(f[0], f[1], f[2], f[3], mid, true)
	for i in 4:
		var nx := (i + 1) % 4
		b.quad(e[i], e[nx], f[nx], f[i], mid)
		b.quad(k[i], k[nx], e[nx], e[i], mid)


## A course of "double 4" vinyl siding, 1 m long (scaled to its run): an
## 8 in panel shaped as two 4 in laps, each face leaning out to its butt,
## the lower one a full 1/2 in, the upper a shallower false lap, as the
## panels on most Indiana houses are. UV2.y is how far up the panel.
static func board() -> ArrayMesh:
	if _cache.has("board"):
		return _cache.board
	var b := Builder.new()
	var t := 0.013
	var t2 := 0.009
	var top := 2.0 * LAP + 0.006
	b.quad(Vector3(0, 0, t), Vector3(1, 0, t), Vector3(1, LAP, 0.002), Vector3(0, LAP, 0.002))
	b.quad(Vector3(0, LAP, 0.002), Vector3(1, LAP, 0.002), Vector3(1, LAP, t2), Vector3(0, LAP, t2))
	b.quad(Vector3(0, LAP, t2), Vector3(1, LAP, t2), Vector3(1, top, 0.001), Vector3(0, top, 0.001))
	b.quad(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, t), Vector3(0, 0, t))
	_cache.board = b.commit()
	return _cache.board


## A course of shingles, 1 m long (scaled), laid up the slope (+y) on the
## roof (+z out): the exposed 5 in and the butt edge.
static func shingle() -> ArrayMesh:
	if _cache.has("shingle"):
		return _cache.shingle
	var b := Builder.new()
	var t := 0.008
	var top := SHINGLE + 0.02
	b.quad(Vector3(0, 0, t), Vector3(1, 0, t), Vector3(1, top, 0.0), Vector3(0, top, 0.0))
	b.quad(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, t), Vector3(0, 0, t))
	_cache.shingle = b.commit()
	return _cache.shingle


## A unit quad, x and y from 0 to 1, facing +z: the mortar behind a brick
## wall, scaled to the wall.
static func backing() -> ArrayMesh:
	if _cache.has("backing"):
		return _cache.backing
	var b := Builder.new()
	b.quad(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0))
	_cache.backing = b.commit()
	return _cache.backing


## The shared mesh for an instance kind (NearDetail's layer names).
static func of(kind: String) -> ArrayMesh:
	match kind:
		"board": return board()
		"shingle": return shingle()
		"mortar": return backing()
	return masonry(kind.trim_prefix("brick_"))
