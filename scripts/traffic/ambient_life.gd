class_name AmbientLife
extends Node3D
## Life around the homes near the camera that the town's own walkers don't
## show: neighbours talking on the sidewalk, someone at the grill, kids
## playing in a back yard, a lawn being mowed, a dog being walked (Nathan,
## 2026-10-25: "make people do different things… sit on a park bench?
## grill in the back yard? stop and talk to someone else?").
##
## Drawn only, never in the town's thinking: each home picks what's going on
## from its own key, the hour and the month, so the same home is doing the
## same thing whenever you look, and nothing is saved. Only homes near the
## camera are looked at, and only so many people are drawn (fewer in the
## browser), so it costs next to nothing.

const RADIUS := 260.0       # metres from the camera a home is looked at
const MAX_PEOPLE := 140
const MAX_PEOPLE_WEB := 50
const REPICK := 0.6         # seconds between looking for homes again
const STRIDE := 1.4

## What can be going on at a home: [name, from hour, to hour, months (1-12,
## empty for all), chance in a hundred]. Hours and months follow a real
## Indiana year: grills and mowers in summer, snow shovels in winter.
const ACTIVITIES := [
	["talk", 9, 20, [], 4],
	["grill", 17, 20, [5, 6, 7, 8, 9], 6],
	["mow", 9, 18, [4, 5, 6, 7, 8, 9, 10], 3],
	["kids", 10, 19, [4, 5, 6, 7, 8, 9], 6],
	["porch", 17, 22, [4, 5, 6, 7, 8, 9, 10], 4],
	["dog", 7, 9, [], 3],
	["dog", 17, 20, [], 3],
	["garden", 9, 17, [4, 5, 6, 7, 8, 9], 3],
	["catch", 10, 19, [4, 5, 6, 7, 8, 9, 10], 2],
	["shovel", 8, 16, [12, 1, 2], 4],
	["jog", 6, 8, [], 3],
	["wash_car", 10, 16, [5, 6, 7, 8, 9], 2],
	["leaves", 10, 17, [10, 11], 4],
]
const SHIRTS := [Color(0.62, 0.16, 0.14), Color(0.16, 0.3, 0.55), Color(0.85, 0.82, 0.74),
	Color(0.24, 0.42, 0.26), Color(0.9, 0.62, 0.2), Color(0.35, 0.35, 0.38), Color(0.55, 0.38, 0.6),
	Color(0.12, 0.12, 0.14), Color(0.7, 0.75, 0.82), Color(0.78, 0.45, 0.42), Color(0.95, 0.95, 0.93),
	Color(0.2, 0.55, 0.62), Color(0.82, 0.74, 0.3), Color(0.9, 0.5, 0.62)]

var sim: CitySim
var _people: MultiMeshInstance3D
var _props := {}            # prop name -> MultiMeshInstance3D
var _scenes := []           # [{kind, lot, seed}] picked near the camera
var _wait := 0.0
var _clock := 0.0


## `walker_material` is the town walkers' own (WalkerView), so these people
## look and move exactly like them.
func setup(s: CitySim, walker_material: Material) -> void:
	sim = s
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = WalkerView._person_mesh()
	_people = MultiMeshInstance3D.new()
	_people.multimesh = mm
	_people.material_override = walker_material
	_people.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_people)
	_prop("grill", _cyl(0.32, 0.9), Color(0.08, 0.08, 0.08))
	_prop("smoke", _cyl(0.25, 1.6), Color(0.85, 0.85, 0.85, 0.35))
	_prop("mower", _box(Vector3(0.55, 0.4, 0.8)), Color(0.75, 0.12, 0.1))
	_prop("dog", _box(Vector3(0.25, 0.4, 0.75)), Color(0.45, 0.32, 0.2))
	_prop("shovel", _box(Vector3(0.45, 0.05, 0.35)), Color(0.15, 0.25, 0.5))
	_prop("bucket", _cyl(0.15, 0.3), Color(0.9, 0.85, 0.2))
	_prop("leafpile", _cyl(0.9, 0.35), Color(0.62, 0.36, 0.12))
	_prop("ball", _cyl(0.12, 0.24), Color(0.95, 0.95, 0.95))
	_prop("bench", _box(Vector3(1.8, 0.45, 0.5)), Color(0.42, 0.3, 0.18))
	_prop("blanket", _box(Vector3(2.0, 0.03, 1.6)), Color(0.75, 0.18, 0.16))
	_prop("disc", _cyl(0.14, 0.03), Color(0.95, 0.75, 0.1))


