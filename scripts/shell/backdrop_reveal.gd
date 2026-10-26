class_name BackdropReveal
extends CanvasLayer
## Covers the home screen's backdrop with a picture of the town (MenuStill)
## until the views that draw it are done, then fades the picture into the
## live town, so the town never fills in while you watch and the screen is
## never blank. Behind the menu's own panel (which sits above this layer).
## Gives up after CAP_S seconds.
##
##   var reveal := BackdropReveal.cover(self, MenuStill.texture_for(clock))
##   ... later, once the views exist:
##   reveal.watch([land.is_drawn, buildings.is_drawn])
##
## Meanwhile the views draw with a bigger share of each frame than in play,
## shared between them all (LoadGate.share_ms) and sized so frames take
## about FRAME_TARGET_MS: the menu stays smooth (over 30 frames a second)
## and the town is drawn as fast as that allows.

## Most seconds to wait: desktop, browser.
const CAP_S := 20.0
const CAP_S_WEB := 30.0
const FADE_S := 0.8
const CALM_FRAMES := 2
## Milliseconds a frame the views share while covered: to start with, and
## the least and most it grows or shrinks to.
const SHARE_MS := 8.0
const SHARE_MIN_MS := 3.0
const SHARE_MAX_MS := 30.0
## The frame time the share aims for (35 frames a second), and how much of
## the gap it closes each frame.
const FRAME_TARGET_MS := 28.0
const SHARE_GAIN := 0.25

var _checks: Array = []
var _watching := false
var _cover := ColorRect.new()
var _picture := TextureRect.new()
var _time := 0.0
var _calm := 0
var _fading := -1.0


static func cover(menu: Node, picture: Texture2D = null) -> BackdropReveal:
	var layer := BackdropReveal.new()
	layer._picture.texture = picture
	menu.add_child(layer)
	return layer


## The views' readiness checks (Callables returning bool); the picture
## stays up until they all read true.
func watch(checks: Array) -> void:
	_checks = checks
	_watching = true


## True once the picture has started to fade into the live town.
func fading() -> bool:
	return _fading >= 0.0


func _ready() -> void:
	layer = 0  # under the menu's own layer
	# The views' shared frame starts as the frame does: before any view, and
	# before the sliced ones (RoadView) carry on from where they waited.
	get_tree().process_frame.connect(LoadGate.frame_begins)
	_cover.color = Brand.SURFACE
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)
	# The picture is wide (MenuStill.ASPECT), cropped to the window as the
	# camera crops the town: the same height, centred.
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(_picture)
	LoadGate.loading = true
	LoadGate.share_ms = SHARE_MS
	LoadGate.frame_begins()


func _exit_tree() -> void:
	_release()


func _release() -> void:
	LoadGate.loading = false
	LoadGate.share_ms = 0.0
	if is_inside_tree() and get_tree().process_frame.is_connected(LoadGate.frame_begins):
		get_tree().process_frame.disconnect(LoadGate.frame_begins)


func _process(delta: float) -> void:
	_time += delta
	if LoadGate.share_ms > 0.0:
		LoadGate.share_ms = clampf(LoadGate.share_ms + (FRAME_TARGET_MS - delta * 1000.0) * SHARE_GAIN,
			SHARE_MIN_MS, SHARE_MAX_MS)
	if _fading >= 0.0:
		_fading += delta
		_cover.modulate.a = 1.0 - smoothstep(0.0, FADE_S, _fading)
		if _fading >= FADE_S:
			queue_free()
		return
	var ready := _watching
	for c in _checks:
		if c.is_valid() and not c.call():
			ready = false
			break
	_calm = _calm + 1 if ready else 0
	if _calm >= CALM_FRAMES or _time > (CAP_S_WEB if OS.has_feature("web") else CAP_S):
		_release()
		_fading = 0.0
