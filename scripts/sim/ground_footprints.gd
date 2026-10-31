class_name GroundFootprints
extends RefCounted
## What stands on the ground, as 2D footprints (world x/z polygons), read
## from the sim's data and the builders' own plans, never from meshes. The
## one footprint reader: the overlap auditor (tools/overlap_audit.gd) checks
## these shapes pair by pair, and the ground map (GroundMap.build) files
## them as claims (docs/spec-ground-map.md).
##
## Where a footprint comes from (file and function) is in SRC; a few are
## worked out here the way their view works them out, because the view
## keeps its result only inside its drawing (noted "mirrors").
##
## Corners cut (each can make a count a little off, none hides a kind):
## the mirrored stop, yield, No Turn and signal posts can drift from their
## view if it changes (junction_view.gd _rebuild_all; where they slide off
## drives is shared: JunctionView._post_spot); a car out on the drive is
## counted for every garage whose drive is long enough (the game draws two
## cars in three there); a duplex's curb cut is taken as 3 m wide; streets
## are straight strips to the node (no curb-return pavement); a tree trunk
## is 0.5 m square. Ramps, crosswalks and drives' curb cuts are read here
## from the junction plans, the house plans and what the builders draw, not
## from CurbClaims, so what the claims miss is still caught.
##
## It lives with the sim but reads through the views' own code (RoadView,
## BuildingView, StreetSignView, JunctionView, run headless for the
## purpose): it runs every building's builder once, so it costs about what
## drawing the town's buildings costs.

## Half widths and sizes (metres).
const RAIL_HALF := 2.3  # ballast shoulder (RailView._ballast: 1.6 top, 2.3 shoulder)
const POST := {"stop_sign": 0.15, "yield_sign": 0.15, "no_turn_sign": 0.15, "street_name": 0.15,
	"signal_pole": 0.25, "streetlight": 0.25, "utility_pole": 0.2, "mailbox": 0.25, "bus_stop": 0.2}
const TRUNK := 0.25
const WALK_CENTRE_HALF := 0.3  # the line people walk along a sidewalk, +-0.3 m
const STALL := Vector2(2.5, 5.0)
const CAR := Vector2(1.9, 4.5)

## Who places each kind of thing (file and function).
const SRC := {
	"road": "scripts/roads/road_view.gd _rebuild_all (RoadMesh.street; RoadStyle.half_width)",
	"sidewalk_line": "scripts/roads/road_mesh.gd _town (sidewalk hw+curb+parkway .. +1.5 m)",
	"curb_ramp": "scripts/roads/junction.gd _ramp / _diagonal_ramp (ramps())",
	"crosswalk": "scripts/roads/junction_marks.gd paint; plain corners: scripts/traffic/junction_view.gd _markings",
	"rail_bed:county": "scripts/terrain/county_rail.gd routes (drawn by county_rail_view.gd _build)",
	"rail_bed:town": "scripts/sim/rail.gd pieces (drawn by scripts/rail/rail_view.gd)",
	"lot": "scripts/sim/lot_planner.gd plan/_lot, kept by scripts/sim/city_sim.gd _plan_lots/_lot_blocked",
	"building": "scripts/buildings/building_view.gd _draw/build_for (HouseBuilder.last_masses)",
	"public_site": "scripts/sim/services.gd footprint, scripts/sim/warehouses.gd corners",
	"drive": "scripts/art/house_builder.gd _yard (drive_x, drive_w); others scripts/sim/site_layout.gd for_building cut_x",
	"curb_cut": "scripts/art/house_builder.gd _yard (drive across the parkway); others site_layout.gd cut_x",
	"front_walk": "scripts/art/house_builder.gd _yard (h.walk: straight or L to the drive)",
	"parking_stall": "scripts/sim/site_layout.gd for_building spots (stall)",
	"dock": "scripts/sim/site_layout.gd factory spots (bay)",
	"post:stop_sign": "scripts/traffic/junction_view.gd _rebuild_all (stop posts; mirrored here)",
	"post:yield_sign": "scripts/traffic/junction_view.gd _rebuild_all (yield posts; mirrored here)",
	"post:no_turn_sign": "scripts/traffic/junction_view.gd _rebuild_all (R3-1/R3-2 posts; mirrored here)",
	"post:signal_pole": "scripts/traffic/junction_view.gd _rebuild_all (signal poles; mirrored here)",
	"post:street_name": "scripts/roads/street_sign_view.gd _corner",
	"post:streetlight": "scripts/art/street_lights.gd place",
	"post:utility_pole": "scripts/roads/pole_line.gd place (runs: road_view.gd _pole_runs/_pole_key/_pole_blocked)",
	"post:mailbox": "scripts/sim/curb_claims.gd mailbox_at (drawn by scripts/mail/mail_view.gd _mailboxes)",
	"post:bus_stop": "scripts/transit/bus_net.gd _place_stop, bus_view.gd _draw_stops",
	"tree_trunk": "scripts/art/house_builder.gd _yard_trees/_street_trees (BuildingView.trees_of)",
	"prop": "scripts/state/lot_state.gd items/_free (StateView._place)",
	"drive_car": "scripts/traffic/traffic_view.gd _out_front/_out_pick (mirrored here)",
	"garage_apron": "scripts/art/house_builder.gd garage DoorLog.add -> door_log.gd placed",
}

