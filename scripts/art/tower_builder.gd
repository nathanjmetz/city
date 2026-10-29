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
##   - pomo: 1980s-90s postmodern towers (Chase Tower, now Salesforce
##     Tower, Indianapolis 1990; Market Tower, Indianapolis 1988; Indiana
##     Michigan Power Center, Fort Wayne 1982): granite and reflective
##     glass, notched corners, setbacks and a crown
##   - podium: 2000s-2020s towers on a podium that fills an assembled site
##     (360 Market Square, Indianapolis 2020; Ash Skyline Plaza, Fort Wayne
##     2015): shops at the sidewalk, parking decks behind screens, a roof
##     deck and a glass tower set back on top
## A grown tower on a bought-up lot uses the land: the podium spreads across
## it, so each stage of growth reads differently from the street.
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
	b.office_glass = DenseBuilder.fine and not homes and not far
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b.sign_spec = spec
	b._fit(lot)
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._added = int(lot.get("added_from", 0)) if not homes and b.era == "prewar" else 0
	if b._added >= storeys:
		b._added = 0
	var kind := era_pick
	if kind == "":
		# Past 60 storeys an office is a supertall of bundled tubes; from 24
		# most postwar offices are granite-and-glass postmodern towers.
		# Picked from the seed, so no random draw moves.
		if storeys >= 60 and not homes:
			kind = "tubes"
		elif b.era == "prewar":
			# From its own random numbers, so a block that grows from three
			# storeys keeps its brick and stone (DenseBuilder.build_office).
			var pr := RandomNumberGenerator.new()
			pr.seed = hash([seed, "prewar form"])
			# One that had floors added keeps the form it was built in.
			# (Under eight storeys it was a Chicago block: build_office.)
			var ks := b._added if b._added > 0 else storeys
			kind = "deco" if ks >= 14 or pr.randf() < 0.3 else "chicago"
			if b._added > 0 and b._added < 8:
				kind = "chicago"
			# On a single storefront lot a 1920s bank often built up instead.
			if kind == "chicago" and b._added == 0 and storeys >= 8 and b.half * 2.0 <= 34.0 and pr.randf() < 0.45:
				kind = "bank"
			# Flats on an old street are a 1920s apartment tower, not an
			# office block with flats in it.
			if homes:
				kind = "flats"
		else:
			kind = _tw_form(seed, b.half * 2.0, homes)
	match kind:
		"chicago": b._tw_chicago(to_curb, b.half * 2.0, storeys)
		"deco": b._tw_deco(to_curb, b.half * 2.0, storeys)
		"pomo": b._tw_pomo(to_curb, b.half * 2.0, storeys)
		"podium": b._tw_podium(to_curb, b.half * 2.0, storeys)
		"tubes": b._tw_tubes(to_curb, b.half * 2.0, storeys)
		"flats": b._tw_flats(to_curb, b.half * 2.0, storeys)
		"bank": b._tw_bank(to_curb, b.half * 2.0, storeys)
		"balcony": b._tw_balcony(to_curb, b.half * 2.0, storeys)
		_:
			if homes:
				b._tw_slab(to_curb, b.half * 2.0, storeys)
			else:
				b._tw_glass(to_curb, b.half * 2.0, storeys)
	return b


## A postwar tower's form, from its own random numbers (so the builder's
## don't move): a wide, assembled site favours a podium; flats are a slab
## or a podium tower, offices any of the three.
static func _tw_form(seed: int, width: float, homes: bool) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed, "tower form"])
	var x := r.randf()
	var wide := width >= 44.0
	if homes:
		# Flats: a podium tower, a 2010s glass tower with shifting balconies,
		# or the 1960s-70s slab ("glass" here).
		var p := 0.55 if wide else 0.2
		return "podium" if x < p else ("balcony" if x < p + 0.3 else "glass")
	if x < 0.3:
		return "glass"
	return "pomo" if x < (0.55 if wide else 0.72) else "podium"


# ---------------------------------------------------------------- bank tower

## A 1910s-20s county-seat bank tower (the eight-to-twelve-storey bank and
## office buildings of Indiana's county seats, after Sullivan's and Burnham's
## "base, shaft and capital"): built to the sidewalk on one storefront lot,
## a two-storey limestone banking hall with three tall arched windows
## between columns, the bank's door in the middle arch, a brick shaft of
## paired windows, a limestone attic under a deep cornice, and the bank's
## name on a rooftop sign. Its own random numbers, so the builder's don't move.
func _tw_bank(to_curb: float, width: float, storeys: int) -> void:
	if _far:
		_tw_chicago(to_curb, width, storeys)
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "bank tower"])
	var w := minf(width - 1.0, r.randf_range(20.0, 28.0))
	var d := minf(depth - 4.0, r.randf_range(22.0, 30.0))
	var zf := 0.4
	var cz := zf + d * 0.5
	var hall := 10.0  # the two-storey banking hall
	var floor_h := 3.7
	var top := hall + floor_h * (storeys - 2)
	var lime := Color(["#d8d0bf", "#cfc6b2", "#e0d9c8"][r.randi() % 3])
	var shaft := Color(["#8a4a38", "#9b5a42", "#b89b72", "#c9b48a"][r.randi() % 4])
	_downtown_walk(to_curb, width, zf)
	# The banking hall: limestone, three arched windows between columns.
	_box("brick", Vector3(w, hall, d), Vector3(0, hall * 0.5, cz), lime)
	var aw := (w - 4.0) / 3.0
	for i in 3:
		var x := -w * 0.5 + 2.0 + (i + 0.5) * aw
		_tw_arch(Vector3(x, 0.6, zf), aw - 1.2, hall - 1.6, lime, Color("#2a3036"))
		if i == 1:
			# Bronze doors in the middle arch, under a transom.
			_box("paint", Vector3(2.6, 3.2, 0.1), Vector3(x, 1.6 + 0.6, zf - 0.78), Color("#5a4a32"))
			_box("paint", Vector3(0.06, 3.2, 0.12), Vector3(x, 2.2, zf - 0.84), Color("#3a2f20"))
	for i in 4:
		var x := -w * 0.5 + 2.0 + i * aw
		_box("paint", Vector3(1.1, hall - 1.4, 1.1), Vector3(x, (hall - 1.4) * 0.5 + 0.6, zf - 0.55), lime.lightened(0.06))  # column
		_box("paint", Vector3(1.5, 0.6, 1.5), Vector3(x, hall - 0.5, zf - 0.55), lime.lightened(0.1))  # capital
		_box("paint", Vector3(1.5, 0.6, 1.5), Vector3(x, 0.3, zf - 0.55), lime.darkened(0.08))  # base
	_box("paint", Vector3(w + 0.6, 0.9, 1.2), Vector3(0, hall + 0.25, zf - 0.2), lime.lightened(0.08))  # entablature
	_box("paint", Vector3(w + 0.6, 0.6, d + 0.6), Vector3(0, 0.3, cz), lime.darkened(0.1))  # water table
	# The shaft: brick with paired windows in every bay, on all four sides.
	var y_attic := top - floor_h
	_box("brick", Vector3(w, y_attic - hall, d), Vector3(0, (hall + y_attic) * 0.5, cz), shaft)
	for face in _tw_faces(w, d, cz):
		var n := maxi(3, roundi(face[2] / 4.2))
		var len_b: float = face[2] / n
		var out: Vector3 = face[1].cross(Vector3.UP)
		for f in range(2, storeys - 1):
			var y := hall + floor_h * (f - 2) + 1.9
			for i in n:
				var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + (i + 0.5) * len_b)
				c.y = y
				for k in [-1.0, 1.0]:
					_glass(c + face[1] * k * 0.75, face[1], 1.15, 2.0, r.randf_range(0.0, 0.6))
				_box("paint", Vector3(len_b * 0.8, 0.12, 0.25), c + out * 0.1 + Vector3(0, -1.08, 0), lime, _tw_yaw(face[1]))  # sill
	# The attic storey in limestone, a deep cornice and a balustraded parapet.
	_box("brick", Vector3(w, floor_h, d), Vector3(0, y_attic + floor_h * 0.5, cz), lime)
	_box("paint", Vector3(w + 0.3, 0.4, d + 0.3), Vector3(0, y_attic, cz), lime.lightened(0.08))  # belt
	for face in _tw_faces(w, d, cz):
		var n := maxi(4, roundi(face[2] / 2.4))
		for i in n:
			var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + (i + 0.5) * face[2] / n)
			c.y = y_attic + floor_h * 0.5
			_glass(c, face[1], 1.0, 1.2, 0.3)
	_box("paint", Vector3(w + 2.2, 0.9, d + 2.2), Vector3(0, top + 0.45, cz), lime.lightened(0.1))  # cornice
	_box("paint", Vector3(w + 1.4, 0.3, d + 1.4), Vector3(0, top + 0.05, cz), lime.darkened(0.05))  # bed mould
	_box("brick", Vector3(w, 1.2, d), Vector3(0, top + 1.5, cz), lime)  # parapet
	_tw_roof(w, d, cz, top + 2.1)
	_tw_rooftop(w, d, cz, top + 2.1, 0.0, false, true)
	if fine:
		for face in _tw_faces(w, d, cz):
			var out: Vector3 = face[1].cross(Vector3.UP)
			var n := maxi(6, roundi(face[2] / 0.6))
			for i in n:
				var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + (i + 0.5) * face[2] / n) + out * 0.12
				c.y = top + 1.45
				_box("paint", Vector3(0.18, 0.8, 0.18), c, lime.lightened(0.14))  # balusters
	_box("brick", Vector3(4.5, 3.4, 5.5), Vector3(w * 0.25, top + 2.1 + 1.7, cz + d * 0.2), shaft.darkened(0.1))  # elevator penthouse
	_tw_roof(4.5, 5.5, cz + d * 0.2, top + 2.1 + 3.4, w * 0.25)
	if not _homes:
		_sign(Vector3(0, hall + 0.75, zf - 0.85), w * 0.5, 0.6)  # carved in the frieze
		_tw_roof_sign(Vector3(-w * 0.1, top + 2.1, zf + 1.6), minf(w * 0.7, 16.0))
	if width - w > 6.0:
		# The rest of the lot: a side lawn with a tree.
		var pick := TreeField.pick(rng)
		trees.append([Vector3(-(w * 0.5 + (width - w) * 0.25), 0, zf + 3.0), pick[0], pick[1], rng.randf_range(0.7, 0.9)])


# ---------------------------------------------------------------- Chicago School

