extends SceneTree
## Median and top speeds (mph) of moving cars by road kind in a small town,
## for checking that drivers drive the limit. Run: godot --headless -s tools/speed_check.gd
func _init() -> void:
	var sim := CitySim.new()
	PerfTown.build(sim, "3")
	var by := {}
	for i in 1440 * 2:
		sim.tick()
		if i > 1440 and i % 5 == 0:
			for c in sim.traffic.cars:
				if c.get("leg", -1) < 0 or c.v < 1.0 or not c.has("route") or c.route.is_empty():
					continue
				var w: Dictionary = sim.traffic.ways.get(c.route[mini(c.leg, c.route.size() - 1)], {})
				if w.is_empty():
					continue
				var spec: Dictionary = RoadStyle.TYPES[w.type]
				var k := "%s (%d mph)" % [spec.name, spec.mph]
				if not by.has(k):
					by[k] = []
				by[k].append(c.v / RoadStyle.MPH)
	for k in by:
		var a: Array = by[k]
		a.sort()
		print("SPEED %s: median %.0f, top 10%% %.0f mph (%d samples)" % [k, a[a.size() / 2], a[a.size() * 9 / 10], a.size()])
	quit()
