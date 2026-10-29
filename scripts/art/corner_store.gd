class_name CornerStore
extends RefCounted
## A shop's first stage, the "Corner store" (BuildingTypes "shop" level 0):
## the neighborhood grocery a block or two off Main Street, as Indiana
## towns built them.
##   - prewar: the one-part commercial block of 1890-1930 (Indianapolis's
##     Fountain Square and Haughville groceries, the corner stores on
##     Marion's south side): one storey of brick at the sidewalk, a plate
##     glass front on a low bulkhead under a prism-glass transom, a sign
##     frieze and a pressed-metal cornice, the side parapet stepping down
##     toward the back. On a corner lot the corner is clipped at 45 degrees
##     for the door, the brick above it carried on a cast-iron column, and
##     the side street gets display windows and a painted wall sign. A
##     frame lean-to out back held the stock (or the family).
##   - postwar: the 1946-60 neighborhood market set back for a row of
##     stalls: buff brick and glass block, a full glass front under a thin
##     flat steel canopy, and a pylon sign by the street.
## Drawn into a CommercialBuilder `b`, in its local space (front at z 0,
## street at -z), with its own random numbers so the builder's don't move.

const CAST_IRON := Color("#2f3432")
const PRISM := Color(0.86, 0.85, 0.78, 0.55)  # prism-glass transom lights
const BULKHEAD := ["#5a3a2a", "#2f3a33", "#3a3530", "#6b2a24"]  # painted wood panels
const CORNICE := ["#3a3d3a", "#6b5a44", "#d9d3c3", "#4a2f2a", "#2a3a4a"]  # painted pressed metal
const BUFF := ["#d6c6a1", "#c9b48c", "#e0d3b4", "#b9a382"]
const TERRA := ["#b9b09f", "#9c6a4e", "#a89f8c"]  # terra cotta or stone caps
const SIDING := ["#e8e4d8", "#d8d0bc", "#c9cfc9", "#efe9da"]
const FLAT_H := 3.3


## How often a shop's first stage is a corner store, by era: the corner
## grocery is a prewar building type; postwar towns built a few; a store
## first built new on a recent street is a dollar store or gas station.
const CHANCE := {"prewar": 70, "postwar": 45, "recent": 0}


## True when this shop is drawn as a corner store: its first stage, an era
## that built them, a lot wide and deep enough (24 ft by 70 ft at least).
static func wanted(b: CommercialBuilder) -> bool:
	if b.half * 2.0 < 8.5 or b.depth < 21.0:
		return false
	return absi(hash([b.rng.seed, "corner store"])) % 100 < int(CHANCE.get(b.era, 0))


## `side`: which way (local x, +1 or -1) the lot's side street lies when it
## is a corner lot, 0 when it is not (or not known).
## `flats`: storeys of flats over the store (a prewar corner store grown
## into a store with flats, BuildingTypes "mixed_use", keeps its ground
## floor and goes up).
static func draw(b: CommercialBuilder, to_curb: float, side: float, flats := 0) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([b.rng.seed, "corner store art"])
	if b.era == "prewar":
		_cs_grocery(b, r, to_curb, side, flats)
	else:
		_cs_market(b, r, to_curb, side)


