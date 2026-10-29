class_name GradeCrossingView
extends Node3D
## The warning devices where the county roads and highways cross the
## county's railroads at grade (CountyRail kind 1), out in the country on
## the desktop app. The town's own streets get theirs from RailView.
##
## Real references (MUTCD 2009, Part 8; FRA crossing inventory):
## - Every approach has a Crossbuck (R15-1, two 48 by 9 inch white blades)
##   on the right, at least 15 ft from the nearest rail, with a "2 TRACKS"
##   plate (R15-2P) where there are more, and the blue Emergency
##   Notification sign (I-13) giving the railroad's number to call.
## - Passive crossings (most low traffic county roads) add a YIELD sign
##   (R1-2) on the Crossbuck's post (8B.04).
## - Active ones (every highway here, and about half the county roads,
##   as in the FRA inventory) have a mast with two 12 inch red lights on
##   20 inch black backgrounds that flash alternately, a bell, and a gate
##   arm striped red and white that lies across the approach lanes from
##   25 seconds before a train until its last car clears (49 CFR 234.225),
##   with the signal case (the "bungalow") beside the track.
## - About 500 ft before the crossing, the round yellow advance warning
##   sign (W10-1) on the right (Table 2C-4).

## How far out crossings are drawn, metres.
const DRAW_TO := 2500.0
## The camera moves this far before the crossings to draw are chosen again.
const RESCAN_M := 256.0
## Crossings of two lines (a double track) this near are one crossing.
const JOIN := 30.0
## The advance warning sign stands this far before the crossing, metres.
const ADVANCE := 150.0
## The lights change over twice a second (45 to 65 flashes a minute each
## per MUTCD 8C.02, so each lamp is lit about half a second).
const FLASH_MS := 550
## Every crossing shut, as if a train were coming (for pictures).
static var shut := false

const POST := Color("#a9aba8")    # galvanized steel
const SIGN_BACK := Color("#9a9c9a")  # bare aluminium
const WHITE := Color("#eceae2")
const BLACK := Color("#161616")
const RED := Color("#b2201a")
const YELLOW := Color("#e8b818")
const BLUE := Color("#1d4f9a")
const LENS := Color("#4a0d0a")
const CASE := Color("#8e9290")

var sim: CitySim
## Every crossing in the county: [{at (region Vector2), road (Vector2
## along it), track (Vector2 along it), half (road half width), tracks,
## spread (metres between the outer tracks), active, hits: [[corridor, s]]}].
static var _all: Array = []
static var _found := false

var _origin := Vector2.INF
var _scan_at := Vector2.INF
## Index into _all -> {node, up, down, lamps: [left, right]}
var _drawn := {}
var _mat: StandardMaterial3D
var _lit: StandardMaterial3D
var _state_at := 0


func setup(s: CitySim) -> void:
	sim = s


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.55
	_mat.metallic = 0.25
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lit = StandardMaterial3D.new()
	_lit.albedo_color = Color(1.0, 0.18, 0.1)
	_lit.emission_enabled = true
	_lit.emission = Color(1.0, 0.12, 0.05)
	_lit.emission_energy_multiplier = 4.0
	_lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _process(_delta: float) -> void:
	if not CountyRail.drawn():
		set_process(false)
		return
	if Terrain.view_origin != _origin:
		_origin = Terrain.view_origin
		for i in _drawn:
			_drawn[i].node.queue_free()
		_drawn.clear()
		_scan_at = Vector2.INF
	var cam := get_viewport().get_camera_3d()
	var c := _origin
	if cam != null:
		c = Vector2(cam.global_position.x, cam.global_position.z) + _origin
	if _scan_at == Vector2.INF or c.distance_to(_scan_at) > RESCAN_M:
		_rescan(c)
	var now := Time.get_ticks_msec()
	if now - _state_at > 200:
		_state_at = now
		_set_states(now)


static func crossings() -> Array:
	if not _found:
		_found = true
		_all = _find()
	return _all


