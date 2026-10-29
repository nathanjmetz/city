extends SceneTree
## Renders every town service, care building, landmark, campus and factory
## on its own plain pad, one picture each, for the civic and industry
## realism loop (compare each with photos of the real thing).
## Run: godot --resolution 1600x900 -s tools/civic_gallery.gd -- out_dir [item ...]
## Items: fire police clinic school substation water_tower well bus taxi
## builder traffic hospital nursing daycare courthouse town_tower elevator
## football fairgrounds trailhead park high_school college university
## mill sawmill refinery metal general warehouse cemetery landfill recycling.
## No items: all of them.
## "item@yaw,pitch,dist" sets the camera; --quality=ultra picks the tier.

const ALL := ["fire", "police", "clinic", "school", "substation", "water_tower", "well", "bus", "taxi",
	"builder", "traffic", "hospital", "nursing", "daycare", "courthouse", "town_tower", "elevator",
	"football", "fairgrounds", "trailhead", "park", "high_school", "college", "university",
	"mill", "sawmill", "refinery", "metal", "general", "warehouse", "cemetery", "landfill", "recycling"]
const SVC := {"fire": Services.Kind.FIRE, "police": Services.Kind.POLICE, "clinic": Services.Kind.CLINIC,
	"school": Services.Kind.SCHOOL, "substation": Services.Kind.SUBSTATION, "water_tower": Services.Kind.WATER_TOWER,
	"well": Services.Kind.WELL, "bus": Services.Kind.BUS_DEPOT, "taxi": Services.Kind.TAXI_COMPANY,
	"builder": Services.Kind.BUILDER_YARD, "traffic": Services.Kind.TRAFFIC_CENTER}
const CARE := {"hospital": Services.Kind.HOSPITAL, "nursing": Services.Kind.NURSING_HOME, "daycare": Services.Kind.DAYCARE}
const SITE := {"courthouse": "courthouse", "town_tower": "water_tower", "elevator": "grain_elevator",
	"football": "football", "fairgrounds": "fairgrounds", "trailhead": "trailhead", "park": "park"}

