class_name FrameBuilder
extends RefCounted
## The bare structure of a building, worked out from the finished building's
## own mesh, so it fits whatever any builder makes (HouseBuilder,
## CommercialBuilder, CivicBuilder, WarehouseBuilder, FarmBuilder) without
## each one drawing its frame by hand.
##
## Every large flat face of the finished building is a wall, a roof slope or
## a ceiling. Members are laid along each one at real spacing, on a grid
## shared by every face in the same plane, so a gable end and the wall under
## it frame as one wall with studs that run up into the peak, and a hip roof
## gets jack rafters that shorten toward the corners. Windows and doors on a
## wall (smaller boxes standing just proud of it) become rough openings:
## studs stop at a header above and a sill below.
##
##   wood    platform framing: 2x4 studs 16 in on centre, doubled top plate,
##           a floor band every storey, 2x6 rafters or trusses at 24 in
##   steel   wide-flange columns on 25 ft bays, girts every 5 ft, bar joists
##           at 5 ft (pre-engineered and steel-and-block buildings)
##   pole    6x6 posts 8 ft apart, 2x4 girts at 24 in, trusses at 8 ft and
##           purlins at 24 in (post-frame barns)
##   tilt_up 25 ft concrete wall panels, each held by pipe braces, and steel
##           joists for the roof
##
## Output: an Array of ArrayMeshes, the members split in the order they go
## up (walls before roof, lowest first, around the building), so a view can
## show more of them as the stage goes on.

const LUMBER := Color("#cdb07a")  # fresh spruce-pine-fir
const PRIMER := Color("#7a3d2c")  # red-oxide primer on structural steel
const GALV := Color("#9aa0a4")    # galvanized girts and purlins
const PANEL := Color("#b9b5ab")   # fresh tilt-up concrete
const BRACE := Color("#5a5e61")
## Chunks the members are split into.
const CHUNKS := 6

const SPECS := {
	"wood": {"post": 0.406, "post_w": 0.045, "post_d": 0.09, "rafter": 0.61, "raf_w": 0.045, "raf_d": 0.14,
		"joist": 0.406, "girt": 0.0, "purlin": 0.0, "plates": true, "col": LUMBER, "sec": LUMBER},
	"steel": {"post": 7.62, "post_w": 0.25, "post_d": 0.25, "rafter": 1.52, "raf_w": 0.08, "raf_d": 0.4,
		"joist": 1.52, "girt": 1.52, "girt_h": 0.2, "girt_d": 0.06, "purlin": 0.0, "plates": false,
		"col": PRIMER, "sec": GALV},
	"pole": {"post": 2.44, "post_w": 0.14, "post_d": 0.14, "rafter": 2.44, "raf_w": 0.09, "raf_d": 0.25,
		"joist": 2.44, "girt": 0.61, "girt_h": 0.09, "girt_d": 0.04, "purlin": 0.61, "plates": false,
		"col": LUMBER, "sec": LUMBER},
	"tilt_up": {"post": 7.62, "post_w": 0.0, "post_d": 0.18, "rafter": 1.52, "raf_w": 0.08, "raf_d": 0.4,
		"joist": 1.52, "girt": 0.0, "purlin": 0.0, "plates": false, "col": PANEL, "sec": GALV},
}

static var _mat: StandardMaterial3D

var _spec: Dictionary
var _kind: String
## Members: [p0, p1, u, su, v, sv, colour, sort key]
var _members := []
var _center := Vector3.ZERO


## The frame of `mesh` (local space), split into CHUNKS meshes.
## Height of the top of the foundation: the highest level low down with a
## good spread of upward faces (slab, foundation walls), or `fallback`.
static func slab_top(mesh: Mesh, fallback: float) -> float:
	var at := {}
	for si in mesh.get_surface_count():
		var v: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for i in range(0, v.size() - 2, 3):
			var n := (v[i + 2] - v[i]).cross(v[i + 1] - v[i])
			if n.normalized().y > 0.95 and v[i].y < 0.9 and v[i].y > 0.05:
				var y := snappedf(v[i].y, 0.01)
				at[y] = at.get(y, 0.0) + n.length() * 0.5
	var best := -1.0
	for y in at:
		if at[y] >= 4.0 and y > best:
			best = y
	return best + 0.02 if best > 0.0 else fallback


static func build(mesh: Mesh, kind: String) -> Array:
	var b := FrameBuilder.new()
	b._kind = kind if SPECS.has(kind) else "wood"
	b._spec = SPECS[b._kind]
	b._frame(mesh)
	return b._commit()


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.85
	return _mat


# ---------------------------------------------------------------- faces

