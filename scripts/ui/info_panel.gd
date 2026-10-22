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
## The one lever a bus depot has: the city's monthly subsidy.
var _subsidy := HBoxContainer.new()
var _subsidy_value := UiStyle.label("", 12)
var _subsidy_for := -1
var _log := VBoxContainer.new()
var _icon_name := ""
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
	_subsidy.add_theme_constant_override("separation", 6)
	var lab := UiStyle.label("City funding", 12, UiStyle.MUTED)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subsidy.add_child(lab)
	for step in [-1, 1]:
		var b := Button.new()
		b.text = "−" if step < 0 else "+"
		b.custom_minimum_size = Vector2(26, 22)
		b.tooltip_text = "Less funding from the city" if step < 0 else "More funding from the city"
		b.pressed.connect(func(): _nudge_subsidy(step))
		_subsidy.add_child(b)
		if step < 0:
			_subsidy_value.custom_minimum_size = Vector2(84, 0)
			_subsidy_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_subsidy.add_child(_subsidy_value)
	_subsidy.visible = false
	col.add_child(_subsidy)
	_log.add_theme_constant_override("separation", 1)
	col.add_child(_log)


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
	_subsidy.visible = d.has("subsidy")
	if _subsidy.visible:
		_subsidy_for = int(d.subsidy.id)
		var lv: Array = Balance.BUS_FUNDING_LEVELS[_level(int(d.subsidy.amount))]
		_subsidy_value.text = lv[0]
		_subsidy_value.tooltip_text = "$%s a month" % CitySim.money_text(int(d.subsidy.amount))
		_subsidy_value.mouse_filter = Control.MOUSE_FILTER_PASS
	# What the hub decided lately, and why.
	for c in _log.get_children():
		_log.remove_child(c)
		c.queue_free()
	for line in d.get("log", []):
		var l := UiStyle.label("·  " + line, 11, UiStyle.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(236, 0)
		_log.add_child(l)
	reset_size()


func _nudge_subsidy(step: int) -> void:
	var b: Dictionary = sim.services.buildings.get(_subsidy_for, {})
	if b.is_empty():
		return
	var i := clampi(_level(int(b.get("subsidy", 0))) + step, 0, Balance.BUS_FUNDING_LEVELS.size() - 1)
	sim.apply({"type": "set_bus_subsidy", "id": _subsidy_for, "amount": Balance.BUS_FUNDING_LEVELS[i][1]})
	_refresh()


## The funding level nearest a monthly amount.
static func _level(amount: int) -> int:
	var best := 0
	for i in Balance.BUS_FUNDING_LEVELS.size():
		if absi(Balance.BUS_FUNDING_LEVELS[i][1] - amount) < absi(Balance.BUS_FUNDING_LEVELS[best][1] - amount):
			best = i
	return best