## The prewar brick grocery at the sidewalk.
static func _cs_grocery(b: CommercialBuilder, r: RandomNumberGenerator, to_curb: float, side: float, flats := 0) -> void:
	var lw := b.half * 2.0
	var bw := clampf(lw - 2.4, 7.0, 10.5)  # 24-34 ft fronts
	if flats > 0:
		bw = lw - 0.4  # the corner building of a Main Street row: wall to wall
	var bd := clampf(b.depth - 11.0, 12.0, 18.0)
	var e := side if side != 0.0 else (1.0 if r.randf() < 0.5 else -1.0)
	# Built to the side street's lot line (or one side lot line mid-block),
	# with a side yard or drive the other side on a wide lot.
	var cx := e * (b.half - 0.3 - bw * 0.5)
	var zf := 0.4
	var deck := r.randf_range(4.2, 4.6)  # a 13-14 ft storey
	var top := deck + r.randf_range(1.0, 1.4)
	# Flats upstairs: a 10-11 ft storey each, the parapet and cornice on top.
	var lift := FLAT_H * flats
	var roof_y := deck + lift
	var wall := Color(CommercialBuilder.FACADE_BRICK[r.randi() % CommercialBuilder.FACADE_BRICK.size()])
	var cornice := Color(CORNICE[r.randi() % CORNICE.size()])
	var trim := cornice if r.randf() < 0.5 else Color("#d9d3c3")
	var bulk := Color(BULKHEAD[r.randi() % BULKHEAD.size()])
	var cap := Color(TERRA[r.randi() % TERRA.size()])
	var clip := 1.8 if side != 0.0 else 0.0  # the clipped corner, about 6 ft
	var xe := cx + e * bw * 0.5  # the corner's x (the side street's wall)
	var xo := cx - e * bw * 0.5  # the far wall
	var gh := 3.5  # storefront height: bulkhead, glass, transom
	# The walls: the ground floor stops short of the clipped corner; the
	# brick over it runs square, on the column.
	if clip > 0.0:
		var wa := bw - clip
		b._box("brick", Vector3(wa, deck, clip), Vector3(cx - e * clip * 0.5, deck * 0.5, zf + clip * 0.5), wall)
		b._box("brick", Vector3(bw, deck, bd - clip), Vector3(cx, deck * 0.5, zf + clip + (bd - clip) * 0.5), wall)
		b._box("brick", Vector3(clip, deck - gh, clip), Vector3(xe - e * clip * 0.5, gh + (deck - gh) * 0.5, zf + clip * 0.5), wall)
		b._quad("paint", Vector3(xe - e * clip, gh, zf), Vector3(xe, gh, zf), Vector3(xe, gh, zf + clip),
			Vector3(xe - e * clip, gh, zf + clip), Color("#e2ddd0"), [], Vector3.DOWN)  # beadboard soffit
		b._box("paint", Vector3(0.26, gh, 0.26), Vector3(xe - e * 0.13, gh * 0.5, zf + 0.13), CAST_IRON)
		b._box("paint", Vector3(0.4, 0.2, 0.4), Vector3(xe - e * 0.13, 0.1, zf + 0.13), CAST_IRON)
		b._box("paint", Vector3(0.42, 0.22, 0.42), Vector3(xe - e * 0.13, gh - 0.11, zf + 0.13), CAST_IRON)
		_cs_clipped_door(b, Vector3(xe - e * clip, 0.0, zf), Vector3(xe, 0.0, zf + clip), e, gh, bulk, trim)
	else:
		b._box("brick", Vector3(bw, deck, bd), Vector3(cx, deck * 0.5, zf + bd * 0.5), wall)
	# The front: plate glass between the corner and a door, under the transom.
	var f0 := xo + e * (0.5 if flats == 0 else 1.9)  # the flats' own door at the far end
	var f1 := xe - e * (clip + 0.4 if clip > 0.0 else 0.5)
	var door_x := 0.0
	if clip == 0.0:
		door_x = cx + e * r.randf_range(-0.6, 0.6)
		_cs_front_door(b, Vector3(door_x, 0.0, zf), gh, bulk, trim)
		_cs_shop_glass(b, f0, door_x - e * 0.7, zf, gh, bulk, trim, r)
		_cs_shop_glass(b, door_x + e * 0.7, f1, zf, gh, bulk, trim, r)
	else:
		_cs_shop_glass(b, f0, f1, zf, gh, bulk, trim, r)
	# The sign frieze over the transom and the cornice.
	var sign_w := bw * 0.72
	b._sign(Vector3(cx - e * clip * 0.3, gh + 0.12, zf - 0.08), sign_w, minf(deck - gh - 0.25, 0.75))
	if flats > 0:
		_cs_flats(b, cx, bw, bd, zf, deck, lift, xe, xo, e, clip, wall, trim, bulk)
	top += lift
	b._box("brick", Vector3(bw, top - roof_y + 0.02, 0.3), Vector3(cx, roof_y + (top - roof_y) * 0.5, zf + 0.15), wall)
	b._box("paint", Vector3(bw + 0.2, 0.34, 0.5), Vector3(cx, top - 0.12, zf - 0.08), cornice)
	b._box("paint", Vector3(bw + 0.05, 0.14, 0.3), Vector3(cx, top - 0.4, zf - 0.02), cornice.darkened(0.15))
	if clip > 0.0:
		# The cornice turns the corner and returns a short way down the side.
		b._box("paint", Vector3(0.5, 0.34, 1.4), Vector3(xe + e * 0.08, top - 0.12, zf + 0.6), cornice)
	if CommercialBuilder.fine_parts:
		# Pressed-metal brackets under the cornice, about every 1.2 m.
		var n := maxi(2, int(bw / 1.2))
		for k in n + 1:
			var x := cx - bw * 0.5 + 0.15 + k * (bw - 0.3) / n
			b._box("paint", Vector3(0.16, 0.42, 0.34), Vector3(x, top - 0.5, zf - 0.04), cornice)
	# The flat roof, falling to the back behind the parapets.
	var y := roof_y + 0.02
	var cz := zf + bd * 0.5
	b._quad("membrane", Vector3(cx - bw * 0.5, y, zf), Vector3(cx + bw * 0.5, y, zf),
		Vector3(cx + bw * 0.5, y, zf + bd), Vector3(cx - bw * 0.5, y, zf + bd), b._low_slope(bw, bd, cz, true), [], Vector3.UP)
	b._roof_bits(cx, bw, bd, cz, y, true)
	# Side parapets stepping down in three, a terra cotta cap on each step.
	var low := roof_y + 0.5
	for s in [-1.0, 1.0]:
		var x: float = cx + s * (bw * 0.5 - 0.12)
		for k in 3:
			var z0 := zf + 0.3 + k * (bd - 0.3) / 3.0
			var z1 := zf + 0.3 + (k + 1) * (bd - 0.3) / 3.0
			var t := lerpf(top - 0.3, low, k / 2.0)
			b._box("brick", Vector3(0.24, t - roof_y, z1 - z0), Vector3(x, roof_y + (t - roof_y) * 0.5, (z0 + z1) * 0.5), wall)
			b._box("paint", Vector3(0.36, 0.1, z1 - z0 + 0.04), Vector3(x, t + 0.05, (z0 + z1) * 0.5), cap)
	b._box("brick", Vector3(bw, low - roof_y, 0.24), Vector3(cx, roof_y + (low - roof_y) * 0.5, zf + bd - 0.12), wall)
	b._box("paint", Vector3(bw + 0.1, 0.1, 0.36), Vector3(cx, low + 0.05, zf + bd - 0.12), cap)
	# Down the side street: display windows near the front, high windows
	# for the stockroom, and the store's name painted on the brick.
	if clip > 0.0:
		var xs := xe + e * 0.02
		for k in 2:
			var z := zf + clip + 0.9 + k * 1.9
			b._glass(Vector3(xs, 1.85, z), Vector3(0, 0, -e), 1.6, 2.2, 0.1)
			b._box("paint", Vector3(0.1, 0.62, 1.74), Vector3(xs + e * 0.03, 0.31, z), bulk)
			b._box("paint", Vector3(0.12, 0.1, 1.74), Vector3(xs + e * 0.04, 2.98, z), trim)
		# High windows up to where the painted sign starts.
		var pw := minf(bd - clip - 3.0, 7.0)
		var pz := zf + bd - 1.0 - pw * 0.5
		var hz_end := pz - pw * 0.5 - 0.8 if pw > 3.0 else zf + bd - 1.0
		var hz := zf + clip + 5.2
		while hz < hz_end:
			b._glass(Vector3(xs, 3.0, hz), Vector3(0, 0, -e), 0.9, 0.9, 0.3)
			b._box("paint", Vector3(0.14, 0.08, 1.05), Vector3(xs + e * 0.05, 2.5, hz), cap)
			hz += 2.6
		if pw > 3.0:
			var faded := Color(["#e8e0c8", "#d9c9a0", "#c8d0c0"][r.randi() % 3])
			faded.a = 0.5 + pw / 60.0  # painted letters (unlit)
			var py := deck - 0.15
			var o := Vector3(xs + e * 0.03, 0, pz)
			# The uv's x runs from the reader's right, as _sign's does.
			b._quad("sign", o + Vector3(0, py - 1.3, -pw * 0.5 * e), o + Vector3(0, py - 1.3, pw * 0.5 * e),
				o + Vector3(0, py, pw * 0.5 * e), o + Vector3(0, py, -pw * 0.5 * e), faded,
				[Vector2(0, 0), Vector2(pw, 0), Vector2(pw, 1), Vector2(0, 1)], Vector3(e, 0, 0))
	# The back: a frame lean-to for the stock, a steel door and a coal-era
	# chimney's stub.
	var lean_w := minf(bw * 0.6, 6.0)
	var lx := cx - e * (bw * 0.5 - lean_w * 0.5)
	var lz := zf + bd
	var ld := minf(4.2, b.depth - lz - 4.0)
	if ld > 2.4:
		var sid := Color(SIDING[r.randi() % SIDING.size()])
		b._box("siding", Vector3(lean_w, 2.7, ld), Vector3(lx, 1.35, lz + ld * 0.5), sid)
		var roof := Color("#5a5a58")
		b._quad("roof", Vector3(lx - lean_w * 0.5 - 0.2, 3.4, lz), Vector3(lx + lean_w * 0.5 + 0.2, 3.4, lz),
			Vector3(lx + lean_w * 0.5 + 0.2, 2.6, lz + ld + 0.3), Vector3(lx - lean_w * 0.5 - 0.2, 2.6, lz + ld + 0.3), roof, [], Vector3.UP)
		for s in [-1.0, 1.0]:
			var sx: float = lx + s * lean_w * 0.5
			b._tri("siding", Vector3(sx, 2.7, lz), Vector3(sx, 2.7, lz + ld), Vector3(sx, 3.4, lz), sid, [], Vector3(s, 0, 0))
		b._steel_door(Vector3(lx, 1.15, lz + ld + 0.03), 1.0, Color("#6b5a44"))
	b._steel_door(Vector3(cx + e * (bw * 0.5 - 1.4), 1.15, zf + bd + 0.03), 1.0)
	# Out front on the walk: a bench under the window, the ice chest and a
	# newspaper box at the curb.
	if CommercialBuilder.fine_parts:
		var bx := (f0 + f1) * 0.5
		b._box("paint", Vector3(1.8, 0.06, 0.42), Vector3(bx, 0.46, zf - 0.45), Color("#7a5a3a"))
		b._box("paint", Vector3(1.8, 0.4, 0.05), Vector3(bx, 0.72, zf - 0.24), Color("#7a5a3a"))
		for s in [-0.8, 0.8]:
			b._box("paint", Vector3(0.06, 0.46, 0.4), Vector3(bx + s, 0.23, zf - 0.45), CAST_IRON)
		var ix := xo + e * 1.2
		b._box("metal", Vector3(1.4, 1.5, 0.75), Vector3(ix, 0.8, zf - 0.55), Color("#eef0f0"))
		b._box("paint", Vector3(1.42, 0.28, 0.02), Vector3(ix, 1.15, zf - 0.93), Color("#2a5ea8"))
		var nx := cx + e * r.randf_range(-1.0, 1.0)
		b._box("paint", Vector3(0.5, 1.1, 0.45), Vector3(nx, 0.55, -to_curb + 0.9), Color(["#1f3b6e", "#c23a2a", "#e0b020"][r.randi() % 3]))
	if r.randf() < 0.55:
		var aw0 := minf(f0, f1)
		var aw1 := maxf(f0, f1)
		b._awning((aw0 + aw1) * 0.5, aw1 - aw0 + 0.3, zf, gh - 0.3, Color(CommercialBuilder.AWNING[r.randi() % 5]))
	# No lot of its own: customers park at the curb and walk in.
	b.site.main_street = true
	if clip > 0.0:
		b.site.door = Vector2(xe - e * clip * 0.5, zf + clip * 0.5)
	else:
		b.site.door = Vector2(door_x, zf)


