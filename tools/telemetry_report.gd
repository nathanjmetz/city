extends SceneTree
## Turns the region server's play telemetry into a ranked fix list.
##
##   godot --headless -s tools/telemetry_report.gd -- ~/neighbors-region-telemetry [report.md] [days]
##
## Writes report.md (for people) and report.json (the same fixes, for
## tools) next to it, and prints the top of the list. The server also
## keeps report.md in the telemetry folder up to date on its own.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Usage: godot --headless -s tools/telemetry_report.gd -- TELEMETRY_DIR [report.md] [days]")
		quit(1)
		return
	var dir := args[0]
	var out := args[1] if args.size() > 1 else dir.path_join("report.md")
	var days := int(args[2]) if args.size() > 2 else 14
	var r := Insights.analyze(Insights.read_dir(dir, days))
	var md := Insights.to_markdown(r)
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(md)
	f = FileAccess.open(out.get_basename() + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(r, "  "))
	print(md.left(3000))
	print("Wrote %s" % out)
	quit()