var _items := []  # [name, centre, size, yaw, pitch, dist]
var _frames := 0
var _cam: Camera3D
var _out := "."
var _at := 0
var _wait := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "."
	var want := []
	for a in args.slice(1):
		if not a.begins_with("--"):
			want.append(a)
	if want.is_empty():
		want = ALL
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(SkyLight.new())
	world.add_child(Ground.new())
	var trees := TreeField.new()
	world.add_child(trees)
	var seed := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 3
	var to_curb := Services.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	for w in want:
		var name := str(w).get_slice("@", 0)
		# "general#7": that seed instead of SEED.
		var sd := seed
		if name.contains("#"):
			sd = int(name.get_slice("#", 1))
			name = name.get_slice("#", 0)
		var lot_front := false
		var view := [25.0, 28.0, 0.0]
		if str(w).contains("@"):
			var v := str(w).get_slice("@", 1).split(",")
			view = [float(v[0]), float(v[1]), float(v[2]) if v.size() > 2 else 0.0]
		var built := []
		var size := Vector2(30, 30)
		if SVC.has(name):
			size = Services.KINDS[SVC[name]].size
			built = CivicBuilder.build_service(SVC[name], sd, size, to_curb)
		elif CARE.has(name):
			size = Services.KINDS[CARE[name]].size
			built = HealthBuilder.build_care(CARE[name], sd, size, to_curb)
		elif SITE.has(name):
			var k: String = SITE[name]
			size = Balance.AMENITIES[k].get("size", Vector2(70, 60))
			var site := {"kind": k, "tier": 2, "size": size, "name": Parks.LANDMARK_NAMES.get(k, "Lincoln Park"),
				"pos": Vector3.ZERO, "dir": Vector3(0, 0, -1), "features": []}
			if k == "park":
				site.name = "Lincoln Park"
				site.features = [{"type": "paths", "pos": Vector3.ZERO, "size": Vector2.ZERO},
					{"type": "playground", "pos": Vector3(-18, 0, -8), "size": Vector2(16, 14)},
					{"type": "pavilion", "pos": Vector3(14, 0, -6), "size": Vector2(12, 9)},
					{"type": "court", "pos": Vector3(14, 0, 14), "size": Vector2(15, 14)}]
			built = ParkBuilder.build_site(site, sd, to_curb, "Swayzee")
		elif name in ["high_school", "college", "university"]:
			size = Vector2(120, 120)
			built = CampusBuilder.build_main(name, sd, to_curb)
		elif name in ["cemetery", "landfill", "recycling"]:
			# A hub grown over three pieces across and two back.
			var cells := []
			for x in [-1, 0, 1]:
				for y in [0, 1]:
					cells.append(Vector2i(x, y))
			size = Vector2(150, 100)
			lot_front = true
			var hub := HubBuilder.build_hub({"kind": "recycling_1" if name == "recycling" else name, "cells": cells,
				"cell": 50.0, "built": [], "received": 40_000_000}, sd, to_curb)
			built = [hub[0], hub[1], hub[2], [], hub[3]]
		elif name == "warehouse":
			size = Vector2(80, 90)
			built = WarehouseBuilder.build_warehouse({"kind": "medium", "bays": 0, "level": 1, "built": []}, sd, to_curb)
		else:
			# An industry-zoned lot, built from its front edge like the game's.
			size = Vector2(44, 64)
			lot_front = true
			built = FactoryBuilder.build_chain(name, sd, 3.9, {"width": size.x, "depth": size.y})
		# A grid of 400 m cells, on the middle of the ground plane.
		var n := _items.size()
		var at := Vector3((n % 6) * 400.0 - 1000.0, 0, (n / 6) * 400.0 - 1000.0)
		for i in mini(2, built.size()):
			var mi := MeshInstance3D.new()
			mi.mesh = built[i]
			mi.position = at
			world.add_child(mi)
		if built.size() > 4 and built[4] is Mesh:
			var lawn := MeshInstance3D.new()
			lawn.mesh = built[4]
			lawn.position = at
			world.add_child(lawn)
		# A street in front (-z), like the game's.
		var road := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(size.x + 80.0, 9.0)
		road.mesh = plane
		road.material_override = Surfaces.asphalt()
		road.position = at + Vector3(0, 0.05, (-3.9 if lot_front else -size.y * 0.5 - to_curb) - 4.5)
		world.add_child(road)
		var planted := []
		if built.size() > 2:
			for t in built[2]:
				planted.append([Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * t[3]), at + t[0]), t[1], t[2]])
		trees.set_trees(str(_items.size()), planted)
		var dist: float = view[2] if view[2] > 0.0 else maxf(size.x, size.y) * 1.35 + 25.0
		var look := at + Vector3(0, 0, size.y * 0.5 if lot_front else 0.0)
		var shot := str(w).get_slice("@", 0).replace("#", "-")
		for other in _items:
			if other[0] == shot:
				shot += "-%d" % _items.size()
		_items.append([shot, look, size, view[0], view[1], dist])
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 4000.0
	_cam.near = 1.0  # like the game camera; 5 cm loses yards under the lawn far off
	world.add_child(_cam)
	_aim(0)


func _aim(i: int) -> void:
	var it: Array = _items[i]
	var yaw := deg_to_rad(float(it[3]))
	var pitch := deg_to_rad(float(it[4]))
	var target: Vector3 = it[1] + Vector3(0, 3, 0)
	_cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * float(it[5])
	_cam.basis = Basis.looking_at(target - _cam.position)
	_cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 30:
		return false
	_wait += 1
	if _wait < 6:
		return false
	var path := "%s/%s.png" % [_out, _items[_at][0]]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	_at += 1
	_wait = 0
	if _at >= _items.size():
		quit()
		return false
	_aim(_at)
	return false