## The flats over a grown corner store: the brick walls carried up a
## storey (square over the clipped corner, on its column), a belt course
## at the floor line, tall one-over-one windows under stone lintels to the
## front and the side street, a bay window over the corner, and the flats'
## own street door at the far end of the front with a transom over it.
static func _cs_flats(b: CommercialBuilder, cx: float, bw: float, bd: float, zf: float, deck: float, lift: float,
		xe: float, xo: float, e: float, clip: float, wall: Color, trim: Color, bulk: Color) -> void:
	var stone := Color("#cfc6b2")
	b._box("brick", Vector3(bw, lift, bd), Vector3(cx, deck + lift * 0.5, zf + bd * 0.5), wall)
	b._box("paint", Vector3(bw + 0.08, 0.2, 0.2), Vector3(cx, deck + 0.1, zf - 0.08), stone)
	var floors := roundi(lift / FLAT_H)
	for f in floors:
		var wy := deck + f * FLAT_H + 1.75
		# Front windows, kept off the corner's bay.
		var x0 := xo + e * 1.0
		var x1 := xe - e * (2.4 if clip > 0.0 else 1.0)
		var n := maxi(2, roundi(absf(x1 - x0) / 1.8) + 1)
		for k in n:
			var x := lerpf(x0, x1, float(k) / (n - 1))
			b._glass(Vector3(x, wy, zf - 0.02), Vector3(-1, 0, 0), 0.9, 1.7, 0.3)
			b._box("paint", Vector3(1.2, 0.24, 0.12), Vector3(x, wy + 0.97, zf - 0.05), stone)
			b._box("paint", Vector3(1.1, 0.1, 0.16), Vector3(x, wy - 0.9, zf - 0.07), stone)
		if clip > 0.0:
			# Down the side street.
			var zs := zf + 3.0
			while zs < zf + bd - 1.2:
				b._glass(Vector3(xe + e * 0.02, wy, zs), Vector3(0, 0, -e), 0.9, 1.7, 0.3)
				b._box("paint", Vector3(0.12, 0.24, 1.2), Vector3(xe + e * 0.05, wy + 0.97, zs), stone)
				b._box("paint", Vector3(0.16, 0.1, 1.1), Vector3(xe + e * 0.07, wy - 0.9, zs), stone)
				zs += 2.4
			# A three-sided bay window hung over the clipped corner.
			var out := Vector3(e, 0, -1).normalized()
			var right := Vector3(-1, 0, -e).normalized()
			var c := Vector3(xe - e * 0.55, wy, zf + 0.55) + out * 0.25
			var basis := Basis(right, Vector3.UP, out)
			b._box("paint", Vector3(1.9, 2.2, 0.7), c, trim, basis)
			b._glass(c + out * 0.36, right, 1.0, 1.6, 0.25)
			b._box("paint", Vector3(2.1, 0.16, 0.9), c + Vector3(0, 1.18, 0), trim.darkened(0.2), basis)
			b._box("paint", Vector3(2.0, 0.3, 0.8), c - Vector3(0, 1.25, 0), trim.darkened(0.1), basis)
	# The flats' door, beside the store front.
	var dx := xo + e * 1.1
	b._box("paint", Vector3(0.95, 2.2, 0.07), Vector3(dx, 1.1, zf - 0.05), bulk)
	b._box("paint", Vector3(1.2, 0.1, 0.14), Vector3(dx, 2.28, zf - 0.07), trim)
	b._quad("glass", Vector3(dx + 0.5, 2.36, zf - 0.08), Vector3(dx - 0.5, 2.36, zf - 0.08),
		Vector3(dx - 0.5, 3.0, zf - 0.08), Vector3(dx + 0.5, 3.0, zf - 0.08), PRISM, [], Vector3.FORWARD)
	b._box("concrete", Vector3(1.2, 0.12, 0.45), Vector3(dx, 0.06, zf - 0.28), Color("#b9b5ab"))


