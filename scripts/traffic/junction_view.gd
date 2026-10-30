class_name JunctionView
extends Node3D
## Traffic lights on mast arms, stop signs and yield signs at every
## junction, drawn in a few batches. Lights change colour as they cycle.
## Signs follow MUTCD: a 30 in red octagon with a white border and STOP on a
## galvanised post, 7 ft to the bottom of the sign, green street-name blades
## on top. Shaped town junctions are painted by JunctionMarks' rules
## (each leg's crosswalk by the junction's control and look, stop and yield
## lines, fresh or worn); other junctions get a
## stop bar and crosswalk across each controlled approach.

const POLE_H := 5.8
const RED := Color(1.0, 0.12, 0.08)
const YELLOW := Color(1.0, 0.72, 0.05)
const GREEN := Color(0.15, 1.0, 0.45)
const LENS_COLORS := [RED, YELLOW, GREEN]
## How bright an unlit lens is: dark, but still reads as coloured glass.
const LENS_DARK := 0.12
const HEAD_W := 0.36
const HEAD_H := 1.05
const HEAD_D := 0.3
## Where lane arrows' heads sit behind the stop line, metres.
const ARROW_BACK := 4.0
## Junction paint a few years on, and long overdue for redoing.
const WORN := Color(0.70, 0.70, 0.67)
const GHOST := Color(0.53, 0.53, 0.51)

var traffic: TrafficSim
## The road view, for where shaped town junctions make each road stop short.
var roads: RoadView
var _version := -1
var _plans_version := -1
## node -> [what its paint was drawn from, mesh]
var _paint_cache := {}
var _poles: MultiMeshInstance3D
var _arms: MultiMeshInstance3D
var _heads: MultiMeshInstance3D
## Three round lenses per head (red, yellow, green, top to bottom), the
## lit one bright and the others dark, and hoods and a backplate around them.
var _lenses: MultiMeshInstance3D
var _hoods: MultiMeshInstance3D
var _plates: MultiMeshInstance3D
var _stops: MultiMeshInstance3D
var _yields: MultiMeshInstance3D
var _blades: MultiMeshInstance3D
var _no_lefts: MultiMeshInstance3D
var _no_rights: MultiMeshInstance3D
var _paint := MeshInstance3D.new()
## [node, way] for each signal head, in instance order.
var _head_ways := []
## Worn and ghost paint at junctions whose look has it (JunctionMarks.wear).
var _worn := MeshInstance3D.new()
var _ghost := MeshInstance3D.new()


func setup(t: TrafficSim) -> void:
	traffic = t


