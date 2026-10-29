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
		# Past 60 storeys an office is a supertall of bundled tubes; from 24
		# most postwar offices are granite-and-glass postmodern towers.
		# Picked from the seed, so no random draw moves.
		if storeys >= 60 and not homes:
			kind = "tubes"
		elif b.era == "prewar":
			kind = "deco" if storeys >= 14 or b.rng.randf() < 0.3 else "chicago"
		elif storeys >= 24 and not homes and posmod(seed, 100) < 65:
			kind = "pomo"
		else:
			kind = "glass"
	match kind:
		"chicago": b._tw_chicago(to_curb, b.half * 2.0, storeys)
		"deco": b._tw_deco(to_curb, b.half * 2.0, storeys)
		"pomo": b._tw_pomo(to_curb, b.half * 2.0, storeys)
		"tubes": b._tw_tubes(to_curb, b.half * 2.0, storeys)
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


# ---------------------------------------------------------------- postmodern

const TW_GRANITE := ["#8d7f78", "#a39388", "#6f6a66", "#b7aa98", "#9a8f86"]


## A 1980s-90s postmodern office tower, what a downtown office grows into
## past two dozen storeys (Salesforce Tower and OneAmerica Tower in
## Indianapolis, Chase Tower's twin masts, Two Prudential in Chicago): a
## granite podium built out to the lot lines with shops and the lobby, the
## tower set back above it with notched corners, granite piers between
## bands of tinted glass, one or two setbacks toward the top, and a crown:
## a pyramid with a spire, a stepped top, or twin masts.
func _tw_pomo(to_curb: float, width: float, storeys: int) -> void:
	var w := minf(width - 2.0, rng.randf_range(34.0, 46.0))
	var d := minf(depth - 8.0, rng.randf_range(30.0, 40.0))
	if w < 24.0 or d < 22.0:
		_tw_glass(to_curb, width, storeys)
		return
	var zf := 3.0  # a narrow plaza strip in front of the podium
	var cz := zf + d * 0.5
	var ground_h := 5.5
	var floor_h := 3.9
	var pod_f := clampi(storeys / 8, 3, 6)
	var pod_h := ground_h + floor_h * (pod_f - 1)
	var top := ground_h + floor_h * (storeys - 1)
	var stone := Color(_pick(TW_GRANITE))
	var tints: Array[Color] = [Color(0.30, 0.36, 0.40), Color(0.36, 0.33, 0.30), Color(0.28, 0.38, 0.36)]
	var tint: Color = tints[rng.randi() % 3]
	var crown := rng.randi() % 3  # 0 pyramid and spire, 1 stepped top, 2 twin masts
	# The tower plan, and two setbacks near the top.
	var tw := w * 0.74
	var td := d * 0.74
	var notch := minf(tw, td) * 0.12
	var f1 := int(storeys * 0.62)
	var f2 := int(storeys * 0.86)
	var y1 := ground_h + floor_h * (f1 - 1)
	var y2 := ground_h + floor_h * (f2 - 1)
	var tiers := [[tw, td, pod_h, y1], [tw - 5.0, td - 5.0, y1, y2], [tw - 10.0, td - 10.0, y2, top]]
	if _far:
		_tw_far_box(Vector3(w, pod_h, d), Vector3(0, pod_h * 0.5, cz), stone, 0.45)
		for t in tiers:
			_tw_far_box(Vector3(t[0], t[3] - t[2], t[1]), Vector3(0, (t[2] + t[3]) * 0.5, cz), tint.lerp(stone, 0.35), 0.85)
		_pm_crown(crown, tiers[-1][0], tiers[-1][1], cz, top, stone, true)
		return
	_downtown_walk(to_curb, width, zf)
	_flat_rect("drive", -width * 0.5 + 0.5, width * 0.5 - 0.5, -0.2, zf, 0.065)
	# The podium: granite, tall shopfronts and a recessed lobby below
	# punched windows, and a cornice where the tower steps back.
	_box("brick", Vector3(w, pod_h, d), Vector3(0, pod_h * 0.5, cz), stone)
	for face in _tw_faces(w, d, cz):
		var n := maxi(3, roundi(face[2] / 4.5))
		var bw: float = face[2] / n
		for i in n:
			var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + (i + 0.5) * bw)
			if face[3] or i % 2 == 0:
				_glass(c + Vector3(0, 2.6, 0), face[1], bw - 1.0, 4.0, 0.0)
			for f in range(1, pod_f):
				_glass(c + Vector3(0, ground_h + floor_h * (f - 1) + 1.9, 0), face[1], bw - 1.6, 2.2, rng.randf_range(0.0, 0.5))
	_box("paint", Vector3(w + 0.6, 0.8, d + 0.6), Vector3(0, pod_h + 0.42, cz), stone.lightened(0.08))
	_tw_roof(w, d, cz, pod_h + 0.8)
	# The lobby: a two-storey glass portal under a canopy, the name above.
	_box("paint", Vector3(10.0, 8.0, 0.4), Vector3(0, 4.0, zf - 0.25), stone.darkened(0.12))
	_glass(Vector3(0, 3.6, zf - 0.47), Vector3(-1, 0, 0), 8.0, 6.6, 0.0)
	_box("metal", Vector3(12.0, 0.4, 3.0), Vector3(0, 4.6, zf - 1.9), Color("#2b2d2f"))
	if not _homes:
		_sign(Vector3(0, 7.2, zf - 0.47), 6.0, 0.7)
	# The tower, tier by tier.
	for t in tiers:
		_pm_shaft(t[0], t[1], notch, cz, t[2], t[3], floor_h, stone, tint)
		_box("paint", Vector3(t[0] + 0.4, 0.6, t[1] + 0.4), Vector3(0, t[3] + 0.32, cz), stone.lightened(0.06))
		_tw_roof(t[0], t[1], cz, t[3] + 0.6)
	_pm_crown(crown, tiers[-1][0], tiers[-1][1], cz, top + 0.6, stone, false)
	for s in [-1.0, 1.0]:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(s * (w * 0.5 - 3.0), 0, -to_curb + RoadStyle.CURB_WIDTH + 1.0), pick[0], pick[1], rng.randf_range(0.7, 0.9)])


