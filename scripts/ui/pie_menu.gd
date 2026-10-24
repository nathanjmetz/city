class_name PieMenu
extends Control
## The number keys' pie menus (marking menus: Kurtenbach and Buxton; Blender's
## and Maya's hotkey pies; the weapon wheels of GTA and Overwatch). Hold 1 for
## Roads: the pie opens around the cursor; flick toward a tool and let go.
## Only the direction counts, not how far, so a quick flick works before the
## pie has even drawn. A tap leaves it open to click. Letting go in the
## middle, Esc or a right click closes it. A group (Road types) opens its own
## pie where the cursor is, by pushing on past the ring or picking it.
## Slots never move, so a hand learns them: 0 is straight up, then clockwise.
## The controller's wheel (Y) lays each menu out the same way.

signal chosen(card: Button)

const RADIUS := 104.0
const SLOT := 52.0
## Inside this the cursor points at nothing.
const DEAD := 22.0
## Pushing this far into a group opens it without letting go.
const OUTER := RADIUS * 1.75
## A flick finished sooner never draws the pie (marking ahead).
const SHOW_MS := 160
## Shorter than this, a press with no flick is a tap: the pie stays open.
const TAP_MS := 260

var _items: Array = []  # slots: null or {title, icon, card} / {title, icon, group}
var _title := ""
var _origin := Vector2.ZERO
var _key: Key = KEY_NONE
var _held := false
var _since := 0
var _sel := -1
var _icons: Array = []


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
	return visible


## Opens a pie around a point, held down by a key (or KEY_NONE: already let go).
func open(title: String, items: Array, at: Vector2, key: Key) -> void:
	_title = title
	_key = key
	_held = key != KEY_NONE
	_since = Time.get_ticks_msec()
	_set_items(items, at)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_held = false
	_items = []


func _set_items(items: Array, at: Vector2) -> void:
	_items = items
	_origin = at
	_sel = -1
	for ic in _icons:
		if ic != null:
			ic.queue_free()
	_icons.clear()
	for it in items:
		var ic: Icon = null
		if it != null:
			ic = Icon.new(it.icon, 24)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ic.size = Vector2(24, 24)
			add_child(ic)
		_icons.append(ic)
	_layout()


func _process(_delta: float) -> void:
	if _shown():
		_layout()
		set_process(false)


func _shown() -> bool:
	return not _held or Time.get_ticks_msec() - _since >= SHOW_MS


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		_aim((event as InputEventMouseMotion).position)
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
			_aim(mb.position)
			if _sel >= 0:
				_choose(_sel, mb.position)
			else:
				close()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			close()
	else:
		return
	get_viewport().set_input_as_handled()


func _aim(p: Vector2) -> void:
	var s := slot_at(_items, p - _origin)
	# Pushing on past the ring into a group opens it, still held.
	if _held and s >= 0 and _items[s].has("group") and (p - _origin).length() > OUTER:
		_open_group(s, p)
		return
	if s != _sel:
		_sel = s
		queue_redraw()
		_layout()


func _release() -> void:
	_held = false
	if _sel >= 0:
		_choose(_sel, get_viewport().get_mouse_position())
	elif Time.get_ticks_msec() - _since < TAP_MS:
		_layout()  # a tap: the pie stays open to click
	else:
		close()  # let go in the middle


func _choose(i: int, at: Vector2) -> void:
	var it: Dictionary = _items[i]
	if it.has("group"):
		_open_group(i, at)
		return
	var card: Button = it.card
	close()
	chosen.emit(card)


func _open_group(i: int, at: Vector2) -> void:
	var it: Dictionary = _items[i]
	_title = it.title
	_set_items(auto_slots(it.group), at)


## Where the pie is drawn: on the cursor, nudged inside the window. Only the
## direction from where the key went down picks, so the nudge never misleads.
func _center() -> Vector2:
	var m := RADIUS + SLOT
	return Vector2(clampf(_origin.x, m, maxf(m, size.x - m)), clampf(_origin.y, m, maxf(m, size.y - m)))


func _layout() -> void:
	var c := _center()
	for i in _icons.size():
		var ic: Icon = _icons[i]
		if ic == null:
			continue
		ic.visible = _shown()
		ic.position = c + slot_dir(i, _items.size()) * RADIUS - Vector2(12, 18)
		var it: Dictionary = _items[i]
		ic.color = Brand.ON_CORAL if i == _sel else (Brand.INK if _usable(it) else Brand.INK_MUTED)
	queue_redraw()


func _draw() -> void:
	if not visible or not _shown() or _items.is_empty():
		return
	var c := _center()
	draw_circle(c, RADIUS + SLOT * 0.8, Color(Brand.SURFACE_PANEL, 0.9))
	draw_circle(c, RADIUS + SLOT * 0.8, Brand.LINE, false, 1.5, true)
	draw_circle(c, DEAD, Brand.LINE, false, 1.0, true)
	var font := get_theme_default_font()
	for i in _items.size():
		if _items[i] == null:
			continue
		var it: Dictionary = _items[i]
		var p := c + slot_dir(i, _items.size()) * RADIUS
		var on := i == _sel
		draw_circle(p, SLOT * 0.5, Brand.BRAND_CORAL if on else Brand.SURFACE_RAISED)
		var t: String = it.title + (" ›" if it.has("group") else "")
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, p + Vector2(-w / 2.0, 18), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Brand.ON_CORAL if on else (Brand.INK if _usable(it) else Brand.INK_MUTED))
	# The middle names the pick, or the menu.
	var head := _title if _sel < 0 else (_items[_sel].title as String)
	var nw := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, c + Vector2(-nw / 2.0, -DEAD - 6), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Brand.INK)
	# A line from the middle toward the cursor shows the flick.
	var d := get_viewport().get_mouse_position() - _origin
	if d.length() >= DEAD:
		draw_line(c + d.normalized() * DEAD, c + d.normalized() * minf(d.length(), RADIUS - SLOT * 0.5),
			Brand.BRAND_CORAL if _sel >= 0 else Brand.LINE, 2.0, true)
