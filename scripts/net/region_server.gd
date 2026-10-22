class_name RegionServer
extends Node
## Hosts a shared region over WebSockets, so players on the web, Mac and
## Windows can all join. It runs headless (no window) for a home computer or
## a cheap cloud server: see scripts/net/server_main.gd.
##
## The server owns the real Region. Players send commands for their own
## city; every tick the server applies what arrived, steps every city and
## sends the tick out, so every player's copy runs the same way.

signal log_line(text: String)

const PROTOCOL := 1
## How often the region is written to disk, in seconds (a server that's
## switched off loses at most this much).
const SAVE_EVERY := 10.0
## How often players get checksums to compare against, in ticks.
const CHECK_EVERY := 50

var region := Region.new()
var invite_code := ""
var data_path := ""

var _peer := WebSocketMultiplayerPeer.new()
var _players := {}   # peer id -> {"id": player id, "name", "city"}
var _events := []    # waiting for the next tick: ["city", id, name] or ["cmd", city, cmd]
var _tick_time := 0.0
var _save_time := 0.0
var _dirty := false


## Starts listening. Returns an error code (OK when it worked).
func start(port: int, code: String, path: String) -> int:
	data_path = path
	invite_code = code.to_upper()
	_load()
	if invite_code == "":
		invite_code = new_code()
		_dirty = true
	var err := _peer.create_server(port)
	if err != OK:
		return err
	_peer.peer_connected.connect(func(id): _log("Peer %d connected" % id))
	_peer.peer_disconnected.connect(_on_left)
	_log("Region running on port %d. Invite code: %s" % [port, invite_code])
	if _dirty:
		save()
	return OK


func stop() -> void:
	save()
	_peer.close()
	_players.clear()
	set_process(false)


## Six letters and digits, leaving out ones that look alike (0/O, 1/I/L).
static func new_code() -> String:
	const CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := ""
	for i in 6:
		s += CHARS[rng.randi() % CHARS.length()]
	return s


func _process(delta: float) -> void:
	_peer.poll()
	while _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var msg = JSON.parse_string(_peer.get_packet().get_string_from_utf8())
		if typeof(msg) == TYPE_DICTIONARY:
			_handle(from, msg)
	_tick_time += delta
	var step := 1.0 / CitySim.TICKS_PER_SECOND
	var guard := 0
	while _tick_time >= step and guard < 20:
		_tick_time -= step
		guard += 1
		_step()
	_tick_time = minf(_tick_time, step)
	_save_time += delta
	if _save_time >= SAVE_EVERY:
		_save_time = 0.0
		if _dirty:
			save()


func _step() -> void:
	var events := _events
	_events = []
	for e in events:
		match e[0]:
			"city":
				if region.city_of(e[1]) != "":
					continue
				var id := region.add_city(e[1], e[2])
				for peer in _players:
					if _players[peer].id == e[1]:
						_players[peer].city = id
			"cmd":
				region.apply(e[1], e[2])
	region.tick()
	if not events.is_empty():
		_dirty = true
	_broadcast({"t": "tick", "n": region.tick_count, "ev": events})
	if region.tick_count % CHECK_EVERY == 0:
		_broadcast({"t": "sums", "n": region.tick_count, "sums": region.checksums()})


func _handle(from: int, msg: Dictionary) -> void:
	if not _players.has(from):
		if msg.get("t") == "hello":
			_hello(from, msg)
		return
	var p: Dictionary = _players[from]
	match msg.get("t", ""):
		"cmd":
			# A player can only change their own city.
			if p.city != "" and typeof(msg.get("cmd")) == TYPE_DICTIONARY:
				_events.append(["cmd", p.city, msg.cmd])
		"chat":
			var text := str(msg.get("text", "")).strip_edges()
			if text != "":
				var line := region.add_chat(p.name, text)
				_dirty = true
				_broadcast({"t": "chat", "line": line})
		"cursor":
			_broadcast({"t": "cursor", "id": p.id, "p": msg.get("p")}, from)
		"resync":
			_log("%s's copy drifted; sending a fresh one" % p.name)
			_send(from, {"t": "region", "region": region.to_dict()})


func _hello(from: int, msg: Dictionary) -> void:
	if int(msg.get("v", 0)) != PROTOCOL:
		_reject(from, "This region runs a different version of the game. Refresh to update.")
		return
	if str(msg.get("code", "")).to_upper().replace("-", "").strip_edges() != invite_code:
		_reject(from, "That invite code doesn't match this region.")
		return
	var pid := str(msg.get("id", "")).left(64)
	var name := str(msg.get("name", "")).strip_edges().left(24)
	if pid == "" or name == "":
		_reject(from, "Pick a name first.")
		return
	for peer in _players:
		if _players[peer].id == pid:
			_reject(from, "You're already playing in this region in another window.")
			return
	var city := region.city_of(pid)
	_players[from] = {"id": pid, "name": name, "city": city}
	if city == "":
		_events.append(["city", pid, name])
	elif region.cities[city].player != name:
		region.cities[city].player = name
	_log("%s joined" % name)
	# The full region as it is now; ticks from here on keep it in step. The
	# server and everyone already here reload the same copy too, so nothing a
	# save rounds off (road coordinates, say) can make one copy drift.
	var snapshot = JSON.parse_string(JSON.stringify(region.to_dict(), "", false, true))
	region.from_dict(snapshot)
	_broadcast({"t": "region", "region": snapshot}, from)
	_send(from, {"t": "welcome", "you": pid, "code": invite_code, "region": snapshot})
	_send_players()
	var line := region.add_chat("", "%s joined the region" % name)
	_broadcast({"t": "chat", "line": line})


func _on_left(peer: int) -> void:
	if not _players.has(peer):
		return
	var name: String = _players[peer].name
	_players.erase(peer)
	_log("%s left" % name)
	_send_players()
	_broadcast({"t": "chat", "line": region.add_chat("", "%s left the region" % name)})


func _send_players() -> void:
	var list := []
	for peer in _players:
		list.append({"id": _players[peer].id, "name": _players[peer].name})
	_broadcast({"t": "players", "list": list})


func _reject(peer: int, reason: String) -> void:
	_send(peer, {"t": "reject", "reason": reason})
	_log("Turned away peer %d: %s" % [peer, reason])


func _send(peer: int, msg: Dictionary) -> void:
	_peer.set_target_peer(peer)
	_peer.put_packet(JSON.stringify(msg, "", false, true).to_utf8_buffer())


func _broadcast(msg: Dictionary, except := 0) -> void:
	var bytes := JSON.stringify(msg, "", false, true).to_utf8_buffer()
	for peer in _players:
		if peer != except:
			_peer.set_target_peer(peer)
			_peer.put_packet(bytes)


func save() -> void:
	if data_path == "":
		return
	var d := region.to_dict()
	d["code"] = invite_code
	var f := FileAccess.open(data_path + ".tmp", FileAccess.WRITE)
	if f == null:
		_log("Couldn't save to %s" % data_path)
		return
	f.store_string(JSON.stringify(d, "", false, true))
	f.close()
	DirAccess.rename_absolute(data_path + ".tmp", data_path)
	_dirty = false


func _load() -> void:
	if data_path == "" or not FileAccess.file_exists(data_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if typeof(d) != TYPE_DICTIONARY:
		_log("Couldn't read %s, starting a new region" % data_path)
		return
	region.from_dict(d)
	if invite_code == "":
		invite_code = str(d.get("code", ""))
	_log("Loaded %d cities from %s" % [region.cities.size(), data_path])


func _log(text: String) -> void:
	print(text)
	log_line.emit(text)
