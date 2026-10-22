class_name RoadNetwork
extends RefCounted
## The road graph as plain data. 1 unit = 1 metre.
##
## Nodes are points, segments are quadratic Bezier curves between two nodes.
## Every edit goes through build_road() or remove_segment(), so a server can
## later receive the same commands from players and replay them.

signal changed

const SAMPLES := 24
const MIN_LENGTH := 4.0
## Crossings closer than this to an existing junction reuse that junction.
const MERGE_DIST := 3.0

var nodes := {}     # int -> Vector3
var segments := {}  # int -> {"a": int, "b": int, "ctrl": Vector3}
var _next_id := 1


# --- Curve math -------------------------------------------------------------

static func bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return p0 * (u * u) + p1 * (2.0 * u * t) + p2 * (t * t)


static func bezier_tangent(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	return ((p1 - p0) * (1.0 - t) + (p2 - p1) * t) * 2.0


static func sample_curve(p0: Vector3, p1: Vector3, p2: Vector3, n: int = SAMPLES) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in n + 1:
		pts.append(bezier(p0, p1, p2, float(i) / n))
	return pts


static func polyline_length(pts: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	return total


## Control point of the part of a curve between t0 and t1 (exact for quadratics).
static func sub_control(p0: Vector3, p1: Vector3, p2: Vector3, t0: float, t1: float) -> Vector3:
	return bezier(p0, p1, p2, t0) + bezier_tangent(p0, p1, p2, t0) * ((t1 - t0) * 0.5)


# --- Queries ----------------------------------------------------------------

func curve_of(seg_id: int) -> Array:
	var s: Dictionary = segments[seg_id]
	return [nodes[s.a], s.ctrl, nodes[s.b]]


func sample_segment(seg_id: int, n: int = SAMPLES) -> PackedVector3Array:
	var c := curve_of(seg_id)
	return sample_curve(c[0], c[1], c[2], n)


func segments_at(node_id: int) -> Array:
	var out := []
	for id in segments:
		if segments[id].a == node_id or segments[id].b == node_id:
			out.append(id)
	return out


func find_node_near(pos: Vector3, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist
	for id in nodes:
		var d: float = _flat(nodes[id]).distance_to(_flat(pos))
		if d <= best_d:
			best_d = d
			best = id
	return best


## Closest point on any segment. Returns {} or {"seg", "t", "point", "dist"}.
func find_segment_near(pos: Vector3, max_dist: float) -> Dictionary:
	var best := {}
	var best_d := max_dist
	var p := _flat(pos)
	for id in segments:
		var c := curve_of(id)
		var n := 48
		var prev := bezier(c[0], c[1], c[2], 0.0)
		for i in range(1, n + 1):
			var cur := bezier(c[0], c[1], c[2], float(i) / n)
			var q := Geometry3D.get_closest_point_to_segment(p, _flat(prev), _flat(cur))
			var d := q.distance_to(p)
			if d <= best_d:
				var seg_len := _flat(prev).distance_to(_flat(cur))
				var f := 0.0 if seg_len < 0.001 else _flat(prev).distance_to(q) / seg_len
				var t := (float(i - 1) + f) / n
				best_d = d
				best = {"seg": id, "t": t, "point": bezier(c[0], c[1], c[2], t), "dist": d}
			prev = cur
	return best


## Where the cursor should snap: an existing junction first, then a road.
func snap(pos: Vector3, node_dist: float, seg_dist: float) -> Dictionary:
	var n := find_node_near(pos, node_dist)
	if n != -1:
		return {"pos": nodes[n], "kind": "node"}
	var s := find_segment_near(pos, seg_dist)
	if not s.is_empty():
		return {"pos": s.point, "kind": "segment"}
	return {"pos": Vector3(pos.x, 0.0, pos.z), "kind": "free"}


func total_length() -> float:
	var total := 0.0
	for id in segments:
		total += polyline_length(sample_segment(id))
	return total


# --- Commands ---------------------------------------------------------------

## Builds a road from start to end bent toward ctrl. Joins existing junctions
## and roads it starts on, ends on, or crosses.
func build_road(start: Vector3, ctrl: Vector3, end: Vector3) -> bool:
	if _flat(start).distance_to(_flat(end)) < MIN_LENGTH:
		return false
	var a := _resolve_endpoint(start)
	var b := _resolve_endpoint(end)
	if a == b:
		return false
	var p0: Vector3 = nodes[a]
	var p2: Vector3 = nodes[b]

	# Split every existing road this one crosses, remembering where.
	var cuts := []  # [t_on_new_road, node_id]
	for _guard in 64:
		var hit := _first_crossing(p0, ctrl, p2, cuts, [a, b])
		if hit.is_empty():
			break
		var node_id := split_segment(hit.seg, hit.t_seg)
		cuts.append([hit.t_new, node_id])
	cuts.sort_custom(func(x, y): return x[0] < y[0])

	var stops := [[0.0, a]] + cuts + [[1.0, b]]
	for i in range(stops.size() - 1):
		var t0: float = stops[i][0]
		var t1: float = stops[i + 1][0]
		var na: int = stops[i][1]
		var nb: int = stops[i + 1][1]
		if na == nb or _has_segment(na, nb):
			continue
		_add_segment(na, nb, sub_control(p0, ctrl, p2, t0, t1))
	changed.emit()
	return true


func remove_segment(seg_id: int) -> void:
	if not segments.has(seg_id):
		return
	var s: Dictionary = segments[seg_id]
	segments.erase(seg_id)
	for n in [s.a, s.b]:
		if segments_at(n).is_empty():
			nodes.erase(n)
	changed.emit()


func clear() -> void:
	nodes.clear()
	segments.clear()
	changed.emit()


## Splits a segment at t and returns the new junction's id.
func split_segment(seg_id: int, t: float) -> int:
	var s: Dictionary = segments[seg_id]
	var c := curve_of(seg_id)
	var mid := bezier(c[0], c[1], c[2], t)
	var existing := find_node_near(mid, MERGE_DIST)
	if existing == s.a or existing == s.b:
		return existing
	segments.erase(seg_id)
	var m := _add_node(mid)
	_add_segment(s.a, m, c[0].lerp(c[1], t))
	_add_segment(m, s.b, c[1].lerp(c[2], t))
	return m


# --- Saving (also the future network format) --------------------------------

func to_dict() -> Dictionary:
	var n := {}
	for id in nodes:
		var p: Vector3 = nodes[id]
		n[str(id)] = [p.x, p.z]
	var s := {}
	for id in segments:
		var seg: Dictionary = segments[id]
		s[str(id)] = [seg.a, seg.b, seg.ctrl.x, seg.ctrl.z]
	return {"version": 1, "next_id": _next_id, "nodes": n, "segments": s}


func from_dict(d: Dictionary) -> void:
	nodes.clear()
	segments.clear()
	for k in d.get("nodes", {}):
		var p: Array = d.nodes[k]
		nodes[int(k)] = Vector3(p[0], 0.0, p[1])
	for k in d.get("segments", {}):
		var s: Array = d.segments[k]
		segments[int(k)] = {"a": int(s[0]), "b": int(s[1]), "ctrl": Vector3(s[2], 0.0, s[3])}
	_next_id = int(d.get("next_id", 1))
	changed.emit()


# --- Internals --------------------------------------------------------------

func _resolve_endpoint(pos: Vector3) -> int:
	var n := find_node_near(pos, 0.5)
	if n != -1:
		return n
	var s := find_segment_near(pos, 0.5)
	if not s.is_empty():
		return split_segment(s.seg, s.t)
	return _add_node(Vector3(pos.x, 0.0, pos.z))


func _add_node(pos: Vector3) -> int:
	var id := _next_id
	_next_id += 1
	nodes[id] = pos
	return id


func _add_segment(a: int, b: int, ctrl: Vector3) -> int:
	var id := _next_id
	_next_id += 1
	segments[id] = {"a": a, "b": b, "ctrl": ctrl}
	return id


func _has_segment(a: int, b: int) -> bool:
	for id in segments:
		var s: Dictionary = segments[id]
		if (s.a == a and s.b == b) or (s.a == b and s.b == a):
			return true
	return false


## The first place the new curve crosses an existing road away from any known
## junction. Returns {} or {"seg", "t_seg", "t_new"}.
func _first_crossing(p0: Vector3, p1: Vector3, p2: Vector3, cuts: Array, ends: Array) -> Dictionary:
	var n := 32
	var new_pts := sample_curve(p0, p1, p2, n)
	var avoid := []
	for e in ends:
		avoid.append(nodes[e])
	for c in cuts:
		avoid.append(nodes[c[1]])
	for id in segments:
		var old_pts := sample_segment(id, n)
		for i in n:
			for j in n:
				var hit = Geometry2D.segment_intersects_segment(
					_v2(new_pts[i]), _v2(new_pts[i + 1]), _v2(old_pts[j]), _v2(old_pts[j + 1]))
				if hit == null:
					continue
				var hp := Vector3(hit.x, 0.0, hit.y)
				var near_known := false
				for q in avoid:
					if _flat(q).distance_to(hp) < MERGE_DIST:
						near_known = true
						break
				if near_known:
					continue
				var fi := _v2(new_pts[i]).distance_to(hit) / maxf(_v2(new_pts[i]).distance_to(_v2(new_pts[i + 1])), 0.001)
				var fj := _v2(old_pts[j]).distance_to(hit) / maxf(_v2(old_pts[j]).distance_to(_v2(old_pts[j + 1])), 0.001)
				return {"seg": id, "t_seg": (j + fj) / n, "t_new": (i + fi) / n}
	return {}


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _v2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
