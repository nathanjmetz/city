class_name CivicBuilder
extends CommercialBuilder
## Town service buildings, benchmarked against photos of real small
## Midwestern towns:
##   - the volunteer fire station: a tall brick apparatus bay with 12 x 14 ft
##     sectional doors, a long concrete apron, a lower office wing, a hose
##     tower and a flagpole
##   - the police station and walk-in clinic: one-storey brick offices with
##     flat roofs, a glass entry under a canopy, and a striped lot in front
##   - the 1960s elementary school: long single-storey brick wings with
##     ribbon windows, a taller gym, a bus loop, a blacktop playground and a
##     ball diamond with a backstop
##   - the distribution substation: a fenced gravel yard with galvanised
##     steel frames, insulators, transformers with cooling fins and a small
##     control house
##   - the multi-leg water tower: braced legs, an ellipsoidal tank with a
##     catwalk and a cone roof
##   - the well house and the pole-mounted power feed
##   - the small-town bus garage: a tall metal maintenance building with
##     14 ft doors onto the yard, a brick office in front, and a fenced
##     asphalt yard of striped bus stalls (the buses are drawn by BusView)
## Local space: centred on the site, -z faces the road; the site runs from
## -size.y / 2 (front) to +size.y / 2. `to_curb` is how far the curb lies in
## front of the site.

const WHITE := Color("#e9e7e0")
const GALV := Color("#a9adab")
const CONCRETE := Color("#b9b5ab")
const DARK := Color("#2e3032")
const POLE := Color("#5b4a38")
const DIRT := Color("#9a7a58")
## How deep a fire or police station's first lot is: what a grown station
## adds (Stations) goes on the land behind it.
const FIRST_D := 36.0


static func build_service(kind: int, seed: int, size: Vector2, to_curb: float, built := []) -> Array:
	var b := CivicBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front := -size.y * 0.5
	match kind:
		Services.Kind.FIRE:
			b._fire(front, to_curb)
			b._station_upgrades(kind, size, front, built)
		Services.Kind.POLICE:
			b._police(front, to_curb)
			b._station_upgrades(kind, size, front, built)
		Services.Kind.CLINIC:
			b._clinic(front, to_curb)
			b._station_upgrades(kind, size, front, built)
		Services.Kind.SCHOOL:
			b._school(front, to_curb)
			b._station_upgrades(kind, size, front, built)
		Services.Kind.SUBSTATION: b._substation(front, to_curb)
		Services.Kind.WATER_TOWER: b._water_tower(front, to_curb)
		Services.Kind.WELL, Services.Kind.WATER_UTILITY: b._well(front, to_curb)
		Services.Kind.POWER_FEED: b._power_feed()
		Services.Kind.BUS_DEPOT:
			b._bus_depot(size, front, to_curb)
			b._bus_upgrades(size, front, built)
		Services.Kind.TAXI_COMPANY:
			b._taxi_company(size, front, to_curb)
			b._taxi_upgrades(size, front, built)
		Services.Kind.BUILDER_YARD:
			b._builder_yard(size, front, to_curb)
		Services.Kind.TRAFFIC_CENTER: b._traffic_center(front, to_curb)
	b.half = size.x * 0.5
	b.depth = size.y * 0.5
	b._dress(false, true)
	return [b._commit_house(), b._commit_flat(), b.trees]


# ---------------------------------------------------------------- fire

func _fire(front: float, to_curb: float) -> void:
	var brick := Color(_pick(["#8a4a38", "#9b5a42", "#7a4234", "#a8775c"]))
	var trim := Color(_pick(["#d9d3c3", "#cfc8b6", "#efede6"]))
	var bays := 2 if rng.randf() < 0.6 else 3
	var bay_w := 5.4
	var aw := bays * bay_w + 1.6  # apparatus bay
	var ad := rng.randf_range(18.0, 20.0)
	var ah := 7.2
	var zf := front + rng.randf_range(10.5, 11.5)  # a long apron in front
	var ax := 15.0 - aw * 0.5 - 0.8
	_slab(ax, aw, zf, ad)
	_flat_roofed_at("brick", ax, aw, ad, zf + ad * 0.5, ah, ah + 0.8, brick)
	for i in bays:
		var x := ax - aw * 0.5 + 0.8 + (i + 0.5) * bay_w
		_overhead_door(x, zf, 3.7, 4.3, WHITE)
		# Rear doors too: drive-through bays.
		_overhead_door(x, zf + ad, 3.7, 4.3, WHITE, true)
		_flat_rect("drive", x - 2.4, x + 2.4, -to_curb + front, zf, 0.09)
	# Stone band, sign and lights over the doors.
	_box("paint", Vector3(aw + 0.1, 0.3, 0.18), Vector3(ax, 5.15, zf - 0.09), trim)
	_sign(Vector3(ax, 5.55, zf - 0.12), aw * 0.6, 0.75)
	# Office and day room: a lower wing beside the bays. Its back wall takes
	# the meters and transformer, clear of the drive-through apron.
	_dr_main = _dr_halls.size()
	var ow := 30.0 - aw - 2.4
	var od := rng.randf_range(12.0, 15.0)
	var ox := ax - aw * 0.5 - ow * 0.5
	var oz := zf + 1.5
	_slab(ox, ow, oz, od)
	_flat_roofed_at("brick", ox, ow, od, oz + od * 0.5, 3.9, 4.5, brick)
	_entry(ox + ow * 0.25, oz, trim)
	_window_row(ox - ow * 0.15, oz, ow * 0.5, 1.6, 1.4, 2, trim)
	_window_row(ox - ow * 0.5, oz + od * 0.5, od * 0.6, 1.6, 1.3, 3, trim, Vector3(-1, 0, 0))
	# Hose tower at the back corner.
	if rng.randf() < 0.7:
		var tx := ax + aw * 0.5 - 2.2
		var tz := zf + ad + 2.1
		_box("brick", Vector3(4.0, 13.0, 4.0), Vector3(tx, 6.5, tz), brick)
		_box("paint", Vector3(4.3, 0.3, 4.3), Vector3(tx, 13.1, tz), trim)
		_glass(Vector3(tx, 11.0, tz - 2.02), Vector3(-1, 0, 0), 0.8, 1.4, 0.0)
	# Parking for the volunteers, and the flag.
	_parking(ox - ow * 0.5 + 0.3, ox + ow * 0.5 - 0.3, front + 0.3, oz - 2.0, to_curb, ox)
	_flagpole(Vector3(ox - ow * 0.5 + 1.2, 0, front + 1.5))
	_flat_rect("drive", ax - aw * 0.5, ax + aw * 0.5, zf + ad, front + FIRST_D, 0.08)


# ---------------------------------------------------------------- police

func _police(front: float, to_curb: float) -> void:
	var brick := Color(_pick(["#8a4a38", "#a8775c", "#b59a7c", "#7a4234", "#c9c1ae"]))
	var trim := Color(_pick(["#d9d3c3", "#cfc8b6", "#3a3530"]))
	var w := rng.randf_range(20.0, 23.0)
	var d := rng.randf_range(14.0, 16.0)
	var zf := front + 14.0
	var h := rng.randf_range(4.2, 4.8)
	_slab(0.0, w, zf, d)
	_flat_roofed_at("brick", 0.0, w, d, zf + d * 0.5, h, h + 0.7, brick)
	_box("paint", Vector3(w + 0.1, 0.25, 0.16), Vector3(0, h - 0.3, zf - 0.08), trim)
	var ex := rng.randf_range(-w * 0.2, w * 0.2)
	_vestibule(ex, zf, 4.2, 2.6, h - 0.6)
	_sign(Vector3(ex, h - 0.05, zf - 2.75), 3.6, 0.5)
	_window_row(ex - 2.1 - (w * 0.5 + ex - 2.1) * 0.5, zf, w * 0.5 + ex - 3.5, 1.7, 1.2, 3, trim)
	_window_row(ex + 2.1 + (w * 0.5 - ex - 2.1) * 0.5, zf, w * 0.5 - ex - 3.5, 1.7, 1.2, 3, trim)
	for s in [-1.0, 1.0]:
		_window_row(s * w * 0.5, zf + d * 0.5, d * 0.6, 1.7, 1.2, 3, trim, Vector3(s, 0, 0))
	# A fenced lot for the cruisers out back.
	_flat_rect("asphalt", -14.5, 14.5, zf + d, front + FIRST_D - 0.2, 0.06)
	# The fence takes in any yard the station has grown behind (Stations).
	_fence(Vector2(-14.5, zf + d + 1.0), Vector2(14.5, -front - 0.2), 2.0)
	_parking(-14.5, 14.5, front + 0.3, zf - 3.0, to_curb, -9.0)
	_flat_rect("drive", -w * 0.5, w * 0.5, zf - 3.0, zf, 0.08)
	_flagpole(Vector3(ex - 4.5, 0, zf - 4.0))
	_bed(ex + 3.2, zf - 2.0, 3.0)


# ---------------------------------------------------------------- station growth

## What a fire or police station has added as its town grew (Stations), in
## the order built: a piece that bought land stands on its own strip behind
## the first lot, the strips one after another; the rest fit on the lot.
func _station_upgrades(kind: int, size: Vector2, front: float, built: Array) -> void:
	if built.is_empty():
		return
	var w := size.x
	var z := front + float(Services.KINDS[kind].size.y)
	var back := -front
	var brick := Color(_pick(["#8a4a38", "#9b5a42", "#a8775c", "#b59a7c"]))
	var trim := Color(_pick(["#d9d3c3", "#cfc8b6", "#efede6"]))
	for key in built:
		var g := float(Stations.node(kind, key).get("grow", 0.0))
		if z + g > back + 0.01:
			break  # a lot drawn smaller than what was built (an old copy)
		match key:
			"drill_tower": _drill_tower(w, z, g)
			"ladder": _ladder_bay(w, z, g, brick, trim)
			"quarters": _crew_quarters(w, z, g, brick, trim)
			"eoc": _eoc(w, z, g, brick, trim)
			"generator": _generator(Vector3(-w * 0.5 + 3.0, 0, front + FIRST_D - 3.2))
			"sally_port": _sally_port(w, z, g, brick, trim)
			"evidence": _evidence(w, z, g)
			"k9": _kennel(Vector3(-w * 0.5 + 1.5, 0, front + FIRST_D - 5.6))
			"dispatch": _dispatch_tower(Vector3(w * 0.5 - 3.5, 0, front + FIRST_D - 3.5))
			"pharmacy": _clinic_wing(w, z, g, "pharmacy")
			"urgent_care": _clinic_wing(w, z, g, "urgent_care")
			"dental": _clinic_wing(w, z, g, "dental")
			"dialysis": _clinic_wing(w, z, g, "dialysis")
			"prek": _prek_wing(w, z, g, brick, trim)
			"portables":
				# The addition's classrooms replace the portables: their pad
				# stays as a blacktop.
				if "addition" in built:
					_flat_rect("asphalt", -w * 0.5 + 4.0, -w * 0.5 + 30.0, z + 1.0, z + g - 1.0, 0.06)
					for i in 2:
						_hoop(Vector3(-w * 0.5 + 10.0 + i * 12.0, 0, z + 2.0))
				else:
					_portables(w, z, g)
					_covered_walk(-22.0, front + 70.0, z)
			"addition":
				_school_addition(w, z, g, brick, trim)
				_covered_walk(-22.0, front + 70.0, z + 3.0)
			"aux_gym": _aux_gym(w, z, g, brick, trim)
			_: _care_piece(key, w, z, g)
		z += g


## A fire training tower (ISO credits a department's own): a four-storey
## steel tower in tan and red with open window bays on each floor, a stair
## landing up one side and a guardrail on the roof, a low burn room beside
## it (soot over its door), on an asphalt drill ground with a hydrant.
func _drill_tower(w: float, z: float, g: float) -> void:
	_flat_rect("asphalt", -w * 0.5 + 0.5, w * 0.5 - 0.5, z, z + g - 0.3, 0.06)
	var c := Vector3(-w * 0.5 + 6.0, 0, z + g * 0.5 + 0.5)
	var tan := Color("#c9b08a")
	var red := Color("#9b3328")
	var fl := 3.2
	_box("paint", Vector3(6.4, 0.3, 6.4), c + Vector3(0, 0.15, 0), CONCRETE)
	_box("paint", Vector3(6.0, fl * 4.0, 6.0), c + Vector3(0, fl * 2.0 + 0.3, 0), tan)
	for f in 4:
		var y := 0.3 + f * fl
		_box("paint", Vector3(6.08, 0.25, 6.08), c + Vector3(0, y + fl - 0.1, 0), red)  # floor bands
		# Open window bays, dark inside, on the front and the drill-ground side.
		for k in 2:
			_box("paint", Vector3(1.1, 1.3, 0.06), c + Vector3(-1.4 + k * 2.8, y + 1.6, -3.03), Color("#2b2522"))
			_box("paint", Vector3(0.06, 1.3, 1.1), c + Vector3(3.03, y + 1.6, -1.4 + k * 2.8), Color("#2b2522"))
	# The stair landing up the back, a standpipe and the roof rail.
	_box("paint", Vector3(2.4, fl * 4.0 + 1.0, 2.6), c + Vector3(-1.6, fl * 2.0 + 0.8, 4.3), red.darkened(0.1))
	_box("paint", Vector3(0.16, fl * 4.0, 0.16), c + Vector3(3.15, fl * 2.0 + 0.3, 2.6), Color("#b8322a"))
	var top := 0.3 + fl * 4.0
	for e in [-1.0, 1.0]:
		_box("paint", Vector3(6.0, 0.06, 0.06), c + Vector3(0, top + 1.05, e * 2.97), GALV)
		_box("paint", Vector3(0.06, 0.06, 6.0), c + Vector3(e * 2.97, top + 1.05, 0), GALV)
	for e in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_box("paint", Vector3(0.06, 1.05, 0.06), c + Vector3(e.x * 2.97, top + 0.52, e.y * 2.97), GALV)
	# The burn room: a concrete box, its door blackened.
	var br := c + Vector3(6.2, 0, 0.5)
	_box("paint", Vector3(5.0, 3.0, 4.6), br + Vector3(0, 1.5, 0), Color("#9d9a92"))
	_box("paint", Vector3(1.0, 2.1, 0.06), br + Vector3(0, 1.05, -2.33), Color("#2f2a28"))
	_box("paint", Vector3(1.8, 0.9, 0.05), br + Vector3(0, 2.6, -2.33), Color("#3b3532"))
	# Hydrant and a line of cones for pump practice.
	_cyl_y(Vector3(w * 0.5 - 2.0, 0.4, z + 1.2), 0.15, 0.8, Color("#c8a52a"))
	for i in 5:
		_box("paint", Vector3(0.3, 0.45, 0.3), Vector3(2.0 + i * 2.4, 0.23, z + g - 2.5), Color("#e06a1f"))


