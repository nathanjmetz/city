class_name VehicleModels
extends RefCounted
## Builds every vehicle from code: lofted bodies, glass, wheels, lights and
## the bits that make each kind read at a glance (bed, light bar, ladder,
## hopper, stop arm). Benchmarked against real photos and spec sheets.
##
## Each mesh has its origin at the front bumper on the ground, with the body
## running back along +Z (the view turns it so -Z faces where it drives).
## Vertex colour carries the surface: rgb is the colour (sRGB) and alpha a
## material code read by the shader in VehicleMaterial. PAINT surfaces take
## the vehicle's own body colour.
##
## Two levels of detail: 0 for close up, 1 for far away (a few dozen
## triangles, no small parts).

const PAINT := Color(1, 1, 1, 0.0)
const GLASS := Color(0.10, 0.13, 0.16, 0.1)
const CHROME := Color(0.78, 0.78, 0.78, 0.2)
const TRIM := Color(0.07, 0.07, 0.07, 0.3)
const TIRE := Color(0.035, 0.035, 0.035, 0.3)
const HEAD := Color(0.96, 0.95, 0.9, 0.5)
const TAIL := Color(0.55, 0.03, 0.03, 0.6)
const BEACON_RED := Color(1.0, 0.06, 0.04, 0.7)
const BEACON_BLUE := Color(0.08, 0.25, 1.0, 0.7)
const BEACON_AMBER := Color(1.0, 0.55, 0.05, 0.8)
## Ready-mix drums are white with coloured fins.
const MIXER := Color(0.93, 0.93, 0.91, 0.4)
const USPS_BLUE := Color(0.08, 0.17, 0.42, 0.4)
const USPS_RED := Color(0.75, 0.08, 0.12, 0.4)
const WHITE := Color(0.92, 0.92, 0.91, 0.4)
const STEEL := Color(0.62, 0.63, 0.64, 0.2)
## DOT-C2 conspicuity sheeting: alternating red and white reflective tape.
const TAPE_RED := Color(0.72, 0.05, 0.04, 0.4)
const DARK := Color(0.16, 0.16, 0.17, 0.4)
const RIM := Color(0.72, 0.72, 0.73, 0.2)
## Loads: oak bark, freshly sawn log ends, iron ore, dunnage, ratchet straps.
const BARK := Color(0.46, 0.37, 0.27, 0.4)
## Unpainted aluminium trailer bodies read light grey from above.
const ALUM := Color(0.74, 0.75, 0.77, 0.4)
const WOOD_END := Color(0.94, 0.84, 0.64, 0.4)
const ORE := Color(0.45, 0.28, 0.20, 0.4)
const COIL := Color(0.62, 0.63, 0.65, 0.4)
const WOOD_DARK := Color(0.42, 0.33, 0.22, 0.4)
const STRAP := Color(0.85, 0.62, 0.08, 0.4)
## Ambulance red (the band) and Star of Life blue.
const EMS_RED := Color(0.80, 0.07, 0.07, 0.4)
const EMS_BLUE := Color(0.04, 0.24, 0.72, 0.4)

## Articulated vehicles: the tractor unit is drawn as `cab`, the trailer as
## `trailer`, hitched at `hitch` metres behind the front bumper. The trailer's
## kingpin sits `pin` m behind its own front, and its rear axles `axle` m.
const ARTIC := {
	"semi": {"cab": "tractor_sleeper", "trailer": "trailer_box", "hitch": 6.6, "pin": 0.9, "axle": 14.4},
	"flatbed": {"cab": "tractor_sleeper", "trailer": "trailer_flat", "hitch": 6.6, "pin": 0.9, "axle": 12.9},
	"lumber_truck": {"cab": "tractor_day", "trailer": "trailer_lumber", "hitch": 5.0, "pin": 0.9, "axle": 12.9},
	"grain_truck": {"cab": "tractor_day", "trailer": "trailer_hopper", "hitch": 5.0, "pin": 0.9, "axle": 14.4},
	"log_truck": {"cab": "tractor_day", "trailer": "trailer_logs", "hitch": 5.0, "pin": 0.9, "axle": 13.4},
	"ore_truck": {"cab": "tractor_day", "trailer": "trailer_end_dump", "hitch": 5.0, "pin": 0.9, "axle": 12.6},
	"mail_semi": {"cab": "tractor_day", "trailer": "trailer_usps", "hitch": 5.0, "pin": 0.9, "axle": 14.4},
	"livestock_truck": {"cab": "tractor_sleeper", "trailer": "trailer_livestock", "hitch": 6.6, "pin": 0.9, "axle": 14.4},
	"tractor_wagon": {"cab": "tractor", "trailer": "trailer_gravity_wagon", "hitch": 5.6, "pin": 0.0, "axle": 5.3},
	"tanker": {"cab": "tractor_day", "trailer": "trailer_tank", "hitch": 5.0, "pin": 0.9, "axle": 13.4},
}
## What some kinds wear while snow is on the ground: plows go on contractors'
## pickups and on dump trucks (most Midwest towns hire them for plowing).
const WINTER := {"work_pickup": "work_pickup_plow", "dump_truck": "dump_truck_plow"}
## Open trailers whose load shows: the bare one they pull when empty.
const EMPTY := {"trailer_flat": "trailer_flat_empty", "trailer_lumber": "trailer_flat_empty"}
## Body styles within one kind, all close to its length (see VehicleTypes).
const VARIANTS := {
	"sedan": ["sedan_camry", "sedan_compact", "sedan_fullsize"],
	"pickup": ["pickup", "pickup_ext", "pickup_mid", "pickup_old"],
	"suv": ["suv", "suv_mid", "suv_jeep"],
	"minivan": ["minivan", "minivan_pacifica"],
	"garbage_truck": ["garbage_truck", "garbage_side"],
	"police": ["police", "police", "police_charger", "police_tahoe"],
	"fire_engine": ["fire_engine", "fire_engine", "fire_tender"],
	"crossover": ["crossover", "wagon", "ev_crossover", "crossover_compact"],
	"hatchback": ["hatchback", "hatch_box"],
	"van": ["van", "van_low"],
}
## Where the (rear) axle that steers the body sits, metres behind the front.
const AXLE := {
	"sedan": 3.9, "hatchback": 3.4, "crossover": 3.6, "suv": 4.2, "pickup": 4.7, "work_pickup": 4.8,
	"minivan": 4.0, "sports": 3.8, "motorcycle": 1.8, "van": 4.4, "delivery_van": 5.3,
	"box_truck": 7.9, "dump_truck": 6.7, "tow_truck": 5.2, "police_charger": 3.95, "police_tahoe": 4.15, "fire_tender": 7.2, "garbage_side": 7.3, "pickup_old": 4.4, "suv_jeep": 3.9, "minivan_pacifica": 4.0, "crossover_compact": 3.5, "work_pickup_plow": 4.8, "dump_truck_plow": 6.7, "buggy": 4.9, "golf_cart": 2.2, "rv": 5.9, "motorhome": 7.1, "pickup_camper": 4.8, "bucket_truck": 5.6, "school_bus": 8.9, "city_bus": 9.2, "coach": 10.9,
	"garbage_truck": 7.3, "fire_engine": 7.4, "police": 3.9, "taxi": 3.9, "taxi_old": 4.0, "ambulance": 5.1, "tractor": 4.2,
	"combine": 7.0, "tractor_sleeper": 6.4, "mail_truck": 4.3, "concrete_mixer": 7.0, "sedan_compact": 3.6, "sedan_fullsize": 4.0,
	"pickup_ext": 4.6, "pickup_mid": 4.4, "suv_mid": 3.9, "wagon": 3.7, "ev_crossover": 3.8, "hatch_box": 3.4, "van_low": 4.4,
	"rural_mail": 3.9, "tractor_day": 4.8, "sedan_camry": 3.8,
}

var _st := SurfaceTool.new()
var _lo := false
## Close-up detail for the desktop Ultra tier: rounder wheels with spokes,
## door seams and handles, wipers, plates.
var _hi := false

## Levels of detail build() takes: normal close range, far, and Ultra close-up.
const LOD_NEAR := 0
const LOD_FAR := 1
const LOD_ULTRA := 2


## The mesh for one kind (or one part, like "trailer_box") at a level of detail.
static func build(kind: String, lod := 0) -> ArrayMesh:
	var b := VehicleModels.new()
	b._lo = lod == LOD_FAR
	b._hi = lod == LOD_ULTRA
	b._st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if b.has_method("_" + kind):
		b.call("_" + kind)
	else:
		b._sedan()
	return b._st.commit()


## Every mesh the view needs: each kind that is drawn whole, plus the cabs and
## trailers of articulated ones.
static func mesh_keys() -> Array:
	var out := []
	for k in VehicleTypes.kinds():
		if ARTIC.has(k):
			for p in [ARTIC[k].cab, ARTIC[k].trailer]:
				if not out.has(p):
					out.append(p)
		else:
			out.append_array(VARIANTS.get(k, [k]))
		if WINTER.has(k):
			out.append(WINTER[k])
	for e in EMPTY.values():
		if not out.has(e):
			out.append(e)
	return out


## The trailer as it looks with this trip's cargo: open ones run bare when
## nothing is aboard (heading back after a drop-off).
static func trailer_for(trailer: String, cargo) -> String:
	return EMPTY[trailer] if EMPTY.has(trailer) and not VehicleTypes.is_loaded(cargo) else trailer


## The model one vehicle of a kind uses, fixed by its id, so a street of
## pickups is a mix of crew cabs, extended cabs and midsize ones.
static func variant(kind: String, id: int) -> String:
	var list: Array = VARIANTS.get(kind, [])
	if list.is_empty():
		return kind
	var h := (id * 2246822519 + 3266489917) & 0xffffffff
	h = ((h >> 15) ^ h) * 668265263 & 0xffffffff
	return list[(h >> 8) % list.size()]


# --- Cars -------------------------------------------------------------------

## A passenger car from a few real measurements (all metres from the front
## bumper or the ground): length, width, roof height, ground clearance, hood
## height at the nose, beltline (bottom of the side windows), windshield
## base, roof front, roof back, rear glass base, deck height at the tail,
## wheel radius and axles.
func _car(p: Dictionary) -> void:
	var L: float = p.L
	var hw: float = p.W * 0.5
	var c: float = p.clear
	var hood: float = p.hood
	var belt: float = p.belt
	var tail: float = p.tail
	var body := [
		[0.0, c + 0.12, hood - 0.2, hood - 0.07, hw - 0.12, hw - 0.07, hw - 0.24],
		[0.2, c, hood - 0.07, hood, hw - 0.04, hw, hw - 0.1],
		[p.a, c, belt - 0.1, belt, hw - 0.04, hw, hw - 0.08],
		[p.e, c, belt - 0.1, maxf(tail, belt - 0.02), hw - 0.04, hw, hw - 0.08],
		[L - 0.2, c, tail - 0.08, tail, hw - 0.04, hw, hw - 0.1],
		[L, c + 0.14, tail - 0.2, tail - 0.07, hw - 0.12, hw - 0.07, hw - 0.22],
	]
	if _lo:
		body.remove_at(4)
		body.remove_at(1)
	_loft(body, [_edges(PAINT, TRIM)], PAINT, PAINT)
	# Greenhouse: windshield, roof (painted top, glass sides with a B pillar),
	# rear glass. Side edges of the windshield and rear glass are pillars.
	var g := hw - 0.07
	var r := hw - 0.24
	var mid: float = (p.b + p.c) * 0.5
	var gh := [
		[p.a, belt - 0.03, belt, belt + 0.01, g, g, g - 0.03],
		[p.b, belt - 0.03, belt + 0.05, p.H, g, g, r],
		[mid - 0.07, belt - 0.03, belt + 0.05, p.H, g, g, r],
		[mid + 0.07, belt - 0.03, belt + 0.05, p.H, g, g, r],
		[p.c, belt - 0.03, belt + 0.05, p.H, g, g, r],
		[p.e, belt - 0.03, belt, belt + 0.01, g, g, g - 0.03],
	]
	var pillar_side: Color = PAINT if p.get("c_pillar", true) else GLASS
	var codes := [
		_edges(GLASS, PAINT, PAINT, GLASS),
		_edges(GLASS, PAINT, GLASS, PAINT),
		_edges(PAINT, PAINT, PAINT, PAINT),
		_edges(GLASS, PAINT, GLASS, PAINT),
		_edges(GLASS, PAINT, pillar_side, GLASS),
	]
	if _lo:
		gh = [gh[0], gh[1], gh[4], gh[5]]
		codes = [codes[0], _edges(GLASS, PAINT, GLASS, PAINT), codes[4]]
	_loft(gh, codes, PAINT, PAINT)
	_wheels(p.axles, p.wr, hw, 0.24)
	# Lights, grille, bumpers, mirrors, plate.
	if _hi:
		_car_face(p)
		_car_rear(p)
	else:
		_box(Vector3(hw - 0.3, hood - 0.13, 0.08), Vector3(0.36, 0.1, 0.12), HEAD, true)
		_box(Vector3(hw - 0.2, tail - 0.13, L - 0.06), Vector3(0.3, 0.12, 0.1), TAIL, true)
	if _lo:
		return
	if not _hi:
		_box(Vector3(0, hood - 0.24, 0.03), Vector3(p.W * 0.42, 0.16, 0.08), p.get("grille", TRIM))
	_box(Vector3(0, c + 0.1, 0.1), Vector3(p.W - 0.3, 0.14, 0.16), TRIM)
	_box(Vector3(0, c + 0.12, L - 0.1), Vector3(p.W - 0.3, 0.14, 0.16), TRIM)
	_box(Vector3(0, tail - 0.3, L + 0.005), Vector3(0.3, 0.15, 0.02), WHITE)
	_box(Vector3(hw + 0.07, belt + 0.07, p.a + 0.2), Vector3(0.14, 0.11, 0.08), PAINT, true)
	if _hi:
		_car_detail(p)


## Ultra: a modern car's face on the nose itself, not tucked behind it:
## slim headlamps in dark housings with an LED running-light strip, the
## upper grille between them and the wide lower intake in the bumper.
## Layers stand 6 mm apart so none of them fight.
func _car_face(p: Dictionary) -> void:
	var hw: float = p.W * 0.5
	var y: float = p.hood - 0.15
	var lx := hw - 0.33
	_box(Vector3(lx, y, 0.044), Vector3(0.34, 0.1, 0.1), TRIM, true)
	_box(Vector3(lx + 0.02, y + 0.01, 0.038), Vector3(0.26, 0.06, 0.1), HEAD, true)
	_box(Vector3(lx, y - 0.04, 0.038), Vector3(0.32, 0.018, 0.1), HEAD, true)
	_box(Vector3(0, y - 0.02, 0.044), Vector3(2.0 * (lx - 0.19), 0.12, 0.1), p.get("grille", TRIM))
	_box(Vector3(0, p.clear + 0.3, 0.044), Vector3(p.W * 0.55, 0.16, 0.1), Color(0.03, 0.03, 0.03, 0.3))


## Ultra: the back of a car on its tail, as the face is on its nose: tail
## lamps across the corners with a clear reversing lamp in each, and the
## dark lower fascia of the bumper.
func _car_rear(p: Dictionary) -> void:
	var hw: float = p.W * 0.5
	var L: float = p.L
	var y: float = p.tail - 0.14
	var lx := hw - 0.33
	_box(Vector3(lx, y, L - 0.044), Vector3(0.36, 0.12, 0.1), TAIL, true)
	_box(Vector3(lx - 0.08, y - 0.02, L - 0.038), Vector3(0.1, 0.04, 0.1), Color(0.85, 0.85, 0.84, 0.4), true)
	_box(Vector3(0, p.clear + 0.22, L - 0.044), Vector3(p.W * 0.7, 0.12, 0.1), Color(0.04, 0.04, 0.04, 0.3))


func _sedan() -> void:  # Toyota Camry
	_car({"L": 4.88, "W": 1.84, "H": 1.44, "clear": 0.16, "hood": 0.82, "belt": 0.98, "a": 1.25,
		"b": 2.1, "c": 3.25, "e": 3.95, "tail": 1.0, "wr": 0.34, "axles": [0.98, 3.8]})


## A Toyota Camry (XV70, 2018-24) lofted from its blueprints instead of a
## few boxes: 4885 mm long, 1840 wide, 1445 high, 2825 wheelbase. The
## side, top and plan outlines are smooth curves through measured points;
## each cross-section rounds from rocker to a bulged side, a shoulder at
## the belt line and a greenhouse that tucks in toward the roof. Wheel
## arches are cut into the sides, the windshield, side glass and rear
## window follow the body, and the lamps wrap round its corners.
## (Test model: not in traffic yet.)
const CAMRY_TOP := [[0.0, 0.55], [0.06, 0.68], [0.2, 0.76], [0.6, 0.83], [1.1, 0.89], [1.55, 0.93],
	[1.7, 0.98], [2.1, 1.22], [2.45, 1.4], [2.9, 1.445], [3.3, 1.42], [3.6, 1.33], [3.95, 1.13],
	[4.15, 1.05], [4.55, 1.03], [4.8, 1.0], [4.885, 0.82]]
const CAMRY_BELT := [[0.0, 0.55], [0.06, 0.66], [0.2, 0.72], [1.0, 0.86], [1.6, 0.93], [2.5, 0.98],
	[3.6, 1.02], [4.3, 1.02], [4.75, 0.99], [4.885, 0.82]]
const CAMRY_ROCKER := [[0.0, 0.3], [0.25, 0.22], [0.6, 0.18], [4.4, 0.19], [4.885, 0.34]]
const CAMRY_WIDTH := [[0.0, 0.7], [0.08, 0.8], [0.3, 0.88], [0.8, 0.915], [2.4, 0.92], [4.2, 0.915],
	[4.7, 0.87], [4.885, 0.76]]
const CAMRY_ROOF_W := [[1.55, 0.84], [2.4, 0.67], [3.0, 0.645], [3.6, 0.67], [4.2, 0.82]]


func _sedan_camry() -> void:
	var axles := [0.975, 3.8]
	var step := 0.3 if _lo else (0.05 if _hi else 0.08)
	var zs := []
	var z := 0.0
	while z < 4.885:
		zs.append(z)
		z += step
	zs.append(4.885)
	var rings := []
	for zz in zs:
		rings.append(_camry_ring(zz, axles))
	var m: int = rings[0].size()
	var codes := []
	for i in zs.size() - 1:
		codes.append(_camry_codes(0.5 * (zs[i] + zs[i + 1]), m))
	_skin(rings, codes)
	_cap(rings[0], PAINT, Vector3(0, 0, 1))
	_cap(rings[rings.size() - 1], PAINT, Vector3(0, 0, -1))
	# The wide dark lower grille and the slim upper one between the lamps.
	_box(Vector3(0, 0.33, 0.03), Vector3(1.15, 0.2, 0.08), TRIM)
	_box(Vector3(0, 0.6, 0.07), Vector3(0.62, 0.05, 0.06), TRIM)
	# Door mirrors on the door skin, below the A-pillar.
	_box(Vector3(0.99, 1.0, 1.86), Vector3(0.14, 0.11, 0.22), PAINT, true)
	for az in axles:
		for sx in [-1.0, 1.0]:
			_wheel(Vector3(sx * 0.79, 0.0, az), 0.335, 0.225, RIM)


