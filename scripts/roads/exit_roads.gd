class_name ExitRoads
extends Node3D
## The county highways a town starts on run on past its region links, out to
## the horizon, so the map never looks like it ends. Only drawn: nothing
## drives them (traffic leaves the town at the link, as before), and they
## can't be built on.
##
## Benchmark: Indiana county roads, which run dead straight for miles on the
## Public Land Survey section lines between towns, two lanes with gravel
## shoulders and a pole line down one side (CR 300 N across Pike County).
## A road heading into another town stops short of it; one that meets a
## neighbor's road (a shared link) isn't drawn on at all.

## How far past its link a county highway is drawn: as far as the land is
## drawn (TerrainView.REACH) from a camera standing at the link.
const REACH := 9000.0
## Drawn in pieces this long, like the county highway itself.
const PIECE := 400.0
## Checked for other towns this often along the way, metres.
const PROBE := 100.0
## Stops this far short of another town.
const SHORT := 300.0

## Points along the road this far apart, so it follows the rise and fall
## of the land (the terrain data is 10 m a sample).
const STEP := 10.0
## Utility poles are laid in runs this long (RoadMesh.add_poles spaces
## them about 45 m apart, as on the county highway in town).
const POLE_RUN := 920.0

var sim: CitySim
var terrain: TerrainView
## Callable(p: Vector2) -> bool, in the town's own coordinates: true where
## the road must not go (another town, or a link shared with a neighbor).
var stop := Callable()
var _name := ""
var _ends := []
var _mats := {
	"asphalt": Surfaces.asphalt(),
	"gravel": Surfaces.gravel(),
	"yellow": Surfaces.paint(RoadStyle.MARKING_YELLOW),
	"white": Surfaces.paint(RoadStyle.MARKING_WHITE),
	"concrete": Surfaces.concrete(Color(0.66, 0.65, 0.62)),
	"pole": RoadStyle.material(Color(0.33, 0.27, 0.21)),
	"wire": RoadStyle.material(Color(0.12, 0.12, 0.12)),
}


## `name` keys this town's grading in the terrain (one per town).
func setup(s: CitySim, t: TerrainView, name: String, stop_at := Callable()) -> void:
	sim = s
	terrain = t
	_name = name
	stop = stop_at
	sim.network.changed.connect(refresh)
	refresh()


## Redraws if any link has moved or been added, or a road now has to stop
## somewhere else (a town has been founded in its way).
func refresh() -> void:
	var ends := _open_ends()
	if ends == _ends:
		return
	_ends = ends
	for child in get_children():
		child.queue_free()
	# Drawn moved over with the town it belongs to (a neighbor's).
	Terrain.shift = Terrain.shift_for(self)
	var strips := {}
	var parts := {}
	for k in _mats:
		parts[k] = SurfaceTool.new()
		parts[k].begin(Mesh.PRIMITIVE_TRIANGLES)
	var piers: SurfaceTool = parts.concrete
	var offset := Vector3(Terrain.shift.x, 0.0, Terrain.shift.y)
	for e in ends:
		var type: int = e[3]
		_draw(parts, e[0], e[1], e[2], type, e[4])
		# The land under it is graded and mowed, as under any road.
		var row := RoadStyle.right_of_way_half(type)
		var n := maxi(1, ceili(e[2] / PIECE))
		for i in n:
			var a: Vector3 = e[0] + e[1] * (e[2] * i / n)
			var b: Vector3 = e[0] + e[1] * (e[2] * (i + 1) / n)
			strips["%d:%d" % [_ends.find(e), i]] = [PackedVector3Array([a + offset, b + offset]), row + 2.0,
				row + 2.0 + TerrainView.GRADE_FADE, row + TerrainView.MOW_VERGE]
	piers.generate_normals()
	for k in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = parts[k].commit()
		mi.material_override = _mats[k]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if k in ["pole", "wire"] \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	Terrain.shift = Vector2.ZERO
	if terrain != null:
		terrain.add_strips(_name, strips)