func _tw_chicago(to_curb: float, width: float, storeys: int, roof := true) -> void:
	if _added > 0 and roof:
		# Built lower and added on to: the old block as it was, then the
		# new floors on its roof (_tw_added).
		var keep := _added
		_added = 0
		_tw_chicago(to_curb, width, keep, false)
		_tw_added(storeys - keep)
		return
	var w := minf(width - 1.0, rng.randf_range(24.0, 36.0))
	var d := minf(depth - 4.0, rng.randf_range(24.0, 32.0))
	# On an assembled site the block runs the whole frontage, as the
	# Marquette (about 60 m on Dearborn) and Indianapolis's wide Chicago
	# School office blocks do.
	w = maxf(w, minf(width - 1.0, 64.0))
	var zf := 0.4  # built to the sidewalk
	var cz := zf + d * 0.5
	var ground_h := 5.2
	var floor_h := 3.8
	var base_floors := 2
	var y_base := ground_h + floor_h * (base_floors - 1)
	var top := ground_h + floor_h * (storeys - 1)
	var stone := Color(_pick(TW_STONE))
	var shaft := Color(_pick(TW_SHAFT))
	_old = {"w": w, "d": d, "zf": zf, "top": top + 1.9, "floor_h": floor_h, "shaft": shaft, "stone": stone}
	if _far:
		_tw_far_box(Vector3(w, y_base, d), Vector3(0, y_base * 0.5, cz), stone, 0.7)
		_tw_far_box(Vector3(w, top - y_base, d), Vector3(0, (y_base + top) * 0.5, cz), shaft, 0.9)
		_tw_far_box(Vector3(w + 2.4, 0.8, d + 2.4), Vector3(0, top + 0.4, cz), stone.lightened(0.12), 0.0)
		_tw_far_box(Vector3(w, 1.1, d), Vector3(0, top + 1.35, cz), shaft, 0.0)
		return
	_downtown_walk(to_curb, width, zf)
	var bays := maxi(3, roundi(w / 6.0))
	var bw := w / bays
	var side_bays := maxi(3, roundi(d / 6.0))
	var sbw := d / side_bays
	# Before air conditioning every office wanted a window, so a deep block
	# was built as a U above its base, a light court open to the alley out
	# back (the Fletcher Trust in Indianapolis, the Rookery and the Monadnock
	# era in Chicago). Own random numbers, so the builder's draws don't move.
	var lc := RandomNumberGenerator.new()
	lc.seed = hash([rng.seed, "light court"])
	var ck := (3 if bays >= 9 else 1) if bays % 2 == 1 else (4 if bays >= 10 else 2)
	_court = Vector2.ZERO
	if storeys >= 8 and d >= 22.0 and (w - ck * bw) * 0.5 >= 6.0 and lc.randf() < 0.6 and roof:
		_court = Vector2(ck * bw, maxf(8.0, d * lc.randf_range(0.38, 0.5)))
	var zc := zf + d - _court.y
	_court_z = zc
	# The stone base with its tall shop and lobby windows.
	_box("brick", Vector3(w, y_base, d), Vector3(0, y_base * 0.5, cz), stone)
	_tw_u(w, d, zf, y_base, top - y_base, 0.0, shaft, "brick")
	if _court != Vector2.ZERO:
		_tw_roof(_court.x, _court.y, zc + _court.y * 0.5, y_base)
	_box("paint", Vector3(w + 0.3, 0.5, d + 0.3), Vector3(0, y_base + 0.1, cz), stone.lightened(0.08))  # belt course
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
				var sash := [rng.randf_range(0.0, 0.6), rng.randf_range(0.0, 0.6)]
				if _in_court(c):
					continue
				_glass(c, face[1], gw * 0.52, 2.3, blinds)
				for k in [-1.0, 1.0]:
					_glass(c + face[1] * k * gw * 0.38, face[1], gw * 0.2, 2.3, sash[0 if k < 0.0 else 1])
		# The light court's own walls: plain sash windows, a pair a bay.
		if _court != Vector2.ZERO:
			for wall in _court_walls(zc, zf + d):
				var nb := maxi(1, roundi(float(wall[2]) / 3.2))
				for i in nb:
					var c: Vector3 = wall[0] + wall[1] * (-float(wall[2]) * 0.5 + (i + 0.5) * float(wall[2]) / nb)
					c.y = y
					_glass(c, wall[1], float(wall[2]) / nb - 1.2, 2.1, lc.randf_range(0.0, 0.6))
	# Continuous piers up the shaft.
	for face in _tw_faces(w, d, cz):
		var n: int = bays if face[3] else side_bays
		var len_b: float = bw if face[3] else sbw
		var out: Vector3 = face[1].cross(Vector3.UP)
		for i in n + 1:
			var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + i * len_b) + out * 0.12
			c.y = (y_base + top) * 0.5
			if _in_court(c, 0.2):
				continue
			_box("brick", Vector3(0.9, top - y_base, 0.9), c, shaft.darkened(0.05))
	# The attic storey under a deep cornice, then a parapet.
	_tw_u(w, d, zf, top - floor_h, 0.6, 0.4, shaft.lightened(0.1), "paint")
	for face in _tw_faces(w, d, cz):
		var n: int = bays * 2 if face[3] else side_bays * 2
		var len_b: float = face[2] / n
		for i in n:
			var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + (i + 0.5) * len_b)
			c.y = top - floor_h * 0.5 + 0.2
			if not _in_court(c):
				_glass(c, face[1], len_b - 0.9, 1.3, 0.3)
	_tw_u(w, d, zf, top, 0.8, 2.4, stone.lightened(0.12), "paint")
	_tw_u(w, d, zf, top + 0.8, 1.1, 0.0, shaft, "brick")
	if not roof:
		_tw_alley(w, zf + d, ground_h, floor_h, storeys, lc)
		return
	for r in _court_rects(w, d, zf):
		_tw_roof(r[0], r[1], r[2], top + 1.9, r[3])
	var dz := d - _court.y
	_tw_rooftop(w, dz, zf + dz * 0.5, top + 1.9, 0.0, false, true)
	var tank_at := Vector3(rng.randf_range(-w * 0.25, w * 0.25), top + 1.9, zf + dz * 0.5 + rng.randf_range(-dz * 0.2, dz * 0.2))
	if storeys >= 6:  # city water pressure reaches about six floors
		_tw_tank(tank_at)
	_box("brick", Vector3(5.0, 3.6, 6.0), Vector3(-w * 0.3, top + 3.7, cz + d * 0.25), shaft.darkened(0.1))  # elevator penthouse
	if storeys >= 8:
		_tw_roof_sign(Vector3(0, top + 1.9, zf + 1.6), minf(w * 0.6, 20.0))
	_tw_alley(w, zf + d, ground_h, floor_h, storeys, lc)


## The old block an addition stands on (_tw_chicago): its size, roof
## height (parapet top), floor height and colours.
var _old := {}


## Floors added on top of an old block, as owners did when a downtown
## outgrew its building but the frame could carry more: from the 1940s-60s
## in plain brick a shade off the old (the old cornice left as the seam,
## or the addition set back behind it), or in the 1950s-60s as an aluminium
## curtain wall of glass ribbons over porcelain-enamel spandrel panels
## (Indianapolis and Chicago both have blocks topped this way; Chicago's
## Blue Cross Blue Shield tower was built in 1997 to take 24 more floors,
## added 2007-10). Its own random numbers; the roof gear moves up onto it.
func _tw_added(add: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "added floors"])
	var w: float = _old.w
	var d: float = _old.d
	var zf: float = _old.zf
	var y0: float = _old.top
	var fh: float = _old.floor_h
	var shaft: Color = _old.shaft
	var ribbon := r.randf() < 0.45
	var back := 1.6 if r.randf() < 0.35 else 0.0
	var aw := w - back * 2.0
	var ad := d - back * 2.0
	var cz := zf + d * 0.5
	var h := add * fh
	var col := shaft.lightened(r.randf_range(0.08, 0.2)) if r.randf() < 0.5 else Color(["#c9b48a", "#b9a27e", "#8e8a82", "#a65a3e"][r.randi() % 4])
	var enamel := Color(["#3f6f86", "#5a7a6a", "#7d8a8f", "#2f4a62", "#b8b29e"][r.randi() % 5])
	if ribbon:
		col = Color("#5c5f61")
	if _far:
		_tw_far_box(Vector3(aw, h + 0.6, ad), Vector3(0, y0 + (h + 0.6) * 0.5, cz), enamel if ribbon else col, 0.9)
		return
	_box("brick", Vector3(aw, h + 0.6, ad), Vector3(0, y0 + (h + 0.6) * 0.5, cz), col)
	if back > 0.0:
		_tw_roof(w, d, cz, y0 - 0.02)  # the old roof round a set-back addition
	var bays := maxi(3, roundi(aw / 6.0))
	var side_bays := maxi(3, roundi(ad / 6.0))
	for f in add:
		var y := y0 + f * fh
		for face in _tw_faces(aw, ad, cz):
			var n: int = bays if face[3] else side_bays
			var len_b: float = face[2] / n
			if ribbon:
				# Enamel spandrel under a glass ribbon, the frame's mullions
				# every bay.
				var c: Vector3 = face[0]
				_quad("paint", c - face[1] * face[2] * 0.5 + Vector3(0, y + 0.05, 0), c + face[1] * face[2] * 0.5 + Vector3(0, y + 0.05, 0),
					c + face[1] * face[2] * 0.5 + Vector3(0, y + 1.25, 0), c - face[1] * face[2] * 0.5 + Vector3(0, y + 1.25, 0), enamel, [],
					face[1].cross(Vector3.UP))
				_glass(Vector3(c.x, y + 2.35, c.z), face[1], face[2] - 0.2, 2.1, r.randf_range(0.1, 0.5))
				for i in n + 1:
					var m: Vector3 = c + face[1] * (-face[2] * 0.5 + i * len_b) + face[1].cross(Vector3.UP) * 0.06
					_box("paint", Vector3(0.1, fh, 0.1), Vector3(m.x, y + fh * 0.5, m.z), Color("#b9bcbd"))
			else:
				for i in n:
					var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + (i + 0.5) * len_b)
					for k in [-1.0, 1.0]:
						var g: Vector3 = c + face[1] * k * len_b * 0.22
						g.y = y + 1.75
						_glass(g, face[1], len_b * 0.3, 1.9, r.randf_range(0.0, 0.6))
	var top := y0 + h
	_box("paint", Vector3(aw + 0.2, 0.15, ad + 0.2), Vector3(0, top + 0.62, cz), Color("#9a9c9c"))  # metal coping
	_tw_roof(aw, ad, cz, top + 0.6)
	_tw_rooftop(aw, ad, cz, top + 0.6, 0.0, false, true)
	var storeys := roundi(top / fh)
	if storeys >= 6:
		_tw_tank(Vector3(r.randf_range(-aw * 0.25, aw * 0.25), top + 0.6, cz + r.randf_range(-ad * 0.2, ad * 0.2)))
	_box("brick", Vector3(5.0, 3.6, 6.0), Vector3(-aw * 0.3, top + 0.6 + 1.8, cz + ad * 0.25), col.darkened(0.1))  # elevator penthouse
	if storeys >= 8:
		_tw_roof_sign(Vector3(0, top + 0.6, zf + back + 1.6), minf(aw * 0.6, 20.0))


## The back of a prewar block, on its alley: a steel service door and a
## loading door in the base, barred windows, the trash dumpsters, and a
## steel fire escape zigzagging up the back (or the light court's back
## wall): stairs and a landing at every floor, the second way out that
## 1900s-20s codes took before enclosed exit stairs (desktop only).
func _tw_alley(w: float, zb: float, ground_h: float, floor_h: float, storeys: int, r: RandomNumberGenerator) -> void:
	var steel := Color("#2b2c2d")
	var ox := r.randf_range(-w * 0.3, -w * 0.1)
	_box("paint", Vector3(1.1, 2.3, 0.08), Vector3(ox, 1.15, zb + 0.04), Color("#5a5f63"))  # service door
	_box("paint", Vector3(3.2, 3.4, 0.08), Vector3(ox - 4.0, 1.7, zb + 0.04), Color("#6c6e6f"))  # loading door
	for i in 3:
		var x := w * 0.1 + i * 4.0
		if x > w * 0.5 - 1.5:
			break
		_glass(Vector3(x, 2.4, zb + 0.04), Vector3(1, 0, 0), 1.4, 1.6, 0.5)
		for k in 4:
			_box("paint", Vector3(0.03, 1.6, 0.03), Vector3(x - 0.55 + k * 0.37, 2.4, zb + 0.1), steel)  # bars
	if not fine_parts:
		return
	for k in 2:
		_box("paint", Vector3(1.9, 1.3, 1.6), Vector3(ox + 2.5 + k * 2.2, 0.65, zb + 1.5), Color(["#2f5a3a", "#3a4a6a"][k]))
		_box("paint", Vector3(1.95, 0.06, 1.65), Vector3(ox + 2.5 + k * 2.2, 1.33, zb + 1.5), Color("#1f2a22"))
	if storeys < 4:
		return
	# The fire escape: on the court's back wall when there is one.
	var fz := zb - _court.y if _court != Vector2.ZERO else zb
	var fx := 0.0 if _court != Vector2.ZERO else r.randf_range(-w * 0.15, w * 0.25)
	var run := 2.6
	for f in range(1, storeys - 1):
		var y := ground_h + floor_h * (f - 1)
		var cz := fz + 0.65
		_box("paint", Vector3(run + 1.6, 0.06, 1.2), Vector3(fx, y, cz), steel)  # landing grate
		_box("paint", Vector3(run + 1.6, 0.04, 0.04), Vector3(fx, y + 0.95, fz + 1.23), steel)  # rail
		for e in [-1.0, 1.0]:
			_box("paint", Vector3(0.04, 0.95, 0.04), Vector3(fx + e * (run * 0.5 + 0.78), y + 0.47, fz + 1.23), steel)
			_box("paint", Vector3(0.05, 0.05, 1.2), Vector3(fx + e * (run * 0.5 + 0.78), y - 0.2, cz), steel)  # bracket
		if f < storeys - 2:
			# The stair up to the next landing, flipping side every floor.
			var s := 1.0 if f % 2 == 0 else -1.0
			var a := Vector3(fx - s * run * 0.5, y, cz)
			var b := Vector3(fx + s * run * 0.5, y + floor_h, cz)
			var along := (b - a).normalized()
			var side := Vector3(0, 0, 1)
			var basis := Basis(along, along.cross(side).normalized() * -1.0, side)
			_box("paint", Vector3((b - a).length(), 0.08, 0.75), (a + b) * 0.5, steel, basis)
	# The drop ladder down from the first landing, held up off the alley.
	_box("paint", Vector3(0.5, 2.2, 0.05), Vector3(fx + run * 0.5 + 0.5, ground_h - 1.3, fz + 1.2), steel)


