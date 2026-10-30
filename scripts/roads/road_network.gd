class_name RoadNetwork
extends RefCounted
## The road graph as plain data. 1 unit = 1 metre.
##
## Nodes are points, segments are quadratic Bezier curves between two nodes.
## Every edit goes through build_road() or remove_segment(), so a server can
## later receive the same commands from players and replay them.

signal changed
## A road piece was cut in two (a road joined it mid-block): what was on
## `seg` (a car-free closure, say) can carry on to `first` and `second`.
signal split(seg: int, first: int, second: int)
## Goes up on every change, so caches can tell when to work things out again.
var revision := 0
## Segments meeting at each node, kept until the roads change (segments_at).
var _at := {}
var _at_key := []
## [revision, segment count, RoadIndex] for the roads as they were last
## indexed (RoadIndex.of). The index holds no link back, so no cycle.
var _road_index := []

const SAMPLES := 24
const MIN_LENGTH := 4.0
## Crossings closer than this to an existing junction reuse that junction.
const MERGE_DIST := 3.0
## Roads closer in height than this meet; farther apart they pass over.
const SAME_LEVEL := 1.0
## Height between road surfaces where one crosses over another: 16.5 ft
## (5.0 m) AASHTO vertical clearance plus a 1.5 m bridge deck.
const CLEARANCE := 6.5

var nodes := {}     # int -> Vector3
var segments := {}  # int -> {"a", "b", "ctrl": Vector3, "type": RoadStyle.Type, "oneway": bool}
var _next_id := 1
## While batching, edits don't emit `changed` until end_batch().
var _batch := 0
var _batch_dirty := false


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


## Tightest radius along a curve (straight lines give INF).
static func min_radius(p0: Vector3, p1: Vector3, p2: Vector3) -> float:
	var second := (p0 - p1 * 2.0 + p2) * 2.0
	second.y = 0.0
	var best := INF
	for i in 33:
		var d := bezier_tangent(p0, p1, p2, i / 32.0)
		d.y = 0.0
		var cross := absf(d.x * second.z - d.z * second.x)
		if cross > 0.000001:
			best = minf(best, pow(d.length(), 3.0) / cross)
	return best


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
	# Mid-batch the roads are half edited, so look the slow way.
	if _batch > 0 or _batch_dirty:
		return _scan_at(node_id)
	var key := [revision, segments.size(), nodes.size()]
	if key != _at_key:
		_at_key = key
		_at.clear()
		for id in segments:
			for n in [segments[id].a, segments[id].b]:
				if not _at.has(n):
					_at[n] = []
				if not _at[n].has(id):
					_at[n].append(id)
	return _at.get(node_id, []).duplicate()


func _scan_at(node_id: int) -> Array:
	var out := []
	for id in segments:
		if segments[id].a == node_id or segments[id].b == node_id:
			out.append(id)
	return out


## Closest junction within max_dist across the ground and max_dy up or down.
func find_node_near(pos: Vector3, max_dist: float, max_dy := INF) -> int:
	var best := -1
	var best_d := max_dist
	for id in nodes:
		if absf(nodes[id].y - pos.y) > max_dy:
			continue
		var d: float = _flat(nodes[id]).distance_to(_flat(pos))
		if d <= best_d:
			best_d = d
			best = id
	return best


## Closest point on any segment. Returns {} or {"seg", "t", "point", "dist"}.
func find_segment_near(pos: Vector3, max_dist: float, max_dy := INF) -> Dictionary:
	var best := {}
	var best_d := max_dist
	var p := _flat(pos)
	for id in segments:
		var c := curve_of(id)
		# A curve stays inside its control points: skip the far ones.
		var hull := Rect2(Vector2(c[0].x, c[0].z), Vector2.ZERO).expand(Vector2(c[1].x, c[1].z)) \
			.expand(Vector2(c[2].x, c[2].z)).grow(best_d + 0.01)
		if not hull.has_point(Vector2(p.x, p.z)):
			continue
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
				if absf(bezier(c[0], c[1], c[2], t).y - pos.y) > max_dy:
					prev = cur
					continue
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


## Widest road type meeting at a junction.
func widest_at(node_id: int) -> int:
	var best := 0
	for id in segments_at(node_id):
		if RoadStyle.half_width(segments[id].type) > RoadStyle.half_width(best):
			best = segments[id].type
	return best


func total_length() -> float:
	var total := 0.0
	for id in segments:
		total += polyline_length(sample_segment(id))
	return total


# --- Commands ---------------------------------------------------------------

## Why a road of this shape (curve [start, ctrl, end], town coordinates) and
## type can't be laid on the ground, or "": set by the town (CitySim
## road_ground: a county railroad's track, CountyRail.road_check). Every
## build_road asks it, so no builder lays a road the rules refuse.
var ground_check := Callable()
## Why the last build_road was refused by ground_check, or "".
var refused := ""