## A raised bay for a ladder truck, built on behind the apparatus bays:
## taller brick walls, a 14 ft door at each end so the truck drives through.
func _ladder_bay(w: float, z: float, g: float, brick: Color, trim: Color) -> void:
	var x := w * 0.5 - 4.6
	var bw := 7.4
	var h := 9.4
	_slab(x, bw, z, g - 1.0)
	_flat_roofed_at("brick", x, bw, g - 1.0, z + (g - 1.0) * 0.5, h, h + 0.8, brick)
	_box("paint", Vector3(bw + 0.1, 0.3, 0.18), Vector3(x, h - 1.2, z - 0.09), trim)
	_overhead_door(x, z, 4.3, 4.6, WHITE)
	_overhead_door(x, z + g - 1.0, 4.3, 4.6, WHITE, true)
	_flat_rect("drive", x - bw * 0.5, x + bw * 0.5, z + g - 1.0, z + g, 0.08)
	_flat_rect("drive", -w * 0.5 + 0.5, x - bw * 0.5, z, z + g - 0.3, 0.08)


## Living quarters for a paid crew on 24-hour shifts: a one-storey brick wing
## of bunk rooms and a kitchen, a patio with the grill and picnic table, and
## the crew's parking.
func _crew_quarters(w: float, z: float, g: float, brick: Color, trim: Color) -> void:
	var qw := w * 0.6
	var qd := g - 4.0
	var x := -w * 0.5 + 1.0 + qw * 0.5
	var zf := z + 1.0
	_slab(x, qw, zf, qd)
	_flat_roofed_at("brick", x, qw, qd, zf + qd * 0.5, 3.6, 4.2, brick)
	_window_row(x, zf, qw - 2.0, 1.6, 1.2, 5, trim)
	_window_row(x, zf + qd, qw - 2.0, 1.6, 1.2, 5, trim, Vector3.BACK)
	_entry(x + qw * 0.5 - 1.8, zf, trim)
	_rooftop_units(x, qw, zf, qd, 3.6, 2)
	# The patio by the back door.
	var px := x + qw * 0.5 + 3.0
	_flat_rect("drive", px - 2.6, px + 2.6, zf, zf + 5.0, 0.07)
	_box("paint", Vector3(1.8, 0.75, 0.8), Vector3(px, 0.4, zf + 2.6), Color("#7a5a3a"))
	_box("paint", Vector3(0.6, 0.9, 0.5), Vector3(px + 1.8, 0.45, zf + 1.0), Color("#2a2a2a"))
	# Crew cars park along the back.
	_flat_rect("asphalt", -w * 0.5 + 0.5, w * 0.5 - 0.5, z + g - 3.2, z + g - 0.3, 0.06)


## A city's emergency operations center: a two-storey precast office with
## a long window band to the command room, an antenna mast on the roof and
## the backup generator beside it.
func _eoc(w: float, z: float, g: float, brick: Color, trim: Color) -> void:
	var ew := w - 8.0
	var ed := g - 5.0
	var x := -4.0 + 0.0
	var zf := z + 1.5
	var precast := Color("#c9c4b6")
	_slab(x, ew, zf, ed)
	_flat_roofed_at("brick", x, ew, ed, zf + ed * 0.5, 7.4, 8.1, precast)
	_box("brick", Vector3(ew + 0.06, 1.2, ed + 0.06), Vector3(x, 0.6, zf + ed * 0.5), brick)
	_window_row(x, zf, ew - 2.0, 1.8, 1.3, 5, trim)
	_window_row(x, zf, ew - 2.0, 5.3, 1.6, 7, trim)
	_entry(x - ew * 0.3, zf, trim)
	var m := Vector3(x + ew * 0.3, 8.1, zf + ed * 0.6)
	_box("paint", Vector3(0.12, 9.0, 0.12), m + Vector3(0, 4.5, 0), GALV)
	for a in [3.0, 6.0, 8.5]:
		_box("paint", Vector3(0.9, 0.06, 0.06), m + Vector3(0, a, 0), GALV)
	_generator(Vector3(w * 0.5 - 4.0, 0, zf + ed * 0.5))
	_flat_rect("asphalt", -w * 0.5 + 0.5, w * 0.5 - 0.5, z + 0.2, zf - 0.2, 0.06)


## A standby diesel generator in its weather enclosure on a pad, a fuel
## tank under it (critical facilities keep 24-72 hours of fuel).
func _generator(p: Vector3) -> void:
	_box("paint", Vector3(4.2, 0.25, 2.2), p + Vector3(0, 0.12, 0), CONCRETE)
	_box("paint", Vector3(3.8, 0.6, 1.8), p + Vector3(0, 0.55, 0), Color("#3a3c3e"))  # belly tank
	_box("paint", Vector3(3.6, 1.7, 1.6), p + Vector3(0, 1.7, 0), Color("#d6d2c4"))
	_box("paint", Vector3(0.25, 0.6, 0.25), p + Vector3(1.4, 2.85, 0.3), Color("#3a3c3e"))  # exhaust
	for k in 3:
		_box("paint", Vector3(0.7, 1.0, 0.04), p + Vector3(-1.0 + k * 0.9, 1.8, -0.82), Color("#a9a597"))


## A sally port: the secure garage a patrol car drives into to bring
## someone in, its door to the yard and a man door to the booking room.
func _sally_port(w: float, z: float, g: float, brick: Color, trim: Color) -> void:
	var x := 3.0
	var sw := 9.0
	var sd := g - 2.0
	var zf := z + 1.0
	_slab(x, sw, zf, sd)
	_flat_roofed_at("brick", x, sw, sd, zf + sd * 0.5, 4.8, 5.4, brick)
	_overhead_door(x - 1.0, zf, 3.7, 3.4, Color("#9aa0a4"))
	_box("paint", Vector3(0.95, 2.1, 0.06), Vector3(x + 3.2, 1.35, zf - 0.03), Color("#5a5f66"))
	_box("paint", Vector3(sw + 0.1, 0.2, 0.14), Vector3(x, 4.5, zf - 0.07), trim)
	_flat_rect("asphalt", -14.5, 14.5, z, z + g - 0.2, 0.06)


## The evidence garage and impound lot: a steel building with an overhead
## door for towed cars to be searched in, and a gravel lot behind a tall
## fence with barbed wire.
func _evidence(w: float, z: float, g: float) -> void:
	var x := -w * 0.5 + 8.5
	var bw := 14.0
	var bd := 8.0
	var zf := z + 1.5
	_slab(x, bw, zf, bd)
	_flat_roofed_at("metal", x, bw, bd, zf + bd * 0.5, 4.6, 5.0, Color("#a9adb0"))
	_overhead_door(x - 3.0, zf, 3.7, 3.7, Color("#8f9599"))
	_box("paint", Vector3(0.95, 2.1, 0.06), Vector3(x + 4.0, 1.35, zf - 0.03), Color("#5a5f66"))
	_flat_rect("asphalt", -14.5, 14.5, z, zf, 0.06)
	var ix := x + bw * 0.5 + 1.5
	_flat_rect("gravel", ix, w * 0.5 - 0.8, z + 1.0, z + g - 0.6, 0.06, Color("#a49c8d"))
	_fence(Vector2(ix, z + 1.0), Vector2(w * 0.5 - 0.8, z + g - 0.6), 2.4, true)


## A K-9 kennel: a small block building with chain-link runs under a roof.
func _kennel(p: Vector3) -> void:
	_box("paint", Vector3(3.0, 2.6, 2.6), p + Vector3(1.5, 1.3, 1.3), Color("#c9c1ae"))
	_box("paint", Vector3(3.2, 0.12, 2.8), p + Vector3(1.5, 2.66, 1.3), Color("#6b6f73"))
	for k in 3:
		var r := p + Vector3(3.2 + k * 1.6, 0, 0)
		_flat_rect("drive", r.x, r.x + 1.5, r.z, r.z + 3.6, 0.07)
		_fence(Vector2(r.x, r.z), Vector2(r.x + 1.5, r.z + 3.6), 1.8)
		_box("paint", Vector3(1.6, 0.05, 1.6), r + Vector3(0.75, 1.9, 2.8), Color("#6b6f73"))


## A wing a growing clinic builds on behind (Stations): brick to the window
## heads with a stucco band, like the clinic, its own door under a canopy
## off the side drive. The pharmacy has a drive-through lane under a
## canopy, urgent care an ambulance-height canopy and a lit sign, dialysis
## a covered drop-off (patients come three times a week).
func _clinic_wing(w: float, z: float, g: float, what: String) -> void:
	var brick := Color(_pick(["#a8775c", "#b59a7c", "#8a4a38", "#c9c1ae"]))
	var eifs := Color(_pick(["#d9d3c3", "#e3ddd0", "#c9c1ae"]))
	var ww := w - 10.0 if what != "pharmacy" else 13.0
	var wd := g - 3.0
	var x := -w * 0.5 + 1.0 + ww * 0.5
	var zf := z + 1.0
	var h := 4.4
	_slab(x, ww, zf, wd)
	_flat_roofed_at("brick", x, ww, wd, zf + wd * 0.5, h, h + 0.6, brick)
	_box("paint", Vector3(ww + 0.06, 1.4, wd + 0.06), Vector3(x, h - 0.2, zf + wd * 0.5), eifs)
	# The side facing the drive (+x): windows and the door under a canopy.
	var side := x + ww * 0.5
	_window_row(side, zf + wd * 0.5, wd - 3.0, 1.6, 1.4, 3, eifs, Vector3.RIGHT)
	_glass(Vector3(side + 0.03, 1.4, zf + wd * 0.5), Vector3(0, 0, 1), 2.0, 2.4, 0.0)
	_box("paint", Vector3(2.6, 0.3, 3.4), Vector3(side + 1.3, 3.0, zf + wd * 0.5), eifs)
	_rooftop_units(x, ww, zf, wd, h, 1)
	_flat_rect("asphalt", side, w * 0.5 - 0.5, z, z + g - 0.3, 0.06)
	match what:
		"pharmacy":
			# The drive-through: a canopy on two posts over a lane along the
			# wing, the window under it.
			var lx := side + 2.2
			_box("paint", Vector3(4.4, 0.4, 6.0), Vector3(lx, 3.6, zf + wd * 0.5), eifs)
			for e in [-1.0, 1.0]:
				_box("paint", Vector3(0.3, 3.4, 0.3), Vector3(side + 4.1, 1.7, zf + wd * 0.5 + e * 2.6), eifs.darkened(0.1))
			_box("paint", Vector3(0.06, 1.0, 1.2), Vector3(side + 0.04, 1.3, zf + wd * 0.5 + 1.4), Color("#2a3a44"))
			_flat_rect("line", side + 4.3, side + 4.4, zf - 1.0, zf + wd + 1.0, 0.07, LINE)
			_sign(Vector3(x, h + 0.2, zf - 0.04), ww * 0.5, 0.6)
		"urgent_care":
			_box("paint", Vector3(5.0, 0.5, 6.5), Vector3(side + 2.5, 4.6, zf + wd * 0.5), eifs)
			for e in [-1.0, 1.0]:
				_box("paint", Vector3(0.35, 4.4, 0.35), Vector3(side + 4.8, 2.2, zf + wd * 0.5 + e * 3.0), eifs.darkened(0.1))
			_box("paint", Vector3(0.1, 0.8, 3.6), Vector3(side + 5.06, 4.6, zf + wd * 0.5), Color("#b8322a"))
		"dialysis":
			_box("paint", Vector3(4.0, 0.4, 7.0), Vector3(side + 2.0, 3.3, zf + wd * 0.5 + 0.5), eifs)
			for i in 3:
				_box("paint", Vector3(1.6, 0.45, 0.45), Vector3(side + 1.2, 0.45, zf + 1.5 + i * 2.5), Color("#6b5a48"))
		_:
			_sign(Vector3(x, h + 0.2, zf - 0.04), ww * 0.5, 0.6)
	var pick := TreeField.pick(rng, true)
	trees.append([Vector3(-w * 0.5 + 1.5, 0, z + g - 1.0), pick[0], pick[1], rng.randf_range(0.7, 0.9)])


