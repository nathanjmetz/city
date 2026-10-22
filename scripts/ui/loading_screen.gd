class_name LoadingScreen
extends CanvasLayer
## The Neighbors loading screen: the House mark fills up from the foundation
## to the roof as the game really loads, under a gently moving surface, with
## a thin bar and a status line below. It sits on the tree root, so it stays
## up across scene changes, and only goes away when finish() is called.
##
##   LoadingScreen.open()                       # cover the screen
##   LoadingScreen.progress(0.4, "Paving roads") # 0..1, only goes up
##   LoadingScreen.close()                      # fill to 100%, fade out
##
## The same animation runs in the web page while the game downloads
## (web/shell.html), so the two read as one screen.

signal finished

## The open loading screen, if any.
static var current: LoadingScreen

# The House mark on a 512 square (see branding/kit/logos/neighbors-mark.svg).
# Each cell is drawn with a round 15 px edge, as in the logo.
const _CELLS := [
	[Vector2(61.23, 445.69), Vector2(228.30, 445.69), Vector2(228.30, 284.35), Vector2(86.00, 207.98), Vector2(61.23, 228.62)],
	[Vector2(283.70, 445.69), Vector2(450.77, 445.69), Vector2(450.77, 228.62), Vector2(426.00, 207.98), Vector2(283.70, 284.35)],
	[Vector2(380.11, 169.73), Vector2(256.00, 66.31), Vector2(131.89, 169.73), Vector2(256.00, 236.34)],
]
const _ROUND := 15.11
## Lowest and highest points of the rounded mark: the fill runs between them.
const _BOTTOM := 445.69 + _ROUND
const _TOP := 66.31 - _ROUND
## How far (in seconds) the shown fill lags behind real progress.
const _EASE := 0.25
const _FADE := 0.45

var _target := 0.0
var _shown := 0.0
var _status := ""
var _step_from := 0.0
var _step_to := 1.0
var _closing := false
var _done_at := -1.0
var _time := 0.0
var _rounded: Array[PackedVector2Array] = []
var _line_w := 1.5
var _canvas: Control
var _status_label: Label
var _root: Control


## Covers the screen with the loading screen (or returns the one already up).
static func open(status := "") -> LoadingScreen:
	if current and is_instance_valid(current) and not current._closing:
		if status != "":
			current.set_progress(current._target, status)
		return current
	var ls := LoadingScreen.new()
	ls.name = "LoadingScreen"
	ls._status = status
	(Engine.get_main_loop() as SceneTree).root.add_child(ls)
	current = ls
	return ls


## Reports progress on the open loading screen; does nothing if none is up.
static func progress(fraction: float, status := "") -> void:
	if current and is_instance_valid(current):
		current.set_progress(fraction, status)


## Finishes the open loading screen: fills it, then fades it away.
static func close() -> void:
	if current and is_instance_valid(current):
		current.finish()


static func is_open() -> bool:
	return current != null and is_instance_valid(current)


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	for cell in _CELLS:
		var grown := Geometry2D.offset_polygon(PackedVector2Array(cell), _ROUND, Geometry2D.JOIN_ROUND)
		_rounded.append(grown[0])


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Brand.SURFACE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_screen)
	_root.add_child(_canvas)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_override("font", Brand.ui(500))
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Brand.INK_MUTED)
	_root.add_child(_status_label)
	_update_label()


## Sets how far along loading is (0..1) and, optionally, what it's doing.
## Progress never goes backwards on screen.
func set_progress(fraction: float, status := "") -> void:
	_target = maxf(_target, clampf(fraction, 0.0, 1.0))
	if status != "":
		_status = status
	_update_label()


## Starts a step that runs from the current progress up to `end_fraction`;
## then step_progress(0..1) moves within it.
func begin_step(status: String, end_fraction: float) -> void:
	_step_from = _target
	_step_to = maxf(_target, clampf(end_fraction, 0.0, 1.0))
	set_progress(_target, status)


func step_progress(fraction: float) -> void:
	set_progress(lerpf(_step_from, _step_to, clampf(fraction, 0.0, 1.0)))


## Fills to 100%, lets the house settle for a moment, then fades out.
func finish() -> void:
	if _closing:
		return
	_closing = true
	set_progress(1.0, "Welcome home")


