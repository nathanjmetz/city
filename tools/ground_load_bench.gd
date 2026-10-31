extends SceneTree
## How long the big test town takes to open in the game (the loading
## screen, start to finish), and once it's open, how long the ground map's
## survey (GroundMap.survey_step, a few milliseconds a frame) takes to
## finish and the most one frame of it cost.
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
			_phase = 2
		2:
			var g = _main.sim.get("ground")
			var surveyed: bool = g == null or not g.has_method("surveyed") or g.surveyed()
			if not surveyed and Time.get_ticks_msec() - _t0 < 300_000:
				return false
			if g != null and g.has_method("surveyed"):
				_survey_ms.append(Time.get_ticks_msec() - _t0)
				_survey_frames.append(int(g.survey_frames))
				_survey_max.append(float(g.survey_max_ms))
			_main.queue_free()
			_main = null
			_run += 1
			_phase = 0
	return false


func _report() -> void:
	print("ground_load_bench: opening the %s town (ms, each run): %s" % [_size, str(_open_ms)])
	if not _survey_ms.is_empty():
		print("ground_load_bench: survey after opening (ms): %s, frames %s, most in one frame (ms) %s" % [
			str(_survey_ms), str(_survey_frames), str(_survey_max)])
	else:
		print("ground_load_bench: no ground survey in this build")


func _finalize() -> void:
	if not _refused and FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
