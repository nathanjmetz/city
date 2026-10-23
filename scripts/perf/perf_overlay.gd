class_name PerfOverlay
extends CanvasLayer
## A hidden performance readout, toggled with F3: frame rate, what each
## system costs against its budget (PerfBudget), draw calls, triangles and
## memory. Green is fine, amber is near the budget, red is over it.

var _label: RichTextLabel
var _wait := 0.0


func _ready() -> void:
	layer = 120
	visible = false
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(6))
	panel.position = Vector2(8, 60)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size = Vector2(330, 0)
	_label.add_theme_font_size_override("normal_font_size", 11)
	_label.add_theme_font_override("normal_font", Brand.ui(500))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F3:
		visible = not visible
		_wait = 0.0
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 0.5
	_label.text = text()


static func text() -> String:
	var web := OS.has_feature("web")
	var where := "web" if web else "desktop"
	var out := PackedStringArray()
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	out.append("[b]%s fps[/b]  frame %.1f ms  (%s)" % [_paint(fps, PerfBudget.RENDER.fps[where], true),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, where])
	out.append("[b]Simulation[/b] ms per tick (avg / recent worst)")
	for key in PerfBudget.SIM:
		if Perf.stats.has(key):
			var s: Dictionary = Perf.stats[key]
			var b: Dictionary = PerfBudget.SIM[key]
			out.append("  %-15s %s / %s" % [key.trim_prefix("sim."), _paint(s.avg, b.per_tick), _paint(s.peak, b.max)])
	out.append("[b]Frame[/b] ms (avg / recent worst)")
	for key in PerfBudget.FRAME:
		if Perf.stats.has(key):
			var s: Dictionary = Perf.stats[key]
			var b: Dictionary = PerfBudget.FRAME[key]
			out.append("  %-15s %s / %s" % [key.trim_prefix("frame."), _paint(s.avg, b.avg), _paint(s.peak, b.max)])
	out.append("[b]Drawing[/b]")
	out.append("  draw calls  %s" % _paint(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), PerfBudget.RENDER.draw_calls[where]))
	out.append("  triangles   %s" % _paint(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), PerfBudget.RENDER.primitives[where]))
	out.append("  objects     %s" % _paint(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), PerfBudget.RENDER.objects[where]))
	out.append("  memory MB   %s" % _paint(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, PerfBudget.RENDER.memory_mb[where]))
	out.append("  nodes       %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for key in Perf.counts:
		out.append("  %-11s %d" % [key, Perf.counts[key]])
	return "\n".join(out)


## A number coloured by how it sits against its budget.
static func _paint(value: float, budget: float, higher_is_better := false) -> String:
	var g := ""
	if higher_is_better:
		g = "ok" if value >= budget else ("warn" if value >= budget * 0.8 else "over")
	else:
		g = PerfBudget.grade(value, budget)
	var col: String = {"ok": "#7fd6a6", "warn": "#f2c14e", "over": "#ff6b5b"}[g]
	var txt := ("%.2f" % value) if value < 100.0 else str(int(value))
	return "[color=%s]%s[/color]" % [col, txt]
