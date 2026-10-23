class_name PlacementHints
extends Node3D
## Shows what a placement would do before the player commits, the way Cities:
## Skylines 2 shows the wind when a polluting tool is picked (Brawn,
## 2026-10-23: he zoned industry upwind of his town and only found out once
## the smoke rolled in).
##
## While a polluting tool is in hand (industry zoning, an oil, quarry or
## logging company, a power yard, the landfill or recycling), arrows drift
## across the map on the prevailing wind, and the cursor carries the smoke
## plume and noise rings that one source of that kind would make, worked out
## with the same plume and noise sums as the Smoke and Noise views
## (Pollution), with a count of the homes it would reach. While zoning homes
## or shops it says how smoky and loud the spot under the cursor already is.
##
## Nothing here touches the sim: the plume is painted once per kind of
## source, homes are counted a few times a second only while the cursor
## moves, and it all goes away with the tool.

## Smoke under this isn't drawn or counted, ug/m3 (where the Smoke view's
## colour starts).
const SMOKE_SEEN := 1.0
## The plume picture: pixels across, and rows painted a frame.
const PLUME_RES := 96
const PLUME_ROWS_PER_FRAME := 24
## Wind arrows: a grid this many across, drifting this share of their
## spacing a second.
const ARROWS := 7
const ARROW_SPEED := 0.22
## Homes are recounted at most this often (seconds), and only once the
## cursor has moved this far (metres).
const COUNT_EVERY := 0.2
const COUNT_MOVE := 8.0
## Homes are found through buckets this many metres across, rebuilt at most
## this often (seconds) while hints show.
const BUCKET := 200.0
const INDEX_EVERY := 5.0
const INDEX_PER_FRAME := 4000

## What each kind of source is called in the hint.
const NAMES := {
	"factory": "A factory", "oil": "An oil company", "ore": "A quarry", "forest": "A logging company",
	"landfill": "The landfill", "recycling_1": "A recycling center", "recycling_2": "A recycling center",
	"recycling_3": "A recycling center", "power_coal": "A coal plant", "power_gas": "A gas plant",
	"power_wind": "A wind farm",
}

var sim: CitySim
var cam: CityCamera
## Returns what the tool in hand wants shown: {} for nothing, {"source":
## kind of Balance.POLLUTION_SOURCES}, {"spot": true} for a readout of the
## pollution already there, {"wind": true} for just the arrows.
var want := Callable()

var _key := ""
var _source := ""
var _spot := false
var _hover := Vector3.INF
var _arrows := MultiMeshInstance3D.new()
var _arrow_y := {}
var _arrow_step := 0.0
var _plume := MeshInstance3D.new()
var _plume_mat := StandardMaterial3D.new()
var _plume_img: Image
var _plume_row := -1
var _plume_half := 0.0
var _plume_at := Vector3.INF
var _rings := MeshInstance3D.new()
var _ring_width := 0.0
## A small card beside the cursor (2D, so it stays sharp and above the
## lot badges).
var _layer := CanvasLayer.new()
var _card := PanelContainer.new()
var _text := Label.new()
var _counted_at := Vector3.INF
var _count_wait := 0.0
var _counts := {}
var _homes := {}
var _index_keys := []
var _index_i := -1
var _fresh := {}
var _homes_ready := false
var _index_age := INF
var _time := 0.0


func setup(s: CitySim, camera: CityCamera, wanted: Callable) -> void:
	sim = s
	cam = camera
	want = wanted


