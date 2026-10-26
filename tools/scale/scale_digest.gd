extends SceneTree
## A fingerprint of a PerfTown grid town as it plays, to show a speed-up
## changed nothing the town does: run it before and after a change and the
## town hashes must match. Every PERIOD ticks it prints a hash of the saved
## town (to_dict: every building, person, car...) and its lots.
## Run: godot --headless -s tools/scale/scale_digest.gd -- BLOCKS TICKS [PERIOD]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ticks := int(args[1])
	var period: int = int(args[2]) if args.size() > 2 else 500
	var sim := CitySim.new()
	PerfTown.build(sim, args[0])
	print("DIGEST built ", _digest(sim))
	for i in ticks:
		sim.tick()
		if (i + 1) % period == 0:
			print("DIGEST tick ", sim.tick_count, " pop ", sim.stats.population, " lots ", sim.lots.size(),
				" buildings ", sim.buildings.size(), " money ", sim.economy.money, " ", _digest(sim))
	quit()


## The town without its lot planner's working state, then that state: the
## planner may re-cut a street side sooner or later (the lots come out the
## same), so a change can leave the first the same and the second not.
func _digest(sim: CitySim) -> String:
	var d := sim.to_dict()
	var plan = d.get("plan", {})
	d.erase("plan")
	var lots := {}
	for key in sim.lots:
		lots[key] = sim.lots[key]
	d.lots_now = lots
	return "town %s plan %s" % [JSON.stringify(d, "", true, true).sha256_text().substr(0, 16),
		JSON.stringify(plan, "", true, true).sha256_text().substr(0, 12)]
