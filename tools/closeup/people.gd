extends RefCounted
## Prototype people for the close-up lab (tools/closeup_lab.gd): shaped,
## dressed walkers at three levels of detail, sized from US adult body
## measurements (CDC NHANES: men 1.75 m, women 1.62 m; ANSUR shoulder and
## hip breadths). Not used by the game yet: a proposal to compare.
##
## Origin at the feet, facing -Z. Vertex alpha codes the surface: 0 shirt
## (each person's own colour), 0.25 trousers, 0.5 skin, 0.75 hair (from
## palettes picked per person), 1 a fixed colour. UV.x is a limb's swing
## (sign and size), UV.y its hip or shoulder height; UV2.x marks a shin (1)
## or forearm (2) that bends at the knee or elbow, UV2.y that joint's height.

const SHIRT := 0.0
const TROUSERS := 0.25
const SKIN := 0.5
const HAIR := 0.75
const FIXED := 1.0

var st := SurfaceTool.new()
var sides := 6
var lvl := 1
var _uv := Vector2.ZERO
var _uv2 := Vector2.ZERO
var _col := Color(0, 0, 0, 0)


## level 1: shaped (browser), 2: dressed with knees and elbows, 3: hands,
## face and clothing seams. body: man, woman, child, older. outfit keys:
## sleeve (short/long), jacket, hood, cap (Color), hair (short/long/pony),
## bag (backpack/tote), boots, khaki.
static func build(level: int, body: String, outfit: Dictionary, seated := false, code_override := -1.0) -> Mesh:
	var b = load("res://tools/closeup/people.gd").new()
	b.lvl = level
	b.sides = [6, 6, 8, 12][level]
	b.st.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._person(body, outfit, seated)
	var mesh: Mesh = b.st.commit()
	return mesh


func _c(code: float, rgb := Color(1, 1, 1)) -> void:
	_col = Color(rgb.r, rgb.g, rgb.b, code)


func _v(p: Vector3, n: Vector3) -> void:
	st.set_color(_col)
	st.set_uv(_uv)
	st.set_uv2(_uv2)
	st.set_normal(n)
	st.add_vertex(p)


## A tapered tube from a to b, flattened by `flat` (x across, y front to
## back), with domed ends.
func tube(a: Vector3, b: Vector3, ra: float, rb: float, flat := Vector2.ONE, caps := true) -> void:
	var axis := (b - a).normalized()
	var u := Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD
	u = (u - axis * axis.dot(u)).normalized()
	var w := axis.cross(u)
	var n := sides
	var ring_a := []
	var ring_b := []
	var nrm := []
	for i in n:
		var t := TAU * i / n
		var d := u * cos(t) * flat.x + w * sin(t) * flat.y
		ring_a.append(a + d * ra)
		ring_b.append(b + d * rb)
		nrm.append((u * cos(t) / flat.x + w * sin(t) / flat.y).normalized())
	for i in n:
		var j := (i + 1) % n
		_v(ring_a[i], nrm[i]); _v(ring_b[i], nrm[i]); _v(ring_b[j], nrm[j])
		_v(ring_a[i], nrm[i]); _v(ring_b[j], nrm[j]); _v(ring_a[j], nrm[j])
	if caps:
		var ta := a - axis * ra * 0.6
		var tb := b + axis * rb * 0.6
		for i in n:
			var j := (i + 1) % n
			_v(ring_a[j], nrm[j]); _v(ta, -axis); _v(ring_a[i], nrm[i])
			_v(ring_b[i], nrm[i]); _v(tb, axis); _v(ring_b[j], nrm[j])


## An ellipsoid, or the part of it from latitude `lo` up (radians), leaving
## out the face below `face` latitude in front (for hair).
func blob(c: Vector3, r: Vector3, lo := -PI / 2, face := -9.0, rings := 0) -> void:
	var seg := sides + 2
	var rn := rings if rings > 0 else maxi(3, sides / 2 + 1)
	var pts := []
	for k in rn + 1:
		var lat := lerpf(lo, PI / 2, float(k) / rn)
		var row := []
		for i in seg:
			var lon := TAU * i / seg
			var d := Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
			row.append([c + d * r, Vector3(d.x / r.x, d.y / r.y, d.z / r.z).normalized(), lat, d.z])
		pts.append(row)
	for k in rn:
		for i in seg:
			var j := (i + 1) % seg
			var p: Array = [pts[k][i], pts[k][j], pts[k + 1][j], pts[k + 1][i]]
			# Leave the face open below the hairline (front is -Z).
			if face > -9.0 and p[0][3] < -0.35 and p[1][3] < -0.35 and p[0][2] < face:
				continue
			_v(p[0][0], p[0][1]); _v(p[2][0], p[2][1]); _v(p[1][0], p[1][1])
			_v(p[0][0], p[0][1]); _v(p[3][0], p[3][1]); _v(p[2][0], p[2][1])


