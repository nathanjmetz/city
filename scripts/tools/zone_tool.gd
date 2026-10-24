class_name ZoneTool
extends Node3D
## Zones street frontage, the way real towns zone: click a street side to
## zone that whole block face (Shift: both sides), or drag along a street to
## zone just the stretch you drag over (a few shops, not a whole block), at
## least a lot long. The game then surveys the lots itself.
## Three tool types, like CS2's (Tab steps through them):
## - Street: a click zones the block face, a drag just that stretch.
## - Brush: a round brush for odd spots; [ and ] (or the size meter) size it.
## - Smart: zones each street side the way you have zoned that kind of street
##   before, matched to what's across the street and around it (a planner
##   extends the zoning a town already has; Euclidean zoning maps run along
##   street types: shops on the avenues, homes on the local streets).

signal zone_changed(zone: int)
signal hint_changed(text: String)
signal mode_changed(mode: int)

enum Mode { STREET, BRUSH, SMART }
const MODE_NAMES := ["Street", "Brush", "Smart"]
const HABITS_PATH := "user://zone_habits.cfg"
## How much each clue counts in a smart guess (habits add up to 1).
const ACROSS_WEIGHT := 0.8
const AROUND_WEIGHT := 0.5
const AROUND_RADIUS := 120.0
const AROUND_STEP := 30.0

const OFF := -1
const MIN_RADIUS := 4.0
const MAX_RADIUS := 48.0
## A drag zones at least one lot's frontage, and runs on to the corner when
## it stops this near one.
const MIN_RUN := 20.0
const SNAP_END := 12.0
## How far (pixels) the mouse moves before a click becomes a drag.
const DRAG_PX := 8.0

var sim: CitySim
var cam: CityCamera
var zone_view: ZoneView
var zone := OFF
var radius := 14.0
var mode := Mode.STREET
## The round brush (read-only: mode is the switch).
var brush: bool:
	get: return mode == Mode.BRUSH
## How this player has zoned each street type: {type: {zone: count}}. Kept
## on this computer (it's how you like to zone, not part of the town).
var habits := {}
## Smart guesses for this hover or drag, so they don't flicker: "seg:side" -> zone.
var _guesses := {}
var _smart_sides := {}  # "seg:side" -> [seg, side] a smart drag went over

var _painting := false
var _last_paint := Vector3.INF
var _hover := []      # [seg, side] under the mouse, or []
var _press := Vector2.ZERO  # where the button went down
var _dragging := false
var _spans := {}      # "seg:side" -> [seg, side, from, to] dragged over
var _held := false    # this drag sent zoning whose lots wait for its end
var _ring := MeshInstance3D.new()
var _ring_mat := StandardMaterial3D.new()


func setup(s: CitySim, camera: CityCamera, view: ZoneView) -> void:
	sim = s
	cam = camera
	zone_view = view


func _ready() -> void:
	_load_habits()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.no_depth_test = true
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_update_ring()


func set_zone(z: int) -> void:
	zone = z
	_stop()
	zone_view.show_all = zone != OFF
	zone_view.preview_zone = maxi(zone, 0)
	if zone == OFF:
		_hover = []
		zone_view.preview = []
	_update_ring()
	zone_changed.emit(zone)
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	# Shift + a number opens a bottom bar menu instead (Hud.hotkey_category).
	if event is InputEventKey and event.pressed and not event.echo and not (event as InputEventKey).shift_pressed:
		match KeyBinds.action(event as InputEventKey, ["homes", "shops", "industry", "dezone", "brush", "smaller", "bigger"]):
			"homes": set_zone(ZoneMap.Zone.RESIDENTIAL)
			"shops": set_zone(ZoneMap.Zone.COMMERCIAL)
			"industry": set_zone(ZoneMap.Zone.INDUSTRIAL)
			"dezone": set_zone(ZoneMap.Zone.NONE)
			"brush": if zone != OFF:
				set_mode((mode + 1) % Mode.size())
			"smaller": if zone != OFF: _resize(1.0 / 1.25)
			"bigger": if zone != OFF: _resize(1.25)
	if zone == OFF:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_release()
			_stop()
		_painting = event.pressed and not (event as InputEventMouseButton).alt_pressed
		_last_paint = Vector3.INF
		_spans.clear()
		_smart_sides.clear()
		_dragging = false
		_press = (event as InputEventMouseButton).position
		if _painting and brush:
			_paint()
	elif event is InputEventMouseButton and not event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and not cam.right_dragged:
		set_zone(OFF)


