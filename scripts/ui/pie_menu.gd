class_name PieMenu
extends Control
## The number keys' pie menus (marking menus: Kurtenbach and Buxton; Blender's
## and Maya's hotkey pies; the weapon wheels of GTA and Overwatch). Hold 1 for
## Roads: the pie blooms in the middle of the screen; flick toward a tool and
## let go. Only the direction of the flick counts, not where the cursor is, so
## a quick flick works before the pie has even drawn. A tap leaves it open to
## click. Letting go in the middle, Esc or a right click closes it. A group
## (Road types) swaps in its own pie, by pushing on past the ring or picking it.
## Slots never move, so a hand learns them: 0 is straight up, then clockwise.
## The controller's wheel (Y) lays each menu out the same way.
##
## The look follows the House mark: wedges of a ring split by the cream
## city-line gap, the one you point at lifting out in coral, and a hub whose
## knob leans the way you flick.

signal chosen(card: Button)

const INNER := 62.0  # the hub's edge
const OUTER_R := 178.0  # the ring's outer edge
const RADIUS := (INNER + OUTER_R) * 0.5  # where the icons sit
const GAP := 5.0  # the city-line gap between wedges, in px
const LIFT := 10.0  # how far the pointed-at wedge lifts out
## Inside this (from the middle) the flick points at nothing.
const DEAD := 22.0
## Pushing this far into a group opens it without letting go.
const OUTER := OUTER_R + 30.0
## A flick finished sooner never draws the pie (marking ahead).
const SHOW_MS := 120
## Shorter than this, a press with no flick is a tap: the pie stays open.
const TAP_MS := 260
const OPEN_S := 0.22
const CLOSE_S := 0.14

var _items: Array = []  # slots: null or {title, icon, card} / {title, icon, group}
var _title := ""
var _trail := ""  # "Roads  ›" over a group's own pie
var _origin := Vector2.ZERO  # the middle of the screen
var _pointer := Vector2.ZERO  # the flick, from the middle
var _key: Key = KEY_NONE
var _held := false
var _since := 0
var _sel := -1
var _icons: Array = []
var _open_t := 0.0  # 0..1 bloom
var _closing := false
var _close_t := 0.0
var _hover: Array = []  # per slot, 0..1 eased toward the pick
var _swap_t := 1.0  # 0..1 when a group swaps in
var _picked := -1  # the slot that flashes as it closes
## The desktop can move the cursor to the middle, so the cursor is the flick;
## the browser can't, so the flick adds up the mouse's motion instead.
var _warps := not OS.has_feature("web")


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.theme()
	visible = false
	set_process(false)


## Slot directions: 4 slots are the compass points, 8 add the diagonals.
static func slot_dir(i: int, count: int) -> Vector2:
	var a := TAU * i / count
	return Vector2(sin(a), -cos(a))


## Lays a plain list of items into fixed slots: the compass points first
## (the easiest to hit), then the diagonals.
static func auto_slots(items: Array) -> Array:
	if items.size() <= 4:
		var four := [null, null, null, null]
		for i in items.size():
			four[i] = items[i]
		return four
	var eight := [null, null, null, null, null, null, null, null]
	var order := [0, 2, 4, 6, 1, 3, 5, 7]
	for i in mini(items.size(), 8):
		eight[order[i]] = items[i]
	return eight


## The slot a direction points at, or -1 (the middle, or an empty slot).
static func slot_at(items: Array, d: Vector2) -> int:
	if d.length() < DEAD or items.is_empty():
		return -1
	var s := PadWheel.slot_for(d, items.size())
	return s if items[s] != null and _usable(items[s]) else -1


static func _usable(it: Dictionary) -> bool:
	return it.has("group") or (is_instance_valid(it.get("card")) and not (it.card as Button).disabled)


func is_open() -> bool:
	return visible and not _closing


## Opens a pie in the middle of the screen, held down by a key (or KEY_NONE:
## already let go). `_at` is where the cursor was; the pie no longer follows it.
func open(title: String, items: Array, _at: Vector2, key: Key) -> void:
	_title = title
	_trail = ""
	_key = key
	_held = key != KEY_NONE
	_since = Time.get_ticks_msec()
	_closing = false
	_open_t = 0.0
	_swap_t = 1.0
	_picked = -1
	_origin = size * 0.5 if size != Vector2.ZERO else get_viewport_rect().size * 0.5
	_set_items(items)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	if _held:
		# The cursor goes to the middle with the pie (where the desktop can move
		# it; the browser can't, so flicks are read from the mouse's motion).
		Input.warp_mouse(_origin)
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	_close_t = 0.0
	_held = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)


func _finish_close() -> void:
	visible = false
	_closing = false
	set_process(false)
	_items = []
	for ic in _icons:
		if ic != null:
			ic.queue_free()
	_icons.clear()