## The torso lofted through rings [y, half width, half depth, z offset].
func loft(rings: Array, lean := 0.0) -> void:
	var n := sides + 2
	var prev := []
	var prev_n := []
	for r in rings:
		var row := []
		var nr := []
		var z0: float = r[3] + lean * (r[0] - rings[0][0])
		for i in n:
			var t := TAU * i / n
			row.append(Vector3(sin(t) * r[1], r[0], z0 + cos(t) * r[2]))
			nr.append(Vector3(sin(t) / r[1], 0.0, cos(t) / r[2]).normalized())
		if not prev.is_empty():
			for i in n:
				var j := (i + 1) % n
				_v(prev[i], prev_n[i]); _v(row[j], nr[j]); _v(row[i], nr[i])
				_v(prev[i], prev_n[i]); _v(prev[j], prev_n[j]); _v(row[j], nr[j])
		prev = row
		prev_n = nr
	# Top cap (shoulders), lifted a little in the middle.
	var top: Array = rings[rings.size() - 1]
	var ct := Vector3(0, top[0] + 0.03, top[3] + lean * (top[0] - rings[0][0]))
	for i in n:
		_v(prev[i], prev_n[i]); _v(prev[(i + 1) % n], prev_n[(i + 1) % n]); _v(ct, Vector3.UP)


