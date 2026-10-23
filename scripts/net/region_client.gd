class_name RegionClient
extends Node
## A player's connection to a shared region. Your own town runs here, on
## this computer, and a copy goes to the server every few seconds (see
## send_town); the neighbors' towns arrive the same way from their
## computers, to be drawn. The server settles trade and places new towns.

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
	RegionServer.use_big_buffers(_peer)
	var err := _peer.create_client(server_url)
	if err != OK:
		failed.emit("Couldn't reach %s." % server_url)
		_peer = null


func leave() -> void:
	if _peer:
		send_town()
		_peer.poll()
		_peer.close()
	_peer = null
	_connected = false
	is_joined = false


## Sends the server a copy of your town, for the neighbors and to keep.
func send_town() -> void:
	var sim := my_sim()
	if sim and is_joined:
		_send({"t": "city", "z": RegionServer.pack(sim.to_dict())})


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


func _process(_delta: float) -> void:
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
			var d = RegionServer.unpack(str(msg.get("z", "")))
			if typeof(d) != TYPE_DICTIONARY:
				leave()
				failed.emit("The region sent something this game can't read. Refresh to update.")
				return
			region.from_dict(d)
			my_city = region.city_of(player_id)
			is_joined = true
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
		"region":
			var d = RegionServer.unpack(str(msg.get("z", "")))
			if typeof(d) == TYPE_DICTIONARY:
				var old_ids := region.cities.keys()
				_replace_region(d)
				for id in region.cities:
					if not id in old_ids:
						city_added.emit(id)
		"city":
			# A neighbor's town, fresh from their computer.
			var id := str(msg.get("id", ""))
			var d = RegionServer.unpack(str(msg.get("z", "")))
			if id != my_city and region.cities.has(id) and typeof(d) == TYPE_DICTIONARY:
				region.update_city(id, d)
		"apply":
			# Roads the region built in your town (a new neighbor's county road).
			for cmd in msg.get("cmds", []):
				my_sim().apply_now(cmd)
		"trade":
			my_sim().trade.receive(my_sim(), msg.get("deals", []))
		"interlocal":
			# Service deals with neighbor towns: offers, signings, the month's numbers.
			my_sim().interlocal.receive(my_sim(), msg.get("ops", []))
		"chat":
			region.chat.append(msg.line)
			chat_received.emit(msg.line)
		"players":
			players = msg.list
			players_changed.emit()
		"cursor":
			if msg.get("p") is Array and msg.p.size() == 2:
				cursor_moved.emit(str(msg.id), Vector2(float(msg.p[0]), float(msg.p[1])))


## Loads a fresh copy into the existing city sims, so the views drawing them
## keep working. Your own town runs here, so it is never replaced.
func _replace_region(d: Dictionary) -> void:
	region.chat = d.get("chat", [])
	var r := Region.new()
	r.from_dict({"joins": d.get("joins", [])})
	region.joins = r.joins
	for id in d.cities:
		var c: Dictionary = d.cities[id]
		if id == my_city or not c.has("city"):
			continue
		if region.cities.has(id):
			region.update_city(id, c.city)
		else:
			var sim := Region.new_sim()
			sim.terrain_offset = Vector2(float(c.origin[0]), float(c.origin[1]))
			sim.from_dict(c.city)
			region.cities[id] = {"owner": str(c.owner), "player": str(c.get("player", "")),
				"name": str(c.name), "origin": Vector2(float(c.origin[0]), float(c.origin[1])),
				"color": int(c.color), "sim": sim}


func _send(msg: Dictionary) -> void:
	if _peer == null or not _connected:
		return
	_peer.put_packet(JSON.stringify(msg, "", false, true).to_utf8_buffer())