func _set_items(items: Array) -> void:
	_items = items
	_pointer = Vector2.ZERO
	_sel = -1
	for ic in _icons:
		if ic != null:
			ic.queue_free()
	_icons.clear()
	_hover.clear()
	for it in items:
		var ic: Icon = null
		if it != null:
			ic = Icon.new(it.icon, 36)
			ic.size = Vector2(36, 36)
			ic.pivot_offset = Vector2(18, 18)
			ic.visible = false
			add_child(ic)
		_icons.append(ic)
		_hover.append(0.0)


func _shown() -> bool:
	return not _held or Time.get_ticks_msec() - _since >= SHOW_MS


func _process(delta: float) -> void:
	if _closing:
		_close_t = minf(1.0, _close_t + delta / CLOSE_S)
		if _close_t >= 1.0:
			_finish_close()
			return
	elif _shown():
		_open_t = minf(1.0, _open_t + delta / OPEN_S)
	_swap_t = minf(1.0, _swap_t + delta / OPEN_S)
	for i in _hover.size():
		var want := 1.0 if i == _sel or i == _picked else 0.0
		_hover[i] = lerpf(_hover[i], want, 1.0 - exp(-delta * 18.0))
	_layout()


func _input(event: InputEvent) -> void:
	if not visible or _closing:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _held and not _warps and mm.relative != Vector2.ZERO:
			_pointer += mm.relative
		else:
			_pointer = mm.position - _origin
		_aim()
	elif event is InputEventKey:
		var k := event as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		if _held and not k.pressed and (code == _key or k.keycode == _key):
			_release()
		elif k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			close()
		elif k.pressed and not k.echo and not _held and (code == _key or k.keycode == _key):
			close()  # the same key again closes a pie left open
		else:
			return  # another number key switches pies (Hud)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if not _held:
				_pointer = mb.position - _origin
			_aim()
			if _sel >= 0:
				_choose(_sel)
			else:
				close()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			close()
	else:
		return
	get_viewport().set_input_as_handled()


func _aim() -> void:
	var s := slot_at(_items, _pointer)
	# Pushing on past the ring into a group opens it, still held.
	if _held and s >= 0 and _items[s].has("group") and _pointer.length() > OUTER:
		_open_group(s)
		return
	if s != _sel:
		_sel = s
		_layout()


func _release() -> void:
	_held = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _sel >= 0:
		_choose(_sel)
	elif Time.get_ticks_msec() - _since < TAP_MS:
		Input.warp_mouse(_origin)  # a tap: the pie stays open to click
	else:
		close()  # let go in the middle


func _choose(i: int) -> void:
	var it: Dictionary = _items[i]
	if it.has("group"):
		_open_group(i)
		return
	var card: Button = it.card
	_picked = i
	close()
	chosen.emit(card)


func _open_group(i: int) -> void:
	var it: Dictionary = _items[i]
	_trail = _title
	_title = it.title
	_set_items(auto_slots(it.group))
	_swap_t = 0.0
	if _held:
		Input.warp_mouse(_origin)


## The bloom: a little overshoot opening, a quick shrink closing.
func _scale() -> float:
	if _closing:
		return lerpf(1.0, 0.9, _close_t * _close_t)
	var t := _open_t * _swap_t
	var c := 1.7  # easeOutBack
	return 0.82 + 0.18 * (1.0 + (c + 1.0) * pow(t - 1.0, 3) + c * pow(t - 1.0, 2))


func _alpha() -> float:
	if _closing:
		return 1.0 - _close_t
	return clampf(_open_t * 1.6, 0.0, 1.0) * clampf(0.3 + _swap_t, 0.0, 1.0)


## Each wedge blooms a moment after the one before it, round from the top.
func _stagger(i: int) -> float:
	if _closing:
		return 1.0
	return clampf((_open_t * _swap_t * 1.4) - i * 0.05, 0.0, 1.0)


func _layout() -> void:
	var show := _shown() and visible
	var sc := _scale()
	for i in _icons.size():
		var ic: Icon = _icons[i]
		if ic == null:
			continue
		ic.visible = show
		var h: float = _hover[i]
		var st := _stagger(i)
		var p := _origin + slot_dir(i, _items.size()) * (RADIUS + LIFT * h) * sc * lerpf(0.7, 1.0, st)
		ic.position = p - Vector2(18, 26)
		ic.scale = Vector2.ONE * (1.0 + 0.14 * h) * sc
		ic.modulate.a = _alpha() * st
		var it: Dictionary = _items[i]
		ic.color = Brand.INK.lerp(Brand.ON_CORAL, h) if _usable(it) else Brand.INK_FAINT
	queue_redraw()


