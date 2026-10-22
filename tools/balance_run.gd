extends SceneTree
## The balance harness: plays scripted cities headless and prints how their
## money, people and milestones go, so numbers in scripts/sim/balance.gd can
## be tuned against measured pacing instead of guesses.
## Run: godot --headless -s tools/balance_run.gd -- [days] [pattern ...]

const PATTERNS := ["planner", "grid_rush", "idle"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 30
	var patterns: Array = args.slice(1) if args.size() > 1 else PATTERNS
	var diffs: Array = Economy.DIFFICULTIES.keys()
	if OS.get_environment("DIFF") != "":
		diffs = [OS.get_environment("DIFF")]
	for p in patterns:
		for diff in diffs:
			var t := Time.get_ticks_msec()
			var play := BalancePlay.new(p, diff).play(n)
			print("\n== %s %s  (%d days, %.1f s)" % [p, diff, n, (Time.get_ticks_msec() - t) / 1000.0])
			for row in play.days:
				if row.day <= 5 or row.day % 5 == 0:
					print("  day %3d  money %12s  net/mo %9s  pop %5d  homes %4d  jobs %5d  free %3d  dem %s" % [row.day,
						CitySim.money_text(row.money), CitySim.money_text(row.net), row.pop, row.homes, row.jobs, row.free, row.dem])
			print("  ", play.summary())
	quit()
