class_name NearPeople
extends Node3D
## Ready-made people (MakeHuman, art/people/*.glb) for the town's walkers
## nearest the camera, on the desktop app only (Nathan, 2026-10-25: lean on
## ready-made art for the desktop download, keep the browser light). Each
## one plays its walk in step with the walker it stands in for; WalkerView
## skips those walkers. Farther off, and in the browser, the code-grown
## figures carry on as before.

const FOLDER := "res://art/people"
const NEAR := 30.0        # metres (times GraphicsQuality.detail)
const MAX := 24           # at most this many at once
const WALK_SPEED := 1.4   # m/s the baked walk cycle is made for

## Walker ids drawn here this frame (WalkerView leaves them out).
static var drawn := {}

var traffic: TrafficSim
var tick_fraction: Callable
var _scenes: Array[PackedScene] = []
var _pool := []           # [{node, player, walker}]


## Whether ready-made people can be drawn here: the desktop app, with the
## art present (the browser export leaves art/people out).
static func available() -> bool:
	return not OS.has_feature("web") and DirAccess.dir_exists_absolute(FOLDER)


func setup(t: TrafficSim, frac: Callable) -> void:
	traffic = t
	tick_fraction = frac
	for f in DirAccess.get_files_at(FOLDER):
		if f.ends_with(".glb"):
			var s := load(FOLDER + "/" + f) as PackedScene
			if s != null:
				_scenes.append(s)


func _person(i: int) -> Dictionary:
	while _pool.size() <= i:
		var node := _scenes[_pool.size() % _scenes.size()].instantiate() as Node3D
		add_child(node)
		var players := node.find_children("*", "AnimationPlayer", true, false)
		var player: AnimationPlayer = players[0] if not players.is_empty() else null
		if player != null and not player.get_animation_list().is_empty():
			var anim := player.get_animation(player.get_animation_list()[0])
			anim.loop_mode = Animation.LOOP_LINEAR
			player.play(player.get_animation_list()[0])
		_pool.append({"node": node, "player": player, "walker": -1})
	return _pool[i]


func _process(_delta: float) -> void:
	drawn.clear()
	if traffic == null or _scenes.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	Terrain.shift = Terrain.shift_for(self)
	var eye := cam.global_position
	var reach := NEAR * GraphicsQuality.detail
	var frac: float = tick_fraction.call()
	var near := []
	for w in traffic.walkers:
		var pose := traffic.walker_pose(w, frac)
		var p: Vector3 = Terrain.stand(pose[0])
		var d := p.distance_to(eye)
		if d < reach:
			near.append([d, w, pose, p])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var n := mini(near.size(), MAX)
	for i in n:
		var w: Dictionary = near[i][1]
		var pose: Array = near[i][2]
		var p: Vector3 = near[i][3]
		# The same walker keeps the same person while it stays near.
		var slot := -1
		for k in _pool.size():
			if _pool[k].walker == int(w.id):
				slot = k
				break
		if slot == -1:
			for k in _pool.size():
				if _pool[k].walker == -1 or not drawn.has(_pool[k].walker) and k >= i:
					slot = k
					break
		if slot == -1:
			slot = _pool.size()
		var e := _person(slot)
		e.walker = int(w.id)
		var dir: Vector3 = pose[1]
		if dir.length() < 0.5:
			dir = Vector3.FORWARD
		var node: Node3D = e.node
		node.visible = true
		# The model faces +Z; turn it to walk along `dir`.
		node.global_transform = Transform3D(Basis.looking_at(-Vector3(dir.x, 0.0, dir.z).normalized(), Vector3.UP), p)
		if e.player != null:
			e.player.speed_scale = float(w.get("v", WALK_SPEED)) / WALK_SPEED
		drawn[int(w.id)] = true
	for k in _pool.size():
		if not drawn.has(_pool[k].walker):
			_pool[k].node.visible = false
			_pool[k].walker = -1
	Terrain.shift = Vector2.ZERO