## Portable classrooms (an Indiana school outgrowing its building leases
## modular classrooms, each a 24 x 36 ft double-wide): two tan-sided units
## on block piers, a wooden ramp with rails to each door, a wall-mounted
## heat pump and a covered walk back to the school.
func _portables(w: float, z: float, g: float) -> void:
	var side := Color(_pick(["#cdbf9e", "#d9cdb0", "#bfb59a"]))
	var trim := Color("#efede6")
	var uw := 11.0
	var ud := 7.3
	var floor := 0.75
	for i in 2:
		var c := Vector3(-w * 0.5 + 10.0 + i * 15.0, 0, z + 2.0 + ud * 0.5)
		for px in [-1.0, 0.0, 1.0]:
			for pz in [-1.0, 1.0]:
				_box("concrete", Vector3(0.4, floor, 0.4), c + Vector3(px * (uw * 0.5 - 0.6), floor * 0.5, pz * (ud * 0.5 - 0.6)), CONCRETE)
		_box("paint", Vector3(uw, 0.25, ud), c + Vector3(0, floor - 0.1, 0), DARK)
		_box("paint", Vector3(uw, 2.6, ud), c + Vector3(0, floor + 1.3, 0), side)
		_box("paint", Vector3(uw + 0.3, 0.18, ud + 0.3), c + Vector3(0, floor + 2.7, 0), Color("#d9d9d4"))
		_box("paint", Vector3(uw + 0.06, 0.2, ud + 0.06), c + Vector3(0, floor + 2.5, 0), trim)
		# Windows on the long sides, a door on the school side.
		for e in [-1.0, 1.0]:
			for k in 3:
				_glass(Vector3(c.x - 3.5 + k * 3.5, floor + 1.4, c.z + e * (ud * 0.5 + 0.03)), Vector3(-e, 0, 0), 1.2, 1.0, 0.3)
		_box("paint", Vector3(0.9, 2.0, 0.06), c + Vector3(uw * 0.5 - 1.6, floor + 1.0, -ud * 0.5 - 0.03), Color("#6e7a80"))
		_box("paint", Vector3(0.9, 0.7, 0.5), c + Vector3(-uw * 0.5 - 0.3, floor + 1.0, 0), Color("#c9c9c4"))
		# The ramp: 1:12, along the front to a landing at the door.
		var rz := c.z - ud * 0.5 - 0.9
		_box("wood", Vector3(1.6, 0.12, 1.6), Vector3(c.x + uw * 0.5 - 1.6, floor - 0.05, rz), Color("#a08a6a"))
		_box("wood", Vector3(6.0, 0.1, 1.2), Vector3(c.x + uw * 0.5 - 5.4, floor * 0.5, rz), Color("#a08a6a"),
			Basis(Vector3.BACK, -atan(floor / 6.0)))
		for e in [-1.0, 1.0]:
			_box("wood", Vector3(6.6, 0.06, 0.06), Vector3(c.x + uw * 0.5 - 5.2, floor * 0.5 + 0.9, rz + e * 0.6), Color("#8a7458"),
				Basis(Vector3.BACK, -atan(floor / 6.0)))
	# The walk back to the school's door, under a steel canopy.
	_flat_rect("drive", -w * 0.5 + 4.0, -w * 0.5 + 34.0, z, z + 1.6, 0.08)
	_box("paint", Vector3(30.0, 0.15, 2.2), Vector3(-w * 0.5 + 19.0, 2.6, z + 0.8), Color("#3a4a5a"))
	for i in 6:
		_box("paint", Vector3(0.12, 2.6, 0.12), Vector3(-w * 0.5 + 5.0 + i * 5.6, 1.3, z + 1.8), Color("#3a4a5a"))


## A pre-K wing (Indiana's On My Way Pre-K funds four-year-olds' seats in
## public schools): one storey of brick with big low windows, its own
## door and drop-off, and a fenced playground with soft surfacing.
func _prek_wing(w: float, z: float, g: float, brick: Color, trim: Color) -> void:
	var ww := 30.0
	var wd := g - 6.0
	var x := w * 0.5 - 4.0 - ww * 0.5
	var zf := z + 4.0  # clear of the ball diamond's backstop
	var h := 4.0
	_slab(x, ww, zf, wd)
	_flat_roofed_at("brick", x, ww, wd, zf + wd * 0.5, h, h + 0.5, brick)
	_ribbon_z(x - ww * 0.5, zf + 0.5, zf + wd - 0.5, Vector3.LEFT, Color("#d9a92a"), trim)
	_rooftop_units(x, ww, zf, wd, h, 1)
	# The playground beside it, fenced, on rubber tiles.
	var px0 := x - ww * 0.5 - 18.0
	var px1 := x - ww * 0.5 - 2.0
	_flat_rect("mulch", px0, px1, zf, zf + wd, 0.05, Color("#4a6a8a"))
	_play_set(Vector3(px0 + 4.0, 0, zf + wd * 0.5))
	for e in [[Vector3(px0, 0, zf), Vector3(px1, 0, zf)], [Vector3(px0, 0, zf + wd), Vector3(px1, 0, zf + wd)],
			[Vector3(px0, 0, zf), Vector3(px0, 0, zf + wd)]]:
		_fence_run(e[0], e[1], 1.2)


## A classroom addition: two storeys of brick (eight classrooms, about
## 12,000 sq ft) with ribbon windows on both floors, joined to the school
## by a glass link, a stair tower at its end.
func _school_addition(w: float, z: float, g: float, brick: Color, trim: Color) -> void:
	var panel := Color(_pick(["#3a5a6e", "#6e3a2e", "#3b4a3a", "#c9b27a"]))
	var ww := 44.0
	var wd := g - 6.0
	var x := -w * 0.5 + 6.0 + ww * 0.5
	var zf := z + 3.0
	var h := 8.2
	_slab(x, ww, zf, wd)
	_flat_roofed_at("brick", x, ww, wd, zf + wd * 0.5, h, h + 0.6, brick)
	for f in 2:
		_ribbon_lift(x - ww * 0.5, x + ww * 0.5, zf, Vector3.FORWARD, panel, trim, f * 3.9)
		_ribbon_lift(x - ww * 0.5, x + ww * 0.5, zf + wd, Vector3.BACK, panel, trim, f * 3.9)
	# Stair tower, a little taller, glass up its face.
	_box("brick", Vector3(5.0, h + 2.0, 5.0), Vector3(x + ww * 0.5 + 2.5, (h + 2.0) * 0.5, zf + wd * 0.5), brick.darkened(0.08))
	_glass(Vector3(x + ww * 0.5 + 5.03, h * 0.5 + 0.5, zf + wd * 0.5), Vector3(0, 0, -1), 2.0, h - 1.0, 0.0)
	_glass(Vector3(-22.0, 1.4, zf - 0.03), Vector3(-1, 0, 0), 2.4, 2.6, 0.0)
	_rooftop_units(x, ww - 6.0, zf, wd, h, 3)


## A covered walk from the school's back door out to what it added: a
## concrete path under a flat steel canopy on posts, as schools run out to
## their portables and detached wings.
func _covered_walk(x: float, z0: float, z1: float) -> void:
	if z1 - z0 < 2.0:
		return
	var steel := Color("#3a4a5a")
	_flat_rect("drive", x - 1.1, x + 1.1, z0, z1, 0.085)
	_box("paint", Vector3(2.6, 0.15, z1 - z0), Vector3(x, 2.7, (z0 + z1) * 0.5), steel)
	var n := maxi(1, int((z1 - z0) / 5.0))
	for i in n + 1:
		_box("paint", Vector3(0.12, 2.7, 0.12), Vector3(x + 1.2, 1.35, z0 + 0.3 + (z1 - z0 - 0.6) * i / n), steel)


## A second (auxiliary) gym for practices and community leagues: a tall
## brick box with clerestory windows high up, double doors and a canopy.
func _aux_gym(w: float, z: float, g: float, brick: Color, trim: Color) -> void:
	var ww := 34.0
	var wd := g - 4.0
	var x := w * 0.5 - 4.0 - ww * 0.5
	var zf := z + 2.0
	var h := 9.0
	_slab(x, ww, zf, wd)
	_flat_roofed_at("brick", x, ww, wd, zf + wd * 0.5, h, h + 0.6, brick)
	_box("paint", Vector3(ww + 0.06, 0.5, wd + 0.06), Vector3(x, h - 0.6, zf + wd * 0.5), trim)
	for e in [-1.0, 1.0]:
		for i in 4:
			_glass(Vector3(x + e * (ww * 0.5 + 0.03), 7.0, zf + 3.0 + i * (wd - 6.0) / 3.0), Vector3(0, 0, -e), 3.0, 1.0, 0.0)
	_box("paint", Vector3(3.2, 2.4, 0.06), Vector3(x, 1.2, zf - 0.03), Color("#5a6e7a"))
	_box("paint", Vector3(5.0, 0.3, 2.4), Vector3(x, 3.1, zf - 1.2), trim)
	_rooftop_units(x, ww - 8.0, zf, wd, h, 2)
	_flat_rect("drive", x - 2.0, x + 2.0, z, zf, 0.08)


## A ribbon of windows (as _ribbon) raised `lift` metres, for upper floors.
func _ribbon_lift(x0: float, x1: float, z: float, out: Vector3, panel: Color, trim: Color, lift: float) -> void:
	var right := Vector3(-1, 0, 0) if out.z < 0.0 else Vector3(1, 0, 0)
	var step := 3.0
	var x := x0 + 0.6
	while x + step <= x1 - 0.6:
		var c := x + step * 0.5
		_glass(Vector3(c, 2.45 + lift, z + out.z * 0.03), right, step - 0.15, 1.5, rng.randf_range(0.0, 0.5))
		_box("paint", Vector3(step - 0.15, 0.85, 0.06), Vector3(c, 1.15 + lift, z + out.z * 0.03), panel)
		x += step
	_box("paint", Vector3(x1 - x0 - 1.0, 0.12, 0.14), Vector3((x0 + x1) * 0.5, 3.24 + lift, z + out.z * 0.07), trim)


## A nursing home's or daycare's piece (HealthBuilder draws them).
func _care_piece(_key: String, _w: float, _z: float, _g: float) -> void:
	pass


## The 911 center's radio tower: a self-supporting lattice about 45 m high,
## its equipment shelter and generator at the foot.
func _dispatch_tower(p: Vector3) -> void:
	var steel := Color("#9a9d9f")
	var tall := 45.0
	var parts := 12
	_box("paint", Vector3(3.2, 0.4, 3.2), p + Vector3(0, 0.2, 0), CONCRETE)
	for k in parts:
		var y0 := tall * k / parts
		var y1 := tall * (k + 1) / parts
		var half := lerpf(1.3, 0.3, (y0 + y1) * 0.5 / tall)
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 1)]:
			_box("paint", Vector3(0.1, y1 - y0, 0.1), p + Vector3(c.x * half, (y0 + y1) * 0.5, c.y * half), steel)
		_box("paint", Vector3(half * 2.0, 0.07, 0.07), p + Vector3(0, y1, -half), steel)
	for a in [14.0, 28.0, 38.0]:
		_box("paint", Vector3(0.6, 1.6, 0.2), p + Vector3(0, a, -0.6), Color("#e8e8e2"))
	_box("paint", Vector3(0.25, 0.5, 0.25), p + Vector3(0, tall + 0.25, 0), Color("#c43b2f"))
	_box("paint", Vector3(2.4, 2.6, 3.0), p + Vector3(-3.4, 1.3, -0.5), Color("#c9c1ae"))


# ---------------------------------------------------------------- traffic center

