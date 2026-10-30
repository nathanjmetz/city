class_name StateMeshes
extends RefCounted
## The state layer's props (LotState's items), built from boxes, prisms and
## mounds at their real sizes, once each, and shared by every lot. Each
## mesh's origin is the middle of its footprint on the ground (a wall-hung
## one: the foot of the wall under it), its front toward -Z (the street).
## Vertex colours are sRGB; alpha marks parts for StateMats (see there).
##
## Sizes (real ones, in Marion):
##   cans: two 96-gallon carts (0.66 x 1.0 x 0.72 m bodies, 0.72 x 0.8 m
##     lids), lids up on bags heaped over the rims, two more bags beside.
##   couch: a 2.1 m three-seat sofa (0.9 m deep, seat 0.45 m, back 0.85 m),
##     a cushion off on the grass; with bit 1, a queen mattress (1.52 x
##     2.03 m) leaned on its back.
##   dumpster: a 4-yard front-load steel container (1.83 m wide, 1.22 m
##     deep, 1.25 m high, sloped front, fork pockets), one lid propped open
##     on the bags heaped in it, bags and a flattened box beside it.
##   lease: a 10 x 3 ft vinyl banner, "FOR LEASE" in 14 in letters and a
##     phone number under, tied across the boarded shop window beside the
##     door, 1.5 to 2.4 m up (under the store's own sign).
##   beds: 1 m of fresh mulch bed, 0.8 m deep: three clumps of annuals in
##     the lot's colour behind two white ones.
##   flag: a 3 x 5 ft flag on a 5 ft pole, its bracket 2.2 m up, at 45
##     degrees, the flag hanging from the pole's sleeve.
##   planters: a round cast-stone planter (0.8 m across, 0.55 m tall) with a
##     spike plant, annuals and trailing vine.

const FIXED := 1.0
const EXTRA := 0.9
const TINT := 0.65
const LEAF := 0.4
const BLOOM := 0.25
const BLOOM_FIXED := 0.15

const BAG_BLACK := Color("#1c1d1f")
const BAG_WHITE := Color("#dcdcd4")
const BAG_GREEN := Color("#2f3a2c")
const BAG_GREY := Color("#77797a")
const PLASTIC := Color("#26272a")
const MULCH := Color("#4a2e20")
const SOIL := Color("#2e241c")
const LEAVES := Color("#3d6b2e")
const CONCRETE := Color("#bdb7aa")

## kind -> ArrayMesh
static var _cache := {}

var _st := SurfaceTool.new()


static func of(kind: String) -> Mesh:
	if not _cache.has(kind):
		if kind == "car_blocks":
			_cache[kind] = load("res://scripts/state/blocked_car.gd").make()
		else:
			var m := StateMeshes.new()
			m._st.begin(Mesh.PRIMITIVE_TRIANGLES)
			m.call("_" + kind)
			_cache[kind] = m._st.commit()
	return _cache[kind]


## Triangles in a mesh (for the cost check).
static func triangles(kind: String) -> int:
	var mesh := of(kind)
	var n := 0
	for s in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


# ------------------------------------------------------------------ parts

func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color, code: float) -> void:
	col.a = code
	for p in [a, b, c]:
		_st.set_color(col)
		_st.set_normal(n)
		_st.add_vertex(p)


## A quad a-b-c-d; its face points away from `inside` (or, with none,
## toward the side a-b-c-d runs counter-clockwise round).
func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, code := FIXED, inside := Vector3.INF) -> void:
	var n := (b - a).cross(d - a)
	if n.length_squared() < 1e-12:
		n = (c - b).cross(a - b)
		if n.length_squared() < 1e-12:
			return
	n = n.normalized()
	if inside != Vector3.INF and n.dot((a + b + c + d) * 0.25 - inside) < 0.0:
		var t := b
		b = d
		d = t
		n = -n
	# Godot's front faces wind clockwise seen from in front.
	_tri(a, c, b, n, col, code)
	_tri(a, d, c, n, col, code)


## A triangle facing away from `inside`.
func _tri3(a: Vector3, b: Vector3, c: Vector3, col: Color, inside: Vector3, code := FIXED) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	_tri(a, c, b, n, col, code)


