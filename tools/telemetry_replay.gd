extends SceneTree
## Plays back what a player did, as a timeline: buttons, map clicks and
## drags (in town meters), keys, what the tool's hint said, and every
## command with whether the game took it.
##
##   godot --headless -s tools/telemetry_replay.gd -- ~/neighbors-region-telemetry [player] [last-minutes]
##
## Without a player it shows the latest session; last-minutes (default
## 30) keeps only the end of it.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Usage: godot --headless -s tools/telemetry_replay.gd -- TELEMETRY_DIR [player] [last-minutes]")
		quit(1)
		return
	var who := args[1] if args.size() > 1 else ""
	var minutes := float(args[2]) if args.size() > 2 else 30.0
	var batches := Insights.read_dir(args[0], 2).filter(func(b): return who == "" or str(b.get("from", "")) == who)
	if batches.is_empty():
		print("No play data%s." % ((" from " + who) if who != "" else ""))
		quit()
		return
	var session := str(batches.back().get("session", ""))
	var acts := []
	var flags := []
	for b in batches:
		if str(b.get("session", "")) != session:
			continue
		for e in b.get("events", []):
			if e.get("k") == "actions":
				acts.append_array(e.a)
			elif e.has("replay"):
				flags.append(e)
	if acts.is_empty():
		print("Session %s has no actions." % session)
		quit()
		return
	var end := float(acts.back()[0])
	print("%s, session %s, build %s" % [batches.back().get("from", "?"), session, batches.back().get("build", "?")])
	for a in acts:
		if end - float(a[0]) <= minutes * 60.0:
			print("%8.1f  %s" % [float(a[0]), Insights.action_text(a)])
	for f in flags:
		print("%8.1f  ** %s (%s)" % [float(f.t), f.k, f.get("ctx", "")])
	quit()