## A small city's traffic management center: a two-storey office in brick
## and glass, the engineers' video wall behind a long upper window band,
## and a lattice radio mast out back that talks to the signal cabinets.
func _traffic_center(front: float, to_curb: float) -> void:
	var brick := Color(_pick(["#9b5a42", "#b59a7c", "#8a6a54", "#c9c1ae"]))
	var trim := Color(_pick(["#3a3530", "#d9d3c3", "#5a5f66"]))
	var w := rng.randf_range(20.0, 22.0)
	var d := rng.randf_range(13.0, 15.0)
	var zf := front + 14.0
	var h := 7.6
	_slab(0.0, w, zf, d)
	_flat_roofed_at("brick", 0.0, w, d, zf + d * 0.5, h, h + 0.7, brick)
	_box("paint", Vector3(w + 0.1, 0.3, 0.16), Vector3(0, h - 0.3, zf - 0.08), trim)
	_box("paint", Vector3(w + 0.1, 0.2, 0.14), Vector3(0, 3.7, zf - 0.07), trim)
	var ex := rng.randf_range(-w * 0.2, w * 0.2)
	_vestibule(ex, zf, 4.2, 2.6, 3.4)
	_sign(Vector3(ex, 3.45, zf - 2.75), 3.6, 0.5)
	# Ground floor: offices either side of the door; upstairs, the control
	# room's long window band.
	_window_row(ex - 2.1 - (w * 0.5 + ex - 2.1) * 0.5, zf, w * 0.5 + ex - 3.5, 1.6, 1.2, 3, trim)
	_window_row(ex + 2.1 + (w * 0.5 - ex - 2.1) * 0.5, zf, w * 0.5 - ex - 3.5, 1.6, 1.2, 3, trim)
	_window_row(0.0, zf, w - 2.0, 5.5, 1.4, 6, trim)
	for side in [-1.0, 1.0]:
		_window_row(side * w * 0.5, zf + d * 0.5, d * 0.6, 1.6, 1.2, 3, trim, Vector3(side, 0, 0))
		_window_row(side * w * 0.5, zf + d * 0.5, d * 0.6, 5.5, 1.2, 3, trim, Vector3(side, 0, 0))
	# Rooftop units.
	for i in 2:
		_box("paint", Vector3(2.2, 1.1, 1.6), Vector3(-w * 0.25 + i * w * 0.4, h + 1.2, zf + d * 0.6), Color("#b8b8b2"))
	# The radio mast: a tapering three-legged lattice, about 30 m.
	var mx := w * 0.5 - 2.5
	var mz := zf + d + 2.4
	var steel := Color("#9a9d9f")
	_box("paint", Vector3(2.6, 0.4, 2.6), Vector3(mx, 0.2, mz), Color("#a8a49a"))
	var tall := 30.0
	var parts := 10
	for k in parts:
		var y0 := tall * k / parts
		var y1 := tall * (k + 1) / parts
		var half := lerpf(0.9, 0.25, (y0 + y1) * 0.5 / tall)
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 1)]:
			_box("paint", Vector3(0.09, y1 - y0, 0.09), Vector3(mx + c.x * half, (y0 + y1) * 0.5, mz + c.y * half), steel)
		_box("paint", Vector3(half * 2.0, 0.06, 0.06), Vector3(mx, y1, mz - half), steel)
	for a in [8.0, 18.0, 26.0]:
		_box("paint", Vector3(0.7, 0.7, 0.2), Vector3(mx, a, mz - 0.5), Color("#e8e8e2"))
	_box("paint", Vector3(0.2, 0.4, 0.2), Vector3(mx, tall + 0.2, mz), Color("#c43b2f"))
	_parking(-14.5, 14.5, front + 0.3, zf - 3.0, to_curb, -9.0)
	_flat_rect("drive", -w * 0.5, w * 0.5, zf - 3.0, zf, 0.08)
	_flat_rect("asphalt", -14.5, 14.5, zf + d, 17.8, 0.06)
	_flagpole(Vector3(ex - 4.5, 0, zf - 4.0))
	_bed(ex + 3.2, zf - 2.0, 3.0)


# ---------------------------------------------------------------- clinic

func _clinic(front: float, to_curb: float) -> void:
	var brick := Color(_pick(["#a8775c", "#b59a7c", "#8a4a38", "#c9c1ae"]))
	var eifs := Color(_pick(["#d9d3c3", "#e3ddd0", "#c9c1ae", "#b8b2a4"]))
	var w := rng.randf_range(19.0, 22.0)
	var d := rng.randf_range(12.0, 13.0)
	var zf := front + 15.0
	var h := 4.6
	_slab(0.0, w, zf, d)
	# Brick to the window heads, a stucco (EIFS) band above, flat roof.
	_flat_roofed_at("brick", 0.0, w, d, zf + d * 0.5, h, h + 0.6, brick)
	_box("paint", Vector3(w + 0.06, 1.6, d + 0.06), Vector3(0, h - 0.2, zf + d * 0.5), eifs)
	_box("paint", Vector3(w + 0.1, 0.1, d + 0.1), Vector3(0, h - 1.0, zf + d * 0.5), eifs.darkened(0.15))
	var ex := rng.randf_range(-w * 0.25, w * 0.25)
	# Storefront entry and a drive-under canopy on two columns.
	for i in 4:
		var x := ex - 3.0 + (i + 0.5) * 1.5
		_glass(Vector3(x, 1.5, zf - 0.03), Vector3(-1, 0, 0), 1.4, 2.6 if i == 1 or i == 2 else 2.2, 0.0)
		_box("paint", Vector3(0.08, 2.9, 0.12), Vector3(x - 0.75, 1.45, zf - 0.06), MULLION[1])
	_box("paint", Vector3(6.6, 0.5, 6.0), Vector3(ex, 3.75, zf - 3.0), eifs)
	_box("paint", Vector3(6.4, 0.04, 5.8), Vector3(ex, 3.49, zf - 3.0), SOFFIT)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.4, 3.5, 0.4), Vector3(ex + s * 2.9, 1.75, zf - 5.6), eifs)
	_sign(Vector3(ex, 4.0, zf - 6.02), 4.0, 0.5)
	_flat_rect("drive", ex - 3.3, ex + 3.3, zf - 6.0, zf, 0.09)
	_window_row(ex - 3.5 - (w * 0.5 + ex - 3.5) * 0.5, zf, w * 0.5 + ex - 4.5, 1.6, 1.5, 3, eifs)
	_window_row(ex + 3.5 + (w * 0.5 - ex - 3.5) * 0.5, zf, w * 0.5 - ex - 4.5, 1.6, 1.5, 3, eifs)
	for s in [-1.0, 1.0]:
		_window_row(s * w * 0.5, zf + d * 0.5, d * 0.7, 1.6, 1.4, 4, eifs, Vector3(s, 0, 0))
	_rooftop_units(0.0, w, zf, d, h + 0.0, 2)
	_parking(-14.5, 14.5, front + 0.3, zf - 6.0, to_curb, -11.0)
	_bed(ex - 5.0, zf - 1.0, 4.0)
	_bed(ex + 5.0, zf - 1.0, 4.0)
	for i in 2:
		var pick := TreeField.pick(rng, true)
		trees.append([Vector3((i * 2 - 1) * 13.0, 0, zf + d + 2.0), pick[0], pick[1], rng.randf_range(0.7, 0.95)])


# ---------------------------------------------------------------- school

func _school(front: float, to_curb: float) -> void:
	var brick := Color(_pick(["#8a4a38", "#9b5a42", "#a8775c", "#b59a7c"]))
	var trim := Color(_pick(["#d9d3c3", "#cfc8b6", "#efede6"]))
	var panel := Color(_pick(["#3a5a6e", "#6e3a2e", "#3b4a3a", "#c9b27a"]))
	var h := 4.4
	# Front classroom wing along the street.
	var z0 := front + 22.0
	var wd := 12.0
	_slab(0.0, 56.0, z0, wd)
	_flat_roofed_at("brick", 0.0, 56.0, wd, z0 + wd * 0.5, h, h + 0.5, brick)
	# Back wing (classrooms) off the left end.
	var bx := -22.0
	_slab(bx, 12.0, z0 + wd, 36.0)
	_flat_roofed_at("brick", bx, 12.0, 36.0, z0 + wd + 18.0, h, h + 0.5, brick)
	# Gym and cafeteria: a taller block behind the right half.
	var gx := 16.0
	var gz := z0 + wd
	_slab(gx, 22.0, gz, 24.0)
	_flat_roofed_at("brick", gx, 22.0, 24.0, gz + 12.0, 8.2, 8.8, brick)
	for s in [-1.0, 1.0]:
		for i in 3:
			_glass(Vector3(gx + s * 11.02, 7.0, gz + 5.0 + i * 7.0), Vector3(0, 0, -s), 4.5, 1.0, 0.0)
	# Ribbon windows with coloured panels below, front and back of the wings.
	_ribbon(-27.0, 27.0, z0, Vector3.FORWARD, panel, trim, 5.0)
	_ribbon(-27.0, 4.5, z0 + wd, Vector3.BACK, panel, trim, 0.0)
	_ribbon_z(bx + 6.0, z0 + wd + 1.0, z0 + wd + 35.0, Vector3.RIGHT, panel, trim)
	_ribbon_z(bx - 6.0, z0 + 1.0, z0 + wd + 35.0, Vector3.LEFT, panel, trim)
	# Main entrance: a glass bay under a flat canopy, the sign above.
	var ex := 5.0
	_box("brick", Vector3(9.0, 5.6, 2.0), Vector3(ex, 2.8, z0 - 1.0), brick.darkened(0.08))
	for i in 4:
		_glass(Vector3(ex - 3.0 + i * 2.0, 1.5, z0 - 2.03), Vector3(-1, 0, 0), 1.8, 2.6, 0.0)
	_box("paint", Vector3(10.0, 0.4, 5.0), Vector3(ex, 3.3, z0 - 4.4), trim)
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(0.3, 3.1, 0.3), Vector3(ex + s * 4.6, 1.55, z0 - 6.6), DARK)
	_sign(Vector3(ex, 4.2, z0 - 2.05), 7.0, 0.7)
	_rooftop_units(0.0, 50.0, z0, wd, h, 4)
	_rooftop_units(gx, 18.0, gz, 24.0, 8.2, 2)
	# Bus loop and staff parking in front, the walk to the doors.
	_flat_rect("asphalt", -38.0, 38.0, front + 3.0, front + 10.0, 0.06)
	_curb_cut(-34.5, 3.5, front - to_curb, front + 3.0)
	_curb_cut(34.5, 3.5, front - to_curb, front + 3.0)
	_flat_rect("drive", -38.0, 38.0, front + 10.0, front + 12.0, 0.08)
	_flat_rect("drive", ex - 4.0, ex + 4.0, front + 12.0, z0, 0.08)
	var x := 12.0
	while x <= 37.0:
		_flat_rect("line", x - 0.06, x + 0.06, front + 12.0, front + 17.5, 0.07, LINE)
		x += 2.75
	_flat_rect("asphalt", 11.0, 37.5, front + 12.0, front + 17.5, 0.065)
	_flagpole(Vector3(ex - 8.0, 0, front + 16.0))
	# Blacktop playground with equipment, and the ball diamond.
	_flat_rect("asphalt", -15.0, 4.0, z0 + wd + 2.0, z0 + wd + 22.0, 0.06)
	_flat_rect("mulch", -14.0, -4.0, z0 + wd + 24.0, z0 + wd + 34.0, 0.05, Color("#8a6a48"))
	_play_set(Vector3(-9.0, 0, z0 + wd + 29.0))
	for i in 2:
		_hoop(Vector3(-11.0 + i * 11.0, 0, z0 + wd + 4.0))
	# (Placed from the front: a grown school's lot reaches further back.)
	_diamond(Vector3(22.0, 0, front + 96.0))
	for i in 6:
		var pick := TreeField.pick(rng, true)
		trees.append([Vector3(-36.0 + i * 3.0 + rng.randf_range(-1.0, 1.0), 0, front + 19.0 + rng.randf_range(0.0, 2.0)) if i < 3
			else Vector3(rng.randf_range(-38.0, -30.0), 0, front + rng.randf_range(60.0, 95.0)), pick[0], pick[1], rng.randf_range(0.8, 1.1)])


func _ribbon(x0: float, x1: float, z: float, out: Vector3, panel: Color, trim: Color, gap: float) -> void:
	var right := Vector3(-1, 0, 0) if out.z < 0.0 else Vector3(1, 0, 0)
	var step := 3.0
	var x := x0 + 0.6
	while x + step <= x1 - 0.6:
		var c := x + step * 0.5
		if absf(c - 5.0) > gap:
			_glass(Vector3(c, 2.45, z + out.z * 0.03), right, step - 0.15, 1.5, rng.randf_range(0.0, 0.5))
			_box("paint", Vector3(step - 0.15, 0.85, 0.06), Vector3(c, 1.15, z + out.z * 0.03), panel)
			_box("paint", Vector3(0.12, 2.5, 0.1), Vector3(x, 2.0, z + out.z * 0.06), trim)
		x += step
	_box("paint", Vector3(x1 - x0 - 1.0, 0.12, 0.14), Vector3((x0 + x1) * 0.5, 3.24, z + out.z * 0.07), trim)


func _ribbon_z(x: float, z0: float, z1: float, out: Vector3, panel: Color, trim: Color) -> void:
	var right := Vector3(0, 0, -1) if out.x > 0.0 else Vector3(0, 0, 1)
	var step := 3.0
	var z := z0 + 0.6
	while z + step <= z1 - 0.6:
		var c := z + step * 0.5
		_glass(Vector3(x + out.x * 0.03, 2.45, c), right, step - 0.15, 1.5, rng.randf_range(0.0, 0.5))
		_box("paint", Vector3(0.06, 0.85, step - 0.15), Vector3(x + out.x * 0.03, 1.15, c), panel)
		_box("paint", Vector3(0.1, 2.5, 0.12), Vector3(x + out.x * 0.06, 2.0, z), trim)
		z += step


func _play_set(p: Vector3) -> void:
	var red := Color("#b83a2a")
	var blue := Color("#2f5a8a")
	var yel := Color("#d9a92a")
	_box("paint", Vector3(2.6, 0.12, 2.6), p + Vector3(0, 1.6, 0), blue)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box("paint", Vector3(0.12, 3.2, 0.12), p + Vector3(sx * 1.25, 1.6, sz * 1.25), yel)
	_box("paint", Vector3(2.8, 0.15, 2.8), p + Vector3(0, 3.2, 0), red)
	_box("paint", Vector3(0.8, 0.06, 3.4), p + Vector3(0.6, 0.85, 2.9), yel, Basis(Vector3.RIGHT, -0.5))
	# A swing set.
	var s := p + Vector3(5.0, 0, 0)
	_box("paint", Vector3(0.1, 0.1, 4.5), s + Vector3(0, 2.4, 0), DARK)
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			_box("paint", Vector3(0.08, 2.6, 0.08), s + Vector3(sx * 0.6, 1.2, sz * 2.2), DARK, Basis(Vector3.BACK, sx * 0.25))
	for i in 3:
		_box("paint", Vector3(0.25, 0.04, 0.5), s + Vector3(0, 0.55, -1.4 + i * 1.4), DARK)


