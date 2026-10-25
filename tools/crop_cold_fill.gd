extends SceneTree
## The crop table's cold fills in a real game window: the first fill when a
## town loads (FarmView.setup: every row, then each farm field's row as
## the fields are drawn) and at a year turn (every plan new, the farms'
## new crops getting rows). Prints the work done in the frame each happens
## in and the frame times around it; any frame over 16 ms is a hitch.
## Run (desktop renderer, a real window):
##   godot -s tools/crop_cold_fill.gd --disable-vsync --max-fps 0

var _main: Node
var _fv: FarmView
var _frames := 0
var _phase := ""
var _phase_frames := 0
var _last := 0
var _times := PackedFloat32Array()
var _work := 0.0
var _out := []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _main.loading:
		_last = now
		return false
	_frames += 1
	if _frames == 2:
		_setup()
	if _phase != "":
		_phase_frames += 1
		_times.append((now - _last) / 1000.0)
		if _phase_frames == 90:
			_finish()
	elif _frames == 120:
		_start("load")
	_last = now
	return false


func _setup() -> void:
	var sim: CitySim = _main.sim
	sim.apply({"type": "clear"})
	sim.economy.money = 20_000_000
	_main.set_speed(0)
	DayNight.seasons_on = true
	for c in _main.get_children():
		if c is FarmView:
			_fv = c
		if c is Hud:
			c.close_all()
	# Two farms a few years into their rotation, as tools/crop_bench.gd has.
	sim.apply({"type": "build_road", "start": [-1200, 0], "ctrl": [0, 0], "end": [1200, 0]})
	sim.apply({"type": "paint_farmland", "points": [[-1150, 30], [1150, 30], [1150, 1100], [-1150, 1100]]})
	sim.apply({"type": "place_farmhouse", "pos": [-500, 60], "dir": [0, -1], "crop": "corn"})
	sim.apply({"type": "place_farmhouse", "pos": [450, 60], "dir": [0, -1], "crop": "soybeans"})
	sim.farms.price = 1.1
	for i in 400:
		sim.farms.decide(sim.field_usable)
	for y in 3:
		sim.farms.year += 1
		sim.farms.decide(sim.field_usable)
	sim.tick_count = _tick_at(Seasons.year(sim.tick_count) * 12.0 - 2.5)  # October
	sim.farms_changed.emit()


## The tick when Seasons.months reaches `months`.
static func _tick_at(months: float) -> int:
	return ceili((months - Seasons.START_MONTH) * Seasons.TICKS_PER_DAY)


## Forget everything the table has worked out, as at a fresh start.
static func _cold() -> void:
	CropCalendar.clear_farm_rows()
	CropCalendar._plans.clear()
	CropCalendar._plans_year = -999
	CropCalendar._stamp.fill(Vector2(-1.0, -999.0))


func _start(phase: String) -> void:
	_phase = phase
	_phase_frames = 0
	_times = PackedFloat32Array()
	Perf.reset_window()
	var sim: CitySim = _main.sim
	var t := Time.get_ticks_usec()
	if phase == "load":
		# What FarmView.setup does when a town loads, in its parts.
		_cold()
		_fv._sync_date()
		CropCalendar.refresh(true)
		var t1 := Time.get_ticks_usec()
		for id in sim.farms.farms:
			for c in sim.farms.farms[id].cells:
				FarmView.slot_of(id, sim.farms.farms[id], c)
		var t2 := Time.get_ticks_usec()
		_fv._plants.fields_changed()
		var t3 := Time.get_ticks_usec()
		_fv._rebuild()
		_fv.finish_now()  # all at once, as a town that loads does (a change in play is spread over frames)
		var t5 := Time.get_ticks_usec()
		print("load parts: table %.1f ms, farm rows %.1f ms, plants' farm check %.1f ms, all of the farms' redraw (fields and farmsteads) %.1f ms" % [
			(t1 - t) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t5 - t3) / 1000.0])
		_work = (t2 - t) / 1000.0
		return
	else:
		# The year turns: the farms plan their new crops (the sim's part,
		# not timed) and the fields are redrawn; FarmView sees the new year
		# next frame and the table follows it.
		sim.farms.year += 1
		sim.farms.decide(sim.field_usable)
		sim.tick_count = _tick_at((Seasons.year(sim.tick_count)) * 12.0 + 0.02)
		t = Time.get_ticks_usec()
		sim.farms_changed.emit()
		var t1 := Time.get_ticks_usec()
		_fv._process(0.0)  # FarmView sees the new year (the table starts on it)
		print("year turn: the farms' redraw %.1f ms, then FarmView's first frame of the new year %.1f ms" % [
			(t1 - t) / 1000.0, (Time.get_ticks_usec() - t1) / 1000.0])
		_work = (Time.get_ticks_usec() - t1) / 1000.0
		return
	_work = (Time.get_ticks_usec() - t) / 1000.0


func _finish() -> void:
	var sorted := _times.duplicate()
	sorted.sort()
	var table: Dictionary = Perf.stats.get("frame.crop_table", {})
	var line := "%s: %.1f ms of crop work at the start; table after: worst %.2f ms a frame; frames: worst %.1f ms, median %.1f ms, over 16 ms: %d; farm rows %d" % [
		_phase, _work, table.get("max", 0.0), sorted[-1], sorted[sorted.size() / 2],
		Array(sorted).filter(func(x): return x > 16.0).size(), CropCalendar.farm_rows_used()]
	print(line)
	print("  first frames: ", Array(_times.slice(0, 8)).map(func(x): return snappedf(x, 0.1)))
	_out.append(line)
	if _phase == "load":
		_start("year")
	elif _phase == "year" and _out.size() < 4:
		_start("year")
	else:
		quit(0)
