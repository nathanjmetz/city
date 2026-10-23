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
## A neighbor's town (or the whole region, id "") arrived and was loaded:
## its packed size and the main-thread time to unpack and to load it.
signal town_loaded(id: String, bytes: int, unpack_ms: float, load_ms: float)
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
## The whole town goes to the region at least this often (seconds), and on
## leaving; postcards in between. A computer that dies loses at most this
## much of its town.
const FULL_EVERY := 120.0
var _full_at := 0.0
var _snapshot := {}  # a whole-town copy under way: {"msg", "snap": TownSnapshot}
var _sent_at := -1000.0
var _sent_sig := []
var _land_sent := 0  # hash of the land last sent
## A neighbor's newest copy is unpacked into its simulation (a second or so
## for a grown town) one town at a time, this many seconds apart.
const NEIGHBOR_EVERY := 60.0
const NEIGHBOR_FIRST := 2.0
var _neighbor_wait := NEIGHBOR_FIRST
var _unseen := []  # neighbors not unpacked since joining
## Copies being packed or unpacked on another core (a grown town takes the
## better part of a second, which froze the game every time a neighbor
## built): [{task, ...}], finished in order.
var _incoming := []
var _outgoing := []
var _drawn_look := {}  # town id -> look_of the copy its simulation holds
var _look_waiting := {}  # town id -> look_of its newest copy, not unpacked yet
var _unpacked := {}  # town id -> [bytes, unpack ms] of the copy waiting to load
var _drawn_at := {}  # town id -> seconds when its copy was last unpacked
## A neighbor that looks the same is still unpacked this often, for its
## money, jobs and trade.
const NEIGHBOR_REFRESH := 600.0
## A game month (a game day) in ticks: agreements are paid once a month.
const MONTH_TICKS := 24 * CitySim.TICKS_PER_HOUR
var _booked_month := -1
## The game hour this town last went over its shared-service deals.
var _deals_hour := -1
var _retry_in := 0.0
var _lost_for := 0.0
## A first connection that drops before joining is tried again this many
## times, a few seconds apart, before the player hears about it.
const JOIN_TRIES := 3
var _join_tries := 0
var _join_retry := -1.0


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
	_join_tries = 0
	_join_retry = -1.0
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
		send_town(true, true)
		_flush()
		_peer.close()
	_peer = null
	_connected = false
	is_joined = false
	_join_retry = -1.0


## The region runs another version of the game. When it's newer, the
## browser loads the new game once by itself (the invite in the address
## brings the player back) and the desktop app updates; when it's older,
## the host's computer updates itself shortly (a game already playing
## keeps trying).
func _version_mismatch(theirs: int) -> void:
	var newer := theirs == 0 or theirs > RegionServer.PROTOCOL  # old servers don't say
	if newer and OS.has_feature("web"):
		var tried = JavaScriptBridge.eval("sessionStorage.getItem('neighbors_reload') || ''", true)
		if str(tried) != str(theirs):
			JavaScriptBridge.eval("sessionStorage.setItem('neighbors_reload', '%d'); location.reload()" % theirs)
			return
	var updater := GameUpdater.current
	if newer and updater and updater.active:
		# The desktop app fetches the newest game data and restarts.
		updater.on_version_mismatch()
		if not reconnecting:
			leave()
			failed.emit("This region runs a newer version. Updating...")
		return
	if reconnecting:
		_peer.close()
		_peer = null
		_connected = false
		return
	leave()
	if theirs == 0:
		failed.emit("This page and the region's computer are on different versions of the game. Refresh once; if this keeps showing, the host's computer needs updating.")
	elif newer:
		failed.emit("This region runs a newer version of the game. Refresh the page to get it.")
	else:
		failed.emit("The host's computer is still on the last version. It updates by itself within a few minutes: try again then.")


## Sends what's queued before the connection closes: the town going out
## on leaving is a few MB, and the game may be about to quit. The browser
## sends on its own, so there it can't be waited for (or needn't be).
func _flush() -> void:
	_peer.poll()
	if OS.has_feature("web"):
		return
	var ws: WebSocketPeer = _peer.get_peer(1) if _connected else null
	var until := Time.get_ticks_msec() + 5000
	while ws and ws.get_current_outbound_buffered_amount() > 0 and Time.get_ticks_msec() < until:
		OS.delay_msec(5)
		_peer.poll()


## Sends the server a copy of your town, for the neighbors and to keep.
## Copying a town takes a moment (a tenth of a second or more for a grown
## one), so it goes out only when something visible changed, and at least
## this often (seconds) for the money and the people; `now` sends anyway.
func send_town(now := false, leaving := false) -> void:
	var sim := my_sim()
	if sim == null or not is_joined:
		return
	var t0 := Perf.now()
	_send_town(sim, now, leaving)
	Perf.add("net.send_town", t0)


