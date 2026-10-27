class_name StatChart
extends Control
## A small line (or bar) chart for the stats panel, in the style of Cities:
## Skylines 2's statistics graph: a few soft grid lines with their values,
## the dates under the ends, and a readout that follows the mouse with every
## line's value at that moment.

## [{name, color, pts: [[tick, value], ...], on}]
var series := []
## Formats a value for the grid and the readout.
var fmt: Callable = func(v: float) -> String: return str(roundi(v))
## Optional: formats a grid value to show `step` (v, step), used when `fmt`
## would print two grid lines the same.
var fine: Callable
## Draws bars (one per point) instead of lines.
var bars := false
## Dates under the chart show the day too (short spans).
var hourly := false
## The town's CitySim.calendar_of, so sample ticks read as its dates.
var calendar_of: Callable = func(t: int) -> int: return t
## Always show 0 at the bottom (counts); off lets money go negative.
var from_zero := true

var _hover := -1.0  # mouse x, or -1
var _font: Font = Brand.ui(500)

const PAD_L := 54.0
const PAD_B := 16.0
const PAD_T := 6.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 150)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func():
		_hover = -1.0
		queue_redraw())


func set_series(s: Array) -> void:
	series = s
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = (event as InputEventMouseMotion).position.x
		queue_redraw()


## "Mar 2029", or "Mar 5, 2029" for short spans, for a calendar tick
## (CitySim.calendar_of).
static func when(cal: int, with_day := false) -> String:
	var m: String = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][Seasons.month(cal) - 1]
	if with_day:
		return "%s %d, %d" % [m, Seasons.day(cal), Families.calendar(Seasons.year(cal))]
	return "%s %d" % [m, Families.calendar(Seasons.year(cal))]


