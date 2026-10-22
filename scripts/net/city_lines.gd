class_name CityLines
extends MultiMeshInstance3D
## The city line between neighbors: a cream dashed line on the ground,
## drawn halfway between the two cities' closest buildings (and roads, so
## a brand-new city has one too), like the gaps in the Neighbors logo.
##
## It's traced, not gridded: start midway between the two closest points,
## then walk sideways, pulling each step back onto the spot that is equally
## far from both cities, until it is far from both or a third city is
## nearer. Drawing only; who may build where is a later rule.

const STEP := 10.0          # metres between traced points
const DASH := 6.0           # dash length, metres (a gap of STEP - DASH follows)
## Width on the ground up close; it widens as the camera pulls back so the
## line stays visible from far away, like a map overlay.
const WIDTH := 1.5
const BUCKET := 64.0        # spatial hash cell for nearest-point lookups
## Lines are drawn between cities whose closest points are this close.
const MAX_GAP := 3000.0
## How often the lines are redrawn while cities change, seconds.
const REFRESH := 3.0

var client: RegionClient
## Region coordinates -> this world.
var to_world: Callable

var _dirty := true
var _wait := 0.0
var _lines := []        # traced lines, region coordinates
var _width := WIDTH


func setup(c: RegionClient, world: Callable) -> void:
	client = c
	to_world = world


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.06, DASH)
	mm.mesh = box
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Brand.CITY_LINE
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for id in client.region.cities:
		_watch(id)
	client.city_added.connect(func(id):
		_watch(id)
		_dirty = true)


func _watch(id: String) -> void:
	var sim: CitySim = client.region.cities[id].sim
	sim.buildings_changed.connect(func(): _dirty = true)
	sim.network.changed.connect(func(): _dirty = true)


func _process(delta: float) -> void:
	_wait -= delta
	if _dirty and _wait <= 0.0:
		_dirty = false
		_wait = REFRESH
		_rebuild()
	var cam := get_viewport().get_camera_3d()
	if cam:
		var w := maxf(WIDTH, cam.global_position.y * 0.004)
		if absf(w - _width) > _width * 0.15:
			_width = w
			_place()


func _rebuild() -> void:
	var sets := {}
	for id in client.region.cities:
		var pts := city_points(client.region.cities[id])
		if not pts.is_empty():
			sets[id] = PointSet.new(pts)
	_lines = []
	var ids := sets.keys()
	ids.sort()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var others := []
			for k in ids:
				if k != ids[i] and k != ids[j]:
					others.append(sets[k])
			_lines.append_array(trace(sets[ids[i]], sets[ids[j]], others))
	_place()


func _place() -> void:
	var dashes := []
	for line in _lines:
		dashes.append_array(_dashes(line))
	multimesh.instance_count = dashes.size()
	for n in dashes.size():
		multimesh.set_instance_transform(n, dashes[n])


## Where a city has built, in region coordinates: its buildings and roads.
static func city_points(city: Dictionary) -> PackedVector2Array:
	var sim: CitySim = city.sim
	var o: Vector2 = city.origin
	var out := PackedVector2Array()
	for key in sim.buildings:
		if sim.lots.has(key):
			var p: Vector3 = sim.lots[key].pos
			out.append(o + Vector2(p.x, p.z))
	for seg in sim.network.segments:
		for p in sim.network.sample_segment(seg, 6):
			out.append(o + Vector2(p.x, p.z))
	return out


## The city lines between two cities, as lists of points (region coordinates).
static func trace(a: PointSet, b: PointSet, others: Array) -> Array:
	var pair := _closest_pair(a, b)
	var gap: float = pair[0].distance_to(pair[1])
	if gap > MAX_GAP or gap < 0.01:
		return []
	var start: Vector2 = (pair[0] + pair[1]) * 0.5
	var side: Vector2 = (pair[1] - pair[0]).normalized().orthogonal()
	# Far from both cities, the line has done its job.
	var reach := gap + 300.0
	var halves := []
	for dir in [side, -side]:
		var pts := PackedVector2Array([start])
		var p := start
		var heading: Vector2 = dir
		for i in 600:
			var q := _settle(a, b, p + heading * STEP)
			var da := a.nearest_distance(q)
			if da > reach or not _is_ours(q, da, others) or q.distance_to(p) < STEP * 0.3:
				break
			heading = (q - p).normalized()
			pts.append(q)
			p = q
		halves.append(pts)
	var line := PackedVector2Array()
	var back: PackedVector2Array = halves[1]
	for i in range(back.size() - 1, 0, -1):
		line.append(back[i])
	line.append_array(halves[0])
	return [line] if line.size() > 1 else []


## Slides a point onto the spot equally far from both cities.
static func _settle(a: PointSet, b: PointSet, p: Vector2) -> Vector2:
	for i in 6:
		var na := a.nearest(p)
		var nb := b.nearest(p)
		var da := p.distance_to(na)
		var db := p.distance_to(nb)
		var diff := da - db
		if absf(diff) < 0.5:
			break
		var grad := (p - na) / maxf(da, 0.001) - (p - nb) / maxf(db, 0.001)
		var g2 := grad.length_squared()
		if g2 < 0.0001:
			break
		p -= grad * (diff / g2)
	return p


## True while no third city is nearer than these two.
static func _is_ours(p: Vector2, d: float, others: Array) -> bool:
	for o in others:
		if (o as PointSet).nearest_distance(p) < d:
			return false
	return true


static func _closest_pair(a: PointSet, b: PointSet) -> Array:
	var best := INF
	var pa := Vector2.ZERO
	var pb := Vector2.ZERO
	for p in a.points:
		var q := b.nearest(p)
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			pa = p
			pb = q
	return [pa, pb]


## Dashes laid along a line, flat on the ground.
func _dashes(line: PackedVector2Array) -> Array:
	var out := []
	for i in line.size() - 1:
		var p0: Vector3 = to_world.call(line[i])
		var p1: Vector3 = to_world.call(line[i + 1])
		var mid := (p0 + p1) * 0.5 + Vector3(0, 0.12, 0)
		var basis := Basis.looking_at((p1 - p0).normalized(), Vector3.UP) if p0.distance_to(p1) > 0.01 else Basis()
		out.append(Transform3D(basis.scaled_local(Vector3(_width, 1, 1)), mid))
	return out


## Points with a spatial hash, for quick nearest-point lookups.
class PointSet:
	var points: PackedVector2Array
	var _cells := {}  # Vector2i -> PackedVector2Array

	func _init(pts: PackedVector2Array) -> void:
		points = pts
		for p in pts:
			var c := Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))
			if not _cells.has(c):
				_cells[c] = PackedVector2Array()
			_cells[c].append(p)

	func nearest(p: Vector2) -> Vector2:
		var c := Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))
		var best := INF
		var out := p
		var ring := 0
		# Search rings of cells outwards; stop once a ring can't beat the best.
		while ring < 200:
			if best < INF and (ring - 1) * BUCKET > sqrt(best):
				break
			for x in range(c.x - ring, c.x + ring + 1):
				for y in range(c.y - ring, c.y + ring + 1):
					if ring > 0 and absi(x - c.x) != ring and absi(y - c.y) != ring:
						continue
					var cell: PackedVector2Array = _cells.get(Vector2i(x, y), PackedVector2Array())
					for q in cell:
						var d := p.distance_squared_to(q)
						if d < best:
							best = d
							out = q
			ring += 1
		return out

	func nearest_distance(p: Vector2) -> float:
		return p.distance_to(nearest(p))