## One cross-section: right side from the floor's middle up to the roof's
## middle, then the left side back down (x mirrored).
static func _camry_ring(z: float, axles: Array) -> Array:
	var top := _curve(CAMRY_TOP, z)
	var belt := minf(_curve(CAMRY_BELT, z), top)
	var w := _curve(CAMRY_WIDTH, z)
	var yb := _curve(CAMRY_ROCKER, z)
	for az in axles:
		var dz: float = z - az
		if absf(dz) < 0.4:
			yb = maxf(yb, 0.335 + sqrt(0.16 - dz * dz))  # arch round the tyre
	yb = minf(yb, belt - 0.12)
	var floor_y := minf(0.16, yb)
	# Greenhouse, blended in as the roof rises off the hood and trunk.
	var g := clampf((top - belt - 0.03) / 0.15, 0.0, 1.0)
	var wr := minf(_curve(CAMRY_ROOF_W, clampf(z, 1.55, 4.2)), w - 0.06)
	var hood := [Vector2(w - 0.08, belt + 0.01), Vector2(w * 0.72, lerpf(belt, top, 0.65)),
		Vector2(w * 0.38, top - 0.004)]
	var glass := [Vector2(w - 0.07, belt + 0.02), Vector2(wr + 0.05, top - 0.07), Vector2(wr - 0.1, top - 0.006)]
	var right := [Vector2(0.0, floor_y), Vector2(w - 0.25, floor_y), Vector2(w - 0.03, yb),
		Vector2(w, yb + 0.45 * (belt - yb)), Vector2(w - 0.025, belt)]
	for k in 3:
		right.append((hood[k] as Vector2).lerp(glass[k], g))
	right.append(Vector2(0.0, top))
	var out := []
	for p in right:
		out.append(Vector3(p.x, p.y, z))
	for k in range(right.size() - 2, 0, -1):
		out.append(Vector3(-right[k].x, right[k].y, z))
	return out


## The finish of each strip of a section: floor and arch liners dark, the
## windshield, side glass and rear window, lamps wrapping the corners.
static func _camry_codes(z: float, m: int) -> Array:
	var side := [TRIM, TRIM, PAINT, PAINT, PAINT, PAINT, PAINT, PAINT]
	if z < 0.42:
		side[3] = HEAD
	elif z > 4.6:
		side[3] = TAIL
	if z > 1.95 and z < 3.95 and not (z > 2.86 and z < 2.98):
		side[5] = GLASS
	if z > 1.62 and z < 2.42 or z > 3.38 and z < 4.1:
		side[7] = GLASS
	var out := []
	for e in m:
		out.append(side[e] if e < 8 else side[m - 1 - e])
	return out


## A smooth skin over rings of matching points, shaded smooth across bends
## under 45 degrees and creased past that.
func _skin(rings: Array, codes: Array) -> void:
	var m: int = rings[0].size()
	var fn := []
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var mid := Vector3.ZERO  # the section's middle, so normals point out
		for p in a + b:
			mid += p
		mid /= a.size() * 2
		var row := []
		for e in m:
			var e2 := (e + 1) % m
			var n: Vector3 = (b[e2] - a[e]).cross(a[e2] - b[e])
			if n.length_squared() < 1e-12:
				row.append(Vector3.ZERO)
				continue
			n = n.normalized()
			if n.dot((a[e] + b[e2]) * 0.5 - mid) < 0.0:
				n = -n
			row.append(n)
		fn.append(row)
	for i in rings.size() - 1:
		for e in m:
			var n: Vector3 = fn[i][e]
			if n == Vector3.ZERO:
				continue
			var e2 := (e + 1) % m
			var c: Color = codes[i][e]
			var pts := [rings[i][e], rings[i][e2], rings[i + 1][e2], rings[i + 1][e]]
			var ids := [[i, e], [i, e2], [i + 1, e2], [i + 1, e]]
			var nrm := []
			for v in ids:
				var sum := Vector3.ZERO
				for fi in [v[0] - 1, v[0]]:
					if fi < 0 or fi >= fn.size():
						continue
					for fe in [(v[1] + m - 1) % m, v[1]]:
						var f: Vector3 = fn[fi][fe]
						if f != Vector3.ZERO and f.dot(n) > 0.7 and codes[fi][fe] == c:
							sum += f
				nrm.append(sum.normalized() if sum != Vector3.ZERO else n)
			_tri_n(pts[0], pts[1], pts[2], nrm[0], nrm[1], nrm[2], c)
			_tri_n(pts[0], pts[2], pts[3], nrm[0], nrm[2], nrm[3], c)


## A smooth curve through [[z, value], ...] (monotone, so it never
## overshoots the measured points), flat past either end.
static func _curve(pts: Array, z: float) -> float:
	var n := pts.size()
	if z <= pts[0][0]:
		return pts[0][1]
	if z >= pts[n - 1][0]:
		return pts[n - 1][1]
	var i := 0
	while pts[i + 1][0] < z:
		i += 1
	var z0: float = pts[i][0]
	var z1: float = pts[i + 1][0]
	var h := z1 - z0
	var t := (z - z0) / h
	var y0: float = pts[i][1]
	var y1: float = pts[i + 1][1]
	var s := (y1 - y0) / h
	var m0 := _knot_slope(pts, i, s)
	var m1 := _knot_slope(pts, i + 1, s)
	var t2 := t * t
	var t3 := t2 * t
	return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * h * m0 + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * h * m1


static func _knot_slope(pts: Array, i: int, fallback: float) -> float:
	if i == 0 or i == pts.size() - 1:
		return 0.0 if i == 0 or i == pts.size() - 1 else fallback
	var s0: float = (pts[i][1] - pts[i - 1][1]) / (pts[i][0] - pts[i - 1][0])
	var s1: float = (pts[i + 1][1] - pts[i][1]) / (pts[i + 1][0] - pts[i][0])
	if s0 * s1 <= 0.0:
		return 0.0
	return 2.0 * s0 * s1 / (s0 + s1)


func _hatchback() -> void:  # Honda Civic hatch
	_car({"L": 4.3, "W": 1.8, "H": 1.46, "clear": 0.15, "hood": 0.82, "belt": 0.98, "a": 1.05,
		"b": 1.85, "c": 3.3, "e": 4.12, "tail": 1.02, "wr": 0.33, "axles": [0.9, 3.6]})


func _crossover() -> void:  # Toyota RAV4
	_car({"L": 4.6, "W": 1.86, "H": 1.7, "clear": 0.22, "hood": 1.0, "belt": 1.12, "a": 1.15,
		"b": 1.9, "c": 3.85, "e": 4.42, "tail": 1.14, "wr": 0.37, "axles": [0.95, 3.6], "c_pillar": false, "clad": true})


func _suv() -> void:  # Chevrolet Tahoe
	_car({"L": 5.35, "W": 2.06, "H": 1.93, "clear": 0.26, "hood": 1.2, "belt": 1.3, "a": 1.45,
		"b": 2.15, "c": 4.95, "e": 5.2, "tail": 1.3, "wr": 0.4, "axles": [1.05, 4.15], "c_pillar": false, "clad": true})
	if not _lo:
		for x in [-0.8, 0.8]:
			_box(Vector3(x, 1.96, 3.5), Vector3(0.05, 0.05, 2.4), TRIM)


func _minivan() -> void:  # Honda Odyssey
	_car({"L": 5.18, "W": 2.0, "H": 1.78, "clear": 0.17, "hood": 0.95, "belt": 1.08, "a": 1.05,
		"b": 1.8, "c": 4.75, "e": 5.05, "tail": 1.08, "wr": 0.35, "axles": [0.95, 4.0], "c_pillar": false})


func _sports() -> void:  # Ford Mustang
	_car({"L": 4.81, "W": 1.92, "H": 1.38, "clear": 0.13, "hood": 0.8, "belt": 0.95, "a": 1.85,
		"b": 2.55, "c": 3.2, "e": 4.25, "tail": 0.98, "wr": 0.35, "axles": [1.0, 3.75]})
	if not _lo:
		_box(Vector3(0, 1.06, 4.7), Vector3(1.4, 0.04, 0.16), PAINT)  # spoiler


func _minivan_pacifica() -> void:  # Chrysler Pacifica: lower, sleeker nose
	_car({"L": 5.17, "W": 2.02, "H": 1.77, "clear": 0.15, "hood": 0.92, "belt": 1.04, "a": 1.2,
		"b": 1.95, "c": 4.7, "e": 5.02, "tail": 1.04, "wr": 0.36, "axles": [1.0, 4.08], "c_pillar": false})
	if not _lo:
		for x in [-0.78, 0.78]:
			_box(Vector3(x, 1.8, 3.3), Vector3(0.04, 0.04, 2.2), CHROME)


func _crossover_compact() -> void:  # Honda HR-V / Ford Escape
	_car({"L": 4.39, "W": 1.82, "H": 1.6, "clear": 0.19, "hood": 0.96, "belt": 1.08, "a": 1.1,
		"b": 1.85, "c": 3.65, "e": 4.22, "tail": 1.1, "wr": 0.35, "axles": [0.92, 3.55], "c_pillar": false, "clad": true})


## Jeep Wrangler Unlimited: upright windshield, flat fenders, a spare on
## the tailgate and the seven-slot grille.
func _suv_jeep() -> void:
	_car({"L": 4.88, "W": 1.89, "H": 1.85, "clear": 0.28, "hood": 1.1, "belt": 1.16, "a": 1.55,
		"b": 1.75, "c": 4.55, "e": 4.75, "tail": 1.16, "wr": 0.4, "axles": [0.95, 3.95], "c_pillar": false, "clad": true,
		"grille": Color(0.06, 0.06, 0.06, 0.3)})
	if not _lo:
		_cyl(Vector3(0, 1.28, 4.9), Vector3(0, 1.28, 5.05), 0.38, TIRE, 10)
		for s in [-1.0, 1.0]:
			_box(Vector3(s * 0.98, 0.95, 0.75), Vector3(0.12, 0.05, 0.9), TRIM)
			_box(Vector3(s * 0.98, 0.95, 3.95), Vector3(0.12, 0.05, 0.9), TRIM)


func _taxi() -> void:  # Toyota Camry Hybrid, the usual small-town cab now
	_sedan()
	# Lit roof sign and a checker stripe along the doors.
	_box(Vector3(0, 1.55, 2.6), Vector3(0.75, 0.2, 0.28), WHITE)
	if not _lo:
		for s in [-1.0, 1.0]:
			_box(Vector3(s * 0.925, 0.78, 2.4), Vector3(0.004, 0.1, 1.9), TRIM)


## Ford Crown Victoria, the long body-on-frame sedan most US cab fleets ran
## until hybrids replaced them (a cab company's "hybrids" upgrade).
func _taxi_old() -> void:
	_car({"L": 5.39, "W": 1.99, "H": 1.47, "clear": 0.15, "hood": 0.86, "belt": 1.0, "a": 1.55,
		"b": 2.3, "c": 3.6, "e": 4.3, "tail": 1.02, "wr": 0.34, "axles": [1.15, 4.0], "grille": CHROME})
	_box(Vector3(0, 1.56, 2.9), Vector3(0.75, 0.2, 0.28), WHITE)
	if not _lo:
		for s in [-1.0, 1.0]:
			_box(Vector3(s * 1.0, 0.72, 2.6), Vector3(0.004, 0.1, 2.1), TRIM)


func _sedan_compact() -> void:  # Toyota Corolla
	_car({"L": 4.63, "W": 1.78, "H": 1.43, "clear": 0.14, "hood": 0.8, "belt": 0.96, "a": 1.15,
		"b": 1.95, "c": 3.1, "e": 3.8, "tail": 0.98, "wr": 0.32, "axles": [0.92, 3.62]})


func _sedan_fullsize() -> void:  # Chevrolet Impala: long hood and trunk, chrome grille
	_car({"L": 5.11, "W": 1.86, "H": 1.47, "clear": 0.15, "hood": 0.86, "belt": 1.0, "a": 1.45,
		"b": 2.25, "c": 3.45, "e": 4.15, "tail": 1.02, "wr": 0.34, "axles": [1.05, 3.98], "grille": CHROME})


func _suv_mid() -> void:  # Ford Explorer
	_car({"L": 5.05, "W": 2.0, "H": 1.78, "clear": 0.2, "hood": 1.05, "belt": 1.15, "a": 1.3,
		"b": 2.0, "c": 4.45, "e": 4.85, "tail": 1.15, "wr": 0.38, "axles": [0.98, 3.9], "c_pillar": false, "clad": true})
	if not _lo:
		for x in [-0.78, 0.78]:
			_box(Vector3(x, 1.81, 3.2), Vector3(0.05, 0.05, 2.0), TRIM)


func _wagon() -> void:  # Subaru Outback: low wagon roof, rails, cladding
	_car({"L": 4.87, "W": 1.86, "H": 1.67, "clear": 0.22, "hood": 0.95, "belt": 1.08, "a": 1.25,
		"b": 2.05, "c": 4.45, "e": 4.72, "tail": 1.1, "wr": 0.36, "axles": [0.95, 3.7], "c_pillar": false, "clad": true})
	if not _lo:
		for x in [-0.75, 0.75]:
			_box(Vector3(x, 1.71, 3.2), Vector3(0.05, 0.06, 2.4), TRIM)


func _ev_crossover() -> void:  # Tesla Model Y: smooth nose, no grille, fastback
	_car({"L": 4.75, "W": 1.92, "H": 1.62, "clear": 0.17, "hood": 0.88, "belt": 1.02, "a": 1.2,
		"b": 2.2, "c": 3.35, "e": 4.45, "tail": 1.05, "wr": 0.37, "axles": [0.95, 3.8], "grille": PAINT})


func _hatch_box() -> void:  # Kia Soul: tall, upright box
	_car({"L": 4.2, "W": 1.8, "H": 1.61, "clear": 0.16, "hood": 0.86, "belt": 1.0, "a": 0.95,
		"b": 1.5, "c": 3.85, "e": 4.08, "tail": 1.02, "wr": 0.34, "axles": [0.88, 3.45], "c_pillar": false})


func _pickup_ext() -> void:  # Chevrolet Silverado double cab, 6.5 ft bed
	_truck(5.84, 3.75, [1.15, 4.6], false)


## A 1990s Chevrolet C/K regular cab long bed: square body, chrome grille,
## still common on Indiana farms.
func _pickup_old() -> void:
	_truck(5.55, 3.05, [1.1, 4.45], false, 1.95, 1.82)
	if not _lo:
		_box(Vector3(0, 0.92, 0.01), Vector3(1.5, 0.3, 0.07), CHROME)
		_box(Vector3(0, 0.46, 0.03), Vector3(1.9, 0.2, 0.12), CHROME)


func _pickup_mid() -> void:  # Toyota Tacoma double cab, 5 ft bed
	_truck(5.39, 3.95, [1.0, 4.4], false, 1.9, 1.8)


func _van_low() -> void:  # Ford Transit low roof
	_van_body(5.98, 2.07, 2.08, 2.2, 2.08, PAINT)
	_wheels([1.1, 4.4], 0.37, 1.035, 0.24)
	if not _lo:
		_box(Vector3(1.04, 1.6, 3.0), Vector3(0.004, 0.4, 0.9), GLASS, true)


func _police() -> void:  # Ford Explorer Police Interceptor Utility
	_car({"L": 5.05, "W": 2.0, "H": 1.78, "clear": 0.2, "hood": 1.05, "belt": 1.15, "a": 1.3,
		"b": 2.0, "c": 4.45, "e": 4.85, "tail": 1.15, "wr": 0.38, "axles": [0.98, 3.9], "c_pillar": false})
	# White doors, push bumper, light bar.
	for s in [-1.0, 1.0]:
		_box(Vector3(s * 1.002, 0.72, 2.6), Vector3(0.004, 0.6, 1.9), WHITE)
	_box(Vector3(0, 1.8, 2.5), Vector3(1.2, 0.06, 0.3), TRIM)
	_box(Vector3(-0.32, 1.86, 2.5), Vector3(0.55, 0.08, 0.26), BEACON_RED)
	_box(Vector3(0.32, 1.86, 2.5), Vector3(0.55, 0.08, 0.26), BEACON_BLUE)
	if not _lo:
		_box(Vector3(0, 0.6, -0.08), Vector3(1.1, 0.5, 0.08), TRIM)


## Police light bar and push bumper, shared by the patrol cars.
func _patrol_gear(W: float, roof: float, z: float, doors: Array) -> void:
	for s in [-1.0, 1.0]:
		_box(Vector3(s * (W * 0.5 + 0.002), doors[0], doors[1]), Vector3(0.004, doors[2], doors[3]), WHITE)
	_box(Vector3(0, roof + 0.02, z), Vector3(1.2, 0.06, 0.3), TRIM)
	_box(Vector3(-0.32, roof + 0.08, z), Vector3(0.55, 0.08, 0.26), BEACON_RED)
	_box(Vector3(0.32, roof + 0.08, z), Vector3(0.55, 0.08, 0.26), BEACON_BLUE)
	if not _lo:
		_box(Vector3(0, 0.55, -0.08), Vector3(1.1, 0.45, 0.08), TRIM)


func _police_charger() -> void:  # Dodge Charger Pursuit
	_car({"L": 5.1, "W": 1.9, "H": 1.48, "clear": 0.14, "hood": 0.86, "belt": 1.0, "a": 1.45,
		"b": 2.3, "c": 3.45, "e": 4.25, "tail": 1.02, "wr": 0.37, "axles": [1.05, 4.1]})
	_patrol_gear(1.9, 1.48, 2.85, [0.7, 2.75, 0.5, 1.9])


func _police_tahoe() -> void:  # Chevrolet Tahoe PPV, the county sheriff's usual
	_car({"L": 5.35, "W": 2.06, "H": 1.93, "clear": 0.26, "hood": 1.2, "belt": 1.3, "a": 1.45,
		"b": 2.15, "c": 4.95, "e": 5.2, "tail": 1.3, "wr": 0.4, "axles": [1.05, 4.15], "c_pillar": false})
	_patrol_gear(2.06, 1.93, 2.6, [0.85, 2.7, 0.65, 2.0])


## Ultra close-up detail on a car body: door seams and handles, mirror
## glass, wipers, a front plate, side markers and the maker's badge.
func _car_detail(p: Dictionary) -> void:
	var hw: float = p.W * 0.5
	var belt: float = p.belt
	var c: float = p.clear
	var seam := Color(0.04, 0.04, 0.04, 0.3)
	var doors: Array = [p.a + 0.08, (p.b + p.c) * 0.5]
	if p.c - p.b > 1.2:
		doors.append(p.c - 0.05)
	for s in [-1.0, 1.0]:
		var x: float = s * (hw + 0.003)
		for z in doors:
			_box(Vector3(x, (c + belt) * 0.5 + 0.1, z), Vector3(0.004, belt - c - 0.15, 0.012), seam)
		_box(Vector3(x, c + 0.2, (doors[0] + doors[doors.size() - 1]) * 0.5),
			Vector3(0.004, 0.012, doors[doors.size() - 1] - doors[0]), seam)
		for i in doors.size() - 1:
			_box(Vector3(s * (hw + 0.012), belt - 0.12, doors[i + 1] - 0.25), Vector3(0.02, 0.035, 0.16), CHROME)
		_box(Vector3(s * (hw + 0.115), belt + 0.07, p.a + 0.2), Vector3(0.006, 0.08, 0.06), GLASS)
		_box(Vector3(s * (hw - 0.02), p.hood - 0.15, 0.35), Vector3(0.02, 0.04, 0.1), Color(0.95, 0.55, 0.05, 0.5))
		_box(Vector3(s * (hw - 0.02), p.tail - 0.15, p.L - 0.35), Vector3(0.02, 0.04, 0.1), TAIL)
	# Wipers parked at the foot of the windshield.
	for x in [-0.35, 0.3]:
		_box(Vector3(x, belt + 0.03, p.a + 0.1), Vector3(0.5, 0.015, 0.02), seam)
	_box(Vector3(0, p.hood - 0.42, -0.005), Vector3(0.3, 0.15, 0.02), WHITE)
	_box(Vector3(0, p.hood - 0.17, -0.008), Vector3(0.1, 0.06, 0.02), CHROME)
	if p.get("clad", false):
		_cladding(p)


