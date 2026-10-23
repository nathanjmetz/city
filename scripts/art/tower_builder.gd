class_name TowerBuilder
extends DenseBuilder
## Downtown towers, one builder for every era, sized by the lot and the
## storeys the owner builds (Brawn's metro plan: everything has a real
## reference). Benchmarked against:
##   - chicago: the Chicago School, 1885-1910 (Rookery, Reliance, Marquette,
##     Indianapolis's Majestic): a two-storey stone base, a brick or terra
##     cotta shaft of bays with "Chicago windows" (a wide fixed pane between
##     two narrow sashes) between continuous piers, an attic storey and a
##     deep projecting cornice; a timber water tank on the roof
##   - deco: 1920s setback towers under the 1916 zoning (Circle Tower in
##     Indianapolis, the Chicago Board of Trade): limestone, unbroken
##     vertical piers with dark recessed spandrels, setbacks above the
##     street wall and a stepped crown
##   - glass: postwar International Style (860-880 Lake Shore Drive, the
##     Indiana State Office Building): a tinted curtain wall hung from
##     steel I-beam mullions about 1.6 m apart, set back on a plaza over a
##     recessed lobby on columns, with a louvred mechanical floor on top
## Same output as the other builders: [building, ground work, trees, labels].

const TW_STONE := ["#9c9384", "#8b8476", "#a89f8e"]  # granite or rusticated limestone
const TW_SHAFT := ["#c9b48a", "#b89b72", "#8a4a38", "#9b5a42", "#d8ccb0"]  # buff or red brick, terra cotta
const TW_LIMESTONE := ["#d9d0bc", "#cfc6b0", "#e2dac8"]
const TW_SPANDREL := ["#4e4a44", "#5e5a52", "#3f4448"]
const TW_STEEL := Color("#1d1f21")  # Mies's black-painted steel
const TW_TANK := Color("#6b4f36")


var _far := false  # only the massing, for far away (build_far)
var _homes := false  # an apartment tower: balconies, no business sign


## The era follows the street's (prewar streets get masonry towers; a tall
## prewar tower is a setback Deco one).
static func build_tower(seed: int, to_curb: float, lot: Dictionary, storeys: int, spec := {}, era_pick := "", homes := false) -> Array:
	var b := _tw_start(seed, to_curb, lot, storeys, spec, era_pick, false, homes)
	return b._done()


## The same tower as build_tower (same origin, footprint and heights) as a
## few boxes for distant views: walls carry a window grid in the "far"
## shader, a couple of hundred triangles at most.
static func build_far(seed: int, to_curb: float, lot: Dictionary, storeys: int, era_pick := "", homes := false) -> ArrayMesh:
	var b := _tw_start(seed, to_curb, lot, storeys, {}, era_pick, true, homes)
	return b._commit_house()


static func _tw_start(seed: int, to_curb: float, lot: Dictionary, storeys: int, spec: Dictionary, era_pick: String, far: bool, homes: bool) -> TowerBuilder:
	var b := TowerBuilder.new()
	b._far = far
	b._homes = homes
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b.sign_spec = spec
	b._fit(lot)
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kind := era_pick
	if kind == "":
		if b.era == "prewar":
			kind = "deco" if storeys >= 14 or b.rng.randf() < 0.3 else "chicago"
		else:
			kind = "glass"
	match kind:
		"chicago": b._tw_chicago(to_curb, b.half * 2.0, storeys)
		"deco": b._tw_deco(to_curb, b.half * 2.0, storeys)
		_:
			if homes:
				b._tw_slab(to_curb, b.half * 2.0, storeys)
			else:
				b._tw_glass(to_curb, b.half * 2.0, storeys)
	return b


# ---------------------------------------------------------------- Chicago School

