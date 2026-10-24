class_name PadWheel
extends Control
## The controller's tool wheel (Y), like the radial menus in the console
## editions of Cities: Skylines: the tool bar's categories in a ring. Point
## the left stick at one and press A (or Y again) to open it; a menu with
## tools then opens a second ring of its tools. B closes.

signal picked(key: String)

const RADIUS := 150.0
const SLOT := 64.0

var _items: Array = []  # [icon, title, key] or null (an empty slot); the key defaults to the icon
var _radius := RADIUS
var _hint := "Open"
var _icons: Array = []  # Icon, or null for an empty slot
var _sel := 0
var _style := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.theme()


## Which slot a stick direction points at. Slot 0 is straight up and the
## rest go round clockwise.
static func slot_for(dir: Vector2, count: int) -> int:
	var a := atan2(dir.x, -dir.y)
	return posmod(roundi(a / (TAU / count)), count)


func open(items: Array, style: int, hint := "Open", sel := 0) -> void:
	_items = items
	_style = style
	_hint = hint
	_sel = clampi(sel, 0, maxi(items.size() - 1, 0))
	# More slots need a bigger ring, so the titles don't touch. (Pies keep
	# their empty slots, so each tool sits where the keyboard's pie has it.)
	_radius = maxf(RADIUS, items.size() * SLOT * 1.15 / TAU)
	for ic in _icons:
		if ic != null:
			ic.queue_free()
	_icons.clear()
	for i in items.size():
		var ic: Icon = null
		if items[i] != null:
			ic = Icon.new(items[i][0], 28)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ic.size = Vector2(28, 28)
			add_child(ic)
		_icons.append(ic)
	visible = true
	_layout()


func close() -> void:
	visible = false


func aim(stick: Vector2) -> void:
	if stick.length() < 0.5 or _items.is_empty():
		return
	var s := slot_for(stick, _items.size())
	if _items[s] == null:
		return  # an empty slot keeps the last pick
	if s != _sel:
		_sel = s
		queue_redraw()


func pick() -> void:
	close()
	if _sel < _items.size() and _items[_sel] != null:
		var it: Array = _items[_sel]
		picked.emit(it[2] if it.size() > 2 else it[0])


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_layout()


func _slot_pos(i: int) -> Vector2:
	var a := TAU * i / _items.size()
	return size * 0.5 + Vector2(sin(a), -cos(a)) * _radius


func _layout() -> void:
	for i in _icons.size():
		if _icons[i] != null:
			_icons[i].position = _slot_pos(i) - Vector2(14, 22)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(Brand.SURFACE, 0.35))
	draw_circle(c, _radius + SLOT * 0.75, Color(Brand.SURFACE_PANEL, 0.92))
	draw_circle(c, _radius + SLOT * 0.75, Brand.LINE, false, 1.5, true)
	var font := get_theme_default_font()
	for i in _items.size():
		if _items[i] == null:
			continue
		var p := _slot_pos(i)
		var on := i == _sel
		draw_circle(p, SLOT * 0.5, Brand.BRAND_CORAL if on else Brand.SURFACE_RAISED)
		_icons[i].color = Brand.ON_CORAL if on else Brand.INK
		var title: String = _items[i][1]
		var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, p + Vector2(-w / 2.0, 20), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Brand.ON_CORAL if on else Brand.INK_MUTED)
	if _sel < _items.size() and _items[_sel] != null:
		var t: String = _items[_sel][1]
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(font, c + Vector2(-tw / 2.0, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Brand.INK)
	# What to press, in the pad's own buttons.
	var y := c.y + 14.0
	PadPrompts.glyph(self, Rect2(c.x - 52, y, 20, 20), "a", _style)
	draw_string(font, Vector2(c.x - 28, y + 15), _hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Brand.INK_MUTED)
	PadPrompts.glyph(self, Rect2(c.x + 6, y, 20, 20), "b", _style)
	draw_string(font, Vector2(c.x + 30, y + 15), "Close", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Brand.INK_MUTED)