# ------------------------------------------------------------------ shapes

## Everything that stands on the ground, as shapes: {cat, what, key (its
## owner: "lot:" + a lot key, "seg:N", "node:N", "rail:N", "county:N",
## "service:N", "warehouse:N", "run:N", "stop:N"), poly (world x/z), box, id}.
static func collect(sim: CitySim) -> Array:
	var r := Reader.new(sim)
	r.step()
	return r.out


## Reads the town's footprints a little at a time (the game's ground survey
## after a town opens, GroundMap.survey_step): step() until it says it's
## done, then `out` holds what collect gives. Every step puts the builders'
## shared settings back as it found them, so a building the game draws
## between two steps is drawn as it would have been.
class Reader:
	extends RefCounted
	var sim: CitySim
	var out := []
	## Tells CurbClaims the junction plans worked out here (the auditor and
	## tests: no road view does it for them). The game's survey leaves the
	## road view's own plans be.
	var push_junctions := true
	var _stage := 0
	var _i := 0
	var _segs := []
	var _keys := []
	var _rv: RoadView
	var _plans := {}
	var _bv: BuildingView
	var _drawn := {}  # lot key -> [masses, plan, trees (world entries)]
	var _tree_grid := {}  # Vector2i (40 m) -> [world tree entries]
	var _stale := 0

	func _init(town: CitySim, push := true) -> void:
		sim = town
		push_junctions = push

	func done() -> bool:
		return _stage >= 12

	## Reads on for about `usec` microseconds (at least one piece; all of it
	## when 0). True once everything is read.
	func step(usec := 0) -> bool:
		var t0 := Time.get_ticks_usec()
		var keep := GroundFootprints._builder_state()
		while not done():
			_work()
			if usec > 0 and Time.get_ticks_usec() - t0 >= usec:
				break
		GroundFootprints._restore_builder_state(keep)
		return done()

	## What's left to read, about (0 to 1).
	func share() -> float:
		var per := float(_keys.size()) * 3.0 + 12.0
		var at := float(_stage)
		if _stage in [6, 7, 8]:
			at += float(_stage - 6) * _keys.size() + _i
		elif _stage > 8:
			at += 3.0 * _keys.size()
		return clampf(at / per, 0.0, 1.0)

	func _work() -> void:
		match _stage:
			0:
				# The road view's own reading of which streets are country
				# roads, which are town streets, and its junction plans (curb
				# returns, ramps).
				_rv = RoadView.new()
				_rv.sim = sim
				_rv.network = sim.network
				_rv._rural = _rv._rural_segments()
				_rv._urban = _rv._urban_next
				_plans = Junction.plan(sim.network, _rv._rural, _rv._urban, _rv._signals())
				if push_junctions:
					# The curb claims as the game has them (RoadView pushes its plans).
					CurbClaims.of(sim).set_junctions(_plans)
				_segs = sim.network.segments.keys()
				_i = 0
				_stage = 1
			1:
				# Streets and sidewalks, a few at a time.
				var n := mini(_i + 24, _segs.size())
				for i in range(_i, n):
					GroundFootprints._road(out, sim, _rv, _plans, _segs[i])
				_i = n
				if _i >= _segs.size():
					_stage = 2
			2:
				GroundFootprints._junction_bits(out, sim, _plans)
				GroundFootprints._rail(out, sim)
				GroundFootprints._lots(out, sim)
				GroundFootprints._public(out, sim)
				_stage = 3
			3:
				# The buildings first: their builders' aprons claim the curb (as
				# the game's signs and lamps stand once the town is drawn).
				_bv = BuildingView.new()
				_bv.sim = sim
				_bv._check_parkways()  # the view's keep-clear spots for street trees
				_keys = sim.buildings.keys()
				_keys.sort()
				_i = 0
				_stage = 6
			6:
				if _i < _keys.size():
					GroundFootprints._built_one(self, _keys[_i])
				_next_key(7)
			7:
				# Mailboxes once every lot is drawn (they keep off the neighbours' drives).
				if _i < _keys.size():
					GroundFootprints._mailbox_of(self, _keys[_i])
				_next_key(8)
			8:
				if _i == 0:
					_bv.free()
					_bv = null
					if _stale > 0:
						print("ground_footprints: %d buildings drew no masses of their own (BuildingView would reuse the last one's)" % _stale)
				if _i < _keys.size():
					GroundFootprints._props_of(self, _keys[_i])
				_next_key(9)
			9:
				GroundFootprints._signs(out, sim, _rv, _plans)
				GroundFootprints._name_posts(out, sim)
				_stage = 10
			10:
				for l in StreetLights.place(sim.network, _rv._rural, CurbClaims.of(sim)):
					var p: Vector3 = l[1]
					GroundFootprints._add(out, "post", "streetlight", "seg:%d" % int(l[6]), GroundFootprints._sq(Vector2(p.x, p.z), GroundFootprints.POST.streetlight))
				GroundFootprints._poles(out, sim, _rv)
				_rv.free()
				_rv = null
				_stage = 11
			11:
				for id in sim.buses.stops:
					var st: Dictionary = sim.buses.stops[id]
					var pos: Vector3 = st.pos
					var pt: Vector3 = st.get("pt", pos)
					var outward := Vector3(pos.x - pt.x, 0.0, pos.z - pt.z).normalized()
					var at := pos + outward * (RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5)
					GroundFootprints._add(out, "post", "bus_stop", "stop:%s" % id, GroundFootprints._sq(Vector2(at.x, at.z), GroundFootprints.POST.bus_stop))
				for i in out.size():
					out[i].id = i
				_stage = 12

	func _next_key(then: int) -> void:
		_i += 1
		if _i >= _keys.size():
			_i = 0
			_stage = then


