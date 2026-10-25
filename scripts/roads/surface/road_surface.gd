class_name RoadSurface
extends RefCounted
## One road view's ageing road materials (RoadShaders) and the wear map they
## read: each StreetAge square's paving date, packed in a small texture
## (RoadWear.map_image). Each view has its own, because a neighbor's town
## has its own streets and ages. Kept up to date by tick(): the date every
## half second, the map when the streets or the month change.
##
## Cost: one RGBA8 texel per 40 m square of the town (a 4 km town is 100 x
## 100, 40 KB), redone at most once a game month.

const TICK := 0.5

var _shaders := {}      # name -> Shader, shared by this view's materials
var _mats := []         # every material made here, to set the date on
var _pave := {}         # road type -> its pavement material
var _tex: ImageTexture
var _rect := Vector4.ZERO
var _sig := []
var _wait := 0.0
var _has_map := 0.0
var detail := 1.0

static var _code := {}  # name -> Shader, shared by every view


## Puts this view's materials in a RoadView's material table: the generic
## asphalt (junction pads, corners, ramp merges), the lines, chip seal and
## gravel pads, and "_pave", which makes each road type's own pavement.
func install(mats: Dictionary) -> void:
	mats["asphalt"] = _make("asphalt", {})
	mats["yellow"] = _make("paint", {"paint": RoadStyle.MARKING_YELLOW})
	mats["white"] = _make("paint", {"paint": RoadStyle.MARKING_WHITE})
	mats["bus"] = _make("paint", {"paint": Color(0.56, 0.17, 0.14)})
	mats["chip seal"] = _make("chip", {})
	mats["gravel road"] = _make("gravel", {"width": 0.0})
	mats["_pave"] = pave


## The pavement for one road type, with its width, wheel paths and traffic.
func pave(type: int) -> Material:
	if _pave.has(type):
		return _pave[type]
	var name := ""
	match RoadWear.kind(type):
		RoadWear.Kind.ASPHALT: name = "asphalt"
		RoadWear.Kind.CHIP: name = "chip"
		RoadWear.Kind.GRAVEL: name = "gravel"
		RoadWear.Kind.CONCRETE: name = "concrete"
		RoadWear.Kind.DIRT: return null
		RoadWear.Kind.BRICK: return null
	var l := RoadWear.lanes(type)
	var m := _make(name, {"width": float(RoadStyle.TYPES[type].width), "lane_start": float(l.start),
		"lane_w": float(l.width), "lane_count": float(l.count), "mirror": 1.0 if l.mirror else 0.0,
		"fatigue": RoadWear.fatigue(type), "traffic": RoadWear.traffic(type),
		"edge_break": 1.0 if RoadWear.breaks_at_edge(type) else 0.0})
	_pave[type] = m
	return m


## The date, the town's purse and, when they changed, the wear map.
## `view` is the RoadView (its place in the region), `sim` its town or null.
func tick(view: Node3D, sim, delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = TICK
	var now := 1.0
	var upkeep := 1.0
	if sim != null:
		now = Seasons.months(int(sim.tick_count)) / 12.0
		upkeep = 0.3 if sim.economy.money < 0 else 1.0
		var sa: StreetAge = sim.street_age
		var sig := [sim.network.revision, int(sim.tick_count) / Seasons.TICKS_PER_DAY, sa.paved.size()]
		if sig != _sig:
			_sig = sig
			rebuild_map(sa.paved)
	var origin := Vector2.ZERO
	if view.is_inside_tree():
		origin = Vector2(view.global_position.x, view.global_position.z)
	for m in _mats:
		m.set_shader_parameter("now_years", now)
		m.set_shader_parameter("upkeep", upkeep)
		m.set_shader_parameter("origin", origin)
		m.set_shader_parameter("detail", detail)


## Packs the town's paving dates into the wear map.
func rebuild_map(paved: Dictionary) -> void:
	var t := Perf.now()
	_has_map = 1.0
	var built := RoadWear.map_image(paved)
	if built.is_empty():
		_rect = Vector4.ZERO
	else:
		var img: Image = built.image
		if _tex != null and _tex.get_width() == img.get_width() and _tex.get_height() == img.get_height():
			_tex.update(img)
		else:
			_tex = ImageTexture.create_from_image(img)
		_rect = built.rect
	for m in _mats:
		_bind(m)
	Perf.add("frame.road_wear", t)


func _bind(m: ShaderMaterial) -> void:
	m.set_shader_parameter("has_map", _has_map)
	m.set_shader_parameter("map_rect", _rect)
	m.set_shader_parameter("cell", Balance.STREET_AGE_CELL)
	if _tex != null:
		m.set_shader_parameter("wear_map", _tex)


func _make(name: String, params: Dictionary) -> ShaderMaterial:
	if not _code.has(name):
		var s := Shader.new()
		match name:
			"asphalt": s.code = RoadShaders.asphalt()
			"paint": s.code = RoadShaders.paint()
			"chip": s.code = RoadShaders.chip()
			"gravel": s.code = RoadShaders.gravel()
			"concrete": s.code = RoadShaders.concrete()
		_code[name] = s
	var m := ShaderMaterial.new()
	m.shader = _code[name]
	Surfaces.asphalt()  # makes the shared noise textures
	m.set_shader_parameter("noise_soft", Surfaces._soft)
	m.set_shader_parameter("noise_grain", Surfaces._grain)
	for k in params:
		m.set_shader_parameter(k, params[k])
	_bind(m)
	_mats.append(m)
	return m