func _ready() -> void:
	var metal := RoadStyle.material(Color(0.42, 0.43, 0.42))
	metal.cull_mode = BaseMaterial3D.CULL_BACK
	_poles = _batch(_cylinder(0.12, 1.0, 8), metal)
	_arms = _batch(_box(Vector3(1.0, 0.18, 0.18)), metal)
	# A 12-inch, three-section head (MUTCD 4D): dark housing, black
	# backplate, a hood over each lens.
	var housing := RoadStyle.material(Color(0.07, 0.07, 0.065))
	_heads = _batch(_box(Vector3(HEAD_W, HEAD_H, HEAD_D)), housing)
	_hoods = _batch(_box(Vector3(HEAD_W - 0.04, 0.025, 0.2)), housing)
	_plates = _batch(_box(Vector3(HEAD_W + 0.24, HEAD_H + 0.24, 0.02)), housing)
	var lamp := StandardMaterial3D.new()
	lamp.vertex_color_use_as_albedo = true
	lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var lens := _cylinder(0.14, 0.03, 16)
	_lenses = _batch(lens, lamp, true)
	var red_sign := StandardMaterial3D.new()
	red_sign.albedo_color = Color(0.75, 0.05, 0.05)
	red_sign.emission_enabled = true
	red_sign.emission = Color(0.25, 0.0, 0.0)
	var stop_face := StandardMaterial3D.new()
	stop_face.albedo_texture = _stop_texture()
	stop_face.roughness = 0.5
	# Both faces drawn: the grey back plate sits just behind, so drivers see
	# the red face and people behind the sign see the back.
	stop_face.cull_mode = BaseMaterial3D.CULL_DISABLED
	var back := RoadStyle.material(Color(0.6, 0.61, 0.6))
	# Octagon, 30 in across (MUTCD R1-1); triangle, 36 in (R1-2).
	_stops = _batch(_sign_mesh(0.38, stop_face, back), null)
	_yields = _batch(_plate(0.5, 3), red_sign)
	var green := RoadStyle.material(Color(0.05, 0.36, 0.2))
	_blades = _batch(_box(Vector3(0.9, 0.16, 0.03)), green)
	# No Left Turn and No Right Turn, 30 x 30 in (MUTCD R3-2, R3-1).
	for left in [true, false]:
		var face := StandardMaterial3D.new()
		face.albedo_texture = _no_turn_texture(left)
		face.roughness = 0.5
		face.cull_mode = BaseMaterial3D.CULL_DISABLED
		var signs := _batch(_square_sign(0.38, face, back), null)
		if left:
			_no_lefts = signs
		else:
			_no_rights = signs
	_paint.material_override = Surfaces.paint(RoadStyle.MARKING_WHITE)
	_paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_paint)
	_worn.material_override = Surfaces.paint(WORN)
	_ghost.material_override = Surfaces.paint(GHOST)
	for mi in [_worn, _ghost]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _process(_delta: float) -> void:
	if traffic == null:
		return
	var pv := roads.plans_version if roads != null else 0
	if traffic.version != _version or pv != _plans_version:
		_version = traffic.version
		_plans_version = pv
		_rebuild()
	for i in _head_ways.size():
		var hw: Array = _head_ways[i]
		var on := 2
		match traffic.light(hw[0], hw[1]):
			TrafficSim.Light.RED: on = 0
			TrafficSim.Light.YELLOW: on = 1
		for k in 3:
			var c: Color = LENS_COLORS[k]
			_lenses.multimesh.set_instance_color(i * 3 + k, c if k == on else c * LENS_DARK)


func _rebuild() -> void:
	# Neighbors' cities are drawn moved over to their place on the land.
	Terrain.shift = Terrain.shift_for(self)
	_rebuild_all()
	Terrain.shift = Vector2.ZERO