## A prewar corner store grown into a store with flats (BuildingTypes
## "mixed_use" stage 0, one storey of flats) on a corner lot: the same
## store, a storey taller, the corner building of its Main Street row.
## Empty when this lot's store isn't one (mid-block, or not a prewar
## corner store), for DenseBuilder.build_mixed to draw instead.
static func build_grown(seed: int, to_curb: float, lot: Dictionary, storeys: int, spec := {}) -> Array:
	if storeys != 2 or float(lot.get("side", 0.0)) == 0.0:
		return []
	var b := DenseBuilder._start(seed, lot, spec)
	if b.era != "prewar" or not wanted(b):
		return []
	draw(b, to_curb, float(lot.side), 1)
	b._service_yard(true)
	return b._done()


## Plate glass from x `a` to `b` along the front at `zf`: a painted wood
## bulkhead, the display glass in two or three lights, the prism transom.
static func _cs_shop_glass(b: CommercialBuilder, a: float, c: float, zf: float, gh: float, bulk: Color, trim: Color,
		r: RandomNumberGenerator) -> void:
	var w := absf(c - a)
	if w < 0.8:
		return
	var mid := (a + c) * 0.5
	b._box("paint", Vector3(w, 0.62, 0.14), Vector3(mid, 0.31, zf - 0.07), bulk)
	var n := maxi(1, roundi(w / 1.7))
	for k in n:
		var x := minf(a, c) + (k + 0.5) * w / n
		b.shopfront = CommercialBuilder.fine_parts
		b._glass(Vector3(x, 1.75, zf - 0.03), Vector3(-1, 0, 0), w / n - 0.1, 2.2, r.randf_range(0.0, 0.2))
		b.shopfront = false
		b._box("paint", Vector3(0.09, 2.3, 0.12), Vector3(minf(a, c) + k * w / n, 1.75, zf - 0.07), trim)
	b._box("paint", Vector3(0.09, 2.3, 0.12), Vector3(maxf(a, c), 1.75, zf - 0.07), trim)
	b._box("paint", Vector3(w, 0.1, 0.14), Vector3(mid, 2.9, zf - 0.07), trim)
	b._quad("glass", Vector3(maxf(a, c), 2.96, zf - 0.04), Vector3(minf(a, c), 2.96, zf - 0.04),
		Vector3(minf(a, c), gh - 0.06, zf - 0.04), Vector3(maxf(a, c), gh - 0.06, zf - 0.04), PRISM, [], Vector3.FORWARD)
	b._box("paint", Vector3(w, 0.08, 0.14), Vector3(mid, gh - 0.04, zf - 0.07), trim)