## A notched shaft from y0 to y1: a cross of two boxes (so each corner is
## cut back by `notch`), a band of tinted glass on every floor of every
## face, and granite piers about 3 m apart running the height of the tier.
func _pm_shaft(w: float, d: float, notch: float, cz: float, y0: float, y1: float, floor_h: float, stone: Color, tint: Color) -> void:
	var h := y1 - y0
	var core := tint.darkened(0.6)
	# In the wall material the far version keeps, so it stays solid far off.
	# Starting 3 cm up, so its floor never lies in the tier below's roof.
	_box("brick", Vector3(w, h - 0.03, d - 2.0 * notch), Vector3(0, y0 + 0.03 + (h - 0.03) * 0.5, cz), core)
	_box("brick", Vector3(w - 2.0 * notch, h - 0.03, d), Vector3(0, y0 + 0.03 + (h - 0.03) * 0.5, cz), core)
	var floors := maxi(1, roundi(h / floor_h))
	var fh := h / floors
	for face in _pm_faces(w, d, notch, cz):
		var out: Vector3 = Vector3(face[1].z, 0, -face[1].x) * -1.0
		for f in floors:
			var c: Vector3 = face[0] + Vector3(0, y0 + (f + 0.5) * fh, 0)
			_glass(c, face[1], face[2] - 0.2, fh - 0.9, rng.randf_range(0.05, 0.4))
		var n := maxi(1, roundi(face[2] / 3.0))
		for i in n + 1:
			var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + i * face[2] / n) + out * 0.22
			var ph := h - 0.08 - 0.02 * (i % 2)  # stops short of the tier's roof
			c.y = y0 + 0.04 + ph * 0.5
			_box("paint", Vector3(0.55 + (i % 2) * 0.03, ph, 0.4), c, stone, _tw_yaw(face[1]))
		# A granite spandrel band every floor.
		for f in floors:
			var c: Vector3 = face[0] + out * 0.1 + Vector3(0, y0 + f * fh + 0.31, 0)
			_box("paint", Vector3(face[2] - 0.02, 0.6, 0.12), c, stone.darkened(0.05), _tw_yaw(face[1]))