func _rebuild_all() -> void:
	var poles := []
	var arms := []
	var heads := []
	var lenses := []
	var hoods := []
	var plates := []
	var stops := []
	var yields := []
	var blades := []
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_paint := false
	_head_ways.clear()
	var nodes := traffic.junctions.keys()
	nodes.sort()
	var plans: Dictionary = roads.plans if roads != null else {}
	# Shaped junctions: painted by the rule book, each kept until it changes.
	var cache := {}
	var pieces := []
	var faded := [[], []]  # worn, ghost
	var marked := plans.keys()
	marked.sort()
	for n in marked:
		var plan: Dictionary = plans[n]
		if not JunctionMarks.marked(plan):
			continue
		var rules := JunctionMarks.leg_rules(traffic, n)
		var control := JunctionMarks.control_of(traffic.junctions.get(n, {}))
		var shut := JunctionMarks.car_free_legs(traffic, plan)
		var key := [plan, rules, Terrain.shift, control, shut]
		var hit: Array = _paint_cache.get(n, [])
		if hit.is_empty() or hit[0] != key:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			JunctionMarks.paint(plan, rules, st, RoadStyle.Y_JUNCTION + 0.02, control, shut)
			hit = [key, Terrain.drape(st.commit(), false, 4.0), JunctionMarks.wear(plan, control)]
		cache[n] = hit
		if hit[2] > 0:
			faded[hit[2] - 1].append(hit[1])
		else:
			pieces.append(hit[1])
	_paint_cache = cache
	var sign_at := {}  # way -> [post, facing back, right] of its stop sign or signal pole
	for n in nodes:
		var j: Dictionary = traffic.junctions[n]
		if j.control == TrafficSim.Rule.NONE:
			continue
		var painted := JunctionMarks.marked(plans.get(n, {}))
		var named := false
		# How far back from the stop line the crosswalk is (behind it where
		# the corner isn't shaped: in line with the cross street's
		# sidewalk); stop bars and signs sit behind the crosswalk.
		var cross := 0.0
		for w2 in traffic.ways_into(n):
			cross = maxf(cross, RoadStyle.TYPES[traffic.ways[w2].type].width * 0.5)
		var plain := cross + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH * 0.5
		var country_plan := {}
		for wid in traffic.ways_into(n):
			var seg: int = traffic.ways[wid].seg
			var sl := traffic.stop_line(wid)
			var dir: Vector3 = sl.dir
			var right: Vector3 = sl.right
			var half: float = RoadStyle.TYPES[traffic.ways[wid].type].width * 0.5
			var stops_here: bool = j.control == TrafficSim.Rule.SIGNAL or j.control == TrafficSim.Rule.ALL_STOP \
				or (j.control == TrafficSim.Rule.PRIORITY and not j.major.has(wid) and j.sign != "yield")
			var base := Vector3.ZERO
			var arm := {}
			if _is_country(plans, n, seg):
				if country_plan.is_empty():
					country_plan = _country_plan(plans, n)
				arm = _arm(country_plan, seg)
			if not arm.is_empty():
				# A country junction (no crosswalk): the stop line 4 ft before
				# the edge line of the road it meets, square to the lanes, and
				# the sign beside it, past the shoulder where the corner flares.
				var s := JunctionMarks.country_near(country_plan, arm) + JunctionMarks.BAR + 0.6
				var at: Array = LotPlanner.point_at(arm.pts, s)
				var t: Vector3 = at[1] if at.size() > 1 else Vector3.FORWARD
				t.y = 0.0
				t = t.normalized()
				dir = -t
				right = Vector3(-dir.z, 0.0, dir.x)
				# Past the shoulder, or in the grass strip behind a curb.
				var back: float = Junction.SHOULDER + 0.6 if arm.get("country", true) \
					else RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5
				var off := JunctionMarks.country_edge(country_plan, arm, s) + back
				base = Terrain.lift(at[0] + right * off)
				if stops_here and not RoadStyle.unpaved(arm.type):  # no paint on gravel
					JunctionMarks.country_bar(country_plan, arm, paint, RoadStyle.Y_JUNCTION + 0.02)
					any_paint = true
			else:
				var walk := plain
				# A shaped corner: the crosswalk runs from 0.3 to 2.7 m past where
				# the road stops, in line with the curb ramps.
				var trim := Junction.trim(plans, n, seg)
				if trim > 0.0:
					# Traffic stops behind the bar (TrafficSim.STOP_PAST_RETURN):
					# the crosswalk is 3 m on, at the curb ramps.
					walk = -TrafficSim.CROSSWALK_AHEAD
				var back := walk + 3.3  # behind the crosswalk and the stop bar
				base = sl.pos + right * sl.curb - dir * 1.0
				if not RoadStyle.TYPES[traffic.ways[wid].type].oneway:
					# On the near-side corner, in the grass strip beside the curb.
					base = sl.pos + right * (half + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5) - dir * back
				base = Terrain.lift(base)
				if stops_here and not painted and not RoadStyle.TYPES[traffic.ways[wid].type].oneway:
					# A crosswalk only where there are sidewalks to join.
					var spec: Dictionary = RoadStyle.TYPES[traffic.ways[wid].type]
					var walks: bool = spec.get("walk", true) and not spec.get("rural", false) \
						and not (roads != null and roads._rural.has(seg))
					_markings(paint, sl, half, walk, walks)
					any_paint = true
			var face := Basis.looking_at(-dir, Vector3.UP)  # facing the drivers
			sign_at[wid] = [base, dir, right]
			if j.control == TrafficSim.Rule.SIGNAL:
				poles.append(Transform3D(Basis().scaled(Vector3(1, POLE_H, 1)), base + Vector3(0, POLE_H * 0.5, 0)))
				# Mast arm out over the lanes, head above the middle lane.
				var out: float = (base - sl.pos).dot(right)
				var head: Vector3 = base + right * (sl.mid - out) + Vector3(0, POLE_H - 0.4, 0)
				var span: float = out - sl.mid
				arms.append(Transform3D(Basis(right, Vector3.UP, right.cross(Vector3.UP)).scaled(Vector3(span, 1, 1)),
					base + right * (-span * 0.5) + Vector3(0, POLE_H - 0.1, 0)))
				var ht := Transform3D(face, head)
				heads.append(ht)
				plates.append(ht * Transform3D(Basis(), Vector3(0, 0, HEAD_D * 0.5 + 0.01)))
				for k in 3:
					# The face is -Z, towards the drivers; red on top.
					var y: float = (1 - k) * HEAD_H / 3.0
					lenses.append(ht * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, y, -HEAD_D * 0.5 - 0.015)))
					hoods.append(ht * Transform3D(Basis(), Vector3(0, y + 0.15, -HEAD_D * 0.5 - 0.1)))
				_head_ways.append([n, wid])
			elif j.control == TrafficSim.Rule.ALL_STOP or (j.control == TrafficSim.Rule.PRIORITY and not j.major.has(wid)):
				var top := 2.13 + 0.38  # 7 ft to the bottom of the sign
				if not named:
					top = 3.35
				poles.append(Transform3D(Basis().scaled(Vector3(0.45, top, 0.45)), base + Vector3(0, top * 0.5, 0)))
				var sign_t := Transform3D(face, base + Vector3(0, 2.51, 0.0) + dir * -0.05)
				if not named:
					# Street-name blades crossing on top of the first post.
					named = true
					blades.append(Transform3D(Basis.looking_at(right, Vector3.UP), base + Vector3(0, 3.1, 0)))
					blades.append(Transform3D(Basis.looking_at(dir, Vector3.UP), base + Vector3(0, 3.3, 0)))
				if j.sign == "yield" and j.control == TrafficSim.Rule.PRIORITY:
					yields.append(sign_t)
				else:
					stops.append(sign_t)
	# The player's turn rules: lane-use arrows painted in each lane behind
	# the stop line (MUTCD 3B.20: one set near the line, one 50 ft or so
	# before), and No Left and No Right Turn signs on a post at the near
	# right corner, No Left on top when there are both.
	var rule_keys := traffic.lane_rules.keys()
	rule_keys.sort()
	var no_lefts := []
	var no_rights := []
	for k in rule_keys:
		var rule: Dictionary = traffic.lane_rules[k]
		var wid := _way_in(int(k.get_slice(":", 0)), int(k.get_slice(":", 1)))
		if wid == -1:
			continue
		var sl := traffic.stop_line(wid)
		var w: Dictionary = traffic.ways[wid]
		var masks := traffic.lane_masks(wid)
		if not rule.lanes.is_empty() and not RoadStyle.unpaved(w.type):
			for back in [ARROW_BACK, ARROW_BACK + 15.0]:
				if back + 2.4 > w.len * 0.45:
					continue  # a short block: the near set only
				for i in masks.size():
					var at: Vector3 = sl.pos + sl.right * float(w.offs[i]) - sl.dir * (back + 2.4)
					lane_arrow(paint, at, sl.dir, int(masks[i]), RoadStyle.Y_JUNCTION + 0.02)
					any_paint = true
		var faces := []
		if rule.no_left:
			faces.append(no_lefts)
		if rule.get("no_right", false):
			faces.append(no_rights)
		if not faces.is_empty():
			# On its own post at the near right corner, a little before the
			# stop sign or signal pole where there is one.
			var dir: Vector3 = sl.dir
			var post := Terrain.lift(sl.pos + sl.right * (sl.curb + 0.9) - dir * 1.5)
			if sign_at.has(wid):
				dir = sign_at[wid][1]
				post = sign_at[wid][0] - dir * 2.5
			var top := 2.51 + 0.8 * (faces.size() - 1)
			poles.append(Transform3D(Basis().scaled(Vector3(0.45, top, 0.45)), post + Vector3(0, top * 0.5, 0)))
			for i in faces.size():
				(faces[i] as Array).append(Transform3D(Basis.looking_at(-dir, Vector3.UP),
					post + Vector3(0, top - 0.8 * i, 0) - dir * 0.05))
	_fill(_no_lefts, no_lefts)
	_fill(_no_rights, no_rights)
	_fill(_poles, poles)
	_fill(_arms, arms)
	_fill(_heads, heads)
	_fill(_lenses, lenses)
	_fill(_hoods, hoods)
	_fill(_plates, plates)
	_fill(_stops, stops)
	_fill(_yields, yields)
	_fill(_blades, blades)
	if any_paint:
		pieces.append(Terrain.drape(paint.commit(), false, 4.0))
	_paint.mesh = RoadView._merge(pieces) if not pieces.is_empty() else null
	_worn.mesh = RoadView._merge(faded[0]) if not faded[0].is_empty() else null
	_ghost.mesh = RoadView._merge(faded[1]) if not faded[1].is_empty() else null


