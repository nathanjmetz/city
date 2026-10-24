class_name PerfTown
extends RefCounted
## Builds the big test town the performance benchmark plays
## (tools/perf_run.gd): a grid of streets, every block face zoned and built
## out and lived in, with services, a landfill, a cemetery, parks, farms and
## an oil company, so every system has real work to do.
##
## Sizes: "small" (about 1,000 people), "big" (about 10,000, the budget
## target), "huge" (about 25,000, to see where things break).

const BLOCKS := {"small": 4, "big": 12, "huge": 20}
const BLOCK := 140.0


static func build(sim: CitySim, size := "big") -> void:
	var n: int = BLOCKS.get(size, 12)
	var span := n * BLOCK
	var x0 := -span / 2.0
	var z0 := -span / 2.0
	sim.economy.money = 900_000_000
	sim.charter.reached.merge({"town": 0, "city": 0})
	sim.apply({"type": "build_county_road", "a": [x0 - 2000.0, z0 - 60.0], "b": [x0 + span + 2000.0, z0 - 60.0], "links": [0, 1]})
	sim.apply({"type": "build_grid", "a": [x0, z0], "b": [x0 + span, z0], "c": [x0, z0 + span], "block": BLOCK})
	# Tie the grid to the county road every few blocks.
	for i in range(0, n + 1, 3):
		var x := x0 + i * BLOCK
		sim.apply({"type": "build_road", "start": [x, z0 - 60.0], "ctrl": [x, z0 - 30.0], "end": [x, z0]})
	# Zones: shops along the middle avenue rows, factories along the east edge.
	for id in sim.network.segments.keys():
		for side in [-1, 1]:
			var c := sim.network.curve_of(id)
			var mid := RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
			var tan := RoadNetwork.bezier_tangent(c[0], c[1], c[2], 0.5)
			var p: Vector3 = mid + Vector3(-tan.z, 0.0, tan.x).normalized() * float(side) * 15.0
			if p.z < z0 - 5.0:
				continue  # leave the county road rural
			var zone := ZoneMap.Zone.RESIDENTIAL
			if p.x > x0 + span * 0.8:
				zone = ZoneMap.Zone.INDUSTRIAL
			elif absf(p.z) < BLOCK * 0.6 or absf(p.x) < BLOCK * 0.6:
				zone = ZoneMap.Zone.COMMERCIAL
			sim.apply({"type": "zone_frontage", "seg": id, "side": side, "zone": zone})
	# Services spread across town, one of each per few blocks.
	var kinds := [Services.Kind.SUBSTATION, Services.Kind.WATER_TOWER, Services.Kind.FIRE,
		Services.Kind.POLICE, Services.Kind.CLINIC, Services.Kind.SCHOOL]
	var step := maxi(n / 3, 1)
	var k := 0
	for i in range(0, n, step):
		for j in range(0, n, step):
			var at := Vector3(x0 + (i + 0.5) * BLOCK, 0, z0 + (j + 0.05) * BLOCK)
			var kind: int = kinds[k % kinds.size()]
			k += 1
			var site := Services.site_near(sim.network, kind, at)
			if not site.is_empty():
				sim.apply({"type": "place_service", "kind": kind, "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	# A landfill and a cemetery out along the county road, a park in town.
	for spot in [["landfill", Vector3(x0 - 500.0, 0, z0 - 100.0)], ["cemetery", Vector3(x0 - 900.0, 0, z0 - 100.0)]]:
		var site := CivicHubs.site_near(sim.network, spot[1])
		if not site.is_empty():
			sim.apply({"type": "place_hub", "kind": spot[0], "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	for at in [Vector3(x0 + BLOCK * 1.5, 0, z0 + BLOCK * 1.5), Vector3(x0 + span - BLOCK * 3.5, 0, z0 + span - BLOCK * 1.5)]:
		var site := Parks.site_near(sim.network, "park", at)
		if not site.is_empty():
			sim.apply({"type": "place_park", "kind": "park", "pos": [site[0].x, site[0].z], "dir": [site[1].x, site[1].z]})
	# A farm out past the edge of town.
	sim.apply({"type": "place_farmhouse", "pos": [x0 + span + 600.0, z0 - 140.0], "dir": [0, 1], "crop": "corn"})
	sim.tick()
	_fill(sim)


## Builds every empty zoned lot and moves people in, as if the town had
## grown for years.
static func _fill(sim: CitySim) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for key in sim.empty_zoned_lots():
		var z := sim.zones.zone_at(sim.lots[key].zone_pt)
		var bseed := rng.randi()
		var cap := CitySim.capacity(z, bseed)
		sim.buildings[key] = {"zone": z, "seed": bseed, "built": 0, "cap": cap,
			"occ": cap if z == ZoneMap.Zone.RESIDENTIAL else 0}
	sim.buildings_changed.emit()
	sim.update_stats()