## The builders' shared settings (HouseBuilder's statics), to put back.
static func _builder_state() -> Array:
	return [HouseBuilder.last_masses, HouseBuilder.last_info, HouseBuilder.cuts_drawn, HouseBuilder.dry_all,
		HouseBuilder.keep_arrays, HouseBuilder.owner_care, HouseBuilder.restored, HouseBuilder.flat_weeds,
		HouseBuilder.grown, HouseBuilder.drawn, HouseBuilder.unseated]


static func _restore_builder_state(k: Array) -> void:
	HouseBuilder.last_masses = k[0]
	HouseBuilder.last_info = k[1]
	HouseBuilder.cuts_drawn = k[2]
	HouseBuilder.dry_all = k[3]
	HouseBuilder.keep_arrays = k[4]
	HouseBuilder.owner_care = k[5]
	HouseBuilder.restored = k[6]
	HouseBuilder.flat_weeds = k[7]
	HouseBuilder.grown = k[8]
	HouseBuilder.drawn = k[9]
	HouseBuilder.unseated = k[10]


static func _add(out: Array, cat: String, what: String, key: String, poly: PackedVector2Array) -> void:
	if poly.size() < 3:
		return
	var box := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		box = box.expand(v)
	out.append({"cat": cat, "what": what, "key": key, "poly": poly, "box": box, "id": -1})


static func _sq(c: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-half, -half), c + Vector2(half, -half), c + Vector2(half, half), c + Vector2(-half, half)])


## A box `half_len` along `along` and `half_w` across, round `c`.
static func _obb(c: Vector2, along: Vector2, half_len: float, half_w: float) -> PackedVector2Array:
	var u := along.normalized()
	var n := Vector2(-u.y, u.x)
	return PackedVector2Array([c - u * half_len - n * half_w, c + u * half_len - n * half_w,
		c + u * half_len + n * half_w, c - u * half_len + n * half_w])


