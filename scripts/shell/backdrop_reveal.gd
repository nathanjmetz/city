class_name BackdropReveal
extends CanvasLayer
## Hides the home screen's backdrop behind a plain cover until the views
## that draw it are done, then fades the cover away, so the town never fills
## in while you watch. Behind the menu's own panel (which sits above this
## layer). Gives up after CAP_S seconds.
##
##   BackdropReveal.cover(self, [land.is_drawn, buildings.is_drawn])

const CAP_S := 8.0
const FADE_S := 0.45
const CALM_FRAMES := 2

var _checks: Array = []
var _cover := ColorRect.new()
var _time := 0.0
var _calm := 0
var _fading := -1.0


static func cover(menu: Node, checks: Array) -> void:
	var layer := BackdropReveal.new()
	layer._checks = checks
	menu.add_child(layer)


func _ready() -> void:
	layer = 0  # under the menu's own layer
	_cover.color = Brand.SURFACE
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)
	LoadGate.loading = true  # the views draw with the bigger budget meanwhile


func _exit_tree() -> void:
	LoadGate.loading = false


func _process(delta: float) -> void:
	_time += delta
	if _fading >= 0.0:
		_fading += delta
		_cover.modulate.a = 1.0 - clampf(_fading / FADE_S, 0.0, 1.0)
		if _fading >= FADE_S:
			queue_free()
		return
	var ready := true
	for c in _checks:
		if c.is_valid() and not c.call():
			ready = false
			break
	_calm = _calm + 1 if ready else 0
	if _calm >= CALM_FRAMES or _time > CAP_S:
		LoadGate.loading = false
		_fading = 0.0
