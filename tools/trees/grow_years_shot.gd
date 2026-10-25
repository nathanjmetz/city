extends SceneTree
## Trees growing over the game's years, in the real game: a small new town
## is built (its yard and street trees go in as nursery saplings), then the
## game clock runs on for real, year by year, with pictures near and far
## at each stop. Every stop is in July, so only the years differ.
## Run in a window:
##   godot --resolution 1600x900 -s tools/trees/grow_years_shot.gd -- SAVE OUT_DIR [YEARS,...]
## SAVE is a throwaway save path, never a real town (it is cleared).
## YEARS defaults to 0,10,25.

## [name, yaw, pitch, distance, look-at offset]
## (The town's homes are in the corners; shops along the middle rows.)
const VIEWS := [["near", 225.0, 18.0, 75.0, Vector3(-190, 0, -190)], ["far", 225.0, 30.0, 300.0, Vector3(-160, 0, -160)]]
const TICKS_PER_FRAME := 6000
const SETTLE := 240

var _main: Node
var _frames := 0
var _cam: CityCamera
var _out := ""
var _years := [0, 10, 25]
var _stop := 0
var _target := 0
var _start_tick := 0
var _view := 0
var _view_frames := 0
var _state := "load"
var _t0 := 0


func _process(_delta: float) -> bool:
	var a := OS.get_cmdline_user_args()
	if _main == null:
		root.get_node("/root/Session").save_path = a[0]
		_out = a[1]
		if a.size() > 2:
			_years = Array(a[2].split(",")).map(func(s): return int(s))
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	if _main.loading:
		return false
	_frames += 1
	var sim: CitySim = _main.sim
	match _state:
		"load":
			if _frames < 3:
				return false
			sim.apply({"type": "clear"})
			PerfTown.build(sim, "small")
			sim.require_utilities = false
			# Build out, then on to July.
			for i in 3000:
				sim.tick()
			while Seasons.month(sim.tick_count) != 7:
				sim.tick()
			_start_tick = sim.tick_count
			DayNight.seasons_on = true
			for c in _main.get_children():
				if c is CityCamera:
					_cam = c
				if c is CanvasLayer:
					c.visible = false
			for n in _main.find_children("*", "FirstTownTour", true, false):
				n.stop()
			_main.set_speed(0)
			print("YEARS built %d people, %d buildings" % [sim.stats.population, sim.buildings.size()])
			_target = _start_tick
			_state = "tick"
		"tick":
			# Run the clock on to this stop, a slice a frame.
			var n := mini(TICKS_PER_FRAME, _target - sim.tick_count)
			for i in n:
				sim.tick()
			if sim.tick_count >= _target:
				_state = "shoot"
				_view = 0
				_view_frames = 0
				_aim()
		"shoot":
			_view_frames += 1
			if _view_frames == SETTLE:
				var v: Array = VIEWS[_view]
				var name := "years_%02d_%s" % [_years[_stop], v[0]]
				root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
				print("YEARS shot %s at tick %d (%s)" % [name, sim.tick_count, str(sim.clock())])
				_view += 1
				_view_frames = 0
				if _view < VIEWS.size():
					_aim()
				else:
					_stop += 1
					if _stop >= _years.size():
						quit()
						return true
					_target = _start_tick + int(_years[_stop]) * Seasons.TICKS_PER_DAY * 12
					_state = "tick"
	return false


func _aim() -> void:
	var v: Array = VIEWS[_view]
	_cam.look_at_point(Terrain.lift(v[4]))
	_cam.set_view(deg_to_rad(v[1]), deg_to_rad(v[2]), v[3])