## The way along road `seg` into junction `node`, or -1.
func _way_in(node: int, seg: int) -> int:
	for wid in traffic.ways_into(node):
		if traffic.ways[wid].seg == seg:
			return wid
	return -1


## A white lane-use arrow (MUTCD 3B.20, Figure 3B-24: an 8 ft arrow on a
## town street) with its head at `at`, pointing along `dir`: straight, a
## left or right turn, or a shaft with turn branches for a shared lane.
static func lane_arrow(st: SurfaceTool, at: Vector3, dir: Vector3, mask: int, y: float) -> void:
	dir.y = 0.0
	dir = dir.normalized()
	var right := Vector3(-dir.z, 0.0, dir.x)
	var lift := Vector3(0, y, 0)
	var straight := (mask & TrafficSim.ARROW_S) != 0
	var tail := at - dir * 2.4 + lift
	# The shaft: up to the head, or to where it bends for a turn only.
	var top := at - dir * (0.9 if straight else 1.1) + lift
	_bar(st, tail, top)
	if straight:
		_head(st, top, dir)
	for side: float in [-1.0, 1.0]:
		if not (mask & (TrafficSim.ARROW_L if side < 0.0 else TrafficSim.ARROW_R)):
			continue
		# A branch from the shaft bending out to the side, then its head.
		var from := at - dir * (1.6 if straight else 1.1) + lift
		var neck := from + dir * 0.3 + right * side * 0.5
		_bar(st, from, neck)
		_head(st, neck, right * side)