func _box(c: Vector3, h: Vector3) -> void:
	var v := []
	for i in 8:
		v.append(c + Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		var nrm: Vector3 = ((v[f[0]] + v[f[2]]) * 0.5 - c).normalized()
		for t in [[0, 1, 2], [0, 2, 3]]:
			for k in t:
				_v(v[f[k]], nrm)


func _person(body: String, o: Dictionary, seated: bool) -> void:
	var H: float = {"man": 1.76, "woman": 1.63, "child": 1.3, "older": 1.71}[body]
	var female := body == "woman"
	var child := body == "child"
	var sh: float = (0.205 if not female else 0.18) * (0.78 if child else 1.0)  # half shoulder breadth
	var hip: float = (0.165 if not female else 0.185) * (0.8 if child else 1.0)
	var bulk: float = 1.18 if o.get("jacket", false) or o.get("hood", false) else 1.0
	var head_h := H * (0.13 if not child else 0.16)
	var hy := H * 0.52          # hip joint
	var ky := H * 0.285         # knee
	var ay := H * 0.045         # ankle
	var shy := H * 0.818        # shoulder joint
	var ey := H * 0.625         # elbow
	var wy := H * 0.485         # wrist
	var chin := H - head_h
	var stoop := 0.06 if body == "older" else 0.0
	var trousers := Color(0.62, 0.55, 0.42) if o.get("khaki", false) else Color.WHITE
	var tcode := FIXED if o.get("khaki", false) else TROUSERS
	var shoe := Color(0.33, 0.22, 0.13) if o.get("boots", false) else Color(0.12, 0.12, 0.13)
	if o.has("shoe"):
		shoe = o.shoe
	var lean := -0.25 if seated else 0.0
	# Where the hips, knees and feet go: standing, or sat in a car seat.
	var legs := []
	for s in [-1.0, 1.0]:
		var x: float = s * hip * 0.55
		if seated:
			legs.append([Vector3(x, hy, 0.0), Vector3(x * 1.2, hy + 0.06, -H * 0.25), Vector3(x * 1.2, hy - H * 0.18, -H * 0.31)])
		else:
			legs.append([Vector3(x, hy, 0.0), Vector3(x, ky, 0.0), Vector3(x, ay, 0.0)])
	# Legs: thigh and shin; the shin bends at the knee on the move.
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var L: Array = legs[i]
		_uv = Vector2(s, hy) if not seated else Vector2.ZERO
		_uv2 = Vector2.ZERO
		_c(tcode, trousers)
		tube(L[0], L[1], H * 0.05 * (1.08 if female else 1.0), H * 0.034)
		if lvl >= 2 and not seated:
			_uv2 = Vector2(1, ky)
		tube(L[1], L[2] + Vector3(0, 0.03, 0), H * 0.034, H * 0.026)
		_c(FIXED, shoe)
		var foot: Vector3 = L[2] + Vector3(0, -ay * 0.45, -0.06)
		if lvl >= 3:
			blob(foot, Vector3(0.05, 0.045, 0.13), -0.3)
			_c(FIXED, Color(0.85, 0.83, 0.8) if not o.get("boots", false) else Color(0.1, 0.08, 0.06))
			_box(foot + Vector3(0, -0.035, 0), Vector3(0.05, 0.012, 0.13))
		else:
			blob(foot, Vector3(0.05, 0.05, 0.13), -PI / 2, -9.0, 3)
	_uv = Vector2.ZERO
	_uv2 = Vector2.ZERO
	# Torso: hips, waist, chest, shoulders. Trousers up to the belt.
	var w := 1.0 if not child else 0.85
	_c(tcode, trousers)
	var pelvis := [[hy - 0.06, hip * 1.05, 0.11 * w, 0.0], [hy + H * 0.06, hip * 1.02, 0.105 * w, 0.0]]
	loft(pelvis, lean)
	var top_z := stoop
	_c(SHIRT)
	var tors := [
		[hy + H * 0.05, hip * bulk, 0.105 * w * bulk, 0.0],
		[hy + H * 0.13, (hip * 0.9 if female else sh * 0.8) * bulk, 0.1 * w * bulk, 0.0],
		[shy - H * 0.08, sh * 0.95 * bulk, (0.12 if female else 0.115) * w * bulk, top_z * 0.5],
		[shy + 0.01, sh * 0.82 * bulk, 0.09 * w * bulk, top_z],
	]
	if o.get("jacket", false) and not seated:
		tors[0] = [hy - 0.05, hip * 1.15, 0.12 * w, 0.0]  # jacket hangs past the belt
	loft(tors, lean)
	var neck_base := Vector3(0, shy + 0.01, top_z + lean * (shy - hy))
	# Arms: upper arm and forearm; the forearm bends at the elbow.
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var sp := Vector3(s * sh * bulk, shy - 0.02, top_z + lean * (shy - hy))
		var ep: Vector3
		var wp: Vector3
		if seated:
			ep = sp + Vector3(s * 0.04, -H * 0.17, -H * 0.06)
			wp = ep + Vector3(-s * 0.05, H * 0.03, -H * 0.15)
		else:
			ep = Vector3(sp.x + s * 0.02, ey, stoop * 0.6)
			wp = Vector3(sp.x + s * 0.02, wy, stoop * 0.3)
		_uv = Vector2(-s * 0.7, shy) if not seated else Vector2.ZERO
		_uv2 = Vector2.ZERO
		var long_sleeve: bool = o.get("sleeve", "long") == "long" or o.get("jacket", false) or o.get("hood", false)
		_c(SHIRT)
		if lvl >= 2:
			blob(sp + Vector3(0, -0.01, 0), Vector3(0.06, 0.06, 0.065) * bulk, -0.3, -9.0, 3)
		if long_sleeve:
			tube(sp, ep, H * 0.03 * bulk, H * 0.026 * bulk)
		else:
			var mid := sp.lerp(ep, 0.45)
			tube(sp, mid, H * 0.032, H * 0.029)
			_c(SKIN)
			tube(mid, ep, H * 0.024, H * 0.022, Vector2.ONE, false)
		if lvl >= 2 and not seated:
			_uv2 = Vector2(2, ey)
		_c(SHIRT if long_sleeve else SKIN)
		tube(ep, wp, H * (0.024 if long_sleeve else 0.021) * (bulk if long_sleeve else 1.0), H * 0.018)
		_c(SKIN)
		var hand: Vector3 = wp + (wp - ep).normalized() * 0.07
		if lvl >= 3:
			blob(hand, Vector3(0.022, 0.05, 0.04), -PI / 2, -9.0, 3)
			blob(hand + Vector3(-s * 0.0, 0.01, -0.035), Vector3(0.012, 0.03, 0.012), -PI / 2, -9.0, 2)
		elif lvl >= 2:
			blob(hand, Vector3(0.022, 0.05, 0.04), -PI / 2, -9.0, 2)
	_uv = Vector2.ZERO
	_uv2 = Vector2.ZERO
	# Neck and head.
	var head_c := neck_base + Vector3(0, H * 0.035 + head_h * 0.5, -0.01 + stoop * 0.5 + lean * 0.12)
	_c(SKIN)
	tube(neck_base + Vector3(0, -0.02, 0), head_c + Vector3(0, -head_h * 0.35, 0.01), H * 0.032, H * 0.03, Vector2.ONE, false)
	var hr := Vector3(head_h * 0.36, head_h * 0.5, head_h * 0.45)
	blob(head_c, hr)
	if lvl >= 3:
		# Nose, ears, brow shadow and eyes: a few pixels at the closest zoom.
		tube(head_c + Vector3(0, 0.0, -hr.z * 0.9), head_c + Vector3(0, -0.03, -hr.z * 1.08), 0.012, 0.016, Vector2(0.8, 1.0))
		for s in [-1.0, 1.0]:
			blob(head_c + Vector3(s * hr.x * 0.98, -0.005, 0.01), Vector3(0.012, 0.03, 0.02), -PI / 2, -9.0, 2)
			_c(FIXED, Color(0.08, 0.06, 0.05))
			blob(head_c + Vector3(s * hr.x * 0.4, 0.015, -hr.z * 0.88), Vector3(0.012, 0.007, 0.006), -PI / 2, -9.0, 2)
			_c(SKIN)
	# Hair, then a cap or hood over it.
	_c(HAIR)
	var hair: String = o.get("hair", "short")
	if hair != "none":
		var back := -0.9 if hair == "long" else -0.25
		blob(head_c + Vector3(0, 0.008, 0.008), hr * 1.07, back, 0.45)
		if hair == "pony":
			tube(head_c + Vector3(0, 0.02, hr.z * 0.95), head_c + Vector3(0, -0.14, hr.z * 1.25), 0.03, 0.018)
	if o.has("cap"):
		_c(FIXED, o.cap)
		blob(head_c + Vector3(0, 0.03, 0.005), hr * Vector3(1.1, 0.95, 1.08), 0.15, -9.0, 3)
		_box(head_c + Vector3(0, 0.045, -hr.z - 0.04), Vector3(hr.x * 0.85, 0.006, 0.055))
	if o.get("hood", false):
		_c(SHIRT)
		tube(neck_base + Vector3(0, 0.02, 0.07), neck_base + Vector3(0, 0.06, 0.12), 0.1, 0.07, Vector2(1.4, 0.6))
	if o.get("jacket", false) and lvl >= 2:
		_c(SHIRT)
		tube(neck_base + Vector3(0, -0.01, 0.01), neck_base + Vector3(0, 0.05, 0.02), 0.075, 0.07, Vector2(1.0, 0.85), false)  # collar
	# Bags.
	var bag: String = o.get("bag", "")
	if bag == "backpack":
		_c(FIXED, o.get("bag_col", Color(0.15, 0.22, 0.4)))
		_box(Vector3(0, shy - H * 0.15, 0.12 * w * bulk + 0.07), Vector3(sh * 0.7, H * 0.12, 0.07))
	elif bag == "tote":
		_c(FIXED, o.get("bag_col", Color(0.45, 0.28, 0.18)))
		_box(Vector3(sh * bulk + 0.06, hy + 0.02, 0.02), Vector3(0.03, 0.13, 0.17))
		tube(Vector3(sh * bulk + 0.03, hy + 0.13, 0.0), Vector3(sh * 0.8, shy, 0.0), 0.008, 0.008, Vector2.ONE, false)
	if lvl >= 3 and not seated:
		# Belt and a dark seam down the trouser legs.
		_c(FIXED, Color(0.12, 0.09, 0.07))
		loft([[hy + H * 0.045, hip * 1.04, 0.108 * w, 0.0], [hy + H * 0.06, hip * 1.04, 0.108 * w, 0.0]])
