extends SceneTree
## Levels follow needs (Nathan, 2026-10-25: "the level goes up or down based
## on whether it has what it needs"): a grown home cut off from power or
## water drops a level after two game days, not at once; the clock survives
## a save; and an owner moves up only with most needs met.
var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	var sim := CitySim.new()
	sim.apply({"type": "build_road", "start": [-100, 0], "ctrl": [0, 0], "end": [100, 0]})
	for x in range(-100, 101, 10):
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
		sim.apply({"type": "paint_zone", "center": [x, 25], "radius": 12, "zone": ZoneMap.Zone.INDUSTRIAL})
	for i in 3000:
		sim.tick()
	var key := ""
	var keys := sim.buildings.keys()
	keys.sort()
	for k in keys:
		var b: Dictionary = sim.buildings[k]
		if int(b.zone) == ZoneMap.Zone.RESIDENTIAL and BuildingTypes.TYPES[BuildingTypes.type_of(b)].stages.size() >= 2:
			key = k
			break
	_check(key != "", "a home that can grow a stage")
	if key == "":
		quit(1)
		return
	var type := BuildingTypes.type_of(sim.buildings[key])
	sim.redevelop(key, type, 1)
	_check(int(sim.buildings[key].level) == 1, "it has grown a level")
	# Cut off: nothing happens at once.
	sim.require_utilities = true
	sim.services.served.clear()
	sim._decline()
	_check(int(sim.buildings[key].level) == 1 and sim.buildings[key].has("short"), "cut off: the clock starts, the level holds")
	var copy := CitySim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	_check(int(copy.buildings[key].get("short", -1)) == int(sim.buildings[key].short), "the clock survives a save")
	sim.tick_count += Balance.LEVEL_DOWN_AFTER - 60
	sim._decline()
	_check(int(sim.buildings[key].level) == 1, "a day and more without: still holding")
	sim.tick_count += 60
	sim._decline()
	_check(int(sim.buildings[key].level) == 0, "two days without power and water: down a level")
	_check(str(sim.buildings[key].why).begins_with("Lost a level"), "and the panel can say why")
	# Moving up needs most needs met.
	var lv := Inspect.needs(sim, key)
	_check(int(lv.met) < Balance.LEVEL_UP_MET, "with no power or water its needs are mostly unmet (%d%%)" % lv.met)
	print("level needs: %s" % ("all passed" if _fails == 0 else "%d failed" % _fails))
	quit(1 if _fails > 0 else 0)