## The back of a postwar tower's base, where the building is served: two
## truck docks with black seals and yellow bumpers off a concrete apron, a
## steel service door under a small canopy, the trash compactor, and the
## utility's pad-mounted transformer in its green cabinet behind bollards
## (a downtown office of this size takes its power at medium voltage).
## Own random numbers; the small parts are desktop only.
func _tw_dock(w: float, zb: float) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "dock"])
	var dx := r.randf_range(-w * 0.3, w * 0.05)
	var room := depth - zb
	if room > 3.0:
		_flat_rect("drive", dx - 6.5, dx + 6.5, zb, zb + minf(room - 0.3, 14.0), 0.075)
	for k in 2:
		var x := dx - 3.0 + k * 6.0
		_box("paint", Vector3(3.0, 3.2, 0.08), Vector3(x, 1.6 + 1.2, zb + 0.04), Color("#7a7d80"))  # dock door
		_box("paint", Vector3(3.6, 3.6, 0.3), Vector3(x, 2.6, zb + 0.15), Color("#1d1e1f"))  # seal
		for e in [-1.0, 1.0]:
			_box("paint", Vector3(0.3, 0.5, 0.15), Vector3(x + e * 1.2, 1.0, zb + 0.35), Color("#d8b024"))  # bumpers
	var sx := dx + 7.5
	_box("paint", Vector3(1.0, 2.2, 0.08), Vector3(sx, 1.1, zb + 0.04), Color("#5a5f63"))
	_box("paint", Vector3(1.8, 0.12, 1.0), Vector3(sx, 2.6, zb + 0.5), Color("#3a3c3e"))
	if not fine_parts or room < 3.0:
		return
	_box("paint", Vector3(2.4, 1.8, 4.5), Vector3(dx - 10.5, 0.9, zb + 2.3), Color(["#2f5a3a", "#3a4a6a", "#5a5c5e"][r.randi() % 3]))  # compactor
	_box("paint", Vector3(1.2, 1.2, 0.8), Vector3(dx - 10.5, 1.9, zb + 0.4), Color("#4a4c4e"))  # chute
	if room > 5.0:
		var tx := sx + 4.0
		_box("concrete", Vector3(2.6, 0.15, 2.4), Vector3(tx, 0.08, zb + 2.0), Color("#b9b5ac"))
		_box("paint", Vector3(2.0, 1.6, 1.8), Vector3(tx, 0.95, zb + 2.0), Color("#56705a"))  # transformer
		for b in [Vector2(-1.5, 3.6), Vector2(1.5, 3.6), Vector2(1.7, 0.6)]:
			_box("paint", Vector3(0.18, 1.1, 0.18), Vector3(tx + b.x, 0.55, zb + b.y), Color("#e0b020"))  # bollards


## A Chicago block's light court (width along the street, depth from the
## back), or zero when it is built solid.
var _court := Vector2.ZERO
var _court_z := 0.0  # its front wall


## The block's plan as rectangles [w, d, cz, cx]: the whole block, or, with
## a light court, the front range and the two wings either side of it.
func _court_rects(w: float, d: float, zf: float) -> Array:
	if _court == Vector2.ZERO:
		return [[w, d, zf + d * 0.5, 0.0]]
	var dz := d - _court.y
	var ww := (w - _court.x) * 0.5
	return [[w, dz, zf + dz * 0.5, 0.0], [ww, _court.y, zf + dz + _court.y * 0.5, -(w - ww) * 0.5],
		[ww, _court.y, zf + dz + _court.y * 0.5, (w - ww) * 0.5]]


## A box over the block's plan from `y` up `h`, standing `grow` proud of
## every wall (into the court too): the shaft, a band, the cornice.
func _tw_u(w: float, d: float, zf: float, y: float, h: float, grow: float, col: Color, mat: String) -> void:
	for r in _court_rects(w, d, zf):
		_box(mat, Vector3(r[0] + grow, h, r[1] + grow), Vector3(r[3], y + h * 0.5, r[2]), col)


## True when a spot on the block's back wall falls across its light court.
func _in_court(c: Vector3, edge := 0.0) -> bool:
	return _court != Vector2.ZERO and c.z > _court_z + 0.1 and absf(c.x) < _court.x * 0.5 - edge


## The court's three walls: [centre, right, length], each facing into it.
func _court_walls(zc: float, zb: float) -> Array:
	var hx := _court.x * 0.5
	var mz := (zc + zb) * 0.5
	return [[Vector3(0, 0, zc + 0.03), Vector3(1, 0, 0), _court.x],
		[Vector3(-hx + 0.03, 0, mz), Vector3(0, 0, -1), _court.y],
		[Vector3(hx - 0.03, 0, mz), Vector3(0, 0, 1), _court.y]]


# ---------------------------------------------------------------- Art Deco setbacks

func _tw_deco(to_curb: float, width: float, storeys: int) -> void:
	var w := minf(width - 1.0, rng.randf_range(28.0, 40.0))
	var d := minf(depth - 4.0, rng.randf_range(26.0, 36.0))
	var zf := 0.4
	var ground_h := 5.5
	var floor_h := 3.7
	var stone := Color(_pick(TW_LIMESTONE))
	var spandrel := Color(_pick(TW_SPANDREL))
	# About a third are buff or tan brick with a limestone portal, as many
	# Midwest deco towers are (own random numbers, so no draw moves).
	var dr := RandomNumberGenerator.new()
	dr.seed = hash([rng.seed, "deco look"])
	var base_stone := stone
	if dr.randf() < 0.35:
		stone = Color(["#c9a974", "#b8956a", "#d2b98c"][dr.randi() % 3])
	var crown_kind := dr.randi() % 3
	# The 1916 rule: the street wall rises about a third of the way, then
	# each tier steps back, ending in a slim tower and a stepped crown.
	# On an assembled site the street wall runs the whole frontage and the
	# tower rises from the middle of it (the Chicago Board of Trade's base
	# fills its block end).
	var w0 := maxf(w, minf(width - 1.0, 64.0))
	var tiers := [[w0, d, ceili(storeys * 0.4)], [w - 6.0, d - 6.0, ceili(storeys * 0.7)], [w - 12.0, d - 12.0, storeys]]
	if storeys < 12:
		tiers = [[w0, d, ceili(storeys * 0.6)], [w - 6.0, d - 6.0, storeys]]
	if _far:
		var fy := 0.0
		for t in tiers:
			var y1: float = ground_h + floor_h * (int(t[2]) - 1)
			_tw_far_box(Vector3(t[0], y1 - fy, t[1]), Vector3(0, (fy + y1) * 0.5, zf + d * 0.5), stone, 0.9)
			fy = y1
		_tw_far_box(Vector3(tiers[-1][0] - 4.0, 3.5, tiers[-1][1] - 4.0), Vector3(0, fy + 1.75, zf + d * 0.5), stone, 0.0)
		return
	_downtown_walk(to_curb, width, zf)
	_tw_dock(w0, zf + d)
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
				# The spandrel fills the wall from this window down to the one
				# below, so between the piers the window bays read as
				# unbroken dark strips (the deco skyscraper's verticality:
				# Chicago's Board of Trade, Indianapolis's Indiana Bell).
				var o: Vector3 = face[1].cross(Vector3.UP) * 0.02 + Vector3(0, -1.85, 0)
				_quad("paint", c + o - r - Vector3(0, 0.85, 0), c + o + r - Vector3(0, 0.85, 0), c + o + r + Vector3(0, 0.85, 0),
					c + o - r + Vector3(0, 0.85, 0), spandrel, [], face[1].cross(Vector3.UP))
		# Piers run unbroken to the top of each tier and stand above it.
		for face in _tw_faces(tw, td, cz):
			var n := maxi(3, roundi(face[2] / 2.4))
			var len_b: float = face[2] / n
			var out: Vector3 = face[1].cross(Vector3.UP)
			for i in n + 1:
				var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + i * len_b) + out * 0.15
				var ph := (y1 - maxf(y0, ground_h)) + (1.2 if i % 2 == 0 else 0.6)
				c.y = maxf(y0, ground_h) + ph * 0.5
				# Major piers at the bay lines, slimmer minor ones between.
				var pw := 0.85 if i % 2 == 0 else 0.4
				_box("brick", Vector3(pw, ph, 0.6 if i % 2 == 0 else 0.45), c, stone.lightened(0.05), _tw_yaw(face[1]))
		_box("paint", Vector3(tw + 0.2, 0.6, td + 0.2), Vector3(0, y1 + 0.3, cz), stone.darkened(0.08))  # coping
		_tw_roof(tw, td, cz, y1)  # each setback's roof (the far version steps with them)
		y0 = y1
		f0 = f1
	# The ground floor: bronze shopfronts and a tall lobby portal.
	var cz0 := zf + d * 0.5
	for face in [_tw_faces(w0, d, cz0)[0]]:
		var n := maxi(3, roundi(w0 / 7.0))
		for i in n:
			var c: Vector3 = face[0] + face[1] * (-w0 * 0.5 + (i + 0.5) * w0 / n)
			c.y = 2.6
			_glass(c, face[1], w0 / n - 1.2, 3.8, 0.0)
	_box("brick", Vector3(5.0, 8.0, 0.6), Vector3(0, 4.0, zf - 0.3), base_stone.lightened(0.1))  # limestone portal
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
	# The crown hides the house tank, as deco towers did: steps under a
	# flagpole (Indianapolis's Circle Tower), a copper or gilded pyramid
	# (the Chicago Board of Trade, Fort Wayne's Lincoln Tower's lantern
	# cousins), or a lit lantern with a mast.
	var cz1 := zf + d * 0.5
	match crown_kind:
		1:
			var pcol := TW_COPPER if dr.randf() < 0.6 else Color("#b89a4a")
			_tw_pyramid(Vector3(0, top, cz1), cw + 0.6, cd + 0.6, minf(cw, cd) * 0.6, pcol)
		2:
			var lw := maxf(cw * 0.55, 3.0)
			var ld := maxf(cd * 0.55, 3.0)
			_box("brick", Vector3(lw, 5.0, ld), Vector3(0, top + 2.5, cz1), stone)
			for face in _tw_faces(lw, ld, cz1):
				var c: Vector3 = face[0]
				c.y = top + 2.6
				_glass(c, face[1], face[2] - 1.2, 3.6, 0.0)
			_tw_pyramid(Vector3(0, top + 5.0, cz1), lw + 0.4, ld + 0.4, minf(lw, ld) * 0.5, TW_COPPER)
			_tw_mast(Vector3(0, top + 5.0 + minf(lw, ld) * 0.5, cz1), 6.0)
		_:
			_box("metal", Vector3(0.2, 9.0, 0.2), Vector3(0, top + 4.5, cz1), Color("#c9cccd"))  # flagpole
			_box("paint", Vector3(2.2, 1.3, 0.04), Vector3(-1.2, top + 8.3, cz1), Color("#3c3b6e"))


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
	# Later glass towers vary the box (own random numbers, so the builder's
	# don't move): cut corners, which 1970s-80s towers used for more
	# corner offices, or an upper block set back on a sky terrace.
	var vr := RandomNumberGenerator.new()
	vr.seed = hash([rng.seed, "glass shape"])
	var chamfer := 0.0
	var tele := 0
	if storeys >= 12:
		var x := vr.randf()
		if x < 0.3:
			chamfer = vr.randf_range(2.5, minf(w, d) * 0.18)
		elif x < 0.55 and storeys >= 18:
			tele = ceili(storeys * 0.3)
	if _far:
		_tw_far_box(Vector3(w - 6.0, ground_h, d - 6.0), Vector3(0, ground_h * 0.5, cz), Color("#2a2c2e"), 0.0)
		var split := top - floor_h * tele
		_tw_far_box(Vector3(w, split - ground_h, d), Vector3(0, (ground_h + split) * 0.5, cz), tint.darkened(0.55), 1.0)
		if tele > 0:
			_tw_far_box(Vector3(w - 6.0, top - split, d - 6.0), Vector3(0, (split + top) * 0.5, cz), tint.darkened(0.55), 1.0)
		_tw_far_box(Vector3(w - (6.0 if tele > 0 else 0.0) - chamfer, mech, d - (6.0 if tele > 0 else 0.0) - chamfer), Vector3(0, top + mech * 0.5, cz), Color("#2b2d2f"), 0.0)
		return
	# The core and lobby, recessed behind the columns.
	_box("paint", Vector3(w - 6.0, ground_h, d - 6.0), Vector3(0, ground_h * 0.5, cz), Color("#2a2c2e"))
	for face in _tw_faces(w - 6.0, d - 6.0, cz):
		_glass(face[0] + Vector3(0, ground_h * 0.5, 0), face[1], face[2] - 0.6, ground_h - 0.6, 0.0)
	var cols := maxi(3, roundi(w / 9.0))
	for i in cols + 1:
		for zz in [zf + 0.5, zf + d - 0.5]:
			_box("metal", Vector3(0.6, ground_h, 0.6), Vector3(-w * 0.5 + 0.5 + i * (w - 1.0) / cols, ground_h * 0.5, zz), TW_STEEL)
	if chamfer > 0.0 or tele > 0:
		_tw_glass_shaped(w, d, cz, ground_h, floor_h, storeys, chamfer, tele, mech)
	else:
		_tw_glass_box(w, d, cz, ground_h, floor_h, storeys, top, mech)
	# The plaza: granite paving, planters and the name on a low wall.
	_flat_rect("drive", -width * 0.5 + 0.5, width * 0.5 - 0.5, -to_curb + RoadStyle.CURB_WIDTH, zf + d, 0.06)
	for s in [-1.0, 1.0]:
		_box("concrete", Vector3(4.0, 0.6, 2.0), Vector3(s * w * 0.3, 0.3, zf * 0.45), Color("#8f8b84"))
		_shrub(Vector3(s * w * 0.3, 0.6, zf * 0.45), 0.6)
	_box("concrete", Vector3(6.0, 0.9, 0.5), Vector3(0, 0.45, zf * 0.25), Color("#8f8b84"))
	_sign(Vector3(0, 0.95, zf * 0.25 - 0.27), 5.0, 0.5)
	_tw_plaza(width, zf, w)
	if depth - (zf + d) > 12.0:
		_parking(-width * 0.5 + 0.6, width * 0.5 - 0.6, zf + d + 2.0, depth - 1.0, width)
	for s in [-1.0, 1.0]:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(s * (width * 0.5 - 3.0), 0, zf * 0.6), pick[0], pick[1], rng.randf_range(0.8, 1.0)])