func _hoop(p: Vector3) -> void:
	_box("paint", Vector3(0.14, 3.2, 0.14), p + Vector3(0, 1.6, -0.6), DARK)
	_box("paint", Vector3(1.8, 1.1, 0.05), p + Vector3(0, 3.35, -0.45), WHITE)
	_box("paint", Vector3(0.46, 0.03, 0.46), p + Vector3(0, 3.05, -0.15), Color("#c05a28"))
	_flat_rect("line", p.x - 2.5, p.x + 2.5, p.z + 5.6, p.z + 5.7, 0.07, LINE)


func _diamond(home: Vector3) -> void:
	# Little League: 60 ft bases, the field opening toward -z.
	var base := 18.3
	var dir1 := Vector3(0.7071, 0, -0.7071)
	var dir3 := Vector3(-0.7071, 0, -0.7071)
	var first := home + dir1 * base
	var third := home + dir3 * base
	var second := first + dir3 * base
	# Skinned infield: a fan out to an arc beyond the bases, grass inside.
	var fan := [home + Vector3(0, 0, 2.5)]
	for i in 13:
		var a := lerpf(-PI * 0.25, PI * 0.25, i / 12.0)
		fan.append(home + Vector3(sin(a), 0, -cos(a)) * 29.0)
	_flat_poly(fan, 0.05, DIRT)
	_flat_poly([home + Vector3(0, 0, -3.5), first - dir1 * 1.5 + dir3 * 1.2, second + Vector3(0, 0, 3.0), third - dir3 * 1.5 + dir1 * 1.2], 0.055, Color("#4f7a34"))
	_flat_poly([home + Vector3(0, 0, 2.0), home + Vector3(2.2, 0, 0), home + Vector3(0, 0, -2.2), home + Vector3(-2.2, 0, 0)], 0.056, DIRT)
	var mound := home + Vector3(0, 0, -14.0)
	var ring := []
	for i in 10:
		ring.append(mound + Vector3(cos(TAU * i / 10.0), 0, sin(TAU * i / 10.0)) * 2.7)
	_flat_poly(ring, 0.057, DIRT)
	for p in [first, second, third]:
		_box("paint", Vector3(0.4, 0.08, 0.4), p + Vector3(0, 0.08, 0), WHITE)
	_box("paint", Vector3(0.45, 0.05, 0.45), home + Vector3(0, 0.06, 0), WHITE)
	# Backstop: posts and rails curving behind home plate.
	for i in 5:
		var t := lerpf(-1.1, 1.1, i / 4.0)
		var p := home + Vector3(sin(t), 0, cos(t)) * 6.0
		_box("paint", Vector3(0.1, 4.0, 0.1), p + Vector3(0, 2.0, 0), GALV)
		if i < 4:
			var t2 := lerpf(-1.1, 1.1, (i + 1) / 4.0)
			var q := home + Vector3(sin(t2), 0, cos(t2)) * 6.0
			for y in [4.0, 2.2, 0.15]:
				_strut(p + Vector3(0, y, 0), q + Vector3(0, y, 0), 0.05, GALV)
	# Team benches on the base lines.
	for d in [dir1, dir3]:
		var b: Vector3 = home + d * 9.0 + Vector3(d.x, 0, 0).normalized() * 4.0
		_box("paint", Vector3(0.5, 0.45, 4.0), b + Vector3(0, 0.25, 0), GALV, Basis(Vector3.UP, atan2(d.x, d.z)))


# ---------------------------------------------------------------- substation

func _substation(front: float, to_curb: float) -> void:
	_flat_rect("gravel", -13.0, 13.0, front + 2.0, front + 28.0, 0.05, Color("#8d877c"))
	_flat_rect("gravel", -2.5, 2.5, front - to_curb, front + 2.0, 0.09, Color("#8d877c"))
	_fence(Vector2(-13.0, front + 2.0), Vector2(13.0, front + 28.0), 2.4, true)
	# Incoming line: a tall H-frame dead-end structure at the back.
	var zb := front + 25.0
	for x in [-7.0, 7.0]:
		_lattice(Vector3(x, 0, zb), 11.0)
	_box("metal", Vector3(15.0, 0.5, 0.5), Vector3(0, 10.7, zb), GALV)
	for x in [-4.0, 0.0, 4.0]:
		_insulator(Vector3(x, 10.4, zb), -1.0)
		_box("paint", Vector3(0.04, 0.04, 12.0), Vector3(x, 10.0, zb + 6.0), DARK)  # conductors out
	# Two power transformers with radiators and bushings.
	for i in 2:
		var x := -5.0 + i * 10.0
		var z := front + 15.0
		_box("paint", Vector3(14.0 * 0.25, 0.5, 4.6), Vector3(x, 0.25, z), CONCRETE)
		_box("metal", Vector3(2.6, 2.8, 3.2), Vector3(x, 1.9, z), Color("#8e968f"))
		for s in [-1.0, 1.0]:
			for k in 5:
				_box("metal", Vector3(0.6, 2.2, 0.08), Vector3(x + s * 1.65, 1.8, z - 1.2 + k * 0.6), Color("#7f8780"))
		_cyl_y(Vector3(x, 3.3, z + 1.0), 0.45, 1.2, Color("#8e968f"))  # conservator
		for k in 3:
			_insulator(Vector3(x - 0.8 + k * 0.8, 3.3, z - 0.8), 1.0)
		# Bus from the dead-end frame.
		_box("paint", Vector3(0.08, 0.08, zb - z - 1.0), Vector3(x, 6.3, (zb + z) * 0.5 + 0.5), GALV)
	# Low bus stands with breakers in front.
	for x in [-8.0, -4.0, 4.0, 8.0]:
		var z := front + 8.0
		_box("metal", Vector3(0.3, 4.0, 0.3), Vector3(x, 2.0, z), GALV)
		_box("metal", Vector3(1.4, 1.8, 1.0), Vector3(x, 2.2, z - 1.0), Color("#b9bcbc"))
		_insulator(Vector3(x, 4.0, z), 1.0)
	_box("paint", Vector3(17.0, 0.12, 0.12), Vector3(0, 4.8, front + 8.0), GALV)
	# Control house.
	_box("paint", Vector3(5.0, 0.3, 3.6), Vector3(9.5, 0.15, front + 4.5), CONCRETE)
	_box("brick", Vector3(4.6, 3.0, 3.2), Vector3(9.5, 1.8, front + 4.5), Color(_pick(["#b8b2a4", "#a49d8f", "#8a4a38"])))
	_box("paint", Vector3(4.9, 0.15, 3.5), Vector3(9.5, 3.35, front + 4.5), Color("#cfcbc2"))
	_steel_door(Vector3(8.6, 1.35, front + 2.88), -1.0)
	_sign(Vector3(-1.6, 1.2, front + 1.9), 1.2, 0.4)


func _lattice(p: Vector3, h: float) -> void:
	var w := 0.9
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box("metal", Vector3(0.12, h, 0.12), p + Vector3(sx * w * 0.5, h * 0.5, sz * w * 0.5), GALV)
	var n := int(h / 1.2)
	for i in n:
		var y := 0.6 + i * 1.2
		var rot := Basis(Vector3.BACK, 0.9 if i % 2 == 0 else -0.9)
		_box("metal", Vector3(1.3, 0.05, 0.05), p + Vector3(0, y, -w * 0.5), GALV, rot)
		_box("metal", Vector3(1.3, 0.05, 0.05), p + Vector3(0, y, w * 0.5), GALV, rot)
		var rot2 := Basis(Vector3.RIGHT, 0.9 if i % 2 == 0 else -0.9)
		_box("metal", Vector3(0.05, 0.05, 1.3), p + Vector3(-w * 0.5, y, 0), GALV, rot2)
		_box("metal", Vector3(0.05, 0.05, 1.3), p + Vector3(w * 0.5, y, 0), GALV, rot2)


## A stack of porcelain sheds pointing up (dir 1) or hanging down (-1).
func _insulator(p: Vector3, dir: float) -> void:
	for i in 4:
		_cyl_y(p + Vector3(0, dir * (0.12 + i * 0.16), 0), 0.13, 0.08, Color("#6b4a36"))
	_cyl_y(p + Vector3(0, dir * 0.35, 0), 0.05, 0.7, Color("#6b4a36"))


# ---------------------------------------------------------------- water

func _water_tower(front: float, to_curb: float) -> void:
	var tank := Color(_pick(["#e9e7e0", "#dfe6ea", "#cfdde6", "#e2e4e2"]))
	var legs := 4 if rng.randf() < 0.5 else 6
	var r_top := 6.2
	var r_base := 8.2
	var top := 30.0
	var c := Vector3(0, 0, front + 15.0)
	var tops := []
	var bases := []
	for i in legs:
		var a := TAU * i / legs + PI / legs
		tops.append(c + Vector3(cos(a), 0, sin(a)) * r_top + Vector3(0, top, 0))
		bases.append(c + Vector3(cos(a), 0, sin(a)) * r_base)
	for i in legs:
		_strut(bases[i], tops[i], 0.75, tank)
		_box("paint", Vector3(1.6, 0.6, 1.6), bases[i] + Vector3(0, 0.3, 0), CONCRETE)
	# Horizontal balcony struts and X-rod bracing between the legs.
	for lvl in [10.0, 20.0]:
		for i in legs:
			var j := (i + 1) % legs
			_strut(_leg_at(bases[i], tops[i], lvl), _leg_at(bases[j], tops[j], lvl), 0.25, tank)
	for lv in [[0.0, 10.0], [10.0, 20.0], [20.0, top]]:
		for i in legs:
			var j := (i + 1) % legs
			_strut(_leg_at(bases[i], tops[i], lv[0]), _leg_at(bases[j], tops[j], lv[1]), 0.07, tank.darkened(0.2))
			_strut(_leg_at(bases[j], tops[j], lv[0]), _leg_at(bases[i], tops[i], lv[1]), 0.07, tank.darkened(0.2))
	_cyl_y(c + Vector3(0, top * 0.5, 0), 1.0, top, tank)  # riser pipe
	# The tank: an ellipsoid on a short cylinder, a catwalk round the equator,
	# and a shallow cone roof with a vent.
	var y0 := top - 2.0
	var prof := []
	for i in 7:
		var t := PI * 0.5 * i / 6.0
		prof.append(Vector2(sin(t) * 9.0, y0 + 6.5 * (1.0 - cos(t))))
	prof.append(Vector2(9.0, y0 + 10.0))
	for i in 5:
		var t := PI * 0.5 * (i + 1) / 5.0
		prof.append(Vector2(9.0 * cos(t * 0.6) - 0.0, y0 + 10.0 + sin(t) * 3.2))
	prof.append(Vector2(0.6, y0 + 14.0))
	_lathe(c, prof, tank, 28)
	var cw := y0 + 6.5
	_ring(c, cw, 9.0, 10.3, 0.12, GALV.darkened(0.2))
	_ring_rail(c, cw + 1.1, 10.2, GALV.darkened(0.2))
	_cyl_y(c + Vector3(0, y0 + 14.5, 0), 0.35, 1.2, tank.darkened(0.1))
	# A ladder up one leg.
	_strut(bases[0] + Vector3(0.6, 0, 0), tops[0] + Vector3(0.6, 0, 0), 0.08, DARK)
	# Pump house and its drive.
	var px := 9.0
	var pz := front + 4.5
	_box("paint", Vector3(7.4, 0.3, 5.4), Vector3(px, 0.15, pz), CONCRETE)
	_box("brick", Vector3(7.0, 3.2, 5.0), Vector3(px, 1.9, pz), Color(_pick(["#8a4a38", "#a8775c", "#b8b2a4"])))
	_metal_roof(px, pz, 3.5, 7.0, 5.0, Color(_pick(["#7a7874", "#3e5a48", "#5a2a26"])))
	_steel_door(Vector3(px - 1.8, 1.35, pz - 2.53), -1.0)
	_flat_rect("gravel", px - 3.0, px + 3.0, front - to_curb, pz - 2.7, 0.08, Color("#8d877c"))
	_fence(Vector2(-13.5, front + 1.5), Vector2(13.5, front + 28.0), 2.0)


func _leg_at(base: Vector3, top: Vector3, y: float) -> Vector3:
	return base.lerp(top, y / top.y)


## A square bar from a to b.
func _strut(a: Vector3, b: Vector3, t: float, col: Color) -> void:
	var d := b - a
	var len := d.length()
	var y := d / len
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_box("paint", Vector3(t, len, t), (a + b) * 0.5, col, Basis(x, y, z))


## A surface of revolution about the vertical axis through `c`; profile
## points are (radius, height), bottom to top.
func _lathe(c: Vector3, prof: Array, col: Color, segs: int) -> void:
	for k in prof.size() - 1:
		var p0: Vector2 = prof[k]
		var p1: Vector2 = prof[k + 1]
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var v := [
				c + Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x), c + Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x),
				c + Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x), c + Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)]
			var mid: Vector3 = (v[0] + v[2]) * 0.5
			var out := Vector3(mid.x - c.x, 0, mid.z - c.z) * (p1.y - p0.y) + Vector3(0, -(p1.x - p0.x), 0) * mid.distance_to(Vector3(c.x, mid.y, c.z))
			_quad("paint", v[0], v[1], v[2], v[3], col, [], out)