func _tw_chicago(to_curb: float, width: float, storeys: int) -> void:
	var w := minf(width - 1.0, rng.randf_range(24.0, 36.0))
	var d := minf(depth - 4.0, rng.randf_range(24.0, 32.0))
	var zf := 0.4  # built to the sidewalk
	var cz := zf + d * 0.5
	var ground_h := 5.2
	var floor_h := 3.8
	var base_floors := 2
	var y_base := ground_h + floor_h * (base_floors - 1)
	var top := ground_h + floor_h * (storeys - 1)
	var stone := Color(_pick(TW_STONE))
	var shaft := Color(_pick(TW_SHAFT))
	if _far:
		_tw_far_box(Vector3(w, y_base, d), Vector3(0, y_base * 0.5, cz), stone, 0.7)
		_tw_far_box(Vector3(w, top - y_base, d), Vector3(0, (y_base + top) * 0.5, cz), shaft, 0.9)
		_tw_far_box(Vector3(w + 2.4, 0.8, d + 2.4), Vector3(0, top + 0.4, cz), stone.lightened(0.12), 0.0)
		_tw_far_box(Vector3(w, 1.1, d), Vector3(0, top + 1.35, cz), shaft, 0.0)
		return
	_downtown_walk(to_curb, width, zf)
	# The stone base with its tall shop and lobby windows.
	_box("brick", Vector3(w, y_base, d), Vector3(0, y_base * 0.5, cz), stone)
	_box("brick", Vector3(w, top - y_base, d), Vector3(0, (y_base + top) * 0.5, cz), shaft)
	_box("paint", Vector3(w + 0.3, 0.5, d + 0.3), Vector3(0, y_base + 0.1, cz), stone.lightened(0.08))  # belt course
	var bays := maxi(3, roundi(w / 6.0))
	var bw := w / bays
	var side_bays := maxi(3, roundi(d / 6.0))
	var sbw := d / side_bays
	# Shopfronts and the lobby arch between granite piers.
	for i in bays:
		var x := -w * 0.5 + (i + 0.5) * bw
		_glass(Vector3(x, 0.4 + 1.9, zf - 0.03), Vector3(-1, 0, 0), bw - 1.4, 3.6, rng.randf_range(0.0, 0.2))
		if base_floors > 1:
			_glass(Vector3(x, ground_h + 1.7, zf - 0.03), Vector3(-1, 0, 0), bw - 1.6, 2.4, rng.randf_range(0.0, 0.4))
	var door_x := -w * 0.5 + (floori(bays * 0.5) + 0.5) * bw
	_box("paint", Vector3(2.4, 2.8, 0.1), Vector3(door_x, 1.4, zf - 0.06), Color("#2c2620"))
	_box("paint", Vector3(bw - 0.6, 0.5, 1.6), Vector3(door_x, 4.3, zf - 0.8), Color("#2a2a2a"))  # marquee
	if not _homes:
		_sign(Vector3(door_x, 4.6, zf - 1.62), bw - 1.0, 0.8)
	# The shaft: a Chicago window in every bay of every floor, between piers.
	for f in range(base_floors, storeys - 1):
		var y := ground_h + floor_h * (f - 1) + 1.9
		for face in _tw_faces(w, d, cz):
			var n: int = bays if face[3] else side_bays
			var len_b: float = bw if face[3] else sbw
			for i in n:
				var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + (i + 0.5) * len_b)
				c.y = y
				# A wide fixed pane between two narrow sashes, the wall
				# showing between them as the mullions.
				var gw := len_b - 1.3
				var blinds := rng.randf_range(0.0, 0.6)
				_glass(c, face[1], gw * 0.52, 2.3, blinds)
				for k in [-1.0, 1.0]:
					_glass(c + face[1] * k * gw * 0.38, face[1], gw * 0.2, 2.3, rng.randf_range(0.0, 0.6))
	# Continuous piers up the shaft.
	for face in _tw_faces(w, d, cz):
		var n: int = bays if face[3] else side_bays
		var len_b: float = bw if face[3] else sbw
		var out: Vector3 = face[1].cross(Vector3.UP)
		for i in n + 1:
			var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + i * len_b) + out * 0.12
			c.y = (y_base + top) * 0.5
			_box("brick", Vector3(0.9, top - y_base, 0.9), c, shaft.darkened(0.05))
	# The attic storey under a deep cornice, then a parapet.
	_box("paint", Vector3(w + 0.4, 0.6, d + 0.4), Vector3(0, top - floor_h + 0.3, cz), shaft.lightened(0.1))
	for face in _tw_faces(w, d, cz):
		var n: int = bays * 2 if face[3] else side_bays * 2
		var len_b: float = face[2] / n
		for i in n:
			var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + (i + 0.5) * len_b)
			c.y = top - floor_h * 0.5 + 0.2
			_glass(c, face[1], len_b - 0.9, 1.3, 0.3)
	_box("paint", Vector3(w + 2.4, 0.8, d + 2.4), Vector3(0, top + 0.4, cz), stone.lightened(0.12))
	_box("brick", Vector3(w, 1.1, d), Vector3(0, top + 1.35, cz), shaft)
	_tw_roof(w, d, cz, top + 1.9)
	_tw_tank(Vector3(rng.randf_range(-w * 0.25, w * 0.25), top + 1.9, cz + rng.randf_range(-d * 0.2, d * 0.2)))
	_box("brick", Vector3(5.0, 3.6, 6.0), Vector3(-w * 0.3, top + 3.7, cz + d * 0.25), shaft.darkened(0.1))  # elevator penthouse


