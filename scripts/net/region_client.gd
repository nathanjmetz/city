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
## Back in the region after a dropped connection (the town kept running).
signal reconnected
signal chat_received(line: Dictionary)
signal players_changed
signal cursor_moved(player_id: String, pos: Vector2)
signal city_added(city_id: String)
## Signed up; the host still has to let you in. You join once they do.
signal waiting(message: String)
## (Host only) the list of players waiting to be let in changed.
signal requests_changed
## The server has stored a telemetry batch (by its id), so it can be dropped here.
signal telemetry_acked(id: String)
## Regional projects or service agreements changed (region.ledger).
signal ledger_changed

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
## Your town keeps running when the connection drops (the host's computer
## restarting for an update, say); the game reconnects in the background.
const RECONNECT_EVERY := 5.0
## Gives up (and says so) after this long without the region.
const RECONNECT_FOR := 300.0
var reconnecting := false
const TOWN_GAP := 20.0
const TOWN_MAX_GAP := 120.0
var _sent_at := -1000.0
var _sent_sig := []
## A neighbor's newest copy is unpacked into its simulation (a second or so
## for a grown town) one town at a time, this many seconds apart.
const NEIGHBOR_EVERY := 15.0
const NEIGHBOR_FIRST := 2.0
var _neighbor_wait := NEIGHBOR_FIRST
var _unseen := []  # neighbors not unpacked since joining
## A game month (a game day) in ticks: agreements are paid once a month.
const MONTH_TICKS := 24 * CitySim.TICKS_PER_HOUR
var _booked_month := -1
## The game hour this town last went over its shared-service deals.
var _deals_hour := -1
var _retry_in := 0.0
var _lost_for := 0.0


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
	if _connect() != OK:
		failed.emit("Couldn't reach %s." % server_url)


func _connect() -> int:
	_peer = WebSocketMultiplayerPeer.new()
	RegionServer.use_big_buffers(_peer)
	var err := _peer.create_client(url)
	if err != OK:
		_peer = null
	return err


func leave() -> void:
	if _peer:
		send_town(true)
		_peer.poll()
		_peer.close()
	_peer = null
	_connected = false
	is_joined = false


## Sends the server a copy of your town, for the neighbors and to keep.
## Copying a town takes a moment (a tenth of a second or more for a grown
## one), so it goes out only when something visible changed, and at least
## this often (seconds) for the money and the people; `now` sends anyway.
func send_town(now := false) -> void:
	var sim := my_sim()
	if sim == null or not is_joined:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var sig := [sim.network.segments.size(), sim.buildings.size(), sim.zones.cells.size(),
		sim.stats.population / 25]
	if not now and (t - _sent_at < TOWN_GAP or (sig == _sent_sig and t - _sent_at < TOWN_MAX_GAP)):
		return
	_sent_at = t
	_sent_sig = sig
	_send({"t": "city", "z": RegionServer.pack(sim.to_dict()), "pop": int(sim.stats.population)})


## Sends a batch of play telemetry (see Telemetry); telemetry_acked says when it's kept.
func send_telemetry(batch: Dictionary) -> void:
	_send({"t": "telemetry", "z": RegionServer.pack(batch)})


## Chips in to a regional project's open stage. The server books what the
## stage still needs, and this computer pays exactly that ("pledged").
func pledge(project_id: String, amount: float, good := "money") -> void:
	var sim := my_sim()
	if sim == null or amount <= 0.0:
		return
	if good == "money":
		amount = minf(amount, maxf(0.0, sim.economy.money))
	_send({"t": "pledge", "project": project_id, "good": good, "amount": amount})


## Offers a neighbor a service from your town for a monthly price.
func offer_service(to_city: String, service: String, price_per_month: float, capacity: float) -> void:
	_send({"t": "offer", "to": to_city, "service": service, "price": price_per_month, "capacity": capacity})


## Says yes or no to a neighbor's offer.
func answer_offer(agreement_id: String, yes: bool) -> void:
	_send({"t": "answer", "id": agreement_id, "yes": yes})