## Ultra: the unpainted black plastic that SUVs and crossovers wear (RAV4,
## Explorer, Outback, Wrangler): flares round the wheel arches and a rocker
## strip along the sills between them. It stands 12 mm proud of the body,
## clear of the dark wheel well (4 mm) and the door seams.
func _cladding(p: Dictionary) -> void:
	var hw: float = p.W * 0.5
	var r: float = p.wr + 0.07
	var band := 0.075
	var axles: Array = p.axles
	for s in [-1.0, 1.0]:
		for z in axles:
			_flare(Vector3(s * hw, p.wr, z), r, r + band, s, 0.012)
		var z0: float = axles[0] + r + band * 0.5
		var z1: float = axles[1] - r - band * 0.5
		_box(Vector3(s * (hw - 0.018), p.clear + 0.08, (z0 + z1) * 0.5), Vector3(0.06, 0.16, z1 - z0), TRIM)


## A flat half-ring round a wheel arch from radius r0 to r1, `depth` proud
## of the body side at `c` (x on the body side), with its outer lip
## running back into the body where it tucks in toward the sill.
func _flare(c: Vector3, r0: float, r1: float, side: float, depth: float) -> void:
	var n := 14
	var x := c.x + side * depth
	var inside := Vector3(c.x - side, c.y, c.z)
	for i in n:
		var a1 := PI * i / n
		var a2 := PI * (i + 1) / n
		var d1 := Vector3(0, sin(a1), cos(a1))
		var d2 := Vector3(0, sin(a2), cos(a2))
		var o1 := Vector3(x, c.y, c.z) + d1 * r1
		var o2 := Vector3(x, c.y, c.z) + d2 * r1
		_quad(Vector3(x, c.y, c.z) + d1 * r0, Vector3(x, c.y, c.z) + d2 * r0, o2, o1, TRIM, inside)
		var mid := Vector3(c.x, c.y, c.z) + (d1 + d2) * 0.5 * (r1 - 0.05)
		_quad(o1, o2, o2 - Vector3(side * (depth + 0.04), 0, 0), o1 - Vector3(side * (depth + 0.04), 0, 0), TRIM, mid)


# --- Pickups ----------------------------------------------------------------

## A body-on-frame pickup: hood, cab (crew or regular) and an open bed.
func _truck(L: float, cab_end: float, wb: Array, work: bool, W := 2.03, H := 1.96) -> void:
	var hw := W * 0.5
	var c := 0.32
	var belt := 1.32 * H / 1.96
	var body := [
		[0.0, c + 0.14, 1.06, 1.2, hw - 0.1, hw - 0.06, hw - 0.18],
		[0.18, c, 1.18, 1.28, hw - 0.03, hw, hw - 0.06],
		[1.75, c, belt - 0.08, belt, hw - 0.03, hw, hw - 0.05],
		[L - 0.1, c, belt - 0.08, belt, hw - 0.03, hw, hw - 0.05],
		[L, c + 0.08, belt - 0.12, belt - 0.02, hw - 0.06, hw - 0.04, hw - 0.08],
	]
	_loft(body, [_edges(PAINT, TRIM)], PAINT, PAINT)
	var g := hw - 0.07
	var r := hw - 0.2
	var gh := [
		[1.75, belt - 0.03, belt, belt + 0.01, g, g, g - 0.02],
		[2.45, belt - 0.03, belt + 0.05, H, g, g, r],
		[cab_end - 0.08, belt - 0.03, belt + 0.05, H, g, g, r],
		[cab_end, belt - 0.03, belt + 0.05, H - 0.02, g, g, r],
	]
	_loft(gh, [_edges(GLASS, PAINT, PAINT, GLASS), _edges(GLASS, PAINT, GLASS, PAINT),
		_edges(PAINT, PAINT, PAINT, PAINT)], PAINT, PAINT)
	# The open bed: dark floor between the bed rails.
	_box(Vector3(0, belt + 0.008, (cab_end + 0.08 + L - 0.08) * 0.5), Vector3(W - 0.18, 0.004, L - cab_end - 0.2), DARK)
	_wheels(wb, 0.42, hw, 0.28)
	if _hi:
		_truck_face(hw, c, work)
	else:
		_box(Vector3(hw - 0.28, 1.08, 0.05), Vector3(0.36, 0.16, 0.12), HEAD, true)
	_box(Vector3(hw - 0.07, 1.05, L - 0.03), Vector3(0.12, 0.34, 0.08), TAIL, true)
	if _lo:
		return
	if not _hi:
		_box(Vector3(0, 0.9, 0.03), Vector3(1.3, 0.34, 0.08), CHROME if work else TRIM)
	_box(Vector3(0, c + 0.12, 0.05), Vector3(W - 0.1, 0.2, 0.14), CHROME if work else TRIM)
	_box(Vector3(0, c + 0.12, L - 0.02), Vector3(W - 0.1, 0.18, 0.12), CHROME)
	_box(Vector3(hw + 0.1, belt + 0.12, 1.95), Vector3(0.16, 0.2, 0.1), TRIM, true)
	if _hi:
		# Cab door seams and handles, the bed's tailgate seam, plates.
		var seam := Color(0.04, 0.04, 0.04, 0.3)
		for s in [-1.0, 1.0]:
			var x: float = s * (hw + 0.003)
			var doors: Array = [1.8, cab_end - 0.05] if cab_end - 1.8 < 1.6 else [1.8, (1.8 + cab_end) * 0.5, cab_end - 0.05]
			for z in doors:
				_box(Vector3(x, (c + belt) * 0.5 + 0.12, z), Vector3(0.004, belt - c - 0.2, 0.012), seam)
			for i in doors.size() - 1:
				_box(Vector3(s * (hw + 0.012), belt - 0.15, doors[i + 1] - 0.25), Vector3(0.02, 0.035, 0.16), CHROME)
		_box(Vector3(0, belt - 0.1, L + 0.004), Vector3(W - 0.3, 0.012, 0.004), seam)
		_box(Vector3(0, 0.62, L + 0.005), Vector3(0.3, 0.15, 0.02), WHITE)
		_box(Vector3(0, 0.62, -0.01), Vector3(0.3, 0.15, 0.02), WHITE)
		for x in [-0.4, 0.35]:
			_box(Vector3(x, belt + 0.03, 1.85), Vector3(0.55, 0.015, 0.02), seam)
	if work:
		# Diamond-plate toolbox across the front of the bed, and a contractor
		# ladder rack (Weather Guard style): two hoops joined by side rails
		# along the top, carrying an aluminium extension ladder.
		_box(Vector3(0, belt + 0.15, cab_end + 0.35), Vector3(W - 0.1, 0.3, 0.5), STEEL)
		var z0 := cab_end + 0.15
		var z1 := L - 0.2
		for z in [z0, z1]:
			_box(Vector3(0, 2.1, z), Vector3(W - 0.1, 0.06, 0.06), TRIM)
			for x in [-hw + 0.05, hw - 0.05]:
				_box(Vector3(x, (2.1 + belt) * 0.5, z), Vector3(0.05, 2.1 - belt, 0.05), TRIM)
		for x in [-hw + 0.05, hw - 0.05]:
			_box(Vector3(x, 2.1, (z0 + z1) * 0.5), Vector3(0.05, 0.06, z1 - z0), TRIM)
		var lz := (cab_end + L) * 0.5 - 0.3
		var ll := L - cab_end + 0.6
		for x in [-0.22, 0.22]:
			_box(Vector3(x, 2.17, lz), Vector3(0.05, 0.08, ll), CHROME)
		if _hi:
			for i in int(ll / 0.3):
				_box(Vector3(0, 2.17, lz - ll * 0.5 + 0.15 + i * 0.3), Vector3(0.44, 0.03, 0.03), CHROME)


## Ultra: a full-size pickup's face, after the F-150 / Silverado: a tall
## grille between the headlamps with a chrome frame and two bars, lamp
## housings with an LED running-light strip under and inside the lens, a
## badge, and fog lamps in the bumper. Nothing stands out past 1.2 cm, so
## an older truck's chrome grille still covers it.
func _truck_face(hw: float, c: float, work: bool) -> void:
	var gx := hw - 0.53
	_box(Vector3(0, 0.94, 0.034), Vector3(gx * 2.0, 0.44, 0.08), Color(0.03, 0.03, 0.03, 0.3))
	var trim := STEEL if work else CHROME
	for y in [0.735, 1.145]:
		_box(Vector3(0, y, 0.028), Vector3(gx * 2.0 + 0.04, 0.05, 0.084), trim)
	_box(Vector3(gx, 0.94, 0.028), Vector3(0.04, 0.45, 0.084), trim, true)
	for y in [0.87, 1.01]:
		_box(Vector3(0, y, 0.028), Vector3(gx * 2.0, 0.055, 0.084), trim)
	_box(Vector3(0, 0.94, 0.022), Vector3(0.2, 0.09, 0.084), Color(0.1, 0.2, 0.45, 0.4))
	# Headlamps: dark housing, clear lens, C-shaped running light.
	var lx := hw - 0.27
	_box(Vector3(lx, 1.07, 0.044), Vector3(0.44, 0.22, 0.1), TRIM, true)
	_box(Vector3(lx + 0.02, 1.095, 0.038), Vector3(0.34, 0.11, 0.1), HEAD, true)
	_box(Vector3(lx, 0.98, 0.038), Vector3(0.42, 0.025, 0.1), HEAD, true)
	_box(Vector3(lx - 0.2, 1.06, 0.038), Vector3(0.025, 0.18, 0.1), HEAD, true)
	# Fog lamps in the bumper.
	_box(Vector3(hw - 0.3, c + 0.12, -0.005), Vector3(0.14, 0.07, 0.05), HEAD, true)


func _pickup() -> void:  # Ford F-150 SuperCrew, 5.5 ft bed
	_truck(5.89, 4.2, [1.15, 4.72], false)


func _work_pickup() -> void:  # Ford F-250 regular cab, 8 ft bed
	_truck(5.94, 3.2, [1.15, 4.8], true)


func _tow_truck() -> void:  # wrecker on a Ford F-550
	var L := 7.0
	_truck(L, 3.3, [1.2, 5.2], false)
	_box(Vector3(0, 1.45, 5.15), Vector3(2.2, 0.25, 3.6), TRIM)
	_box(Vector3(0, 2.0, 2.98), Vector3(1.5, 0.12, 0.22), BEACON_AMBER)
	if not _lo:
		_beam(Vector3(0, 1.6, 4.0), Vector3(0, 2.3, 6.4), 0.18, PAINT)
		_box(Vector3(0, 0.75, 6.9), Vector3(1.6, 0.12, 0.3), TRIM)


## An insulated aerial lift (Altec AT40G) on a Ford F-550 with a utility
## service body: side compartments, turntable behind the cab, the boom
## stowed toward the back and the fiberglass bucket at the tail.
func _bucket_truck() -> void:
	var L := 8.2
	_truck(L, 3.3, [1.2, 5.6], false, 2.2, 2.05)
	# Service body: compartments down each side, open well in the middle.
	for s in [-1.0, 1.0]:
		_box(Vector3(s * 0.95, 1.45, 5.75), Vector3(0.5, 1.1, 4.7), WHITE)
		if not _lo:
			for z in [4.2, 5.4, 6.6, 7.6]:
				_box(Vector3(s * 1.202, 1.45, z), Vector3(0.006, 0.9, 0.04), STEEL)
				_box(Vector3(s * 1.203, 1.55, z + 0.4), Vector3(0.006, 0.05, 0.14), CHROME)
	_box(Vector3(0, 1.0, 5.75), Vector3(1.4, 0.06, 4.7), DARK)
	# Turntable and pedestal, the boom lying back on its rest.
	var pivot := Vector3(0, 2.25, 3.95)
	_cyl(Vector3(0, 1.0, 3.95), pivot, 0.32, WHITE, 10)
	_box(Vector3(0, 2.15, 7.0), Vector3(0.2, 0.3, 0.2), TRIM)
	_beam(pivot, Vector3(0, 2.4, 7.4), 0.32, WHITE)
	_beam(Vector3(0, 2.4, 6.2), Vector3(0, 2.45, 7.9), 0.24, Color(0.85, 0.85, 0.82, 0.4))
	# Yellow fiberglass bucket hanging off the tail.
	_box(Vector3(0, 2.25, 8.3), Vector3(0.75, 1.05, 0.75), Color(0.90, 0.72, 0.08, 0.4))
	_box(Vector3(0, 2.04, 2.98), Vector3(1.2, 0.1, 0.2), BEACON_AMBER)
	if not _lo:
		_box(Vector3(0, 2.78, 8.3), Vector3(0.7, 0.02, 0.7), DARK)
		_cyl(Vector3(0, 1.6, 3.95), Vector3(0, 2.5, 6.9), 0.07, CHROME, 6)


## A Class C motorhome (Thor Four Winds on a Ford E-450 cutaway): van cab,
## a fiberglass box with the bunk over the cab, side windows, an entry door
## and the maker's swoosh in the paint colour.
func _rv() -> void:
	var L := 9.4
	_van_body(3.0, 2.3, 2.45, 2.4, 1.2, PAINT)
	var hw := 1.22
	_loft([
		[0.95, 2.2, 2.4, 2.45, hw - 0.1, hw - 0.06, hw - 0.16],
		[1.5, 1.6, 3.3, 3.42, hw - 0.04, hw, hw - 0.08],
		[2.4, 0.6, 3.3, 3.42, hw, hw, hw - 0.06],
		[L - 0.15, 0.6, 3.3, 3.42, hw, hw, hw - 0.06],
		[L, 0.75, 3.2, 3.32, hw - 0.04, hw - 0.04, hw - 0.1],
	], [_edges(WHITE, TRIM)], WHITE, WHITE)
	_wheels([1.1, 5.9], 0.4, 1.15, 0.3)
	_box(Vector3(hw - 0.08, 1.2, L + 0.01), Vector3(0.14, 0.3, 0.04), TAIL, true)
	for s in [-1.0, 1.0]:
		_box(Vector3(s * (hw + 0.004), 1.15, 5.8), Vector3(0.006, 0.18, 6.6), PAINT)
		_box(Vector3(s * (hw + 0.004), 2.95, 5.8), Vector3(0.006, 0.1, 6.6), PAINT)
		if _lo:
			continue
		for z in [3.3, 6.6, 8.4]:
			_box(Vector3(s * (hw + 0.005), 2.15, z), Vector3(0.006, 0.6, 1.1), GLASS)
		_box(Vector3(s * (hw - 0.3), 2.4, 1.15), Vector3(0.006, 0.3, 0.5), GLASS)
	if not _lo:
		_box(Vector3(hw + 0.005, 1.7, 4.6), Vector3(0.006, 1.8, 0.65), Color(0.85, 0.85, 0.83, 0.4))
		_box(Vector3(0, 3.55, 6.0), Vector3(0.75, 0.22, 0.9), WHITE)  # roof air conditioner
		_box(Vector3(0, 0.6, L + 0.12), Vector3(0.3, 0.12, 0.24), TRIM)  # hitch


## A Class A diesel pusher (Winnebago, Tiffin): a bus-like box with a big
## one-piece windshield, a cap over it, and paint swooshes down the sides.
func _motorhome() -> void:
	var L := 11.3
	var hw := 1.27
	_loft([
		[0.0, 0.45, 1.3, 1.55, hw - 0.12, hw - 0.08, hw - 0.2],
		[0.15, 0.4, 1.4, 1.7, hw - 0.04, hw, hw - 0.1],
		[0.6, 0.4, 2.95, 3.35, hw, hw, hw - 0.12],
		[1.3, 0.4, 3.6, 3.72, hw, hw, hw - 0.06],
		[L - 0.15, 0.4, 3.6, 3.72, hw, hw, hw - 0.06],
		[L, 0.5, 3.5, 3.62, hw - 0.04, hw - 0.04, hw - 0.1],
	], [_edges(WHITE, TRIM)], WHITE, WHITE)
	# Windshield and the driver's side windows.
	_quad(Vector3(-hw + 0.1, 1.6, 0.1), Vector3(hw - 0.1, 1.6, 0.1), Vector3(hw - 0.1, 2.85, 0.38),
		Vector3(-hw + 0.1, 2.85, 0.38), GLASS, Vector3(0, 2.0, 3.0))
	_wheels([2.0, 7.1], 0.5, 1.2, 0.32)
	_box(Vector3(hw - 0.3, 0.95, 0.04), Vector3(0.4, 0.15, 0.1), HEAD, true)
	_box(Vector3(hw - 0.08, 1.3, L + 0.01), Vector3(0.14, 0.4, 0.04), TAIL, true)
	for s in [-1.0, 1.0]:
		_box(Vector3(s * (hw + 0.004), 0.95, 6.0), Vector3(0.006, 0.45, 9.6), PAINT)
		_box(Vector3(s * (hw + 0.004), 3.2, 6.6), Vector3(0.006, 0.12, 8.8), PAINT)
		if _lo:
			continue
		_box(Vector3(s * (hw + 0.005), 2.25, 1.6), Vector3(0.006, 0.8, 1.2), GLASS)
		for z in [4.2, 6.8, 9.6]:
			_box(Vector3(s * (hw + 0.005), 2.3, z), Vector3(0.006, 0.7, 1.4), GLASS)
		_box(Vector3(s * (hw + 0.12), 2.6, 0.5), Vector3(0.06, 0.4, 0.12), TRIM)
	if not _lo:
		_box(Vector3(0, 0.75, 0.02), Vector3(1.4, 0.35, 0.06), CHROME)
		for z in [3.5, 8.0]:
			_box(Vector3(0, 3.85, z), Vector3(0.75, 0.22, 0.9), WHITE)


## A Ford F-250 with a slide-in truck camper (Lance): the cabover bunk
## rides above the cab roof and the box hangs past the tailgate.
func _pickup_camper() -> void:
	_truck(5.94, 3.2, [1.15, 4.8], false)
	var hw := 1.15
	_loft([
		[2.55, 2.0, 2.15, 2.2, hw - 0.1, hw - 0.08, hw - 0.14],
		[2.9, 1.95, 3.1, 3.2, hw - 0.02, hw, hw - 0.06],
		[3.25, 1.3, 3.1, 3.2, hw, hw, hw - 0.06],
		[6.7, 1.3, 3.1, 3.2, hw, hw, hw - 0.06],
	], [_edges(WHITE, TRIM)], WHITE, WHITE)
	for s in [-1.0, 1.0]:
		_box(Vector3(s * (hw + 0.004), 1.55, 4.9), Vector3(0.006, 0.12, 3.6), PAINT)
		if not _lo:
			_box(Vector3(s * (hw + 0.005), 2.45, 4.4), Vector3(0.006, 0.5, 0.9), GLASS)
	if not _lo:
		_box(Vector3(0, 2.3, 6.71), Vector3(0.7, 1.6, 0.01), Color(0.85, 0.85, 0.83, 0.4))
		_box(Vector3(0, 3.3, 5.0), Vector3(0.7, 0.2, 0.8), WHITE)


# --- Vans and trucks --------------------------------------------------------