# ---------------------------------------------------------------- Art Deco setbacks

func _tw_deco(to_curb: float, width: float, storeys: int) -> void:
	var w := minf(width - 1.0, rng.randf_range(28.0, 40.0))
	var d := minf(depth - 4.0, rng.randf_range(26.0, 36.0))
	var zf := 0.4
	var ground_h := 5.5
	var floor_h := 3.7
	var stone := Color(_pick(TW_LIMESTONE))
	var spandrel := Color(_pick(TW_SPANDREL))
	# The 1916 rule: the street wall rises about a third of the way, then
	# each tier steps back, ending in a slim tower and a stepped crown.
	var tiers := [[w, d, ceili(storeys * 0.4)], [w - 6.0, d - 6.0, ceili(storeys * 0.7)], [w - 12.0, d - 12.0, storeys]]
	if storeys < 12:
		tiers = [[w, d, ceili(storeys * 0.6)], [w - 6.0, d - 6.0, storeys]]
	if _far:
		var fy := 0.0
		for t in tiers:
			var y1: float = ground_h + floor_h * (int(t[2]) - 1)
			_tw_far_box(Vector3(t[0], y1 - fy, t[1]), Vector3(0, (fy + y1) * 0.5, zf + d * 0.5), stone, 0.9)
			fy = y1
		_tw_far_box(Vector3(tiers[-1][0] - 4.0, 3.5, tiers[-1][1] - 4.0), Vector3(0, fy + 1.75, zf + d * 0.5), stone, 0.0)
		return
	_downtown_walk(to_curb, width, zf)
	var y0 := 0.0
	var f0 := 0
	for t in tiers:
		var tw: float = t[0]
		var td: float = t[1]
		var f1: int = t[2]
		var y1 := ground_h + floor_h * (f1 - 1)
		var cz := zf + d * 0.5
		_box("brick", Vector3(tw, y1 - y0, td), Vector3(0, (y0 + y1) * 0.5, cz), stone)
		for f in range(maxi(f0, 1), f1):
			var y := ground_h + floor_h * (f - 1) + 1.8
			# One band of windows and one of dark cast spandrels per facade
			# and floor; the piers in front divide them into bays.
			for face in _tw_faces(tw, td, cz):
				var c: Vector3 = face[0]
				c.y = y
				_glass(c, face[1], face[2] - 0.6, 2.0, rng.randf_range(0.0, 0.5))
				var r: Vector3 = face[1] * (face[2] - 0.6) * 0.5
				var o: Vector3 = face[1].cross(Vector3.UP) * 0.02 + Vector3(0, -1.65, 0)
				_quad("paint", c + o - r - Vector3(0, 0.55, 0), c + o + r - Vector3(0, 0.55, 0), c + o + r + Vector3(0, 0.55, 0),
					c + o - r + Vector3(0, 0.55, 0), spandrel, [], face[1].cross(Vector3.UP))
		# Piers run unbroken to the top of each tier and stand above it.
		for face in _tw_faces(tw, td, cz):
			var n := maxi(3, roundi(face[2] / 2.4))
			var len_b: float = face[2] / n
			var out: Vector3 = face[1].cross(Vector3.UP)
			for i in n + 1:
				var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + i * len_b) + out * 0.15
				var ph := (y1 - maxf(y0, ground_h)) + (1.2 if i % 2 == 0 else 0.6)
				c.y = maxf(y0, ground_h) + ph * 0.5
				_box("brick", Vector3(0.6, ph, 0.6), c, stone.lightened(0.05), _tw_yaw(face[1]))
		_box("paint", Vector3(tw + 0.2, 0.6, td + 0.2), Vector3(0, y1 + 0.3, cz), stone.darkened(0.08))  # coping
		y0 = y1
		f0 = f1
	# The ground floor: bronze shopfronts and a tall lobby portal.
	var cz0 := zf + d * 0.5
	for face in [_tw_faces(w, d, cz0)[0]]:
		var n := maxi(3, roundi(w / 7.0))
		for i in n:
			var c: Vector3 = face[0] + face[1] * (-w * 0.5 + (i + 0.5) * w / n)
			c.y = 2.6
			_glass(c, face[1], w / n - 1.2, 3.8, 0.0)
	_box("brick", Vector3(5.0, 8.0, 0.6), Vector3(0, 4.0, zf - 0.3), stone.lightened(0.1))
	_box("paint", Vector3(3.0, 6.5, 0.1), Vector3(0, 3.25, zf - 0.62), Color("#3b2f22"))  # bronze and glass
	if not _homes:
		_sign(Vector3(0, 7.3, zf - 0.66), 4.2, 0.6)
	# The crown: two more small steps.
	var top := y0
	var cw: float = tiers[-1][0]
	var cd: float = tiers[-1][1]
	for k in 2:
		cw -= 4.0
		cd -= 4.0
		if cw < 4.0 or cd < 4.0:
			break
		_box("brick", Vector3(cw, 3.5, cd), Vector3(0, top + 1.75, zf + d * 0.5), stone)
		top += 3.5
	_tw_tank(Vector3(0, top, zf + d * 0.5))