func end_agreement(agreement_id: String) -> void:
	_send({"t": "end", "id": agreement_id})


## Each game month of your own town, your side of every active agreement:
## booked here, so it keeps going whoever is online.
func _book_agreements() -> void:
	var sim := my_sim()
	if sim == null:
		return
	var month := int(sim.tick_count / MONTH_TICKS)
	if _booked_month < 0 or month < _booked_month:
		_booked_month = month
	while _booked_month < month:
		_booked_month += 1
		sim.economy.money += region.ledger.book_month(my_city, Interlocal.KINDS.keys())


## Shared services with neighbors (Interlocal): this town's half of each
## agreement in the ledger, and the offers and answers its bell sends out.
func _sync_deals() -> void:
	var sim := my_sim()
	if sim == null:
		return
	var hour := int(sim.tick_count / CitySim.TICKS_PER_HOUR)
	if hour == _deals_hour:
		return
	_deals_hour = hour
	sim.regional.sync(region, my_city)
	for act in sim.interlocal.sync(region, my_city, sim):
		match act.op:
			"offer":
				offer_service(act.to, act.service, act.price, act.capacity)
			"answer":
				answer_offer(act.id, act.yes)
			"end":
				end_agreement(act.id)


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
	if reconnecting:
		_lost_for += delta
		_retry_in -= delta
		if _peer == null and _retry_in <= 0.0:
			if _lost_for > RECONNECT_FOR:
				reconnecting = false
				disconnected.emit()
				return
			_retry_in = RECONNECT_EVERY
			_connect()
	if is_joined:
		_book_agreements()
		_neighbor_wait -= delta
		if _neighbor_wait <= 0.0 and not region.stale_ids().is_empty():
			# Towns never drawn yet come first, and quicker.
			var next: String = _unseen.pop_front() if not _unseen.is_empty() else region.stale_ids()[0]
			_neighbor_wait = NEIGHBOR_FIRST if not _unseen.is_empty() else NEIGHBOR_EVERY
			region.load_stale(next)
		_sync_deals()
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
		if was_joined or reconnecting:
			if not reconnecting:
				reconnecting = true
				_lost_for = 0.0
				_retry_in = RECONNECT_EVERY
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
			if reconnecting and region.cities.has(my_city):
				# Back after a dropped connection: this computer's copy of your
				# town is the newest, so keep it and send it.
				reconnecting = false
				var old_ids := region.cities.keys()
				_replace_region(d)
				is_joined = true
				for id in region.cities:
					if not id in old_ids:
						city_added.emit(id)
				send_town(true)
				reconnected.emit()
				return
			# Your own town first, so you can play at once; the neighbors are
			# unpacked one by one right after.
			var mine := ""
			for id in d.get("cities", {}):
				if str(d.cities[id].owner) == player_id:
					mine = id
			region.from_dict(d, mine)
			my_city = region.city_of(player_id)
			_unseen = region.stale_ids()
			is_joined = true
			joined.emit()
		"waiting":
			token = str(msg.get("token", token))
			waiting.emit(str(msg.get("reason", "")))
		"telemetry_ok":
			telemetry_acked.emit(str(msg.get("id", "")))
		"requests":
			requests = msg.list
			requests_changed.emit()
		"ledger":
			if msg.get("d") is Dictionary:
				region.ledger.from_dict(msg.d)
				_deals_hour = -1
				ledger_changed.emit()
		"pledged":
			# The server booked our pledge: pay it from the town.
			var sim := my_sim()
			if sim and str(msg.get("good", "")) == "money":
				sim.economy.money -= float(msg.get("amount", 0.0))
				send_town(true)
		"reject":
			var reason := str(msg.get("reason", "The region turned you away."))
			if reconnecting and "version" in reason and OS.has_feature("web"):
				# The host's computer updated to a new version of the game:
				# load it (the invite link in the address bar brings you back).
				JavaScriptBridge.eval("location.reload()")
				return
			if reconnecting:
				# Say the server still holds the old connection: try again soon.
				_peer.close()
				_peer = null
				_connected = false
				return
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
	region.ledger.from_dict(d.get("ledger", {}))
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