## A wood-and-glass door with its transom, facing the street.
static func _cs_front_door(b: CommercialBuilder, at: Vector3, gh: float, bulk: Color, trim: Color) -> void:
	var z := at.z - 0.05
	b._box("paint", Vector3(1.0, 2.3, 0.07), Vector3(at.x, 1.15, z), bulk)
	b._glass(Vector3(at.x, 1.45, z - 0.04), Vector3(-1, 0, 0), 0.7, 1.3, 0.0)
	for s in [-1.0, 1.0]:
		b._box("paint", Vector3(0.1, gh, 0.14), Vector3(at.x + s * 0.6, gh * 0.5, z - 0.02), trim)
	b._box("paint", Vector3(1.3, 0.1, 0.14), Vector3(at.x, 2.35, z - 0.02), trim)
	b._quad("glass", Vector3(at.x + 0.55, 2.42, z - 0.06), Vector3(at.x - 0.55, 2.42, z - 0.06),
		Vector3(at.x - 0.55, gh - 0.06, z - 0.06), Vector3(at.x + 0.55, gh - 0.06, z - 0.06), PRISM, [], Vector3.FORWARD)
	b._box("concrete", Vector3(1.4, 0.12, 0.5), Vector3(at.x, 0.06, at.z - 0.3), Color("#b9b5ab"))  # the step