# ---------------------------------------------------------------- postwar glass

func _tw_glass(to_curb: float, width: float, storeys: int) -> void:
	var w := minf(width - 8.0, rng.randf_range(24.0, 36.0))
	var d := minf(depth - 16.0, rng.randf_range(18.0, 26.0))
	if w < 12.0 or d < 10.0:
		if _far:
			_tw_far_box(Vector3(width - 8.0, 3.9 * storeys, 18.0), Vector3(0, 3.9 * storeys * 0.5, 18.0), Color(_pick(SPANDREL)), 0.9)
		else:
			_office(to_curb, width, storeys)
		return
	var zf := minf(rng.randf_range(10.0, 16.0), depth - d - 2.0)  # set back on a plaza
	var cz := zf + d * 0.5
	var ground_h := 5.5
	var floor_h := 3.6
	var top := ground_h + floor_h * (storeys - 1)
	var tint := Color(0.42, 0.40, 0.36) if rng.randf() < 0.6 else Color(0.36, 0.42, 0.46)
	var mech := 3.6
	if _far:
		_tw_far_box(Vector3(w - 6.0, ground_h, d - 6.0), Vector3(0, ground_h * 0.5, cz), Color("#2a2c2e"), 0.0)
		_tw_far_box(Vector3(w, top - ground_h, d), Vector3(0, (ground_h + top) * 0.5, cz), tint.darkened(0.55), 1.0)
		_tw_far_box(Vector3(w, mech, d), Vector3(0, top + mech * 0.5, cz), Color("#2b2d2f"), 0.0)
		return
	# The core and lobby, recessed behind the columns.
	_box("paint", Vector3(w - 6.0, ground_h, d - 6.0), Vector3(0, ground_h * 0.5, cz), Color("#2a2c2e"))
	for face in _tw_faces(w - 6.0, d - 6.0, cz):
		_glass(face[0] + Vector3(0, ground_h * 0.5, 0), face[1], face[2] - 0.6, ground_h - 0.6, 0.0)
	var cols := maxi(3, roundi(w / 9.0))
	for i in cols + 1:
		for zz in [zf + 0.5, zf + d - 0.5]:
			_box("metal", Vector3(0.6, ground_h, 0.6), Vector3(-w * 0.5 + 0.5 + i * (w - 1.0) / cols, ground_h * 0.5, zz), TW_STEEL)
	# The tower: a dark box wrapped in glass floor by floor.
	_box("paint", Vector3(w, top - ground_h, d), Vector3(0, (ground_h + top) * 0.5, cz), Color("#1c1e20"))
	for f in range(1, storeys):
		var y := ground_h + floor_h * (f - 1) + floor_h * 0.5
		for face in _tw_faces(w, d, cz):
			var c: Vector3 = face[0]
			c.y = y
			_glass(c, face[1], face[2] - 0.2, floor_h - 0.25, rng.randf_range(0.1, 0.5))
	# The I-beam mullions, full height, about 1.6 m apart.
	for face in _tw_faces(w, d, cz):
		var n := maxi(4, roundi(face[2] / 1.6))
		var out: Vector3 = face[1].cross(Vector3.UP)
		for i in n + 1:
			var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + i * face[2] / n) + out * 0.12
			c.y = (ground_h + top) * 0.5
			_box("metal", Vector3(0.14, top - ground_h, 0.22), c, TW_STEEL, _tw_yaw(face[1]))
		# Floor lines in the steel.
	for f in range(1, storeys):
		_box("metal", Vector3(w + 0.3, 0.12, d + 0.3), Vector3(0, ground_h + floor_h * (f - 1), cz), TW_STEEL)
	# The louvred mechanical floor and a flat roof.
	_box("metal", Vector3(w, mech, d), Vector3(0, top + mech * 0.5, cz), Color("#2b2d2f"))
	_tw_roof(w, d, cz, top + mech)
	# The plaza: granite paving, planters and the name on a low wall.
	_flat_rect("drive", -width * 0.5 + 0.5, width * 0.5 - 0.5, -to_curb + RoadStyle.CURB_WIDTH, zf + d, 0.06)
	for s in [-1.0, 1.0]:
		_box("concrete", Vector3(4.0, 0.6, 2.0), Vector3(s * w * 0.3, 0.3, zf * 0.45), Color("#8f8b84"))
		_shrub(Vector3(s * w * 0.3, 0.6, zf * 0.45), 0.6)
	_box("concrete", Vector3(6.0, 0.9, 0.5), Vector3(0, 0.45, zf * 0.25), Color("#8f8b84"))
	_sign(Vector3(0, 0.95, zf * 0.25 - 0.27), 5.0, 0.5)
	if depth - (zf + d) > 12.0:
		_parking(-width * 0.5 + 0.6, width * 0.5 - 0.6, zf + d + 2.0, depth - 1.0, width)
	for s in [-1.0, 1.0]:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(s * (width * 0.5 - 3.0), 0, zf * 0.6), pick[0], pick[1], rng.randf_range(0.8, 1.0)])


