extends SceneTree
## Makes a region save with grown neighbor towns, so the play-through can
## join a region like the family one (tools/playtest/).
## Run: godot --headless -s tools/playtest/make_region.gd -- out.json [towns] [size]

## Players that can join the test region, each with a PIN of their own
## (the play-through passes it as --playtest-pin).
const BOTS := ["Playtest", "Alice", "Bob", "Cara", "Dana"]


static func bot_pin(name: String) -> String:
	return "%06d" % (500001 + BOTS.find(name))


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "region.json"
	var towns := int(args[1]) if args.size() > 1 else 2
	var size: String = args[2] if args.size() > 2 else "small"
	var region := Region.new()
	var accounts := {}
	for i in towns:
		var name := "Neighbor %d" % (i + 1)
		var id := region.add_city("seed%d" % i, name)
		var sim: CitySim = region.cities[id].sim
		sim.require_utilities = false
		PerfTown.build(sim, size)
		for t in 300:
			sim.tick()
		sim.require_utilities = true
		region.touched(id)
		accounts[name.to_lower()] = {"name": name, "salt": "", "hash": "", "status": "approved",
			"player": "seed%d" % i, "host": i == 0, "tokens": []}
		print("%s: %d people" % [name, sim.stats.population])
	# The players the play-through and the soak test bring: a region only lets
	# in people it has a PIN for (their towns are made when they first join).
	for i in BOTS.size():
		accounts[BOTS[i].to_lower()] = {"name": BOTS[i], "salt": "", "hash": "", "status": "approved",
			"player": "bot%d" % i, "host": false, "tokens": [], "pin": bot_pin(BOTS[i])}
	var d := region.to_dict()
	d["code"] = "PLAYT1"
	d["accounts"] = accounts
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "", false, true))
	f.close()
	quit()
