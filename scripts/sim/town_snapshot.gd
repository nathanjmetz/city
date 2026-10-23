class_name TownSnapshot
extends RefCounted
## Saves a whole town a few parts at a time over several frames, so a big
## town's full copy (about half a second all at once) never freezes the
## game. The town holds still until it's done (CitySim.hold: no ticks, and
## commands wait), so the parts agree with each other. Each part is turned
## into bytes as it is taken, so later changes can't reach it.

## Main-thread time per frame, in milliseconds.
const BUDGET_MS := 12.0
## The key a sliced town is saved under (see join).
const PARTS := "town_parts"

var sim: CitySim
var parts := {}  # key -> var_to_bytes of that part
var _steps := []
var _i := 0
var _done := false


func _init(s: CitySim) -> void:
	sim = s
	sim.vegetation.update(sim)  # land cleared since the last tick counts
	_steps = sim.save_steps(false)
	sim.hold()


## Takes some more parts; true once the town is all taken (then bytes()).
func step(budget_ms := BUDGET_MS) -> bool:
	if _done:
		return true
	# (INF, from finish, would overflow to a deadline in the past.)
	var end := Time.get_ticks_usec() + int(minf(budget_ms, 1e9) * 1000.0)
	while _i < _steps.size():
		var st: Array = _steps[_i]
		_i += 1
		parts[st[0]] = var_to_bytes(st[1].call())
		if Time.get_ticks_usec() >= end:
			break
	if _i >= _steps.size():
		_done = true
		sim.release()
	return _done


## Takes the rest at once (leaving can't wait).
func finish() -> void:
	step(INF)


func is_done() -> bool:
	return _done


## The whole town as one byte string, for RegionServer.pack_bytes or a save.
func bytes() -> PackedByteArray:
	return var_to_bytes({PARTS: parts})


## A town saved by a snapshot, back as the usual to_dict data; anything
## else comes back as it is.
static func join(d: Dictionary) -> Dictionary:
	if d.size() != 1 or not d.has(PARTS) or not d[PARTS] is Dictionary:
		return d
	var out := {}
	for key in d[PARTS]:
		var b = d[PARTS][key]
		if b is PackedByteArray:
			out[key] = bytes_to_var(b)
	return out
