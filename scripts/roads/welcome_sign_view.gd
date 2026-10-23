class_name WelcomeSignView
extends Node3D
## "Welcome to ..." signs where the highway a town starts on reaches the
## edge of town, one facing each way in. Modelled on small-town Indiana
## welcome signs: a routed cedar panel on two 6x6 posts over a low brick
## planter, the town's name large, its nickname under it once it has earned
## one (Town heritage: "Corn Capital of Pike County"), and the year it was
## founded. The sign moves out as the town grows: it stands a little past
## the farthest building from the middle of town, as city-limit signs do.

const PANEL := Color("#5b3a22")
const LETTER := Color("#efe2bf")
const POST := Color("#6b5038")
const BRICK := Color("#8a3d2c")
const W := 3.6
const H := 1.8
const BOTTOM := 0.9
## The edge of town: this far past the farthest building, and never nearer
## the middle than MIN_REACH.
const PAST_EDGE := 60.0
const MIN_REACH := 220.0
const DRAW_RANGE := 400.0

var sim: CitySim
var _signs := []
var _key := []


func setup(s: CitySim) -> void:
	sim = s
	for sig in [sim.streets.changed, sim.nicknames.changed, sim.buildings_changed]:
		sig.connect(_sync)
	_sync.call_deferred()


## The town's own name, from its save.
func town_name() -> String:
	var session := get_node_or_null("/root/Session")
	var n := str(session.current_name) if session != null else ""
	return n if n != "" else "Our Town"


func _sync() -> void:
	var spots := _spots()
	var nick := str(sim.nicknames.current.get("text", ""))
	var key := [spots, nick, town_name()]
	if key == _key:
		return
	_key = key
	for n in _signs:
		n.queue_free()
	_signs.clear()
	var was := Terrain.shift
	Terrain.shift = Terrain.shift_for(self)
	for s in spots:
		var node := _sign(s[0], s[1], nick)
		add_child(node)
		_signs.append(node)
	Terrain.shift = was


## Where the signs go: [[position, heading into town]], one on each way out
## along the starting highway.
func _spots() -> Array:
	var center: Vector2 = sim.streets.main_at
	var reach := MIN_REACH
	for key in sim.buildings:
		var lot: Dictionary = sim.lots.get(key, {})
		if not lot.is_empty():
			reach = maxf(reach, Vector2(lot.front.x, lot.front.z).distance_to(center) + PAST_EDGE)
	reach = snappedf(reach, 20.0)
	var out := []
	for link in sim.region_links:
		var segs: Array = sim.network.segments_at(link)
		if segs.is_empty():
			continue
		var road := sim.streets.name_of(segs[0])
		# Walk the highway in from its far end until it comes within reach.
		var at := _point_at(road, link, center, reach)
		if not at.is_empty():
			out.append(at)
	return out


## The first point on the road named `road`, walking in from node `from`,
## within `reach` of the middle of town: [Vector2 there, Vector2 heading in].
func _point_at(road: String, from: int, center: Vector2, reach: float) -> Array:
	var node := from
	var seen := {}
	for _guard in 512:
		var next := -1
		for id in sim.network.segments_at(node):
			if seen.has(id) or sim.streets.name_of(id) != road:
				continue
			seen[id] = true
			var s: Dictionary = sim.network.segments[id]
			var pts := sim.network.sample_segment(id, 16)
			if s.b == node:
				pts.reverse()
			for i in range(1, pts.size()):
				var p := Vector2(pts[i].x, pts[i].z)
				if p.distance_to(center) <= reach:
					var q := Vector2(pts[i - 1].x, pts[i - 1].z)
					return [p, (p - q).normalized()]
			next = s.b if s.a == node else s.a
			break
		if next == -1:
			return []
		node = next
	return []


func _sign(at: Vector2, heading: Vector2, nick: String) -> Node3D:
	# On the right of the road for drivers coming in, past the shoulder,
	# facing them.
	var right := Vector2(-heading.y, heading.x)
	var p := at + right * (RoadStyle.right_of_way_half() + 2.5)
	var root := Node3D.new()
	root.position = Vector3(p.x, Terrain.ground_y(p.x, p.y), p.y)
	root.basis = Basis.looking_at(Vector3(-heading.x, 0, -heading.y), Vector3.UP)
	var b := CommercialBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		b._box("paint", Vector3(0.15, BOTTOM + H + 0.15, 0.15), Vector3(s * (W * 0.5 - 0.3), (BOTTOM + H + 0.15) * 0.5, 0.1), POST)
	b._box("paint", Vector3(W, H, 0.08), Vector3(0, BOTTOM + H * 0.5, 0), PANEL)
	b._box("paint", Vector3(W + 0.1, 0.1, 0.12), Vector3(0, BOTTOM + H + 0.05, 0), PANEL.darkened(0.3))
	# The brick planter under it, with flowers.
	b._box("brick", Vector3(W + 0.6, 0.45, 1.1), Vector3(0, 0.22, 0.3), BRICK)
	b._box("paint", Vector3(W + 0.4, 0.12, 0.9), Vector3(0, 0.5, 0.3), Color("#c2402f"))
	var mi := MeshInstance3D.new()
	mi.mesh = b._commit_house()
	mi.visibility_range_end = DRAW_RANGE
	root.add_child(mi)
	var face := Vector3(0, BOTTOM, -0.05)
	var n := Vector3(0, 0, -1)
	var lines := [["WELCOME TO", 0.12, 0.84, "franklin"], [town_name(), 0.36, 0.6, "serif"]]
	if nick != "":
		lines.append([nick, 0.11, 0.36, "script"])
	lines.append(["EST. %d" % Families.calendar(1), 0.09, 0.14, "franklin"])
	for l in lines:
		var label := SignText.make({"pos": face + Vector3(0, H * float(l[2]), 0), "normal": n, "text": l[0],
			"height": l[1], "width": W - 0.4, "color": LETTER, "style": l[3]})
		root.add_child(label)
	return root
