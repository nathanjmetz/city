class_name HoverCard
extends PanelContainer
## Rest the cursor on a building for a moment and a small card says what it
## is, and its problem if it has one, without a click (SimCity 4's query
## tool). Just the name and the problem: the info panel has the rest.
## Only with no tool in hand, and never over the menus or for roads.

const WAIT := 0.6
## Moving the pointer this far, in pixels, starts the wait over.
const STILL_PX := 4.0
const SKIP := ["road", "vehicle", "person", "spot", "pollution"]

var sim: CitySim
var cam: CityCamera
var select_tool: SelectTool
## True while a tool is in hand or a panel wants the cursor.
var busy := Callable()

var _title := UiStyle.label("", 13)
var _problem := UiStyle.label("", 12, Color(0.95, 0.45, 0.4))
var _rest := 0.0
var _at := Vector2(-1000, -1000)
var _shown := {}
var _view := Transform3D()


func setup(s: CitySim, camera: CityCamera, sel: SelectTool, tool_in_hand: Callable) -> void:
	sim = s
	cam = camera
	select_tool = sel
	busy = tool_in_hand


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiStyle.panel())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	col.add_child(_title)
	col.add_child(_problem)
	visible = false


func _process(delta: float) -> void:
	if sim == null:
		return
	var pad := Gamepad.find()
	var p := pad.pointer(get_viewport()) if pad != null else get_viewport().get_mouse_position()
	# A camera move (keys, wheel, stick, flying home) with the pointer still
	# puts a different place under it: start over, as CS2 does.
	var camera := get_viewport().get_camera_3d()
	var view := camera.global_transform if camera != null else Transform3D()
	# (Past the camera's own easing: a few centimetres or a hair of a turn.)
	var moved := view.origin.distance_to(_view.origin) > 0.05 or view.basis.z.dot(_view.basis.z) < 0.99999
	_view = view
	if moved or p.distance_to(_at) > STILL_PX or (busy.is_valid() and busy.call()) or get_viewport().gui_get_hovered_control() != null:
		_at = p
		_rest = 0.0
		_hide()
		return
	_rest += delta
	if _rest < WAIT or visible:
		return
	var hit = cam.mouse_ground_point()
	var sel := {} if hit == null else Inspect.pick(sim, hit)
	if sel.is_empty() or sel.type in SKIP or sel == select_tool.selection:
		return
	var d := Inspect.describe(sim, sel)
	if d.is_empty():
		return
	_shown = sel
	_title.text = d.title
	var problems: Array = d.get("problems", [])
	_problem.text = str(problems[0]) if not problems.is_empty() else ""
	_problem.visible = _problem.text != ""
	reset_size()
	var vp := get_viewport_rect().size
	position = Vector2(clampf(p.x + 18.0, 0.0, vp.x - size.x), clampf(p.y + 18.0, 0.0, vp.y - size.y))
	visible = true


func _hide() -> void:
	if visible:
		visible = false
		_shown = {}
