class_name FarmHerdJob
extends RefCounted
## Places every beef herd grazing its pasture, one cow per 2 acres
## (Livestock), a few hundred cows at a time (FarmView runs it a few
## milliseconds a frame). First it notes each herd's pasture (its
## signature: if the herds are as they were, nothing is done), then works
## out where each cow stands, then fills the MultiMesh, which replaces the
## old herd only when whole.

## Most cows drawn at once, across every herd.
const MAX_COWS := 3000
## Angus black, Hereford red and the odd black baldy: the beef breeds on
## southern Indiana pasture.
const COW_COLORS := [Color("#1c1a19"), Color("#1c1a19"), Color("#6e3420"), Color("#2a2522")]
## Cows placed or filled in a step.
const SLICE := 150

var signature: Array = []
var changed := true
var multimesh: MultiMesh  # null when there are no cows
var done := false

var _herds := []  # [id, {pos, dir}, grass cells, head]
var _i := 0
var _n := 0  # cows placed so far in this herd
var _cap := 0  # cows this herd gets
var _spots := []
var _phase := 0  # 0 place the cows, 1 fill the multimesh


func _init(sim: CitySim, previous: Array) -> void:
	for id in sim.farms.farms:
		var f: Dictionary = sim.farms.farms[id]
		if Livestock.kind(f) != "cattle":
			continue
		var grass := []
		for c in f.cells:
			if CropPlan.crop_at(f, c) == "pasture":
				grass.append(c)
		if grass.is_empty():
			continue
		_herds.append([id, {"pos": f.pos, "dir": f.dir}, grass, Livestock.head(f)])
	signature = _herds
	if signature == previous:
		changed = false
		done = true


## Works until `deadline` (Time.get_ticks_usec) or done; true when done.
func step(deadline: int) -> bool:
	while not done:
		if _phase == 0:
			_place()
		else:
			_fill()
		if Time.get_ticks_usec() >= deadline:
			break
	return done


func _place() -> void:
	if _i >= _herds.size():
		_phase = 1
		_i = 0
		return
	var h: Array = _herds[_i]
	var id: Variant = h[0]
	var f: Dictionary = h[1]
	var grass: Array = h[2]
	if _n == 0:
		_cap = mini(int(h[3]), MAX_COWS - _spots.size())
	var n := _cap
	var first := _n
	var stop := mini(first + SLICE, n)
	for i in range(first, stop):
		var c: Vector2i = grass[int(Farms._hash01(Vector2i(int(id), i), 31) * grass.size()) % grass.size()]
		var corners := Farms.cell_corners(f, c)
		var u := Farms._hash01(c + Vector2i(i, 0), 37)
		var v := Farms._hash01(c + Vector2i(0, i), 41)
		var p := corners[0].lerp(corners[1], 0.1 + 0.8 * u).lerp(corners[3].lerp(corners[2], 0.1 + 0.8 * u), 0.1 + 0.8 * v)
		_spots.append([Vector3(p.x, Terrain.ground_y(p.x, p.y), p.y), Farms._hash01(c + Vector2i(i, i), 43)])
	_n = stop
	if stop >= n:
		_i += 1
		_n = 0


func _fill() -> void:
	if multimesh == null:
		if _spots.is_empty():
			done = true
			return
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = FarmView._cow_mesh()
		multimesh.instance_count = _spots.size()
	var stop := mini(_i + SLICE, _spots.size())
	for i in range(_i, stop):
		var h: float = _spots[i][1]
		multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, h * TAU), _spots[i][0]))
		multimesh.set_instance_color(i, COW_COLORS[int(h * 97.0) % COW_COLORS.size()])
	_i = stop
	done = _i >= _spots.size()