func _ready() -> void:
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.vertex_color_use_as_albedo = true
	line_mat.no_depth_test = true
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	line_mat.disable_fog = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _arrow_mesh()
	mm.instance_count = ARROWS * ARROWS
	_arrows.multimesh = mm
	_arrows.material_override = line_mat
	_rings.material_override = line_mat
	_plume_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plume_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plume_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_plume_mat.no_depth_test = true
	_plume_mat.disable_fog = true
	_plume.material_override = _plume_mat
	for mi in [_plume, _rings, _arrows]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
	_layer.layer = 5
	_card.add_theme_stylebox_override("panel", UiStyle.panel())
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	_text.add_theme_font_size_override("font_size", 13)
	_text.add_theme_color_override("font_color", UiStyle.TEXT)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_text)
	_layer.add_child(_card)
	add_child(_layer)
	sim.buildings_changed.connect(func(): _index_age = INF)
	sim.lots_changed.connect(func(): _index_age = INF)


func _process(delta: float) -> void:
	var w: Dictionary = want.call() if want.is_valid() else {}
	var key := str(w)
	if key != _key:
		_key = key
		_use(w)
	if w.is_empty():
		return
	_time += delta
	_place_arrows()
	var hit = cam.mouse_ground_point()
	if hit != null:
		_hover = Vector3(hit.x, Terrain.ground_y(hit.x, hit.z), hit.z)
	if _source != "":
		_paint_rows()
		_index_age += delta
		if _index_age > INDEX_EVERY and _index_i < 0:
			_start_index()
		_build_index()
	_place_card()
	if _hover == Vector3.INF or not (_source != "" or _spot):
		_card.visible = _hover != Vector3.INF
		_text.text = _wind_line()
		return
	_card.visible = true
	if _source != "":
		_follow()
	_count_wait -= delta
	if _count_wait <= 0.0 and _hover.distance_to(_counted_at) > COUNT_MOVE:
		_count_wait = COUNT_EVERY
		_counted_at = _hover
		_text.text = _source_text() if _source != "" else _spot_text()
		_card.reset_size()


## Shows (or hides) everything for what the tool wants.
func _use(w: Dictionary) -> void:
	_source = str(w.get("source", ""))
	if not Balance.POLLUTION_SOURCES.has(_source):
		_source = ""
	_spot = bool(w.get("spot", false))
	_arrows.visible = not w.is_empty()
	_card.visible = false
	_text.text = _wind_line()
	_plume.visible = false
	_rings.visible = false
	_counted_at = Vector3.INF
	_count_wait = 0.0
	_arrow_y.clear()
	if _source != "":
		_start_plume()
		_ring_width = 0.0


## Keeps the card just below and right of the mouse, on screen.
func _place_card() -> void:
	var vp := get_viewport()
	var m := vp.get_mouse_position()
	var size := vp.get_visible_rect().size
	var c := _card.size
	_card.position = Vector2(clampf(m.x + 22.0, 0.0, size.x - c.x), clampf(m.y + 22.0, 0.0, size.y - c.y))


# --- Wind arrows ----------------------------------------------------------------

## A flat chevron a metre long, pointing along -z.
static func _arrow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0, 0, -0.5)
	var pts := [tip, Vector3(-0.32, 0, 0.1), Vector3(-0.18, 0, 0.1),
		tip, Vector3(-0.18, 0, 0.1), Vector3(0, 0, -0.22),
		tip, Vector3(0.18, 0, 0.1), Vector3(0.32, 0, 0.1),
		tip, Vector3(0, 0, -0.22), Vector3(0.18, 0, 0.1),
		Vector3(-0.04, 0, -0.2), Vector3(-0.04, 0, 0.5), Vector3(0.04, 0, 0.5),
		Vector3(-0.04, 0, -0.2), Vector3(0.04, 0, 0.5), Vector3(0.04, 0, -0.2)]
	for p in pts:
		st.set_color(Color.WHITE)
		st.set_normal(Vector3.UP)
		st.add_vertex(p)
	return st.commit()