## Eight corners: bottom (y low) 0-3 then top 4-7, each ring going round
## x-, z- / x+, z- / x+, z+ / x-, z+.
func _hexa(v: Array, col: Color, code := FIXED, top := true, bottom := false) -> void:
	var mid := Vector3.ZERO
	for p in v:
		mid += p / 8.0
	for i in 4:
		var j := (i + 1) % 4
		_quad(v[i], v[j], v[j + 4], v[i + 4], col, code, mid)
	if top:
		_quad(v[4], v[5], v[6], v[7], col, code, mid)
	if bottom:
		_quad(v[3], v[2], v[1], v[0], col, code, mid)


func _box(c: Vector3, size: Vector3, col: Color, code := FIXED, b := Basis.IDENTITY, pivot := Vector3.INF) -> void:
	var h := size * 0.5
	var v := []
	for k in 8:
		var sx := -1.0 if k % 4 == 0 or k % 4 == 3 else 1.0
		var sz := -1.0 if k % 4 < 2 else 1.0
		var sy := -1.0 if k < 4 else 1.0
		var p := c + Vector3(sx * h.x, sy * h.y, sz * h.z)
		if pivot != Vector3.INF:
			p = pivot + b * (p - pivot)
		else:
			p = c + b * (p - c)
		v.append(p)
	_hexa(v, col, code, true, true)


## A round (n-sided) prism or frustum standing at `c`.
func _round(c: Vector3, r0: float, r1: float, h: float, col: Color, code := FIXED, n := 8, top := true) -> void:
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var axis := c + Vector3(0, h * 0.5, 0)
		if r1 > 0.0:
			_quad(c + d1 * r0, c + d0 * r0, c + d0 * r1 + Vector3(0, h, 0), c + d1 * r1 + Vector3(0, h, 0), col, code, axis)
		else:
			_tri3(c + d1 * r0, c + d0 * r0, c + Vector3(0, h, 0), col, axis - Vector3(0, h * 0.4, 0), code)
		if top and r1 > 0.0:
			_tri3(c + Vector3(0, h, 0), c + d1 * r1 + Vector3(0, h, 0), c + d0 * r1 + Vector3(0, h, 0), col, c, code)


## A low dome of leaves or flowers: a ring and a rounded top.
func _mound(c: Vector3, r: float, h: float, col: Color, code: float, n := 6) -> void:
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var top := c + Vector3(0, h, 0)
		var m0 := c + d0 * r + Vector3(0, h * 0.55, 0)
		var m1 := c + d1 * r + Vector3(0, h * 0.55, 0)
		_quad(c + d1 * r * 0.8, c + d0 * r * 0.8, m0, m1, col, code, c + Vector3(0, h * 0.3, 0))
		_tri3(top, m1, m0, col, c, code)


## A tied trash bag sitting at `c`: a fat six-sided body, the neck
## gathered to a knot.
func _bag(c: Vector3, r: float, h: float, col: Color, lean := 0.0) -> void:
	var rings := [[0.0, r * 0.85], [h * 0.15, r], [h * 0.62, r * 0.95], [h * 0.85, r * 0.35], [h, r * 0.12]]
	var n := 6
	var tip := Vector3(lean, 0, lean * 0.5)
	for k in rings.size() - 1:
		var y0: float = rings[k][0]
		var y1: float = rings[k + 1][0]
		for i in n:
			var a0 := TAU * i / n + k * 0.3
			var a1 := TAU * (i + 1) / n + k * 0.3
			var o0 := tip * (y0 / h)
			var o1 := tip * (y1 / h)
			var p00 := c + o0 + Vector3(cos(a0) * rings[k][1], y0, sin(a0) * rings[k][1])
			var p01 := c + o0 + Vector3(cos(a1) * rings[k][1], y0, sin(a1) * rings[k][1])
			var p10 := c + o1 + Vector3(cos(a0 + 0.3) * rings[k + 1][1], y1, sin(a0 + 0.3) * rings[k + 1][1])
			var p11 := c + o1 + Vector3(cos(a1 + 0.3) * rings[k + 1][1], y1, sin(a1 + 0.3) * rings[k + 1][1])
			_quad(p01, p00, p10, p11, col, FIXED, c + Vector3(0, y0 + (y1 - y0) * 0.5, 0) + tip * ((y0 + y1) * 0.5 / h))
	# The knot's two ears.
	var k := c + tip + Vector3(0, h, 0)
	_tri3(k, k + Vector3(-0.07, 0.07, 0.02), k + Vector3(0.0, 0.02, 0.03), col, k + Vector3(0, 0, -1))
	_tri3(k, k + Vector3(0.07, 0.06, -0.02), k + Vector3(0.0, 0.02, -0.03), col, k + Vector3(0, 0, 1))


