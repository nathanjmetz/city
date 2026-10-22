class_name LotAlerts
extends Node3D
## Little "no power" and "no water" badges over lots, like the problem icons
## Cities: Skylines 2 floats over buildings. Buildings that lack a utility
## always show one; empty zoned lots show theirs while `show_empty` is on
## (the Zoning or Services drawer is open).

const HEIGHT := 14.0
const SIZE := 0.0005  # badges keep the same size on screen, like CS2's icons

var sim: CitySim
var show_empty := false:
	set(v):
		if v != show_empty:
			show_empty = v
			_dirty = true

var _tex := {}
var _pool := []
var _dirty := true


func setup(s: CitySim) -> void:
	sim = s
	for sig in [sim.lots_changed, sim.buildings_changed, sim.stats_changed, sim.zones_changed]:
		sig.connect(func(): _dirty = true)


func _ready() -> void:
	_tex["power"] = _badge("power")
	_tex["water"] = _badge("water")


func _process(_delta: float) -> void:
	if not _dirty:
		return
	_dirty = false
	var wanted := []
	if sim.require_utilities:
		var keys := sim.lots.keys()
		keys.sort()
		for key in keys:
			var built := sim.buildings.has(key)
			if not built and (not show_empty or sim.zones.zone_at(sim.lots[key].zone_pt) == ZoneMap.Zone.NONE):
				continue
			var s: Dictionary = sim.services.served.get(key, {})
			# One badge per lot: power first, as nothing runs without it.
			for u in ["power", "water"]:
				if not s.get(u, false):
					wanted.append([sim.lots[key].pos + Vector3(0, HEIGHT, 0), u])
					break
	while _pool.size() < wanted.size():
		var sp := Sprite3D.new()
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.pixel_size = SIZE
		sp.fixed_size = true
		sp.no_depth_test = true
		sp.render_priority = 2
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sp)
		_pool.append(sp)
	for i in _pool.size():
		var sp: Sprite3D = _pool[i]
		sp.visible = i < wanted.size()
		if sp.visible:
			sp.position = wanted[i][0]
			sp.texture = _tex[wanted[i][1]]


## A round badge with a lightning bolt or a water drop, drawn in code.
static func _badge(kind: String) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var bolt := PackedVector2Array([Vector2(36, 10), Vector2(20, 36), Vector2(31, 36), Vector2(26, 54),
		Vector2(44, 26), Vector2(33, 26), Vector2(38, 10)])
	var glyph := Brand.WARNING if kind == "power" else Color("#5fb8e8")
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var r := p.distance_to(Vector2(32, 32))
			if r > 31.0:
				continue
			var c: Color = Brand.CRITICAL if r > 27.0 else Brand.SURFACE
			var inside := false
			if kind == "power":
				inside = Geometry2D.is_point_in_polygon(p, bolt)
			else:
				# A drop: a circle at the bottom running up to a point.
				var d := p - Vector2(32, 38)
				inside = d.length() < 11.0 or (p.y > 12.0 and p.y < 38.0
					and absf(p.x - 32.0) < 11.0 * (p.y - 12.0) / 26.0)
			if inside:
				c = glyph
			c.a = clampf(31.5 - r, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