## A short-nose van cab followed by a tall body (Transit, ambulance module).
func _van_body(L: float, W: float, H: float, box_from: float, box_h: float, box_code: Color) -> void:
	var hw := W * 0.5
	var c := 0.3
	_loft([
		[0.0, c + 0.12, 0.85, 0.98, hw - 0.12, hw - 0.08, hw - 0.22],
		[0.2, c, 0.98, 1.08, hw - 0.03, hw, hw - 0.08],
		[0.85, c, 1.12, 1.2, hw - 0.03, hw, hw - 0.06],
		[box_from, c, 1.12, 1.2, hw - 0.03, hw, hw - 0.06],
	], [_edges(PAINT, TRIM)], PAINT, PAINT)
	# Cab with windshield, side windows.
	var g := hw - 0.05
	_loft([
		[0.85, 1.17, 1.2, 1.21, g, g, g - 0.02],
		[1.65, 1.17, 1.24, H - 0.05, g, g, g - 0.1],
		[box_from, 1.17, 1.24, H - 0.05, g, g, g - 0.1],
	], [_edges(GLASS, PAINT, PAINT, GLASS), _edges(PAINT, PAINT, GLASS, PAINT)], PAINT, PAINT)
	_loft([
		[box_from, c, box_h - 0.12, box_h, hw, hw, hw - 0.06],
		[L, c, box_h - 0.12, box_h, hw, hw, hw - 0.06],
	], [_edges(box_code, TRIM)], box_code, box_code)
	_box(Vector3(hw - 0.25, 0.92, 0.07), Vector3(0.34, 0.14, 0.12), HEAD, true)
	_box(Vector3(hw - 0.06, 1.2, L - 0.02), Vector3(0.1, 0.4, 0.06), TAIL, true)
	if not _lo:
		_box(Vector3(0, 0.75, 0.03), Vector3(1.2, 0.3, 0.08), TRIM)
		_box(Vector3(0, c + 0.1, 0.06), Vector3(W - 0.15, 0.18, 0.14), TRIM)
		_box(Vector3(hw + 0.12, 1.45, 1.05), Vector3(0.1, 0.32, 0.18), TRIM, true)


func _van() -> void:  # Ford Transit high roof
	_van_body(6.0, 2.07, 2.75, 2.2, 2.75, PAINT)
	_wheels([1.1, 4.4], 0.37, 1.035, 0.24)
	if not _lo:
		_box(Vector3(1.04, 1.8, 3.0), Vector3(0.004, 0.45, 0.9), GLASS, true)


## Oshkosh NGDV, the Postal Service's new carrier truck: short sloping hood,
## tall body, big windshield, postal white with the red and blue stripe.
func _mail_truck() -> void:
	_van_body(5.4, 2.05, 2.35, 1.9, 2.9, PAINT)
	_wheels([0.95, 4.3], 0.38, 1.025, 0.26)
	for s in [-1.0, 1.0]:
		_box(Vector3(s * 1.029, 1.05, 3.6), Vector3(0.004, 0.12, 3.4), USPS_RED)
		_box(Vector3(s * 1.029, 0.92, 3.6), Vector3(0.004, 0.12, 3.4), USPS_BLUE)
	if not _lo:
		# Eagle badge on the side and the sliding door's window.
		_box(Vector3(1.031, 2.1, 3.2), Vector3(0.004, 0.45, 0.6), USPS_BLUE, true)
		_box(Vector3(1.031, 1.75, 1.5), Vector3(0.004, 0.5, 0.5), GLASS, true)


## A rural carrier's own right-hand-drive Jeep Wrangler, with the roof
## beacon and U.S. MAIL sign rural routes use.
func _rural_mail() -> void:
	_car({"L": 4.88, "W": 1.89, "H": 1.85, "clear": 0.28, "hood": 1.1, "belt": 1.16, "a": 1.55,
		"b": 1.75, "c": 4.55, "e": 4.75, "tail": 1.16, "wr": 0.4, "axles": [0.95, 3.95], "c_pillar": false,
		"grille": Color(0.06, 0.06, 0.06, 0.3)})
	_box(Vector3(0, 1.9, 2.4), Vector3(0.25, 0.1, 0.18), BEACON_AMBER)
	if not _lo:
		_box(Vector3(0, 1.98, 3.3), Vector3(0.9, 0.26, 0.04), WHITE)
		_cyl(Vector3(0, 1.28, 4.9), Vector3(0, 1.28, 5.05), 0.38, TIRE, 10)  # spare on the tailgate


## Type III module on a Ford E-450 cutaway, as Indiana EMS run them (KKK-A
## 1822 / NFPA 1917 markings): a white module with a broad red band, the
## blue Star of Life on the sides, back and roof (big enough to read from
## the air), red and white warning lights at the module's corners and a
## light bar on the cab. A line of plain white boxes read as box trucks and
## a box truck read as an ambulance (look check, 2026-10-25).
func _ambulance() -> void:
	_van_body(7.0, 2.4, 2.4, 2.4, 3.0, PAINT)
	_wheels([1.1, 5.1], 0.4, 1.2, 0.3)
	for s in [-1.0, 1.0]:
		# The red band down the module and the cab doors, a pinstripe above.
		_box(Vector3(s * 1.205, 1.12, 4.7), Vector3(0.004, 0.42, 4.6), EMS_RED)
		_box(Vector3(s * 1.205, 2.74, 4.7), Vector3(0.004, 0.12, 4.6), EMS_RED)
		_box(Vector3(s * 1.205, 0.98, 1.55), Vector3(0.004, 0.26, 1.5), EMS_RED)
		_star(Vector3(s * 1.208, 2.0, 5.75), Vector3(s, 0, 0), 0.62)
		if not _lo:
			# Side entry door and its window, ahead of the star.
			_box(Vector3(s * 1.211, 1.75, 3.2), Vector3(0.004, 1.9, 0.04), DARK)
			_box(Vector3(s * 1.211, 2.25, 3.65), Vector3(0.004, 0.45, 0.6), GLASS)
	_star(Vector3(0, 3.004, 4.9), Vector3.UP, 1.5)  # on the roof
	_star(Vector3(0, 2.15, 7.004), Vector3.BACK, 0.5)  # on the back doors
	# A red band across the back, and the word over the cab in red.
	_box(Vector3(0, 1.12, 7.006), Vector3(2.3, 0.42, 0.004), EMS_RED)
	_box(Vector3(0, 2.72, 2.396), Vector3(1.6, 0.22, 0.004), EMS_RED)
	# Cab light bar: red, clear, red.
	_box(Vector3(0, 2.42, 1.95), Vector3(1.7, 0.12, 0.26), TRIM)
	_box(Vector3(-0.5, 2.5, 1.95), Vector3(0.6, 0.1, 0.24), BEACON_RED)
	_box(Vector3(0.5, 2.5, 1.95), Vector3(0.6, 0.1, 0.24), BEACON_RED)
	_box(Vector3(0, 2.5, 1.95), Vector3(0.38, 0.1, 0.24), HEAD)
	# Module corner lights, front and back, standing proud of the roof edge.
	for x in [-1.08, 1.08]:
		_box(Vector3(x, 2.88, 2.37), Vector3(0.22, 0.16, 0.06), BEACON_RED)
		_box(Vector3(x, 2.88, 7.03), Vector3(0.22, 0.16, 0.06), BEACON_RED)
		_box(Vector3(x * 1.11, 2.88, 2.6), Vector3(0.04, 0.16, 0.24), BEACON_RED)
		_box(Vector3(x * 1.11, 2.88, 6.85), Vector3(0.04, 0.16, 0.24), BEACON_RED)
	_box(Vector3(0, 2.88, 2.37), Vector3(0.3, 0.12, 0.06), HEAD)


## The Star of Life: three crossed bars in EMS blue, flat on a face with
## normal `n`, `size` metres tip to tip, with a white rim like the decal's.
func _star(c: Vector3, n: Vector3, size: float) -> void:
	var u := Vector3.UP if absf(n.y) < 0.5 else Vector3.BACK
	u = (u - n * u.dot(n)).normalized()
	var v := n.cross(u)
	for k in 3:
		var ang := PI / 3.0 * k
		var a := u * cos(ang) + v * sin(ang)
		_flat(c + n * 0.002, a, n, size, size * 0.3, PAINT)
		_flat(c + n * 0.008, a, n, size * 0.86, size * 0.2, EMS_BLUE)


## A flat strip on a face: centre, direction along it, the face's normal,
## length and width.
func _flat(c: Vector3, along: Vector3, n: Vector3, length: float, width: float, col: Color) -> void:
	var a := along * length * 0.5
	var b := n.cross(along).normalized() * width * 0.5
	_quad(c - a - b, c + a - b, c + a + b, c - a + b, col, c - n)


func _delivery_van() -> void:  # step van (Freightliner MT45 / Ford P1000)
	var L := 7.0
	var hw := 1.2
	_loft([
		[0.0, 0.42, 0.95, 1.05, hw - 0.14, hw - 0.1, hw - 0.2],
		[0.5, 0.38, 1.1, 1.2, hw - 0.03, hw, hw - 0.04],
		[0.56, 0.38, 2.9, 3.1, hw - 0.03, hw, hw - 0.04],
		[L, 0.38, 2.9, 3.1, hw - 0.02, hw, hw - 0.02],
	], [_edges(PAINT, TRIM)], PAINT, PAINT)
	# Flat windshield and the cab's open side door.
	_box(Vector3(0, 1.85, 0.55), Vector3(2.2, 1.0, 0.04), GLASS)
	for s in [-1.0, 1.0]:
		_box(Vector3(s * 1.205, 1.7, 1.25), Vector3(0.006, 0.9, 0.8), GLASS)
	_wheels([1.0, 5.3], 0.45, hw, 0.28)
	_box(Vector3(hw - 0.25, 0.9, 0.02), Vector3(0.3, 0.14, 0.1), HEAD, true)
	_box(Vector3(hw - 0.08, 1.0, L + 0.01), Vector3(0.12, 0.3, 0.04), TAIL, true)
	if not _lo:
		_box(Vector3(0, 1.6, L + 0.01), Vector3(1.6, 2.2, 0.02), DARK)


## A conventional medium-duty cab (Freightliner M2): hood, cab and its glass.
## Returns where the cab ends.
func _md_cab(W: float, paint := PAINT) -> float:
	var hw := W * 0.5
	var c := 0.55
	_loft([
		[0.0, c + 0.1, 1.15, 1.35, hw - 0.25, hw - 0.2, hw - 0.4],
		[0.3, c, 1.4, 1.55, hw - 0.12, hw - 0.1, hw - 0.3],
		[1.55, c, 1.6, 1.75, hw - 0.1, hw - 0.05, hw - 0.12],
		[3.0, c, 1.6, 1.75, hw - 0.1, hw - 0.05, hw - 0.12],
	], [_edges(paint, TRIM)], paint, paint)
	_loft([
		[1.6, 1.7, 1.74, 1.75, hw - 0.12, hw - 0.12, hw - 0.14],
		[2.15, 1.7, 1.78, 2.75, hw - 0.12, hw - 0.12, hw - 0.2],
		[3.0, 1.7, 1.78, 2.75, hw - 0.12, hw - 0.12, hw - 0.2],
	], [_edges(GLASS, paint, paint, GLASS), _edges(paint, paint, GLASS, paint)], paint, paint)
	_box(Vector3(0, 1.0, 0.02), Vector3(1.0, 0.65, 0.06), CHROME)
	_box(Vector3(0, 0.65, -0.05), Vector3(W - 0.2, 0.22, 0.2), CHROME if not _lo else TRIM)
	if _hi:
		_heavy_face(hw - 0.42, 1.05, 1.0, 1.0, 0.65)
	else:
		_box(Vector3(hw - 0.4, 1.15, 0.12), Vector3(0.3, 0.16, 0.12), HEAD, true)
	if not _lo:
		for s in [-1.0, 1.0]:
			_box(Vector3(s * (hw + 0.12), 2.1, 1.75), Vector3(0.06, 0.45, 0.14), TRIM)
	return 3.0


## Ultra: a truck cab's face (Freightliner M2 and Cascadia, Peterbilt): the
## headlamps on the nose in dark housings with an amber marker, and dark
## bars across the chrome grille (gw wide, gh high, centred at gy), each
## layer 6 mm proud of the one behind.
func _heavy_face(lx: float, ly: float, gw: float, gy: float, gh: float) -> void:
	_box(Vector3(lx, ly, 0.044), Vector3(0.36, 0.2, 0.1), TRIM, true)
	_box(Vector3(lx + 0.03, ly + 0.02, 0.038), Vector3(0.24, 0.12, 0.1), HEAD, true)
	_box(Vector3(lx + 0.14, ly - 0.07, 0.038), Vector3(0.06, 0.04, 0.1), Color(1.0, 0.55, 0.05, 0.5), true)
	var n := int(gh / 0.11)
	for i in range(1, n):  # the lowest slot is behind the bumper
		_box(Vector3(0, gy - gh * 0.5 + (i + 0.5) * gh / n, 0.034), Vector3(gw - 0.08, 0.035, 0.1), Color(0.05, 0.05, 0.05, 0.3))


## A 26 ft box truck on a Freightliner M2: the box takes the fleet's colour
## (white, rental yellow or orange, a company red or blue), with a dark rub
## rail along the bottom, corner posts and a roll-up door at the back.
func _box_truck() -> void:  # 26 ft box truck
	var L := 10.4
	_md_cab(2.45)
	_box(Vector3(0, 0.75, (3.0 + L) * 0.5), Vector3(1.0, 0.3, L - 3.0), TRIM)
	_loft([
		[3.15, 1.0, 3.8, 3.9, 1.3, 1.3, 1.28],
		[L, 1.0, 3.8, 3.9, 1.3, 1.3, 1.28],
	], [_edges(PAINT, STEEL)], PAINT, Color(0.8, 0.8, 0.8, 0.4))
	_wheels([1.2, 7.9], 0.5, 1.2, 0.3)
	_box(Vector3(1.1, 1.0, L + 0.01), Vector3(0.12, 0.2, 0.04), TAIL, true)
	_box(Vector3(-1.1, 1.0, L + 0.01), Vector3(0.12, 0.2, 0.04), TAIL, true)
	for s in [-1.0, 1.0]:
		_box(Vector3(s * 1.302, 1.1, (3.15 + L) * 0.5), Vector3(0.01, 0.16, L - 3.15), DARK)  # rub rail
		_box(Vector3(s * 1.29, 2.45, L - 0.04), Vector3(0.06, 2.9, 0.1), STEEL)  # corner posts
		_box(Vector3(s * 1.29, 2.45, 3.19), Vector3(0.06, 2.9, 0.1), STEEL)
	_box(Vector3(0, 2.4, L + 0.006), Vector3(2.3, 2.6, 0.01), STEEL)  # the roll-up door
	if not _lo:
		for y in [1.6, 2.2, 2.8, 3.4]:
			_box(Vector3(0, y, L + 0.012), Vector3(2.3, 0.03, 0.01), DARK)
		_box(Vector3(0, 0.95, L + 0.15), Vector3(2.2, 0.12, 0.3), DARK)  # step bumper


func _dump_truck() -> void:  # tandem dump on a conventional chassis
	var L := 9.0
	_md_cab(2.5)
	_box(Vector3(0, 0.75, 5.5), Vector3(1.0, 0.3, 6.5), TRIM)
	if _hi:
		_dump_bed(L)
	else:
		_loft([
			[3.3, 1.05, 2.9, 3.0, 1.15, 1.25, 1.25],
			[L - 0.1, 1.05, 2.9, 3.0, 1.15, 1.25, 1.25],
			[L, 1.25, 2.9, 3.0, 1.1, 1.25, 1.25],
		], [_edges(PAINT, TRIM)], PAINT, PAINT)
		_box(Vector3(0, 2.75, 6.2), Vector3(2.3, 0.004, 5.5), DARK)
	_wheels([1.2, 6.2, 7.6], 0.52, 1.25, 0.3)
	_box(Vector3(1.1, 1.2, L + 0.01), Vector3(0.12, 0.2, 0.04), TAIL, true)


## Ultra: a real open dump body (Ox, Rugby): steel sides 1.4 m tall with
## upright stiffeners and a top rail, the headboard with its cab shield
## reaching forward over the cab roof, a tailgate, and the worn floor
## inside, on a long sill over the frame.
func _dump_bed(L: float) -> void:
	_loft([
		[3.3, 1.05, 1.5, 1.6, 1.15, 1.25, 1.25],
		[L - 0.1, 1.05, 1.5, 1.6, 1.15, 1.25, 1.25],
		[L, 1.25, 1.5, 1.6, 1.1, 1.25, 1.25],
	], [_edges(PAINT, TRIM)], PAINT, PAINT)
	var mid := (3.38 + L - 0.08) * 0.5
	var len := L - 0.08 - 3.38
	for s in [-1.0, 1.0]:
		_box(Vector3(s * 1.21, 2.3, mid), Vector3(0.08, 1.4, len), PAINT)
		_box(Vector3(s * 1.22, 3.02, mid), Vector3(0.12, 0.06, len), PAINT)
		var z := 3.9
		while z < L - 0.4:
			_box(Vector3(s * 1.265, 2.3, z), Vector3(0.03, 1.3, 0.08), PAINT)
			z += 0.9
	_box(Vector3(0, 2.3, 3.34), Vector3(2.5, 1.4, 0.08), PAINT)
	_box(Vector3(0, 2.3, L - 0.04), Vector3(2.5, 1.4, 0.08), PAINT)
	_box(Vector3(0, 2.98, 2.98), Vector3(2.0, 0.06, 0.72), PAINT)
	# Inside, the paint is scraped back to dull steel by the loads.
	var worn := Color(0.3, 0.28, 0.26, 0.4)
	_box(Vector3(0, 1.62, mid), Vector3(2.34, 0.04, len), worn)
	for s in [-1.0, 1.0]:
		_box(Vector3(s * 1.166, 2.315, mid), Vector3(0.004, 1.35, len - 0.02), worn)
	_box(Vector3(0, 2.315, 3.386), Vector3(2.32, 1.35, 0.004), worn)
	_box(Vector3(0, 2.315, L - 0.086), Vector3(2.32, 1.35, 0.004), worn)


## A rear-discharge ready-mix truck (Kenworth T880 with a McNeilus drum):
## a white 11 yd drum tilted up toward the back, water tank, rear chutes,
## tridem axles. The cab takes the fleet colour.
func _concrete_mixer() -> void:
	var L := 10.4
	_md_cab(2.5)
	_box(Vector3(0, 0.8, 6.0), Vector3(1.0, 0.3, 7.6), TRIM)
	# The drum: wide in the middle, narrow at both ends, rising to the rear.
	var drum := [[3.4, 1.7, 0.55], [4.3, 1.95, 1.05], [6.4, 2.3, 1.2], [8.6, 2.75, 0.85], [9.6, 3.05, 0.45]]
	var sections := []
	for d in drum:
		var r: float = d[2]
		sections.append([d[0], d[1] - r, d[1] - r * 0.1, d[1] + r, r * 0.7, r, r * 0.7])
	_loft(sections, [_edges(MIXER, MIXER)], MIXER, DARK)
	if not _lo:
		# Spiral fins painted on the drum, the water tank and the chutes.
		for k in [1, 2, 3]:
			var a: Array = drum[k]
			var b: Array = drum[k + 1]
			for f in [0.3, 0.7]:
				var z: float = lerpf(a[0], b[0], f)
				var y: float = lerpf(a[1], b[1], f)
				var r: float = lerpf(a[2], b[2], f) + 0.03
				var band := []
				for dz in [-0.12, 0.12]:
					band.append([z + dz, y - r, y - r * 0.1, y + r, r * 0.7, r, r * 0.7])
				_loft(band, [_edges(PAINT, PAINT)], PAINT, PAINT)
		_cyl(Vector3(0, 2.0, 3.1), Vector3(0, 2.9, 3.1), 0.35, STEEL, 10)
		_beam(Vector3(0, 2.4, 9.7), Vector3(0, 1.6, 10.3), 0.35, TRIM)
		_box(Vector3(0, 1.4, 9.9), Vector3(0.9, 0.5, 0.5), STEEL)
		_box(Vector3(0, 1.15, 10.38), Vector3(0.5, 0.06, 0.6), STEEL)  # the fold-down discharge chute
	_wheels([1.2, 7.0, 8.4], 0.52, 1.25, 0.3)
	_box(Vector3(1.1, 1.0, L - 0.05), Vector3(0.12, 0.2, 0.06), TAIL, true)