func _frame(mesh: Mesh) -> void:
	var groups := []
	var aabb := mesh.get_aabb()
	_center = aabb.get_center()
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		var count: int = idx.size() if idx != null and idx.size() > 0 else v.size()
		for i in range(0, count - 2, 3):
			var p0: Vector3
			var p1: Vector3
			var p2: Vector3
			if idx != null and idx.size() > 0:
				p0 = v[idx[i]]
				p1 = v[idx[i + 1]]
				p2 = v[idx[i + 2]]
			else:
				p0 = v[i]
				p1 = v[i + 1]
				p2 = v[i + 2]
			_add_tri(groups, p0, p1, p2)
	for g in groups:
		if g.area >= 2.0:
			_frame_group(g)


func _add_tri(groups: Array, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	# Godot's front faces wind clockwise: this normal points out.
	var n := (p2 - p0).cross(p1 - p0)
	var area := n.length() * 0.5
	if area < 0.002:
		return
	n = n.normalized()
	var top := maxf(p0.y, maxf(p1.y, p2.y))
	if top < 0.5:
		return  # slabs, steps and ground work
	var cat := ""
	if absf(n.y) < 0.25:
		cat = "wall"
	elif n.y > 0.97:
		if (p0.y + p1.y + p2.y) / 3.0 < 1.0:
			return
		cat = "flat"
	elif n.y > 0.25:
		cat = "roof"
	else:
		return  # soffits and undersides
	var d := n.dot(p0)
	var g: Dictionary = {}
	for e in groups:
		if e.cat == cat and e.n.dot(n) > 0.995 and absf(e.d - d) < 0.3:
			g = e
			break
	if g.is_empty():
		var a: Vector3
		if cat == "flat":
			a = Vector3.RIGHT
		else:
			a = Vector3(-n.z, 0.0, n.x).normalized()
		var b := n.cross(a).normalized()
		if cat == "wall":
			b = Vector3.UP
		g = {"cat": cat, "n": n, "a": a, "b": b, "d": d, "area": 0.0, "tris": [], "main_area": 0.0}
		groups.append(g)
	g.area += area
	g.tris.append([d, area, Vector2(p0.dot(g.a), p0.dot(g.b)), Vector2(p1.dot(g.a), p1.dot(g.b)),
		Vector2(p2.dot(g.a), p2.dot(g.b))])
	# The plane with the most face area is the real wall; the rest stand off it.
	if area > g.main_area:
		g.main_area = area
		g.d = d


func _frame_group(g: Dictionary) -> void:
	var main := []
	var others := []
	for t in g.tris:
		if absf(t[0] - g.d) < 0.03:
			main.append(t)
		else:
			others.append(t)
	if main.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for t in main:
		for k in [2, 3, 4]:
			lo = lo.min(t[k])
			hi = hi.max(t[k])
	if g.cat == "wall" and hi.x - lo.x < 1.0:
		return  # a chimney or a post, not a framed wall
	var openings := _openings(others, lo, hi) if g.cat == "wall" and _kind != "tilt_up" else []
	var spacing: float
	var su: float
	var sv: float
	match g.cat:
		"wall":
			spacing = _spec.post
			su = _spec.post_w
			sv = _spec.post_d
		"roof":
			spacing = _spec.rafter
			su = _spec.raf_w
			sv = _spec.raf_d
		_:
			spacing = _spec.joist
			su = _spec.raf_w
			sv = _spec.raf_d
	if g.cat == "wall" and _kind == "tilt_up":
		_panels(g, main, lo, hi)
		return
	var rank: float = {"wall": 0.0, "flat": 50.0, "roof": 100.0}[g.cat]
	# Main members across the face: studs, columns, posts, rafters, joists.
	var lines := _lines(main, 0, spacing, lo.x, hi.x, su)
	for c in lines:
		var parts := [[lines[c][0], lines[c][1]]]
		for o in openings:
			if c > o.position.x - 0.02 and c < o.end.x + 0.02:
				parts = _cut(parts, o.position.y - 0.04, o.end.y + 0.26)
		for p in parts:
			if p[1] - p[0] > 0.05:
				_member_on(g, c, p[0], p[1], 0, su, sv, _spec.col, rank)
	# Rough openings: a header over each, a sill under windows, king studs.
	for o in openings:
		if _spec.plates:
			_member_on(g, o.end.y + 0.13, o.position.x - 0.05, o.end.x + 0.05, 1, 0.24, sv, _spec.col, rank + 5.0)
			if o.position.y > lo.y + 0.3:
				_member_on(g, o.position.y - 0.02, o.position.x, o.end.x, 1, su, sv, _spec.col, rank + 1.0)
		for x in [o.position.x - 0.03, o.end.x + 0.03]:
			var r := _range_at(main, 0, x)
			if r.size() == 2:
				_member_on(g, x, r[0], r[1], 0, su, sv, _spec.col, rank)
	if g.cat == "wall":
		# Studs at each end of the wall, too.
		for x in [lo.x + su * 0.5, hi.x - su * 0.5]:
			var r := _range_at(main, 0, x)
			if r.size() == 2:
				_member_on(g, x, r[0], r[1], 0, maxf(su, 0.09), sv, _spec.col, rank)
		var eave := hi.y
		for c in lines:
			eave = minf(eave, lines[c][1])
		if _spec.plates:
			_member_on(g, lo.y + 0.02, lo.x, hi.x, 1, 0.045, sv, _spec.col, rank)
			_member_on(g, eave - 0.045, lo.x, hi.x, 1, 0.09, sv, _spec.col, rank + 4.0)
			# Platform framing: a floor band every storey.
			var level := lo.y + 2.75
			while level < eave - 0.8:
				_member_on(g, level, lo.x, hi.x, 1, 0.24, sv, _spec.col, rank + 2.0)
				level += 2.75
		if _spec.girt > 0.0:
			var rows := _lines(main, 1, _spec.girt, lo.y + 0.4, hi.y, _spec.girt_h)
			for c in rows:
				_member_on(g, c, rows[c][0], rows[c][1], 1, _spec.girt_h, _spec.girt_d + sv, _spec.sec, rank + 3.0)
	elif g.cat == "roof" and _spec.purlin > 0.0:
		var rows := _lines(main, 1, _spec.purlin, lo.y, hi.y, 0.09)
		for c in rows:
			_member_on(g, c, rows[c][0], rows[c][1], 1, 0.09, sv + 0.04, _spec.sec, rank + 3.0)


## Concrete wall panels, one per bay, each propped by two pipe braces.
func _panels(g: Dictionary, main: Array, lo: Vector2, hi: Vector2) -> void:
	var w: float = _spec.post
	var count := maxi(1, roundi((hi.x - lo.x) / w))
	w = (hi.x - lo.x) / count
	for i in count:
		var x0 := lo.x + w * i
		var x1 := x0 + w
		var y0 := INF
		var y1 := -INF
		for x in [x0 + 0.1, (x0 + x1) * 0.5, x1 - 0.1]:
			var r := _range_at(main, 0, x)
			if r.size() == 2:
				y0 = minf(y0, r[0])
				y1 = maxf(y1, r[1])
		if y1 - y0 < 0.5:
			continue
		var mid := (x0 + x1) * 0.5
		var base := _point(g, mid, y0, _spec.post_d * 0.5)
		var key := _angle_key(base)
		_member_on(g, mid, y0, y1, 0, w - 0.03, _spec.post_d, PANEL, key)
		var h := y1 - y0
		for s in [-0.25, 0.25]:
			var top := _point(g, mid + w * s, y0 + h * 0.66, _spec.post_d + 0.05)
			var foot: Vector3 = top - g.n * (h * 0.6)
			foot.y = y0 + 0.05
			_members.append([top, foot, g.n.cross(Vector3.UP).normalized(), 0.09, Vector3.UP, 0.09, BRACE, key])


## Windows and doors on a wall: the outlines of smaller faces that stand
## just off it, merged where they touch. Anything nearly as wide as the wall
## (brick wainscot, a band of trim) isn't an opening.
func _openings(tris: Array, lo: Vector2, hi: Vector2) -> Array:
	var rects := []
	for t in tris:
		var r := Rect2(t[2], Vector2.ZERO).expand(t[3]).expand(t[4])
		if r.size.x < 0.02 or r.size.y < 0.02:
			continue
		var merged := false
		for i in rects.size():
			if rects[i].grow(0.08).intersects(r):
				rects[i] = rects[i].merge(r)
				merged = true
				break
		if not merged:
			rects.append(r)
	# Merging can join rectangles that were apart before: settle it.
	var changed := true
	while changed:
		changed = false
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				if rects[i].grow(0.08).intersects(rects[j]):
					rects[i] = rects[i].merge(rects[j])
					rects.remove_at(j)
					changed = true
					break
			if changed:
				break
	var out := []
	var width := hi.x - lo.x
	var height := hi.y - lo.y
	for r in rects:
		if r.size.x * r.size.y > 0.3 and r.size.x < width * 0.6 and r.size.y < height * 0.9 \
				and r.size.x > 0.4 and r.size.y > 0.5:
			out.append(r)
	return out


## Grid lines across a face: for each line at a multiple of `spacing` along
## axis `ax` (0: a, 1: b) inside [from, to], where it enters and leaves the
## face. -> {coordinate: [lo, hi]}
func _lines(tris: Array, ax: int, spacing: float, from: float, to: float, thick: float) -> Dictionary:
	var out := {}
	var k0 := ceili((from + thick) / spacing)
	var k1 := floori((to - thick) / spacing)
	for k in range(k0, k1 + 1):
		var c := k * spacing
		var r := _range_at(tris, ax, c)
		if r.size() == 2 and r[1] - r[0] > 0.05:
			out[c] = r
	return out


## Where the line at `c` on axis `ax` crosses these triangles: [lo, hi] on
## the other axis, or [] if it misses them all.
func _range_at(tris: Array, ax: int, c: float) -> Array:
	var lo := INF
	var hi := -INF
	var o := 1 - ax
	for t in tris:
		for e in [[t[2], t[3]], [t[3], t[4]], [t[4], t[2]]]:
			var p: Vector2 = e[0]
			var q: Vector2 = e[1]
			var pa: float = p[ax] - c
			var qa: float = q[ax] - c
			if pa * qa > 0.0 or absf(p[ax] - q[ax]) < 1e-6:
				if absf(pa) < 1e-6:
					lo = minf(lo, p[o])
					hi = maxf(hi, p[o])
				continue
			var f := pa / (pa - qa)
			var y: float = lerpf(p[o], q[o], f)
			lo = minf(lo, y)
			hi = maxf(hi, y)
	return [] if lo > hi else [lo, hi]


## Removes [c0, c1] from a list of [lo, hi] ranges.
static func _cut(parts: Array, c0: float, c1: float) -> Array:
	var out := []
	for p in parts:
		if c1 <= p[0] or c0 >= p[1]:
			out.append(p)
			continue
		if c0 > p[0]:
			out.append([p[0], c0])
		if c1 < p[1]:
			out.append([c1, p[1]])
	return out


## A member on a face: along axis b at a = c from b = from to b = to
## (along = 0), or along a at b = c (along = 1). It sits just inside the
## face, `sv` deep, `su` wide across its run.
func _member_on(g: Dictionary, c: float, from: float, to: float, along: int, su: float, sv: float,
		col: Color, rank: float) -> void:
	var p0: Vector3
	var p1: Vector3
	var u: Vector3
	if along == 0:
		p0 = _point(g, c, from, sv * 0.5)
		p1 = _point(g, c, to, sv * 0.5)
		u = g.a
	else:
		p0 = _point(g, from, c, sv * 0.5)
		p1 = _point(g, to, c, sv * 0.5)
		u = g.b
	var key := rank + floorf(minf(p0.y, p1.y) / 1.5) * 2.0 + _angle_key((p0 + p1) * 0.5) * 0.5
	_members.append([p0, p1, u, su, g.n, sv, col, key])


func _point(g: Dictionary, x: float, y: float, inset: float) -> Vector3:
	return g.a * x + g.b * y + g.n * (g.d - inset)


## 0-1 around the building, so pieces go up in turn rather than all at once.
func _angle_key(p: Vector3) -> float:
	return (atan2(p.z - _center.z, p.x - _center.x) + PI) / TAU


# ---------------------------------------------------------------- meshes

func _commit() -> Array:
	_members.sort_custom(func(a, b): return a[7] < b[7])
	var out := []
	var per := ceili(_members.size() / float(CHUNKS))
	for c in CHUNKS:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var any := false
		for i in range(c * per, mini((c + 1) * per, _members.size())):
			var m: Array = _members[i]
			_box(st, m[0], m[1], m[2], m[3], m[4], m[5], m[6])
			any = true
		if any:
			var mesh := st.commit()
			mesh.surface_set_material(0, material())
			out.append(mesh)
	return out


## A box from p0 to p1, `su` across along u and `sv` across along v.
static func _box(st: SurfaceTool, p0: Vector3, p1: Vector3, u: Vector3, su: float, v: Vector3, sv: float,
		col: Color) -> void:
	var l := p1 - p0
	if l.length() < 0.01:
		return
	var lw := l.normalized()
	# Square the cross-section axes to the run.
	u = (u - lw * u.dot(lw))
	if u.length() < 0.01:
		u = v.cross(lw)
	u = u.normalized()
	v = lw.cross(u).normalized()
	var hu := u * su * 0.5
	var hv := v * sv * 0.5
	var c := [p0 - hu - hv, p0 + hu - hv, p0 + hu + hv, p0 - hu + hv]
	var e := [p1 - hu - hv, p1 + hu - hv, p1 + hu + hv, p1 - hu + hv]
	st.set_color(col)
	for i in 4:
		var j := (i + 1) % 4
		_quad(st, c[i], c[j], e[j], e[i])
	_quad(st, c[3], c[2], c[1], c[0])
	_quad(st, e[0], e[1], e[2], e[3])


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	# Wind every face to look out of the box (Godot culls clockwise).
	st.set_normal(-n)
	for p in [a, c, b, a, d, c]:
		st.add_vertex(p)
