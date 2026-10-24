class_name StreetSignView
extends Node3D
## Street name signs at junctions: two green blades crossed on a galvanized
## post at a corner, one along each street (MUTCD D3-1: white letters on
## green, 6 in letters on a 9 in blade for a 25 mph street, the bottom at
## least 7 ft up). Mixed case with the standard abbreviations ("Walnut St"),
## as the 2009 MUTCD has it. Lettering is drawn within DRAW_RANGE, the post
## and blades a bit farther.

const DRAW_RANGE := 140.0
const GREEN := Color("#0b6a3a")
const POST := Color("#9a9d9f")
const BLADE_H := 0.23
const LETTER_H := 0.15
## MUTCD street suffix abbreviations (Table 2D-2).
const ABBREV := {"Street": "St", "Avenue": "Ave", "Boulevard": "Blvd", "Drive": "Dr", "Lane": "Ln",
	"Road": "Rd", "Court": "Ct", "Parkway": "Pkwy"}

var sim: CitySim
var _signs := {}  # node id -> Node3D


func setup(s: CitySim) -> void:
	sim = s
	sim.streets.changed.connect(_sync)
	sim.network.changed.connect(_sync)
	_sync.call_deferred()


func _sync() -> void:
	var was := Terrain.shift
	Terrain.shift = Terrain.shift_for(self)
	var want := {}
	for n in sim.network.nodes:
		var spec := _corner(n)
		if not spec.is_empty():
			want[n] = spec
	for n in _signs.keys():
		if not want.has(n) or _signs[n].get_meta("key") != want[n].key:
			_signs[n].queue_free()
			_signs.erase(n)
	for n in want:
		if not _signs.has(n):
			_signs[n] = _post(want[n])
			add_child(_signs[n])
	Terrain.shift = was


## Where a junction's sign goes and what it says: the first two streets that
## meet there (by segment id), at the corner between them.
func _corner(n: int) -> Dictionary:
	var p: Vector3 = sim.network.nodes[n]
	if absf(p.y) > 1.0:
		return {}  # bridges and tunnels carry no corner post
	var segs: Array = sim.network.segments_at(n)
	if segs.size() < 3:
		return {}
	segs.sort()
	var first := -1
	var second := -1
	for id in segs:
		var name := sim.streets.name_of(id)
		if name == "":
			continue
		if first == -1:
			first = id
		elif name != sim.streets.name_of(first):
			second = id
			break
	if second == -1:
		return {}
	var d1 := Streets._out_dir(sim.network, first, n)
	var d2 := Streets._out_dir(sim.network, second, n)
	var t1 := int(sim.network.segments[first].type)
	var t2 := int(sim.network.segments[second].type)
	var h1 := RoadStyle.half_width(t1)
	var h2 := RoadStyle.half_width(t2)
	# The corner between them: street 1's curb on street 2's side, and
	# street 2's curb on street 1's side.
	var side := Vector2(-d1.y, d1.x)
	if side.dot(d2) < 0.0:
		side = -side
	var side2 := Vector2(-d2.y, d2.x)
	if side2.dot(d1) < 0.0:
		side2 = -side2
	var corner = Geometry2D.line_intersects_line(side * h1, d1, side2 * h2, d2)
	if corner == null:
		return {}
	# The curb rounds that corner (Junction's curb return), so the post goes
	# in the grass strip behind the curved curb, on the corner's diagonal,
	# where a city sets it, not out in the pavement the return gave the road.
	var r: float = Junction.RETURN_RADIUS.get(maxi(t1, t2), 6.0)
	var ctr = Geometry2D.line_intersects_line(side * (h1 + r), d1, side2 * (h2 + r), d2)
	var at := Vector2(p.x, p.z) + (corner as Vector2) + (side + side2).normalized() * 1.2
	if ctr != null and (ctr as Vector2).distance_to(corner) > 0.1:
		var out: Vector2 = ((corner as Vector2) - ctr).normalized()
		at = Vector2(p.x, p.z) + ctr + out * (r - RoadStyle.CURB_WIDTH - RoadStyle.PARKWAY_WIDTH * 0.5)
	var a := sim.streets.name_of(first)
	var b := sim.streets.name_of(second)
	return {"at": at, "d1": d1, "d2": d2, "a": a, "b": b, "key": [a, b, at.snapped(Vector2(0.1, 0.1))]}


func _post(spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	var at: Vector2 = spec.at
	root.position = Vector3(at.x, Terrain.ground_y(at.x, at.y), at.y)
	root.set_meta("key", spec.key)
	var b := CommercialBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._box("metal", Vector3(0.06, 3.15, 0.06), Vector3(0, 1.575, 0), POST)
	var labels := []
	for i in 2:
		var name := short(spec.a if i == 0 else spec.b)
		var d: Vector2 = spec.d1 if i == 0 else spec.d2
		var y := 2.55 + i * 0.27
		var len := clampf(0.3 + name.length() * 0.085, 0.75, 1.4)
		var along := Vector3(d.x, 0, d.y)
		var basis := Basis.looking_at(Vector3(-d.y, 0, d.x), Vector3.UP)
		# The blade hangs out over the street it names, from the post.
		var mid := along * (len * 0.5 - 0.1)
		b._box("paint", Vector3(len, BLADE_H, 0.025), mid + Vector3(0, y, 0), GREEN, basis)
		var normal := basis.z
		for s in [1.0, -1.0]:
			labels.append({"pos": mid + Vector3(0, y, 0) + normal * s * 0.016, "normal": normal * s, "text": name,
				"height": LETTER_H, "width": len - 0.1, "color": Color.WHITE, "style": "blade"})
	var mi := MeshInstance3D.new()
	mi.mesh = b._commit_house()
	mi.visibility_range_end = DRAW_RANGE * 2.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	for l in labels:
		var label := SignText.make(l)
		label.visibility_range_end = DRAW_RANGE
		root.add_child(label)
	return root


## A street's name as its blade reads: "Walnut St", "3rd Ave".
static func short(name: String) -> String:
	var parts := name.split(" ")
	if parts.size() > 1 and ABBREV.has(parts[-1]):
		parts[-1] = ABBREV[parts[-1]]
	return " ".join(parts).replace("County Road", "CR")