func _garbage_truck() -> void:  # rear loader on a Mack LR cab-over
	var L := 9.8
	var hw := 1.3
	_loft([
		[0.0, 0.55, 1.4, 1.5, hw - 0.1, hw - 0.05, hw - 0.1],
		[2.3, 0.55, 1.4, 1.5, hw - 0.05, hw, hw - 0.05],
	], [_edges(WHITE, TRIM)], WHITE, WHITE)
	_loft([
		[0.0, 1.45, 1.5, 1.52, hw - 0.1, hw - 0.1, hw - 0.1],
		[0.25, 1.45, 1.5, 2.8, hw - 0.1, hw - 0.1, hw - 0.12],
		[2.3, 1.45, 1.5, 2.8, hw - 0.05, hw - 0.05, hw - 0.1],
	], [_edges(GLASS, WHITE, WHITE, GLASS), _edges(GLASS, WHITE, WHITE, WHITE)], WHITE, WHITE)
	_loft([
		[2.45, 0.9, 3.55, 3.7, hw, hw, hw - 0.05],
		[L - 1.9, 0.9, 3.55, 3.7, hw, hw, hw - 0.05],
	], [_edges(PAINT, TRIM)], PAINT, PAINT)
	# Hopper: tapers down at the back.
	_loft([
		[L - 1.9, 0.75, 3.3, 3.5, hw, hw, hw - 0.05],
		[L, 0.75, 1.8, 2.3, hw - 0.05, hw - 0.05, hw - 0.1],
	], [_edges(PAINT, TRIM)], PAINT, DARK)
	_wheels([1.0, 6.6, 7.9], 0.52, hw, 0.3)
	_box(Vector3(0, 0.9, 0.0), Vector3(2.2, 0.3, 0.1), TRIM)
	if _hi:
		_refuse_face(hw)
	else:
		_box(Vector3(hw - 0.25, 1.1, -0.02), Vector3(0.3, 0.16, 0.06), HEAD, true)
	_box(Vector3(hw - 0.15, 2.4, L + 0.01), Vector3(0.14, 0.14, 0.04), TAIL, true)
	_box(Vector3(0, 2.86, 1.2), Vector3(0.9, 0.1, 0.2), BEACON_AMBER)


## An automated side loader (Heil Rapid Rail on an Autocar ACX): the same
## low cab, a hopper right behind it with the gripper arm on the curb side
## that tips the cart, and a rounded tailgate. Most towns' home routes now.
func _garbage_side() -> void:
	var L := 9.8
	var hw := 1.3
	_loft([
		[0.0, 0.55, 1.4, 1.5, hw - 0.1, hw - 0.05, hw - 0.1],
		[2.3, 0.55, 1.4, 1.5, hw - 0.05, hw, hw - 0.05],
	], [_edges(WHITE, TRIM)], WHITE, WHITE)
	_loft([
		[0.0, 1.45, 1.5, 1.52, hw - 0.1, hw - 0.1, hw - 0.1],
		[0.25, 1.45, 1.5, 2.8, hw - 0.1, hw - 0.1, hw - 0.12],
		[2.3, 1.45, 1.5, 2.8, hw - 0.05, hw - 0.05, hw - 0.1],
	], [_edges(GLASS, WHITE, WHITE, GLASS), _edges(GLASS, WHITE, WHITE, WHITE)], WHITE, WHITE)
	# Hopper, open on top, then the packer body and a rounded tailgate.
	_loft([
		[2.45, 0.9, 3.4, 3.5, hw, hw, hw - 0.05],
		[3.9, 0.9, 3.4, 3.5, hw, hw, hw - 0.05],
	], [_edges(PAINT, TRIM)], PAINT, PAINT)
	_box(Vector3(0, 3.48, 3.18), Vector3(2.3, 0.01, 1.3), DARK)
	_loft([
		[3.95, 0.9, 3.55, 3.75, hw, hw, hw - 0.08],
		[L - 1.1, 0.9, 3.55, 3.75, hw, hw, hw - 0.08],
		[L - 0.3, 1.0, 3.3, 3.45, hw - 0.05, hw - 0.05, hw - 0.2],
		[L, 1.3, 2.8, 2.95, hw - 0.15, hw - 0.15, hw - 0.4],
	], [_edges(PAINT, TRIM)], PAINT, PAINT)
	# The arm, folded in against the curb side, and its two grabbers.
	_box(Vector3(hw + 0.12, 1.3, 3.2), Vector3(0.22, 0.9, 1.1), TRIM)
	_box(Vector3(hw + 0.2, 1.1, 3.2), Vector3(0.08, 0.5, 0.9), STEEL)
	_wheels([1.0, 6.6, 7.9], 0.52, hw, 0.3)
	_box(Vector3(0, 0.9, 0.0), Vector3(2.2, 0.3, 0.1), TRIM)
	if _hi:
		_refuse_face(hw)
	else:
		_box(Vector3(hw - 0.25, 1.1, -0.02), Vector3(0.3, 0.16, 0.06), HEAD, true)
	_box(Vector3(hw - 0.2, 2.2, L - 0.15), Vector3(0.14, 0.14, 0.04), TAIL, true)
	_box(Vector3(0, 2.86, 1.2), Vector3(0.9, 0.1, 0.2), BEACON_AMBER)


func _fire_engine() -> void:  # custom-cab pumper (Pierce Enforcer)
	var L := 10.4
	var hw := 1.3
	_loft([
		[0.0, 0.45, 1.5, 1.65, hw - 0.1, hw - 0.05, hw - 0.1],
		[3.4, 0.45, 1.5, 1.65, hw - 0.03, hw, hw - 0.03],
	], [_edges(PAINT, TRIM)], PAINT, PAINT)
	_loft([
		[0.05, 1.6, 1.65, 1.66, hw - 0.08, hw - 0.08, hw - 0.08],
		[0.35, 1.6, 1.65, 3.0, hw - 0.08, hw - 0.08, hw - 0.1],
		[3.4, 1.6, 1.65, 3.0, hw - 0.03, hw - 0.03, hw - 0.06],
	], [_edges(GLASS, PAINT, PAINT, GLASS), _edges(WHITE, PAINT, GLASS, WHITE)], PAINT, PAINT)
	_loft([
		[3.45, 0.55, 2.7, 2.85, hw, hw, hw - 0.04],
		[L, 0.55, 2.7, 2.85, hw, hw, hw - 0.04],
	], [_edges(PAINT, TRIM)], PAINT, PAINT)
	_wheels([1.3, 7.4], 0.55, hw, 0.32)
	_box(Vector3(0, 3.06, 1.7), Vector3(2.2, 0.12, 0.3), BEACON_RED)
	_box(Vector3(0, 1.0, -0.06), Vector3(2.4, 0.4, 0.14), CHROME)
	if _hi:
		_pumper_face(hw)
	else:
		_box(Vector3(hw - 0.3, 1.25, -0.02), Vector3(0.36, 0.18, 0.06), HEAD, true)
	_box(Vector3(hw - 0.1, 1.1, L + 0.01), Vector3(0.14, 0.2, 0.04), TAIL, true)
	if _lo:
		return
	# Ladders on the roof rack and chrome compartment doors down the sides.
	for x in [-0.55, 0.55]:
		_box(Vector3(x, 3.0, 6.8), Vector3(0.45, 0.08, 6.4), STEEL)
	for s in [-1.0, 1.0]:
		for i in 5:
			_box(Vector3(s * (hw + 0.004), 1.65, 4.0 + i * 0.85 + (1.6 if i > 2 else 0.0)), Vector3(0.006, 1.6, 0.04), CHROME)
	for x in [-1.2, 1.2]:
		_box(Vector3(x, 2.9, L - 0.05), Vector3(0.12, 0.14, 0.08), BEACON_RED)


## Ultra: a low-cab-forward refuse truck's face (Mack LR, Peterbilt 520):
## the black grille with its chrome bars under the split windshield,
## headlamps in dark housings at the corners with amber markers above,
## west-coast mirrors on arms and the convex corner mirrors drivers use to
## see the curb right below the nose. Layers stand 6 mm apart.
func _refuse_face(hw: float) -> void:
	_box(Vector3(0, 1.22, -0.006), Vector3(1.1, 0.42, 0.012), TRIM)
	for i in 4:
		_box(Vector3(0, 1.07 + i * 0.1, -0.012), Vector3(1.0, 0.03, 0.012), CHROME)
	_box(Vector3(hw - 0.3, 1.2, -0.006), Vector3(0.34, 0.2, 0.012), TRIM, true)
	_box(Vector3(hw - 0.3, 1.2, -0.012), Vector3(0.28, 0.13, 0.012), HEAD, true)
	_box(Vector3(hw - 0.3, 1.36, -0.006), Vector3(0.22, 0.06, 0.012), Color(0.95, 0.55, 0.05, 0.5), true)
	_lcf_glass(Vector3(0, 1.52, 0.0), Vector3(0, 2.8, 0.25), hw - 0.1)
	_lcf_mirrors(hw, 2.15, 0.45)


## Ultra: a custom fire cab's face (Pierce Enforcer, E-One): a chrome
## grille with dark slots, quad headlamps in black housings either side,
## red warning lights above them that flash with the siren, and mirrors.
func _pumper_face(hw: float) -> void:
	_box(Vector3(0, 1.36, -0.006), Vector3(1.0, 0.44, 0.012), CHROME)
	for i in 5:
		_box(Vector3(0, 1.2 + i * 0.08, -0.012), Vector3(0.9, 0.035, 0.012), TRIM)
	_box(Vector3(hw - 0.32, 1.38, -0.006), Vector3(0.44, 0.22, 0.012), TRIM, true)
	for dx in [-0.1, 0.1]:
		_box(Vector3(hw - 0.32 + dx, 1.38, -0.012), Vector3(0.16, 0.15, 0.012), HEAD, true)
	_box(Vector3(hw - 0.32, 1.56, -0.006), Vector3(0.3, 0.07, 0.012), BEACON_RED, true)
	_lcf_glass(Vector3(0, 1.66, 0.05), Vector3(0, 3.0, 0.35), hw - 0.08)
	_lcf_mirrors(hw, 2.45, 0.6)


## The split windshield's centre post and a pair of parked wipers on a
## cab-over's face, from its foot `a` to its top `b`, 8 mm out from the
## glass.
func _lcf_glass(a: Vector3, b: Vector3, half: float) -> void:
	var up := (b - a).normalized()
	var out := Vector3(0, up.z, -up.y) * 0.008
	_beam(a + out, b + out, 0.06, TRIM)
	for x in [-half * 0.5, half * 0.5]:
		_beam(a + out + up * 0.06 + Vector3(x - half * 0.4, 0, 0),
			a + out + up * 0.06 + Vector3(x + half * 0.4, 0, 0), 0.025, TRIM)


## West-coast mirrors on arms out from both doors, and a convex mirror
## on a stalk at each front corner.
func _lcf_mirrors(hw: float, y: float, z: float) -> void:
	for s in [-1.0, 1.0]:
		_box(Vector3(s * (hw + 0.14), y + 0.2, z), Vector3(0.28, 0.04, 0.04), TRIM)
		_box(Vector3(s * (hw + 0.3), y, z), Vector3(0.07, 0.5, 0.2), TRIM)
		_beam(Vector3(s * (hw - 0.12), y - 0.35, 0.02), Vector3(s * (hw - 0.05), y - 0.3, -0.25), 0.03, TRIM)
		_cyl(Vector3(s * (hw - 0.05), y - 0.3, -0.25), Vector3(s * (hw - 0.05), y - 0.3, -0.3), 0.09, TRIM, 10)


## A rural water tender (Pierce or KME on a commercial chassis): a 3,000
## gal elliptical tank, a portable drop tank racked on the side and a dump
## chute at the back. Volunteer departments without hydrants run them.
func _fire_tender() -> void:
	var L := 10.4
	_md_cab(2.5)
	_box(Vector3(0, 0.75, 6.7), Vector3(1.0, 0.3, 7.2), TRIM)
	_loft([
		[3.2, 1.0, 2.0, 3.0, 0.9, 1.25, 0.95],
		[L - 0.4, 1.0, 2.0, 3.0, 0.9, 1.25, 0.95],
		[L - 0.1, 1.1, 2.0, 2.9, 0.8, 1.15, 0.85],
	], [_edges(PAINT, PAINT)], PAINT, PAINT)
	_wheels([1.2, 7.2, 8.5], 0.52, 1.25, 0.3)
	_box(Vector3(0, 2.84, 1.8), Vector3(2.0, 0.12, 0.3), BEACON_RED)
	_box(Vector3(1.1, 1.0, L + 0.01), Vector3(0.12, 0.2, 0.04), TAIL, true)
	_box(Vector3(-1.1, 1.0, L + 0.01), Vector3(0.12, 0.2, 0.04), TAIL, true)
	if not _lo:
		for s in [-1.0, 1.0]:
			_box(Vector3(s * 1.255, 1.55, 6.5), Vector3(0.006, 0.12, 6.4), WHITE)
		_box(Vector3(-1.32, 2.1, 6.0), Vector3(0.12, 0.7, 2.6), STEEL)  # folded drop tank
		_box(Vector3(0, 1.1, L + 0.15), Vector3(0.5, 0.3, 0.3), CHROME)  # dump chute
		for x in [-1.15, 1.15]:
			_box(Vector3(x, 2.85, L - 0.2), Vector3(0.12, 0.14, 0.08), BEACON_RED)


func _school_bus() -> void:  # Type C conventional (Blue Bird Vision, IC CE)
	var L := 12.2
	var hw := 1.22
	_loft([
		[0.0, 0.6, 1.15, 1.35, hw - 0.35, hw - 0.3, hw - 0.45],
		[0.25, 0.55, 1.35, 1.5, hw - 0.25, hw - 0.2, hw - 0.35],
		[1.55, 0.55, 1.55, 1.65, hw - 0.2, hw - 0.15, hw - 0.2],
	], [_edges(PAINT, TRIM)], PAINT, PAINT)
	_loft([
		[1.6, 0.45, 2.9, 3.05, hw, hw, hw - 0.12],
		[L, 0.45, 2.9, 3.05, hw, hw, hw - 0.12],
	], [_edges(PAINT, TRIM, PAINT, Color(0.95, 0.94, 0.9, 0.4))], PAINT, PAINT)
	_box(Vector3(0, 2.25, 1.59), Vector3(2.2, 0.85, 0.02), GLASS)
	# Window band, black rub rails and the warning lights.
	for s in [-1.0, 1.0]:
		_box(Vector3(s * (hw + 0.004), 2.15, 6.6), Vector3(0.006, 0.7, 9.6), GLASS)
		for y in [0.85, 1.25, 1.65]:
			_box(Vector3(s * (hw + 0.006), y, 6.9), Vector3(0.006, 0.07, 10.6), TRIM)
		if not _lo:
			for i in 12:
				_box(Vector3(s * (hw + 0.012), 2.15, 2.25 + i * 0.85), Vector3(0.006, 0.72, 0.09), PAINT)
	_wheels([1.0, 8.9], 0.5, hw, 0.3)
	for x in [-0.9, 0.9]:
		_box(Vector3(x, 2.85, 1.58), Vector3(0.16, 0.16, 0.06), BEACON_AMBER)
		_box(Vector3(x, 2.85, L + 0.02), Vector3(0.16, 0.16, 0.06), BEACON_RED)
	_box(Vector3(hw - 0.35, 1.2, 0.06), Vector3(0.28, 0.16, 0.1), HEAD, true)
	_box(Vector3(hw - 0.2, 1.0, L + 0.01), Vector3(0.18, 0.18, 0.04), TAIL, true)
	if not _lo:
		_box(Vector3(0, 1.0, 0.02), Vector3(0.9, 0.5, 0.06), CHROME)
		_box(Vector3(-hw - 0.3, 1.9, 2.2), Vector3(0.45, 0.45, 0.03), Color(0.75, 0.05, 0.05, 0.4))


func _city_bus() -> void:  # 40 ft low-floor transit bus (Gillig, New Flyer)
	var L := 12.2
	var hw := 1.3
	_loft([
		[0.0, 0.3, 3.0, 3.1, hw - 0.08, hw - 0.04, hw - 0.12],
		[0.25, 0.3, 3.0, 3.1, hw, hw, hw - 0.08],
		[L - 0.15, 0.3, 3.0, 3.1, hw, hw, hw - 0.08],
		[L, 0.35, 2.95, 3.05, hw - 0.06, hw - 0.04, hw - 0.12],
	], [_edges(PAINT, TRIM)], PAINT, PAINT)
	_box(Vector3(0, 1.85, -0.004), Vector3(2.4, 1.7, 0.02), GLASS)
	_box(Vector3(0, 3.18, 6.0), Vector3(1.8, 0.2, 3.0), PAINT)
	for s in [-1.0, 1.0]:
		_box(Vector3(s * (hw + 0.004), 1.9, 6.2), Vector3(0.006, 1.0, 11.2), GLASS)
		_box(Vector3(s * (hw + 0.006), 0.85, 6.1), Vector3(0.006, 0.25, 11.6), Color(0.1, 0.35, 0.55, 0.4))
	_wheels([2.4, 9.2], 0.5, hw, 0.3)
	_box(Vector3(hw - 0.25, 0.75, -0.02), Vector3(0.3, 0.16, 0.06), HEAD, true)
	_box(Vector3(hw - 0.15, 1.1, L + 0.01), Vector3(0.14, 0.3, 0.04), TAIL, true)
	_box(Vector3(0, 2.85, -0.03), Vector3(1.8, 0.22, 0.03), Color(1.0, 0.6, 0.1, 0.5))
	if _lo:
		return
	# Window pillars down both sides, the two curb-side doors (glass leaves
	# in dark frames) and a folded bike rack on the front, as on most US
	# transit buses.
	for s in [-1.0, 1.0]:
		for i in 8:
			if s > 0.0 and i == 4:
				continue  # the back door
			_box(Vector3(s * (hw + 0.012), 1.9, 1.8 + i * 1.3), Vector3(0.006, 1.0, 0.1), PAINT)
	for z in [0.95, 6.9]:
		_box(Vector3(hw + 0.016, 1.45, z), Vector3(0.006, 2.3, 1.2), DARK)
		_box(Vector3(hw + 0.022, 1.5, z - 0.28), Vector3(0.006, 2.0, 0.5), GLASS)
		_box(Vector3(hw + 0.022, 1.5, z + 0.28), Vector3(0.006, 2.0, 0.5), GLASS)
	for x in [-0.6, 0.6]:
		_box(Vector3(x, 0.75, -0.12), Vector3(0.05, 0.5, 0.05), STEEL)
	_box(Vector3(0, 0.98, -0.16), Vector3(1.3, 0.05, 0.12), STEEL)