## Where each line crosses a road: the middle of each run of crossing
## samples, set on the road's own line.
static func _find() -> Array:
	var out := []
	var cs := CountyTrains.corridors()
	for route in CountyRail.all().size():
		var prof := CountyRail.profile(route)
		var at: PackedVector2Array = prof.at
		var kind: PackedByteArray = prof.kind
		var i := 0
		while i < kind.size():
			if kind[i] != 1:
				i += 1
				continue
			var j := i
			while j + 1 < kind.size() and kind[j + 1] == 1:
				j += 1
			var mid := at[(i + j) >> 1]
			var a := at[maxi(i - 2, 0)]
			var b := at[mini(j + 2, at.size() - 1)]
			i = j + 1
			var track := (b - a).normalized()
			var x := _road_at(mid)
			if x.is_empty():
				continue
			# Where the track's line meets the road's.
			var hit: Variant = Geometry2D.line_intersects_line(mid, track, x.on, x.dir)
			var p: Vector2 = hit if hit != null and (hit as Vector2).distance_to(mid) < 20.0 else x.on
			var joined := false
			for e in out:
				if e.at.distance_to(p) < JOIN:
					e.tracks += 1
					e.spread = maxf(e.spread, e.at.distance_to(p) * 2.0)
					joined = true
					break
			if joined:
				continue
			var e := {"at": p, "road": x.dir, "track": track, "half": x.half, "highway": x.highway,
				"tracks": 1, "spread": 0.0, "hits": []}
			# Every highway; about half the county roads (hashed, so every
			# copy of a town sees the same).
			e.active = x.highway or (hash([roundi(p.x), roundi(p.y)]) & 1) == 0
			for ci in cs.size():
				var h := CountyTrains._cross(cs[ci], p - x.dir * 15.0, p + x.dir * 15.0)
				if not h.is_empty():
					e.hits.append([ci, h.s])
			out.append(e)
	return out


## The road crossing near p: {on, dir, half, highway}, or {}.
static func _road_at(p: Vector2) -> Dictionary:
	var h := Highways.near(p.x, p.y, CountyRail.CROSSING + 1.0)
	if not h.is_empty():
		var pts: PackedVector2Array = Highways.routes[h.route].pts
		var d: Vector2 = (pts[h.seg + 1] - pts[h.seg]).normalized()
		return {"on": h.on, "dir": d, "half": Highways.HALF_WIDTH, "highway": true}
	var m := CountyGrid.mile_at(p.x, p.y, CountyRail.CROSSING + 1.0)
	if not m.is_empty():
		return {"on": m.on, "dir": (m.b - m.a).normalized(), "half": CountyGrid.HALF_WIDTH, "highway": false}
	return {}


func _rescan(c: Vector2) -> void:
	_scan_at = c
	var all := crossings()
	for i in all.size():
		var e: Dictionary = all[i]
		var near: bool = e.at.distance_to(c) < DRAW_TO
		if near and not _drawn.has(i):
			var local := Vector3(e.at.x - _origin.x, 0.0, e.at.y - _origin.y)
			# The town's own streets win there (RailView draws their gates).
			if sim != null and sim.vegetation.is_occupied(Vegetation.cell_of(local)):
				continue
			_drawn[i] = _build(e)
		elif not near and _drawn.has(i) and e.at.distance_to(c) > DRAW_TO + RESCAN_M * 2.0:
			_drawn[i].node.queue_free()
			_drawn.erase(i)


## Gates down and lights flashing while a county train is near (as
## CountyTrains.tick works out the town's own crossings).
func _set_states(now: int) -> void:
	if _drawn.is_empty() or sim == null:
		return
	var trains := []
	if sim.county_rail:
		trains = sim.county_trains.now(sim.tick_count)  # with the trains' interchange stops
	var blink := (now / FLASH_MS) % 2
	var all := crossings()
	for i in _drawn:
		var d: Dictionary = _drawn[i]
		if not d.has("up"):
			continue
		var down := shut or _closed(all[i], trains)
		d.up.visible = not down
		d.down.visible = down
		d.lamps[0].visible = down and blink == 0
		d.lamps[1].visible = down and blink == 1


static func _closed(e: Dictionary, trains: Array) -> bool:
	for t in trains:
		var ahead: float = 0.0 if t.get("stopped", false) else CountyTrains.SPEED * CountyTrains.GATE_WARNING
		for h in e.hits:
			if int(t.corridor) != int(h[0]):
				continue
			var head: float = t.s
			var lo: float = head - (t.length if t.dir > 0 else -ahead)
			var hi: float = head + (ahead if t.dir > 0 else t.length)
			if h[1] >= lo - CountyTrains.GATE_PAD and h[1] <= hi + CountyTrains.GATE_PAD:
				return true
	return false