## The door across the clipped corner from `p0` (on the front) to `p1` (on
## the side street): sidelights on bulkheads either side, a transom over.
static func _cs_clipped_door(b: CommercialBuilder, p0: Vector3, p1: Vector3, e: float, gh: float, bulk: Color,
		trim: Color) -> void:
	var out := Vector3(e, 0, -1).normalized()
	var right := Vector3(-1, 0, -e).normalized()  # as _glass takes it, for a face looking `out`
	var basis := Basis(right, Vector3.UP, out)
	var mid := (p0 + p1) * 0.5
	var run := p0.distance_to(p1)
	b._quad("brick", Vector3(p0.x, 0, p0.z), Vector3(p1.x, 0, p1.z), Vector3(p1.x, gh, p1.z), Vector3(p0.x, gh, p0.z),
		Color("#6b4a3a"), [], out)
	b._box("paint", Vector3(1.0, 2.25, 0.07), mid + Vector3(0, 1.13, 0) + out * 0.04, bulk, basis)
	b._glass(mid + Vector3(0, 1.45, 0) + out * 0.08, right, 0.7, 1.3, 0.0)
	var side := (run - 1.1) * 0.5
	if side > 0.3:
		for s in [-1.0, 1.0]:
			var c: Vector3 = mid + right * s * (0.55 + side * 0.5) + out * 0.05
			b._box("paint", Vector3(side, 0.62, 0.1), c + Vector3(0, 0.31, 0), bulk, basis)
			b._glass(c + Vector3(0, 1.75, 0) + out * 0.03, right, side - 0.06, 2.2, 0.0)
	b._box("paint", Vector3(run, 0.1, 0.14), mid + Vector3(0, 2.9, 0) + out * 0.06, trim, basis)
	b._glass(mid + Vector3(0, (2.96 + gh) * 0.5, 0) + out * 0.05, right, run - 0.1, gh - 3.0, 0.5)
	b._box("paint", Vector3(1.6, 0.04, 1.6), Vector3(mid.x, 0.02, mid.z) - out * 0.35, Color("#b9b5ab"), basis)  # tile step


