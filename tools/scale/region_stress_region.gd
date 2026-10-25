extends SceneTree
## Makes a region save for the shared-region stress test: one big grown town
## per player (PerfTown, the same town the scale test uses) plus accounts and
## PINs for the players and for late joiners, whose towns the region makes
## when they first come in.
##
## Run: godot --headless -s tools/scale/region_stress_region.gd -- out.json players blocks [late]
##   players  how many towns to grow (Bot1 ... BotN)
##   blocks   blocks a side of each town ("12" is about 5,000 people, "20"
##            about 16,000, "30" about 38,000)
##   late     how many extra accounts to make for players that join later
##            (Late1 ... LateN), default 1
## Also writes out.json.players: name, PIN and city id of each, for the runner.

const FIRST_PIN := 600001


static func pin_of(index: int) -> String:
	return "%06d" % (FIRST_PIN + index)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "region.json"
	var players := int(args[1]) if args.size() > 1 else 4
	var blocks: String = args[2] if args.size() > 2 else "20"
	var late := int(args[3]) if args.size() > 3 else 1
	var region := Region.new()
	var accounts := {}
	var roster := []
	var t0 := Time.get_ticks_msec()
	for i in players:
		var name := "Bot%d" % (i + 1)
		var pid := "stress%d" % i
		var id := region.add_city(pid, name)
		var sim: CitySim = region.cities[id].sim
		sim.require_utilities = false
		PerfTown.build(sim, blocks)
		for t in 300:
			sim.tick()
		sim.require_utilities = true
		region.take_land(id, region.land_of_sim(id))
		region.touched(id)
		accounts[name.to_lower()] = {"name": name, "salt": "", "hash": "", "status": "approved",
			"player": pid, "host": i == 0, "tokens": [], "pin": pin_of(i)}
		roster.append({"name": name, "pin": pin_of(i), "city": id, "people": sim.stats.population,
			"buildings": sim.buildings.size()})
		print("%s: %d people, %d buildings (%.0f s)" % [name, sim.stats.population, sim.buildings.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	for j in late:
		var name := "Late%d" % (j + 1)
		accounts[name.to_lower()] = {"name": name, "salt": "", "hash": "", "status": "approved",
			"player": "stresslate%d" % j, "host": false, "tokens": [], "pin": pin_of(players + j)}
		roster.append({"name": name, "pin": pin_of(players + j), "city": "", "people": 0, "buildings": 0})
	var d := region.to_dict()
	d["code"] = "STRESS"
	d["accounts"] = accounts
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "", false, true))
	f.close()
	var g := FileAccess.open(out + ".players", FileAccess.WRITE)
	g.store_string(JSON.stringify(roster, "  "))
	g.close()
	quit()
