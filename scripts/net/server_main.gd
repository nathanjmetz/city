extends SceneTree
## Runs a shared region with no window, for a home computer or a cloud server.
##
##   godot --headless -s scripts/net/server_main.gd -- --port 9080 --data region.json
##
## Options (or the same names as environment variables):
##   --port N      CITY_PORT    port to listen on (default 9080)
##   --code ABC123 CITY_CODE    invite code (default: made up once, then kept in the data file)
##   --data FILE   CITY_DATA    where the region is saved (default user://region.json)
##   --host NAMES  CITY_HOST    the host's player name(s), comma separated
##                              (default: whoever comes in first)
##   --telemetry DIR CITY_TELEMETRY_DIR  where play telemetry and its fix
##                              list (report.md) go (default: next to the
##                              data file, as <name>-telemetry/)
##   --approve yes CITY_APPROVE the host lets each new player in (default: the
##                              invite code is the only key)

var server: RegionServer


func _init() -> void:
	var opts := {
		"port": OS.get_environment("CITY_PORT"),
		"code": OS.get_environment("CITY_CODE"),
		"data": OS.get_environment("CITY_DATA"),
		"host": OS.get_environment("CITY_HOST"),
		"approve": OS.get_environment("CITY_APPROVE"),
		"telemetry": OS.get_environment("CITY_TELEMETRY_DIR"),
	}
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		if args[i].begins_with("--") and opts.has(args[i].substr(2)):
			opts[args[i].substr(2)] = args[i + 1]
	var port := int(opts.port) if opts.port != "" else 9080
	var data: String = opts.data if opts.data != "" else "user://region.json"
	if not data.begins_with("user://") and not data.begins_with("/"):
		data = OS.get_environment("PWD").path_join(data)
	server = RegionServer.new()
	server.require_approval = opts.approve in ["yes", "true", "1"]
	if opts.telemetry != "":
		server.telemetry_dir = opts.telemetry if opts.telemetry.begins_with("/") or opts.telemetry.begins_with("user://") \
			else OS.get_environment("PWD").path_join(opts.telemetry)
	root.add_child.call_deferred(server)
	var host: String = opts.host
	# The Mac mini's installed host script still passes its old default,
	# "Brawn"; Brawn plays as "Nathan Metz" (2026-10-24).
	if host == "Brawn":
		host = "Brawn,Nathan Metz"
	var err := server.start(port, opts.code, data, host)
	if err != OK:
		printerr("Couldn't open port %d (error %d)" % [port, err])
		quit(1)


func _finalize() -> void:
	if server:
		server.stop()