## A grid of arrows around the camera's focus, fixed to the land and drifting
## downwind, fading at the edges.
func _place_arrows() -> void:
	var c := cam.focus()
	var dist := cam.camera.global_position.distance_to(c)
	var step := clampf(dist * 0.32, 45.0, 1600.0)
	if absf(step - _arrow_step) > _arrow_step * 0.1:
		_arrow_step = step
		_arrow_y.clear()
	step = _arrow_step
	var wv := Pollution.WIND
	var u := Vector3(wv.x, 0.0, wv.y)
	var v := Vector3(-wv.y, 0.0, wv.x)
	var cu := c.dot(u)
	var cv := c.dot(v)
	var base_u := floorf(cu / step)
	var base_v := floorf(cv / step)
	var phase := fmod(_time * ARROW_SPEED, 1.0) * step
	var basis := Basis.looking_at(u, Vector3.UP).scaled(Vector3.ONE * step * 0.32)
	var mm := _arrows.multimesh
	var half := ARROWS / 2
	var i := 0
	for a in ARROWS:
		for b in ARROWS:
			var cell := Vector2i(int(base_u) + a - half, int(base_v) + b - half)
			# Every other row starts half a step on, so they don't line up.
			var along := cell.x * step + phase + (step * 0.5 if posmod(cell.y, 2) == 1 else 0.0)
			var side := cell.y * step
			var p := u * along + v * side
			if not _arrow_y.has(cell):
				_arrow_y[cell] = Terrain.ground_y(p.x, p.z)
			p.y = _arrow_y[cell] + 2.0
			var off := Vector2(along - cu, side - cv).length() / (step * (half + 0.5))
			var alpha := 0.75 * (1.0 - smoothstep(0.55, 1.0, off))
			mm.set_instance_transform(i, Transform3D(basis, p))
			mm.set_instance_color(i, Color(1.0, 1.0, 1.0, alpha))
			i += 1


func _wind_line() -> String:
	var words := Pollution.wind_words()
	return "Wind from the %s: smoke drifts %s" % words


# --- One source's footprint -----------------------------------------------------

func _start_plume() -> void:
	var spec: Dictionary = Balance.POLLUTION_SOURCES[_source]
	var q := float(spec.smoke)
	_plume_half = clampf(Pollution.smoke_reach(maxf(q, Pollution.SMOKE_FLOOR)) + 150.0, 400.0, 3000.0)
	_plume_img = Image.create(PLUME_RES, PLUME_RES, false, Image.FORMAT_RGBA8)
	_plume_row = 0 if q >= SMOKE_SEEN else -1
	_plume_at = Vector3.INF
	# A square with uv (0, 0) at its north-west corner (-x, -z), like the image.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := _plume_half
	for c in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
		st.set_uv(c)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(-h + c.x * h * 2.0, 0.0, -h + c.y * h * 2.0))
	_plume.mesh = st.commit()
	_plume_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_rings(float(spec.noise))


## Paints the plume a few rows a frame, centred on the source; it is the
## same wherever the source goes, since the wind is.
func _paint_rows() -> void:
	if _plume_row < 0:
		return
	var q := float(Balance.POLLUTION_SOURCES[_source].smoke)
	var ramp: Array = InfoView.RAMPS[InfoView.Mode.SMOKE]
	var scale: Array = InfoView.POLLUTION_SCALE[InfoView.Mode.SMOKE]
	var px := _plume_half * 2.0 / PLUME_RES
	var w := Pollution.WIND
	var end := mini(_plume_row + PLUME_ROWS_PER_FRAME, PLUME_RES)
	for y in range(_plume_row, end):
		for x in PLUME_RES:
			var d := Vector2(-_plume_half + (x + 0.5) * px, -_plume_half + (y + 0.5) * px)
			var s := Pollution._plume(q, d, w)
			if s < SMOKE_SEEN:
				_plume_img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var t := clampf((s - scale[0]) / (scale[1] - scale[0]), 0.0, 1.0)
			var col := (ramp[1] as Color).lerp(ramp[2], sqrt(t))
			col.a *= smoothstep(SMOKE_SEEN, SMOKE_SEEN * 2.0, s)
			_plume_img.set_pixel(x, y, col)
	_plume_row = end
	if _plume_row >= PLUME_RES:
		_plume_row = -1
		_plume_mat.albedo_texture = ImageTexture.create_from_image(_plume_img)
		_plume.visible = true