## A 45 ft intercity motorcoach (MCI J4500, Prevost H3-45): high deck over
## luggage bays, a tag axle behind the drive axle, and the door up front on
## the curb side.
func _coach() -> void:
	var L := 13.8
	var hw := 1.29
	_loft([
		[0.0, 0.45, 3.0, 3.3, hw - 0.12, hw - 0.1, hw - 0.3],
		[0.5, 0.4, 3.25, 3.45, hw - 0.02, hw, hw - 0.12],
		[L - 0.3, 0.4, 3.25, 3.45, hw - 0.02, hw, hw - 0.12],
		[L, 0.45, 3.15, 3.35, hw - 0.1, hw - 0.08, hw - 0.22],
	], [_edges(PAINT, TRIM)], PAINT, PAINT)
	# A tall two-piece windshield raked back over the driver.
	_box(Vector3(0, 2.15, 0.02), Vector3(2.3, 1.75, 0.02), GLASS)
	for s in [-1.0, 1.0]:
		# Passenger windows sit high, above the luggage bays.
		_box(Vector3(s * (hw + 0.004), 2.45, 7.6), Vector3(0.006, 1.05, 10.6), GLASS)
		_box(Vector3(s * (hw + 0.006), 1.55, 7.0), Vector3(0.006, 0.12, 12.4), Color(0.1, 0.25, 0.5, 0.4))
		if not _lo:
			for i in 5:  # luggage bay doors between the axles
				_box(Vector3(s * (hw + 0.006), 0.95, 3.6 + i * 1.25), Vector3(0.006, 0.8, 0.03), TRIM)
	_box(Vector3(hw + 0.006, 1.75, 1.3), Vector3(0.006, 2.4, 0.9), GLASS)  # curb-side door
	_wheels([2.2, 10.2, 11.6], 0.52, hw, 0.3)
	for x in [-1.0, 1.0]:
		_box(Vector3(x * (hw - 0.3), 0.85, -0.02), Vector3(0.36, 0.16, 0.06), HEAD, true)
		_box(Vector3(x * (hw - 0.15), 1.3, L + 0.01), Vector3(0.14, 0.4, 0.04), TAIL, true)
	_box(Vector3(0, 3.1, -0.03), Vector3(1.8, 0.2, 0.03), Color(1.0, 0.6, 0.1, 0.5))  # destination sign
	if not _lo:
		for x in [-1.0, 1.0]:
			_box(Vector3(x * (hw + 0.25), 2.3, 0.4), Vector3(0.08, 0.45, 0.2), TRIM)  # mirrors on long arms


# --- Semis ------------------------------------------------------------------

## A conventional Class 8 tractor (Freightliner Cascadia, Peterbilt 579).
func _tractor_unit(sleeper: bool) -> void:
	var hw := 1.3
	var cab_end := 3.4
	_loft([
		[0.0, 0.55, 1.35, 1.5, hw - 0.25, hw - 0.2, hw - 0.4],
		[0.3, 0.5, 1.55, 1.75, hw - 0.12, hw - 0.1, hw - 0.3],
		[1.9, 0.6, 1.8, 1.95, hw - 0.1, hw - 0.05, hw - 0.15],
		[cab_end, 0.6, 1.8, 1.95, hw - 0.1, hw - 0.05, hw - 0.15],
	], [_edges(PAINT, TRIM)], PAINT, PAINT)
	_loft([
		[1.95, 1.9, 1.93, 1.94, hw - 0.12, hw - 0.12, hw - 0.14],
		[2.5, 1.9, 1.98, 3.0, hw - 0.12, hw - 0.12, hw - 0.2],
		[cab_end, 1.9, 1.98, 3.0, hw - 0.12, hw - 0.12, hw - 0.2],
	], [_edges(GLASS, PAINT, PAINT, GLASS), _edges(PAINT, PAINT, GLASS, PAINT)], PAINT, PAINT)
	var back := cab_end
	if sleeper:
		back = 5.2
		_loft([
			[cab_end, 0.75, 3.6, 3.95, hw - 0.1, hw - 0.08, hw - 0.3],
			[back, 0.75, 3.6, 3.95, hw - 0.1, hw - 0.08, hw - 0.3],
		], [_edges(PAINT, TRIM)], PAINT, PAINT)
	else:
		_box(Vector3(0, 3.2, cab_end - 0.4), Vector3(2.2, 0.4, 0.8), PAINT)
	# Frame, fuel tanks, fifth wheel, stacks.
	_box(Vector3(0, 0.85, (back + 7.4) * 0.5), Vector3(1.0, 0.3, 7.4 - back), TRIM)
	_box(Vector3(0, 1.15, back + 1.4), Vector3(1.6, 0.12, 1.1), TRIM)
	for s in [-1.0, 1.0]:
		_cyl(Vector3(s * 1.05, 0.85, cab_end - 0.4), Vector3(s * 1.05, 0.85, cab_end + 0.6), 0.32, CHROME)
		if not _lo:
			_cyl(Vector3(s * 1.15, 1.7, back + 0.05), Vector3(s * 1.15, 4.0, back + 0.05), 0.09, CHROME)
	_wheels([1.3], 0.52, hw, 0.32)
	_wheels([back + 1.0, back + 2.3], 0.52, hw, 0.6)
	_box(Vector3(0, 1.2, 0.02), Vector3(1.1, 0.75, 0.06), CHROME)
	_box(Vector3(0, 0.75, -0.06), Vector3(2.4, 0.25, 0.2), CHROME if not _lo else TRIM)
	if _hi:
		_heavy_face(hw - 0.42, 1.2, 1.1, 1.2, 0.75)
	else:
		_box(Vector3(hw - 0.45, 1.25, 0.1), Vector3(0.36, 0.16, 0.12), HEAD, true)
	if not _lo:
		for s in [-1.0, 1.0]:
			_box(Vector3(s * (hw + 0.14), 2.35, 2.0), Vector3(0.06, 0.5, 0.14), TRIM)


func _tractor_sleeper() -> void:
	_tractor_unit(true)


func _tractor_day() -> void:
	_tractor_unit(false)


## 53 ft dry van (or other trailers): origin at the trailer's front.
func _trailer_base(L: float, wheels_at: Array) -> void:
	_wheels(wheels_at, 0.52, 1.3, 0.6)
	_box(Vector3(1.1, 1.05, L + 0.01), Vector3(0.14, 0.16, 0.04), TAIL, true)
	_box(Vector3(-1.1, 1.05, L + 0.01), Vector3(0.14, 0.16, 0.04), TAIL, true)
	if not _lo:
		_box(Vector3(0, 0.6, L - 0.3), Vector3(2.3, 0.12, 0.12), TRIM)
		for s in [-1.0, 1.0]:
			_box(Vector3(s * 0.9, 0.7, 4.0), Vector3(0.15, 0.7, 0.15), TRIM)
	if _hi:
		# Ultra: red and white tape across the underride guard (FMVSS 108
		# asks for it on every trailer 80 in wide), and mud flaps behind
		# the rear axle.
		var x := -1.15
		var k := 0
		while x < 1.15:
			var w := minf(0.3, 1.15 - x)
			_box(Vector3(x + w * 0.5, 0.6, L - 0.237), Vector3(w, 0.06, 0.006), WHITE if k % 2 == 0 else TAPE_RED)
			x += w
			k += 1
		for s in [-1.0, 1.0]:
			_box(Vector3(s * 1.0, 0.45, float(wheels_at[wheels_at.size() - 1]) + 0.68), Vector3(0.6, 0.6, 0.015), TIRE)


func _trailer_box() -> void:
	var L := 16.15
	_loft([
		[0.0, 1.25, 4.0, 4.1, 1.3, 1.3, 1.28],
		[L, 1.25, 4.0, 4.1, 1.3, 1.3, 1.28],
	], [_edges(WHITE, STEEL)], WHITE, Color(0.85, 0.85, 0.85, 0.4))
	if _hi:
		_trailer_box_tape(L)
	elif not _lo:
		for s in [-1.0, 1.0]:
			_box(Vector3(s * 1.304, 1.3, L * 0.5), Vector3(0.006, 0.05, L), Color(0.85, 0.2, 0.05, 0.4))
	if not _lo:
		_box(Vector3(0, 2.6, L + 0.01), Vector3(0.03, 2.6, 0.01), STEEL)
	_trailer_base(L, [13.9, 15.15])


## Ultra: the conspicuity tape a dry van carries by law (DOT-C2, 7 in red
## and 11 in white) along both sills and across the rear, white corner
## marks up top, and the four lock rods on the swing doors.
func _trailer_box_tape(L: float) -> void:
	for s in [-1.0, 1.0]:
		var z := 0.3
		var k := 0
		while z < L - 0.3:
			var seg := 0.18 if k % 2 == 0 else 0.28
			seg = minf(seg, L - 0.3 - z)
			_box(Vector3(s * 1.304, 1.32, z + seg * 0.5), Vector3(0.006, 0.05, seg), TAPE_RED if k % 2 == 0 else WHITE)
			z += seg
			k += 1
		# Upper rear corners: an inverted L of white.
		_box(Vector3(s * 1.1, 3.93, L + 0.022), Vector3(0.3, 0.05, 0.006), WHITE)
		_box(Vector3(s * 1.225, 3.75, L + 0.022), Vector3(0.05, 0.3, 0.006), WHITE)
	var x := -1.2
	var k2 := 0
	while x < 1.2:
		var w := minf(0.18 if k2 % 2 == 0 else 0.28, 1.2 - x)
		_box(Vector3(x + w * 0.5, 1.36, L + 0.022), Vector3(w, 0.05, 0.006), TAPE_RED if k2 % 2 == 0 else WHITE)
		x += w
		k2 += 1
	for rx in [-0.9, -0.35, 0.35, 0.9]:
		_box(Vector3(rx, 2.68, L + 0.03), Vector3(0.03, 2.5, 0.03), STEEL)


## A 53 ft USPS contract trailer: white with the blue and red stripe.
func _trailer_usps() -> void:
	_trailer_box()
	for s in [-1.0, 1.0]:
		_box(Vector3(s * 1.305, 3.2, 8.0), Vector3(0.006, 0.22, 14.0), USPS_BLUE)
		_box(Vector3(s * 1.305, 2.98, 8.0), Vector3(0.006, 0.1, 14.0), USPS_RED)
		if not _lo:
			_box(Vector3(s * 1.306, 2.3, 3.0), Vector3(0.006, 0.9, 1.6), USPS_BLUE)


func _trailer_hopper() -> void:  # 42 ft grain hopper (Wilson, Timpte)
	var L := 15.5
	_loft([
		[0.0, 1.5, 2.6, 3.1, 1.25, 1.3, 1.3],
		[L, 1.5, 2.6, 3.1, 1.25, 1.3, 1.3],
	], [_edges(ALUM, ALUM)], ALUM, ALUM)
	# Tarp over the grain, and the two hopper bins underneath.
	_box(Vector3(0, 3.14, L * 0.5), Vector3(2.5, 0.08, L - 0.2), Color(0.14, 0.15, 0.16, 0.4))
	for z in [5.0, 9.8]:
		_loft([
			[z - 2.0, 1.5, 1.5, 1.52, 1.2, 1.2, 1.2],
			[z, 0.75, 1.2, 1.5, 0.3, 0.6, 1.2],
			[z + 2.0, 1.5, 1.5, 1.52, 1.2, 1.2, 1.2],
		], [_edges(ALUM, ALUM)], ALUM, ALUM)
	_trailer_base(L, [13.4, 14.65])


func _trailer_tank() -> void:  # stainless tanker (milk, fuel)
	var L := 14.6
	_cyl(Vector3(0, 2.25, 0.3), Vector3(0, 2.25, L - 0.3), 1.0, CHROME, 14)
	_box(Vector3(0, 1.3, L * 0.5), Vector3(1.0, 0.25, L - 1.0), TRIM)
	if not _lo:
		_box(Vector3(0, 3.3, L * 0.5), Vector3(0.5, 0.08, L - 2.0), STEEL)
	_trailer_base(L, [12.4, 13.65])


func _trailer_flat() -> void:  # 48 ft flatbed with steel coils on cradles
	var L := 14.6
	_box(Vector3(0, 1.35, L * 0.5), Vector3(2.6, 0.2, L), STEEL)
	_box(Vector3(0, 1.5, 0.15), Vector3(2.5, 0.12, 0.3), TRIM)
	for i in 5:
		var z := 2.0 + i * 2.5
		_cyl(Vector3(-0.9, 2.15, z), Vector3(0.9, 2.15, z), 0.7, COIL, 12)
		if not _lo:
			_box(Vector3(0, 1.55, z), Vector3(1.6, 0.2, 1.3), WOOD_DARK)
			_box(Vector3(0, 2.15, z), Vector3(1.84, 1.44, 0.04), STRAP)
	_trailer_base(L, [12.4, 13.65])


## A 48 ft flatbed running empty: bare deck, the load's dunnage stacked
## up front and the straps rolled at the headboard, as drivers carry them.
func _trailer_flat_empty() -> void:
	var L := 14.6
	_box(Vector3(0, 1.35, L * 0.5), Vector3(2.6, 0.2, L), STEEL)
	_box(Vector3(0, 1.5, 0.15), Vector3(2.5, 0.12, 0.3), TRIM)
	if not _lo:
		for i in 3:
			_box(Vector3(0, 1.5 + i * 0.1, 0.9), Vector3(2.3, 0.09, 0.12), WOOD_DARK)
		for x in [-0.8, -0.4, 0.4, 0.8]:
			_cyl(Vector3(x - 0.1, 1.58, 0.45), Vector3(x + 0.1, 1.58, 0.45), 0.13, STRAP, 8)
	_trailer_base(L, [12.4, 13.65])


## A 48 ft flatbed of sawmill lumber: banded units two high on dunnage,
## pale pine ends showing, strapped down (benchmark: mill loads on I-69).
func _trailer_lumber() -> void:
	var L := 14.6
	_box(Vector3(0, 1.35, L * 0.5), Vector3(2.6, 0.2, L), STEEL)
	_box(Vector3(0, 1.5, 0.15), Vector3(2.5, 0.12, 0.3), TRIM)
	var pine := Color(0.80, 0.71, 0.55, 0.4)
	var ends := Color(0.93, 0.83, 0.62, 0.4)
	for row in 2:
		var y0 := 1.5 + row * 1.12
		for i in 3:
			var z0 := 0.5 + i * 4.75
			_box(Vector3(0, y0 + 0.05, z0 + 2.2), Vector3(2.3, 0.1, 0.12), WOOD_DARK)
			_box(Vector3(0, y0 + 0.55, z0 + 2.2), Vector3(2.4, 0.9, 4.5), pine)
			if not _lo:
				_box(Vector3(0, y0 + 0.55, z0 - 0.06), Vector3(2.36, 0.86, 0.01), ends)
				_box(Vector3(0, y0 + 0.55, z0 + 4.46), Vector3(2.36, 0.86, 0.01), ends)
				for k in 3:
					_box(Vector3(0, y0 + 0.55, z0 + 0.7 + k * 1.5), Vector3(2.42, 0.92, 0.04), STRAP if row == 1 else STEEL)
	_trailer_base(L, [12.4, 13.65])


## A log trailer: skeletal frame, steel bunks with stakes, and a pyramid of
## 40 ft logs with pale cut ends (benchmark: Midwest hardwood haulers).
func _trailer_logs() -> void:
	var L := 14.6
	_box(Vector3(0, 1.3, L * 0.5), Vector3(0.9, 0.3, L), TRIM)
	var bunks := [1.2, 5.0, 9.0, 13.0]
	for z in bunks:
		_box(Vector3(0, 1.55, z), Vector3(2.6, 0.2, 0.25), TRIM)
		for x in [-1.22, 1.22]:
			_box(Vector3(x, 2.5, z), Vector3(0.12, 1.9, 0.12), TRIM)
	if _lo:
		_box(Vector3(0, 2.4, L * 0.5), Vector3(2.3, 1.4, 13.2), BARK)
		_box(Vector3(0, 2.4, L * 0.5 - 6.62), Vector3(2.2, 1.3, 0.02), WOOD_END)
		_box(Vector3(0, 2.4, L * 0.5 + 6.62), Vector3(2.2, 1.3, 0.02), WOOD_END)
	else:
		# Rows from the bottom: 5, 4, 3 logs, nested in the gaps below.
		var y := 1.65
		for row in [5, 4, 3]:
			for i in row:
				var r: float = 0.2 + 0.035 * fmod(i * 3.7 + row * 1.3, 2.0)
				var x: float = (i - (row - 1) * 0.5) * 0.47
				var z0: float = 0.75 + 0.35 * fmod(i * 1.7 + row, 1.0)
				var z1: float = z0 + 12.9 + 0.3 * fmod(i * 2.3, 1.0)
				_cyl(Vector3(x, y + r, z0), Vector3(x, y + r, z1), r, BARK, 7)
				_disc(Vector3(x, y + r, z0 - 0.01), Vector3(0, 0, -1), r * 0.92, WOOD_END)
				_disc(Vector3(x, y + r, z1 + 0.01), Vector3(0, 0, 1), r * 0.92, WOOD_END)
			y += 0.4
		for z in bunks:
			_box(Vector3(0, y + 0.02, z), Vector3(1.6, 0.03, 0.06), STRAP)
	_trailer_base(L, [12.4, 13.65])


## An end-dump trailer (half-round aluminium tub) heaped with iron ore.
func _trailer_end_dump() -> void:
	var L := 12.8
	_loft([
		[0.0, 1.35, 2.6, 3.5, 0.8, 1.25, 1.25],
		[L - 0.3, 1.35, 2.6, 3.5, 0.8, 1.25, 1.25],
		[L, 1.6, 2.7, 3.5, 0.75, 1.2, 1.2],
	], [_edges(ALUM, ALUM)], ALUM, ALUM)
	# The load heaps up above the rim in the middle.
	_loft([
		[0.4, 3.3, 3.45, 3.5, 1.15, 1.18, 1.0],
		[3.0, 3.3, 3.6, 3.95, 1.15, 1.18, 0.6],
		[L - 3.0, 3.3, 3.6, 3.95, 1.15, 1.18, 0.6],
		[L - 0.6, 3.3, 3.45, 3.5, 1.1, 1.13, 1.0],
	], [_edges(ORE, ORE)], ORE, ORE)
	_box(Vector3(0, 1.2, L * 0.5), Vector3(1.0, 0.25, L), TRIM)
	_trailer_base(L, [10.6, 11.85])


## A 53 ft aluminium "pot belly" livestock trailer (Wilson Silverstar):
## raised decks over the kingpin and the axles, a deep drop belly between,
## and rows of air slots down the sides where the cattle look out.
func _trailer_livestock() -> void:
	var L := 16.15
	_loft([
		[0.0, 1.35, 4.0, 4.1, 1.3, 1.3, 1.28],
		[3.4, 1.35, 4.0, 4.1, 1.3, 1.3, 1.28],
		[3.9, 0.55, 4.0, 4.1, 1.3, 1.3, 1.28],
		[11.3, 0.55, 4.0, 4.1, 1.3, 1.3, 1.28],
		[11.8, 1.35, 4.0, 4.1, 1.3, 1.3, 1.28],
		[L, 1.35, 4.0, 4.1, 1.3, 1.3, 1.28],
	], [_edges(ALUM, ALUM)], ALUM, ALUM)
	var slot := Color(0.07, 0.07, 0.07, 0.4)
	for s in [-1.0, 1.0]:
		if _lo:
			_box(Vector3(s * 1.302, 2.9, L * 0.5), Vector3(0.006, 1.0, L - 1.0), Color(0.3, 0.3, 0.3, 0.4))
			continue
		# Upper deck slots run the full length; the belly gets lower rows too.
		for y in [3.6, 3.3, 3.0, 2.7, 2.4]:
			for i in 12:
				_box(Vector3(s * 1.302, y, 0.9 + i * 1.22), Vector3(0.006, 0.09, 0.95), slot)
		for y in [1.8, 1.5, 1.2]:
			for i in 6:
				_box(Vector3(s * 1.302, y, 4.6 + i * 1.12), Vector3(0.006, 0.09, 0.85), slot)
	if not _lo:
		# Rear swing gates and a nose vent.
		_box(Vector3(0, 2.75, L + 0.01), Vector3(0.04, 2.7, 0.01), STEEL)
		_box(Vector3(0, 3.6, -0.01), Vector3(1.6, 0.4, 0.01), slot)
	_trailer_base(L, [13.9, 15.15])