## A wedge of the ring from angle a0 to a1, its sides pulled in by the gap.
func _wedge(c: Vector2, r0: float, r1: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 18
	var g0 := GAP * 0.5 / r0
	var g1 := GAP * 0.5 / r1
	for k in n + 1:
		var a := lerpf(a0 + g1, a1 - g1, float(k) / n)
		pts.append(c + Vector2(sin(a), -cos(a)) * r1)
	for k in n + 1:
		var a := lerpf(a1 - g0, a0 + g0, float(k) / n)
		pts.append(c + Vector2(sin(a), -cos(a)) * r0)
	return pts


func _draw() -> void:
	if not visible or not _shown() or _items.is_empty():
		return
	var c := _origin
	var a := _alpha()
	var sc := _scale()
	# The town dims a little round the pie, so it reads without a hard box.
	var dim := 0.32 * a
	draw_rect(Rect2(Vector2.ZERO, size), Color(Brand.SURFACE, dim * 0.55))
	for k in 6:
		draw_circle(c, (OUTER_R + 140.0 - k * 22.0) * sc, Color(Brand.SURFACE, dim * 0.12))
	# A soft shadow under the ring lifts it off the town.
	for k in 5:
		draw_circle(c + Vector2(0, 6.0 * sc), (OUTER_R + 4.0 + k * 5.0) * sc, Color(0, 0, 0, 0.06 * a))
	var n := _items.size()
	var step := TAU / n
	var font_ui := Brand.ui(600)
	var font_title := Brand.display(600)
	# The ring: one wedge per slot, split by the cream city-line gap.
	for i in n:
		var st := _stagger(i)
		if st <= 0.0:
			continue
		var h: float = _hover[i] if i < _hover.size() else 0.0
		var mid := step * i
		var lift := LIFT * h
		var off := Vector2(sin(mid), -cos(mid)) * lift
		var r0 := (INNER + 4.0) * sc * lerpf(0.75, 1.0, st)
		var r1 := (OUTER_R + 6.0 * h) * sc * lerpf(0.75, 1.0, st)
		var it = _items[i]
		var fill: Color
		if it == null:
			fill = Color(Brand.SURFACE_PANEL, 0.45)
		elif not _usable(it):
			fill = Color(Brand.SURFACE_PANEL, 0.75)
		else:
			fill = Color(Brand.SURFACE_PANEL, 0.94).lerp(Brand.BRAND_CORAL, h)
		var poly := _wedge(c + off, r0, r1, mid - step * 0.5, mid + step * 0.5)
		draw_colored_polygon(poly, Color(fill, fill.a * a * st))
		# A soft lighter rim along the outside edge, like light on glass.
		var rim := PackedVector2Array()
		for k in 19:
			var ang := lerpf(mid - step * 0.5 + GAP * 0.5 / r1, mid + step * 0.5 - GAP * 0.5 / r1, k / 18.0)
			rim.append(c + off + Vector2(sin(ang), -cos(ang)) * (r1 - 1.5))
		var rim_col := Brand.LINE_STRONG.lerp(Brand.BRAND_CREAM, h * 0.6)
		draw_polyline(rim, Color(rim_col, 0.7 * a * st), 2.0, true)
		poly.append(poly[0])
		draw_polyline(poly, Color(fill.lightened(0.05), fill.a * a * st * 0.8), 1.0, true)
		if it == null:
			continue
		# The name under the icon.
		var t: String = it.title + ("  ›" if it.has("group") else "")
		var p := c + Vector2(sin(mid), -cos(mid)) * (RADIUS + lift) * sc * lerpf(0.7, 1.0, st)
		var fs := 12
		var w := font_ui.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tc := Brand.INK_MUTED.lerp(Brand.ON_CORAL, h) if _usable(it) else Brand.INK_FAINT
		draw_string(font_ui, p + Vector2(-w * 0.5, 30.0 * sc), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(tc, a * st))
	# The hub: a cream-rimmed disc whose knob leans the way you flick.
	var hub := INNER * sc
	draw_circle(c, hub, Color(Brand.SURFACE, 0.96 * a))
	draw_circle(c, hub - 5.0, Color(Brand.SURFACE_RAISED, 0.35 * a))
	draw_arc(c, hub, 0, TAU, 64, Color(Brand.BRAND_CREAM, 0.22 * a), 1.5, true)
	draw_arc(c, hub - 5.0, 0, TAU, 64, Color(Brand.BRAND_MINT, 0.12 * a), 1.0, true)
	if _sel >= 0:
		var mid := step * _sel
		draw_arc(c, hub - 3.0, mid - step * 0.5 - PI * 0.5, mid + step * 0.5 - PI * 0.5, 24,
			Color(Brand.BRAND_CORAL, a), 3.0, true)
	# The knob rides the hub's rim toward the flick.
	if _shown() and _pointer.length() >= DEAD * 0.5:
		var dir := _pointer.normalized()
		draw_circle(c + dir * (hub - 11.0), 4.5, Color(Brand.BRAND_CORAL if _sel >= 0 else Brand.INK_FAINT, a))
	# The middle names the menu, or the tool pointed at.
	var head := _title if _sel < 0 else String(_items[_sel].title)
	var hs := 17 if head.length() <= 9 else 14
	var hw := font_title.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
	draw_string(font_title, c + Vector2(-hw * 0.5, -6.0), head, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(Brand.INK, a))
	var sub := _trail + "  ›" if _trail != "" and _sel < 0 else ("Let go" if _held else "Click")
	if _sel < 0 and _trail == "":
		sub = "Flick to a tool" if _held else "Click a tool"
	var sw := font_ui.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font_ui, c + Vector2(-sw * 0.5, 14.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Brand.INK_MUTED, a))