## A lot-frame Rect2 (x across, z back from the street) in the world.
static func _rect(frame: Transform3D, r: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var w := frame * Vector3(q.x, 0.0, q.y)
		out.append(Vector2(w.x, w.z))
	return out


## Quads along a polyline between offsets o0..o1 (to the right of travel
## when positive), one per step.
static func _strip(out: Array, cat: String, what: String, key: String, pts: PackedVector3Array, o0: float, o1: float) -> void:
	for i in pts.size() - 1:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		if a.distance_to(b) < 0.01:
			continue
		var u := (b - a).normalized()
		var n := Vector2(-u.y, u.x)
		_add(out, cat, what, key, PackedVector2Array([a + n * o0, b + n * o0, b + n * o1, a + n * o1]))


## One street's pavement and its sidewalks' walking lines.
static func _road(out: Array, sim: CitySim, rv: RoadView, plans: Dictionary, id: int) -> void:
	var net := sim.network
	var sg: Dictionary = net.segments[id]
	var type: int = sg.type
	var pts := net.sample_segment(id)
	if absf(pts[pts.size() / 2].y) > 1.0:
		return  # a bridge or tunnel: it claims no ground at grade
	var hw := RoadStyle.half_width(type)
	var key := "seg:%d" % id
	_strip(out, "road", RoadStyle.TYPES[type].get("name", str(type)), key, pts, -hw, hw)
	var spec: Dictionary = RoadStyle.TYPES[type]
	if RoadStyle.is_freeway(type) or not spec.get("walk", true):
		return
	var urban: bool = rv._urban.has(id)
	var rural: bool = (rv._rural.has(id) or spec.get("rural", false))
	if not urban and (spec.get("rural", false) or (rural and float(spec.median) == 0.0)):
		return  # a country road: no sidewalk
	# Its sidewalks, trimmed where a shaped corner takes over.
	var ja := Junction.trim(plans, sg.a, id)
	var jb := Junction.trim(plans, sg.b, id)
	if ja > 0.0 or jb > 0.0:
		pts = RoadMesh._between(pts, ja, RoadNetwork.polyline_length(pts) - jb)
	var mid := hw + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH * 0.5
	for side in [-1.0, 1.0]:
		_strip(out, "sidewalk_line", "sidewalk", key, pts, side * (mid - WALK_CENTRE_HALF), side * (mid + WALK_CENTRE_HALF))


## Curb ramps and crosswalks at shaped town corners (Junction._draw_node,
## JunctionMarks.paint): across each arm from d + 0.3 to d + 2.7 m out.
## Worked out here from the junction plans themselves, not from CurbClaims,
## so a post the claims let stand on a ramp is still caught.
static func _junction_bits(out: Array, sim: CitySim, plans: Dictionary) -> void:
	for n in plans:
		var j: Dictionary = plans[n]
		if j.get("country", false) or j.has("bend"):
			continue
		var center: Vector3 = j.center
		var key := "node:%d" % n
		var ramps := Junction.ramps(j)
		for r in ramps:
			var c: Dictionary = j.corners[r[0]]
			var a: Dictionary = j.arms[c.a]
			var b: Dictionary = j.arms[c.b]
			if r[1] == "pair":
				for pair in [[a, 1.0], [b, -1.0]]:
					var arm: Dictionary = pair[0]
					var from: float = float(arm.d) + Junction.RAMP_GAP
					if from + Junction.RAMP_WIDTH > float(arm.length) * 0.5:
						continue
					_arm_band(out, "curb_ramp", "pair", key, center, arm, pair[1], float(arm.hw),
						float(arm.hw) + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH, from, from + Junction.RAMP_WIDTH)
			else:
				# A diagonal ramp at the corner's middle: a square at the curb return.
				var mid := (Vector2(a.n) * -1.0 + Vector2(b.n)).normalized()
				var arm_hw := maxf(float(a.hw), float(b.hw))
				var at := Vector2(center.x, center.z) + mid * (arm_hw + float(c.r) * 0.4)
				_add(out, "curb_ramp", "diagonal", key, _sq(at, 1.2))
		if JunctionMarks.marked(j):
			for arm in j.arms:
				var d: float = float(arm.d)
				if d + JunctionMarks.CROSS_FAR > float(arm.length) * 0.5:
					continue
				_arm_band(out, "crosswalk", "shaped", key, center, arm, 1.0, -float(arm.hw), float(arm.hw),
					d + JunctionMarks.CROSS_NEAR, d + JunctionMarks.CROSS_FAR)


static func _arm_band(out: Array, cat: String, what: String, key: String, center: Vector3, arm: Dictionary,
		side: float, o0: float, o1: float, from: float, to: float) -> void:
	var p0: Array = LotPlanner.point_at(arm.pts, from)
	var p1: Array = LotPlanner.point_at(arm.pts, to)
	var a := Vector2(p0[0].x, p0[0].z)
	var b := Vector2(p1[0].x, p1[0].z)
	var dir := Vector2(p0[1].x, p0[1].z).normalized()
	var nrm := Vector2(-dir.y, dir.x) * side
	_add(out, cat, what, key, PackedVector2Array([a + nrm * o0, b + nrm * o0, b + nrm * o1, a + nrm * o1]))


static func _rail(out: Array, sim: CitySim) -> void:
	for id in sim.rail.pieces:
		var pc: Dictionary = sim.rail.pieces[id]
		var pts: PackedVector3Array = PackedVector3Array(pc.get("pts", []))
		if pts.size() < 2:
			continue
		_strip(out, "rail_bed", "town", "rail:%d" % id, pts, -RAIL_HALF, RAIL_HALF)
	# The county's real railroads near the town (region -> local).
	var box := Rect2()
	var first := true
	for id in sim.network.nodes:
		var p: Vector3 = sim.network.nodes[id]
		if first:
			box = Rect2(Vector2(p.x, p.z), Vector2.ZERO)
			first = false
		box = box.expand(Vector2(p.x, p.z))
	if first:
		return
	box = box.grow(300.0)
	var o := sim.terrain_offset
	var rbox := Rect2(box.position + o, box.size)
	for route in CountyRail.all().size():
		var prof := CountyRail.profile(route)
		var at: PackedVector2Array = prof.at
		var kind: PackedByteArray = prof.kind
		for i in at.size() - 1:
			if not rbox.has_point(at[i]):
				continue
			if kind[i] == 3 or kind[i + 1] == 3 or kind[i] == 2 or kind[i + 1] == 2:
				continue  # inside a backdrop town (not drawn), or on a bridge
			var a := at[i] - o
			var b := at[i + 1] - o
			if a.distance_to(b) < 0.01:
				continue
			var u := (b - a).normalized()
			var n := Vector2(-u.y, u.x)
			_add(out, "rail_bed", "county", "county:%d" % route,
				PackedVector2Array([a - n * RAIL_HALF, b - n * RAIL_HALF, b + n * RAIL_HALF, a + n * RAIL_HALF]))


static func _lots(out: Array, sim: CitySim) -> void:
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		var c: PackedVector2Array = lot.get("corners", PackedVector2Array())
		if c.size() >= 3:
			_add(out, "lot", "built" if sim.buildings.has(key) else "empty", "lot:" + key, c)


static func _public(out: Array, sim: CitySim) -> void:
	for id in sim.services.buildings:
		_add(out, "public_site", "service", "service:%d" % id, sim.services.footprint(id))
	for id in sim.warehouses.buildings:
		var poly := PackedVector2Array()
		for p in Warehouses.corners(sim.warehouses.buildings[id]):
			poly.append(Vector2(p.x, p.y))
		_add(out, "public_site", "warehouse", "warehouse:%d" % id, poly)


## Stop, yield and No Left/Right posts and signal poles, where
## JunctionView._rebuild_all stands them (mirrors junction_view.gd 183-327:
## positions only; each slid off drives and ramps by the same
## JunctionView._post_spot and no_turn_spot).
static func _signs(out: Array, sim: CitySim, rv: RoadView, plans: Dictionary) -> void:
	var traffic := sim.traffic
	if traffic._dirty:
		traffic._rebuild()  # a town just loaded, not yet run: its junctions worked out (as car_pose does)
	var claims := CurbClaims.of(sim)
	var nodes := traffic.junctions.keys()
	nodes.sort()
	var sign_at := {}
	for n in nodes:
		var j: Dictionary = traffic.junctions[n]
		if j.control == TrafficSim.Rule.NONE:
			continue
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
			var base := Vector3.ZERO
			var arm := {}
			if _is_country(traffic, rv, plans, n, seg):
				if country_plan.is_empty():
					country_plan = _country_plan(traffic, rv, plans, n)
				arm = _arm(country_plan, seg)
			if not arm.is_empty():
				var s := JunctionMarks.country_near(country_plan, arm) + JunctionMarks.BAR + 0.6
				var at: Array = LotPlanner.point_at(arm.pts, s)
				var t: Vector3 = at[1] if at.size() > 1 else Vector3.FORWARD
				t.y = 0.0
				t = t.normalized()
				dir = -t
				right = Vector3(-dir.z, 0.0, dir.x)
				var back: float = Junction.SHOULDER + 0.6 if arm.get("country", true) \
					else RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5
				var off := JunctionMarks.country_edge(country_plan, arm, s) + back
				var meant: Vector3 = at[0] + right * off
				base = JunctionView._post_spot(claims, meant, dir, j.control == TrafficSim.Rule.SIGNAL,
					JunctionView.post_back(sim.network.nodes[n], meant, dir, cross, j.control == TrafficSim.Rule.SIGNAL),
					JunctionView.post_ahead(false, true))
			else:
				var walk := plain
				if Junction.trim(plans, n, seg) > 0.0:
					walk = -TrafficSim.CROSSWALK_AHEAD
				var back := walk + 3.3
				base = sl.pos + right * sl.curb - dir * 1.0
				if not RoadStyle.TYPES[traffic.ways[wid].type].oneway:
					base = sl.pos + right * (half + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5) - dir * back
				base = JunctionView._post_spot(claims, base, dir, j.control == TrafficSim.Rule.SIGNAL,
					JunctionView.post_back(sim.network.nodes[n], base, dir, cross, j.control == TrafficSim.Rule.SIGNAL),
					JunctionView.post_ahead(Junction.trim(plans, n, seg) > 0.0, false))
				# A crosswalk at a plain (unshaped) corner (_markings).
				var stops_here: bool = j.control == TrafficSim.Rule.SIGNAL or j.control == TrafficSim.Rule.ALL_STOP \
					or (j.control == TrafficSim.Rule.PRIORITY and not j.major.has(wid) and j.sign != "yield")
				var spec: Dictionary = RoadStyle.TYPES[traffic.ways[wid].type]
				var walks: bool = spec.get("walk", true) and not spec.get("rural", false) and not rv._rural.has(seg)
				if stops_here and not JunctionMarks.marked(plans.get(n, {})) and not spec.oneway and walks:
					var c: Vector3 = sl.pos - dir * walk
					_add(out, "crosswalk", "plain", "node:%d" % n, _obb(Vector2(c.x, c.z), Vector2(dir.x, dir.z), 1.2, half))
			sign_at[wid] = [base, dir]
			var at2 := Vector2(base.x, base.z)
			if j.control == TrafficSim.Rule.SIGNAL:
				_add(out, "post", "signal_pole", "node:%d" % n, _sq(at2, POST.signal_pole))
			elif j.control == TrafficSim.Rule.ALL_STOP or (j.control == TrafficSim.Rule.PRIORITY and not j.major.has(wid)):
				var what := "yield_sign" if j.sign == "yield" and j.control == TrafficSim.Rule.PRIORITY else "stop_sign"
				_add(out, "post", what, "node:%d" % n, _sq(at2, POST.stop_sign))
	var rule_keys := traffic.lane_rules.keys()
	rule_keys.sort()
	for k in rule_keys:
		var rule: Dictionary = traffic.lane_rules[k]
		var wid := -1
		var node := int(k.get_slice(":", 0))
		var seg := int(k.get_slice(":", 1))
		for w in traffic.ways_into(node):
			if traffic.ways[w].seg == seg:
				wid = w
		if wid == -1 or not (rule.get("no_left", false) or rule.get("no_right", false)):
			continue
		var sl := traffic.stop_line(wid)
		var post: Vector3 = sl.pos + sl.right * (sl.curb + 0.9) - sl.dir * 1.5
		var pdir: Vector3 = sl.dir
		if sign_at.has(wid):
			pdir = sign_at[wid][1]
			post = sign_at[wid][0] - pdir * 2.5
		post = JunctionView.no_turn_spot(claims, post, pdir)
		_add(out, "post", "no_turn_sign", "node:%d" % node, _sq(Vector2(post.x, post.z), POST.no_turn_sign))


static func _is_country(traffic: TrafficSim, rv: RoadView, plans: Dictionary, n: int, seg: int) -> bool:
	var j: Dictionary = plans.get(n, {})
	if j.get("country", false) or j.get("unmarked", false):
		return true
	if plans.has(n) or not traffic.network.segments.has(seg):
		return false
	var spec: Dictionary = RoadStyle.TYPES[traffic.network.segments[seg].type]
	if spec.oneway:
		return false
	return spec.get("rural", false) or not spec.get("walk", true) or rv._rural.has(seg)


static func _country_plan(traffic: TrafficSim, rv: RoadView, plans: Dictionary, n: int) -> Dictionary:
	var j: Dictionary = plans.get(n, {})
	if j.get("country", false) or j.get("unmarked", false):
		return j
	var net: RoadNetwork = traffic.network
	return {"center": net.nodes[n], "arms": Junction.arms_at(net, n, rv._rural, rv._urban), "corners": []}


static func _arm(plan: Dictionary, seg: int) -> Dictionary:
	for arm in plan.get("arms", []):
		if arm.seg == seg:
			return arm
	return {}


## Corner street-name posts (StreetSignView._corner, called as is).
static func _name_posts(out: Array, sim: CitySim) -> void:
	var ssv := StreetSignView.new()
	ssv.sim = sim
	for n in sim.network.nodes:
		var spec := ssv._corner(n)
		if not spec.is_empty():
			_add(out, "post", "street_name", "node:%d" % n, _sq(spec.at, POST.street_name))
	ssv.free()


## Utility poles down country roads and town streets (RoadView's own runs,
## keys and blocks: road_view.gd 570-620).
static func _poles(out: Array, sim: CitySim, rv: RoadView) -> void:
	var segs := {}
	for id in sim.network.segments:
		var pts := sim.network.sample_segment(id)
		var spec: Dictionary = RoadStyle.TYPES[sim.network.segments[id].type]
		if RoadStyle.is_freeway(sim.network.segments[id].type) or absf(pts[pts.size() / 2].y) > 1.0:
			continue
		var rural: bool = (rv._rural.has(id) or spec.get("rural", false)) and pts[pts.size() / 2].y < 1.0
		if rv._urban.has(id) or rural:
			segs[id] = true
	var drives := rv._drives()
	for run in rv._pole_runs(segs):
		var pkey := rv._pole_key(run, drives)
		for pole in PoleLine.place(run.pts, pkey[2], pkey[3], pkey[4], rv._pole_blocked(run.ids)):
			var b: Vector3 = pole[0]
			_add(out, "post", "utility_pole", "run:%d" % int(run.id), _sq(Vector2(b.x, b.z), POST.utility_pole))


## One building as its builder draws it (BuildingView._spawn's own steps:
## its footprints, its plan, its trees), then what stands on its lot: the
## drive and curb cut, the front walk, parking and docks, garage doors'
## aprons, a car drawn out on the drive. Its builder runs dry (its plan laid
## out, no surfaces made: the same plan, as HouseBuilder.dry_all promises).
static func _built_one(r: Reader, key: String) -> void:
	var sim := r.sim
	var out := r.out
	var bv := r._bv
	if not sim.lots.has(key):
		return
	var lot: Dictionary = sim.lots[key]
	var b: Dictionary = sim.buildings[key]
	var frame := SiteLayout.frame(lot)
	var xf := Transform3D(Basis.looking_at(-lot.normal, Vector3.UP), Vector3(lot.front.x, 0.0, lot.front.z))
	var rng := RandomNumberGenerator.new()
	rng.seed = b.seed
	var fit := bv.fit_of(key, xf)
	var type := BuildingTypes.type_of(b)
	HouseBuilder.last_info = {}
	var before := HouseBuilder.last_masses
	HouseBuilder.last_masses = []
	# What its builder paves across the parkway, as it draws it (the
	# curb claims read the plan instead, so the two are checked apart).
	HouseBuilder.cuts_drawn = []
	HouseBuilder.dry_all = true
	var parts := bv._draw(key, lot, b, fit, rng.randi())
	HouseBuilder.dry_all = false
	var paved: Array = HouseBuilder.cuts_drawn
	HouseBuilder.cuts_drawn = null
	var masses: Array = HouseBuilder.last_masses
	if masses.is_empty() and not before.is_empty():
		r._stale += 1  # BuildingView would have used the previous building's masses here
	var plan: Dictionary = HouseBuilder.last_info.duplicate() if type == "house" else {}
	var trees := []
	# The trees as BuildingView._set_trees keeps them: street trees off
	# its keep-clear spots and the mailbox, a corner lot's side-street
	# trees too.
	var mailbox := CurbClaims.of(sim).mailbox_at(key, true)  # BuildingView._set_trees' own reading
	var planted := []
	if parts.size() > 2:
		for t: Array in parts[2]:
			var w := frame * (t[0] as Vector3)
			var street := (t[0] as Vector3).z < -0.5
			if street and (not bv._parkway_free(Vector2(w.x, w.z)) \
					or Vector2(w.x, w.z).distance_to(mailbox) < BuildingView.MAILBOX_CLEAR):
				continue
			planted.append([w, int(t[1]), float(t[3]), float(t[4]) if t.size() > 4 else -1.0, street])
	for t: Array in bv._side_trees(key):
		var q: Vector2 = t[0]
		if bv._parkway_free(q):
			planted.append([Vector3(q.x, 0.0, q.y), int(t[1]), float(t[3]), -1.0, true])
	for e in planted:
		var w: Vector3 = e[0]
		trees.append(e)
		var c := Vector2i(floori(w.x / 40.0), floori(w.z / 40.0))
		if not r._tree_grid.has(c):
			r._tree_grid[c] = []
		r._tree_grid[c].append(e)
	r._drawn[key] = [masses, plan, trees]
	for m: Rect2 in masses:
		_add(out, "building", type, "lot:" + key, _rect(frame, m))
	for e in trees:
		var w: Vector3 = e[0]
		_add(out, "tree_trunk", "street" if e[4] else "yard", "lot:" + key, _sq(Vector2(w.x, w.z), TRUNK))
	var tc := float(lot.get("to_curb", 2.0))
	# Drive and curb cut, front walk.
	var lay := SiteLayout.for_lot(sim, key)
	if type == "house" and plan.has("drive_x"):
		var dx := float(plan.drive_x)
		var dw := float(plan.drive_w)
		_add(out, "drive", "house", "lot:" + key, _rect(frame, Rect2(dx - dw * 0.5, 0.0, dw, maxf(float(plan.get("garage_z", 6.0)), 1.0))))
		_add(out, "curb_cut", "house", "lot:" + key, _rect(frame, Rect2(dx - dw * 0.5, -tc, dw, tc)))
		if plan.has("walk"):
			# Where an L walk meets the drive, the drive takes over.
			var wr: Rect2 = plan.walk
			if wr.end.x > dx - dw * 0.5 and wr.position.x < dx + dw * 0.5 and wr.size.y < 2.0:
				if wr.position.x < dx:
					wr = Rect2(wr.position, Vector2(maxf(dx - dw * 0.5 - wr.position.x, 0.0), wr.size.y))
				else:
					wr = Rect2(Vector2(dx + dw * 0.5, wr.position.y), Vector2(maxf(wr.end.x - dx - dw * 0.5, 0.0), wr.size.y))
			if wr.size.x > 0.1:
				_add(out, "front_walk", "house", "lot:" + key, _rect(frame, wr))
		for d in DoorLog.placed(plan):
			if d[0] != "garage":
				continue
			var c: Vector3 = d[1]
			var f: Vector3 = d[2]
			var w := float(d[3])
			var a2 := Vector2(c.x, c.z) + Vector2(f.x, f.z) * 1.5
			var poly := PackedVector2Array()
			for q in _obb(a2, Vector2(f.x, f.z), 1.5, w * 0.5):
				var wq := frame * Vector3(q.x, 0.0, q.y)
				poly.append(Vector2(wq.x, wq.z))
			_add(out, "garage_apron", "house", "lot:" + key, poly)
	else:
		if type == "duplex":
			if not lay.get("main_street", false) and not lay.spots.is_empty():
				var dcx := float(lay.cut_x)
				_add(out, "curb_cut", type, "lot:" + key, _rect(frame, Rect2(dcx - 1.5, -tc, 3.0, tc)))
		else:
			for c in paved:
				_add(out, "curb_cut", type, "lot:" + key, _paved_poly(frame, c))
		if not lay.get("main_street", false) and not lay.spots.is_empty():
			var cx := float(lay.cut_x)
			var cw := 3.0 if type == "duplex" else 6.0  # the drive on the lot (as #940 measured it)
			_add(out, "drive", type, "lot:" + key, _rect(frame, Rect2(cx - cw * 0.5, 0.0, cw, maxf(float(lay.get("aisle_z", 0.0)), 3.0))))
	for sp in lay.spots:
		var at: Vector2 = sp.pos
		var face: Vector2 = sp.get("face", Vector2(0, 1))
		match String(sp.kind):
			"stall":
				_add(out, "parking_stall", type, "lot:" + key, _local_obb(frame, at, face, STALL.y * 0.5, STALL.x * 0.5))
			"bay", "dock":
				_add(out, "dock", type, "lot:" + key, _local_obb(frame, at - face * 3.0, face, 3.0, 1.8))
			"garage":
				if int(b.zone) != ZoneMap.Zone.RESIDENTIAL:
					continue
				# Drawn out on the drive where it's long enough (TrafficView._out_pick).
				var front := at - face * 6.2
				if (front - face * CAR.y * 0.5).y >= 2.6 and (front - face * CAR.y).y >= 0.0:
					_add(out, "drive_car", type, "lot:" + key, _local_obb(frame, front - face * CAR.y * 0.5, face, CAR.y * 0.5, CAR.x * 0.5))


## A home's curbside mailbox (once every lot is drawn: it keeps off the
## neighbours' drives).
static func _mailbox_of(r: Reader, key: String) -> void:
	if r._drawn.has(key) and int(r.sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL:
		var box := r._bv._mailbox_at(key)
		if box.is_finite():
			_add(r.out, "post", "mailbox", "lot:" + key, _sq(box, POST.mailbox))


## A lot's yard props (StateView._place: the drawn masses, plan and nearby trees).
static func _props_of(r: Reader, key: String) -> void:
	var sim := r.sim
	if not r._drawn.has(key) or LotState.kind_of(sim.buildings[key]) == "":
		return
	var p: Vector3 = sim.lots[key].pos
	var near := []
	var c0 := Vector2i(floori(p.x / 40.0), floori(p.z / 40.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for e in r._tree_grid.get(c0 + Vector2i(dx, dz), []):
				if Vector2(e[0].x, e[0].z).distance_to(Vector2(p.x, p.z)) < 40.0:
					near.append([e[0], e[1], e[2], e[3]])
	var yard := LotState.yard_of(sim, key, r._drawn[key][0], r._drawn[key][1], near)
	var b: Dictionary = sim.buildings[key]
	var piled := float(sim.hubs.trash.get(int(sim.lots[key].seg), 0.0)) >= Balance.GARBAGE_PILE_LB
	var items := LotState.items(sim.city_seed, key, int(b.seed), sim.care.tier_of(key), sim.care.cond_of(key), yard, piled)
	var frame := SiteLayout.frame(sim.lots[key])
	for it in items:
		if it.item in ["lease", "flag"]:
			continue  # a sign on a post or a flag pole: stands where it's meant to
		_add(r.out, "prop", String(it.item), "lot:" + key, _rect(frame, LotState.footprint(it.item, it.at, it.yaw)))


## Paving a builder drew out to the curb ([x0, x1, curb z, flare], lot
## frame) as it lies: across the parkway and sidewalk, a commercial apron
## flared at the curb (HouseBuilder._curb_cut's triangles).
static func _paved_poly(frame: Transform3D, c: Array) -> PackedVector2Array:
	var x0 := float(c[0])
	var x1 := float(c[1])
	var cz := float(c[2])
	var f := float(c[3])
	var w0 := cz + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH
	var w1 := w0 + RoadStyle.SIDEWALK_WIDTH
	var pts := [Vector2(x0 - f, cz), Vector2(x1 + f, cz), Vector2(x1, w0), Vector2(x1, w1), Vector2(x0, w1), Vector2(x0, w0)]
	var out := PackedVector2Array()
	for q: Vector2 in pts:
		var w := frame * Vector3(q.x, 0.0, q.y)
		out.append(Vector2(w.x, w.z))
	return out


static func _local_obb(frame: Transform3D, c: Vector2, along: Vector2, half_len: float, half_w: float) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for q in _obb(c, along, half_len, half_w):
		var w := frame * Vector3(q.x, 0.0, q.y)
		poly.append(Vector2(w.x, w.z))
	return poly