## A modernist tower's plaza (Mies's Federal Center and IBM plazas in
## Chicago, the bank plazas of downtown Indianapolis): granite paving on a
## grid of joints, honey locusts in square grates, long granite benches,
## and on most a public sculpture of painted steel or weathering Cor-ten
## plates (Calder's Flamingo, Chicago's percent-for-art pieces). Its own
## random numbers, so the builder's don't move.
func _tw_plaza(width: float, zf: float, w: float) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "plaza"])
	var x0 := -width * 0.5 + 0.5
	var x1 := width * 0.5 - 0.5
	var joint := Color("#7d7a74")
	if fine:
		var x := x0 + 3.0
		while x < x1:
			_flat_rect("line", x - 0.04, x + 0.04, 0.2, zf - 0.2, 0.065, joint)
			x += 3.0
		var z := 3.0
		while z < zf - 0.5:
			_flat_rect("line", x0, x1, z - 0.04, z + 0.04, 0.065, joint)
			z += 3.0
	# Honey locusts in grates along the street side, clear of the planters.
	var n := maxi(2, int((width - 4.0) / 12.0)) if r.randf() < 0.65 else 0
	for i in n:
		var tx := lerpf(x0 + 3.0, x1 - 3.0, (i + 0.5) / n)
		if absf(absf(tx) - w * 0.3) < 2.5 or absf(tx) < 4.0:
			continue
		_flat_rect("line", tx - 0.9, tx + 0.9, 1.4, 3.2, 0.068, Color("#3a3836"))
		var tint: Color = TreeField.LEAF[TreeField.Species.LOCUST]
		trees.append([Vector3(tx, 0, 2.3), TreeField.Species.LOCUST, tint.lightened(r.randf_range(-0.05, 0.08)), r.randf_range(0.65, 0.8)])
	# Long granite benches facing the street.
	for sx in [-1.0, 1.0]:
		_box("concrete", Vector3(3.2, 0.45, 0.7), Vector3(sx * (w * 0.3), 0.225, zf * 0.72), Color("#9a958c"))
	# The sculpture, beside the tower where the plaza is wide enough.
	if r.randf() < 0.7 and (width - w) * 0.5 >= 9.0:
		var red := r.randf() < 0.5
		var col := Color("#c23a2b") if red else Color("#6e4126")
		var at := Vector3((w * 0.5 + (width - w) * 0.25) * (1.0 if r.randf() < 0.5 else -1.0), 0, zf + 5.0)
		var h := r.randf_range(6.0, 9.0)
		# Three bent plates leaning in on each other, and a low arch between.
		for k in 3:
			var a := TAU * k / 3.0 + r.randf_range(-0.3, 0.3)
			var foot := at + Vector3(cos(a), 0, sin(a)) * 2.4
			var lean := Basis(Vector3(-sin(a), 0, cos(a)), 0.32) * Basis(Vector3.UP, -a)
			_box("metal", Vector3(0.12, h, 1.4), foot + Vector3(0, h * 0.5, 0) + (at - foot) * 0.35, col, lean)
		_box("metal", Vector3(3.6, 0.5, 0.12), at + Vector3(0, h * 0.62, 0), col, Basis(Vector3.UP, r.randf_range(0.0, PI)))
		_box("concrete", Vector3(6.0, 0.1, 6.0), at + Vector3(0, 0.05, 0), Color("#8f8b84"))


## The International Style box: a dark core wrapped in glass floor by
## floor, I-beam mullions and floor lines in the steel, a louvred top.
func _tw_glass_box(w: float, d: float, cz: float, ground_h: float, floor_h: float, storeys: int, top: float, mech: float) -> void:
	_box("paint", Vector3(w, top - ground_h, d), Vector3(0, (ground_h + top) * 0.5, cz), Color("#1c1e20"))
	# A tall tower's mid-height mechanical floor: air handlers serving the
	# floors above and below, a louvred band in the curtain wall (towers of
	# 24 storeys and up put one about every 20-30 floors). Own random
	# numbers, so the builder's don't move.
	var mr := RandomNumberGenerator.new()
	mr.seed = hash([rng.seed, "mech floor"])
	var mid := storeys / 2 if storeys >= 24 and mr.randf() < 0.7 else -1
	for f in range(1, storeys):
		var y := ground_h + floor_h * (f - 1) + floor_h * 0.5
		for face in _tw_faces(w, d, cz):
			var c: Vector3 = face[0]
			c.y = y
			var blinds := rng.randf_range(0.1, 0.5)
			if f != mid:
				_glass(c, face[1], face[2] - 0.2, floor_h - 0.25, blinds)
		if f == mid:
			_box("metal", Vector3(w + 0.08, floor_h, d + 0.08), Vector3(0, y, cz), Color("#3a3d40"))
			_tw_louvres(w + 0.08, d + 0.08, cz, y - floor_h * 0.5, floor_h)
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
	_tw_louvres(w, d, cz, top, mech)
	_tw_roof(w, d, cz, top + mech)
	_tw_rooftop(w, d, cz, top + mech, 0.0, true)
	_tw_name(Vector3(0, top + mech * 0.2, cz - d * 0.5), w * 0.7, mech * 0.6)


## Desktop: a mechanical floor's louvre blades, horizontal fins about
## 45 cm apart round a w by d band from `y`, `h` tall.
func _tw_louvres(w: float, d: float, cz: float, y: float, h: float, x := 0.0) -> void:
	if not fine_parts:
		return
	for face in _tw_faces(w, d, cz, x):
		var out: Vector3 = face[1].cross(Vector3.UP)
		for i in int((h - 0.3) / 0.45):
			var c: Vector3 = face[0] + out * 0.08
			c.y = y + 0.35 + i * 0.45
			_box("metal", Vector3(face[2], 0.06, 0.16), c, Color("#5d6164"), _tw_yaw(face[1]))


## The glass tower as a prism: corners cut by `chamfer`, and the top
## `tele` floors on a block 3 m in on every side over a sky terrace.
func _tw_glass_shaped(w: float, d: float, cz: float, ground_h: float, floor_h: float, storeys: int, chamfer: float, tele: int, mech: float) -> void:
	var tiers := [[w, d, 1, storeys - tele]]
	if tele > 0:
		tiers.append([w - 6.0, d - 6.0, storeys - tele, storeys])
	var tw := w
	var td := d
	var y1 := ground_h
	for t in tiers:
		tw = t[0]
		td = t[1]
		var y0: float = ground_h + floor_h * (int(t[2]) - 1)
		y1 = ground_h + floor_h * (int(t[3]) - 1)
		var c := minf(chamfer, minf(tw, td) * 0.25)
		var edges := _tw_prism_edges(tw, td, cz, c)
		for e in edges:
			var a: Vector3 = e[0]
			var b: Vector3 = e[1]
			var along: Vector3 = (b - a).normalized()
			var out := along.cross(Vector3.UP)
			var len := a.distance_to(b)
			_quad("paint", a + Vector3(0, y0, 0), b + Vector3(0, y0, 0), b + Vector3(0, y1, 0), a + Vector3(0, y1, 0), Color("#1c1e20"), [], out)
			var mid := (a + b) * 0.5 + out * 0.03
			for f in range(int(t[2]), int(t[3])):
				var y := ground_h + floor_h * (f - 1) + floor_h * 0.5
				_glass(mid + Vector3(0, y, 0), along, len - 0.2, floor_h - 0.25, rng.randf_range(0.1, 0.5))
				_box("metal", Vector3(len + 0.1, 0.12, 0.25), mid + out * 0.1 + Vector3(0, ground_h + floor_h * (f - 1), 0), TW_STEEL, _tw_yaw(along))
			var n := maxi(1, roundi(len / 1.6))
			for i in n + 1:
				var p: Vector3 = a + along * (i * len / n) + out * 0.12
				p.y = (y0 + y1) * 0.5
				_box("metal", Vector3(0.14, y1 - y0, 0.22), p, TW_STEEL, _tw_yaw(along))
		# The cap: the sky terrace (or the roof) inside the parapet.
		var pts := []
		for e in edges:
			pts.append(e[0])
		var mid_pt := Vector3(0, y1 + 0.03, cz)
		for k in pts.size():
			var a: Vector3 = pts[k]
			var b: Vector3 = pts[(k + 1) % pts.size()]
			_tri("paint", mid_pt, b + Vector3(0, y1 + 0.03, 0), a + Vector3(0, y1 + 0.03, 0), GRAVEL if t == tiers[-1] else Color("#8f8b84"), [], Vector3.UP)
		if t != tiers[-1]:
			# Planters and a glass guard round the terrace.
			for e in edges:
				var a: Vector3 = e[0]
				var b: Vector3 = e[1]
				var along: Vector3 = (b - a).normalized()
				var out := along.cross(Vector3.UP)
				_glass((a + b) * 0.5 - out * 0.2 + Vector3(0, y1 + 0.55, 0), along, a.distance_to(b) - 0.4, 1.1, 0.0)
			for s in [-1.0, 1.0]:
				_shrub(Vector3(s * (tw * 0.5 - 2.0), y1, cz - td * 0.5 + 1.5), 0.7)
	var c := minf(chamfer, minf(tw, td) * 0.25)
	_box("metal", Vector3(tw - c * 1.2, mech, td - c * 1.2), Vector3(0, y1 + mech * 0.5, cz), Color("#2b2d2f"))
	_tw_roof(tw - c * 1.2, td - c * 1.2, cz, y1 + mech)
	_tw_rooftop(tw - c * 1.2, td - c * 1.2, cz, y1 + mech, 0.0, true)
	_tw_name(Vector3(0, y1 + mech * 0.2, cz - (td - c * 1.2) * 0.5), (tw - c * 1.2) * 0.75, mech * 0.6)


## The outline of a w by d footprint with corners cut by c, as edges
## [from, to] at y 0, each running "right as seen from outside" (so
## along x UP points out), starting along the street front.
func _tw_prism_edges(w: float, d: float, cz: float, c: float) -> Array:
	var hw := w * 0.5
	var hd := d * 0.5
	var p := [Vector3(hw - c, 0, cz - hd), Vector3(-hw + c, 0, cz - hd), Vector3(-hw, 0, cz - hd + c), Vector3(-hw, 0, cz + hd - c),
		Vector3(-hw + c, 0, cz + hd), Vector3(hw - c, 0, cz + hd), Vector3(hw, 0, cz + hd - c), Vector3(hw, 0, cz - hd + c)]
	var out := []
	for i in p.size():
		var a: Vector3 = p[i]
		var b: Vector3 = p[(i + 1) % p.size()]
		if a.distance_to(b) > 0.1:
			out.append([a, b])
	return out


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
	if not _far:
		_tw_name(Vector3(0, float(heights[1]) - floor_h * 1.6, cz - s * 1.5), s * 0.9, floor_h * 1.1)
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
	_tw_rooftop(w, d, cz, top + 0.8)
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