func _prop(name: String, mesh: Mesh, col: Color) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.9
	if col.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_props[name] = mi


static func _cyl(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 1
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## The hour of day (0-24) and month (1-12) the town is at.
func _when() -> Array:
	var t := sim.tick_count
	var hour := fmod(6.0 + t / 60.0, 24.0)
	var month := Seasons.month(t)
	return [hour, month]


func _process(delta: float) -> void:
	if sim == null:
		return
	_clock += delta
	_wait -= delta
	if _wait <= 0.0:
		_wait = REPICK
		_pick()
	_draw()


## Which homes near the camera have something going on right now.
func _pick() -> void:
	_scenes.clear()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var when := _when()
	var hour: float = when[0]
	var month: int = when[1]
	var cap := MAX_PEOPLE_WEB if OS.has_feature("web") else MAX_PEOPLE
	var people := 0
	for key in sim.buildings:
		var b: Dictionary = sim.buildings[key]
		if int(b.zone) != ZoneMap.Zone.RESIDENTIAL or int(b.get("occ", 0)) == 0 or not sim.lots.has(key):
			continue
		if sim.construction.sites.has("lot:" + key):
			continue  # still going up: no lawn to mow yet
		var lot: Dictionary = sim.lots[key]
		var f: Vector3 = lot.front
		if Vector2(f.x - eye.x, f.z - eye.z).length() > RADIUS:
			continue
		var h := hash([key, int(hour), "ambient"])
		var roll := h % 100
		var acc := 0
		for a in ACTIVITIES:
			if hour < float(a[1]) or hour >= float(a[2]):
				continue
			if not (a[3] as Array).is_empty() and not month in a[3]:
				continue
			acc += int(a[4])
			if roll < acc:
				_scenes.append({"kind": a[0], "lot": lot, "seed": h})
				people += 3 if a[0] == "kids" else 2 if a[0] in ["talk", "catch"] else 1
				break
		if people >= cap:
			break
	# Parks: benches, picnics, strolls and frisbee, busiest on fine afternoons.
	for id in sim.parks.sites:
		if people >= cap:
			break
		var pk: Dictionary = sim.parks.sites[id]
		var pp: Vector3 = pk.pos
		if Vector2(pp.x - eye.x, pp.z - eye.z).length() > RADIUS or hour < 7.0 or hour >= 21.0:
			continue
		var warm := month >= 4 and month <= 10
		var n := 2 + (2 if warm else 0) + (2 if hour >= 11.0 and hour < 18.0 else 0)
		for i in n:
			var h := hash([id, i, int(hour), "park"])
			var kinds := ["bench", "stroll", "stroll", "picnic", "frisbee"] if warm else ["bench", "stroll", "stroll"]
			_scenes.append({"kind": kinds[h % kinds.size()], "park": pk, "seed": h})
			people += 2
	# Shops: window shoppers out front in the day, a worker on a break.
	for key in sim.buildings:
		if people >= cap:
			break
		var b: Dictionary = sim.buildings[key]
		if int(b.zone) != ZoneMap.Zone.COMMERCIAL or not sim.lots.has(key) or hour < 8.0 or hour >= 20.0:
			continue
		var lot: Dictionary = sim.lots[key]
		var f: Vector3 = lot.front
		if Vector2(f.x - eye.x, f.z - eye.z).length() > RADIUS:
			continue
		var h := hash([key, int(hour), "shop"])
		if h % 100 < 30:
			_scenes.append({"kind": "window" if h % 3 != 0 else "break", "lot": lot, "seed": h})
			people += 1


## One person: where, facing, shirt, walk phase (0 standing), size.
func _person(list: Array, at: Vector3, face: Vector3, seed: int, walked: float, size := 1.0) -> void:
	var shirt: Color = SHIRTS[(seed >> 3) % SHIRTS.size()]
	shirt.a = fposmod(walked, STRIDE * size) / (STRIDE * size) if walked >= 0.0 else 0.0
	var f := Vector3(face.x, 0.0, face.z)
	if f.length() < 0.01:
		f = Vector3.FORWARD
	var tall := (0.92 + float(seed % 17) / 100.0) * size
	list.append([Transform3D(Basis.looking_at(f.normalized(), Vector3.UP).scaled(Vector3(tall, tall, tall)),
		Terrain.stand(at)), shirt, WalkerView.skin_tone(seed)])


func _draw() -> void:
	var people := []
	var props := {}
	for k in _props:
		props[k] = []
	for s in _scenes:
		if s.has("park"):
			_park_scene(people, props, s)
			continue
		var lot: Dictionary = s.lot
		var seed: int = s.seed
		var into: Vector3 = lot.normal
		var along: Vector3 = lot.dir
		var front: Vector3 = lot.front
		var depth: float = float(lot.get("depth", 36.0))
		var width: float = float(lot.get("width", 18.0))
		var walk := front - into * 1.2                      # the sidewalk
		var lawn := front + into * 3.5                      # the front lawn
		var back := front + into * depth * 0.8              # the back yard
		var t := _clock + float(seed % 97)
		match s.kind:
			"talk":
				var mid := walk + along * (float(seed % 9) - 4.0)
				_person(people, mid - along * 0.45, along, seed, -1.0)
				_person(people, mid + along * 0.45, -along, seed >> 5, -1.0)
			"grill":
				var g := back + along * width * 0.15
				props.grill.append(Transform3D(Basis(), Terrain.stand(g) + Vector3(0, 0.45, 0)))
				props.smoke.append(Transform3D(Basis().scaled(Vector3(1, 0.8 + 0.3 * sin(t * 1.3), 1)),
					Terrain.stand(g) + Vector3(0, 1.9, 0)))
				_person(people, g - into * 0.9, into, seed, -1.0)
			"mow":
				# Back and forth across the front lawn in strips.
				var u := fposmod(t * 0.9, width * 2.0)
				var x := u if u < width else width * 2.0 - u
				var p := front + into * (2.0 + float(int(t * 0.9 / width) % 4)) + along * (x - width * 0.5)
				var heading := along if u < width else -along
				props.mower.append(Transform3D(Basis.looking_at(heading, Vector3.UP), Terrain.stand(p + heading * 0.9) + Vector3(0, 0.2, 0)))
				_person(people, p, heading, seed, t * 0.9)
			"kids":
				for i in 3:
					var a := t * (1.6 + i * 0.3) + i * 2.1
					var r := 2.5 + i
					var p := back + along * cos(a) * r + into * sin(a) * r * 0.6
					var heading := -along * sin(a) + into * cos(a) * 0.6
					_person(people, p, heading, seed >> i, a * r * (1.6 + i * 0.3) * 0.25, 0.62)
			"porch":
				_person(people, front + into * 7.5 + along * 1.5, -into, seed, -1.0)
			"dog":
				var u := fposmod(t * 1.1, 60.0)
				var x := u if u < 30.0 else 60.0 - u
				var heading := along if u < 30.0 else -along
				var p := walk + along * (x - 15.0)
				_person(people, p, heading, seed, t * 1.1)
				props.dog.append(Transform3D(Basis.looking_at(heading, Vector3.UP), Terrain.stand(p + heading * 1.6 + along.cross(Vector3.UP) * 0.4) + Vector3(0, 0.2, 0)))
			"garden":
				var p := lawn + along * (width * 0.35)
				_person(people, p, into, seed, -1.0, 0.8)  # bent over the bed
			"catch":
				var a := back - along * 4.0
				var b := back + along * 4.0
				_person(people, a, along, seed, -1.0)
				_person(people, b, -along, seed >> 4, -1.0)
				var k := fposmod(t * 0.7, 2.0)
				var u2 := k if k < 1.0 else 2.0 - k
				props.ball.append(Transform3D(Basis(), Terrain.stand(a.lerp(b, u2)) + Vector3(0, 1.6 + sin(u2 * PI) * 2.0, 0)))
			"shovel":
				var u := fposmod(t * 0.6, 12.0)
				var x := u if u < 6.0 else 12.0 - u
				var p := front + along * (width * 0.35) + into * (x - 1.0)
				var heading := into if u < 6.0 else -into
				_person(people, p, heading, seed, t * 0.6)
				props.shovel.append(Transform3D(Basis.looking_at(heading, Vector3.UP), Terrain.stand(p + heading * 0.7) + Vector3(0, 0.05, 0)))
			"jog":
				var u := fposmod(t * 3.0, 120.0)
				var x := u if u < 60.0 else 120.0 - u
				var heading := along if u < 60.0 else -along
				_person(people, walk + along * (x - 30.0), heading, seed, t * 3.0 * 0.7)
			"wash_car":
				var p := front + into * 2.0 + along * (width * 0.35)
				_person(people, p + along * 1.2 * sin(t * 0.8), -along, seed, -1.0)
				props.bucket.append(Transform3D(Basis(), Terrain.stand(p - along * 1.4) + Vector3(0, 0.15, 0)))
			"window":
				var p := walk + into * 0.6 + along * (float(seed % 11) - 5.0)
				_person(people, p, into, seed, -1.0)
			"break":
				_person(people, back + along * (width * 0.3), -along, seed, -1.0)
			"leaves":
				var p := lawn + along * (float(seed % 7) - 3.0)
				_person(people, p + into * 0.6 * sin(t * 1.4), along, seed, -1.0)
				props.leafpile.append(Transform3D(Basis(), Terrain.stand(p + along * 1.6) + Vector3(0, 0.15, 0)))
	var mm := _people.multimesh
	if mm.instance_count < people.size():
		mm.instance_count = maxi(people.size() * 2, 32)
	for i in people.size():
		mm.set_instance_transform(i, people[i][0])
		mm.set_instance_color(i, people[i][2])
		mm.set_instance_custom_data(i, people[i][1])
	mm.visible_instance_count = people.size()
	for k in props:
		var pm: MultiMesh = _props[k].multimesh
		var list: Array = props[k]
		if pm.instance_count < list.size():
			pm.instance_count = maxi(list.size() * 2, 8)
		for i in list.size():
			pm.set_instance_transform(i, list[i])
		pm.visible_instance_count = list.size()


## A park scene: someone on a bench (drawn low, as if seated), a picnic on a
## blanket, a stroll round the park, or a game of frisbee.
func _park_scene(people: Array, props: Dictionary, s: Dictionary) -> void:
	var pk: Dictionary = s.park
	var seed: int = s.seed
	var c: Vector3 = pk.pos
	var size: Vector2 = pk.size if pk.size is Vector2 else Vector2(40, 40)
	var dir: Vector3 = pk.dir if pk.dir is Vector3 else Vector3.FORWARD
	var side := Vector3(-dir.z, 0.0, dir.x)
	var spot := c + side * (float(seed % 100) / 100.0 - 0.5) * size.x * 0.7 \
		+ dir * (float((seed >> 7) % 100) / 100.0 - 0.5) * size.y * 0.7
	var t := _clock + float(seed % 97)
	match s.kind:
		"bench":
			props.bench.append(Transform3D(Basis.looking_at(dir, Vector3.UP), Terrain.stand(spot) + Vector3(0, 0.22, 0)))
			# Seated: drawn short and set back on the seat.
			_person(people, spot + dir * 0.05, -dir, seed, -1.0, 0.62)
			if seed % 3 == 0:
				_person(people, spot + side * 0.6 + dir * 0.05, -dir, seed >> 3, -1.0, 0.62)
		"picnic":
			props.blanket.append(Transform3D(Basis.looking_at(dir, Vector3.UP), Terrain.stand(spot) + Vector3(0, 0.02, 0)))
			_person(people, spot - side * 0.5, side, seed, -1.0, 0.6)
			_person(people, spot + side * 0.5, -side, seed >> 4, -1.0, 0.6)
		"stroll":
			var a := t * 0.05 + float(seed % 6)
			var r := minf(size.x, size.y) * 0.35
			var p := c + side * cos(a) * r + dir * sin(a) * r
			_person(people, p, -side * sin(a) + dir * cos(a), seed, a * r)
		"frisbee":
			var a2 := spot - side * 6.0
			var b2 := spot + side * 6.0
			_person(people, a2, side, seed, -1.0)
			_person(people, b2, -side, seed >> 4, -1.0)
			var k := fposmod(t * 0.6, 2.0)
			var u := k if k < 1.0 else 2.0 - k
			props.disc.append(Transform3D(Basis(), Terrain.stand(a2.lerp(b2, u)) + Vector3(0, 1.4 + sin(u * PI) * 1.2, 0)))
