class_name InfoPanel
extends PanelContainer
## The selected-object panel (Cities: Skylines 2's info panel): docked to the
## left edge under the top bar, it shows what the selected thing is, whether
## it's working, its numbers and any problem, refreshed as the city runs.

const GOOD := Brand.POSITIVE
const BAD := Brand.CRITICAL

var sim: CitySim
var tool: SelectTool

var _icon_slot := Control.new()
var _title := UiStyle.label("", 16)
var _kind := UiStyle.label("", 11, UiStyle.MUTED)
var _status := UiStyle.label("", 13)
var _rows := GridContainer.new()
var _problems := VBoxContainer.new()
## Buttons for what the selection can do (upgrade, demolish), when it says.
var _actions := VBoxContainer.new()
var _action_key := ""
var _icon_name := ""
var _guide: LeaderGuide
var _guide_for := {}
var _wait := 0.0


func setup(s: CitySim, t: SelectTool) -> void:
	sim = s
	tool = t
	tool.selected.connect(func(_sel): _refresh())


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.dock(false))
	custom_minimum_size = Vector2(260, 0)
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	_icon_slot.custom_minimum_size = Vector2(28, 28)
	head.add_child(_icon_slot)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(_kind)
	names.add_child(_title)
	head.add_child(names)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(func(): tool.select({}))
	head.add_child(close)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 12)
	_rows.add_theme_constant_override("v_separation", 2)
	col.add_child(_rows)
	_problems.add_theme_constant_override("separation", 2)
	col.add_child(_problems)
	_actions.add_theme_constant_override("separation", 4)
	col.add_child(_actions)


func _process(delta: float) -> void:
	if not visible:
		return
	_wait -= delta
	if _wait <= 0.0:
		_refresh()


func _refresh() -> void:
	_wait = 0.5
	var d := Inspect.describe(sim, tool.selection)
	visible = not d.is_empty()
	if d.is_empty():
		return
	if d.icon != _icon_name:
		_icon_name = d.icon
		for c in _icon_slot.get_children():
			_icon_slot.remove_child(c)
			c.queue_free()
		var ic := Icon.new(d.icon, 28)
		ic.size = Vector2(28, 28)
		_icon_slot.add_child(ic)
	_title.text = d.title
	_kind.text = d.kind.to_upper()
	_status.text = "●  " + d.status
	_status.add_theme_color_override("font_color", GOOD if d.ok else BAD)
	var labels := _rows.get_children()
	if labels.size() != d.rows.size() * 2:
		for c in labels:
			_rows.remove_child(c)
			c.queue_free()
		for r in d.rows:
			_rows.add_child(UiStyle.label("", 12, UiStyle.MUTED))
			var v := UiStyle.label("", 12)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_rows.add_child(v)
		labels = _rows.get_children()
	for i in d.rows.size():
		labels[i * 2].text = d.rows[i][0]
		labels[i * 2 + 1].text = d.rows[i][1]
	for c in _problems.get_children():
		_problems.remove_child(c)
		c.queue_free()
	for p in d.problems:
		var l := UiStyle.label("⚠  " + p, 12, Brand.WARNING)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(236, 0)
		_problems.add_child(l)
	_show_actions(d.get("actions", []))
	_sync_guide()
	reset_size()


func _show_actions(actions: Array) -> void:
	var key := str(actions)
	if key == _action_key:
		return
	_action_key = key
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	for a in actions:
		var b := Button.new()
		b.text = a.label
		b.disabled = not a.get("enabled", true)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(236, 0)
		var cmd: Dictionary = a.cmd
		b.pressed.connect(func():
			sim.apply(cmd)
			_refresh())
		_actions.add_child(b)


## Hubs with a leader get your word to them at the bottom (see LeaderGuide).
func _sync_guide() -> void:
	if tool.selection == _guide_for:
		return
	_guide_for = tool.selection.duplicate()
	if _guide:
		_guide.queue_free()
		_guide = null
	if LeaderGuide.takes(sim, tool.selection):
		_guide = LeaderGuide.new()
		_guide.setup(sim, str(tool.selection.type), int(tool.selection.id))
		get_child(0).add_child(_guide)
