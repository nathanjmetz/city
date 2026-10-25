class_name LotAlerts
extends Node3D
## Little "no power" and "no water" badges over lots, like the problem icons
## Cities: Skylines 2 floats over buildings. Buildings that lack a utility
## always show one; empty zoned lots show theirs while `show_empty` is on
## (the Zoning or Services drawer is open).
##
## Badges that would overlap on screen merge into one with a count, the way
## map apps and city builders cluster markers: up close every house has its
## own, from across town a street shares one, and from the county view the
## whole town is a badge or two. At most MAX_BADGES show at once (the
## biggest groups), so a dry town never draws a pink smear over the roofs
## (look check, 2026-10-25).

const HEIGHT := 14.0
const SIZE := 0.0005  # badges keep the same size on screen, like CS2's icons
## Badges nearer than this on screen (pixels at 900 px tall) share one.
const MERGE_PX := 40.0
const MAX_BADGES := 40
## Within NEAR_M of the camera badges merge at MERGE_PX; farther, the
## distance grows with it, up to FAR_MERGE times as far.
const NEAR_M := 300.0
const FAR_MERGE := 5.0
## How often the groups are redone while the camera moves, in seconds.
const REGROUP_S := 0.1

var sim: CitySim
var show_empty := false:
	set(v):
		if v != show_empty:
			show_empty = v
			_dirty = true

var _tex := {}
var _pool := []
var _dirty := true
var _alerts := []  # [world point, "power" | "water"]
var _seen := Transform3D()  # the camera when the groups were last made
var _seen_size := Vector2.ZERO
var _since := 0.0
var _regroup := true


func setup(s: CitySim) -> void:
	sim = s
	for sig in [sim.lots_changed, sim.buildings_changed, sim.stats_changed, sim.zones_changed]:
		sig.connect(func(): _dirty = true)


func _ready() -> void:
	_tex["power"] = _badge("power")
	_tex["water"] = _badge("water")


func _process(delta: float) -> void:
	if _dirty:
		_dirty = false
		_alerts = wanted(sim, show_empty)
		_regroup = true
	var cam := get_viewport().get_camera_3d()
	var size := get_viewport().get_visible_rect().size
	_since += delta
	if cam != null and (cam.global_transform != _seen or size != _seen_size) and _since >= REGROUP_S:
		_regroup = true
	if not _regroup:
		return
	_regroup = false
	_since = 0.0
	if cam != null:
		_seen = cam.global_transform
		_seen_size = size
	_show(group(_alerts, cam, size))


## Every badge the town needs: [world point, "power" | "water"], one per
## lot (power first, as nothing runs without it), in lot order.
static func wanted(s: CitySim, empty_too: bool) -> Array:
	var out := []
	if not s.require_utilities:
		return out
	var keys := s.lots.keys()
	keys.sort()
	for key in keys:
		var built := s.buildings.has(key)
		if not built and (not empty_too or s.zones.zone_at(s.lots[key].zone_pt) == ZoneMap.Zone.NONE):
			continue
		var served: Dictionary = s.services.served.get(key, {})
		for u in ["power", "water"]:
			if not served.get(u, false):
				out.append([Terrain.lift(s.lots[key].pos + Vector3(0, HEIGHT, 0)), u])
				break
	return out


## Badges merged where they'd overlap on screen: [[world point, kind,
## count], ...], biggest groups first, at most MAX_BADGES. A group sits at
## the middle of its lots and shows power if any of them lacks it. Off
## screen and behind the camera are left out. Without a camera (headless)
## nothing merges, but the cap still holds.
static func group(alerts: Array, cam: Camera3D, size: Vector2) -> Array:
	var groups := []
	if cam == null:
		for a in alerts.slice(0, MAX_BADGES):
			groups.append([a[0], a[1], 1])
		return groups
	var px := maxf(size.y, 1.0) / 900.0
	var cell_px := MERGE_PX * FAR_MERGE * px  # the widest a group reaches
	var eye := cam.global_position
	var cells := {}  # screen cell -> indexes into `at`
	var at := []  # [screen point of the group's first badge, world sum, count, power?]
	for a in alerts:
		var p: Vector3 = a[0]
		if cam.is_position_behind(p):
			continue
		var q := cam.unproject_position(p)
		# Farther off, a group covers more of the screen: a street at 1 km,
		# the whole town from the county view.
		var merge := MERGE_PX * px * clampf(eye.distance_to(p) / NEAR_M, 1.0, FAR_MERGE)
		if q.x < -merge or q.y < -merge or q.x > size.x + merge or q.y > size.y + merge:
			continue
		var cell := Vector2i(floori(q.x / cell_px), floori(q.y / cell_px))
		var hit := -1
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for gi in cells.get(cell + Vector2i(dx, dy), []):
					if hit == -1 and (at[gi][0] as Vector2).distance_to(q) < merge:
						hit = gi
		if hit == -1:
			hit = at.size()
			at.append([q, Vector3.ZERO, 0, false])
			if not cells.has(cell):
				cells[cell] = []
			cells[cell].append(hit)
		at[hit][1] += p
		at[hit][2] += 1
		at[hit][3] = at[hit][3] or a[1] == "power"
	for g in at:
		groups.append([g[1] / float(g[2]), "power" if g[3] else "water", g[2]])
	groups.sort_custom(func(x, y): return x[2] > y[2])
	return groups.slice(0, MAX_BADGES)


func _show(groups: Array) -> void:
	while _pool.size() < groups.size():
		var sp := Sprite3D.new()
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.pixel_size = SIZE
		sp.fixed_size = true
		sp.no_depth_test = true
		sp.render_priority = 2
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# How many lots a merged badge stands for, at its top right.
		var n := Label3D.new()
		n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		n.fixed_size = true
		n.pixel_size = SIZE
		n.font_size = 34
		n.outline_size = 12
		n.outline_modulate = Brand.SURFACE
		n.modulate = Brand.INK
		n.font = Brand.font("ui", 700)
		n.offset = Vector2(34, 28)
		n.no_depth_test = true
		n.render_priority = 3
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.add_child(n)
		add_child(sp)
		_pool.append(sp)
	for i in _pool.size():
		var sp: Sprite3D = _pool[i]
		sp.visible = i < groups.size()
		if sp.visible:
			sp.position = groups[i][0]
			sp.texture = _tex[groups[i][1]]
			var n: Label3D = sp.get_child(0)
			var count: int = groups[i][2]
			n.visible = count > 1
			n.text = str(count) if count < 100 else "99+"


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