func _process(_delta: float) -> void:
	var hit = cam.mouse_ground_point()
	_ring.visible = zone != OFF and hit != null and brush
	if zone != OFF and not brush:
		_update_hover(hit)
	if zone == OFF or hit == null:
		return
	_ring.position = Vector3(hit.x, Terrain.ground_y(hit.x, hit.z) + 0.4, hit.z)
	if _painting and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_release()
		_stop()
	if _painting and brush:
		_paint()
	elif _painting:
		if not _dragging and get_viewport().get_mouse_position().distance_to(_press) > DRAG_PX:
			_dragging = true
		if _dragging and mode == Mode.SMART:
			_smart_extend()
		elif _dragging:
			_extend(hit)


## A drag along a street: the stretch under the mouse joins this drag's.
func _extend(hit) -> void:
	if _hover.is_empty() or hit == null:
		return
	var s := sim.planner.side_survey(sim.network, _hover[0], _hover[1])
	if s.is_empty():
		return
	var p := Vector2(hit.x, hit.z)
	var at := -1.0
	var best := INF
	for f in s.fronts:
		var d := (f[1] as Vector2).distance_to(p)
		if d < best:
			best = d
			at = f[0]
	var key := "%d:%d" % [_hover[0], _hover[1]]
	var span: Array = _spans.get(key, [_hover[0], _hover[1], at, at])
	span[2] = minf(span[2], at)
	span[3] = maxf(span[3], at)
	_spans[key] = span
	var parts := _runs()
	var shown := parts.duplicate()
	if Input.is_key_pressed(KEY_SHIFT):
		for r in parts:
			shown.append([r[0], -r[1], r[2], r[3]])
	zone_view.preview = shown
	var metres := 0.0
	for r in parts:
		metres += r[3] - r[2]
	var verb: String = "Dezone" if zone == ZoneMap.Zone.NONE else "Zone " + ZoneMap.NAMES[zone]
	hint_changed.emit("%s: %d ft (%d m) of street. Let go to zone it." % [verb, roundi(metres * 3.28084), roundi(metres)])


## The dragged stretches as they'll be zoned: at least a lot long, and on to
## the corner when they stop near one. [[seg, side, from, to], ...]
func _runs() -> Array:
	var out := []
	var keys := _spans.keys()
	keys.sort()
	for key in keys:
		var r: Array = _spans[key]
		var s := sim.planner.side_survey(sim.network, r[0], r[1])
		if s.is_empty():
			continue
		var length: float = s.len
		var a0: float = r[2]
		var a1: float = r[3]
		if a1 - a0 < MIN_RUN:
			var mid := clampf((a0 + a1) * 0.5, MIN_RUN * 0.5, maxf(length - MIN_RUN * 0.5, MIN_RUN * 0.5))
			a0 = mid - MIN_RUN * 0.5
			a1 = mid + MIN_RUN * 0.5
		if a0 < SNAP_END:
			a0 = 0.0
		if a1 > length - SNAP_END:
			a1 = length
		out.append([r[0], r[1], a0, a1])
	return out


## The button came up: a click zones the whole block face, a drag the
## stretches it went over.
func _release() -> void:
	if not _painting or brush:
		return
	var both := Input.is_key_pressed(KEY_SHIFT)
	if mode == Mode.SMART:
		var sides := _smart_sides.values() if _dragging else ([_hover] if not _hover.is_empty() else [])
		for sd in _with_across(sides, both):
			_held = sim.apply({"type": "zone_frontage", "seg": sd[0], "side": sd[1], "zone": guess(sd[0], sd[1]),
				"hold": true}) or _held
		_smart_sides.clear()
		_guesses.clear()
		_dragging = false
		_hover = []
		_update_hint()
		return
	if _dragging:
		for r in _runs():
			_held = sim.apply({"type": "zone_frontage", "seg": r[0], "side": r[1], "zone": zone,
				"span": [r[2], r[3]], "both": both, "hold": true}) or _held
			_learn(r[0], zone)
		_spans.clear()
		_dragging = false
		_hover = []  # shows the block face under the mouse again
		_update_hint()
	elif not _hover.is_empty():
		sim.apply({"type": "zone_frontage", "seg": _hover[0], "side": _hover[1], "zone": zone, "both": both})
		_learn(_hover[0], zone)


## The street side under the mouse, with its whole block face shown.
func _update_hover(hit) -> void:
	var h := []
	if hit != null:
		var near := sim.network.find_segment_near(Vector3(hit.x, 0.0, hit.z), 40.0, 1.0)
		if not near.is_empty() and RoadStyle.TYPES[sim.network.segments[near.seg].type].lots:
			var c := sim.network.curve_of(near.seg)
			var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], near.t)
			var to_mouse := Vector2(hit.x - near.point.x, hit.z - near.point.z)
			var side := 1 if Vector2(-tan.z, tan.x).dot(to_mouse) >= 0.0 else -1
			h = [near.seg, side]
	if h == _hover:
		return
	_hover = h
	if _dragging:
		return  # the dragged stretch is shown instead
	if h.is_empty():
		zone_view.preview = []
		return
	if mode == Mode.SMART:
		_guesses.clear()
		_show_smart([h])
		return
	var parts := sim.frontage_chain(h[0], h[1])
	if Input.is_key_pressed(KEY_SHIFT):
		parts.append_array(sim.frontage_chain(h[0], -h[1]))
	zone_view.preview_zones = []
	zone_view.preview = parts