## A 2010s apartment tower (the glass point towers of Chicago's West Loop
## and South Loop, Indianapolis's and Columbus's new downtown high-rises):
## floor-to-ceiling glass behind white slab edges, and cantilevered
## balconies that shift from side to side floor by floor, so the faces
## read as a checkerboard; frosted glass guards; a glass lobby under a
## porte-cochere on a drop-off loop; a dark mechanical penthouse on top.
## Its own random numbers, so the builder's don't move.
func _tw_balcony(to_curb: float, width: float, storeys: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "balcony tower"])
	var w := minf(width - 10.0, r.randf_range(24.0, 30.0))
	var d := minf(depth - 22.0, r.randf_range(22.0, 28.0))
	if w < 16.0 or d < 14.0 or _far:
		_tw_slab(to_curb, width, storeys)
		return
	var zf := minf(r.randf_range(11.0, 14.0), depth - d - 2.0)
	var cz := zf + d * 0.5
	var ground_h := 5.0
	var floor_h := 3.1
	var top := ground_h + floor_h * (storeys - 1)
	var edge := Color(["#e6e4de", "#d9d6cf", "#c9ccce"][r.randi() % 3])
	var guard := Color("#a9bcc4")
	var mech := 4.0
	# The core behind the glass, and the glass floor by floor.
	_box("paint", Vector3(w - 0.4, top, d - 0.4), Vector3(0, top * 0.5, cz), Color("#2a2d30"))
	var shift := r.randf_range(0.35, 0.5)  # how much of a face one floor's balconies cover
	for f in range(1, storeys):
		var y0 := ground_h + floor_h * (f - 1)
		_box("paint", Vector3(w + 0.2, 0.28, d + 0.2), Vector3(0, y0 + 0.14, cz), edge)  # slab edge
		for face in _tw_faces(w, d, cz):
			var c: Vector3 = face[0]
			var along: Vector3 = face[1]
			var len: float = face[2]
			var out := along.cross(Vector3.UP)
			_glass(c + Vector3(0, y0 + 0.28 + (floor_h - 0.4) * 0.5, 0), along, len - 0.3, floor_h - 0.45, r.randf_range(0.05, 0.6))
			# This floor's balcony: at one end of the face or the other, by floor.
			var bl := len * shift
			var off := (len - bl) * 0.5 * (1.0 if (f + int(face[3])) % 2 == 0 else -1.0)
			var bc: Vector3 = c + along * off + out * 0.9
			var yaw := _tw_yaw(along)
			_box("paint", Vector3(bl, 0.24, 1.8), bc + Vector3(0, y0 + 0.12, 0), edge, yaw)
			_box("paint", Vector3(bl, 1.05, 0.04), bc + out * 0.88 + Vector3(0, y0 + 0.24 + 0.53, 0), guard, yaw)
			if fine:
				_box("metal", Vector3(bl, 0.05, 0.08), bc + out * 0.88 + Vector3(0, y0 + 1.32, 0), Color("#5d6266"), yaw)
				for sd in [-1.0, 1.0]:
					_box("paint", Vector3(0.04, 1.05, 1.76), bc + along * sd * (bl * 0.5 - 0.02) + Vector3(0, y0 + 0.77, 0), guard, yaw)
	# The lobby: glass all round, set back under the second floor.
	for face in _tw_faces(w - 3.0, d - 3.0, cz):
		_glass(face[0] + Vector3(0, ground_h * 0.5, 0), face[1], face[2] - 0.4, ground_h - 0.5, 0.0)
	# Parapet, roof and the dark mechanical penthouse.
	_box("paint", Vector3(w + 0.2, 1.0, d + 0.2), Vector3(0, top + 0.5, cz), edge)
	_tw_roof(w, d, cz, top + 1.0)
	_tw_rooftop(w, d, cz, top + 1.0, 0.0, false, true)
	_tw_roof_deck(w, d, cz, top + 1.0, mech, edge, guard)
	# The porte-cochere over a drop-off loop, and the walk to the curb.
	_box("paint", Vector3(10.0, 0.6, 7.0), Vector3(0, ground_h - 0.3, zf - 3.5), edge)
	for sx in [-1.0, 1.0]:
		_box("metal", Vector3(0.3, ground_h - 0.6, 0.3), Vector3(sx * 4.6, (ground_h - 0.6) * 0.5, zf - 6.6), Color("#5d6266"))
	_flat_rect("drive", -8.0, 8.0, zf - 9.0, zf - 0.5, 0.07)
	for sx in [-1.0, 1.0]:
		_flat_rect("drive", sx * 8.0 - 3.0, sx * 8.0 + 3.0, -to_curb + RoadStyle.CURB_WIDTH, zf - 9.0, 0.07)
	_box("concrete", Vector3(5.0, 0.6, 3.0), Vector3(0, 0.3, zf - 13.0 + 3.0), Color("#8f8b84"))  # island planter
	_shrub(Vector3(0, 0.6, zf - 10.0), 0.8)
	_sign(Vector3(0, 0.3, zf - 11.6), 3.0, 0.6)
	var keep := rng
	rng = r
	var sx := -w * 0.5 + 1.0
	while sx < w * 0.5 - 1.0:
		if absf(sx) > 6.0:
			_shrub(Vector3(sx, 0, zf - 0.9), r.randf_range(0.5, 0.8))
		sx += r.randf_range(2.2, 3.4)
	rng = keep
	for s2 in [-1.0, 1.0]:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(s2 * (width * 0.5 - 3.5), 0, zf * 0.5), pick[0], pick[1], rng.randf_range(0.8, 1.0)])


## A 2000s-10s apartment tower's roof: the mechanical penthouse clad in
## metal panels a shade off the slab edges, with a louvred band and the
## elevator overrun standing above it, at the back of the roof; in front of
## it, on most, the residents' roof deck (grills, a pergola, planters and
## loungers behind a glass guard), as the rental and condo towers of
## Indianapolis and Chicago's River North have. Its own random numbers.
func _tw_roof_deck(w: float, d: float, cz: float, y: float, mech: float, edge: Color, guard: Color, x := 0.0) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "roof deck"])
	var pw := w * 0.55
	var pd := d * 0.45
	var pz := cz + d * 0.5 - pd * 0.5 - 1.5
	var clad := edge.darkened(r.randf_range(0.25, 0.45))
	_box("membrane", Vector3(pw, mech, pd), Vector3(x, y + mech * 0.5, pz), clad)
	_tw_roof(pw, pd, pz, y + mech, x)
	_tw_louvres(pw, pd, pz, y + mech * 0.3, mech * 0.5, x)
	# The elevator overrun, a little taller, over the core.
	var ox := x + r.randf_range(-pw * 0.2, pw * 0.2)
	_box("membrane", Vector3(4.0, 1.8, 3.4), Vector3(ox, y + mech + 0.9, pz), clad.darkened(0.1))
	_tw_roof(4.0, 3.4, pz, y + mech + 1.8, ox)
	if r.randf() >= 0.7:
		return
	# The deck: pavers, a glass guard set in from the parapet, a pergola.
	var z0 := cz - d * 0.5 + 1.2
	var z1 := pz - pd * 0.5 - 0.3
	if z1 - z0 < 5.0:
		return
	var dw := w - 2.4
	_box("paint", Vector3(dw, 0.12, z1 - z0), Vector3(x, y + 0.06, (z0 + z1) * 0.5), Color("#b9b1a3"))
	_glass(Vector3(x, y + 0.65, z0 - 0.02), Vector3(-1, 0, 0), dw, 1.1, 0.0)
	for s in [-1.0, 1.0]:
		_glass(Vector3(x + s * dw * 0.5, y + 0.65, (z0 + z1) * 0.5), Vector3(0, 0, s), z1 - z0, 1.1, 0.0)
	var gx := x + r.randf_range(-dw * 0.2, dw * 0.2)
	var gw := minf(dw * 0.4, 9.0)
	var wood := Color("#6b4a32")
	for cx in [gx - gw * 0.5, gx + gw * 0.5]:
		for zz in [z0 + 1.5, z1 - 0.8]:
			_box("paint", Vector3(0.25, 2.7, 0.25), Vector3(cx, y + 1.35, zz), Color("#2f3133"))
	if fine_parts:
		var n := int(gw / 0.6)
		for i in n + 1:
			_box("paint", Vector3(0.08, 0.2, z1 - z0 - 1.6), Vector3(gx - gw * 0.5 + i * gw / n, y + 2.75, (z0 + z1) * 0.5 + 0.35), wood)
		for i in 4:  # loungers along the guard
			_box("paint", Vector3(0.7, 0.35, 1.9), Vector3(x - dw * 0.5 + 2.0 + i * 1.4, y + 0.3, z0 + 1.6), Color("#e8e4da"))
		_box("metal", Vector3(1.6, 0.9, 0.7), Vector3(x + dw * 0.5 - 2.0, y + 0.45, z1 - 0.8), Color("#8d9194"))  # grills
	for k in 3:  # planters with small trees and grasses
		var px := x + lerpf(-dw * 0.5 + 1.5, dw * 0.5 - 1.5, k / 2.0)
		_box("concrete", Vector3(1.6, 0.8, 1.6), Vector3(px, y + 0.4, (z0 + z1) * 0.5), Color("#8f8b84"))
		_shrub(Vector3(px, y + 0.8, (z0 + z1) * 0.5), 0.7)


# ---------------------------------------------------------------- postmodern

const TW_GRANITE := ["#b48f80", "#a3897a", "#c4b29c", "#8c7b70", "#d0c4b4"]  # rose, buff and grey granite
const TW_MIRROR := ["#2e3b44", "#33443c", "#463b33", "#2b3440"]  # reflective blue, green, bronze, grey glass
const TW_COPPER := Color("#6f9a86")  # weathered copper
## How far off a tower's name reads: 3-4 m letters, about a kilometre.
const TW_NAME_RANGE := 1200.0


