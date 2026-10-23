extends SceneTree
## The desktop app's first-run graphics guess and the version range that
## lets slightly different builds share a region.
## Run: godot --headless -s tests/test_desktop.gd

var _failed := false


func _init() -> void:
	var dgpu := RenderingDevice.DEVICE_TYPE_DISCRETE_GPU
	var igpu := RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	_check(GraphicsQuality.guess_tier("Apple M2 Max", igpu, 12, 48.0) == GraphicsQuality.CINEMATIC,
		"a Mac Studio with 48 GB starts on Cinematic")
	_check(GraphicsQuality.guess_tier("Apple M2", igpu, 8, 8.0) == GraphicsQuality.MEDIUM,
		"an 8 GB Mac mini starts on Medium")
	_check(GraphicsQuality.guess_tier("Apple M4 Pro", igpu, 12, 24.0) == GraphicsQuality.HIGH, "a Pro chip starts on High")
	_check(GraphicsQuality.guess_tier("NVIDIA GeForce RTX 4070", dgpu, 16, 32.0) == GraphicsQuality.CINEMATIC,
		"a gaming PC starts on Cinematic")
	_check(GraphicsQuality.guess_tier("Intel(R) UHD Graphics 620", igpu, 4, 8.0) == GraphicsQuality.LOW,
		"an old office laptop starts on Low")
	_check(GraphicsQuality.guess_tier("llvmpipe (LLVM 20)", RenderingDevice.DEVICE_TYPE_CPU, 32, 64.0) == GraphicsQuality.LOW,
		"software drawing starts on Low")
	for t in GraphicsQuality.TIERS.size() - 1:
		var lo: Dictionary = GraphicsQuality.TIERS[t]
		var hi: Dictionary = GraphicsQuality.TIERS[t + 1]
		_check(hi.detail >= lo.detail and hi.shadow_size >= lo.shadow_size and hi.lod <= lo.lod,
			"%s never looks worse than %s" % [GraphicsQuality.NAMES[t + 1], GraphicsQuality.NAMES[t]])

	# Versions: the server takes anything from MIN_PROTOCOL to its own.
	var server := RegionServer.new()
	root.add_child(server)
	_check(server.start(9391, "ABC123", "user://test-desktop-region.json", "Host") == OK, "a region starts")
	_check(_hello(9391, {"v": RegionServer.PROTOCOL, "min": RegionServer.MIN_PROTOCOL}), "the same version gets in")
	_check(not _hello(9391, {"v": RegionServer.MIN_PROTOCOL - 1}), "a too-old game is turned away")
	_check(not _hello(9391, {"v": RegionServer.PROTOCOL + 1, "min": RegionServer.PROTOCOL + 1}),
		"a game that needs a newer server is turned away")
	server.stop()
	DirAccess.remove_absolute("user://test-desktop-region.json")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


## Whether a hello with these version fields is let in (welcomed or asked to
## wait) rather than turned away.
func _hello(port: int, versions: Dictionary) -> bool:
	var peer := WebSocketMultiplayerPeer.new()
	peer.create_client("ws://127.0.0.1:%d" % port)
	var msg := {"t": "hello", "code": "ABC123", "id": "t%d" % randi(), "name": "Tester %d" % randi_range(1, 9999),
		"password": "", "new": true, "token": ""}
	msg.merge(versions)
	var sent := false
	for i in 400:
		peer.poll()
		for n in root.get_children():
			if n is RegionServer:
				n._process(0.016)
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and not sent:
			peer.put_packet(JSON.stringify(msg).to_utf8_buffer())
			sent = true
		while peer.get_available_packet_count() > 0:
			var reply = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if typeof(reply) == TYPE_DICTIONARY and reply.get("t") in ["welcome", "waiting", "reject"]:
				peer.close()
				return reply.t != "reject"
		OS.delay_msec(5)
	peer.close()
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