## The postwar neighborhood market, set back for a row of stalls.
static func _cs_market(b: CommercialBuilder, r: RandomNumberGenerator, to_curb: float, side: float) -> void:
	var lw := b.half * 2.0
	var bw := clampf(lw - 3.0, 8.0, 15.0)
	var bd := clampf(b.depth - 21.0, 10.0, 15.0)
	var zf := 12.4  # a walk and a row of 90 degree stalls in front
	if zf + bd > b.depth - 1.0:
		zf = maxf(b.depth - 1.0 - bd, 8.0)
	var cx := 0.0
	var deck := r.randf_range(4.0, 4.4)
	var top := deck + 0.7
	var face := Color(BUFF[r.randi() % BUFF.size()])
	var block := Color(CommercialBuilder.BLOCK[r.randi() % 4])
	var cz := zf + bd * 0.5
	# Buff face brick across the front and round the street corner; painted
	# block down the sides and back.
	b._box("paint", Vector3(bw, deck, bd), Vector3(cx, deck * 0.5, cz), block)
	b._box("brick", Vector3(bw + 0.1, top, 0.2), Vector3(cx, top * 0.5, zf - 0.1), face)
	b._quad("membrane", Vector3(cx - bw * 0.5, deck + 0.02, zf), Vector3(cx + bw * 0.5, deck + 0.02, zf),
		Vector3(cx + bw * 0.5, deck + 0.02, zf + bd), Vector3(cx - bw * 0.5, deck + 0.02, zf + bd), b._low_slope(bw, bd, cz), [], Vector3.UP)
	b._roof_bits(cx, bw, bd, cz, deck + 0.02, false)
	b._box("paint", Vector3(bw + 0.15, 0.1, 0.3), Vector3(cx, top + 0.05, zf - 0.1), b._coping_color(false))
	# The glass front in aluminium on a low brick sill, a door at one end,
	# and a panel of glass block at the other (1950s stores lit their
	# stockrooms with it).
	var gw := bw * 0.72
	var gx := cx - bw * 0.5 + 0.6 + gw * 0.5
	if r.randf() < 0.5:
		gx = cx + bw * 0.5 - 0.6 - gw * 0.5
	b._box("brick", Vector3(gw, 0.5, 0.26), Vector3(gx, 0.25, zf - 0.23), face.darkened(0.1))
	var n := maxi(2, roundi(gw / 1.8))
	var mull: Color = CommercialBuilder.MULLION[1]
	for k in n:
		var x := gx - gw * 0.5 + (k + 0.5) * gw / n
		b.shopfront = CommercialBuilder.fine_parts and k != 0
		b._glass(Vector3(x, 1.75, zf - 0.24), Vector3(-1, 0, 0), gw / n - 0.08, 2.5, 0.0 if k == 0 else r.randf_range(0.0, 0.15))
		b.shopfront = false
		b._box("metal", Vector3(0.07, 2.6, 0.1), Vector3(x - gw / n * 0.5, 1.8, zf - 0.26), mull)
	b._box("metal", Vector3(0.07, 2.6, 0.1), Vector3(gx + gw * 0.5, 1.8, zf - 0.26), mull)
	b._box("metal", Vector3(gw, 0.08, 0.1), Vector3(gx, 3.06, zf - 0.26), mull)
	var bx := cx + bw * 0.5 - 1.2 if gx < cx else cx - bw * 0.5 + 1.2
	b._box("paint", Vector3(1.2, 1.6, 0.06), Vector3(bx, 1.9, zf - 0.22), Color("#dfe6e4"))  # glass block
	if CommercialBuilder.fine_parts:
		for row in 5:
			b._box("paint", Vector3(1.2, 0.02, 0.07), Vector3(bx, 1.1 + row * 0.32 + 0.16, zf - 0.22), Color("#b9c2c0"))
		for col in 3:
			b._box("paint", Vector3(0.02, 1.6, 0.07), Vector3(bx - 0.4 + col * 0.4, 1.9, zf - 0.22), Color("#b9c2c0"))
	# The thin flat canopy across the front on steel pipe posts, its fascia
	# carrying the sign.
	var cd := 2.4
	b._box("paint", Vector3(bw + 0.6, 0.32, cd), Vector3(cx, 3.5, zf - cd * 0.5), Color("#e8e6df"))
	b._box("paint", Vector3(bw + 0.62, 0.36, 0.06), Vector3(cx, 3.5, zf - cd), Color(["#c23a2a", "#1f3b6e", "#2d5a3a", "#e0b020"][r.randi() % 4]))
	for s in [-1.0, 1.0]:
		b._box("metal", Vector3(0.1, 3.3, 0.1), Vector3(cx + s * (bw * 0.5 + 0.1), 1.65, zf - cd + 0.2), Color("#d8d6cf"))
	b._sign(Vector3(cx, 3.75, zf - 0.22), bw * 0.6, 0.85)
	b.site.door = Vector2(gx - gw * 0.5 + gw / n * 0.5, zf)
	b._steel_door(Vector3(cx + bw * 0.3, 1.15, zf + bd + 0.03), 1.0)
	# The pylon sign by the street: a steel post and a two-sided panel,
	# on the side street's corner when there is one.
	var px := (side if side != 0.0 else -1.0) * (b.half - 1.3)
	b._box("paint", Vector3(0.22, 5.0, 0.22), Vector3(px, 2.5, 0.8), Color("#5a5e60"))
	var ps := Color(CommercialBuilder.SIGNS[r.randi() % CommercialBuilder.SIGNS.size()])
	b._box("sign" if CommercialBuilder.fine_parts else "paint", Vector3(2.4, 1.3, 0.3), Vector3(px, 5.3, 0.8), Color(ps, 0.0))
	# The walk, the row of stalls and the drive in.
	b._flat_rect("drive", cx - bw * 0.5 - 0.5, cx + bw * 0.5 + 0.5, zf - 2.2, zf, 0.08)
	var lot0 := -b.half + 0.6
	var lot1 := b.half - 0.6
	b._flat_rect("asphalt", lot0, lot1, 0.0, zf - 2.2, 0.06)
	var cut := -px * 0.4
	b._curb_cut(cut, 3.6, -to_curb, 0.0)
	if zf - 2.2 >= 11.0:
		var x := lot0
		while x <= lot1 + 0.01:
			b._flat_rect("line", x - 0.06, x + 0.06, zf - 2.2 - 5.5, zf - 2.2, 0.07, CommercialBuilder.LINE)
			x += 2.75
		b._site_row(lot0, lot1, zf - 2.2, cut)
	else:
		b.site.main_street = false
		b.site.cut_x = cut
		b.site.aisle_z = (zf - 2.2) * 0.5