## A painted bar 0.16 m wide from a to b.
static func _bar(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var r := Vector3(-along.z, 0.0, along.x) * 0.08
	RoadMesh._quad(st, a - r, a + r, b - r, b + r, 0.0, 0.0)


## An arrowhead 0.6 m across and 0.9 m long from `base`, pointing `fwd`.
static func _head(st: SurfaceTool, base: Vector3, fwd: Vector3) -> void:
	var r := Vector3(-fwd.z, 0.0, fwd.x) * 0.3
	RoadMesh._tri(st, [base - r, Vector2.ZERO], [base + r, Vector2.ZERO], [base + fwd * 0.9, Vector2.ZERO])


## True when the road `seg` meets node `n` as a country road (no curbs or
## sidewalks to join), in a country junction or a plain join.
func _is_country(plans: Dictionary, n: int, seg: int) -> bool:
	if _country_like(plans.get(n, {})):
		return true
	if plans.has(n) or not traffic.network.segments.has(seg):
		return false
	var spec: Dictionary = RoadStyle.TYPES[traffic.network.segments[seg].type]
	if spec.oneway:
		return false
	return spec.get("rural", false) or not spec.get("walk", true) or (roads != null and roads._rural.has(seg))


## The country junction's plan at a node, or its plain roads as arms.
func _country_plan(plans: Dictionary, n: int) -> Dictionary:
	if _country_like(plans.get(n, {})):
		return plans[n]
	var net: RoadNetwork = traffic.network
	return {"center": net.nodes[n], "arms": Junction.arms_at(net, n, roads._rural if roads != null else {},
		roads._urban if roads != null else {}),
		"corners": []}


## A country junction, or a town street meeting the highway through town:
## no crosswalks, stop lines at the edge of the road met.
static func _country_like(plan: Dictionary) -> bool:
	return plan.get("country", false) or plan.get("unmarked", false)


static func _arm(plan: Dictionary, seg: int) -> Dictionary:
	for arm in plan.get("arms", []):
		if arm.seg == seg:
			return arm
	return {}


## A stop bar across the approach lanes and a pair of crosswalk lines across
## the whole street, just short of the junction.
## `walk` is the crosswalk's centre, metres back from the stop line (less
## than 0 for one ahead of it).
func _markings(st: SurfaceTool, sl: Dictionary, half: float, walk: float, crosswalk := true) -> void:
	var y := RoadStyle.Y_JUNCTION + 0.02
	var p: Vector3 = sl.pos
	var dir: Vector3 = sl.dir
	# Two 12 in lines about 7 ft apart (MUTCD 3B.18: at least 6 ft), then a
	# 24 in stop bar 4 ft back.
	for k in ([-1.05, 1.05] if crosswalk else []):
		var c: float = walk + k
		RoadMesh.add_strip(st, PackedVector3Array([p - dir * (c + 0.15), p - dir * (c - 0.15)]), -half, half, y)
	var bar := walk + 1.2 + 1.2
	RoadMesh.add_strip(st, PackedVector3Array([p - dir * (bar + 0.6), p - dir * bar]), 0.15, half - 0.2, y)


func _batch(mesh: Mesh, mat: Material, colors := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	if mat != null:
		inst.material_override = mat
	add_child(inst)
	return inst


static func _fill(inst: MultiMeshInstance3D, xforms: Array) -> void:
	inst.multimesh.instance_count = xforms.size()
	for i in xforms.size():
		inst.multimesh.set_instance_transform(i, xforms[i])
		if inst.multimesh.use_colors:
			inst.multimesh.set_instance_color(i, GREEN)


static func _cylinder(r: float, h: float, sides: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = sides
	m.rings = 1
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## A flat sign plate facing -Z with the given number of corners.
static func _plate(r: float, corners: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for k in corners:
		# Octagons sit flat on top; the yield triangle points down.
		var a := TAU * k / corners + (PI / corners if corners == 8 else -PI * 0.5)
		pts.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	for k in corners:
		for face in [[Vector3.ZERO, pts[k], pts[(k + 1) % corners]], [Vector3.ZERO, pts[(k + 1) % corners], pts[k]]]:
			for v in face:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## The octagon: a textured face toward -Z and a grey back.
static func _sign_mesh(r: float, face: Material, back: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for side in [0, 1]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var z := 0.0 if side == 0 else 0.015
		var pts := []
		for k in 8:
			var a := TAU * k / 8 + PI / 8
			pts.append(Vector2(cos(a), sin(a)))
		for k in 8:
			var tri := [Vector2.ZERO, pts[k], pts[(k + 1) % 8]]
			if side == 0:
				tri = [Vector2.ZERO, pts[(k + 1) % 8], pts[k]]
			for v in tri:
				st.set_normal(Vector3(0, 0, -1) if side == 0 else Vector3(0, 0, 1))
				st.set_uv(Vector2(0.5 - v.x * 0.5, 0.5 - v.y * 0.5))
				st.add_vertex(Vector3(v.x * r, v.y * r, z))
		st.commit(mesh)
		mesh.surface_set_material(side, face if side == 0 else back)
	return mesh


## A square sign plate facing -Z, `h` metres half across, textured face and
## grey back.
static func _square_sign(h: float, face: Material, back: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for side in [0, 1]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var z := 0.0 if side == 0 else 0.015
		var c := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		var tris := [[0, 2, 1], [0, 3, 2]] if side == 0 else [[0, 1, 2], [0, 2, 3]]
		for tri in tris:
			for k in tri:
				var v: Vector2 = c[k]
				st.set_normal(Vector3(0, 0, -1) if side == 0 else Vector3(0, 0, 1))
				st.set_uv(Vector2(0.5 - v.x * 0.5, 0.5 - v.y * 0.5))
				st.add_vertex(Vector3(v.x * h, v.y * h, z))
		st.commit(mesh)
		mesh.surface_set_material(side, face if side == 0 else back)
	return mesh


## A 64 px No Left Turn face (R3-2), or No Right Turn (R3-1): white with a
## black border, a black turn arrow, and a red circle and slash over it.
## The arrow is mirrored for right; the slash runs top left to bottom right
## on both, as MUTCD draws it.
static func _no_turn_texture(left: bool) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var white := Color(0.95, 0.95, 0.93)
	var black := Color(0.06, 0.06, 0.06)
	var red := Color(0.75, 0.06, 0.06)
	for y in n:
		for x in n:
			var edge := mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			img.set_pixel(x, y, black if edge < 2 else white)
	# The arrow: up from the bottom, then left (or right), with a head.
	var flip := func(x: int) -> int: return x if left else n - 1 - x
	for y in range(22, 50):
		for x in range(34, 40):
			img.set_pixel(flip.call(x), y, black)
	for y in range(22, 28):
		for x in range(22, 40):
			img.set_pixel(flip.call(x), y, black)
	for y in range(14, 36):
		for x in range(12, 23):
			if x - 12 >= absf(y - 24.5) * 0.9:
				img.set_pixel(flip.call(x), y, black)
	# The red ring and slash, top left to bottom right.
	var c := Vector2(31.5, 31.5)
	for y in n:
		for x in n:
			var q := Vector2(x, y) - c
			var r := q.length()
			var on_ring := r > 23.0 and r < 28.0
			var on_slash := r < 25.0 and absf(q.x - q.y) < 4.0
			if on_ring or on_slash:
				img.set_pixel(x, y, red)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A 64 px STOP face: red octagon field, white border, white letters.
static func _stop_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var red := Color(0.72, 0.05, 0.06)
	var white := Color(0.95, 0.95, 0.93)
	for y in n:
		for x in n:
			var q := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5) / (n * 0.5)
			# Distance to the octagon's edge (apothem 0.924 of the radius).
			var d := maxf(maxf(absf(q.x), absf(q.y)), (absf(q.x) + absf(q.y)) * 0.7071)
			img.set_pixel(x, y, white if d > 0.84 else red)
	# Letters, 5 x 7 px each, scaled 2x, centred.
	var font := {
		"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
		"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
		"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
		"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	}
	var x0 := 32 - (4 * 6 * 2 - 2) / 2
	var y0 := 32 - 7
	var i := 0
	for ch in "STOP":
		var rows: Array = font[ch]
		for ry in 7:
			for rx in 5:
				if rows[ry][rx] == "1":
					for sy in 2:
						for sx in 2:
							img.set_pixel(x0 + i * 12 + rx * 2 + sx, y0 + ry * 2 + sy, white)
		i += 1
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