## Builds a road from start to end bent toward ctrl. Joins existing junctions
## and roads it starts on, ends on, or crosses.
func build_road(start: Vector3, ctrl: Vector3, end: Vector3, type := 0, oneway := false) -> bool:
	refused = ""
	# Whatever builds it (the road tool, a grid, a subdivision, the town's
	# engineer, a hub's road, a roundabout, the highway out of town), a road
	# goes only where the ground lets it (ground_check).
	if ground_check.is_valid():
		refused = ground_check.call([start, ctrl, end], type)
		if refused != "":
			return false
	# The roads it cuts on the way (where it starts, ends or crosses) and the
	# road itself are one change, so `changed` fires once.
	begin_batch()
	var built := _build_road(start, ctrl, end, type, oneway)
	end_batch()
	return built


func _build_road(start: Vector3, ctrl: Vector3, end: Vector3, type: int, oneway: bool) -> bool:
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
		_add_segment(na, nb, sub_control(p0, ctrl, p2, t0, t1), type, oneway)
	_changed()
	return true


func remove_segment(seg_id: int) -> void:
	if not segments.has(seg_id):
		return
	var s: Dictionary = segments[seg_id]
	segments.erase(seg_id)
	for n in [s.a, s.b]:
		if segments_at(n).is_empty():
			nodes.erase(n)
	_changed()


## True when traffic may only drive a segment from a to b.
func is_oneway(seg_id: int) -> bool:
	var s: Dictionary = segments[seg_id]
	return s.oneway or RoadStyle.TYPES[s.type].oneway


## Changes a road to another type (an upgrade or downgrade).
func set_type(seg_id: int, type: int) -> bool:
	if not segments.has(seg_id) or segments[seg_id].type == type:
		return false
	segments[seg_id].type = type
	_changed()
	return true


func clear() -> void:
	nodes.clear()
	segments.clear()
	_changed()


## Splits a segment at t and returns the new junction's id. The cut is a
## change: the segment's id is gone, so whatever pointed at it (lots,
## walkers, services) must catch up (reviewer 2026-10-27: a cut alone never
## moved `revision`, so nothing refreshed).
func split_segment(seg_id: int, t: float) -> int:
	var s: Dictionary = segments[seg_id]
	var c := curve_of(seg_id)
	var mid := bezier(c[0], c[1], c[2], t)
	var existing := find_node_near(mid, MERGE_DIST, SAME_LEVEL)
	if existing == s.a or existing == s.b:
		return existing
	segments.erase(seg_id)
	var m := _add_node(mid)
	var p := _add_segment(s.a, m, c[0].lerp(c[1], t), s.type, s.oneway)
	var q := _add_segment(m, s.b, c[1].lerp(c[2], t), s.type, s.oneway)
	if s.has("built_by"):
		segments[p].built_by = s.built_by
		segments[q].built_by = s.built_by
	split.emit(seg_id, p, q)  # closures move onto the halves before anything hears of the change
	_changed()
	return m


# --- Saving (also the future network format) --------------------------------

## A copy of the roads to put back later (UndoLog), cheaper than to_dict.
func snapshot() -> Dictionary:
	return {"nodes": nodes.duplicate(), "segments": segments.duplicate(true), "next_id": _next_id}


func restore(snap: Dictionary) -> void:
	nodes = snap.nodes.duplicate()
	segments = snap.segments.duplicate(true)
	_next_id = snap.next_id
	_changed()


func to_dict() -> Dictionary:
	var n := {}
	for id in nodes:
		var p: Vector3 = nodes[id]
		n[str(id)] = [p.x, p.z, p.y]
	var s := {}
	for id in segments:
		var seg: Dictionary = segments[id]
		s[str(id)] = [seg.a, seg.b, seg.ctrl.x, seg.ctrl.z, seg.type, seg.ctrl.y, 1 if seg.oneway else 0]
		if seg.has("built_by"):
			s[str(id)].append(seg.built_by)
	return {"version": 1, "next_id": _next_id, "nodes": n, "segments": s}


func from_dict(d: Dictionary) -> void:
	nodes.clear()
	segments.clear()
	for k in d.get("nodes", {}):
		var p: Array = d.nodes[k]
		nodes[int(k)] = Vector3(p[0], p[2] if p.size() > 2 else 0.0, p[1])
	for k in d.get("segments", {}):
		var s: Array = d.segments[k]
		segments[int(k)] = {"a": int(s[0]), "b": int(s[1]),
			"ctrl": Vector3(s[2], s[5] if s.size() > 5 else 0.0, s[3]),
			"type": int(s[4]) if s.size() > 4 else 0,
			"oneway": s.size() > 6 and int(s[6]) == 1}
		if s.size() > 7:
			segments[int(k)].built_by = str(s[7])
	_next_id = int(d.get("next_id", 1))
	_changed()