# --- Farm -------------------------------------------------------------------

func _tractor() -> void:  # John Deere 8R row-crop tractor
	var hw := 1.0
	_loft([
		[0.0, 0.85, 1.75, 1.9, 0.45, 0.48, 0.42],
		[2.6, 0.85, 2.0, 2.2, 0.5, 0.52, 0.46],
	], [_edges(PAINT, TRIM)], PAINT, TRIM)
	_box(Vector3(0, 1.1, 3.5), Vector3(1.3, 0.8, 1.8), TRIM)
	# Cab: glass all round under a painted roof.
	_box(Vector3(0, 2.7, 3.6), Vector3(1.5, 1.3, 1.6), GLASS)
	_box(Vector3(0, 3.38, 3.6), Vector3(1.7, 0.12, 1.8), PAINT)
	_box(Vector3(0, 3.48, 3.2), Vector3(0.12, 0.1, 0.12), BEACON_AMBER)
	_box(Vector3(0, 3.48, 4.0), Vector3(0.12, 0.1, 0.12), BEACON_AMBER)
	_cyl(Vector3(0.35, 2.0, 1.9), Vector3(0.35, 3.4, 1.9), 0.07, TRIM)
	var rim := Color(0.95, 0.75, 0.05, 0.4)
	if _hi:
		_tractor_hi(hw, rim)
	else:
		_wheel(Vector3(-hw, 0.0, 1.0), 0.62, 0.45, rim)
		_wheel(Vector3(hw, 0.0, 1.0), 0.62, 0.45, rim)
		_wheel(Vector3(-hw - 0.15, 0.0, 4.2), 1.0, 0.6, rim)
		_wheel(Vector3(hw + 0.15, 0.0, 4.2), 1.0, 0.6, rim)
		_box(Vector3(0, 1.4, 0.04), Vector3(0.6, 0.12, 0.1), HEAD, true)
	_box(Vector3(0, 0.75, 5.4), Vector3(0.6, 0.15, 0.4), TRIM)


## Ultra: what makes a row-crop tractor read as one (JD 8R, Case IH
## Magnum): lugged ag tyres on dished rims instead of car wheels, fenders
## arching over the rears, a four-post cab, the grille and lamps on the
## nose, a stack of suitcase weights out front, steps and a grab rail up to
## the door, and the orange slow-moving-vehicle triangle every tractor on
## an Indiana road must carry (IC 9-21-9, ASABE S276).
func _tractor_hi(hw: float, rim: Color) -> void:
	for s in [-1.0, 1.0]:
		_ag_wheel(Vector3(s * hw, 0.0, 1.0), 0.62, 0.45, rim)
		_ag_wheel(Vector3(s * (hw + 0.15), 0.0, 4.2), 1.0, 0.6, rim)
		_fender(Vector3(s * (hw + 0.15), 1.0, 4.2), 1.1, 0.72)
		# Cab posts at the four corners.
		for z in [2.8, 4.4]:
			_box(Vector3(s * 0.75, 2.7, z), Vector3(0.08, 1.3, 0.08), TRIM)
	_box(Vector3(0, 1.4, -0.006), Vector3(0.72, 0.8, 0.012), TRIM)
	for i in 6:
		_box(Vector3(0, 1.08 + i * 0.12, -0.012), Vector3(0.66, 0.025, 0.012), PAINT)
	for x in [-0.24, 0.24]:
		_box(Vector3(x, 1.68, -0.018), Vector3(0.18, 0.08, 0.012), HEAD)
	# Suitcase weights on the front bracket.
	_box(Vector3(0, 0.62, -0.08), Vector3(0.5, 0.18, 0.16), TRIM)
	for i in 6:
		_box(Vector3(-0.42 + i * 0.168, 0.7, -0.3), Vector3(0.15, 0.42, 0.3), TRIM)
	# Steps and the grab rail on the left, up to the door.
	for y in [0.75, 1.15, 1.55]:
		_box(Vector3(-0.85, y, 2.85), Vector3(0.3, 0.04, 0.22), STEEL)
	_beam(Vector3(-0.8, 1.2, 2.72), Vector3(-0.8, 2.9, 2.72), 0.04, STEEL)
	# Slow-moving-vehicle emblem on the back of the cab: a red-bordered
	# fluorescent orange triangle, point up.
	var o := Vector3(0, 2.35, 4.45)
	_tri(o + Vector3(-0.21, -0.18, 0), o + Vector3(0.21, -0.18, 0), o + Vector3(0, 0.18, 0), TAPE_RED, o - Vector3(0, 0, 1))
	o.z += 0.006
	_tri(o + Vector3(-0.15, -0.14, 0), o + Vector3(0.15, -0.14, 0), o + Vector3(0, 0.12, 0), Color(1.0, 0.38, 0.04, 0.4), o - Vector3(0, 0, 1))


## A farm tyre on a dished steel rim: deep sidewall, the rim as a plain
## dish with its hub, and chevron lugs round the tread.
func _ag_wheel(c: Vector3, r: float, w: float, rim: Color) -> void:
	var ax := Vector3(1, 0, 0)
	var mid := Vector3(c.x, r, c.z)
	_cyl(mid - ax * w * 0.5, mid + ax * w * 0.5, r - 0.03, TIRE, 24)
	for side in [-1.0, 1.0]:
		var face: Vector3 = mid + ax * side * (w * 0.5 + 0.008)
		_disc(face, ax * side, r * 0.62, rim)
		_disc(face + ax * side * 0.006, ax * side, r * 0.2, Color(0.2, 0.2, 0.2, 0.2))
		_disc(face + ax * side * 0.012, ax * side, r * 0.08, rim)
	# Lugs: bars from each shoulder in toward the middle, offset round the
	# tyre so they meet in a chevron.
	var n := 22
	for k in n:
		var a1 := TAU * k / n
		for side in [-1.0, 1.0]:
			var a2: float = a1 + side * 0.12
			var p1: Vector3 = mid + ax * side * w * 0.48 + Vector3(0, sin(a1), cos(a1)) * (r - 0.01)
			var p2: Vector3 = mid + ax * side * w * 0.05 + Vector3(0, sin(a2), cos(a2)) * (r - 0.01)
			_beam(p1, p2, 0.07, TIRE)


## A fender arching over a big rear tyre: a strip of painted steel round
## `c` (the axle) at radius r, w wide, from behind the wheel up and over to
## the front.
func _fender(c: Vector3, r: float, w: float) -> void:
	var n := 8
	for i in n:
		var a1 := lerpf(0.35, PI - 0.35, float(i) / n)
		var a2 := lerpf(0.35, PI - 0.35, float(i + 1) / n)
		var d1 := Vector3(0, sin(a1), cos(a1))
		var d2 := Vector3(0, sin(a2), cos(a2))
		var hx := Vector3(w * 0.5, 0, 0)
		var p1 := c + d1 * r
		var p2 := c + d2 * r
		_quad(p1 - hx, p1 + hx, p2 + hx, p2 - hx, PAINT, c)
		var q1 := c + d1 * (r + 0.02)
		var q2 := c + d2 * (r + 0.02)
		_quad(q1 - hx, q1 + hx, q2 + hx, q2 - hx, PAINT, c + d1 * 5.0)


## A 500 bu gravity wagon (Parker, Brent) on a four-wheel running gear:
## steep front and back, the floor sloping to the side door, a tarp roll.
func _trailer_gravity_wagon() -> void:
	var red := Color(0.62, 0.09, 0.06, 0.4)
	_box(Vector3(0, 0.75, 1.0), Vector3(0.12, 0.1, 2.0), TRIM)  # tongue
	_box(Vector3(0, 0.75, 3.9), Vector3(0.5, 0.15, 3.4), TRIM)   # running gear
	_loft([
		[1.6, 1.9, 2.25, 2.95, 0.5, 1.15, 1.2],
		[2.6, 1.05, 2.25, 2.95, 1.0, 1.15, 1.2],
		[5.2, 1.05, 2.25, 2.95, 1.0, 1.15, 1.2],
		[6.2, 1.9, 2.25, 2.95, 0.5, 1.15, 1.2],
	], [_edges(red, red)], red, red)
	_box(Vector3(0, 2.97, 3.9), Vector3(2.2, 0.04, 4.3), Color(0.85, 0.72, 0.30, 0.4))  # corn heaped
	for z in [2.3, 5.3]:
		for s in [-1.0, 1.0]:
			_wheel(Vector3(s * 0.95, 0.0, z), 0.45, 0.3, Color(0.85, 0.85, 0.82, 0.4))
	if not _lo:
		_box(Vector3(1.2, 1.4, 3.9), Vector3(0.05, 0.5, 0.6), STEEL)  # side door
		_box(Vector3(0, 0.9, 6.25), Vector3(0.6, 0.35, 0.02), Color(1.0, 0.35, 0.05, 0.4))  # SMV sign
		_box(Vector3(1.15, 1.2, 6.22), Vector3(0.1, 0.1, 0.03), TAIL, true)


func _combine() -> void:  # John Deere S790, header off for the road
	var L := 9.0
	_loft([
		[1.6, 1.2, 3.5, 3.7, 1.4, 1.5, 1.4],
		[L - 0.5, 1.2, 3.5, 3.7, 1.4, 1.5, 1.4],
		[L, 1.6, 3.0, 3.3, 1.2, 1.3, 1.2],
	], [_edges(PAINT, TRIM)], PAINT, PAINT)
	# Feeder house at the front, glass cab above it, grain tank on top.
	_loft([
		[0.0, 0.9, 1.6, 1.8, 0.65, 0.7, 0.65],
		[1.7, 1.3, 2.3, 2.5, 0.75, 0.8, 0.75],
	], [_edges(PAINT, TRIM)], TRIM, PAINT)
	_box(Vector3(0, 3.0, 1.2), Vector3(1.7, 1.5, 1.4), GLASS)
	_box(Vector3(0, 3.8, 1.2), Vector3(1.9, 0.12, 1.6), WHITE)
	if _hi:
		# The grain tank's folding extensions flare out above the body,
		# open on top over the grain.
		_loft([
			[3.2, 3.7, 4.05, 4.3, 1.25, 1.32, 1.42],
			[6.8, 3.7, 4.05, 4.3, 1.25, 1.32, 1.42],
		], [_edges(PAINT, PAINT)], PAINT, PAINT)
		_box(Vector3(0, 4.306, 5.0), Vector3(2.6, 0.004, 3.4), Color(0.82, 0.68, 0.3, 0.4))
	else:
		_box(Vector3(0, 4.0, 5.0), Vector3(2.6, 0.6, 3.6), PAINT)
	_box(Vector3(0, 3.96, 1.4), Vector3(0.14, 0.12, 0.14), BEACON_AMBER)
	_beam(Vector3(-1.2, 3.8, 3.6), Vector3(-1.4, 3.8, 8.6), 0.18, PAINT)
	var rim := Color(0.95, 0.75, 0.05, 0.4)
	if _hi:
		_combine_hi(L, rim)
	else:
		_wheel(Vector3(-1.4, 0.0, 2.4), 0.95, 0.7, rim)
		_wheel(Vector3(1.4, 0.0, 2.4), 0.95, 0.7, rim)
		_wheel(Vector3(-1.2, 0.0, 7.0), 0.7, 0.45, rim)
		_wheel(Vector3(1.2, 0.0, 7.0), 0.7, 0.45, rim)
	_box(Vector3(0.5, 3.4, 0.45), Vector3(0.3, 0.12, 0.08), HEAD, true)


## Ultra: a combine close up (JD S790, Case IH Axial-Flow): lugged drive
## and steer tyres, the cab's corner posts and mirrors, the stair up the
## left front to the platform, the dark mouth of the feeder house with
## its header off, the rotary radiator screen and louvres at the back of
## the engine bay, the straw chopper's housing, tail lamps and the
## slow-moving-vehicle triangle.
func _combine_hi(L: float, rim: Color) -> void:
	for s in [-1.0, 1.0]:
		_ag_wheel(Vector3(s * 1.4, 0.0, 2.4), 0.95, 0.7, rim)
		_ag_wheel(Vector3(s * 1.2, 0.0, 7.0), 0.7, 0.45, rim)
		for z in [0.5, 1.9]:
			_box(Vector3(s * 0.85, 3.0, z), Vector3(0.08, 1.5, 0.08), TRIM)
		_box(Vector3(s * 1.08, 3.45, 0.7), Vector3(0.38, 0.04, 0.04), TRIM)
		_box(Vector3(s * 1.28, 3.25, 0.7), Vector3(0.06, 0.4, 0.2), TRIM)
		_box(Vector3(s * 1.0, 1.05, L - 0.2), Vector3(0.14, 0.18, 0.04), TAIL)
	# The stair: treads stepping up the left front, with its rail.
	for i in 6:
		_box(Vector3(-1.05, 0.55 + i * 0.32, 0.55 + i * 0.12), Vector3(0.5, 0.04, 0.25), STEEL)
	_beam(Vector3(-1.3, 1.1, 0.4), Vector3(-1.3, 2.9, 1.1), 0.05, STEEL)
	# The feeder house's mouth, open with the header off.
	_box(Vector3(0, 1.32, -0.006), Vector3(1.1, 0.6, 0.012), Color(0.04, 0.04, 0.04, 0.3))
	# Radiator screen and engine louvres on the right side at the back.
	_disc(Vector3(1.51, 3.0, L - 1.6), Vector3(1, 0, 0), 0.55, Color(0.1, 0.1, 0.1, 0.3))
	for i in 5:
		_box(Vector3(1.506, 2.3 + i * 0.16, L - 3.2), Vector3(0.012, 0.06, 1.2), TRIM)
	# Straw chopper housing under the back, and the SMV sign above it.
	_box(Vector3(0, 1.25, L + 0.15), Vector3(1.9, 0.5, 0.3), TRIM)
	var o := Vector3(0, 2.2, L + 0.006)
	_tri(o + Vector3(-0.21, -0.18, 0), o + Vector3(0.21, -0.18, 0), o + Vector3(0, 0.18, 0), TAPE_RED, o - Vector3(0, 0, 1))
	o.z += 0.006
	_tri(o + Vector3(-0.15, -0.14, 0), o + Vector3(0.15, -0.14, 0), o + Vector3(0, 0.12, 0), Color(1.0, 0.38, 0.04, 0.4), o - Vector3(0, 0, 1))


func _motorcycle() -> void:  # cruiser (Harley-Davidson Street Glide) with rider
	_wheel(Vector3(0, 0, 0.35), 0.33, 0.13, CHROME, true)
	_wheel(Vector3(0, 0, 1.85), 0.33, 0.15, CHROME, true)
	_loft([
		[0.25, 0.75, 0.95, 1.1, 0.25, 0.4, 0.3],
		[0.7, 0.45, 0.9, 1.0, 0.18, 0.2, 0.16],
		[1.6, 0.45, 0.75, 0.85, 0.2, 0.22, 0.18],
		[2.15, 0.65, 0.9, 0.95, 0.22, 0.24, 0.2],
	], [_edges(PAINT, CHROME)], PAINT, PAINT)
	_box(Vector3(0, 1.15, 1.25), Vector3(0.4, 0.55, 0.35), Color(0.12, 0.12, 0.13, 0.4))
	_box(Vector3(0, 1.55, 1.15), Vector3(0.24, 0.26, 0.26), Color(0.06, 0.06, 0.07, 0.2))
	_box(Vector3(0, 0.95, 0.27), Vector3(0.16, 0.1, 0.06), HEAD, true)
	_box(Vector3(0, 0.85, 2.15), Vector3(0.14, 0.06, 0.04), TAIL, true)


## A street-legal four-seat golf cart (Club Car Onward / E-Z-GO Express
## S4): low front cowl with headlights, a canopy roof on four posts, a fold
## windshield, the driver on the front bench and a rear seat facing back.
func _golf_cart() -> void:
	var seat := Color(0.80, 0.74, 0.62, 0.4)
	var canopy := Color(0.12, 0.12, 0.13, 0.4)
	var shirt := Color(0.30, 0.42, 0.62, 0.4)
	var skin := Color(0.80, 0.62, 0.50, 0.4)
	_wheels([0.48, 2.2], 0.26, 0.62, 0.2)
	# Front cowl and the body round the floor, rear bodywork over the motor.
	_box(Vector3(0, 0.6, 0.36), Vector3(1.16, 0.52, 0.62), PAINT)
	_box(Vector3(0, 0.36, 1.35), Vector3(1.18, 0.14, 1.5), TRIM)
	_box(Vector3(0, 0.55, 2.25), Vector3(1.2, 0.4, 0.9), PAINT)
	# Front bench and back, the rear seat facing back.
	_box(Vector3(0, 0.74, 1.5), Vector3(1.08, 0.14, 0.5), seat)
	_box(Vector3(0, 1.02, 1.78), Vector3(1.08, 0.46, 0.1), seat)
	_box(Vector3(0, 0.82, 2.25), Vector3(1.08, 0.12, 0.46), seat)
	_box(Vector3(0, 1.02, 1.95), Vector3(1.08, 0.36, 0.08), seat)
	# Roof posts, canopy and windshield.
	for s in [-1.0, 1.0]:
		_beam(Vector3(s * 0.52, 0.8, 0.66), Vector3(s * 0.52, 1.86, 0.78), 0.05, TRIM)
		_beam(Vector3(s * 0.52, 0.75, 2.6), Vector3(s * 0.52, 1.86, 2.6), 0.05, TRIM)
	_box(Vector3(0, 1.9, 1.62), Vector3(1.24, 0.06, 2.12), canopy)
	if not _lo:
		_box(Vector3(0, 1.35, 0.72), Vector3(1.0, 0.9, 0.02), GLASS)
		_beam(Vector3(0.26, 0.85, 1.0), Vector3(0.26, 1.08, 1.12), 0.04, TRIM)  # steering column
		_box(Vector3(0.26, 1.1, 1.14), Vector3(0.34, 0.04, 0.12), TRIM)  # wheel
		# The driver on the front bench.
		_box(Vector3(0.26, 1.1, 1.52), Vector3(0.38, 0.5, 0.26), shirt)
		_box(Vector3(0.26, 1.48, 1.5), Vector3(0.2, 0.22, 0.22), skin)
		_box(Vector3(0.38, 0.62, 0.05), Vector3(0.14, 0.08, 0.04), HEAD, true)
		_box(Vector3(0.48, 0.62, 2.71), Vector3(0.1, 0.08, 0.03), TAIL, true)