func _ring(c: Vector3, y: float, r0: float, r1: float, t: float, col: Color) -> void:
	var segs := 28
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_quad("paint", c + d0 * r0 + Vector3(0, y, 0), c + d1 * r0 + Vector3(0, y, 0),
			c + d1 * r1 + Vector3(0, y, 0), c + d0 * r1 + Vector3(0, y, 0), col, [], Vector3.UP)
		_quad("paint", c + d0 * r0 + Vector3(0, y - t, 0), c + d1 * r0 + Vector3(0, y - t, 0),
			c + d1 * r1 + Vector3(0, y - t, 0), c + d0 * r1 + Vector3(0, y - t, 0), col, [], Vector3.DOWN)


func _ring_rail(c: Vector3, y: float, r: float, col: Color) -> void:
	var segs := 28
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := c + Vector3(cos(a0) * r, y, sin(a0) * r)
		var p1 := c + Vector3(cos(a1) * r, y, sin(a1) * r)
		_strut(p0, p1, 0.06, col)
		_box("paint", Vector3(0.05, 1.1, 0.05), p0 - Vector3(0, 0.55, 0), col)


# ---------------------------------------------------------------- small utilities

func _well(front: float, to_curb: float) -> void:
	var c := Vector3(-2.0, 0, front + 9.0)
	_box("paint", Vector3(6.4, 0.3, 5.4), c + Vector3(0, 0.15, 0), CONCRETE)
	_box("brick", Vector3(6.0, 3.0, 5.0), c + Vector3(0, 1.8, 0), Color(_pick(["#8a4a38", "#a8775c", "#b8b2a4"])))
	_metal_roof(c.x, c.z, 3.3, 6.0, 5.0, Color(_pick(["#7a7874", "#3e5a48", "#5a2a26"])))
	_steel_door(c + Vector3(-1.4, 1.35, -2.53), -1.0)
	_box("metal", Vector3(1.0, 0.6, 0.6), c + Vector3(2.2, 2.4, -2.8), Color("#b9bcbc"))  # louvre vent
	# Hydropneumatic tank on saddles, and the capped well head.
	var t := Vector3(5.5, 0, front + 9.0)
	_box("paint", Vector3(2.4, 0.3, 5.0), t + Vector3(0, 0.15, 0), CONCRETE)
	_tank_on_saddles(t + Vector3(0, 0.3, 0), 0.9, 4.2, Color("#d8dadb"))
	_cyl_y(Vector3(-2.0, 0.5, front + 14.5), 0.3, 1.0, Color("#3a5a8a"))
	_flat_rect("gravel", -5.0, 7.0, front - to_curb, front + 6.0, 0.06, Color("#8d877c"))
	_fence(Vector2(-7.0, front + 2.0), Vector2(8.5, front + 17.0), 1.8)


func _power_feed() -> void:
	for x in [-4.0, 4.0]:
		_cyl_y(Vector3(x, 5.5, 0), 0.17, 11.0, POLE)
		_box("paint", Vector3(2.4, 0.12, 0.12), Vector3(x, 10.4, 0), POLE)
		for k in 3:
			_insulator(Vector3(x - 1.0 + k * 1.0, 10.45, 0), 1.0)
		for k in 3:
			_cyl_y(Vector3(x + 0.35, 7.6 - k * 1.4, 0.45), 0.36, 1.1, Color("#8a9094"))
	for k in 3:
		_box("paint", Vector3(8.0, 0.03, 0.03), Vector3(-1.0 + k * 1.0, 10.55, 0), DARK)


# ---------------------------------------------------------------- bus depot

func _bus_depot(size: Vector2, front: float, to_curb: float) -> void:
	var w := size.x
	var back := size.y * 0.5
	var trim := Color(_pick(["#d9d3c3", "#cfc8b6", "#3a3530"]))
	var metal := Color(_pick(["#c9ccc8", "#b8c0c4", "#d6d2c4"]))
	var brick := Color(_pick(["#8a4a38", "#a8775c", "#b59a7c"]))
	var drive_x := w * 0.5 - 5.0
	# The driveway in along one side, the yard behind the garage.
	var yard_z := front + BusNet.GARAGE_D
	_curb_cut(drive_x, 4.0, front - to_curb, yard_z)
	_flat_rect("asphalt", -w * 0.5 + 0.5, w * 0.5 - 0.5, yard_z, back - 0.5, 0.07)
	for slot in BusNet.bay_slots(size):
		var p: Vector3 = slot[0]
		for e in [-1.0, 1.0]:
			var x: float = p.x + e * BusNet.STALL_W * 0.5
			_flat_rect("line", x - 0.06, x + 0.06, p.z - 0.6, p.z - 0.6 + BusNet.STALL_D, 0.08, LINE)
	# Maintenance garage: two drive-through bays, doors onto the yard.
	var gw := minf(w - 10.0, 26.0)
	var gx := drive_x - 4.5 - gw * 0.5
	var gd := BusNet.GARAGE_D - 3.0
	var gz := front + 1.0
	_slab(gx, gw, gz, gd)
	_flat_roofed_at("metal", gx, gw, gd, gz + gd * 0.5, 7.6, 8.2, metal)
	for i in 2:
		var x := gx - gw * 0.25 + i * gw * 0.5
		_overhead_door(x, gz + gd, 4.3, 4.3, WHITE, true)
	_rooftop_units(gx, gw, gz, gd, 8.2, 2)
	# A brick office and drivers' room at the street end, with the sign.
	var ow := minf(12.0, gw * 0.5)
	var ox := gx - gw * 0.5 + ow * 0.5 + 0.5
	_box("brick", Vector3(ow, 3.6, 3.2), Vector3(ox, 1.8, gz - 1.0), brick)
	_box("paint", Vector3(ow + 0.2, 0.25, 3.4), Vector3(ox, 3.7, gz - 1.0), trim)
	_entry(ox, gz - 2.6, trim)
	_sign(Vector3(gx + gw * 0.2, 5.2, gz - 0.04), gw * 0.4, 0.9)
	# Fuel and wash island by the yard gate.
	var fz := yard_z + 1.5
	_box("paint", Vector3(1.2, 0.9, 3.0), Vector3(drive_x, 0.45, fz + 1.5), CONCRETE)
	for e in [-1.0, 1.0]:
		_box("paint", Vector3(0.25, 4.6, 0.25), Vector3(drive_x + e * 3.2, 2.3, fz + 1.5), GALV)
	_box("metal", Vector3(7.4, 0.35, 5.0), Vector3(drive_x, 4.75, fz + 1.5), WHITE)
	# Chain-link along the sides and back of the yard (thin strips, so the
	# gate side stays open).
	_fence(Vector2(-w * 0.5 + 0.2, yard_z), Vector2(-w * 0.5 + 0.4, back - 0.3), 2.1)
	_fence(Vector2(w * 0.5 - 0.4, yard_z), Vector2(w * 0.5 - 0.2, back - 0.3), 2.1)
	_fence(Vector2(-w * 0.5 + 0.2, back - 0.5), Vector2(w * 0.5 - 0.2, back - 0.3), 2.1)


## The depot's development tree (BusNet.TREE) at the depot itself, each as
## a real small-city transit garage has it. Most go in the strip between the
## back of the bus stalls and the back fence; the coach stop is on the
## office front. Shelters, the transfer center and park-and-ride are at the
## stops (BusView).
func _bus_upgrades(size: Vector2, front: float, built: Array) -> void:
	if built.is_empty():
		return
	var w := size.x
	var back := size.y * 0.5
	var slots := BusNet.bay_slots(size)
	var z0 := front + BusNet.GARAGE_D
	for slot in slots:
		z0 = maxf(z0, slot[0].z - 0.6 + BusNet.STALL_D)
	z0 += 0.4
	var z1 := back - 0.9
	var zm := (z0 + z1) * 0.5
	var gw := minf(w - 10.0, 26.0)
	var gx := w * 0.5 - 5.0 - 4.5 - gw * 0.5
	var ow := minf(12.0, gw * 0.5)
	var ox := gx - gw * 0.5 + ow * 0.5 + 0.5
	var gz := front + 1.0
	if "cng" in built:
		# A CNG fueling station: a sound-walled compressor package, a frame
		# of ASME storage tubes, and a CNG dispenser by the fuel island.
		var cx := w * 0.5 - 2.6
		_box("metal", Vector3(3.6, 2.6, 2.4), Vector3(cx, 1.3, zm), Color("#d8d6cf"))
		_box("paint", Vector3(3.7, 0.15, 2.5), Vector3(cx, 2.68, zm), Color("#8e9aa3"))
		for k in 3:
			UpgradeKits._drum(self, Vector3(cx - 4.6, 0.6 + k * 0.85, zm), 0.38, 4.2, Color("#c9c6bb"))
		for e in [-1.0, 1.0]:
			_box("paint", Vector3(0.15, 2.7, 1.0), Vector3(cx - 4.6 + e * 1.8, 1.35, zm), UpgradeKits.STEEL)
		var dx := w * 0.5 - 5.0
		_box("paint", Vector3(0.8, 2.0, 0.5), Vector3(dx + 1.6, 1.0, front + BusNet.GARAGE_D + 3.0), Color("#2f6d9a"))
	if "electric" in built:
		# Depot charging: a pad-mounted transformer and a charger pedestal at
		# the head of every other stall (one charger serves two buses).
		_box("paint", Vector3(1.8, 1.7, 1.6), Vector3(w * 0.5 - 10.4, 0.85, zm), Color("#4d6b4f"))
		_box("paint", Vector3(2.2, 0.15, 2.0), Vector3(w * 0.5 - 10.4, 0.07, zm), CONCRETE)
		for i in range(0, slots.size(), 2):
			var p: Vector3 = slots[i][0]
			var at := Vector3(p.x + BusNet.STALL_W * 0.5, 0, p.z - 0.6 + BusNet.STALL_D + 0.05)
			_box("paint", Vector3(0.6, 0.15, 0.6), at + Vector3(0, 0.07, 0), CONCRETE)
			_box("paint", Vector3(0.55, 1.9, 0.4), at + Vector3(0, 1.1, 0), Color("#e4e6e3"))
			_box("paint", Vector3(0.3, 0.3, 0.05), at + Vector3(0, 1.5, -0.22), Color("#2b2f33"))
	if "dial_a_ride" in built:
		# Paratransit vans park under a carport along the back fence, with
		# the 8 ft striped access aisle a lift van needs (ADA 502).
		var x0 := -w * 0.5 + 0.8
		var x1 := minf(x0 + 13.0, -1.0)
		var top := 3.4
		for x in [x0 + 0.2, (x0 + x1) * 0.5, x1 - 0.2]:
			for z in [z0 + 0.2, z1 - 0.2]:
				_box("paint", Vector3(0.15, top, 0.15), Vector3(x, top * 0.5, z), GALV)
		_box("metal", Vector3(x1 - x0 + 0.4, 0.18, z1 - z0 + 0.6), Vector3((x0 + x1) * 0.5, top + 0.09, zm), Color("#cfd2d0"))
		var ax := (x0 + x1) * 0.5
		for k in 6:
			_flat_rect("line", ax - 1.2 + k * 0.45, ax - 1.05 + k * 0.45, z0 + 0.3, z1 - 0.3, 0.09, Color("#2a5aa8"))
	if "school_contract" in built:
		# The contractor's drivers work out of a modular office trailer on
		# blocks, with wooden steps up to the door.
		var tx := 1.0
		_box("paint", Vector3(9.8, 0.6, 3.2), Vector3(tx, 0.3, zm), Color("#6c6a64"))
		_box("metal", Vector3(10.0, 2.6, 3.4), Vector3(tx, 1.9, zm), Color("#efeae0"))
		_box("paint", Vector3(10.1, 0.12, 3.5), Vector3(tx, 3.25, zm), Color("#b5b2aa"))
		_box("paint", Vector3(0.9, 2.0, 0.05), Vector3(tx + 2.5, 1.6, zm - 1.73), Color("#8a8f93"))
		_box("paint", Vector3(1.2, 0.6, 1.0), Vector3(tx + 2.5, 0.3, zm - 2.2), Color("#9a7f60"))
		for k in 3:
			_box("paint", Vector3(1.0, 0.05, 0.6), Vector3(tx - 2.0 + k * 1.4, 2.2, zm - 1.72), Color("#6e8592"))
	if "intercity" in built:
		# Intercity coaches (Indiana's Miller/Hoosier Ride) stop at the
		# depot: an awning and bench by the office door and a blue
		# coach-stop sign at the curb.
		_box("paint", Vector3(ow * 0.7, 0.15, 1.5), Vector3(ox, 2.9, gz - 3.3), Color("#2b4a6b"))
		for e in [-1.0, 1.0]:
			_box("paint", Vector3(0.1, 0.1, 1.5), Vector3(ox + e * ow * 0.33, 2.7, gz - 3.3), Color("#2b4a6b"))
		_box("paint", Vector3(1.8, 0.45, 0.45), Vector3(ox + 2.0, 0.45, gz - 3.1), Color("#6b5a48"))
		var sx := ox + ow * 0.5 - 0.6
		_box("paint", Vector3(0.08, 2.9, 0.08), Vector3(sx, 1.45, front - 1.3), GALV)
		_box("paint", Vector3(0.6, 0.75, 0.04), Vector3(sx, 2.55, front - 1.34), Color("#1d4f91"))
	if "regional" in built:
		# Shared regional routes: a real-time departures totem with the
		# region's route map, by the drive.
		var tx2 := ox - ow * 0.5 + 0.8
		_box("paint", Vector3(0.8, 2.4, 0.3), Vector3(tx2, 1.2, front - 0.9), Color("#2e3438"))
		_box("paint", Vector3(0.6, 0.9, 0.02), Vector3(tx2, 1.75, front - 1.06), Color("#f0c23a"))
		_box("paint", Vector3(0.6, 0.6, 0.02), Vector3(tx2, 0.85, front - 1.06), Color("#e9e7e0"))