## A smart drag: every street side it crosses, each zoned its own way.
func _smart_extend() -> void:
	if _hover.is_empty():
		return
	var key := "%d:%d" % [_hover[0], _hover[1]]
	if _smart_sides.has(key):
		return
	_smart_sides[key] = _hover.duplicate()
	_show_smart(_smart_sides.values())


## Shows street sides' whole block faces in the zones a smart click would give them.
func _show_smart(sides: Array) -> void:
	var parts := []
	var zones := []
	var counts := {}
	for sd in _with_across(sides, Input.is_key_pressed(KEY_SHIFT)):
		var z := guess(sd[0], sd[1])
		counts[z] = counts.get(z, 0) + 1
		for part in sim.frontage_chain(sd[0], sd[1]):
			parts.append(part)
			zones.append(z)
	zone_view.preview_zones = zones
	zone_view.preview = parts
	if sides.size() == 1:
		hint_changed.emit("Smart: %s here (%s).  Click to zone it, or drag across streets.  Shift: both sides   Tab: tool   Right click to stop." \
			% [ZoneMap.NAMES[guess(sides[0][0], sides[0][1])], why(sides[0][0], sides[0][1])])
	else:
		var bits := []
		for z in counts:
			bits.append("%d %s" % [counts[z], ZoneMap.NAMES[z]])
		hint_changed.emit("Smart: %d street sides (%s).  Let go to zone them." % [sides.size(), ", ".join(bits)])


func _with_across(sides: Array, both: bool) -> Array:
	var out := []
	var seen := {}
	for sd in sides:
		for side in ([sd[1], -sd[1]] if both else [sd[1]]):
			var key := "%d:%d" % [sd[0], side]
			if not seen.has(key):
				seen[key] = true
				out.append([sd[0], side])
	return out


## The zone smart paint gives a street side: how you've zoned that street type
## before, what's across the street, and what's around it.
func guess(seg: int, side: int) -> int:
	var key := "%d:%d" % [seg, side]
	if _guesses.has(key):
		return _guesses[key]
	var sc := _scores(seg, side)
	var best := ZoneMap.Zone.RESIDENTIAL
	for z in [ZoneMap.Zone.RESIDENTIAL, ZoneMap.Zone.COMMERCIAL, ZoneMap.Zone.INDUSTRIAL]:
		if sc[z] > sc[best] + 0.001:
			best = z
	_guesses[key] = best
	return best


func _scores(seg: int, side: int) -> Dictionary:
	var sc := {ZoneMap.Zone.RESIDENTIAL: 0.0, ZoneMap.Zone.COMMERCIAL: 0.0, ZoneMap.Zone.INDUSTRIAL: 0.0}
	if not sim.network.segments.has(seg):
		return sc
	var t: int = sim.network.segments[seg].type
	var h: Dictionary = habits.get(t, {})
	var total := 0.0
	for z in h:
		total += h[z]
	if total > 0.0:
		for z in h:
			if sc.has(z):
				sc[z] += h[z] / total
	else:
		# Nothing learned yet: shops on the busy streets, homes on the rest.
		var lanes: int = RoadStyle.TYPES[t].get("lanes", 2)
		sc[ZoneMap.Zone.COMMERCIAL if lanes >= 4 else ZoneMap.Zone.RESIDENTIAL] += 0.6
	var across := _side_zone(seg, -side)
	if sc.has(across):
		sc[across] += ACROSS_WEIGHT
	var around := _around(seg, side)
	var n := 0.0
	for z in around:
		n += around[z]
	for z in around:
		if sc.has(z):
			sc[z] += AROUND_WEIGHT * around[z] / n
	return sc


## Why smart paint picked what it did, in a few words.
func why(seg: int, side: int) -> String:
	var z := guess(seg, side)
	var t: int = sim.network.segments[seg].type
	var h: Dictionary = habits.get(t, {})
	var total := 0
	for k in h:
		total += h[k]
	var road: String = RoadStyle.TYPES[t].name.to_lower()
	var bits := []
	if total > 0 and h.get(z, 0) > 0:
		bits.append("you zone %ss as %s %d of %d times" % [road, ZoneMap.NAMES[z].to_lower(), h[z], total])
	if _side_zone(seg, -side) == z:
		bits.append("matches across the street")
	var around := _around(seg, side)
	var top := -1
	for k in around:
		if top < 0 or around[k] > around[top]:
			top = k
	if top == z:
		bits.append("fits the area")
	if bits.is_empty():
		bits.append("a usual fit for a %s" % road)
	return ", ".join(bits)


