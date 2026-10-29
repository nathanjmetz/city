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
## empty for all), chance in a hundred, and optionally the weekdays (0 is
## Sunday)]. Hours and months follow a real Indiana year: grills and mowers
## in summer, snow shovels and snowmen in winter, yard sales on spring and
## summer Saturdays, costumes on October evenings.
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
	["snowman", 10, 16, [12, 1, 2], 3],
	["lemonade", 11, 16, [6, 7, 8], 2],
	["bike", 9, 19, [4, 5, 6, 7, 8, 9, 10], 3],
	["hoops", 15, 20, [3, 4, 5, 6, 7, 8, 9, 10, 11], 3],
	["yard_sale", 8, 13, [4, 5, 6, 7, 8, 9], 6, [6]],
	["costumes", 18, 21, [10], 5],
]
## October costume colours: pumpkins, witches, ghosts and superheroes.
const COSTUMES := [Color(0.95, 0.5, 0.1), Color(0.08, 0.08, 0.1), Color(0.97, 0.97, 0.97),
	Color(0.15, 0.3, 0.8), Color(0.75, 0.1, 0.12), Color(0.4, 0.15, 0.5)]
const SHIRTS := [Color(0.62, 0.16, 0.14), Color(0.16, 0.3, 0.55), Color(0.85, 0.82, 0.74),
	Color(0.24, 0.42, 0.26), Color(0.9, 0.62, 0.2), Color(0.35, 0.35, 0.38), Color(0.55, 0.38, 0.6),
	Color(0.12, 0.12, 0.14), Color(0.7, 0.75, 0.82), Color(0.78, 0.45, 0.42), Color(0.95, 0.95, 0.93),
	Color(0.2, 0.55, 0.62), Color(0.82, 0.74, 0.3), Color(0.9, 0.5, 0.62)]

## For pictures only (tools/ambient_shot.gd): every home near the camera
## shows this scene. The game never sets it.
static var force := ""

var sim: CitySim
var _people: MultiMeshInstance3D
var _dogs: MultiMeshInstance3D
var _month := 7
var _desktop := true
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
	# Dogs trot in the walkers' shader too.
	var dm := MultiMesh.new()
	dm.transform_format = MultiMesh.TRANSFORM_3D
	dm.use_colors = true
	dm.use_custom_data = true
	dm.mesh = WalkerView._dog_mesh(2 if OS.has_feature("web") else 3)
	_dogs = MultiMeshInstance3D.new()
	_dogs.multimesh = dm
	_dogs.material_override = walker_material
	_dogs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dogs)
	_desktop = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	_prop("grill", _cyl(0.32, 0.9), Color(0.08, 0.08, 0.08))
	_prop("smoke", _cyl(0.25, 1.6), Color(0.85, 0.85, 0.85, 0.35))
	_prop("mower", _box(Vector3(0.55, 0.4, 0.8)), Color(0.75, 0.12, 0.1))
	_prop("leash", _box(Vector3(0.012, 0.012, 1.0)), Color(0.55, 0.1, 0.1))
	_prop("shovel", _box(Vector3(0.45, 0.05, 0.35)), Color(0.15, 0.25, 0.5))
	_prop("bucket", _cyl(0.15, 0.3), Color(0.9, 0.85, 0.2))
	_prop("leafpile", _cyl(0.9, 0.35), Color(0.62, 0.36, 0.12))
	_prop("ball", _cyl(0.12, 0.24), Color(0.95, 0.95, 0.95))
	_prop("bench", _box(Vector3(1.8, 0.45, 0.5)), Color(0.42, 0.3, 0.18))
	_prop("chair", _box(Vector3(0.55, 0.45, 0.5)), Color(0.86, 0.85, 0.8))
	_prop("chair_back", _box(Vector3(0.55, 0.55, 0.05)), Color(0.86, 0.85, 0.8))
	_prop("blanket", _box(Vector3(2.0, 0.03, 1.6)), Color(0.75, 0.18, 0.16))
	_prop("disc", _cyl(0.14, 0.03), Color(0.95, 0.75, 0.1))
	_prop("snowball", _ball(0.5), Color(0.96, 0.97, 1.0))
	_prop("snowhead", _ball(0.3), Color(0.96, 0.97, 1.0))
	_prop("table", _box(Vector3(1.6, 0.75, 0.7)), Color(0.86, 0.84, 0.78))
	_prop("pole", _box(Vector3(0.1, 3.05, 0.1)), Color(0.3, 0.3, 0.32))
	_prop("board", _box(Vector3(1.1, 0.75, 0.05)), Color(0.95, 0.95, 0.95))
	_prop("bike", _box(Vector3(0.12, 0.55, 1.5)), Color(0.15, 0.35, 0.75))
	_prop("sled", _box(Vector3(0.5, 0.1, 1.0)), Color(0.8, 0.12, 0.1))


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


