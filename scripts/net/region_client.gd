class_name RegionClient
extends Node
## A player's connection to a shared region. Keeps a copy of the whole
## region in step with the server: it gets the region once on joining, then
## every tick with the commands applied in it. Your own commands go to the
## server and come back in a tick, like everyone else's.

## In the region, with your city ready to play.
signal joined
signal failed(reason: String)
signal disconnected
signal chat_received(line: Dictionary)
signal players_changed
signal cursor_moved(player_id: String, pos: Vector2)
signal city_added(city_id: String)
## Signed up; the host still has to let you in. You join once they do.
signal waiting(message: String)
## (Host only) the list of players waiting to be let in changed.
signal requests_changed

var region := Region.new()
var player_id := ""
var player_name := ""
var invite_code := ""
var url := ""
## The city this player owns ("" until the server has made it).
var my_city := ""
## Who is online: [{"id", "name"}].
var players := []
var is_joined := false
## Saved on this device so the password isn't needed every time.
var token := ""
## True for the region's host, who decides who may play.
var is_host := false
## (Host only) names waiting to be let in.
var requests := []
## Seconds since the last tick arrived, for smooth car movement.
var since_tick := 0.0

var _peer: WebSocketMultiplayerPeer
var _connected := false
var _password := ""
var _new_account := false


## Connects and logs in (or, with new_account, signs up). Watch the joined,
## waiting and failed signals. A saved token stands in for the password.
func join(server_url: String, code: String, id: String, name: String, password := "",
		new_account := false, saved_token := "") -> void:
	url = server_url
	invite_code = code
	player_id = id
	player_name = name
	_password = password
	_new_account = new_account
	token = saved_token
	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_client(server_url)
	if err != OK:
		failed.emit("Couldn't reach %s." % server_url)
		_peer = null


func leave() -> void:
	if _peer:
		_peer.close()
	_peer = null
	_connected = false
	is_joined = false


## Sends one of your commands to the server. It applies in a coming tick.
func send_command(cmd: Dictionary) -> void:
	_send({"t": "cmd", "cmd": cmd})


## (Host only) lets a waiting player in, or turns them away.
func approve(name: String, ok: bool) -> void:
	_send({"t": "approve", "name": name, "ok": ok})


func send_chat(text: String) -> void:
	_send({"t": "chat", "text": text})


## Where you are pointing, in region coordinates, so others can see it.
func send_cursor(p: Vector2) -> void:
	_send({"t": "cursor", "p": [snappedf(p.x, 0.1), snappedf(p.y, 0.1)]})


func my_sim() -> CitySim:
	return region.cities[my_city].sim if region.cities.has(my_city) else null


func name_of(id: String) -> String:
	for p in players:
		if p.id == id:
			return p.name
	for c in region.cities.values():
		if c.owner == id:
			return c.player
	return "Someone"


func _process(delta: float) -> void:
	since_tick += delta
	if _peer == null:
		return
	_peer.poll()
	var state := _peer.get_connection_status()
	if state == MultiplayerPeer.CONNECTION_CONNECTED and not _connected:
		_connected = true
		_send({"t": "hello", "v": RegionServer.PROTOCOL, "code": invite_code,
			"id": player_id, "name": player_name, "password": _password, "new": _new_account, "token": token})
		_password = ""
	elif state == MultiplayerPeer.CONNECTION_DISCONNECTED:
		var was_joined := is_joined
		_peer = null
		_connected = false
		is_joined = false
		if was_joined:
			disconnected.emit()
		else:
			failed.emit("Couldn't connect to the region. Check the address, and that the server is running.")
		return
	while _peer and _peer.get_available_packet_count() > 0:
		var msg = JSON.parse_string(_peer.get_packet().get_string_from_utf8())
		if typeof(msg) == TYPE_DICTIONARY:
			_handle(msg)


func _handle(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"welcome":
			player_id = str(msg.you)
			player_name = str(msg.get("name", player_name))
			is_host = bool(msg.get("host", false))
			if str(msg.get("token", "")) != "":
				token = str(msg.token)
			region.from_dict(msg.region)
			my_city = region.city_of(player_id)
			is_joined = true
			# New players get their city in the next tick.
			if my_city != "":
				joined.emit()
		"waiting":
			token = str(msg.get("token", token))
			waiting.emit(str(msg.get("reason", "")))
		"requests":
			requests = msg.list
			requests_changed.emit()
		"reject":
			var reason := str(msg.get("reason", "The region turned you away."))
			leave()
			failed.emit(reason)
		"tick":
			_tick(msg)
		"sums":
			# Our copy drifted from the server's: ask for a fresh one.
			if int(msg.n) == region.tick_count and msg.sums != _sums_as_json():
				_send({"t": "resync"})
		"region":
			var old_ids := region.cities.keys()
			_replace_region(msg.region)
			for id in region.cities:
				if not id in old_ids:
					city_added.emit(id)
		"chat":
			region.chat.append(msg.line)
			chat_received.emit(msg.line)
		"players":
			players = msg.list
			players_changed.emit()
		"cursor":
			if msg.get("p") is Array and msg.p.size() == 2:
				cursor_moved.emit(str(msg.id), Vector2(float(msg.p[0]), float(msg.p[1])))


func _tick(msg: Dictionary) -> void:
	if int(msg.n) != region.tick_count + 1:
		return  # Already counted in the region we were sent.
	for e in msg.ev:
		match e[0]:
			"city":
				if region.city_of(e[1]) != "":
					continue  # The server skips these too.
				var id := region.add_city(e[1], e[2])
				city_added.emit(id)
				if e[1] == player_id:
					my_city = id
					joined.emit()
			"cmd":
				region.apply(e[1], e[2])
	region.tick()
	since_tick = 0.0


## Loads a fresh copy into the existing city sims, so the views drawing them
## keep working.
func _replace_region(d: Dictionary) -> void:
	region.tick_count = int(d.tick)
	region.chat = d.get("chat", [])
	for id in d.cities:
		var c: Dictionary = d.cities[id]
		if region.cities.has(id):
			region.cities[id].sim.from_dict(c.city)
		else:
			var sim := Region.new_sim()
			sim.from_dict(c.city)
			region.cities[id] = {"owner": str(c.owner), "player": str(c.get("player", "")),
				"name": str(c.name), "origin": Vector2(float(c.origin[0]), float(c.origin[1])),
				"color": int(c.color), "sim": sim}


## Checksums the way they arrive over the wire (JSON numbers are floats).
func _sums_as_json() -> Dictionary:
	return JSON.parse_string(JSON.stringify(region.checksums()))


func _send(msg: Dictionary) -> void:
	if _peer == null or not _connected:
		return
	_peer.put_packet(JSON.stringify(msg, "", false, true).to_utf8_buffer())