# ---------------------------------------------------------------- postwar apartments

## A 1960s-70s concrete-frame apartment slab (Riley Towers in Indianapolis,
## Carl Sandburg Village in Chicago): a double-loaded slab about 17 m deep,
## 9 ft 6 in floors, brick or painted concrete between exposed slab edges,
## cantilevered balconies stacked in columns with aluminium guards, set back
## on a lawn behind a lobby canopy with the street number on it.
func _tw_slab(to_curb: float, width: float, storeys: int) -> void:
	var w := minf(width - 8.0, rng.randf_range(30.0, 46.0))
	var d := minf(depth - 14.0, rng.randf_range(16.0, 19.0))
	if w < 14.0 or d < 12.0:
		_tw_glass(to_curb, width, storeys)
		return
	var zf := minf(rng.randf_range(8.0, 14.0), depth - d - 2.0)
	var cz := zf + d * 0.5
	var ground_h := 4.5
	var floor_h := 2.9
	var top := ground_h + floor_h * (storeys - 1)
	var wall := Color(_pick(["#c9b48a", "#d8ccb0", "#b89b72", "#e4e0d6"]))  # buff, cream, tan brick, painted concrete
	var slab := Color("#cfcbc2")
	var guard := Color("#3a3c3e") if rng.randf() < 0.6 else Color("#e8e6e0")
	var mech := 3.2
	if _far:
		_tw_far_box(Vector3(w, top, d), Vector3(0, top * 0.5, cz), wall, 0.55)
		_tw_far_box(Vector3(w * 0.3, mech, d * 0.6), Vector3(0, top + 0.8 + mech * 0.5, cz), slab.darkened(0.1), 0.0)
		return
	_box("brick", Vector3(w, top, d), Vector3(0, top * 0.5, cz), wall)
	var bays := maxi(4, roundi(w / 3.6))
	var bw := w / bays
	var side_bays := maxi(3, roundi(d / 3.6))
	var sbw := d / side_bays
	# Balconies run the whole width on some slabs, every other bay on most.
	var every := 1 if rng.randf() < 0.35 else 2
	for f in range(1, storeys):
		var y0 := ground_h + floor_h * (f - 1)
		_box("paint", Vector3(w + 0.12, 0.22, d + 0.12), Vector3(0, y0 + 0.11, cz), slab)  # exposed slab edge
		for face in _tw_faces(w, d, cz):
			var n: int = bays if face[3] else side_bays
			var len_b: float = bw if face[3] else sbw
			var out: Vector3 = face[1].cross(Vector3.UP)
			var wall_at: Vector3 = face[0] - out * 0.03
			for i in n:
				var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + (i + 0.5) * len_b)
				var balcony: bool = face[3] and i > 0 and i < n - 1 and i % every == every - 1
				if not balcony:
					c.y = y0 + 1.55
					_glass(c, face[1], len_b - 1.4, 1.5, rng.randf_range(0.1, 0.7))
					continue
				# A sliding door out to a cantilevered slab with an aluminium guard.
				c.y = y0 + 0.22 + 1.05
				_glass(c, face[1], len_b - 1.2, 2.1, rng.randf_range(0.1, 0.6))
				var b0: Vector3 = wall_at + face[1] * (-face[2] * 0.5 + (i + 0.5) * len_b)
				var yaw := _tw_yaw(face[1])
				_box("paint", Vector3(len_b - 0.4, 0.24, 1.54), b0 + out * 0.72 + Vector3(0, y0 + 0.14, 0), slab, yaw)
				_box("metal", Vector3(len_b - 0.4, 1.05, 0.05), b0 + out * 1.47 + Vector3(0, y0 + 0.785, 0), guard, yaw)
				for s in [-1.0, 1.0]:
					_box("metal", Vector3(0.05, 1.05, 1.36), b0 + out * 0.78 + face[1] * s * (len_b * 0.5 - 0.22) + Vector3(0, y0 + 0.785, 0), guard, yaw)
	# The lobby: glass across the middle bays under a canopy with the number.
	var lobby := minf(w * 0.3, 11.0)
	_glass(Vector3(0, 2.0, zf - 0.03), Vector3(-1, 0, 0), lobby, 3.4, 0.0)
	for i in bays:
		var x := -w * 0.5 + (i + 0.5) * bw
		if absf(x) > lobby * 0.5 + 0.5:
			_glass(Vector3(x, 2.1, zf - 0.03), Vector3(-1, 0, 0), bw - 1.4, 1.6, rng.randf_range(0.2, 0.7))
	_box("paint", Vector3(5.0, 0.3, 4.0), Vector3(0, 3.35, zf - 2.0), slab)
	for s in [-1.0, 1.0]:
		_box("metal", Vector3(0.15, 3.2, 0.15), Vector3(s * 2.2, 1.6, zf - 3.7), guard)
	_box("paint", Vector3(1.4, 0.22, 0.04), Vector3(0, 3.35, zf - 4.03), Color("#c8b27a"))  # brass street number
	# A concrete parapet, the roof and the elevator and fan penthouse.
	_box("paint", Vector3(w + 0.12, 0.8, d + 0.12), Vector3(0, top + 0.4, cz), slab)
	_tw_roof(w, d, cz, top + 0.8)
	_box("brick", Vector3(w * 0.3, mech, d * 0.6), Vector3(0, top + 0.8 + mech * 0.5, cz), wall.darkened(0.1))
	# The lawn: a walk to the curb, foundation shrubs, shade trees, parking behind.
	_flat_rect("drive", -1.5, 1.5, -to_curb + RoadStyle.CURB_WIDTH, zf - 4.0, 0.06)
	_flat_rect("drive", -2.5, 2.5, zf - 4.0, zf, 0.06)
	var sx := -w * 0.5 + 1.0
	while sx < w * 0.5 - 1.0:
		if absf(sx) > 3.5:
			_shrub(Vector3(sx, 0, zf - 0.9), rng.randf_range(0.5, 0.8))
		sx += rng.randf_range(2.2, 3.4)
	if depth - (zf + d) > 12.0:
		_parking(-width * 0.5 + 0.6, width * 0.5 - 0.6, zf + d + 2.0, depth - 1.0, width)
	for s in [-1.0, 1.0]:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(s * (width * 0.5 - 4.0), 0, zf * 0.5), pick[0], pick[1], rng.randf_range(0.8, 1.0)])