## The cab company's tree (TaxiCo.TREE) on its own lot and storefront. The
## hybrid cabs themselves show on the street (VehicleModels).
func _taxi_upgrades(size: Vector2, front: float, built: Array) -> void:
	if built.is_empty():
		return
	var w := size.x
	var back := size.y * 0.5
	var z0 := front + TaxiCo.OFFICE_D
	for slot in TaxiCo.stall_slots(size):
		z0 = maxf(z0, slot[0].z - 0.3 + TaxiCo.STALL_D)
	var drive_x := w * 0.5 - 4.0
	var ow := minf(w - 9.0, 16.0)
	var ox := drive_x - 3.8 - ow * 0.5
	var od := TaxiCo.OFFICE_D - 3.0
	var oz := front + 1.0
	if "radio" in built:
		# Two-way radio: a base-station antenna mast on the roof.
		var m := Vector3(ox - ow * 0.5 + 1.0, 4.8, oz + od - 1.0)
		_box("paint", Vector3(0.1, 7.0, 0.1), m + Vector3(0, 3.5, 0), GALV)
		_box("paint", Vector3(0.06, 2.6, 0.06), m + Vector3(0, 8.3, 0), Color("#efede6"))
		for e in [-1.0, 1.0]:
			UpgradeKits._strut(self, m + Vector3(0, 5.0, 0), m + Vector3(e * 2.2, 0.0, -1.2), 0.03, GALV)
	if "late_night" in built:
		# Lot lights for the night shift: two poles with shoebox heads.
		for x in [-w * 0.5 + 1.0, drive_x - 3.4]:
			_box("paint", Vector3(0.18, 7.0, 0.18), Vector3(x, 3.5, back - 1.0), Color("#2b2f33"))
			_box("paint", Vector3(0.6, 0.18, 0.9), Vector3(x, 7.0, back - 1.5), Color("#2b2f33"))
	if "wheelchair_van" in built:
		# A van-accessible space behind the cab row: the 8 ft striped access
		# aisle for the lift and the blue sign (MUTCD R7-8 with "van
		# accessible").
		var vx := -w * 0.5 + 4.5
		_flat_rect("line", vx - 1.25, vx - 1.15, z0 + 0.4, z0 + 6.2, 0.09, LINE)
		_flat_rect("line", vx + 1.15, vx + 1.25, z0 + 0.4, z0 + 6.2, 0.09, LINE)
		for k in 5:
			_flat_rect("line", vx - 1.0 + k * 0.45, vx - 0.85 + k * 0.45, z0 + 0.6, z0 + 6.0, 0.09, Color("#2a5aa8"))
		_box("paint", Vector3(0.07, 2.4, 0.07), Vector3(vx + 3.5, 1.2, z0 + 6.6), GALV)
		_box("paint", Vector3(0.45, 0.6, 0.03), Vector3(vx + 3.5, 2.1, z0 + 6.56), Color("#1d4f91"))
	if "campus" in built:
		# The campus contract's cab stand sign by the door, with the
		# school's colours, and a bench for students waiting on a ride.
		_box("paint", Vector3(0.07, 2.5, 0.07), Vector3(ox + ow * 0.5 - 0.5, 1.25, front - 1.2), GALV)
		_box("paint", Vector3(0.6, 0.45, 0.03), Vector3(ox + ow * 0.5 - 0.5, 2.2, front - 1.24), Color("#7a1f2b"))
		_box("paint", Vector3(1.8, 0.45, 0.45), Vector3(ox + ow * 0.5 - 2.4, 0.45, oz - 1.0), Color("#6b5a48"))
	if "app" in built:
		# The ride app's window graphic and QR code on the storefront glass.
		_box("paint", Vector3(1.4, 1.0, 0.02), Vector3(ox - ow * 0.2, 1.7, oz - 0.06), Color("#f2c21b"))
		_box("paint", Vector3(0.45, 0.45, 0.01), Vector3(ox - ow * 0.2 + 0.3, 1.6, oz - 0.08), Color("#1e1e1e"))
	if "airport" in built:
		# An "Airport service" blade sign off the storefront, with the
		# airplane symbol (MUTCD I-5) in white on blue.
		var bx := ox + ow * 0.5 - 0.6
		_box("paint", Vector3(0.05, 0.08, 1.0), Vector3(bx, 3.4, oz - 0.5), Color("#2b2f33"))
		_box("paint", Vector3(0.06, 0.8, 0.8), Vector3(bx, 2.9, oz - 0.7), Color("#1d4f91"))
		_box("paint", Vector3(0.07, 0.08, 0.5), Vector3(bx, 2.95, oz - 0.7), Color("#f2f2ee"))
		_box("paint", Vector3(0.07, 0.4, 0.08), Vector3(bx, 2.95, oz - 0.7), Color("#f2f2ee"))


## A small-town cab company: a one-story brick storefront for the dispatch
## office and drivers' room at the street, with a TAXI sign, and an asphalt
## lot of striped stalls behind it reached by a side driveway.
func _taxi_company(size: Vector2, front: float, to_curb: float) -> void:
	var w := size.x
	var back := size.y * 0.5
	var trim := Color(_pick(["#d9d3c3", "#cfc8b6", "#efede6"]))
	var brick := Color(_pick(["#8a4a38", "#9b5a42", "#a8775c", "#b59a7c"]))
	var drive_x := w * 0.5 - 4.0
	var lot_z := front + TaxiCo.OFFICE_D
	_curb_cut(drive_x, 3.2, front - to_curb, lot_z)
	_flat_rect("asphalt", -w * 0.5 + 0.5, w * 0.5 - 0.5, lot_z, back - 0.5, 0.07)
	for slot in TaxiCo.stall_slots(size):
		var p: Vector3 = slot[0]
		for e in [-1.0, 1.0]:
			var x: float = p.x + e * TaxiCo.STALL_W * 0.5
			_flat_rect("line", x - 0.05, x + 0.05, p.z - 0.3, p.z - 0.3 + TaxiCo.STALL_D, 0.08, LINE)
	# The storefront: brick, a glass front with the door, a parapet sign.
	var ow := minf(w - 9.0, 16.0)
	var ox := drive_x - 3.8 - ow * 0.5
	var od := TaxiCo.OFFICE_D - 3.0
	var oz := front + 1.0
	_slab(ox, ow, oz, od)
	_flat_roofed_at("brick", ox, ow, od, oz + od * 0.5, 4.0, 4.8, brick)
	_glass(Vector3(ox - ow * 0.2, 1.6, oz - 0.03), Vector3(-1, 0, 0), ow * 0.45, 2.0, 0.0)
	_entry(ox + ow * 0.25, oz, trim)
	_sign(Vector3(ox, 4.3, oz - 0.04), ow * 0.5, 0.7)
	_fence(Vector2(-w * 0.5 + 0.2, lot_z), Vector2(-w * 0.5 + 0.4, back - 0.3), 1.2)
	_fence(Vector2(-w * 0.5 + 0.2, back - 0.5), Vector2(w * 0.5 - 0.2, back - 0.3), 1.2)


## The home builder's yard (Builders): a steel shop at the street with the
## office windows and an overhead door, and behind it a fenced gravel lot of
## truck stalls (railroad-tie bumpers), a lumber rack and a pile of crushed
## stone. Benchmark: a small-town builder's yard, a Morton-style steel shop
## and gravel lot at the edge of town.
func _builder_yard(size: Vector2, front: float, to_curb: float) -> void:
	var w := size.x
	var back := size.y * 0.5
	var steel := Color(_pick(["#c9c4b8", "#8f9a8c", "#b8a98e", "#9aa3a8"]))
	var trim := Color(_pick(["#4a3f35", "#2f3a34", "#5b2c22"]))
	var drive_x := w * 0.5 - 4.5
	var lot_z := front + Builders.OFFICE_D
	var gravel := Color("#a49c8d")
	_curb_cut(drive_x, 3.6, front - to_curb, lot_z)
	_flat_rect("gravel", -w * 0.5 + 0.5, w * 0.5 - 0.5, lot_z, back - 0.5, 0.06, gravel)
	for slot in Builders.stall_slots(size):
		var p: Vector3 = slot[0]
		# A railroad tie at the head of each stall.
		_box("paint", Vector3(Builders.STALL_W - 1.0, 0.18, 0.22), Vector3(p.x, 0.09, p.z + Builders.STALL_D - 0.6),
			Color("#4a3b2e"))
	# The shop: steel siding, a dark trim band, office windows, a door and a
	# 12 ft overhead door at the drive.
	var ow := minf(w - 11.0, 22.0)
	var ox := drive_x - 4.4 - ow * 0.5
	var od := Builders.OFFICE_D - 3.0
	var oz := front + 1.0
	_slab(ox, ow, oz, od)
	_flat_roofed_at("metal", ox, ow, od, oz + od * 0.5, 4.6, 5.0, steel)
	_box("paint", Vector3(ow + 0.05, 0.35, od + 0.05), Vector3(ox, 4.75, oz + od * 0.5), trim)
	_glass(Vector3(ox - ow * 0.28, 1.6, oz - 0.03), Vector3(-1, 0, 0), ow * 0.3, 1.4, 0.0)
	_entry(ox - ow * 0.05, oz, trim)
	_overhead_door(ox + ow * 0.3, oz, 3.7, 3.7, steel)
	_sign(Vector3(ox - ow * 0.2, 4.0, oz - 0.04), ow * 0.45, 0.6)
	# A lumber rack along the far fence: steel uprights and stacked boards.
	var rz := lot_z + 1.5
	var rx := -w * 0.5 + 1.4
	for k in 4:
		_box("paint", Vector3(0.12, 2.4, 0.12), Vector3(rx, 1.2, rz + k * 2.4), GALV)
	for lvl in 3:
		_box("paint", Vector3(1.0, 0.3, 7.6), Vector3(rx + 0.2, 0.5 + lvl * 0.75, rz + 3.6), Color("#c9a66b").darkened(lvl * 0.06))
	# Bulk material bays along the back fence, walled with interlocking
	# 2 x 2 x 6 ft concrete blocks as real contractors' yards are: #57
	# stone, fill sand, topsoil and mulch, each heaped at its angle of repose.
	var mats := [Color("#8d877d"), Color("#c9ad7a"), Color("#4e3b2c"), Color("#6a4630")]
	var bay := 6.0
	var bays := clampi(int((drive_x - 6.0 + w * 0.5 - 4.0) / bay), 1, 4)
	var bx0 := drive_x - 6.0 - bays * bay
	var bz := back - 4.2
	for i in bays + 1:
		_lego_wall(Vector3(bx0 + i * bay, 0, bz - 0.4), 0.6, 5.2)  # short of the back wall
	_lego_wall(Vector3(bx0 + bays * bay * 0.5, 0, back - 1.0), bays * bay + 0.6, 0.6)
	for i in bays:
		var c := Vector3(bx0 + (i + 0.5) * bay, 0, bz + 0.6)
		_aggregate_pile(c, 2.5, 1.7 - 0.2 * (i % 2), mats[i % mats.size()])
	_fence(Vector2(-w * 0.5 + 0.2, lot_z), Vector2(-w * 0.5 + 0.4, back - 0.3), 1.8)
	_fence(Vector2(-w * 0.5 + 0.2, back - 0.5), Vector2(w * 0.5 - 0.2, back - 0.3), 1.8)
	_fence(Vector2(w * 0.5 - 0.4, lot_z), Vector2(w * 0.5 - 0.2, back - 0.3), 1.8)


## A wall of interlocking concrete blocks (0.6 m cubes stacked two high
## and 1.8 m long), `sx` by `sz` on the ground, centred at `c`.
func _lego_wall(c: Vector3, sx: float, sz: float) -> void:
	var col := Color("#a7a399")
	var along_x := sx > sz
	var len := sx if along_x else sz
	var n := maxi(1, int(round(len / 1.8)))
	for k in n:
		for lvl in 2:
			var t := -len * 0.5 + (k + 0.5) * len / n + (0.45 if lvl == 1 else 0.0)
			if absf(t) > len * 0.5 - 0.3:
				continue
			var size := Vector3(len / n - 0.04, 0.58, 0.6) if along_x else Vector3(0.6, 0.58, len / n - 0.04)
			var at := c + (Vector3(t, 0, 0) if along_x else Vector3(0, 0, t)) + Vector3(0, 0.3 + lvl * 0.6, 0)
			_box("concrete", size, at, col.darkened(0.05 * ((k + lvl) % 2)))