func _exit_tree() -> void:
	if terrain != null and is_instance_valid(terrain):
		terrain.remove_network(_name)


## One county highway from `at` on `length` metres: the same two-lane
## country road as in town (RoadMesh._rural), with its pole line and a
## bridge wherever it crosses water. Built straight and laid straight onto
## the land (no draping afterwards), so it's cheap however long.
func _draw(parts: Dictionary, at: Vector3, dir: Vector3, length: float, type: int, pole_side: float) -> void:
	var spec: Dictionary = RoadStyle.TYPES[type]
	var hw: float = spec.width * 0.5
	var edge := 3.6 * maxi(spec.lanes / 2, 1)
	var y_mark := RoadStyle.Y_ASPHALT + 0.01
	var pts := PackedVector3Array()
	var n := maxi(1, ceili(length / STEP))
	for k in n + 1:
		pts.append(Terrain.lift(at + dir * (length * k / n)))
	RoadMesh.add_strip(parts.asphalt, pts, -hw, hw, RoadStyle.Y_ASPHALT)
	for side in [-1.0, 1.0]:
		RoadMesh.add_strip(parts.gravel, pts, minf(side * hw, side * (hw + 1.8)), maxf(side * hw, side * (hw + 1.8)),
			RoadStyle.Y_SIDEWALK)
		RoadMesh.add_strip(parts.white, pts, minf(side * (edge + 0.05), side * (edge + 0.2)),
			maxf(side * (edge + 0.05), side * (edge + 0.2)), y_mark)
	# A dashed centre line: 3 m dashes, 9 m gaps (MUTCD), started clear of the
	# link, each end on the road between its samples.
	var d := 6.0
	while d + 3.0 < length:
		RoadMesh.add_strip(parts.yellow, PackedVector3Array([_on(pts, d), _on(pts, d + 3.0)]), -0.06, 0.06, y_mark)
		d += 12.0
	# Poles down one side, on the same side as the pole line in town, in runs
	# that share their end poles so the wires carry on unbroken.
	var off: float = (hw + spec.get("verge", 4.0)) * pole_side
	var run := int(POLE_RUN / STEP)
	var i := 0
	while i < pts.size() - 6:
		RoadMesh.add_poles(parts.pole, parts.wire, pts.slice(i, mini(i + run + 1, pts.size())), off)
		i += run - 2
	RoadMesh.bridge(pts, RoadStyle.right_of_way_half(type), parts.concrete, Terrain.ground_y)


## The point `d` metres along evenly spaced samples, between its neighbours.
func _on(pts: PackedVector3Array, d: float) -> Vector3:
	var f := d / Vector2(pts[1].x - pts[0].x, pts[1].z - pts[0].z).length()
	var k := clampi(floori(f), 0, pts.size() - 2)
	return pts[k].lerp(pts[k + 1], f - k)


## Each link that leads on to open country: [where, which way, how far,
## road type, which side its poles are on (+1 left, -1 right)].
func _open_ends() -> Array:
	var out := []
	var net := sim.network
	for node in sim.region_links:
		if not net.nodes.has(node):
			continue
		var seg := -1
		for s in net.segments_at(node):
			if sim.is_link_segment(s):
				seg = s
				break
		if seg == -1:
			continue
		var pts := net.sample_segment(seg)
		# RoadView puts a country road's poles on this side, looking from a to b.
		var poles := 1.0 if hash(seg) % 2 == 0 else -1.0
		if net.segments[seg].b != node:
			pts.reverse()
			poles = -poles
		var at: Vector3 = net.nodes[node]
		var dir := pts[pts.size() - 1] - pts[pts.size() - 2]
		dir.y = 0.0
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		var length := REACH
		if stop.is_valid():
			var d := 0.0
			while d <= REACH:
				var q := at + dir * d
				if stop.call(Vector2(q.x, q.z)):
					length = d - SHORT
					break
				d += PROBE
		if length < PIECE * 0.5:
			continue
		out.append([Vector3(at.x, 0.0, at.z), dir, snappedf(length, 1.0), net.segments[seg].type, poles])
	return out