## A 1980s-90s postmodern office tower: built to the sidewalk on a tall
## granite base with an arched entry; notched corners (eight corner
## offices a floor); bands of reflective glass between granite spandrels
## and a glass slot up the middle of the street faces; one or two setbacks
## near the top and a crown (_tw_crown).
func _tw_pomo(to_curb: float, width: float, storeys: int) -> void:
	var w := minf(width - 2.0, rng.randf_range(26.0, 36.0))
	var d := minf(depth - 6.0, rng.randf_range(24.0, 32.0))
	if w < 16.0 or d < 14.0:
		_tw_glass(to_curb, width, storeys)
		return
	var zf := rng.randf_range(1.0, 4.0)
	var cz := zf + d * 0.5
	var ground_h := 6.0
	var floor_h := 3.9
	var base_f := 3 if storeys >= 12 else 2
	var y_base := ground_h + floor_h * (base_f - 1)
	var granite := Color(_pick(TW_GRANITE))
	var base_col := granite.darkened(0.18)
	var mirror := Color(_pick(TW_MIRROR))
	var crown: String = ["gable", "pyramid", "spires", "stepped"][rng.randi() % 4]
	# The shaft and two setbacks, each tier 3 m in on every side.
	var tiers := [[w, d, ceili(storeys * 0.8)], [w - 6.0, d - 6.0, ceili(storeys * 0.92)], [w - 12.0, d - 12.0, storeys]]
	if storeys < 14:
		tiers = [[w, d, storeys]]
	if _far:
		_tw_far_box(Vector3(w, y_base, d), Vector3(0, y_base * 0.5, cz), base_col, 0.5)
		var fy := y_base
		for t in tiers:
			var y1: float = ground_h + floor_h * (int(t[2]) - 1)
			_tw_far_box(Vector3(t[0], y1 - fy, t[1]), Vector3(0, (fy + y1) * 0.5, cz), granite.lerp(mirror, 0.45), 0.8)
			fy = y1
		_tw_far_box(Vector3(tiers[-1][0] * 0.7, 6.0, tiers[-1][1] * 0.7), Vector3(0, fy + 3.0, cz), TW_COPPER if crown != "spires" else granite, 0.0)
		return
	_downtown_walk(to_curb, width, zf)
	_tw_dock(w - minf(w, d) * 0.3, zf + d)
	# The base: dark polished granite, tall shop windows, the arched entry.
	_tw_notched("brick", w, d, cz, 0.0, y_base, base_col, minf(w, d) * 0.14)
	var bays := maxi(3, roundi(w / 7.0))
	for i in bays:
		var x := -w * 0.5 + (i + 0.5) * w / bays
		if absf(x) < 4.0:
			continue
		_glass(Vector3(x, 2.6, zf - 0.03), Vector3(-1, 0, 0), w / bays - 1.8, 4.2, rng.randf_range(0.0, 0.2))
		for f in range(1, base_f):
			_glass(Vector3(x, ground_h + floor_h * (f - 1) + 1.8, zf - 0.03), Vector3(-1, 0, 0), w / bays - 2.2, 2.2, rng.randf_range(0.1, 0.5))
	_tw_arch(Vector3(0, 0, zf), 7.0, minf(y_base - 1.0, 10.0), granite.lightened(0.08), mirror)
	_sign(Vector3(0, minf(y_base - 1.0, 10.0) + 0.6, zf - 0.7), 6.0, 0.7)
	# The shaft, tier by tier: granite with a band of glass on every floor,
	# on the notches too, and the glass slot up the street faces.
	var y0 := y_base
	var f0 := base_f
	var cw := w
	var cd := d
	for t in tiers:
		cw = t[0]
		cd = t[1]
		var f1: int = t[2]
		var y1 := ground_h + floor_h * (f1 - 1)
		var notch := minf(cw, cd) * 0.14
		_tw_notched("brick", cw, cd, cz, y0, y1, granite, notch)
		for f in range(f0, f1):
			var y := ground_h + floor_h * (f - 1) + floor_h * 0.55
			for face in _tw_notch_faces(cw, cd, cz, notch):
				_glass(face[0] + Vector3(0, y, 0), face[1], face[2] - 0.8, floor_h * 0.5, rng.randf_range(0.05, 0.4))
		for face in _tw_faces(cw - notch * 2.0, cd, cz):
			if face[3]:
				var out: Vector3 = face[1].cross(Vector3.UP)
				_glass(face[0] + out * 0.02 + Vector3(0, (y0 + y1) * 0.5, 0), face[1], 3.6, y1 - y0 - 0.6, 0.0)
				# Aluminium floor lines and a centre mullion across the slot.
				for f in range(f0, f1):
					_box("metal", Vector3(3.6, 0.18, 0.08), face[0] + out * 0.06 + Vector3(0, ground_h + floor_h * (f - 1), 0), Color("#8d9296"), _tw_yaw(face[1]))
				_box("metal", Vector3(0.12, y1 - y0 - 0.6, 0.08), face[0] + out * 0.06 + Vector3(0, (y0 + y1) * 0.5, 0), Color("#8d9296"), _tw_yaw(face[1]))
		_box("paint", Vector3(cw - notch * 2.0 + 0.4, 0.5, cd + 0.4), Vector3(0, y1 + 0.25, cz), granite.lightened(0.1))  # coping
		_box("paint", Vector3(cw + 0.4, 0.5, cd - notch * 2.0 + 0.4), Vector3(0, y1 + 0.25, cz), granite.lightened(0.1))
		_tw_roof(cw - notch * 2.0, cd, cz, y1 + 0.5)
		_tw_roof(cw, cd - notch * 2.0, cz, y1 + 0.49)
		y0 = y1
		f0 = f1
	_tw_crown(crown, cw, cd, cz, y0 + 0.5, granite, mirror)
	_tw_name(Vector3(0, y0 - floor_h + 0.6, cz - cd * 0.5), (cw - minf(cw, cd) * 0.28) * 0.8, floor_h * 0.6)


## A box with its four corners notched in by `n` (a cross in plan).
func _tw_notched(mat: String, w: float, d: float, cz: float, y0: float, y1: float, col: Color, n: float) -> void:
	_box(mat, Vector3(w - n * 2.0, y1 - y0, d), Vector3(0, (y0 + y1) * 0.5, cz), col)
	_box(mat, Vector3(w, y1 - y0, d - n * 2.0), Vector3(0, (y0 + y1) * 0.5, cz), col)


## The twelve outside faces of a notched box, as _tw_faces gives them.
func _tw_notch_faces(w: float, d: float, cz: float, n: float) -> Array:
	var out := []
	for f in _tw_faces(w - n * 2.0, d, cz):
		out.append(f)
	for f in _tw_faces(w, d - n * 2.0, cz):
		if not f[3]:
			out.append(f)
	# The notch walls, facing the street or the back and the sides.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var x: float = sx * (w * 0.5 - n * 0.5)
			out.append([Vector3(x, 0, cz + sz * (d * 0.5 - n) + sz * 0.03), Vector3(-sz, 0, 0), n, true])
			var z: float = cz + sz * (d * 0.5 - n * 0.5)
			out.append([Vector3(sx * (w * 0.5 - n) + sx * 0.03, 0, z), Vector3(0, 0, sx), n, false])
	return out


## A round-arched entry: a granite surround, glass doors and a fanlight.
func _tw_arch(at: Vector3, w: float, h: float, stone: Color, glass_col: Color) -> void:
	var r := w * 0.5 - 0.8
	var spring := h - r - 0.6
	_box("brick", Vector3(w, h, 0.7), at + Vector3(0, h * 0.5, -0.35), stone)
	_glass(at + Vector3(0, spring * 0.5, -0.73), Vector3(-1, 0, 0), r * 2.0, spring, 0.0)
	var segs := 10
	var c := at + Vector3(0, spring, -0.73)
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		_tri("paint", c, c + Vector3(cos(a1) * r, sin(a1) * r, 0), c + Vector3(cos(a0) * r, sin(a0) * r, 0),
			glass_col.darkened(0.2), [], Vector3(0, 0, -1))
	_box("paint", Vector3(r * 2.0 + 0.2, 0.15, 0.1), c + Vector3(0, 0, -0.03), stone.darkened(0.3))  # transom bar


## The top of a postmodern tower over a w by d roof at height y:
##   gable    a pitched copper roof with glass gable ends (a 1980s nod to
##            the gabled skyscraper tops of the 1920s)
##   pyramid  a stepped base under a copper or glass pyramid
##   spires   two slim spires on the street corners (Chase Tower)
##   stepped  three shrinking tiers and a lantern
func _tw_crown(kind: String, w: float, d: float, cz: float, y: float, stone: Color, glass_col: Color) -> void:
	match kind:
		"gable":
			var h := minf(w, 30.0) * 0.35
			var hw := w * 0.5
			var f := Vector3(0, 0, cz - d * 0.5)
			var bk := Vector3(0, 0, cz + d * 0.5)
			for e in [[f, Vector3(0, 0, -1)], [bk, Vector3(0, 0, 1)]]:
				var z: Vector3 = e[0]
				_tri("paint", z + Vector3(-hw, y, 0), z + Vector3(hw, y, 0), z + Vector3(0, y + h, 0), glass_col.lightened(0.1), [], e[1])
			for sx in [-1.0, 1.0]:
				_quad("roof", Vector3(sx * hw, y, f.z - 0.3), Vector3(sx * hw, y, bk.z + 0.3), Vector3(0, y + h, bk.z + 0.3),
					Vector3(0, y + h, f.z - 0.3), TW_COPPER, [], Vector3(sx, 1, 0))
			_tw_mast(Vector3(0, y + h, cz), 8.0)
		"pyramid":
			var cw := w
			var cd := d
			var yy := y
			for k in 2:
				cw -= 3.0
				cd -= 3.0
				_box("brick", Vector3(cw, 3.0, cd), Vector3(0, yy + 1.5, cz), stone)
				yy += 3.0
			var top_col := TW_COPPER if rng.randf() < 0.6 else glass_col.lightened(0.15)
			_tw_pyramid(Vector3(0, yy, cz), cw, cd, minf(cw, cd) * 0.75, top_col)
		"spires":
			_box("brick", Vector3(w - 2.0, 4.0, d - 2.0), Vector3(0, y + 2.0, cz), stone)
			for sx in [-1.0, 1.0]:
				var b := Vector3(sx * (w * 0.5 - 4.0), y + 4.0, cz - d * 0.5 + 4.0)
				_box("brick", Vector3(4.0, 6.0, 4.0), b + Vector3(0, 3.0, 0), stone.lightened(0.05))
				_tw_pyramid(b + Vector3(0, 6.0, 0), 4.0, 4.0, 16.0, stone.lightened(0.1))
				_tw_mast(b + Vector3(0, 22.0, 0), 6.0)
		_:
			var cw := w
			var cd := d
			var yy := y
			for k in 3:
				cw *= 0.72
				cd *= 0.72
				_box("brick", Vector3(cw, 3.2, cd), Vector3(0, yy + 1.6, cz), stone)
				for face in _tw_faces(cw, cd, cz):
					_glass(face[0] + Vector3(0, yy + 1.8, 0), face[1], face[2] * 0.6, 1.6, 0.0)
				yy += 3.2
			_tw_pyramid(Vector3(0, yy, cz), cw, cd, cw * 0.6, TW_COPPER)


## A four-sided pyramid of base w by d rising h from `base`.
func _tw_pyramid(base: Vector3, w: float, d: float, h: float, col: Color) -> void:
	var apex := base + Vector3(0, h, 0)
	var c := [base + Vector3(-w * 0.5, 0, -d * 0.5), base + Vector3(w * 0.5, 0, -d * 0.5),
		base + Vector3(w * 0.5, 0, d * 0.5), base + Vector3(-w * 0.5, 0, d * 0.5)]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		_tri("roof", a, b, apex, col, [], (a + b) * 0.5 - base + Vector3(0, h * 0.3, 0))


## A steel antenna mast with an aircraft warning light.
func _tw_mast(at: Vector3, h: float) -> void:
	_box("metal", Vector3(0.25, h, 0.25), at + Vector3(0, h * 0.5, 0), TW_STEEL)
	_box("paint", Vector3(0.4, 0.4, 0.4), at + Vector3(0, h + 0.2, 0), Color("#c0281e"))


# ---------------------------------------------------------------- podium towers