# ---------------------------------------------------------------- parts

## A box for the far version: four walls with their own metre UVs (along
## the wall, up it) so the "far" shader can draw a window grid on them,
## `windows` (0..1, in vertex alpha) saying how much of the wall is glass,
## and a flat top. Ten triangles.
func _tw_far_box(size: Vector3, center: Vector3, col: Color, windows: float) -> void:
	var h := size * 0.5
	var y0 := center.y - h.y
	var y1 := center.y + h.y
	col.a = windows
	for face in _tw_faces(size.x, size.z, center.z):
		var c: Vector3 = face[0]
		var r: Vector3 = face[1] * face[2] * 0.5
		var l: float = face[2]
		_quad("far", Vector3(c.x - r.x, y0, c.z - r.z), Vector3(c.x + r.x, y0, c.z + r.z), Vector3(c.x + r.x, y1, c.z + r.z),
			Vector3(c.x - r.x, y1, c.z - r.z), col, [Vector2(0, y0), Vector2(l, y0), Vector2(l, y1), Vector2(0, y1)], face[1].cross(Vector3.UP))
	var top := col
	top.a = 0.0
	_quad("far", Vector3(center.x - h.x, y1, center.z - h.z), Vector3(center.x + h.x, y1, center.z - h.z),
		Vector3(center.x + h.x, y1, center.z + h.z), Vector3(center.x - h.x, y1, center.z + h.z), top.darkened(0.25),
		[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP)


## The four faces of a box footprint: [centre at y 0, along (right as seen
## from outside), length, is it the street front or back].
func _tw_faces(w: float, d: float, cz: float) -> Array:
	return [
		[Vector3(0, 0, cz - d * 0.5 - 0.03), Vector3(-1, 0, 0), w, true],
		[Vector3(0, 0, cz + d * 0.5 + 0.03), Vector3(1, 0, 0), w, true],
		[Vector3(-w * 0.5 - 0.03, 0, cz), Vector3(0, 0, 1), d, false],
		[Vector3(w * 0.5 + 0.03, 0, cz), Vector3(0, 0, -1), d, false],
	]


## Turns a box built facing the street to lie along `along`.
func _tw_yaw(along: Vector3) -> Basis:
	return Basis(Vector3.UP, atan2(-along.z, -along.x))


## A gravel roof inside the parapet.
func _tw_roof(w: float, d: float, cz: float, y: float) -> void:
	_quad("paint", Vector3(-w * 0.5, y + 0.03, cz - d * 0.5), Vector3(w * 0.5, y + 0.03, cz - d * 0.5),
		Vector3(w * 0.5, y + 0.03, cz + d * 0.5), Vector3(-w * 0.5, y + 0.03, cz + d * 0.5), GRAVEL, [], Vector3.UP)


## A timber rooftop water tank on a steel stand (Rosenwach / Isseks style):
## staves bound with hoops under a conical cap.
func _tw_tank(at: Vector3) -> void:
	var r := 2.3
	var h := 4.2
	var leg := 3.4
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_box("metal", Vector3(0.25, leg, 0.25), at + Vector3(s.x * r * 0.6, leg * 0.5, s.y * r * 0.6), TW_STEEL)
	_box("metal", Vector3(r * 1.7, 0.3, r * 1.7), at + Vector3(0, leg, 0), TW_STEEL)
	var sides := 10
	var y0 := at.y + leg + 0.15
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(at.x + cos(a0) * r, y0, at.z + sin(a0) * r)
		var p1 := Vector3(at.x + cos(a1) * r, y0, at.z + sin(a1) * r)
		var outv := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		_quad("siding", p0, p1, p1 + Vector3(0, h, 0), p0 + Vector3(0, h, 0), TW_TANK, [], outv)
		for hoop in [0.6, 1.8, 3.0]:
			_quad("paint", p0 * Vector3(1, 0, 1) + outv * 0.03 + Vector3(0, y0 + hoop, 0), p1 * Vector3(1, 0, 1) + outv * 0.03 + Vector3(0, y0 + hoop, 0),
				p1 * Vector3(1, 0, 1) + outv * 0.03 + Vector3(0, y0 + hoop + 0.08, 0), p0 * Vector3(1, 0, 1) + outv * 0.03 + Vector3(0, y0 + hoop + 0.08, 0), TW_STEEL, [], outv)
		var apex := Vector3(at.x, y0 + h + 1.3, at.z)
		var e0 := p0 + Vector3(0, h, 0) + outv * 0.15
		var e1 := p1 + Vector3(0, h, 0) + outv * 0.15
		_tri("roof", e0, e1, apex, TW_TANK.darkened(0.3), [], Vector3.UP)