# ------------------------------------------------------------------ props

## Two 96-gallon carts out at the curb, lids up on the bags.
func _cans() -> void:
	for i in 2:
		var x := -0.75 + i * 0.84
		var code := TINT if i == 0 else FIXED
		var body := Color.WHITE if i == 0 else Color("#2f4f8a")  # the recycling cart is blue
		# Tapered a little toward the foot, as a cart is.
		_hexa([Vector3(x - 0.3, 0.04, -0.33), Vector3(x + 0.3, 0.04, -0.33), Vector3(x + 0.3, 0.04, 0.33),
			Vector3(x - 0.3, 0.04, 0.33), Vector3(x - 0.33, 1.0, -0.37), Vector3(x + 0.33, 1.0, -0.37),
			Vector3(x + 0.33, 1.0, 0.36), Vector3(x - 0.33, 1.0, 0.36)], body, code, false)
		# The rim, and the handle bar and wheels at the back (toward the house).
		_box(Vector3(x, 0.99, 0.0), Vector3(0.7, 0.04, 0.76), body.darkened(0.1), code)
		_box(Vector3(x, 0.98, 0.43), Vector3(0.5, 0.04, 0.05), PLASTIC)
		for s in [-1.0, 1.0]:
			_round(Vector3(x + s * 0.3, 0.1, 0.33), 0.1, 0.1, 0.06, PLASTIC, FIXED, 6)
		# Bags heaped over the rim, the lid up behind them on its hinge.
		var heap := [BAG_BLACK, BAG_WHITE] if i == 0 else [BAG_GREY, BAG_BLACK]
		_bag(Vector3(x - 0.1, 0.82, -0.05), 0.24, 0.5, heap[0], 0.05)
		_bag(Vector3(x + 0.13, 0.86, 0.08), 0.21, 0.45, heap[1], -0.06)
		var lid_tilt := -1.95 if i == 0 else -1.7
		_box(Vector3(x, 1.0, -0.01), Vector3(0.72, 0.05, 0.8), body.darkened(0.15), code,
			Basis(Vector3.RIGHT, lid_tilt), Vector3(x, 1.02, 0.39))
	# Two more bags on the grass beside them.
	_bag(Vector3(0.72, 0.0, -0.12), 0.27, 0.55, BAG_BLACK, 0.06)
	_bag(Vector3(0.66, 0.0, 0.34), 0.22, 0.45, BAG_WHITE, -0.05)
	_bag(Vector3(1.0, 0.0, 0.12), 0.2, 0.4, BAG_GREEN, 0.04)