## A 2000s-2020s tower on a podium that fills the whole assembled site:
## shops and the lobby in glass at the sidewalk, parking decks above them
## behind metal screens, a roof deck (a pool and lawn for flats), and the
## tower set back on the podium in floor-to-ceiling glass with its slab
## edges showing: offices with vertical fins and a lit blade over the
## mechanical screen, flats with glass balconies at the corners.
func _tw_podium(to_curb: float, width: float, storeys: int) -> void:
	var pw := width - 1.0
	var pd := minf(depth - 2.0, rng.randf_range(34.0, 46.0))
	var tw := minf(pw - 4.0, rng.randf_range(26.0, 38.0) if _homes else rng.randf_range(24.0, 32.0))
	var td := minf(pd - 8.0, rng.randf_range(18.0, 22.0) if _homes else rng.randf_range(20.0, 26.0))
	if pw < 26.0 or tw < 16.0 or td < 14.0:
		_tw_glass(to_curb, width, storeys)
		return
	var zf := 0.4
	var levels := 4 if storeys >= 16 else 3
	var ground_h := 5.5
	var park_h := 3.2
	var ph := ground_h + park_h * (levels - 1)
	var floor_h := 3.1 if _homes else 4.0
	var top := ph + floor_h * maxi(4, storeys - levels)
	var slack := (pw - tw) * 0.5 - 2.0
	var tx := 0.0 if slack < 3.0 else rng.randf_range(-slack, slack)
	var tz := zf + rng.randf_range(4.0, maxf(4.0, pd - td - 3.0)) + td * 0.5
	var pcz := zf + pd * 0.5
	var panel := Color(_pick(["#bdb7ac", "#8e9294", "#5a5e62", "#c9c2b4"]))  # precast or metal panel
	var tint := Color(_pick(["#5f7f8a", "#4f6a74", "#6a8478", "#7b8a90"]))
	var slab := Color("#d6d3cc") if _homes else Color("#3a3e42")
	var mech := 7.0
	var blade := not _homes and rng.randf() < 0.6
	if _far:
		_tw_far_box(Vector3(pw, ph, pd), Vector3(0, ph * 0.5, pcz), panel, 0.3)
		_tw_far_box(Vector3(tw, top - ph, td), Vector3(tx, (ph + top) * 0.5, tz), tint.darkened(0.3), 1.0)
		_tw_far_box(Vector3(tw * 0.62, mech, td * 0.62), Vector3(tx, top + mech * 0.5, tz), Color("#3a3f44"), 0.0)
		return
	_downtown_walk(to_curb, width, zf)
	_tw_dock(pw, zf + pd)
	# The podium: storefronts at the sidewalk, parking decks above.
	_box("paint", Vector3(pw, ph, pd), Vector3(0, ph * 0.5, pcz), panel)
	var shops := maxi(2, roundi(pw / 9.0))
	for i in shops:
		var x := -pw * 0.5 + (i + 0.5) * pw / shops
		_glass(Vector3(x, 2.5, zf - 0.03), Vector3(-1, 0, 0), pw / shops - 1.2, 4.0, rng.randf_range(0.0, 0.15))
	for s in [-1.0, 1.0]:
		_glass(Vector3(s * (pw * 0.5 + 0.03), 2.5, zf + 5.0), Vector3(0, 0, -s), 8.0, 4.0, 0.0)  # corner shops wrap round
	_box("paint", Vector3(pw - 1.0, 0.25, 1.8), Vector3(0, ground_h - 0.6, zf - 0.9), Color("#2b2d2f"))  # canopy
	_sign(Vector3(tx, ground_h - 0.2, zf - 1.85), 5.0, 0.6)
	var ramp_x := pw * 0.5 - 4.0 if tx < 0.0 else -pw * 0.5 + 4.0
	_box("paint", Vector3(6.0, 3.8, 0.1), Vector3(ramp_x, 1.9, zf - 0.05), Color("#1c1d1e"))  # the garage door
	for lv in range(1, levels):
		var y := ground_h + park_h * (lv - 1)
		for face in [[Vector3(0, 0, zf - 0.03), Vector3(-1, 0, 0), pw], [Vector3(-pw * 0.5 - 0.03, 0, pcz), Vector3(0, 0, 1), pd],
				[Vector3(pw * 0.5 + 0.03, 0, pcz), Vector3(0, 0, -1), pd]]:
			var out: Vector3 = face[1].cross(Vector3.UP)
			var c: Vector3 = face[0] + Vector3(0, y + park_h * 0.55, 0)
			var r: Vector3 = face[1] * (face[2] - 1.2) * 0.5
			var u := Vector3(0, park_h * 0.3, 0)
			_quad("paint", c - r - u + out * 0.01, c + r - u + out * 0.01, c + r + u + out * 0.01, c - r + u + out * 0.01, Color("#232527"), [], out)
			if fine:
				# Vertical screen fins in front of the open deck.
				var n := int((face[2] - 1.2) / 0.9)
				for i in n:
					var p: Vector3 = c - r + face[1] * (i + 0.5) * (face[2] - 1.2) / n + out * 0.15
					_box("metal", Vector3(0.12, park_h * 0.62, 0.3), p, panel.lightened(0.12), _tw_yaw(face[1]))
	_box("paint", Vector3(pw + 0.2, 0.9, pd + 0.2), Vector3(0, ph + 0.45, pcz), panel.darkened(0.1))  # parapet
	_tw_roof(pw, pd, pcz, ph + 0.84)  # under the deck: the far version's podium top
	# The roof deck around the tower.
	_quad("paint", Vector3(-pw * 0.5 + 0.4, ph + 0.92, zf + 0.4), Vector3(pw * 0.5 - 0.4, ph + 0.92, zf + 0.4),
		Vector3(pw * 0.5 - 0.4, ph + 0.92, zf + pd - 0.4), Vector3(-pw * 0.5 + 0.4, ph + 0.92, zf + pd - 0.4), Color("#a39e94"), [], Vector3.UP)
	var deck_z := zf + 3.0
	if tz - td * 0.5 - deck_z > 3.0:
		_quad("paint", Vector3(-pw * 0.5 + 2.0, ph + 0.95, deck_z), Vector3(pw * 0.5 - 2.0, ph + 0.95, deck_z),
			Vector3(pw * 0.5 - 2.0, ph + 0.95, tz - td * 0.5 - 1.0), Vector3(-pw * 0.5 + 2.0, ph + 0.95, tz - td * 0.5 - 1.0),
			Color("#6f8a52"), [], Vector3.UP)  # green roof
	if _homes:
		var px := -tx * 0.5
		_quad("paint", Vector3(px - 6.0, ph + 0.97, deck_z + 0.5), Vector3(px + 6.0, ph + 0.97, deck_z + 0.5),
			Vector3(px + 6.0, ph + 0.97, deck_z + 3.5), Vector3(px - 6.0, ph + 0.97, deck_z + 3.5), Color("#3f8fb0"), [], Vector3.UP)  # the pool
	var sx := -pw * 0.5 + 3.0
	while sx < pw * 0.5 - 3.0:
		if absf(sx - tx) > tw * 0.5 + 1.0:
			_shrub(Vector3(sx, ph + 0.95, zf + 1.5), rng.randf_range(0.5, 0.8))
		sx += rng.randf_range(3.0, 5.0)
	# The tower: a dark core wrapped in glass floor by floor, slab edges between.
	_box("paint", Vector3(tw, top - ph, td), Vector3(tx, (ph + top) * 0.5, tz), Color("#1c1e20"))
	var floors := int((top - ph) / floor_h)
	for f in floors:
		var y0 := ph + f * floor_h
		_box("paint", Vector3(tw + 0.1, 0.32, td + 0.1), Vector3(tx, y0 + 0.16, tz), slab)
		for face in _tw_faces(tw, td, tz, tx):
			_glass(face[0] + Vector3(0, y0 + 0.32 + (floor_h - 0.32) * 0.5, 0), face[1], face[2] - 0.2, floor_h - 0.4, rng.randf_range(0.05, 0.5))
	if _homes:
		# Solid panel piers between the window walls (flats need walls for
		# kitchens and closets; 2010s towers clad them in metal or
		# fibre-cement panel, often a second colour).
		var pier := Color(_pick(["#e8e6e0", "#3b3d40", "#b9b2a4", "#8f9599"]))
		for face in _tw_faces(tw, td, tz, tx):
			var n := maxi(3, roundi(face[2] / 3.4))
			var outv: Vector3 = face[1].cross(Vector3.UP)
			for i in range(1, n):
				if i % 3 != 1:
					continue
				var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + i * face[2] / n) + outv * 0.1
				c.y = (ph + top) * 0.5
				_box("paint", Vector3(2.4, top - ph, 0.3), c, pier, _tw_yaw(face[1]))
		# Glass balconies stacked at the four corners.
		for f in range(1, floors):
			var y0 := ph + f * floor_h
			for cxs in [-1.0, 1.0]:
				for czs in [-1.0, 1.0]:
					var c := Vector3(tx + cxs * (tw * 0.5 - 2.5), y0, tz + czs * (td * 0.5 + 0.8))
					_box("paint", Vector3(5.0, 0.2, 1.6), c + Vector3(0, 0.1, 0), slab)
					_glass(c + Vector3(0, 0.75, czs * 0.8), Vector3(czs, 0, 0), 5.0, 1.05, 0.0)
	else:
		# Vertical aluminium fins on the street and back faces, 1.5 m apart.
		for face in _tw_faces(tw, td, tz, tx):
			if not face[3]:
				continue
			var n := maxi(4, roundi(face[2] / 1.5))
			var out: Vector3 = face[1].cross(Vector3.UP)
			for i in n + 1:
				var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + i * face[2] / n) + out * 0.25
				c.y = (ph + top) * 0.5
				_box("metal", Vector3(0.1, top - ph, 0.45), c, Color("#a9adb0"), _tw_yaw(face[1]))
	# The mechanical screen on top, and on some offices a lit blade.
	_tw_roof(tw, td, tz, top + 0.05, tx)  # the tower's own roof: far away it stops here, under the screen
	_tw_rooftop(tw, td, tz, top + 0.05, tx, true, true)
	if _homes:
		# An apartment tower: a clad penthouse and the residents' roof deck.
		_tw_roof_deck(tw, td, tz, top + 0.05, 4.5, slab, Color("#a9bcc4"), tx)
		return
	# (membrane-faced, so far away it keeps its dark grey instead of the walls' colour)
	var mw := tw * 0.62
	var md := td * 0.62
	_box("membrane", Vector3(mw, mech, md), Vector3(tx, top + mech * 0.5, tz), Color("#3a3f44"))
	for face in _tw_faces(mw, md, tz, tx):
		var n := maxi(4, roundi(face[2] / 0.8))
		var out: Vector3 = face[1].cross(Vector3.UP)
		for i in n:
			var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + (i + 0.5) * face[2] / n) + out * 0.05
			c.y = top + mech * 0.5
			if fine:
				_box("metal", Vector3(0.08, mech - 0.4, 0.2), c, Color("#5b6166"), _tw_yaw(face[1]))
	_tw_roof(mw, md, tz, top + mech, tx)
	_tw_name(Vector3(tx, top + mech * 0.2, tz - md * 0.5), mw * 0.9, mech * 0.55)
	if blade:
		var bx := tx + (tw * 0.5 - 0.6) * (1.0 if rng.randf() < 0.5 else -1.0)
		_box("paint", Vector3(0.8, mech + 12.0, td * 0.8), Vector3(bx, top + (mech + 12.0) * 0.5 - 2.0, tz), Color("#d9dde0"))


# ---------------------------------------------------------------- 1920s apartment towers

const TW_FLATS_BRICK := ["#9b5a42", "#8a4a38", "#b07a55", "#c9a77c", "#7a4234"]  # red, dark red, tan, buff, brown


