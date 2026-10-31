extends SceneTree
## How long the big test town takes to open in the game (the loading
## screen, start to finish), the worst frame of the game's own first ten
## seconds open, and then with the Ground view turned on: how long its
## survey (GroundMap.survey_step, a few milliseconds a frame) and drawing
## take, and the most one frame of each cost.
##
## Run headless only, with HOME set to a scratch folder:
##   HOME=/tmp/x godot --headless -s tools/ground_load_bench.gd [-- --size=big --runs=3]
## Writes the town to a throwaway save in the user folder first.

const SAVE := "user://ground_load_bench.city"

var _main: Node
var _size := "big"
var _runs := 3
var _run := 0
var _t0 := 0
var _open_ms := []
var _survey_ms := []
var _survey_frames := []
var _survey_max := []
var _draw_ms := []
var _draw_max := []
var _worst_open := []
var _worst := 0.0
var _last := 0
var _view: GroundView
var _phase := 0  # 0 start a run, 1 loading, 2 surveying
var _refused := false


func _initialize() -> void:
	if not _throwaway_home():
		printerr("ground_load_bench: refusing to run: the user folder is %s. Set HOME to a scratch folder." % OS.get_user_data_dir())
		_refused = true
		quit(1)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			_size = a.trim_prefix("--size=")
		elif a.begins_with("--runs="):
			_runs = int(a.trim_prefix("--runs="))
	var sim := CitySim.new()
	sim.county_rail = true
	PerfTown.build(sim, _size)
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(sim.to_dict()))
	f.close()
	print("ground_load_bench: %s town saved: %d buildings" % [_size, sim.buildings.size()])


static func _throwaway_home() -> bool:
	var dir := OS.get_user_data_dir().replace("\\", "/")
	for p in ["/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/"]:
		if dir.begins_with(p):
			return true
	return "/scratchpad/" in dir or "/scratch/" in dir


func _process(_delta: float) -> bool:
	if _refused:
		return true
	match _phase:
		0:
			if _run >= _runs:
				_report()
				return true
			root.get_node("/root/Session").save_path = SAVE
			_t0 = Time.get_ticks_msec()
			_main = load("res://scenes/main.tscn").instantiate()
			root.add_child(_main)
			_phase = 1
		1:
			if _main.loading:
				return false
			_open_ms.append(Time.get_ticks_msec() - _t0)
			_t0 = Time.get_ticks_msec()
			_last = Time.get_ticks_usec()
			_worst = 0.0
			_phase = 3
		3:
			# The game's own frames for its first ten seconds open.
			var now := Time.get_ticks_usec()
			_worst = maxf(_worst, (now - _last) / 1000.0)
			_last = now
			if Time.get_ticks_msec() - _t0 < 10_000:
				return false
			_worst_open.append(_worst)
			_view = null
			for c in _main.get_children():
				if c is GroundView:
					_view = c
			if _view == null:
				_phase = 4
				return false
			_view.set_on(true)  # as Views > Taken ground does
			_t0 = Time.get_ticks_msec()
			_phase = 2
		2:
			var g: GroundMap = _main.sim.ground
			var view: GroundView = _view
			if (not g.surveyed() or view._building or view.pieces_drawn == 0) and Time.get_ticks_msec() - _t0 < 300_000:
				return false
			_survey_ms.append(g.survey_ms)
			_survey_frames.append(int(g.survey_frames))
			_survey_max.append(float(g.survey_max_ms))
			_draw_ms.append(Time.get_ticks_msec() - _t0)
			_draw_max.append(float(view.max_step_ms))
			view.set_on(false)
			_phase = 4
		4:
			_main.queue_free()
			_main = null
			_run += 1
			_phase = 0
	return false


func _report() -> void:
	print("ground_load_bench: opening the %s town (ms, each run): %s" % [_size, str(_open_ms)])
	print("ground_load_bench: worst frame in the first 10 s open (ms, whole frame): %s" % str(_worst_open))
	if not _survey_ms.is_empty():
		print("ground_load_bench: Ground view on: survey (ms) %s over %s frames, its worst frame (ms) %s" % [
			str(_survey_ms), str(_survey_frames), str(_survey_max)])
		print("ground_load_bench: Ground view on to first drawing (ms) %s, the drawing's worst frame (ms) %s" % [
			str(_draw_ms), str(_draw_max)])


func _finalize() -> void:
	if not _refused and FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