func _send_town(sim: CitySim, now: bool, leaving: bool) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var sig := [sim.network.segments.size(), sim.buildings.size(), sim.zones.cells.size(),
		sim.stats.population / 25]
	if not now and (t - _sent_at < TOWN_GAP or (sig == _sent_sig and t - _sent_at < TOWN_MAX_GAP)):
		return
	_sent_at = t
	_sent_sig = sig
	var msg := {"t": "city", "pop": int(sim.stats.population)}
	# Where the town has built, only when that changed (it can be long).
	var land := region.land_of_sim(my_city)
	if land.hash() != _land_sent:
		_land_sent = land.hash()
		region.take_land(my_city, land)
		msg.land = land
	# Neighbors only need a postcard; the whole town (its people, cars and
	# plans, which take most of the time) goes now and then and on leaving,
	# for the region to keep. The copy is taken now, as bytes (the town keeps
	# changing); packing it happens on another core, except when leaving,
	# which can't wait.
	if leaving:
		var whole: TownSnapshot = _snapshot.snap if _snapshot else TownSnapshot.new(sim)
		whole.finish()
		_snapshot = {}
		msg.z = RegionServer.pack_bytes(whole.bytes())
		_send(msg)
		return
	if _snapshot:
		return  # the whole town is on its way; it carries all this too
	if t - _full_at >= FULL_EVERY:
		# The whole town, a few parts per frame (see _step_snapshot).
		_full_at = t
		_snapshot = {"msg": msg, "snap": TownSnapshot.new(sim)}
		return
	_pack_and_send(msg, var_to_bytes(sim.to_dict(true)))


## Packs a copy on another core, then sends it (see _finish_packing).
func _pack_and_send(msg: Dictionary, raw: PackedByteArray) -> void:
	var job := {"msg": msg}
	job.task = _on_another_core(func():
		msg.z = RegionServer.pack_bytes(raw)
		job.bytes = JSON.stringify(msg, "", false, true).to_utf8_buffer())
	_outgoing.append(job)


## Takes some more of a whole-town copy; sends it once it's all taken.
func _step_snapshot() -> void:
	if _snapshot.is_empty():
		return
	var snap: TownSnapshot = _snapshot.snap
	if not snap.step():
		return
	var msg: Dictionary = _snapshot.msg
	_snapshot = {}
	if is_joined:
		_pack_and_send(msg, snap.bytes())


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
	var t_all := Perf.now()
	_step_snapshot()
	_poll(delta)
	Perf.add("net.client", t_all)


func _poll(delta: float) -> void:
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
	if _join_retry >= 0.0:
		_join_retry -= delta
		if _join_retry < 0.0:
			_connect()
	var t := Perf.now()
	_finish_packing()
	Perf.add("net.packing", t)
	if is_joined:
		t = Perf.now()
		_book_agreements()
		Perf.add("net.agreements", t)
		_neighbor_wait -= delta
		if _neighbor_wait <= 0.0 and not region.stale_ids().is_empty():
			# Towns never drawn yet come first, and quicker.
			var next: String = _unseen.pop_front() if not _unseen.is_empty() else region.stale_ids()[0]
			_neighbor_wait = NEIGHBOR_FIRST if not _unseen.is_empty() else NEIGHBOR_EVERY
			var t0 := Time.get_ticks_usec()
			region.load_stale(next)
			Perf.add("net.neighbor_load", t0)
			var got: Array = _unpacked.get(next, [0, 0.0])
			_unpacked.erase(next)
			town_loaded.emit(next, got[0], got[1], (Time.get_ticks_usec() - t0) / 1000.0)
			if _look_waiting.has(next):
				_drawn_look[next] = _look_waiting[next]
				_look_waiting.erase(next)
			_drawn_at[next] = Time.get_ticks_msec() / 1000.0
		t = Perf.now()
		_sync_deals()
		Perf.add("net.deals", t)
	if _peer == null:
		return
	_peer.poll()
	var state := _peer.get_connection_status()
	if state == MultiplayerPeer.CONNECTION_CONNECTED and not _connected:
		_connected = true
		_send({"t": "hello", "v": RegionServer.PROTOCOL, "min": RegionServer.MIN_PROTOCOL, "code": invite_code,
			"id": player_id, "name": player_name, "password": _password, "new": _new_account, "token": token})
		_password = ""
	elif state == MultiplayerPeer.CONNECTION_DISCONNECTED:
		var was_joined := is_joined
		var said_hello := _connected
		_peer = null
		_connected = false
		is_joined = false
		if was_joined or reconnecting:
			if not reconnecting:
				reconnecting = true
				_lost_for = 0.0
				_retry_in = RECONNECT_EVERY
		elif not said_hello and _join_tries < JOIN_TRIES - 1:
			# Never got through (a slow link or a busy computer): try again.
			# A region that answered and said no isn't asked again.
			_join_tries += 1
			_join_retry = RECONNECT_EVERY
		else:
			failed.emit("The region isn't answering. The host's computer may be off, asleep or restarting: try again in a minute.")
		return
	while _peer and _peer.get_available_packet_count() > 0:
		t = Perf.now()
		var msg = JSON.parse_string(_peer.get_packet().get_string_from_utf8())
		Perf.add("net.parse", t)
		if typeof(msg) == TYPE_DICTIONARY:
			t = Perf.now()
			_handle(msg)
			Perf.add("net.msg." + str(msg.get("t", "")), t)