func _shown() -> Array:
	return series.filter(func(s): return s.get("on", true) and s.pts.size() > 0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Brand.SURFACE_SUNKEN)
	var shown := _shown()
	var plot := Rect2(PAD_L, PAD_T, size.x - PAD_L - 6.0, size.y - PAD_T - PAD_B)
	if shown.is_empty() or shown[0].pts.size() < (1 if bars else 2):
		_text(Vector2(size.x * 0.5, size.y * 0.5), "Not much history yet. Check back in a game hour.", Brand.INK_FAINT, 12, true)
		return
	var t0 := INF
	var t1 := -INF
	var lo := 0.0 if from_zero else INF
	var hi := -INF
	for s in shown:
		for p in s.pts:
			t0 = minf(t0, p[0])
			t1 = maxf(t1, p[0])
			lo = minf(lo, float(p[1]))
			hi = maxf(hi, float(p[1]))
	if hi - lo < 0.0001:
		hi = lo + maxf(absf(lo) * 0.1, 3.0)
	hi += (hi - lo) * 0.08
	if not from_zero:
		lo -= (hi - lo) * 0.05
	if t1 <= t0:
		t1 = t0 + 1.0
	var X := func(t: float) -> float: return plot.position.x + (t - t0) / (t1 - t0) * plot.size.x
	var Y := func(v: float) -> float: return plot.end.y - (v - lo) / (hi - lo) * plot.size.y
	# Grid: lines at round values (about three), plus zero when the chart
	# crosses it.
	var step := _nice((hi - lo) / 3.0)
	var g := ceilf(lo / step) * step
	var grid := []
	while g <= hi:
		grid.append(g)
		g += step
	# Labels that never repeat (the critic, 2026-10-26: both grid lines of a
	# money chart said "$1.49M", which read as a flat line): more decimals
	# when two would print the same, and any repeat left unlabeled.
	var labels := grid.map(func(v): return fmt.call(v))
	if _repeats(labels) and fine.is_valid():
		labels = grid.map(func(v): return fine.call(v, step))
	var last := ""
	for i in grid.size():
		var y: float = Y.call(grid[i])
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(Brand.LINE, 0.6), 1.0)
		if labels[i] != last:
			_text(Vector2(PAD_L - 6.0, y + 4.0), labels[i], Brand.INK_MUTED, 11, false, true)
		last = labels[i]
	if lo < 0.0 and hi > 0.0:
		var yz: float = Y.call(0.0)
		draw_line(Vector2(plot.position.x, yz), Vector2(plot.end.x, yz), Brand.LINE_STRONG, 1.0)
	_text(Vector2(plot.position.x, size.y - 3.0), when(calendar_of.call(int(t0)), hourly), Brand.INK_MUTED, 11)
	_text(Vector2(plot.end.x, size.y - 3.0), "Now", Brand.INK_MUTED, 11, false, true)
	# The lines (or bars).
	for si in shown.size():
		var s: Dictionary = shown[si]
		var col: Color = s.color
		if bars:
			var n: int = s.pts.size()
			var w := maxf(plot.size.x / n / shown.size() - 2.0, 1.0)
			for i in n:
				var p: Array = s.pts[i]
				var x := plot.position.x + (i + 0.5) / n * plot.size.x + (si - (shown.size() - 1) * 0.5) * (w + 1.0)
				var y0: float = Y.call(maxf(lo, 0.0))
				var y1: float = Y.call(float(p[1]))
				draw_rect(Rect2(x - w * 0.5, minf(y0, y1), w, absf(y1 - y0)), Color(col, 0.85))
			continue
		# Lines that sit on the same values draw a pixel or two apart, so
		# one never hides another (Shops and Industry both at 0% hid Shops).
		var nudge := (si - (shown.size() - 1) * 0.5) * 2.0
		var line := PackedVector2Array()
		for p in s.pts:
			line.append(Vector2(X.call(float(p[0])), Y.call(float(p[1])) + nudge))
		if si == 0 and shown.size() == 1:
			# One line gets a soft fill under it.
			var fill := line.duplicate()
			fill.append(Vector2(line[-1].x, plot.end.y))
			fill.append(Vector2(line[0].x, plot.end.y))
			draw_colored_polygon(fill, Color(col, 0.14))
		draw_polyline(line, col, 2.0, true)
	# The readout under the mouse.
	if _hover < plot.position.x or _hover > plot.end.x:
		return
	var ref: Array = shown[0].pts
	var idx := 0
	if bars:
		idx = clampi(int((_hover - plot.position.x) / plot.size.x * ref.size()), 0, ref.size() - 1)
	else:
		var best := INF
		for i in ref.size():
			var d := absf(X.call(float(ref[i][0])) - _hover)
			if d < best:
				best = d
				idx = i
	var hx: float = plot.position.x + (idx + 0.5) / ref.size() * plot.size.x if bars else X.call(float(ref[idx][0]))
	draw_line(Vector2(hx, plot.position.y), Vector2(hx, plot.end.y), Brand.INK_MUTED, 1.0)
	var lines := [_label_of(shown[0], idx)]
	for s in shown:
		if idx < s.pts.size():
			var v := float(s.pts[idx][1])
			if not bars:
				draw_circle(Vector2(hx, Y.call(v)), 3.5, s.color)
			lines.append([s.name, fmt.call(v), s.color])
	var box_w := 150.0
	var box_h := 16.0 * lines.size() + 6.0
	var bx := hx + 8.0 if hx + 8.0 + box_w < size.x else hx - 8.0 - box_w
	draw_rect(Rect2(bx, plot.position.y, box_w, box_h), Color(Brand.SURFACE, 0.95))
	draw_rect(Rect2(bx, plot.position.y, box_w, box_h), Brand.LINE, false, 1.0)
	_text(Vector2(bx + 6.0, plot.position.y + 14.0), lines[0], Brand.INK_MUTED, 11)
	for i in range(1, lines.size()):
		var y := plot.position.y + 14.0 + 16.0 * i
		draw_circle(Vector2(bx + 9.0, y - 4.0), 3.0, lines[i][2])
		_text(Vector2(bx + 16.0, y), lines[i][0], Brand.INK, 11)
		_text(Vector2(bx + box_w - 6.0, y), lines[i][1], Brand.INK, 11, false, true)


static func _repeats(labels: Array) -> bool:
	for i in range(1, labels.size()):
		if labels[i] == labels[i - 1]:
			return true
	return false


## A round step near `x`: 1, 2 or 5 times a power of ten.
static func _nice(x: float) -> float:
	if x <= 0.0:
		return 1.0
	var p := pow(10.0, floorf(log(x) / log(10.0)))
	for m in [1.0, 2.0, 5.0, 10.0]:
		if x <= m * p:
			return maxf(m * p, 1.0)
	return 10.0 * p


## The date (or the point's own label, for bars by year) at a point.
func _label_of(s: Dictionary, idx: int) -> String:
	var p: Array = s.pts[idx]
	if p.size() > 2:
		return str(p[2])
	return when(calendar_of.call(int(p[0])), hourly)


func _text(at: Vector2, s: String, col: Color, px: int, center := false, right := false) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var x := at.x - (w * 0.5 if center else (w if right else 0.0))
	draw_string(_font, Vector2(x, at.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