## An old three-seat sofa at the curb (and, with bit 1, a mattress leaned on it).
func _couch() -> void:
	var wood := Color("#3a2a1e")
	for x in [-0.95, 0.95]:
		for z in [-0.38, 0.38]:
			_box(Vector3(x, 0.05, z), Vector3(0.06, 0.1, 0.06), wood)
	# The frame, back and arms in the fabric.
	_box(Vector3(0, 0.27, 0.0), Vector3(2.1, 0.34, 0.9), Color.WHITE, TINT)
	# The back, tall and rolled over at the top, leaning back a little.
	_box(Vector3(0, 0.66, 0.3), Vector3(1.78, 0.56, 0.26), Color.WHITE, TINT, Basis(Vector3.RIGHT, -0.14))
	_box(Vector3(0, 0.95, 0.35), Vector3(1.8, 0.12, 0.3), Color.WHITE, TINT)
	for s in [-1.0, 1.0]:
		_box(Vector3(s * 0.95, 0.5, 0.0), Vector3(0.2, 0.3, 0.9), Color.WHITE, TINT)
		_box(Vector3(s * 0.95, 0.68, 0.0), Vector3(0.26, 0.1, 0.92), Color.WHITE, TINT)
	# Two seat cushions sagging in place, lighter where the sun faded them;
	# the third off on the grass.
	for x in [-0.42, 0.42]:
		_box(Vector3(x, 0.5, -0.07), Vector3(0.8, 0.15, 0.66), Color.WHITE, TINT,
			Basis(Vector3.FORWARD, 0.04 if x < 0.0 else -0.06))
	_box(Vector3(1.6, 0.08, -0.5), Vector3(0.8, 0.15, 0.62), Color.WHITE, TINT,
		Basis(Vector3.UP, 0.6) * Basis(Vector3.FORWARD, 0.18))
	# The mattress, leaned on the back from behind the couch, its top over it.
	var b := Basis(Vector3.RIGHT, -1.08)
	var c := Vector3(0.05, 0.72, 0.78)
	_box(c, Vector3(2.03, 1.52, 0.25), Color("#d9d6cc"), EXTRA, b)
	# A blue border round its quilted face (the street side), and a stain.
	var n := b * Vector3(0, 0, -1)
	var u := b * Vector3(0, 1, 0)
	var face := c + n * 0.13
	for e in [[Vector3.RIGHT * 1.0, u * 0.73], [Vector3.RIGHT * 1.0, -u * 0.73]]:
		var mid: Vector3 = face + e[1]
		_quad(mid - e[0] + n * 0.002, mid + e[0] + n * 0.002, mid + e[0] - e[1].normalized() * 0.06 + n * 0.002,
			mid - e[0] - e[1].normalized() * 0.06 + n * 0.002, Color("#8fa2bb"), EXTRA, c)
	var sp := face + u * 0.15 + Vector3.RIGHT * 0.35 + n * 0.003
	_quad(sp - Vector3.RIGHT * 0.22 - u * 0.15, sp + Vector3.RIGHT * 0.18 - u * 0.12, sp + Vector3.RIGHT * 0.2 + u * 0.14,
		sp - Vector3.RIGHT * 0.2 + u * 0.16, Color("#b8a47e"), EXTRA, c)


## A 4-yard steel dumpster, one lid propped open on the bags heaped in it,
## and the overflow on the ground beside it (at +x).
func _dumpster() -> void:
	var x0 := -1.37
	var x1 := 0.46
	var cx := (x0 + x1) * 0.5
	# The bin: sloped front (toward -z), straight back.
	_hexa([Vector3(x0, 0.12, -0.5), Vector3(x1, 0.12, -0.5), Vector3(x1, 0.12, 0.6), Vector3(x0, 0.12, 0.6),
		Vector3(x0, 1.3, -0.68), Vector3(x1, 1.3, -0.68), Vector3(x1, 1.3, 0.6), Vector3(x0, 1.3, 0.6)],
		Color.WHITE, TINT, false, true)
	# Skids, the top rail and the fork pockets on each side.
	for z in [-0.4, 0.5]:
		_box(Vector3(cx, 0.06, z), Vector3(1.83, 0.12, 0.1), Color("#2b2b2b"))
	_box(Vector3(cx, 1.31, -0.67), Vector3(1.87, 0.06, 0.06), Color.WHITE, TINT)
	for x in [x0 - 0.05, x1 + 0.05]:
		_box(Vector3(x, 0.92, 0.0), Vector3(0.1, 0.16, 1.05), Color("#2b2b2b"))
	# Rust run down the front from the rail.
	for x in [cx - 0.55, cx + 0.2, cx + 0.62]:
		_quad(Vector3(x - 0.05, 0.3, -0.535), Vector3(x + 0.05, 0.3, -0.535), Vector3(x + 0.06, 1.24, -0.665),
			Vector3(x - 0.06, 1.24, -0.665), Color("#6b4a32"), FIXED, Vector3(x, 0.7, 0.0))
	# The bags heaped in the open half, over the rim.
	_bag(Vector3(cx - 0.45, 1.0, 0.0), 0.3, 0.55, BAG_BLACK, 0.08)
	_bag(Vector3(cx - 0.05, 1.05, -0.2), 0.27, 0.5, BAG_WHITE, -0.05)
	_bag(Vector3(cx - 0.3, 1.2, 0.25), 0.26, 0.48, BAG_GREEN, 0.04)
	_bag(Vector3(cx + 0.45, 1.1, 0.15), 0.27, 0.45, BAG_BLACK)
	# Black plastic lids hinged at the back: the left one flung open over
	# the back, the right one riding up on the bags.
	_box(Vector3(cx - 0.46, 1.32, 0.0), Vector3(0.9, 0.05, 1.3), PLASTIC, FIXED,
		Basis(Vector3.RIGHT, -2.1), Vector3(cx - 0.46, 1.33, 0.62))
	_box(Vector3(cx + 0.46, 1.32, 0.0), Vector3(0.9, 0.05, 1.3), PLASTIC, FIXED,
		Basis(Vector3.RIGHT, -0.3), Vector3(cx + 0.46, 1.33, 0.62))
	# On the ground beside it: bags and a flattened carton leaned on its side.
	_bag(Vector3(0.85, 0.0, -0.25), 0.3, 0.55, BAG_BLACK, 0.05)
	_bag(Vector3(1.2, 0.0, 0.15), 0.27, 0.5, BAG_WHITE, -0.04)
	_bag(Vector3(0.82, 0.0, 0.35), 0.24, 0.45, BAG_GREEN, 0.03)
	_box(Vector3(0.6, 0.45, 0.0), Vector3(0.05, 0.85, 0.75), Color("#a27d52"), FIXED, Basis(Vector3.FORWARD, 0.25))