# --- Drawing -------------------------------------------------------------------

func _build(e: Dictionary) -> Dictionary:
	var node := Node3D.new()
	add_child(node)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := SurfaceTool.new()
	up.begin(Mesh.PRIMITIVE_TRIANGLES)
	var down := SurfaceTool.new()
	down.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lamps := [SurfaceTool.new(), SurfaceTool.new()]
	for l in lamps:
		l.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := Vector2(e.at) - _origin
	var road: Vector2 = e.road
	var track: Vector2 = e.track
	var hw: float = e.half
	var sin_a := maxf(absf(road.cross(track)), 0.35)
	# Back from the nearest rail by 15 ft (and the gate a little nearer).
	var back: float = (e.spread * 0.5 + RailModels.GAUGE * 0.5 + 4.6) / sin_a
	for k: float in [-1.0, 1.0]:
		# Traffic coming from the k side heads -k along the road; its right.
		var v := -road * k
		var right := Vector2(-v.y, v.x)
		var face := Vector3(-v.x, 0.0, -v.y)
		var rx := Vector3(right.x, 0.0, right.y)
		var at: Vector2 = p - v * back + right * (hw + 2.2)
		var f := Transform3D(Basis(rx, Vector3.UP, face), Vector3(at.x, Terrain.ground_y(at.x, at.y), at.y))
		if e.active:
			_signal(st, up, down, lamps, f, e, hw + 1.8)
		else:
			_passive(st, f, e)
		# The advance warning sign, where the road still runs.
		var w := p - v * ADVANCE + right * (hw + 2.4)
		var wr := w + _origin
		var on_road := Highways.distance(wr.x, wr.y) < 3.0 if e.highway else CountyGrid.distance(wr.x, wr.y) < 3.0
		if on_road and not sim.vegetation.is_occupied(Vegetation.cell_of(Vector3(w.x, 0, w.y))):
			_advance(st, Transform3D(f.basis, Vector3(w.x, Terrain.ground_y(w.x, w.y), w.y)))
	if e.active:
		_bungalow(st, p, road, track, hw, sin_a, e)
	var out := {"node": node}
	_add(node, st, _mat)
	if e.active:
		out.up = _add(node, up, _mat)
		out.down = _add(node, down, _mat)
		out.down.visible = false
		out.lamps = [_add(node, lamps[0], _lit), _add(node, lamps[1], _lit)]
		for l in out.lamps:
			l.visible = false
	return out