static func _ball(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## The hour of day (0-24) and month (1-12) the town is at.
func _when() -> Array:
	return [sim.sky_hour(), Seasons.month(sim.calendar_tick())]


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
	_month = DayNight.visible_month(sim)
	var cap := MAX_PEOPLE_WEB if OS.has_feature("web") else MAX_PEOPLE
	var people := 0
	var wd := Mail.weekday_of(sim.tick_count)
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
		if force != "":
			if h % 3 == 0:
				_scenes.append({"kind": force, "lot": lot, "seed": h})
				people += 3
			if people >= cap:
				break
			continue
		var roll := h % 100
		var acc := 0
		for a in ACTIVITIES:
			if hour < float(a[1]) or hour >= float(a[2]):
				continue
			if not (a[3] as Array).is_empty() and not month in a[3]:
				continue
			if a.size() > 5 and not wd in a[5]:
				continue
			acc += int(a[4])
			if roll < acc:
				_scenes.append({"kind": a[0], "lot": lot, "seed": h})
				people += {"kids": 3, "talk": 2, "catch": 2, "snowman": 2, "lemonade": 3, "yard_sale": 3,
					"costumes": 4}.get(a[0], 1)
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
			var snowy := month == 12 or month <= 2
			var kinds := ["bench", "stroll", "stroll", "picnic", "frisbee"] if warm else \
				(["sled", "sled", "stroll", "sled"] if snowy and hour >= 10.0 and hour < 17.0 else ["bench", "stroll", "stroll"])
			_scenes.append({"kind": kinds[h % kinds.size()], "park": pk, "seed": h})
			people += 2
	var weekday := wd >= 1 and wd <= 5  # 0 is Sunday
	# Building sites: a crew of two or three at work through the working day.
	if weekday and hour >= 7.0 and hour < 16.0:
		for ref in sim.construction.sites:
			if people >= cap:
				break
			var site: Dictionary = sim.construction.sites[ref]
			if int(site.get("stage", -1)) < 0:
				continue
			var fr := Vector3(float(site.front[0]), 0.0, float(site.front[1]))
			if Vector2(fr.x - eye.x, fr.z - eye.z).length() > RADIUS:
				continue
			var out := Vector3(float(site.out[0]), 0.0, float(site.out[1]))
			_scenes.append({"kind": "crew", "front": fr, "out": out, "seed": hash([ref, "crew"])})
			people += 3
	# Bus stops: riders waiting for the next bus. About half a headway's
	# worth of the stop's riders turn up between buses (a small-town route
	# runs about hourly, and a stop sees about 8% of its day's riders in an
	# hour, more at the rush).
	if hour >= 6.0 and hour < 19.0:
		for sid in sim.buses.stops:
			if people >= cap:
				break
			var st: Dictionary = sim.buses.stops[sid]
			if not st.has("pos") or int(st.get("depot", -1)) == -1:
				continue
			var sp: Vector3 = st.pos
			if Vector2(sp.x - eye.x, sp.z - eye.z).length() > RADIUS:
				continue
			var rush := 1.6 if hour < 9.0 or hour >= 16.0 and hour < 18.0 else 1.0
			var jitter := float(hash([sid, int(hour), "wait"]) % 100) / 100.0 - 0.5
			var n := mini(roundi(float(st.get("riders", 0.0)) * 0.04 * rush + jitter), 6)
			if n > 0:
				_scenes.append({"kind": "bus_stop", "stop": st, "n": n, "seed": hash([sid, int(hour), "stop"]),
					"shelter": BusView.has_shelter(sim, st)})
				people += n
	# Schools: recess in the yard on school days (late August to May).
	var term := month >= 9 or month <= 5 or (month == 8 and fposmod(Seasons.months(sim.calendar_tick()), 1.0) > 0.6)
	if weekday and term and (hour >= 10.0 and hour < 10.5 or hour >= 12.0 and hour < 12.75 or hour >= 14.0 and hour < 14.3):
		for id in sim.services.buildings:
			var sb: Dictionary = sim.services.buildings[id]
			if int(sb.kind) != Services.Kind.SCHOOL or people >= cap:
				continue
			var sp: Vector3 = sb.pos
			if Vector2(sp.x - eye.x, sp.z - eye.z).length() > RADIUS:
				continue
			_scenes.append({"kind": "recess", "school": sb, "seed": hash([id, "recess"])})
			people += 14
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
func _person(list: Array, at: Vector3, face: Vector3, seed: int, walked: float, size := 1.0, sit := false) -> void:
	# Dressed for the month like the town's walkers (age by size: a small
	# one is a kid).
	var worn := WalkerView.dress(seed, _month, 10 if size < 0.7 and not sit else 25 + seed % 55)
	var shirt: Color = worn[0]
	shirt.a = fposmod(walked, STRIDE * size) / (STRIDE * size) if walked >= 0.0 else 0.0
	if _desktop:
		# Seated people bend into the chair (WalkerView.SEATED).
		shirt.a = minf(shirt.a, 0.999) + float(int(worn[1]) | (WalkerView.SEATED if sit else 0))
	elif sit:
		size *= 0.62  # the browser can't bend them: drawn short instead
	var f := Vector3(face.x, 0.0, face.z)
	if f.length() < 0.01:
		f = Vector3.FORWARD
	var tall := (0.92 + float(seed % 17) / 100.0) * size
	list.append([Transform3D(Basis.looking_at(f.normalized(), Vector3.UP).scaled(Vector3(tall, tall, tall)),
		Terrain.stand(at)), shirt, WalkerView.skin_tone(seed)])


func _draw() -> void:
	var people := []
	var dogs := []
	var props := {}
	for k in _props:
		props[k] = []
	for s in _scenes:
		if s.has("park"):
			_park_scene(people, props, s)
			continue
		if s.kind == "crew":
			_crew_scene(people, s)
			continue
		if s.kind == "recess":
			_recess_scene(people, s)
			continue
		if s.kind == "bus_stop":
			_stop_scene(people, s)
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
				# Out on the porch of an evening in a pair of chairs, watching
				# the street.
				for i in (2 if seed % 3 == 0 else 1):
					var at := front + into * 7.6 + along * (1.5 - i * 0.9)
					props.chair.append(Transform3D(Basis.looking_at(-into, Vector3.UP), Terrain.stand(at - into * 0.1) + Vector3(0, 0.22, 0)))
					props.chair_back.append(Transform3D(Basis.looking_at(-into, Vector3.UP), Terrain.stand(at + into * 0.15) + Vector3(0, 0.7, 0)))
					_person(people, at, -into, seed >> (i * 4), -1.0, 1.0, true)
			"dog":
				var u := fposmod(t * 1.1, 60.0)
				var x := u if u < 30.0 else 60.0 - u
				var heading := along if u < 30.0 else -along
				var p := walk + along * (x - 15.0)
				_person(people, p, heading, seed, t * 1.1)
				# The dog a leash-length ahead and to the side, trotting.
				var side := heading.cross(Vector3.UP).normalized()
				var dog := WalkerView.dog_of(seed)
				var dp := Terrain.stand(p + heading * 1.5 + side * 0.45)
				var coat: Color = dog[0]
				coat.a = fposmod(t * 1.1, WalkerView.DOG_STRIDE * dog[1]) / (WalkerView.DOG_STRIDE * dog[1])
				dogs.append([Transform3D(Basis.looking_at(heading, Vector3.UP).scaled(Vector3.ONE * dog[1]), dp), coat])
				var hand := Terrain.stand(p) + side * 0.25 + Vector3(0, 0.82, 0)
				var collar: Vector3 = dp + Vector3(0, 0.55 * float(dog[1]), 0) - heading * 0.3 * float(dog[1])
				props.leash.append(Transform3D(Basis.looking_at(collar - hand, Vector3.UP).scaled(Vector3(1, 1, hand.distance_to(collar))),
					(hand + collar) * 0.5))
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
			"snowman":
				# Two kids and their snowman on the front lawn.
				var p := lawn + along * (float(seed % 7) - 3.0)
				props.snowball.append(Transform3D(Basis(), Terrain.stand(p) + Vector3(0, 0.45, 0)))
				props.snowhead.append(Transform3D(Basis(), Terrain.stand(p) + Vector3(0, 1.15, 0)))
				_person(people, p - along * 1.1, along, seed, -1.0, 0.62)
				var k := fposmod(t * 0.4, 6.0)
				_person(people, p + along * 1.4 + into * (k - 3.0) * 0.4, -along, seed >> 4, t * 0.4 if k < 3.0 else -1.0, 0.6)
			"lemonade":
				# Two kids at a table by the sidewalk; now and then a neighbour buys a cup.
				var p := walk + into * 1.6 + along * (float(seed % 5) - 2.0)
				props.table.append(Transform3D(Basis.looking_at(-into, Vector3.UP), Terrain.stand(p) + Vector3(0, 0.38, 0)))
				_person(people, p + into * 0.7 - along * 0.4, -into, seed, -1.0, 0.62)
				_person(people, p + into * 0.7 + along * 0.4, -into, seed >> 3, -1.0, 0.6)
				if fmod(t, 20.0) < 8.0:
					_person(people, p - into * 0.9, into, seed >> 6, -1.0)
			"bike":
				# A kid riding up and down the sidewalk.
				var u := fposmod(t * 3.5, 140.0)
				var x := u if u < 70.0 else 140.0 - u
				var heading := along if u < 70.0 else -along
				var p := walk + along * (x - 35.0)
				props.bike.append(Transform3D(Basis.looking_at(heading, Vector3.UP), Terrain.stand(p) + Vector3(0, 0.35, 0)))
				_person(people, p, heading, seed, -1.0, 0.68)
			"hoops":
				# Shooting baskets at a hoop by the garage.
				var hoop := front + into * 6.0 + along * (width * 0.3)
				props.pole.append(Transform3D(Basis(), Terrain.stand(hoop) + Vector3(0, 1.52, 0)))
				props.board.append(Transform3D(Basis.looking_at(-into, Vector3.UP), Terrain.stand(hoop - into * 0.2) + Vector3(0, 3.2, 0)))
				var p := hoop - into * 4.0 + along * 1.5 * sin(t * 0.5)
				_person(people, p, into, seed, -1.0, 0.85)
				var k := fposmod(t * 0.8, 2.0)
				var ball_at := p.lerp(hoop - into * 0.5, minf(k, 1.0)) if k < 1.0 else (hoop - into * 0.5).lerp(p, k - 1.0)
				var lift := 1.5 + sin(minf(k, 1.0) * PI) * 2.2 if k < 1.0 else 0.4 + absf(sin((k - 1.0) * PI * 3.0)) * 0.8
				props.ball.append(Transform3D(Basis(), Terrain.stand(ball_at) + Vector3(0, lift, 0)))
			"yard_sale":
				# Tables on the lawn, the family behind them, neighbours browsing.
				for i in 2:
					var p := lawn + along * (i * 2.4 - 1.2)
					props.table.append(Transform3D(Basis.looking_at(-into, Vector3.UP), Terrain.stand(p) + Vector3(0, 0.38, 0)))
				_person(people, lawn + into * 1.0, -into, seed, -1.0)
				var k := fposmod(t * 0.3, 8.0)
				_person(people, lawn - into * 1.0 + along * (k - 4.0) * 0.6, along, seed >> 3, t * 0.3)
				_person(people, lawn - into * 1.1 - along * 1.5, into, seed >> 6, -1.0)
			"costumes":
				# Little ones in costumes going door to door, a parent behind.
				var u := fposmod(t * 1.0, 60.0)
				var x := u if u < 30.0 else 60.0 - u
				var heading := along if u < 30.0 else -along
				var p := walk + along * (x - 15.0)
				for i in 3:
					var at := p + heading * (0.8 * i) + into * (0.5 if i % 2 == 0 else -0.3)
					var before := people.size()
					_person(people, at, heading, seed >> i, t * 1.0, 0.55)
					var dress: Color = COSTUMES[(seed >> (i * 3)) % COSTUMES.size()]
					dress.a = (people[before][1] as Color).a
					people[before][1] = dress
				_person(people, p - heading * 1.8, heading, seed >> 9, t * 1.0)
	var mm := _people.multimesh
	if mm.instance_count < people.size():
		mm.instance_count = maxi(people.size() * 2, 32)
	for i in people.size():
		mm.set_instance_transform(i, people[i][0])
		mm.set_instance_color(i, people[i][2])
		mm.set_instance_custom_data(i, people[i][1])
	mm.visible_instance_count = people.size()
	var dm := _dogs.multimesh
	if dm.instance_count < dogs.size():
		dm.instance_count = maxi(dogs.size() * 2, 8)
	for i in dogs.size():
		dm.set_instance_transform(i, dogs[i][0])
		dm.set_instance_color(i, Color.WHITE)
		dm.set_instance_custom_data(i, dogs[i][1])
	dm.visible_instance_count = dogs.size()
	for k in props:
		var pm: MultiMesh = _props[k].multimesh
		var list: Array = props[k]
		if pm.instance_count < list.size():
			pm.instance_count = maxi(list.size() * 2, 8)
		for i in list.size():
			pm.set_instance_transform(i, list[i])
		pm.visible_instance_count = list.size()


## People waiting at a bus stop: on the shelter's bench if it has one,
## else standing by the pole, turned to look up the street for the bus.
func _stop_scene(people: Array, s: Dictionary) -> void:
	var st: Dictionary = s.stop
	var along: Vector3 = st.dir
	var out := Vector3(-along.z, 0.0, along.x) * float(st.side)
	var base: Vector3 = st.pos + out * (RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5)
	var walk := base + out * (RoadStyle.PARKWAY_WIDTH * 0.5 + RoadStyle.SIDEWALK_WIDTH * 0.5)
	var coming := along * float(st.side)  # the way the bus comes from (it pulls in facing dir * -side)
	var seed: int = s.seed
	var standing := 0
	for i in int(s.n):
		if s.shelter and i < 3:
			# The shelter's bench (BusView): 3 m back along the street, at the
			# sidewalk's far side.
			var back := -(RoadStyle.PARKWAY_WIDTH * 0.5 + RoadStyle.SIDEWALK_WIDTH + 0.9) - 0.6
			var at := base + along * (-3.0 + (i - 1) * 0.75) - out * back
			_person(people, at, -out, seed >> (i * 3), -1.0, 1.0, true)
			continue
		var at := walk + along * (-0.8 - standing * 0.9 + float((seed >> (i * 2)) % 5) * 0.1) \
			+ out * (float((seed >> (i * 3)) % 3) - 1.0) * 0.35
		_person(people, at, (-out * 0.6 + coming).normalized(), seed >> (i * 3), -1.0)
		standing += 1


## A park scene: someone on a bench (drawn low, as if seated), a picnic on a
## blanket, a stroll round the park, a game of frisbee, or sledding in the
## snow.
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
			# Seated, set back on the seat.
			_person(people, spot + dir * 0.12, -dir, seed, -1.0, 1.0, true)
			if seed % 3 == 0:
				_person(people, spot + side * 0.6 + dir * 0.12, -dir, seed >> 3, -1.0, 1.0, true)
		"picnic":
			props.blanket.append(Transform3D(Basis.looking_at(dir, Vector3.UP), Terrain.stand(spot) + Vector3(0, 0.02, 0)))
			_person(people, spot - side * 0.5, side, seed, -1.0, 0.6)
			_person(people, spot + side * 0.5, -side, seed >> 4, -1.0, 0.6)
		"stroll":
			var a := t * 0.05 + float(seed % 6)
			var r := minf(size.x, size.y) * 0.35
			var p := c + side * cos(a) * r + dir * sin(a) * r
			_person(people, p, -side * sin(a) + dir * cos(a), seed, a * r)
		"sled":
			# Down the park's slope on a sled, then the long walk back up.
			var u := fposmod(t * 0.35, 3.0)
			var top := spot - dir * 9.0
			var foot := spot + dir * 9.0
			if u < 1.0:
				var p := top.lerp(foot, u)
				props.sled.append(Transform3D(Basis.looking_at(dir, Vector3.UP), Terrain.stand(p) + Vector3(0, 0.06, 0)))
				_person(people, p, dir, seed, -1.0, 0.45)  # sitting on the sled
			else:
				var p := foot.lerp(top, (u - 1.0) / 2.0)
				props.sled.append(Transform3D(Basis.looking_at(-dir, Vector3.UP), Terrain.stand(p - dir * 0.8) + Vector3(0, 0.06, 0)))
				_person(people, p, -dir, seed, t * 0.35 * 9.0, 0.62)
		"frisbee":
			var a2 := spot - side * 6.0
			var b2 := spot + side * 6.0
			_person(people, a2, side, seed, -1.0)
			_person(people, b2, -side, seed >> 4, -1.0)
			var k := fposmod(t * 0.6, 2.0)
			var u := k if k < 1.0 else 2.0 - k
			props.disc.append(Transform3D(Basis(), Terrain.stand(a2.lerp(b2, u)) + Vector3(0, 1.4 + sin(u * PI) * 1.2, 0)))


## Builders at a house going up: one walks to and from the truck, two work
## along the walls, stopping and starting.
func _crew_scene(people: Array, s: Dictionary) -> void:
	var seed: int = s.seed
	var fr: Vector3 = s.front
	var into: Vector3 = -(s.out as Vector3)
	var along := Vector3(-into.z, 0.0, into.x)
	var t := _clock + float(seed % 97)
	var u := fposmod(t * 0.5, 16.0)
	var x := u if u < 8.0 else 16.0 - u
	_person(people, fr + into * (1.0 + x), into if u < 8.0 else -into, seed, t * 0.5)
	for k in 2:
		var side := -1.0 if k == 0 else 1.0
		var p := fr + into * (10.0 + 3.0 * k) + along * side * (4.0 + 1.5 * sin(t * 0.3 + k))
		_person(people, p, -along * side, seed >> (k + 2), -1.0 if fmod(t + k * 3.0, 6.0) < 4.0 else t * 0.4)


## Recess: children running about the school yard, a teacher watching.
func _recess_scene(people: Array, s: Dictionary) -> void:
	var sb: Dictionary = s.school
	var seed: int = s.seed
	var c: Vector3 = sb.pos
	var dir: Vector3 = sb.dir if sb.dir is Vector3 else Vector3.FORWARD
	var side := Vector3(-dir.z, 0.0, dir.x)
	var yard := c + dir * 30.0
	var t := _clock
	for i in 13:
		var a := t * (0.8 + float((seed >> i) % 7) * 0.1) + i * 0.7
		var r := 4.0 + float((seed >> (i + 3)) % 12)
		var p := yard + side * cos(a) * r + dir * sin(a) * r * 0.6
		_person(people, p, -side * sin(a) + dir * cos(a) * 0.6, seed >> i, a * r * 0.3, 0.62)
	_person(people, yard - dir * 6.0, dir, seed >> 20, -1.0)