## 5 x 7 block letters for the banner.
const FONT := {
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
}


## "FOR LEASE" on a white vinyl banner hung on the wall at z 0.
func _lease() -> void:
	var y0 := 1.5
	var w := 3.05
	var h := 0.91
	var z := -0.03
	var wall := Vector3(0, y0 + h * 0.5, 1.0)
	_quad(Vector3(-w * 0.5, y0, z), Vector3(w * 0.5, y0, z), Vector3(w * 0.5, y0 + h, z), Vector3(-w * 0.5, y0 + h, z),
		Color("#f3f1ea"), FIXED, wall)
	# Its hem, grommets at the corners.
	for c in [Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)]:
		var p := Vector3(c.x * (w * 0.5 - 0.06), y0 + 0.06 + c.y * (h - 0.12), z - 0.004)
		_quad(p + Vector3(-0.025, -0.025, 0), p + Vector3(0.025, -0.025, 0), p + Vector3(0.025, 0.025, 0),
			p + Vector3(-0.025, 0.025, 0), Color("#9a9a96"), FIXED, wall)
	# The letters, in the instance's colour, 14 in (0.36 m) tall.
	var px := 0.052
	var text := "FOR LEASE"
	var x := -text.length() * 6 * px * 0.5 + px * 0.5
	var top := y0 + h - 0.1
	for ch in text:
		if FONT.has(ch):
			var rows: Array = FONT[ch]
			for r in 7:
				var row: String = rows[r]
				var c := 0
				while c < 5:
					if row[c] != "#":
						c += 1
						continue
					var e := c
					while e < 5 and row[e] == "#":
						e += 1
					# Read from the street (-z), where +x is on the left.
					var a := Vector3(-(x + e * px), top - (r + 1) * px, z - 0.003)
					var b := Vector3(-(x + c * px), top - r * px, z - 0.003)
					_quad(a, Vector3(b.x, a.y, a.z), b, Vector3(a.x, b.y, a.z), Color.WHITE, TINT, wall)
					c = e
		x += 6 * px
	# The phone number under it, a line of small figures.
	var fx := -0.62
	for i in 12:
		if i != 3 and i != 7:
			_quad(Vector3(fx, y0 + 0.1, z - 0.003), Vector3(fx + 0.07, y0 + 0.1, z - 0.003),
				Vector3(fx + 0.07, y0 + 0.21, z - 0.003), Vector3(fx, y0 + 0.21, z - 0.003), Color("#2a2a2a"), FIXED, wall)
		fx += 0.105