## The twelve faces of a box with its corners notched: the long faces, then
## the two short returns at each corner. Same layout as _tw_faces.
func _pm_faces(w: float, d: float, n: float, cz: float) -> Array:
	if n < 0.1:
		return _tw_faces(w, d, cz)
	var out := [
		[Vector3(0, 0, cz - d * 0.5 - 0.03), Vector3(-1, 0, 0), w - 2.0 * n, true],
		[Vector3(0, 0, cz + d * 0.5 + 0.03), Vector3(1, 0, 0), w - 2.0 * n, true],
		[Vector3(-w * 0.5 - 0.03, 0, cz), Vector3(0, 0, 1), d - 2.0 * n, false],
		[Vector3(w * 0.5 + 0.03, 0, cz), Vector3(0, 0, -1), d - 2.0 * n, false],
	]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			# The notch's face toward the street (or back), and its side.
			out.append([Vector3(sx * (w * 0.5 - n * 0.5), 0, cz + sz * (d * 0.5 - n + 0.03)), Vector3(-sz, 0, 0), n, false])
			out.append([Vector3(sx * (w * 0.5 - n + 0.03), 0, cz + sz * (d * 0.5 - n * 0.5)), Vector3(0, 0, sx), n, false])
	return out


## The crown on a postmodern tower's top tier (w × d at height y).
func _pm_crown(kind: int, w: float, d: float, cz: float, y: float, stone: Color, far: bool) -> void:
	var dark := Color("#2b2d2f")
	match kind:
		0:
			# A pyramid in dark metal with a spire (Salesforce Tower, Indianapolis).
			var ph := minf(w, d) * 0.55
			var a := Vector3(-w * 0.5, y, cz - d * 0.5)
			var b := Vector3(w * 0.5, y, cz - d * 0.5)
			var c := Vector3(w * 0.5, y, cz + d * 0.5)
			var e := Vector3(-w * 0.5, y, cz + d * 0.5)
			var apex := Vector3(0, y + ph, cz)
			var m := "far" if far else "roof"
			var col := Color("#4a5a58") if not far else Color("#4a5a58", 0.0)
			for pr in [[a, b], [b, c], [c, e], [e, a]]:
				var nrm: Vector3 = ((pr[1] - pr[0]).cross(apex - pr[0])).normalized() * -1.0
				if far:
					_tri(m, pr[0], pr[1], apex, col, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], nrm)
				else:
					_tri(m, pr[0], pr[1], apex, col, [], nrm)
			if not far:
				_box("metal", Vector3(0.9, 9.0, 0.9), apex + Vector3(0, 3.5, 0), dark)
				_box("metal", Vector3(0.4, 10.0, 0.4), apex + Vector3(0, 12.0, 0), dark)
		1:
			# Two more stepped tiers with a lit band (OneAmerica-style flat top).
			var cw := w
			var cd := d
			var yy := y
			for k in 2:
				cw -= 4.0
				cd -= 4.0
				if far:
					_tw_far_box(Vector3(cw, 4.0, cd), Vector3(0, yy + 2.0, cz), stone, 0.0)
				else:
					_box("paint", Vector3(cw, 4.0, cd), Vector3(0, yy + 2.0, cz), stone)
					_box("paint", Vector3(cw + 0.1, 0.5, cd + 0.1), Vector3(0, yy + 3.4, cz), Color("#e8e2c8"))
				yy += 4.0
		_:
			# A mechanical screen and twin masts (Chase Tower, Indianapolis).
			if far:
				_tw_far_box(Vector3(w * 0.8, 5.0, d * 0.8), Vector3(0, y + 2.5, cz), dark, 0.0)
			else:
				_box("metal", Vector3(w * 0.8, 5.0, d * 0.8), Vector3(0, y + 2.5, cz), dark)
				for s in [-1.0, 1.0]:
					_box("metal", Vector3(0.8, 26.0, 0.8), Vector3(s * w * 0.25, y + 18.0, cz), Color("#d8d8d4"))
					for k in 4:
						_box("metal", Vector3(1.4, 0.15, 1.4), Vector3(s * w * 0.25, y + 9.0 + k * 5.0, cz), Color("#c23a2a") if k % 2 == 0 else Color("#e8e8e4"))


# ---------------------------------------------------------------- supertall