func _handle(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"welcome":
			player_id = str(msg.you)
			_full_at = Time.get_ticks_msec() / 1000.0
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
				# The whole town: the region may have restarted from its save.
				_full_at = -FULL_EVERY
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
			_land_sent = 0
			_hook_land()
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
		"elsewhere":
			# The same player opened the region on another computer or window:
			# that one has the town now.
			leave()
			failed.emit("You're playing this town on another computer now. Play here again to bring it back.")
		"reject":
			var reason := str(msg.get("reason", "The region turned you away."))
			if "version" in reason:
				_version_mismatch(int(msg.get("v", 0)))
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
			var t0 := Time.get_ticks_usec()
			var d = RegionServer.unpack(str(msg.get("z", "")))
			var t1 := Time.get_ticks_usec()
			if typeof(d) == TYPE_DICTIONARY:
				var old_ids := region.cities.keys()
				_replace_region(d)
				for id in region.cities:
					if not id in old_ids:
						city_added.emit(id)
				town_loaded.emit("", str(msg.get("z", "")).length(), (t1 - t0) / 1000.0, (Time.get_ticks_usec() - t1) / 1000.0)
		"city":
			# A neighbor's town, fresh from their computer.
			var id := str(msg.get("id", ""))
			if id != my_city and region.cities.has(id):
				var job := {"id": id, "msg": msg}
				var z := str(msg.get("z", ""))
				job.task = _on_another_core(func():
					var t0 := Time.get_ticks_usec()
					var d = RegionServer.unpack(z)
					job.unpack_ms = (Time.get_ticks_usec() - t0) / 1000.0
					if typeof(d) == TYPE_DICTIONARY:
						job.d = d
						job.look = look_of(d))
				_incoming.append(job)
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


## Hands over copies packed or unpacked on another core, oldest first.
func _finish_packing() -> void:
	while not _outgoing.is_empty() and _done(_outgoing[0].task):
		var job: Dictionary = _outgoing.pop_front()
		if _peer != null and _connected:
			_peer.put_packet(job.bytes)
	while not _incoming.is_empty() and _done(_incoming[0].task):
		var job: Dictionary = _incoming.pop_front()
		var id: String = job.id
		if not job.has("d") or not region.cities.has(id):
			continue
		if job.msg.get("land") is Array:
			region.take_land(id, job.msg.land)
		var now := Time.get_ticks_msec() / 1000.0
		if _drawn_look.get(id) == job.look and not region.stale_ids().has(id) \
				and now - float(_drawn_at.get(id, -1e9)) < NEIGHBOR_REFRESH:
			# Nothing you can see changed (their people come and go): keep
			# the town as drawn and just note its size.
			region.cities[id].sim.stats.population = int(job.msg.get("pop", region.cities[id].sim.stats.population))
			town_loaded.emit(id, str(job.msg.get("z", "")).length(), job.unpack_ms, 0.0)
			continue
		region.update_city(id, job.d)
		_look_waiting[id] = job.look
		_unpacked[id] = [str(job.msg.get("z", "")).length(), job.unpack_ms]


## Runs every job at once, like the browser does (the play-through check
## sets it to time the browser's work on the desktop).
static var inline_jobs := false


## Runs `job` on a worker thread; the browser build without threads runs it
## at once. Returns a task id, or -1 when it's already done.
static func _on_another_core(job: Callable) -> int:
	if (OS.has_feature("web") and not OS.has_feature("threads")) or inline_jobs:
		job.call()
		return -1
	return WorkerThreadPool.add_task(job)


static func _done(task: int) -> bool:
	if task < 0:
		return true
	if not WorkerThreadPool.is_task_completed(task):
		return false
	WorkerThreadPool.wait_for_task_completion(task)
	return true


## What a neighbor's town looks like from here: its roads, lots and
## buildings (not who lives in them).
static func look_of(d: Dictionary) -> int:
	var looks := []
	var b: Dictionary = d.get("buildings", {})
	for key in b:
		looks.append([key, b[key].get("type", ""), b[key].get("zone", 0), b[key].get("level", 0),
			b[key].get("units", 1), b[key].get("chain", "")])
	return [d.get("roads", {}), d.get("parcels", {}), looks].hash()


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
		if id != my_city and c.get("land") is Array and not c.land.is_empty():
			region.take_land(id, c.land)
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


## Your town keeps to its own land and open land, and starts neighborhoods
## only where there's room (see Region.land_problem, site_problem).
func _hook_land() -> void:
	var sim := my_sim()
	if sim == null:
		return
	var me := my_city
	sim.land_check = func(pts: Array) -> String: return region.land_problem(me, pts)
	sim.site_check = func(spot: Vector2) -> String: return region.site_problem(me, spot)


func _send(msg: Dictionary) -> void:
	if _peer == null or not _connected:
		return
	_peer.put_packet(JSON.stringify(msg, "", false, true).to_utf8_buffer())