## A 1920s apartment tower (Chicago's Lake Shore Drive and Sheridan Road
## co-ops, Indianapolis's Meridian Street apartment buildings): a
## limestone base of two storeys behind a strip of lawn and a canvas
## canopy out to the curb; a brick shaft of paired double-hung windows
## with stone sills, limestone quoins at the corners and a belt course
## every few floors; a cornice, and on the taller ones a set-back
## penthouse storey of arched windows under a hipped tile roof that hides
## the water tank.
func _tw_flats(to_curb: float, width: float, storeys: int) -> void:
	var w := minf(width - 4.0, rng.randf_range(24.0, 36.0))
	var d := minf(depth - 8.0, rng.randf_range(20.0, 26.0))
	if w < 14.0 or d < 12.0:
		_tw_chicago(to_curb, width, storeys)
		return
	var zf := rng.randf_range(3.0, 6.0)
	var cz := zf + d * 0.5
	var ground_h := 4.6
	var floor_h := 3.2
	var base_f := 2
	var y_base := ground_h + floor_h * (base_f - 1)
	var top := ground_h + floor_h * (storeys - 1)
	var brick := Color(_pick(TW_FLATS_BRICK))
	var stone := Color(_pick(TW_LIMESTONE))
	var tile := Color(_pick(["#8a3b2a", "#5f6b4e", "#4a4a4c"]))  # red tile, green tile, slate
	var pent := storeys >= 14
	if _far:
		_tw_far_box(Vector3(w, y_base, d), Vector3(0, y_base * 0.5, cz), stone, 0.4)
		_tw_far_box(Vector3(w, top - y_base, d), Vector3(0, (y_base + top) * 0.5, cz), brick, 0.5)
		if pent:
			_tw_far_box(Vector3(w - 8.0, 4.0, d - 8.0), Vector3(0, top + 2.0, cz), stone, 0.3)
			_tw_pyramid(Vector3(0, top + 4.0, cz), w - 7.0, d - 7.0, 4.0, tile)
		return
	# A strip of lawn and shrubs in front, a walk under the canopy.
	_flat_rect("drive", -width * 0.5, width * 0.5, -to_curb + RoadStyle.CURB_WIDTH, -to_curb + RoadStyle.CURB_WIDTH + 1.8, 0.06)
	_flat_rect("drive", -1.6, 1.6, -to_curb + RoadStyle.CURB_WIDTH, zf, 0.065)
	var sx := -w * 0.5 + 0.8
	while sx < w * 0.5 - 0.8:
		if absf(sx) > 2.6:
			_shrub(Vector3(sx, 0, zf - 0.8), rng.randf_range(0.45, 0.7))
		sx += rng.randf_range(1.6, 2.4)
	# The base: rusticated limestone, tall windows, the entry.
	_box("brick", Vector3(w, y_base, d), Vector3(0, y_base * 0.5, cz), stone)
	_box("brick", Vector3(w, top - y_base, d), Vector3(0, (y_base + top) * 0.5, cz), brick)
	_box("paint", Vector3(w + 0.3, 0.45, d + 0.3), Vector3(0, y_base + 0.1, cz), stone.lightened(0.08))  # belt course
	var bays := maxi(4, roundi(w / 3.6))
	var bw := w / bays
	var side_bays := maxi(3, roundi(d / 3.6))
	var sbw := d / side_bays
	for i in bays:
		var x := -w * 0.5 + (i + 0.5) * bw
		if absf(x) < 2.4:
			continue
		_glass(Vector3(x, 2.2, zf - 0.03), Vector3(-1, 0, 0), bw - 1.4, 2.4, rng.randf_range(0.2, 0.6))
		_glass(Vector3(x, ground_h + 1.6, zf - 0.03), Vector3(-1, 0, 0), bw - 1.6, 1.8, rng.randf_range(0.2, 0.6))
	_box("brick", Vector3(3.6, 4.2, 0.4), Vector3(0, 2.1, zf - 0.2), stone.lightened(0.1))  # entry surround
	_box("paint", Vector3(2.0, 2.8, 0.08), Vector3(0, 1.4, zf - 0.42), Color("#3b2f22"))  # bronze doors
	# The canopy: canvas on brass poles out to the curb (Chicago's apartment
	# canopies run across the parkway so residents step out of a cab dry).
	var cz0 := -to_curb + RoadStyle.CURB_WIDTH + 0.4
	var canvas := Color(_pick(["#1f3a2a", "#5a1f22", "#1f2a44", "#2a2a2a"]))
	var clen := zf - cz0
	if clen > 2.0:
		_box("paint", Vector3(2.4, 0.35, clen), Vector3(0, 3.0, cz0 + clen * 0.5), canvas)
		for z in [cz0 + 0.2, cz0 + clen * 0.5]:
			for s in [-1.0, 1.0]:
				_box("metal", Vector3(0.07, 2.85, 0.07), Vector3(s * 1.1, 1.42, z), Color("#b59a5a"))
	# The shaft: paired double-hung windows with stone sills, quoins, and a
	# belt course every fourth floor.
	for f in range(base_f, storeys):
		var y := ground_h + floor_h * (f - 1) + 1.6
		for face in _tw_faces(w, d, cz):
			var n: int = bays if face[3] else side_bays
			var len_b: float = bw if face[3] else sbw
			var out: Vector3 = face[1].cross(Vector3.UP)
			for i in n:
				var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + (i + 0.5) * len_b)
				c.y = y
				for k in [-1.0, 1.0]:
					_glass(c + face[1] * k * 0.55, face[1], 0.85, 1.7, rng.randf_range(0.1, 0.7))
				if fine:
					_box("paint", Vector3(2.3, 0.1, 0.18), c + out * 0.06 + Vector3(0, -0.92, 0), stone, _tw_yaw(face[1]))  # sill
		if (f - base_f) % 4 == 3:
			_box("paint", Vector3(w + 0.16, 0.3, d + 0.16), Vector3(0, ground_h + floor_h * (f - 1) + 0.15, cz), stone)
	for qx in [-1.0, 1.0]:
		for qz in [-1.0, 1.0]:
			var q := Vector3(qx * (w * 0.5 - 0.35), 0, cz + qz * (d * 0.5 - 0.35))
			var y := y_base
			while y < top - 0.6:
				_box("brick", Vector3(0.9 if int(y / 0.6) % 2 == 0 else 0.75, 0.55, 0.9 if int(y / 0.6) % 2 == 1 else 0.75), q + Vector3(0, y + 0.3, 0), stone)
				y += 0.6
	# The cornice, then the penthouse and its tile roof, or a parapet.
	_box("paint", Vector3(w + 1.4, 0.7, d + 1.4), Vector3(0, top + 0.35, cz), stone.lightened(0.06))
	if pent:
		var pw := w - 8.0
		var pd := d - 8.0
		_box("brick", Vector3(pw, 4.0, pd), Vector3(0, top + 2.7, cz), stone)
		for face in _tw_faces(pw, pd, cz):
			var n := maxi(3, roundi(face[2] / 3.0))
			for i in n:
				var c: Vector3 = face[0] + face[1] * (-face[2] * 0.5 + (i + 0.5) * face[2] / n)
				c.y = top + 2.5
				_glass(c, face[1], 1.4, 2.4, 0.2)
		_tw_pyramid(Vector3(0, top + 4.7, cz), pw + 1.0, pd + 1.0, minf(pw, pd) * 0.35, tile)
	else:
		_box("brick", Vector3(w, 1.0, d), Vector3(0, top + 1.2, cz), brick)
		_tw_roof(w, d, cz, top + 1.7)
		_tw_rooftop(w, d, cz, top + 1.7, 0.0, false, true)
		if storeys >= 6:
			_tw_tank(Vector3(rng.randf_range(-w * 0.2, w * 0.2), top + 1.7, cz + d * 0.15))
	for s in [-1.0, 1.0]:
		var pick := TreeField.pick(rng)
		trees.append([Vector3(s * (width * 0.5 - 2.0), 0, -to_curb + RoadStyle.CURB_WIDTH + 0.9), pick[0], pick[1], rng.randf_range(0.6, 0.8)])


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
	for face in _tw_faces(size.x, size.z, center.z, center.x):
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
func _tw_faces(w: float, d: float, cz: float, cx := 0.0) -> Array:
	return [
		[Vector3(cx, 0, cz - d * 0.5 - 0.03), Vector3(-1, 0, 0), w, true],
		[Vector3(cx, 0, cz + d * 0.5 + 0.03), Vector3(1, 0, 0), w, true],
		[Vector3(cx - w * 0.5 - 0.03, 0, cz), Vector3(0, 0, 1), d, false],
		[Vector3(cx + w * 0.5 + 0.03, 0, cz), Vector3(0, 0, -1), d, false],
	]


## Turns a box built facing the street to lie along `along`.
func _tw_yaw(along: Vector3) -> Basis:
	return Basis(Vector3.UP, atan2(-along.z, -along.x))


## A gravel roof inside the parapet, in the membrane material, so the far
## version knows where each mass ends (a tier's walls stop at its roof
## instead of running up to the tower's top).
## What stands on a tower's roof, seen from the air over any downtown
## (aerials of Indianapolis, Columbus and Chicago): on a big plate a pair
## of cooling-tower cells with their fan stacks, exhaust fans and a roof
## hatch; cell carriers' panel antennas in three sectors at the corners;
## on a glass tower the window-washing machine (a BMU) parked on its track
## round the edge. `small` keeps to the edges, around a penthouse or tank
## in the middle. Its own random numbers, so the builder's don't move.
func _tw_rooftop(w: float, d: float, cz: float, y: float, x := 0.0, glass := false, small := false) -> void:
	if _far or w < 10.0 or d < 10.0:
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "rooftop", snappedf(y, 0.1)])
	var grey := Color("#9ea3a6")
	var dark := Color("#2b2d2f")
	var side := 1.0 if r.randf() < 0.5 else -1.0
	if not small and w * d > 300.0:
		# Two cooling-tower cells side by side, toward one end.
		for k in 2:
			var c := Vector3(x + side * w * 0.3, y, cz + (k - 0.5) * 4.8)
			_box("metal", Vector3(4.4, 3.4, 4.4), c + Vector3(0, 1.7, 0), grey)
			_box("metal", Vector3(3.0, 0.9, 3.0), c + Vector3(0, 3.85, 0), grey.darkened(0.15))  # fan stack
			_box("paint", Vector3(2.6, 0.05, 2.6), c + Vector3(0, 4.32, 0), dark)  # the fan, from above
		_box("metal", Vector3(0.5, 0.5, 9.0), Vector3(x + side * (w * 0.3 - 2.8), y + 0.6, cz), Color("#6d7174"))  # piping
	# Exhaust fans and a roof hatch.
	for i in r.randi_range(2, 4):
		var p := Vector3(x - side * r.randf_range(w * 0.18, w * 0.4), y, cz + r.randf_range(-d * 0.38, d * 0.38))
		if small:
			p.x = x + (1.0 if i % 2 == 0 else -1.0) * (w * 0.5 - 2.0)
		_box("metal", Vector3(1.1, 0.7, 1.1), p + Vector3(0, 0.35, 0), grey)
		_box("metal", Vector3(1.4, 0.12, 1.4), p + Vector3(0, 0.8, 0), grey.lightened(0.1))
	if fine:
		_box("metal", Vector3(1.0, 0.45, 1.2), Vector3(x - side * w * 0.2, y + 0.22, cz + d * 0.38 - 1.2), grey.darkened(0.1))
	# Panel antennas: three sectors, each on a short pipe mast at a corner.
	if r.randf() < 0.7:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1 if side > 0 else -1, 1)]:
			var p := Vector3(x + corner.x * (w * 0.5 - 1.2), y, cz + corner.y * (d * 0.5 - 1.2))
			_box("metal", Vector3(0.12, 3.2, 0.12), p + Vector3(0, 1.6, 0), Color("#8d8f8e"))
			for k in 3:
				var a := TAU * k / 3.0 + atan2(corner.y, corner.x)
				var o := Vector3(cos(a), 0, sin(a)) * 0.35
				_box("paint", Vector3(0.3, 1.4, 0.12), p + o + Vector3(0, 2.6, 0), Color("#e4e3df"), Basis(Vector3.UP, -a + PI * 0.5))
	# A glass tower's window-washing machine on a track round the roof.
	if glass:
		var inset := 1.4
		for sz in [-1.0, 1.0]:
			_box("metal", Vector3(w - inset * 2.0, 0.15, 0.25), Vector3(x, y + 0.08, cz + sz * (d * 0.5 - inset)), Color("#6d7174"))
		for sx in [-1.0, 1.0]:
			_box("metal", Vector3(0.25, 0.15, d - inset * 2.0), Vector3(x + sx * (w * 0.5 - inset), y + 0.08, cz), Color("#6d7174"))
		var bz := cz + side * (d * 0.5 - inset)
		var bx := x + r.randf_range(-w * 0.25, w * 0.25)
		_box("metal", Vector3(2.4, 2.2, 2.0), Vector3(bx, y + 1.1, bz - side * 0.6), Color("#d8d8d4"))
		_box("metal", Vector3(0.4, 0.4, 5.0), Vector3(bx, y + 2.4, bz + side * 1.0), Color("#d8d8d4"))  # jib, over the edge


func _tw_roof(w: float, d: float, cz: float, y: float, x := 0.0) -> void:
	var g := GRAVEL
	g.a = 0.5
	_quad("membrane", Vector3(x - w * 0.5, y + 0.03, cz - d * 0.5), Vector3(x + w * 0.5, y + 0.03, cz - d * 0.5),
		Vector3(x + w * 0.5, y + 0.03, cz + d * 0.5), Vector3(x - w * 0.5, y + 0.03, cz + d * 0.5), g, [], Vector3.UP)


## A timber rooftop water tank on a steel stand (Rosenwach / Isseks style):
## staves bound with hoops under a conical cap.
## The owner's name near the top of the street face, in channel letters
## (Indianapolis's Salesforce and OneAmerica towers, Des Moines's
## Principal, Fort Wayne's Indiana Michigan Power Center): a company that
## grew into a tower puts its name where the whole town can read it. `c`
## is the letters' bottom middle on the face; read from well past the
## usual sign range. Nothing when no family owns the lot.
func _tw_name(c: Vector3, w: float, h: float) -> void:
	if sign_spec.is_empty() or _far or _homes:
		return
	var col: Color = sign_spec.panel
	if col.get_luminance() < 0.35:
		col = Color("#f3efe4")  # lit white letters on a dark brand
	labels.append({"pos": c + Vector3(0, h * 0.5, -0.15), "normal": Vector3.FORWARD, "text": sign_spec.text,
		"height": h, "width": w, "color": col, "style": sign_spec.style, "range": TW_NAME_RANGE})


## A rooftop sign on a steel frame along the front of an old office
## block's roof (the lettered frames over Chicago's Loop and Indianapolis's
## old hotels and office blocks): angle posts and rails, the name on top
## facing the street. `c` is the middle of its foot on the roof.
func _tw_roof_sign(c: Vector3, w: float) -> void:
	if sign_spec.is_empty() or _far or _homes:
		return
	var steel := Color("#3b3a38")
	var h := 3.4
	var n := maxi(2, roundi(w / 2.5))
	for i in n + 1:
		var x := c.x - w * 0.5 + i * w / n
		_box("metal", Vector3(0.12, h, 0.12), Vector3(x, c.y + h * 0.5, c.z), steel)
		_box("metal", Vector3(0.1, h * 0.8, 0.1), Vector3(x, c.y + h * 0.4, c.z + 1.2), steel, Basis(Vector3.RIGHT, -0.4))  # brace
	for y in [0.4, h * 0.5, h - 0.1]:
		_box("metal", Vector3(w, 0.1, 0.1), Vector3(c.x, c.y + y, c.z), steel)
	# Against the sky the brand's own colour reads; a near-black one goes red.
	var col: Color = sign_spec.panel
	if col.get_luminance() < 0.08:
		col = Color("#c8302a")
	labels.append({"pos": c + Vector3(0, h * 0.5 + 0.3, -0.12), "normal": Vector3.FORWARD, "text": sign_spec.text,
		"height": h * 0.8, "width": w, "color": col, "style": sign_spec.style, "range": TW_NAME_RANGE})


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