## An Amish black top buggy (Daviess County, Indiana) behind a bay
## Standardbred: tall thin wheels, shafts to the harness, the driver under
## the top, and the orange slow-moving-vehicle triangle on the back.
func _buggy() -> void:
	var bay := Color(0.48, 0.29, 0.15, 0.4)
	var dark := Color(0.08, 0.06, 0.05, 0.4)
	# Horse: barrel, chest, neck and head, legs mid-trot, tail.
	_loft([
		[0.75, 1.0, 1.35, 1.55, 0.2, 0.28, 0.18],
		[1.1, 0.95, 1.35, 1.6, 0.26, 0.32, 0.22],
		[2.0, 0.95, 1.35, 1.6, 0.27, 0.33, 0.23],
		[2.4, 1.05, 1.35, 1.55, 0.22, 0.28, 0.18],
	], [_edges(bay, bay)], bay, bay)
	_beam(Vector3(0, 1.35, 0.95), Vector3(0, 1.95, 0.55), 0.24, bay)
	_beam(Vector3(0, 1.95, 0.6), Vector3(0, 1.75, 0.08), 0.18, bay)
	_beam(Vector3(0, 1.62, 1.0), Vector3(0, 2.12, 0.66), 0.07, dark)  # mane
	var legs := [[0.95, 0.15], [1.05, -0.2], [2.15, -0.15], [2.25, 0.2]]
	for i in 4:
		var s := -1.0 if i % 2 == 0 else 1.0
		var z: float = legs[i][0]
		_beam(Vector3(s * 0.15, 1.0, z), Vector3(s * 0.15, 0.0, z + legs[i][1]), 0.1, dark if _lo else bay)
	_beam(Vector3(0, 1.45, 2.4), Vector3(0, 0.75, 2.65), 0.1, dark)
	# Shafts and harness.
	for s in [-1.0, 1.0]:
		_beam(Vector3(s * 0.42, 1.15, 0.9), Vector3(s * 0.5, 0.95, 3.4), 0.05, TRIM)
	_box(Vector3(0, 1.4, 1.25), Vector3(0.7, 0.08, 0.12), TRIM)
	# Buggy: box seat body, black top, open front with the driver.
	_box(Vector3(0, 0.95, 4.3), Vector3(1.3, 0.5, 1.9), PAINT)
	_loft([
		[3.6, 1.2, 2.25, 2.35, 0.62, 0.66, 0.6],
		[5.25, 1.2, 2.25, 2.35, 0.62, 0.66, 0.6],
	], [_edges(PAINT, PAINT)], PAINT, PAINT)
	_box(Vector3(0, 1.65, 3.62), Vector3(0.9, 0.7, 0.02), Color(0.03, 0.03, 0.03, 0.4))
	_box(Vector3(0.18, 1.45, 3.9), Vector3(0.38, 0.6, 0.3), Color(0.10, 0.12, 0.18, 0.4))
	_box(Vector3(0.18, 1.9, 3.9), Vector3(0.22, 0.24, 0.22), Color(0.82, 0.68, 0.5, 0.4))
	_box(Vector3(0.18, 2.06, 3.9), Vector3(0.4, 0.04, 0.4), Color(0.06, 0.06, 0.06, 0.4))
	# Tall wooden-spoke wheels, black with steel tyres.
	for z in [3.45, 4.9]:
		var r := 0.55 if z < 4.0 else 0.65
		for s in [-1.0, 1.0]:
			var c := Vector3(s * 0.78, r, z)
			if _lo:
				_box(c, Vector3(0.05, r * 1.6, r * 1.6), dark)
				continue
			# Steel tyre round the rim, and spokes you can see through.
			var n := 12
			for i in n:
				var a0 := TAU * i / n
				var a1 := TAU * (i + 1) / n
				_beam(c + Vector3(0, cos(a0), sin(a0)) * r, c + Vector3(0, cos(a1), sin(a1)) * r, 0.05, dark)
			for i in 6:
				var a := TAU * i / 12.0
				var d := Vector3(0, cos(a), sin(a)) * r
				_beam(c - d, c + d, 0.025, dark)
	# Slow-moving-vehicle emblem and battery lamps.
	_tri(Vector3(-0.2, 1.35, 5.27), Vector3(0.2, 1.35, 5.27), Vector3(0, 1.7, 5.27),
		Color(1.0, 0.35, 0.05, 0.4), Vector3(0, 1.5, 4.0))
	_box(Vector3(0.62, 1.9, 5.27), Vector3(0.08, 0.1, 0.03), TAIL, true)
	_box(Vector3(0.62, 1.9, 3.59), Vector3(0.08, 0.1, 0.03), HEAD, true)


## A straight snow plow blade (Western, Fisher, Boss) out front, on its
## A-frame and lift.
func _plow(W: float, H: float, y0: float, col: Color) -> void:
	var hw := W * 0.5
	# Curved moldboard: three bands leaning back toward the top.
	_quad(Vector3(-hw, y0, -0.95), Vector3(hw, y0, -0.95), Vector3(hw, y0 + H * 0.4, -0.85),
		Vector3(-hw, y0 + H * 0.4, -0.85), col, Vector3(0, y0, 0.5))
	_quad(Vector3(-hw, y0 + H * 0.4, -0.85), Vector3(hw, y0 + H * 0.4, -0.85), Vector3(hw, y0 + H * 0.8, -0.85),
		Vector3(-hw, y0 + H * 0.8, -0.85), col, Vector3(0, y0, 0.5))
	_quad(Vector3(-hw, y0 + H * 0.8, -0.85), Vector3(hw, y0 + H * 0.8, -0.85), Vector3(hw, y0 + H, -1.0),
		Vector3(-hw, y0 + H, -1.0), col, Vector3(0, y0, 0.5))
	_box(Vector3(0, y0 + H * 0.5, -0.8), Vector3(W - 0.1, H * 0.9, 0.05), TRIM)
	_box(Vector3(0, y0 + 0.02, -0.97), Vector3(W, 0.06, 0.08), STEEL)
	_box(Vector3(0, y0 + H * 0.45, -0.45), Vector3(0.8, 0.15, 0.7), TRIM)
	if not _lo:
		_box(Vector3(0, y0 + H + 0.25, -0.35), Vector3(0.12, 0.6, 0.12), TRIM)
		for s in [-1.0, 1.0]:
			_box(Vector3(s * (hw - 0.05), y0 + H + 0.35, -0.95), Vector3(0.04, 0.7, 0.04), BEACON_AMBER)


func _work_pickup_plow() -> void:  # an F-250 with an 8 ft Western plow
	_work_pickup()
	_plow(2.45, 0.8, 0.12, Color(0.88, 0.70, 0.06, 0.4))
	_box(Vector3(0, 2.0, 1.95), Vector3(0.9, 0.1, 0.2), BEACON_AMBER)


## A dump truck on plow duty: a 11 ft blade, the bed heaped with road salt
## and a spinner spreader at the tail.
func _dump_truck_plow() -> void:
	_dump_truck()
	_plow(3.35, 1.1, 0.15, Color(0.92, 0.42, 0.05, 0.4))
	_loft([
		[3.6, 2.6, 2.9, 2.95, 1.1, 1.12, 1.0],
		[5.0, 2.6, 2.9, 3.25, 1.1, 1.12, 0.5],
		[7.8, 2.6, 2.9, 3.25, 1.1, 1.12, 0.5],
		[8.7, 2.6, 2.9, 2.95, 1.1, 1.12, 1.0],
	], [_edges(Color(0.78, 0.74, 0.70, 0.4), Color(0.78, 0.74, 0.70, 0.4))], Color(0.78, 0.74, 0.70, 0.4), Color(0.78, 0.74, 0.70, 0.4))
	_box(Vector3(0, 0.75, 9.15), Vector3(0.7, 0.3, 0.4), TRIM)
	_box(Vector3(0, 2.62, 3.05), Vector3(1.2, 0.1, 0.2), BEACON_AMBER)


# --- Building blocks --------------------------------------------------------

## The eight edge codes round a loft section, from the bottom: bottom, low
## chamfers, sides, upper sides and top. Up to four codes are spread out:
## (sides, bottom, upper sides, top).
static func _edges(sides: Color, bottom: Color, upper := Color(-1, 0, 0), top := Color(-1, 0, 0)) -> Array:
	var u := sides if upper.r < 0.0 else upper
	var t := u if top.r < 0.0 else top
	return [bottom, bottom, sides, u, t, u, sides, bottom]


## A body lofted through sections [z, bottom y, shoulder y, top y, bottom
## half width, shoulder half width, top half width]. codes holds the edge
## codes for each span (the last one repeats).
func _loft(sections: Array, codes: Array, front: Color, back: Color) -> void:
	if _hi:
		var fine := _refine(sections, codes)
		sections = fine[0]
		codes = fine[1]
	var rings := []
	for s in sections:
		var z: float = s[0]
		var yb: float = s[1]
		var ys: float = s[2]
		var yt: float = s[3]
		var ch := minf(0.08, (ys - yb) * 0.3)
		rings.append([
			Vector3(-s[4] + ch, yb, z), Vector3(s[4] - ch, yb, z), Vector3(s[4], yb + ch, z),
			Vector3(s[5], ys, z), Vector3(s[6], yt, z), Vector3(-s[6], yt, z),
			Vector3(-s[5], ys, z), Vector3(-s[4], yb + ch, z),
		])
	var m := 8
	if _hi:
		# Ultra: cut each corner of the cross-section, so the sides and
		# roof round over like pressed steel instead of meeting at a fold.
		for r in rings.size():
			rings[r] = _round_ring(rings[r])
		var fine := []
		for cs in codes:
			var row := []
			for e in 8:
				# The bevel after edge e takes its code, unless that is
				# glass: then it takes the next one, so roof and belt
				# corners stay steel on both sides.
				var nx: Color = cs[(e + 1) % 8]
				row.append(cs[e])
				row.append(nx if _is_glass(cs[e]) else cs[e])
			fine.append(row)
		codes = fine
		m = 16
	# Face normals, pointing out.
	var fn := []
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var mid := Vector3(0, (sections[i][1] + sections[i][3] + sections[i + 1][1] + sections[i + 1][3]) * 0.25,
			(sections[i][0] + sections[i + 1][0]) * 0.5)
		var row := []
		for e in m:
			var e2 := (e + 1) % m
			var n: Vector3 = (b[e2] - a[e]).cross(a[e2] - b[e])
			if n.length_squared() < 1e-12:
				row.append(Vector3.ZERO)
				continue
			n = n.normalized()
			if n.dot((a[e] + b[e2]) * 0.5 - mid) < 0.0:
				n = -n
			row.append(n)
		fn.append(row)
	# Smooth across gentle bends (under 60 degrees), keep sharp creases.
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var cs: Array = codes[mini(i, codes.size() - 1)]
		for e in m:
			var n: Vector3 = fn[i][e]
			if n == Vector3.ZERO:
				continue
			var e2 := (e + 1) % m
			var corners := [[a[e], i, e], [a[e2], i, e2], [b[e2], i + 1, e2], [b[e], i + 1, e]]
			var pts := []
			var nrm := []
			for c in corners:
				pts.append(c[0])
				nrm.append(n if _lo else _smooth(fn, n, c[1], c[2]))
			_tri_n(pts[0], pts[1], pts[2], nrm[0], nrm[1], nrm[2], cs[e])
			_tri_n(pts[0], pts[2], pts[3], nrm[0], nrm[2], nrm[3], cs[e])
	_cap(rings[0], front, Vector3(0, 0, 1))
	_cap(rings[rings.size() - 1], back, Vector3(0, 0, -1))


## Ultra: extra sections between the given ones on a smooth curve through
## them, so hoods, roofs and noses round over instead of folding. Tangents
## go flat where a value turns, so nothing bulges past the shape.
static func _refine(sections: Array, codes: Array) -> Array:
	var out := []
	var out_codes := []
	var n := sections.size()
	for i in n - 1:
		var a: Array = sections[i]
		var b: Array = sections[i + 1]
		var span: float = b[0] - a[0]
		var steps := clampi(int(span / 0.35), 1, 4)
		var cs: Array = codes[mini(i, codes.size() - 1)]
		out.append(a)
		for k in range(1, steps):
			var t := float(k) / steps
			var row := [lerpf(a[0], b[0], t)]
			for f in range(1, a.size()):
				var prev: float = sections[i - 1][f] if i > 0 else a[f]
				var next: float = sections[i + 2][f] if i + 2 < n else b[f]
				var m0 := _slope(prev, a[f], b[f])
				var m1 := _slope(a[f], b[f], next)
				var t2 := t * t
				var t3 := t2 * t
				row.append((2 * t3 - 3 * t2 + 1) * a[f] + (t3 - 2 * t2 + t) * m0
					+ (-2 * t3 + 3 * t2) * b[f] + (t3 - t2) * m1)
			out.append(row)
		for k in steps:
			out_codes.append(cs)
	out.append(sections[n - 1])
	return [out, out_codes]


## One corner cut on a cross-section: each edge keeps its middle and a
## short bevel (7 cm at most, so glass keeps its size) joins it to the next. Points 2e and 2e+1 lie on edge e.
static func _round_ring(ring: Array) -> Array:
	var out := []
	var n := ring.size()
	for e in n:
		var a: Vector3 = ring[e]
		var b: Vector3 = ring[(e + 1) % n]
		var f := minf(0.16, 0.07 / maxf(a.distance_to(b), 0.001))
		out.append(a.lerp(b, f))
		out.append(a.lerp(b, 1.0 - f))
	return out


static func _is_glass(c: Color) -> bool:
	return absf(c.a - GLASS.a) < 0.03


static func _slope(p: float, c: float, n: float) -> float:
	var d0 := c - p
	var d1 := n - c
	if d0 * d1 <= 0.0:
		return 0.0
	return 2.0 * d0 * d1 / (d0 + d1)


## The normal at ring r, point k, averaged over the faces around it that
## bend less than 60 degrees from face normal n.
static func _smooth(fn: Array, n: Vector3, r: int, k: int) -> Vector3:
	var sum := Vector3.ZERO
	for i in [r - 1, r]:
		if i < 0 or i >= fn.size():
			continue
		var cnt: int = fn[i].size()
		for e in [(k + cnt - 1) % cnt, k]:
			var m: Vector3 = fn[i][e]
			if m.dot(n) > 0.5:
				sum += m
	return sum.normalized() if sum.length_squared() > 0.0 else n


## A triangle with its own vertex normals, wound to face along them.
func _tri_n(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color) -> void:
	var f := (c - a).cross(b - a)
	if f.length_squared() < 1e-12:
		return
	if f.dot(na + nb + nc) < 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	_st.set_color(col)
	_st.set_normal(na)
	_st.add_vertex(a)
	_st.set_normal(nb)
	_st.add_vertex(b)
	_st.set_normal(nc)
	_st.add_vertex(c)


func _cap(ring: Array, col: Color, inward: Vector3) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	for i in ring.size():
		_tri(ring[i], ring[(i + 1) % ring.size()], c, col, c + inward)


func _box(c: Vector3, size: Vector3, col: Color, mirror := false) -> void:
	if mirror:
		_box(Vector3(-c.x, c.y, c.z), size, col)
	var h := size * 0.5
	var v := []
	for k in 8:
		v.append(c + Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
	for f in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		_quad(v[f[0]], v[f[1]], v[f[2]], v[f[3]], col, c)


## A square beam from a to b (booms, augers).
func _beam(a: Vector3, b: Vector3, t: float, col: Color) -> void:
	_cyl(a, b, t * 0.7, col, 4)


func _cyl(a: Vector3, b: Vector3, r: float, col: Color, n := 8) -> void:
	if _lo:
		n = mini(n, 6)
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := axis.cross(u)
	var ra := []
	var rb := []
	for i in n:
		var ang := TAU * i / n
		var off := (u * cos(ang) + w * sin(ang)) * r
		ra.append(a + off)
		rb.append(b + off)
	var mid := (a + b) * 0.5
	for i in n:
		var j := (i + 1) % n
		_quad(ra[i], ra[j], rb[j], rb[i], col, mid)
		_tri(ra[i], ra[j], a, col, mid)
		_tri(rb[i], rb[j], b, col, mid)


## Pairs of wheels on axles at these distances from the front bumper.
## `w` is the tyre width, or for tandem duals, the width of the pair.
func _wheels(axles: Array, r: float, hw: float, w: float) -> void:
	for z in axles:
		for s in [-1.0, 1.0]:
			_wheel(Vector3(s * (hw - w * 0.5 + 0.03), 0.0, z), r, w, RIM)
			if not _lo:
				# Dark wheel well behind the tyre.
				_arch(Vector3(s * (hw + 0.004), r, z), r + 0.07, s)


func _wheel(c: Vector3, r: float, w: float, rim: Color, upright := false) -> void:
	var y := r
	if _lo:
		_box(Vector3(c.x, y, c.z), Vector3(w, r * 1.8, r * 1.8), TIRE)
		return
	var n := 24 if _hi else 12
	var ax := Vector3(0, 0, 1) if upright else Vector3(1, 0, 0)
	var a := Vector3(c.x, y, c.z) - ax * w * 0.5
	var b := a + ax * w
	_cyl(a, b, r, TIRE, n)
	# Hubs on both faces, inset a little.
	for side in [-1.0, 1.0]:
		var face: Vector3 = Vector3(c.x, y, c.z) + ax * side * (w * 0.5 + 0.005)
		if not _hi:
			_disc(face, ax * side, r * 0.58, rim)
			continue
		# Sidewall, the rim lip, a dark barrel behind open spokes, the brake
		# disc, five spokes and the centre cap.
		_disc(face, ax * side, r * 0.66, Color(0.06, 0.06, 0.06, 0.3))
		_disc(face + ax * side * 0.006, ax * side, r * 0.6, rim)
		_disc(face + ax * side * 0.012, ax * side, r * 0.53, Color(0.03, 0.03, 0.03, 0.4))
		_disc(face + ax * side * 0.018, ax * side, r * 0.36, STEEL)
		var u := ax.cross(Vector3.UP).normalized() if absf(ax.y) < 0.9 else Vector3.RIGHT
		var v := ax.cross(u)
		for k in 5:
			var ang := TAU * k / 5.0
			var dir := u * cos(ang) + v * sin(ang)
			_beam(face + ax * side * 0.026 + dir * r * 0.12, face + ax * side * 0.026 + dir * r * 0.56, 0.09, rim)
		_disc(face + ax * side * 0.034, ax * side, r * 0.14, rim)


func _disc(c: Vector3, normal: Vector3, r: float, col: Color) -> void:
	var u := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := normal.cross(u)
	var n := 20 if _hi else 8
	for i in n:
		var p1 := c + (u * cos(TAU * i / n) + w * sin(TAU * i / n)) * r
		var p2 := c + (u * cos(TAU * (i + 1) / n) + w * sin(TAU * (i + 1) / n)) * r
		_tri(p1, p2, c, col, c - normal)


## A dark half-disc on the body side behind a wheel, so it reads as a well.
func _arch(c: Vector3, r: float, side: float) -> void:
	var n := 7
	for i in n:
		var a1 := PI * i / n
		var a2 := PI * (i + 1) / n
		var p1 := c + Vector3(0, sin(a1) * r, cos(a1) * r)
		var p2 := c + Vector3(0, sin(a2) * r, cos(a2) * r)
		_tri(p1, p2, c, TIRE, c - Vector3(side, 0, 0))


## Two triangles, wound so they face away from `inside`.
func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, inside: Vector3) -> void:
	_tri(a, b, c, col, inside)
	_tri(a, c, d, col, inside)


func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color, inside: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	_st.set_color(col)
	_st.set_normal(n)
	_st.add_vertex(a)
	_st.set_normal(n)
	_st.add_vertex(b)
	_st.set_normal(n)
	_st.add_vertex(c)