## Groups many edits (a whole grid of roads) into one `changed` signal.
func begin_batch() -> void:
	_batch += 1


func end_batch() -> void:
	_batch -= 1
	if _batch == 0 and _batch_dirty:
		_batch_dirty = false
		revision += 1
		changed.emit()


# --- Internals --------------------------------------------------------------

func _changed() -> void:
	if _batch > 0:
		_batch_dirty = true
	else:
		revision += 1
		changed.emit()


func _resolve_endpoint(pos: Vector3) -> int:
	var n := find_node_near(pos, 0.5, SAME_LEVEL)
	if n != -1:
		return n
	var s := find_segment_near(pos, 0.5, SAME_LEVEL)
	if not s.is_empty():
		return split_segment(s.seg, s.t)
	return _add_node(pos)


func _add_node(pos: Vector3) -> int:
	var id := _next_id
	_next_id += 1
	nodes[id] = pos
	return id


func _add_segment(a: int, b: int, ctrl: Vector3, type := 0, oneway := false) -> int:
	var id := _next_id
	_next_id += 1
	segments[id] = {"a": a, "b": b, "ctrl": ctrl, "type": type, "oneway": oneway}
	return id


func _has_segment(a: int, b: int) -> bool:
	for id in segments:
		var s: Dictionary = segments[id]
		if (s.a == a and s.b == b) or (s.a == b and s.b == a):
			return true
	return false


## Why a new road can't cross the roads already there, or "" if it can:
## it must meet them level or clear them by CLEARANCE.
func crossing_problem(p0: Vector3, p1: Vector3, p2: Vector3) -> String:
	var n := 32
	var new_pts := sample_curve(p0, p1, p2, n)
	var box := _bounds(new_pts)
	for id in segments:
		# A curve lies inside its control points: most roads are far off.
		if not box.intersects(_bounds(PackedVector3Array(curve_of(id))), true):
			continue
		var old_pts := sample_segment(id, n)
		if not box.intersects(_bounds(old_pts), true):
			continue
		for i in n:
			for j in n:
				var hit = Geometry2D.segment_intersects_segment(
					_v2(new_pts[i]), _v2(new_pts[i + 1]), _v2(old_pts[j]), _v2(old_pts[j + 1]))
				if hit == null:
					continue
				var fi := _v2(new_pts[i]).distance_to(hit) / maxf(_v2(new_pts[i]).distance_to(_v2(new_pts[i + 1])), 0.001)
				var fj := _v2(old_pts[j]).distance_to(hit) / maxf(_v2(old_pts[j]).distance_to(_v2(old_pts[j + 1])), 0.001)
				var dy := absf(lerpf(new_pts[i].y, new_pts[i + 1].y, fi) - lerpf(old_pts[j].y, old_pts[j + 1].y, fj))
				if dy >= SAME_LEVEL and dy < CLEARANCE:
					return "Not enough room to pass: %.1f m. Crossings need 16.5 ft (5 m) clearance under the deck (AASHTO)." % dy
	return ""


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
	var box := _bounds(new_pts)
	for id in segments:
		# A curve lies inside its control points: most roads are far off.
		if not box.intersects(_bounds(PackedVector3Array(curve_of(id))), true):
			continue
		var old_pts := sample_segment(id, n)
		if not box.intersects(_bounds(old_pts), true):
			continue
		for i in n:
			for j in n:
				var hit = Geometry2D.segment_intersects_segment(
					_v2(new_pts[i]), _v2(new_pts[i + 1]), _v2(old_pts[j]), _v2(old_pts[j + 1]))
				if hit == null:
					continue
				var hp := Vector3(hit.x, 0.0, hit.y)
				var fi0 := _v2(new_pts[i]).distance_to(hit) / maxf(_v2(new_pts[i]).distance_to(_v2(new_pts[i + 1])), 0.001)
				var fj0 := _v2(old_pts[j]).distance_to(hit) / maxf(_v2(old_pts[j]).distance_to(_v2(old_pts[j + 1])), 0.001)
				var dy := lerpf(new_pts[i].y, new_pts[i + 1].y, fi0) - lerpf(old_pts[j].y, old_pts[j + 1].y, fj0)
				if absf(dy) >= SAME_LEVEL:
					continue  # passes over or under
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


static func _bounds(pts: PackedVector3Array) -> Rect2:
	var r := Rect2(_v2(pts[0]), Vector2.ZERO)
	for p in pts:
		r = r.expand(_v2(p))
	return r.grow(0.5)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _v2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