## Noise rings around the source: where it falls to 55 dBA (EPA's level for
## healthy outdoor living, where home prices start to slip) and to the level
## that counts a home as hurt (Balance.HURT_NOISE_DB).
func _build_rings(level: float) -> void:
	var dist := cam.camera.global_position.distance_to(cam.focus())
	_ring_width = clampf(dist * 0.004, 1.5, 30.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for ring in [[Balance.NOISE_QUIET_DB, Brand.WARNING], [Balance.HURT_NOISE_DB, Brand.CRITICAL]]:
		var r := _noise_radius(level, ring[0])
		if r < 1.0:
			continue
		any = true
		var col: Color = ring[1]
		var n := 64
		for k in n:
			var a0 := TAU * k / n
			var a1 := TAU * (k + 1) / n
			var o0 := Vector3(cos(a0), 0, sin(a0))
			var o1 := Vector3(cos(a1), 0, sin(a1))
			var hw := _ring_width * 0.5
			var quad := [o0 * (r - hw), o0 * (r + hw), o1 * (r + hw), o0 * (r - hw), o1 * (r + hw), o1 * (r - hw)]
			for p in quad:
				st.set_color(col)
				st.set_normal(Vector3.UP)
				st.add_vertex(p)
	_rings.mesh = st.commit() if any else null
	_rings.visible = any


## How far from a point source of `level` dBA (at 15 m) it is down to
## `target`, metres (Pollution's spreading, 6 dB per doubling).
static func _noise_radius(level: float, target: float) -> float:
	if level <= target:
		return 0.0
	var r := Pollution.REF_M * pow(10.0, (level - target) / 20.0)
	# A little more is lost to air and soft ground far out.
	for i in 3:
		r = Pollution.REF_M * pow(10.0, (level - target) / 20.0) * exp(-r / 4000.0)
	return r


## Keeps the plume and rings under the cursor.
func _follow() -> void:
	if _hover == Vector3.INF:
		return
	var dist := cam.camera.global_position.distance_to(cam.focus())
	if absf(clampf(dist * 0.004, 1.5, 30.0) - _ring_width) > _ring_width * 0.25:
		_build_rings(float(Balance.POLLUTION_SOURCES[_source].noise))
	_plume.position = _hover + Vector3(0, 1.5, 0)
	_rings.position = _hover + Vector3(0, 1.8, 0)
	_plume_at = _hover


## What the source under the cursor would do to the homes around it.
func _source_text() -> String:
	var spec: Dictionary = Balance.POLLUTION_SOURCES[_source]
	var c := count_homes(_hover, float(spec.smoke), float(spec.noise))
	var lines := [_wind_line()]
	var who: String = NAMES.get(_source, "This")
	if not _homes_ready:
		lines.append("%s here: counting homes nearby..." % who)
	elif c.smoke == 0 and c.noise == 0:
		lines.append("%s here: no homes in its smoke or noise." % who)
	else:
		var parts := []
		if c.smoke > 0:
			parts.append("smoke over %d home%s%s" % [c.smoke, "" if c.smoke == 1 else "s",
				" (%d unhealthy)" % c.unhealthy if c.unhealthy > 0 else ""])
		if c.noise > 0:
			parts.append("noise at %d home%s" % [c.noise, "" if c.noise == 1 else "s"])
		lines.append("%s here: %s." % [who, ", ".join(parts)])
		if _source == "factory":
			lines.append("Each factory adds its own; a whole industrial area adds up.")
	return "\n".join(lines)


## Homes a source at `p` would reach: {smoke (at least SMOKE_SEEN),
## unhealthy (at least Balance.HURT_SMOKE), noise (at least 55 dBA)}.
func count_homes(p: Vector3, q: float, level: float) -> Dictionary:
	var out := {"smoke": 0, "unhealthy": 0, "noise": 0}
	var w := Pollution.WIND
	var nr := _noise_radius(level, Balance.NOISE_QUIET_DB)
	var sr := Pollution.smoke_reach(maxf(q, Pollution.SMOKE_FLOOR)) if q >= SMOKE_SEEN else 0.0
	var box := Rect2(Vector2(p.x, p.z), Vector2.ZERO).grow(maxf(nr, 160.0))
	if sr > 0.0:
		var tail := Vector2(p.x, p.z) + w * sr
		box = box.expand(tail).grow(Balance.SMOKE_WIDTH + Balance.SMOKE_SPREAD * sr)
	var origin := Vector2(p.x, p.z)
	for bx in range(floori(box.position.x / BUCKET), floori(box.end.x / BUCKET) + 1):
		for bz in range(floori(box.position.y / BUCKET), floori(box.end.y / BUCKET) + 1):
			for h in _homes.get(Vector2i(bx, bz), []):
				var d: Vector2 = h - origin
				if not box.has_point(h):
					continue
				if d.length() < nr:
					out.noise += 1
				if sr > 0.0:
					var s := Pollution._plume(q, d, w)
					if s >= SMOKE_SEEN:
						out.smoke += 1
						if s >= Balance.HURT_SMOKE:
							out.unhealthy += 1
	return out


func _start_index() -> void:
	_index_keys = sim.lots.keys()
	_index_i = 0
	_index_age = 0.0


## Buckets the town's homes (and lots zoned for them) a few thousand a frame.
func _build_index() -> void:
	if _index_i < 0:
		return
	if _index_i == 0:
		_fresh = {}
	var fresh := _fresh
	var end := mini(_index_i + INDEX_PER_FRAME, _index_keys.size())
	for i in range(_index_i, end):
		var key = _index_keys[i]
		if not sim.lots.has(key):
			continue
		# Built homes, and lots zoned for homes that will fill in.
		var b: Dictionary = sim.buildings.get(key, {})
		var zone := int(b.zone) if not b.is_empty() else sim.zones.zone_at(sim.lots[key].zone_pt)
		if zone != ZoneMap.Zone.RESIDENTIAL:
			continue
		var p: Vector3 = sim.lots[key].pos
		var bk := Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))
		if not fresh.has(bk):
			fresh[bk] = []
		fresh[bk].append(Vector2(p.x, p.z))
	_index_i = end
	if _index_i >= _index_keys.size():
		_homes = fresh
		_homes_ready = true
		_fresh = {}
		_index_keys = []
		_index_i = -1
		_counted_at = Vector3.INF


# --- What's already here --------------------------------------------------------

## The smoke and noise already at the cursor, and who makes them.
func _spot_text() -> String:
	var pol := sim.pollution
	var lines := [_wind_line()]
	var s := pol.sample(_hover)
	var parts := []
	if s.smoke >= SMOKE_SEEN:
		parts.append("smoke %.1f µg/m³%s" % [s.smoke, _top(s, "smoke")])
	if s.noise >= Balance.NOISE_QUIET_DB:
		parts.append("noise %d dBA%s" % [roundi(s.noise), _top(s, "noise")])
	if s.ground >= Balance.HURT_GROUND:
		parts.append("dirty ground%s" % _top(s, "ground"))
	lines.append("Here: " + (", ".join(parts) if not parts.is_empty() else "clean air and quiet") + ".")
	if s.smoke >= Balance.HURT_SMOKE or s.noise >= Balance.HURT_NOISE_DB:
		lines.append("Homes here would be hurt by it.")
	return "\n".join(lines)


func _top(s: Dictionary, kind: String) -> String:
	var by: Array = s.by.get(kind, [])
	if by.is_empty() or not sim.pollution.sources.has(by[0][0]):
		return ""
	return " (%s)" % sim.pollution.sources[by[0][0]].name