## A 1 m piece of fresh mulch bed: a row of annuals in the lot's colour
## and white ones in front, edged against the lawn.
func _beds() -> void:
	_box(Vector3(0, 0.04, 0), Vector3(1.0, 0.08, 0.8), MULCH)
	# Black edging along the lawn side.
	_box(Vector3(0, 0.05, -0.41), Vector3(1.0, 0.1, 0.02), Color("#1e1e1e"))
	for i in 3:
		var p := Vector3(-0.33 + i * 0.33, 0.07, 0.14)
		_mound(p, 0.2, 0.26, LEAVES, LEAF)
		_mound(p + Vector3(0, 0.13, 0), 0.19, 0.18, Color.WHITE, BLOOM)
	for i in 2:
		var p := Vector3(-0.17 + i * 0.34, 0.07, -0.2)
		_mound(p, 0.15, 0.16, LEAVES, LEAF)
		_mound(p + Vector3(0, 0.08, 0), 0.14, 0.12, Color("#f4f1e8"), BLOOM_FIXED)


## The flag on its bracket, 2.2 m up the wall or porch post.
func _flag() -> void:
	var base := Vector3(0, 2.2, 0)
	var out := Vector3(0, 0.7071, -0.7071)
	_box(base + Vector3(0, 0, 0.0), Vector3(0.08, 0.14, 0.06), Color("#2a2a2a"))
	_box(base + out * 0.76, Vector3(0.028, 0.028, 1.52), Color("#d8d8d2"), FIXED, Basis(Vector3.RIGHT, PI * 0.25))
	_round(base + out * 1.53, 0.035, 0.0, 0.08, Color("#c9a43a"), FIXED, 5)
	# The flag hangs from its sleeve along the pole: thirteen stripes across
	# the hoist (the top one at the tip), five feet down, with a fold in it;
	# the union at the tip, seven stripes wide and two feet down.
	var red := Color("#b22234")
	var white := Color("#f2efe8")
	var blue := Color("#3c3b6e")
	var t_tip := 1.46
	var sw := 0.914 / 13.0
	var drop := 1.52
	for k in 13:
		var a := base + out * (t_tip - k * sw)
		var b := base + out * (t_tip - (k + 1) * sw)
		var col := red if k % 2 == 0 else white
		var split := drop * 0.4 if k < 7 else 0.0
		if split > 0.0:
			_hang(a, b, 0.0, split, blue)
		_hang(a, b, split, drop, col)


## One strip of the flag from `d0` to `d1` metres below the pole, folded
## once at the middle of its fall.
func _hang(a: Vector3, b: Vector3, d0: float, d1: float, col: Color) -> void:
	var fold := Vector3(0.07, 0, 0)
	var mid := 0.76
	var pts := [d0, d1] if d1 <= mid or d0 >= mid else [d0, mid, d1]
	for i in pts.size() - 1:
		var y0: float = pts[i]
		var y1: float = pts[i + 1]
		var o0 := fold * sin(PI * clampf(y0 / 1.52, 0.0, 1.0))
		var o1 := fold * sin(PI * clampf(y1 / 1.52, 0.0, 1.0))
		_quad(a - Vector3(0, y0, 0) + o0, b - Vector3(0, y0, 0) + o0, b - Vector3(0, y1, 0) + o1, a - Vector3(0, y1, 0) + o1,
			col, FIXED, a - Vector3(1, y0, 0))


## A round cast-stone planter by a shop door, planted for the summer.
func _planters() -> void:
	_round(Vector3.ZERO, 0.33, 0.4, 0.5, CONCRETE, FIXED, 10, false)
	_round(Vector3(0, 0.5, 0), 0.42, 0.42, 0.06, CONCRETE.darkened(0.06), FIXED, 10)
	_round(Vector3(0, 0.5, 0), 0.37, 0.37, 0.065, SOIL, FIXED, 10)
	# A spike plant in the middle, annuals round it, vine over the rim.
	_round(Vector3(0, 0.55, 0), 0.12, 0.0, 0.7, Color("#4e6b38"), LEAF, 5, false)
	for i in 5:
		var a := TAU * i / 5.0
		var p := Vector3(cos(a) * 0.24, 0.55, sin(a) * 0.24)
		_mound(p, 0.15, 0.2, LEAVES, LEAF)
		_mound(p + Vector3(0, 0.1, 0), 0.13, 0.13, Color.WHITE, BLOOM)
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		var p := Vector3(cos(a) * 0.43, 0.25, sin(a) * 0.43)
		_box(p, Vector3(0.1, 0.4, 0.1), Color("#5f8a3a"), LEAF, Basis(Vector3.UP, a))