## A supertall office of bundled tubes, past 60 storeys (Willis Tower,
## Chicago, 108 storeys: nine 23 m square tubes on a 3 × 3 grid, two
## stopping at the 50th floor, two at the 66th, three at the 90th and two
## running to the top): black aluminium and bronze glass, setbacks where
## tubes end, two masts on top.
func _tw_tubes(to_curb: float, width: float, storeys: int) -> void:
	var side := minf(minf(width - 2.0, depth - 8.0), 60.0)
	if side < 30.0:
		_tw_pomo(to_curb, width, storeys)
		return
	var s := side / 3.0
	var zf := 3.0
	var cz := zf + side * 0.5
	var ground_h := 6.0
	var floor_h := 3.9
	var top := ground_h + floor_h * (storeys - 1)
	var black := Color("#18191b")
	var bronze := Color(0.30, 0.26, 0.20)
	# Willis's pattern of tube heights, as shares of the full height.
	var share := [0.46, 0.83, 0.46, 0.61, 1.0, 0.83, 0.61, 1.0, 0.83]
	var heights := []
	for i in 9:
		heights.append(ground_h + floor_h * (int(storeys * share[i]) - 1))
	if not _far:
		_downtown_walk(to_curb, width, zf)
		_flat_rect("drive", -width * 0.5 + 0.5, width * 0.5 - 0.5, -0.2, zf, 0.065)
	for i in 9:
		var gx := i % 3 - 1
		var gz := i / 3 - 1
		var x := gx * s
		var z := cz + gz * s
		var h: float = heights[i]
		if _far:
			_tw_far_box(Vector3(s, h, s), Vector3(x, h * 0.5, z), black, 0.85)
			continue
		_box("brick", Vector3(s, h, s), Vector3(x, h * 0.5, z), black)
		# A parapet cap and the roof inset from the tube's edges, so a lower
		# neighbour's roof never reads as this tube's top far off.
		_box("paint", Vector3(s + 0.2, 0.6, s + 0.2), Vector3(x, h + 0.3, z), black)
		_tw_roof(s - 1.6, s - 1.6, z, h + 0.6, x)
		# Each face shows from the top of the neighbouring tube (or the ground).
		for face in _tw_faces(s, s, z):
			var o: Vector3 = Vector3(face[1].z, 0, -face[1].x) * -1.0
			var nx := gx + int(round(o.x))
			var nz := gz + int(round(o.z))
			var lo := 0.0
			if nx >= -1 and nx <= 1 and nz >= -1 and nz <= 1:
				lo = heights[(nz + 1) * 3 + (nx + 1)]
			if lo >= h:
				continue
			var c0: Vector3 = face[0] + Vector3(x, 0, 0)
			var f0 := maxi(0, int((lo - ground_h) / floor_h) + 1) if lo > 0.0 else 0
			for f in range(f0, storeys):
				var y := ground_h + floor_h * (f - 1) if f > 0 else 0.0
				var y_top := ground_h + floor_h * f if f > 0 else ground_h
				if y_top > h + 0.01:
					break
				_glass(c0 + Vector3(0, (y + y_top) * 0.5, 0), face[1], s - 0.3, (y_top - y) - 0.8, rng.randf_range(0.05, 0.35) if f > 0 else 0.0)
			# Black mullions every 4.6 m (Willis's bay), the height of the face.
			var n := 5
			for k in n + 1:
				var c: Vector3 = c0 + face[1] * (-s * 0.5 + k * s / n) + o * 0.17
				c.y = (lo + h) * 0.5
				_box("metal", Vector3(0.3, h - lo, 0.3), c, black, _tw_yaw(face[1]))
	# Two masts on the tallest tubes.
	for i in [4, 7]:
		var x: float = (i % 3 - 1) * s
		var z: float = cz + (i / 3 - 1) * s
		var h: float = heights[i]
		if _far:
			_tw_far_box(Vector3(1.2, 80.0, 1.2), Vector3(x, h + 40.0, z), Color("#d8d8d4", 0.0), 0.0)
		else:
			_box("metal", Vector3(1.5, 6.0, 1.5), Vector3(x, h + 3.03, z), black)
			_box("metal", Vector3(1.0, 80.0, 1.0), Vector3(x, h + 46.0, z), Color("#d8d8d4"))
	if not _far:
		# The street lobby: a glass pavilion along the front.
		_box("metal", Vector3(side * 0.6, 0.5, 4.0), Vector3(0, 6.2, zf - 2.08), black)
		if not _homes:
			_sign(Vector3(0, 6.7, zf - 4.02), 6.0, 0.6)


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


## A gravel roof inside the parapet, in the membrane material, so the far
## version knows where each mass ends (a tier's walls stop at its roof
## instead of running up to the tower's top).
func _tw_roof(w: float, d: float, cz: float, y: float, x := 0.0) -> void:
	var g := GRAVEL
	g.a = 0.5
	_quad("membrane", Vector3(x - w * 0.5, y + 0.03, cz - d * 0.5), Vector3(x + w * 0.5, y + 0.03, cz - d * 0.5),
		Vector3(x + w * 0.5, y + 0.03, cz + d * 0.5), Vector3(x - w * 0.5, y + 0.03, cz + d * 0.5), g, [], Vector3.UP)


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