func _process(delta: float) -> void:
	_time += delta
	# Ease toward real progress, with a floor speed so it never crawls.
	var gap := _target - _shown
	if gap > 0.0:
		_shown = minf(_target, _shown + maxf(gap * (1.0 - exp(-delta / _EASE)), delta * 0.08))
	_update_label()
	if _closing and _shown >= 1.0 and _done_at < 0.0:
		_done_at = _time
	if _done_at >= 0.0:
		var t := _time - _done_at - 0.35
		if t > 0.0:
			_root.modulate.a = 1.0 - clampf(t / _FADE, 0.0, 1.0)
			if t >= _FADE:
				if current == self:
					current = null
				finished.emit()
				queue_free()
				return
	_canvas.queue_redraw()


func _update_label() -> void:
	if _status_label == null:
		return
	var pct := int(floor(_shown * 100.0 + 0.0001))
	_status_label.text = ("%s  ·  %d%%" % [_status, pct]) if _status != "" else "%d%%" % pct


func _draw_screen() -> void:
	var view := _canvas.size
	var mark_px := clampf(minf(view.y * 0.3, view.x * 0.4), 120.0, 260.0)
	var scale := mark_px / 512.0
	var title_size := int(round(mark_px * 0.2))
	var block_h := mark_px + title_size * 1.6 + 48.0
	var top := (view.y - block_h) * 0.5
	var origin := Vector2((view.x - mark_px) * 0.5, top)

	# A little settle when it's full: the house rises and comes back down.
	var lift := 0.0
	if _done_at >= 0.0:
		lift = sin(clampf((_time - _done_at) / 0.35, 0.0, 1.0) * PI) * 6.0

	_canvas.draw_set_transform(origin + Vector2(0, -lift), 0.0, Vector2(scale, scale))
	_line_w = 1.5 / scale
	var level := lerpf(_BOTTOM, _TOP, _shown)
	# The surface moves gently; it calms down as the house fills.
	var amp := 7.0 * (1.0 - _shown * 0.85)
	var colors := [Brand.BRAND_TEAL, Brand.BRAND_CORAL, Brand.BRAND_MINT]
	var back := _surface(level - 5.0, amp * 0.8, _time * 1.3 + 1.7)
	var front := _surface(level, amp, -_time * 1.9)
	for i in _rounded.size():
		var cell: PackedVector2Array = _rounded[i]
		_fill(cell, Brand.SURFACE_RAISED)
		for part in Geometry2D.intersect_polygons(cell, back):
			_fill(part, Color(colors[i], 0.35))
		for part in Geometry2D.intersect_polygons(cell, front):
			_fill(part, colors[i])
	_canvas.draw_set_transform(Vector2.ZERO)

	# Wordmark, bar and status under the mark.
	var font := Brand.display(600)
	var y := origin.y + mark_px + title_size * 1.25
	var tw := font.get_string_size("Neighbors", HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	_canvas.draw_string(font, Vector2((view.x - tw) * 0.5, y), "Neighbors",
		HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Brand.INK)
	var bar_w := mark_px * 1.2
	var bar := Rect2((view.x - bar_w) * 0.5, y + title_size * 0.55, bar_w, 4)
	_canvas.draw_rect(bar, Brand.SURFACE_SUNKEN)
	_canvas.draw_rect(Rect2(bar.position, Vector2(bar_w * _shown, 4)), Brand.BRAND_MINT)
	_status_label.position = Vector2(0, bar.end.y + 10)
	_status_label.size = Vector2(view.x, 20)


## The filled region: everything below a wavy line at `level`.
func _surface(level: float, amp: float, phase: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 32
	for i in steps + 1:
		var x := -20.0 + i * 552.0 / steps
		pts.append(Vector2(x, level + sin(x * 0.024 + phase) * amp + sin(x * 0.051 - phase * 0.6) * amp * 0.35))
	pts.append(Vector2(532, 600))
	pts.append(Vector2(-20, 600))
	return pts


func _fill(poly: PackedVector2Array, color: Color) -> void:
	if poly.size() < 3:
		return
	_canvas.draw_colored_polygon(poly, color)
	# Soft edge, since filled polygons aren't antialiased.
	var ring := poly.duplicate()
	ring.append(poly[0])
	_canvas.draw_polyline(ring, color, _line_w, true)