## The zone of a street side, read at the middle of its frontage (0 if none).
func _side_zone(seg: int, side: int) -> int:
	var s := sim.planner.side_survey(sim.network, seg, side)
	if s.is_empty() or s.rays.is_empty():
		return 0
	var r: Array = s.rays[s.rays.size() / 2]
	if r[3] < 0.0:
		return 0
	var p: Vector2 = (r[1] as Vector2) + (r[2] as Vector2) * LotPlanner.ZONE_PROBE
	return sim.zones.zone_at(Vector3(p.x, 0.0, p.y))


## Zoned ground around a street side's middle: {zone: samples}.
func _around(seg: int, side: int) -> Dictionary:
	var out := {}
	var s := sim.planner.side_survey(sim.network, seg, side)
	if s.is_empty() or s.fronts.is_empty():
		return out
	var mid: Vector2 = s.fronts[s.fronts.size() / 2][1]
	var steps := int(AROUND_RADIUS / AROUND_STEP)
	for i in range(-steps, steps + 1):
		for j in range(-steps, steps + 1):
			var off := Vector2(i, j) * AROUND_STEP
			if off.length() > AROUND_RADIUS:
				continue
			var z := sim.zones.zone_at(Vector3(mid.x + off.x, 0.0, mid.y + off.y))
			if z != 0:
				out[z] = out.get(z, 0) + 1
	return out


## Remembers that the player zoned a street of this type this way.
func _learn(seg: int, z: int) -> void:
	if z == ZoneMap.Zone.NONE or not sim.network.segments.has(seg):
		return
	var t: int = sim.network.segments[seg].type
	var h: Dictionary = habits.get(t, {})
	h[z] = h.get(z, 0) + 1
	habits[t] = h
	var cfg := ConfigFile.new()
	for k in habits:
		for zz in habits[k]:
			cfg.set_value(str(k), str(zz), habits[k][zz])
	cfg.save(HABITS_PATH)


func _load_habits() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(HABITS_PATH) != OK:
		return
	for k in cfg.get_sections():
		var h := {}
		for zz in cfg.get_section_keys(k):
			h[int(zz)] = int(cfg.get_value(k, zz, 0))
		habits[int(k)] = h


func set_mode(m: int) -> void:
	mode = m
	_painting = false
	_dragging = false
	_spans.clear()
	_smart_sides.clear()
	_guesses.clear()
	_hover = []
	zone_view.preview = []
	_update_hint()
	mode_changed.emit(mode)


## The round brush.
func _paint() -> void:
	var hit = cam.mouse_ground_point()
	if hit == null:
		return
	var p := Vector3(hit.x, 0.0, hit.z)
	if _last_paint != Vector3.INF and p.distance_to(_last_paint) < radius * 0.25:
		return
	_last_paint = p
	_held = sim.apply({"type": "paint_zone", "center": [p.x, p.z], "radius": radius, "zone": zone,
		"hold": true}) or _held


## Ends a drag: its streets' lots are cut now, once (see CitySim "hold").
func _stop() -> void:
	_painting = false
	if _held:
		_held = false
		sim.apply({"type": "zone_done"})


func _resize(f: float) -> void:
	set_radius(radius * f)


func set_radius(r: float) -> void:
	radius = clampf(r, MIN_RADIUS, MAX_RADIUS)
	_update_ring()
	_update_hint()
	mode_changed.emit(mode)


func _update_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.6
	torus.outer_radius = radius
	torus.rings = 48
	_ring.mesh = torus
	var c: Color = ZoneMap.COLORS[maxi(zone, 0)] if zone != ZoneMap.Zone.NONE else Color(1, 0.35, 0.3)
	_ring_mat.albedo_color = Color(c, 0.9)


func _update_hint() -> void:
	if zone == OFF:
		return
	var verb: String = "Dezone" if zone == ZoneMap.Zone.NONE else "Zone " + ZoneMap.NAMES[zone]
	if mode == Mode.SMART:
		hint_changed.emit("Smart paint: point at a street side to see the zone it guesses from how you zone.  Click or drag across streets.  Tab: tool   Right click to stop.")
	elif brush:
		hint_changed.emit("%s with the brush: drag over the street edge.  Brush %d m  [ ]   Tab: tool   Right click to stop." \
			% [verb, int(radius)])
	else:
		hint_changed.emit("%s: click a street side for its whole block, or drag along it for just that stretch.  Shift: both sides   Tab: tool   Right click to stop." \
			% verb)