static func _add(node: Node3D, st: SurfaceTool, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	st.generate_normals()
	mi.mesh = st.commit()
	mi.material_override = mat
	node.add_child(mi)
	return mi


## A Crossbuck's two blades, white with black lettering, centred at y.
static func _crossbuck(st: SurfaceTool, f: Transform3D, y: float) -> void:
	for tilt: float in [PI * 0.25, -PI * 0.25]:
		var b := f * Transform3D(Basis(Vector3.BACK, tilt), Vector3(0, y, 0.07))
		RailView._box(st, b, Vector3.ZERO, Vector3(1.22, 0.23, 0.02), SIGN_BACK)
		_face(st, b, Vector3(0, 0, 0.011), Vector2(1.2, 0.21), WHITE)
		# RAILROAD / CROSSING: a word of letters each side of the middle.
		for n in 8:
			var x := -0.52 + n * 0.149
			if absf(x) < 0.09:
				continue
			_face(st, b, Vector3(x, 0, 0.013), Vector2(0.09, 0.12), BLACK)


## A passive crossing's post: Crossbuck, tracks plate, YIELD and I-13.
static func _passive(st: SurfaceTool, f: Transform3D, e: Dictionary) -> void:
	RailView._box(st, f, Vector3(0, 1.6, 0), Vector3(0.07, 3.2, 0.07), POST)
	_crossbuck(st, f, 2.85)
	var y := 2.2
	if e.tracks > 1:
		_plate(st, f, Vector3(0, y, 0.05), Vector2(0.68, 0.34), WHITE, BLACK)
		y -= 0.45
	# YIELD: a red triangle point down, white inside, red word.
	var c := Vector3(0, y - 0.28, 0.05)
	var s := 0.9
	var hgt := s * 0.866
	RailView._box(st, f, c + Vector3(0, hgt * 0.17, -0.01), Vector3(s * 0.5, hgt * 0.6, 0.01), SIGN_BACK)
	_tri(st, f, c + Vector3(-s * 0.5, hgt / 3.0, 0.0), c + Vector3(s * 0.5, hgt / 3.0, 0.0), c + Vector3(0, -hgt * 2.0 / 3.0, 0.0), RED)
	var si := s * 0.62
	var hi := si * 0.866
	var ci := c + Vector3(0, 0.01, 0.003)
	_tri(st, f, ci + Vector3(-si * 0.5, hi / 3.0, 0.0), ci + Vector3(si * 0.5, hi / 3.0, 0.0), ci + Vector3(0, -hi * 2.0 / 3.0, 0.0), WHITE)
	_face(st, f, c + Vector3(0, 0.06, 0.006), Vector2(0.3, 0.07), RED)
	_ens(st, f, Vector3(0, 1.0, 0.05))


## The blue Emergency Notification sign, low on the post.
static func _ens(st: SurfaceTool, f: Transform3D, c: Vector3) -> void:
	_plate(st, f, c, Vector2(0.46, 0.3), BLUE, WHITE)


## A rectangular plate: its face colour with a band of text in another.
static func _plate(st: SurfaceTool, f: Transform3D, c: Vector3, size: Vector2, col: Color, ink: Color) -> void:
	RailView._box(st, f, c - Vector3(0, 0, 0.008), Vector3(size.x, size.y, 0.012), SIGN_BACK)
	_face(st, f, c, size * 0.97, col)
	_face(st, f, c + Vector3(0, size.y * 0.12, 0.002), Vector2(size.x * 0.7, size.y * 0.18), ink)
	_face(st, f, c + Vector3(0, -size.y * 0.18, 0.002), Vector2(size.x * 0.55, size.y * 0.18), ink)


## An active crossing's mast: Crossbuck, bell, two flashing lights and the
## gate (its arm up in one mesh and down in the other).
func _signal(st: SurfaceTool, up: SurfaceTool, down: SurfaceTool, lamps: Array, f: Transform3D, e: Dictionary, arm_len: float) -> void:
	RailView._box(st, f, Vector3(0, 0.15, 0), Vector3(0.7, 0.3, 0.7), Color("#b9b6ae"))  # footing
	RailView._box(st, f, Vector3(0, 2.4, 0), Vector3(0.12, 4.8, 0.12), POST)
	_crossbuck(st, f, 4.15)
	var y := 3.55
	if e.tracks > 1:
		_plate(st, f, Vector3(0, y, 0.05), Vector2(0.68, 0.34), WHITE, BLACK)
	RailView._box(st, f, Vector3(0, 4.85, 0.0), Vector3(0.22, 0.14, 0.22), BLACK)  # bell
	# The cross arm and the two lights on their black backgrounds.
	RailView._box(st, f, Vector3(0, 2.95, 0.08), Vector3(1.55, 0.09, 0.09), POST)
	for i in 2:
		var x := -0.62 if i == 0 else 0.62
		var c := Vector3(x, 2.95, 0.16)
		_disc(st, f, c, 0.25, BLACK)
		_disc(st, f, c + Vector3(0, 0, 0.012), 0.155, LENS)
		RailView._box(st, f, c + Vector3(0, 0.17, 0.13), Vector3(0.34, 0.03, 0.26), BLACK)  # hood
		_disc(lamps[i], f, c + Vector3(0, 0, 0.02), 0.15, Color.WHITE)
	_ens(st, f, Vector3(0, 1.85, 0.07))
	# The gate mechanism on the mast, its arm reaching across the
	# approach lanes, and the counterweights behind.
	var g := Vector3(0, 1.05, 0.16)
	RailView._box(st, f, g, Vector3(0.42, 0.72, 0.36), Color("#2a2b2c"))
	var pivot := g + Vector3(-0.25, 0.1, 0.12)
	_arm(down, f * Transform3D(Basis.IDENTITY, pivot), arm_len)
	_arm(up, f * Transform3D(Basis(Vector3.BACK, -PI * 0.5), pivot), arm_len)


## A gate arm from its pivot out along -x: red and white stripes, a red
## lamp at its tip, and the counterweight behind the pivot.
static func _arm(st: SurfaceTool, f: Transform3D, length: float) -> void:
	var n := maxi(4, int(length / 0.4))
	for i in n:
		var x := -(i + 0.5) * length / n
		var w := 0.11 * (1.0 - 0.4 * float(i) / n)
		RailView._box(st, f, Vector3(x, 0, 0), Vector3(length / n, w, 0.07), RED if i % 2 == 0 else WHITE)
	RailView._box(st, f, Vector3(0.35, 0, 0), Vector3(0.6, 0.22, 0.12), Color("#3a3b3c"))


## The signal case by the track, a little steel house with a sloped roof.
func _bungalow(st: SurfaceTool, p: Vector2, road: Vector2, track: Vector2, hw: float, sin_a: float, e: Dictionary) -> void:
	var side := Vector2(-track.y, track.x)
	var along := (hw + 9.0) / sin_a
	# Away from the road on the side the track leans from it.
	var dir := track if track.dot(road) <= 0.0 else -track
	var q: Vector2 = p + dir * along + side * (e.spread * 0.5 + 6.0)
	var face := Vector3(side.x, 0.0, side.y)
	var rx := Vector3(dir.x, 0.0, dir.y)
	var f := Transform3D(Basis(rx, Vector3.UP, rx.cross(Vector3.UP).normalized()), Vector3(q.x, Terrain.ground_y(q.x, q.y), q.y))
	if face.dot(f.basis.z) < 0.0:
		f.basis = Basis(-rx, Vector3.UP, face)
	RailView._box(st, f, Vector3(0, 0.12, 0), Vector3(3.0, 0.24, 2.8), Color("#b9b6ae"))  # slab
	RailView._box(st, f, Vector3(0, 1.45, 0), Vector3(2.4, 2.5, 2.4), CASE)
	RailView._box(st, f, Vector3(0, 2.78, -0.1), Vector3(2.6, 0.08, 2.8), Color("#7d817f"))
	RailView._box(st, f, Vector3(0.4, 1.25, 1.21), Vector3(0.9, 2.0, 0.03), Color("#7f8381"))  # door
	RailView._box(st, f, Vector3(-0.75, 1.9, 1.22), Vector3(0.4, 0.25, 0.02), Color("#3a3e3d"))  # vent


## The round yellow advance warning sign: a black X and R R.
static func _advance(st: SurfaceTool, f: Transform3D) -> void:
	RailView._box(st, f, Vector3(0, 1.1, 0), Vector3(0.07, 2.2, 0.07), POST)
	var c := Vector3(0, 2.05, 0.06)
	_disc(st, f, c - Vector3(0, 0, 0.01), 0.465, SIGN_BACK)
	_disc(st, f, c, 0.455, BLACK)
	_disc(st, f, c + Vector3(0, 0, 0.002), 0.43, YELLOW)
	for tilt: float in [PI * 0.25, -PI * 0.25]:
		var b := f * Transform3D(Basis(Vector3.BACK, tilt), c + Vector3(0, 0, 0.004))
		_face(st, b, Vector3.ZERO, Vector2(0.74, 0.07), BLACK)
	for x: float in [-0.22, 0.22]:
		_face(st, f, c + Vector3(x, 0, 0.005), Vector2(0.1, 0.17), BLACK)


## A flat quad facing +z in frame f.
static func _face(st: SurfaceTool, f: Transform3D, c: Vector3, size: Vector2, col: Color) -> void:
	var u := Vector3(size.x * 0.5, 0, 0)
	var v := Vector3(0, size.y * 0.5, 0)
	RailView._quad(st, f * (c - u - v), f * (c + u - v), f * (c + u + v), f * (c - u + v), col)


static func _tri(st: SurfaceTool, f: Transform3D, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for q in [a, b, c]:
		st.set_color(col)
		st.add_vertex(f * (q as Vector3))


## A round disc facing +z in frame f.
static func _disc(st: SurfaceTool, f: Transform3D, c: Vector3, r: float, col: Color) -> void:
	var n := 18
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		_tri(st, f, c, c + Vector3(cos(a0), sin(a0), 0) * r, c + Vector3(cos(a1), sin(a1), 0) * r, col)