## A heap of loose material: a cone with a slightly rounded top.
func _aggregate_pile(base: Vector3, r: float, h: float, col: Color, segs := 18) -> void:
	var rings := [[1.0, 0.0], [0.66, 0.42], [0.3, 0.8], [0.0, 1.0]]
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		for k in rings.size() - 1:
			var lo: Array = rings[k]
			var hi: Array = rings[k + 1]
			var p0 := base + Vector3(cos(a0) * r * lo[0], h * lo[1], sin(a0) * r * lo[0])
			var p1 := base + Vector3(cos(a1) * r * lo[0], h * lo[1], sin(a1) * r * lo[0])
			var q0 := base + Vector3(cos(a0) * r * hi[0], h * hi[1], sin(a0) * r * hi[0])
			var q1 := base + Vector3(cos(a1) * r * hi[0], h * hi[1], sin(a1) * r * hi[0])
			var n := Vector3(cos((a0 + a1) * 0.5), 0.9, sin((a0 + a1) * 0.5)).normalized()
			_quad("paint", p0, p1, q1, q0, col.darkened(0.04 * k), [], n)


# ---------------------------------------------------------------- shared parts

func _slab(cx: float, w: float, zf: float, d: float) -> void:
	_box("paint", Vector3(w + 0.1, 0.3, d + 0.1), Vector3(cx, 0.15, zf + d * 0.5), FOUNDATION)


## CommercialBuilder._flat_roofed, offset along x.
func _flat_roofed_at(mat: String, cx: float, w: float, d: float, cz: float, deck: float, top: float, wall: Color) -> void:
	var t := 0.25
	var ph := top - deck
	_box(mat, Vector3(w, deck, d), Vector3(cx, deck * 0.5, cz), wall)
	_dr_note(cx, cz, w, d, deck, "none", 0.0, mat, wall)
	var y := deck + 0.02
	_quad("membrane", Vector3(cx - w * 0.5, y, cz - d * 0.5), Vector3(cx + w * 0.5, y, cz - d * 0.5),
		Vector3(cx + w * 0.5, y, cz + d * 0.5), Vector3(cx - w * 0.5, y, cz + d * 0.5), _low_slope(w, d, cx + cz, mat == "brick"), [], Vector3.UP)
	_roof_bits(cx, w, d, cz, y, mat == "brick")
	_box(mat, Vector3(w, ph, t), Vector3(cx, deck + ph * 0.5, cz - d * 0.5 + t * 0.5), wall)
	_box(mat, Vector3(w, ph, t), Vector3(cx, deck + ph * 0.5, cz + d * 0.5 - t * 0.5), wall)
	_box(mat, Vector3(t, ph, d), Vector3(cx - w * 0.5 + t * 0.5, deck + ph * 0.5, cz), wall)
	_box(mat, Vector3(t, ph, d), Vector3(cx + w * 0.5 - t * 0.5, deck + ph * 0.5, cz), wall)
	var col := Color("#cfcbc2")
	_box("paint", Vector3(w + 0.1, 0.1, 0.35), Vector3(cx, top, cz - d * 0.5), col)
	_box("paint", Vector3(w + 0.1, 0.1, 0.35), Vector3(cx, top, cz + d * 0.5), col)
	_box("paint", Vector3(0.35, 0.1, d), Vector3(cx - w * 0.5, top, cz), col)
	_box("paint", Vector3(0.35, 0.1, d), Vector3(cx + w * 0.5, top, cz), col)


## A sectional overhead door with a row of lites, on a wall facing -z (or +z
## when `back`).
func _overhead_door(x: float, z: float, w: float, h: float, col: Color, back := false) -> void:
	var s := 1.0 if back else -1.0
	_glass_log.append([Vector3(x, 0.3 + h * 0.5, z), Vector3(1, 0, 0), w + 0.6, h + 0.5])
	_box("siding", Vector3(w, h, 0.08), Vector3(x, 0.3 + h * 0.5, z + s * 0.03), Color(col, 0.0))
	_glass(Vector3(x, 0.3 + h * 0.72, z + s * 0.08), Vector3(1 if back else -1, 0, 0), w - 0.5, 0.45, 0.0)
	_box("paint", Vector3(w + 0.3, 0.18, 0.12), Vector3(x, 0.3 + h + 0.09, z + s * 0.06), Color("#cfcbc2"))
	for e in [-1.0, 1.0]:
		_box("paint", Vector3(0.15, h, 0.12), Vector3(x + e * (w * 0.5 + 0.07), 0.3 + h * 0.5, z + s * 0.06), Color("#cfcbc2"))


## A glass entry door with sidelites and a small flat canopy.
func _entry(x: float, zf: float, trim: Color) -> void:
	_glass(Vector3(x, 1.4, zf - 0.03), Vector3(-1, 0, 0), 1.0, 2.2, 0.0)
	for s in [-1.0, 1.0]:
		_glass(Vector3(x + s * 0.85, 1.4, zf - 0.03), Vector3(-1, 0, 0), 0.5, 2.2, 0.0)
		_box("paint", Vector3(0.08, 2.4, 0.1), Vector3(x + s * 0.55, 1.4, zf - 0.06), MULLION[0])
	_box("paint", Vector3(3.0, 0.25, 1.6), Vector3(x, 2.85, zf - 0.8), trim)
	_box("paint", Vector3(2.6, 0.3, 1.8), Vector3(x, 0.15, zf - 0.9), CONCRETE)


## A glass vestibule that steps out of the facade, flat-roofed.
func _vestibule(x: float, zf: float, w: float, d: float, h: float) -> void:
	_box("paint", Vector3(w + 0.3, 0.3, d + 0.3), Vector3(x, 0.15, zf - d * 0.5), CONCRETE)
	_box("paint", Vector3(w + 0.4, 0.35, d + 0.2), Vector3(x, h, zf - d * 0.5), Color("#cfcbc2"))
	_glass(Vector3(x, h * 0.48, zf - d - 0.01), Vector3(-1, 0, 0), w - 0.2, h * 0.9, 0.0)
	for s in [-1.0, 1.0]:
		_glass(Vector3(x + s * w * 0.5, h * 0.48, zf - d * 0.5), Vector3(0, 0, -s), d - 0.2, h * 0.9, 0.0)
		_box("paint", Vector3(0.12, h, 0.12), Vector3(x + s * w * 0.5, h * 0.5, zf - d), MULLION[0])
	for i in 3:
		_box("paint", Vector3(0.08, h, 0.1), Vector3(x - w * 0.25 + i * w * 0.25, h * 0.5, zf - d - 0.04), MULLION[0])


## Punched windows in a row along a wall. `out` is the wall's outward normal.
func _window_row(cx: float, cz: float, span: float, y: float, h: float, n: int, trim: Color, out := Vector3.FORWARD) -> void:
	if span < 1.2 or n < 1:
		return
	var along := Vector3(-out.z, 0, out.x)  # runs along the wall
	var right := -along
	var ww := minf(1.4, span / n - 0.6)
	if ww < 0.6:
		return
	for i in n:
		var t := (i + 0.5) / n - 0.5
		var c := Vector3(cx, y, cz) + along * t * span + out * 0.03
		_glass(c, right, ww, h, rng.randf_range(0.0, 0.6))
		_box("paint", Vector3(absf(along.x) * (ww + 0.3) + absf(out.x) * 0.16, 0.1, absf(along.z) * (ww + 0.3) + absf(out.z) * 0.16),
			c + Vector3(0, -h * 0.5 - 0.05, 0) + out * 0.05, trim)


## A parking lot from x0..x1 and z0..z1 (z1 is the building side), stalls
## facing the building, with the drive out to the street at `drive_x`.
func _parking(x0: float, x1: float, z0: float, z1: float, to_curb: float, drive_x: float) -> void:
	_flat_rect("asphalt", x0, x1, z0, z1, 0.06)
	_curb_cut(drive_x, 3.6, z0 - to_curb, z0)
	if z1 - z0 < 6.0:
		return
	var x := x0 + 0.3
	while x <= x1 - 0.3:
		_flat_rect("line", x - 0.06, x + 0.06, z1 - 5.5, z1, 0.07, LINE)
		if z1 - z0 >= 11.0 and absf(x - drive_x) > 4.0:
			_flat_rect("line", x - 0.06, x + 0.06, z0, z0 + 5.5, 0.07, LINE)
		x += 2.75


func _flagpole(p: Vector3) -> void:
	_box("paint", Vector3(1.2, 0.2, 1.2), p + Vector3(0, 0.1, 0), CONCRETE)
	_cyl_y(p + Vector3(0, 5.0, 0), 0.07, 10.0, Color("#d0d2d2"))
	var f := p + Vector3(0.95, 9.2, 0)
	var stripes := 7
	for i in stripes:
		_box("paint", Vector3(1.8, 1.0 / stripes, 0.02), f + Vector3(0, 0.5 - (i + 0.5) / stripes, 0),
			Color("#b22234") if i % 2 == 0 else Color("#f2f0ea"))
	_box("paint", Vector3(0.75, 0.54, 0.03), f + Vector3(-0.52, 0.23, 0), Color("#3c3b6e"))


func _bed(x: float, z: float, w: float) -> void:
	_flat_rect("mulch", x - w * 0.5, x + w * 0.5, z - 0.9, z + 0.9, 0.05)
	for i in int(w / 1.2):
		_shrub(Vector3(x - w * 0.5 + 0.6 + i * 1.2, 0, z), rng.randf_range(0.45, 0.6))


func _rooftop_units(cx: float, w: float, zf: float, d: float, h: float, n: int) -> void:
	for i in n:
		var p := Vector3(cx + rng.randf_range(-w * 0.35, w * 0.35), h, zf + rng.randf_range(d * 0.25, d * 0.75))
		_box("metal", Vector3(2.0, 1.2, 1.4), p + Vector3(0, 0.6, 0), Color("#b9bcbc"))
		_box("paint", Vector3(1.1, 0.08, 0.9), p + Vector3(0, 1.24, 0), Color("#3a3c3e"))


## Chain-link fence: galvanised posts every 3 m with top and bottom rails.
## The fabric itself reads as see-through at game distances.
func _fence(a: Vector2, b: Vector2, h: float, barbed := false) -> void:
	var corners := [Vector3(a.x, 0, a.y), Vector3(b.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(a.x, 0, b.y)]
	for i in 4:
		_fence_run(corners[i], corners[(i + 1) % 4], h, barbed)


## One straight run of chain-link fence from p to q.
func _fence_run(p: Vector3, q: Vector3, h: float, barbed := false) -> void:
	var len := p.distance_to(q)
	if len < 0.01:
		return  # a zero-length side would put NaNs in the mesh and hide all of it
	var dir := (q - p) / len
	var yaw := Basis(Vector3.UP, atan2(dir.x, dir.z))
	var n := maxi(1, int(len / 3.0))
	for k in n:
		_box("paint", Vector3(0.07, h, 0.07), p + dir * (len * k / n) + Vector3(0, h * 0.5, 0), GALV)
	_box("paint", Vector3(0.05, 0.05, len), (p + q) * 0.5 + Vector3(0, h, 0), GALV, yaw)
	_box("paint", Vector3(0.03, 0.03, len), (p + q) * 0.5 + Vector3(0, 0.1, 0), GALV, yaw)
	if barbed:
		for k in 3:
			_box("paint", Vector3(0.02, 0.02, len), (p + q) * 0.5 + Vector3(0, h + 0.15 + k * 0.15, 0), DARK, yaw)


## A horizontal pressure tank lying along z on two concrete saddles, with
## shallow dished heads (an ASME hydropneumatic tank, 6 ft by 14 ft for a
## small town well). `base` is the middle of the slab top it stands on.
func _tank_on_saddles(base: Vector3, r: float, length: float, col: Color) -> void:
	var c := base + Vector3(0, 0.45 + r, 0)
	var h := length * 0.5
	for s in [-1.0, 1.0]:
		_box("paint", Vector3(r * 1.6, 0.45 + r * 0.4, 0.35), base + Vector3(0, (0.45 + r * 0.4) * 0.5, s * h * 0.6), CONCRETE)
	var segs := 16
	var dish := r * 0.3
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		var p0 := c + d0 * r
		var p1 := c + d1 * r
		var out := (d0 + d1) * 0.5
		_quad("paint", p0 + Vector3(0, 0, -h), p1 + Vector3(0, 0, -h), p1 + Vector3(0, 0, h), p0 + Vector3(0, 0, h), col, [], out)
		for s in [-1.0, 1.0]:
			# Dished head: a ring in to 60 % of the radius, then a flat cap.
			var q0 := c + d0 * r * 0.6 + Vector3(0, 0, s * (h + dish))
			var q1 := c + d1 * r * 0.6 + Vector3(0, 0, s * (h + dish))
			var e0 := p0 + Vector3(0, 0, s * h)
			var e1 := p1 + Vector3(0, 0, s * h)
			_quad("paint", e0, e1, q1, q0, col.darkened(0.05), [], out + Vector3(0, 0, s))
			_tri("paint", c + Vector3(0, 0, s * (h + dish)), q0, q1, col.darkened(0.08), [], Vector3(0, 0, s))


func _cyl_y(c: Vector3, r: float, h: float, col: Color) -> void:
	_cylinder("paint", c - Vector3(0, h * 0.5, 0), r, h, col, 10)


## A flat ground polygon (convex, any winding) for the yard shader.
func _flat_poly(pts: Array, y: float, col: Color) -> void:
	col.a = 1.0  # gravel / mulch: coloured ground
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	for i in pts.size():
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		var tri := [c, a, b]
		if (a - c).cross(b - c).y > 0.0:
			tri = [c, b, a]
		for p in tri:
			_flat.set_normal(Vector3.UP)
			_flat.set_color(col)
			_flat.set_uv(Vector2(p.x, p.z) * 0.25)
			_flat.add_vertex(Vector3(p.x, y, p.z))
