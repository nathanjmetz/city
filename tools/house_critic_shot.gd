extends "res://tools/street_critic_shot.gd"
## Street-level pictures of the houses in a grown town, for the houses
## critic: finds the house with the most houses round it and shoots its
## street at 40 m (front and back), 80 m and from low down.
## Run: godot -s tools/house_critic_shot.gd -- town.city OUT_DIR [--quality=ultra]
## (pass a copy of the .city: the game autosaves into it).

var _picked := false


func _initialize() -> void:
	super._initialize()
	_todo.clear()


func _process(d: float) -> bool:
	if not _picked and not _main.loading:
		_picked = true
		var sim: CitySim = _main.sim
		var homes := []
		for key in sim.buildings:
			if BuildingTypes.type_of(sim.buildings[key]) == "house" and sim.lots.has(key):
				homes.append(sim.lots[key])
		var best = null
		var most := -1
		for a in homes:
			var n := 0
			for b in homes:
				if (a.pos as Vector3).distance_to(b.pos) < 70.0:
					n += 1
			if n > most:
				most = n
				best = a
		if best != null:
			var to_street: Vector3 = best.front - best.pos
			var yaw := rad_to_deg(atan2(to_street.x, to_street.z))
			var p: Vector3 = best.pos
			print("homes at ", p, " with ", most, " nearby")
			_todo.append(["homes_40", p, yaw + 25.0, 30.0, 40.0])
			_todo.append(["homes_back_40", p, yaw + 180.0 + 20.0, 32.0, 40.0])
			_todo.append(["homes_80", p, yaw - 30.0, 35.0, 80.0])
			_todo.append(["homes_low", p, yaw + 60.0, 12.0, 45.0])
	return super._process(d)
