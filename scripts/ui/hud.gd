class_name Hud
extends CanvasLayer
## Toolbar along the bottom, tips and town stats in the corners.

var tool: RoadTool
var network: RoadNetwork
var houses: HouseSpawner

var _buttons := {}
var _hint := Label.new()
var _stats := Label.new()


func setup(t: RoadTool, net: RoadNetwork, h: HouseSpawner) -> void:
	tool = t
	network = net
	houses = h


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position.y -= 16
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	for entry in [
		[RoadTool.Mode.STRAIGHT, "Straight road  [1]"],
		[RoadTool.Mode.CURVED, "Curved road  [2]"],
		[RoadTool.Mode.BULLDOZE, "Bulldoze  [3]"],
	]:
		var b := Button.new()
		b.text = entry[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 40)
		var m: int = entry[0]
		b.pressed.connect(func(): tool.set_mode(m))
		row.add_child(b)
		_buttons[m] = b
	var clear := Button.new()
	clear.text = "Clear map"
	clear.focus_mode = Control.FOCUS_NONE
	clear.custom_minimum_size = Vector2(110, 40)
	clear.pressed.connect(network.clear)
	row.add_child(clear)

	var tips := Label.new()
	tips.text = "WASD move   Q/E rotate   R/F tilt   Scroll zoom   Middle drag rotate"
	tips.position = Vector2(16, 12)
	_style(tips)
	root.add_child(tips)

	_hint.position = Vector2(16, 40)
	_style(_hint)
	_hint.add_theme_font_size_override("font_size", 20)
	root.add_child(_hint)

	_stats.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stats.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stats.position = Vector2(-16, 12)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(_stats)
	root.add_child(_stats)

	tool.mode_changed.connect(_on_mode)
	tool.hint_changed.connect(func(text): _hint.text = text)
	network.changed.connect(_update_stats)
	houses.house_count_changed.connect(func(_n): _update_stats())
	_on_mode(tool.mode)
	_update_stats()


func _on_mode(mode: int) -> void:
	for m in _buttons:
		_buttons[m].set_pressed_no_signal(m == mode)


func _update_stats() -> void:
	_stats.text = "Roads: %.2f km\nHouses: %d" % [network.total_length() / 1000.0, houses.count()]


static func _style(l: Label) -> void:
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_font_size_override("font_size", 16)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
