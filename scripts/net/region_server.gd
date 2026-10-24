class_name RegionServer
extends Node
## Hosts a shared region over WebSockets, so players on the web, Mac and
## Windows can all join. It runs headless (no window) for a home computer or
## a cheap cloud server: see scripts/net/server_main.gd.
##
## Each player's own computer runs their own town and sends the server a
## copy every few seconds; the server keeps the latest copy of every town,
## passes copies on so neighbors see each other, places new towns, settles
## trade between towns that are online, and keeps accounts and the chat.
## The server simulates nothing, so a small computer can host many players.

signal log_line(text: String)

const PROTOCOL := 4
## The oldest version this server still lets in, and (sent in the hello)
## the oldest server a client can talk to. Desktop apps can trail the live
## build by one launch, so small gaps still play together: raise this only
## when an older game would really break. Unknown message types are ignored
## on both sides.
const MIN_PROTOCOL := 4
## How often the region is written to disk, in seconds (a server that's
## switched off loses at most this much).
const SAVE_EVERY := 10.0
## WebSocket buffer size: a whole region goes out in one message when a
## player joins or resyncs (Godot's 64 KB default is far too small).
const BUFFER_BYTES := 16 * 1024 * 1024
## Biggest telemetry batch kept, unpacked (anything bigger is dropped).
const TELEMETRY_MAX := 512 * 1024
## pack()'s marker, and the most an unpacked copy may be.
const PACKED := "b1:"
const MAX_UNPACKED := 256 * 1024 * 1024
## How often the fix list (report.md in the telemetry folder) is redone
## when new play data has come in, in seconds.
const REPORT_EVERY := 1800.0

var region := Region.new()
var invite_code := ""
var data_path := ""
## Where play telemetry is kept, one JSON line per batch in a file per day
## (default: next to the region file, as <name>-telemetry/).
var telemetry_dir := ""
## Player accounts, kept on the server only (never sent to players):
## lowercase name -> {"name", "salt", "hash", "status": "pending" | "approved"
## | "declined", "player": player id, "host": bool, "tokens": [token hashes]}.
## Only players the host approves can play.
var accounts := {}
## The host's player name: their account is approved from the start and
## they approve everyone else. Empty means the first account made.
var host_name := ""
## Whether the host must let each new player in. Off: the invite code is
## the key (Brawn: "if you have the invite code, you can play").
var require_approval := false

var _peer := WebSocketMultiplayerPeer.new()
var _players := {}   # peer id -> {"id": player id, "name", "city", "host"}
var _waiting := {}   # peer id -> account key, signed up but not approved yet
var _trade_time := 0.0
var _save_time := 0.0
var _dirty := false
var _report_time := 0.0
var _new_telemetry := false


## Starts listening. Returns an error code (OK when it worked).
func start(port: int, code: String, path: String, host := "") -> int:
	data_path = path
	invite_code = code.to_upper()
	host_name = host.strip_edges()
	if telemetry_dir == "" and data_path != "":
		telemetry_dir = data_path.get_basename() + "-telemetry"
	_load()
	if invite_code == "":
		invite_code = new_code()
		_dirty = true
	use_big_buffers(_peer)
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
	if _new_telemetry:
		write_report()
	_peer.close()
	_players.clear()
	_waiting.clear()
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


var _left := []  # peers that disconnected this poll (see _gone)


func _process(delta: float) -> void:
	_peer.poll()
	while _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var msg = JSON.parse_string(_peer.get_packet().get_string_from_utf8())
		if typeof(msg) == TYPE_DICTIONARY:
			_handle(from, msg)
	# Players who left go only now: the town a player sends as they leave
	# often comes in with the goodbye, and is theirs to keep.
	for peer in _left:
		_gone(peer)
	_left.clear()
	_trade_time += delta
	if _trade_time >= Region.TRADE_SECONDS:
		_trade_time = 0.0
		settle_trade()
	_save_time += delta
	if _save_time >= SAVE_EVERY:
		_save_time = 0.0
		if _dirty:
			save()
	_report_time += delta
	if _report_time >= REPORT_EVERY:
		_report_time = 0.0
		if _new_telemetry:
			write_report()


## A month of trade between the towns that are running now; each player's
## computer gets its own deals and moves the money.
func settle_trade() -> void:
	var online := []
	for peer in _players:
		if _players[peer].city != "":
			online.append(_players[peer].city)
	if online.is_empty():
		return
	region.settle_trade(online)
	for peer in _players:
		var id: String = _players[peer].city
		if id != "":
			_send(peer, {"t": "trade", "deals": region.cities[id].sim.trade.last_deals})


func _ledger_changed() -> void:
	_dirty = true
	_broadcast({"t": "ledger", "d": region.ledger.to_dict()})


## A region or a town packed small for the wire: JSON, gzipped, in base64.
## Packs data to send: Godot's own binary form, Zstandard-compressed, as
## text. Several times faster than JSON for a grown town (about 0.15 s
## against 0.9 s for 12 MB), which matters in the browser, where it runs
## on the main thread.
static func pack(d: Dictionary) -> String:
	return pack_bytes(var_to_bytes(d))


## pack() for data already turned into bytes (var_to_bytes, which also
## copies it, so the rest can run on another core).
static func pack_bytes(raw: PackedByteArray) -> String:
	var head := PackedByteArray()
	head.resize(4)
	head.encode_u32(0, raw.size())
	return PACKED + Marshalls.raw_to_base64(head + raw.compress(FileAccess.COMPRESSION_ZSTD))


## Unpacks pack()'s text, or the older gzipped JSON.
static func unpack(z: String) -> Variant:
	if z.begins_with(PACKED):
		var all := Marshalls.base64_to_raw(z.substr(PACKED.length()))
		if all.size() < 4:
			return null
		var size := all.decode_u32(0)
		if size > MAX_UNPACKED:
			return null
		var bytes := all.slice(4).decompress(size, FileAccess.COMPRESSION_ZSTD)
		var d = bytes_to_var(bytes) if bytes.size() == size else null
		return TownSnapshot.join(d) if d is Dictionary else d
	var raw := Marshalls.base64_to_raw(z)
	if raw.is_empty():
		return null
	var bytes := raw.decompress_dynamic(MAX_UNPACKED, FileAccess.COMPRESSION_GZIP)
	return JSON.parse_string(bytes.get_string_from_utf8())


func _handle(from: int, msg: Dictionary) -> void:
	if not _players.has(from):
		if msg.get("t") == "hello":
			_hello(from, msg)
		return
	var p: Dictionary = _players[from]
	match msg.get("t", ""):
		"city":
			# A copy of the player's own town (never anyone else's): a
			# postcard, or now and then a full copy. Neighbors get postcards.
			var d = unpack(str(msg.get("z", "")))
			if p.city != "" and typeof(d) == TYPE_DICTIONARY:
				region.update_city(p.city, d)
				_dirty = true
				var postcard: String = msg.z if d.get("postcard", false) else pack(Region.postcard_of(d))
				var relay := {"t": "city", "id": p.city, "z": postcard}
				# Its land, when it changed (see Region.land).
				if msg.get("land") is Array:
					region.take_land(p.city, msg.land)
					relay.land = msg.land
				_broadcast(relay, from)
				if msg.get("leaving", false):
					_send(from, {"t": "bye"})  # it can close now (RegionClient._linger)
				# Its population, for the metro (older games don't send it).
				if msg.has("pop") and region.ledger.set_population(p.city, int(msg.pop)) and region.update_metro():
					_ledger_changed()
		"chat":
			var text := str(msg.get("text", "")).strip_edges()
			if text != "":
				var line := region.add_chat(p.name, text)
				_dirty = true
				_broadcast({"t": "chat", "line": line})
		"telemetry":
			var batch = unpack(str(msg.get("z", "")))
			if typeof(batch) == TYPE_DICTIONARY and store_telemetry(p, batch):
				_send(from, {"t": "telemetry_ok", "id": str(batch.get("id", ""))})
		"cursor":
			_broadcast({"t": "cursor", "id": p.id, "p": msg.get("p")}, from)
		"approve":
			if p.host:
				approve(str(msg.get("name", "")), bool(msg.get("ok", false)))
		"add_player":
			if p.host:
				add_player(str(msg.get("name", "")))
		"remove_pin":
			if p.host:
				remove_pin(str(msg.get("name", "")))
		"pledge":
			# Money only for now; goods need each town to set them aside.
			var good := str(msg.get("good", "money"))
			var amount := float(msg.get("amount", 0.0))
			if p.city == "" or good != "money" or not is_finite(amount) or amount <= 0.0:
				return
			region.load_stale(p.city)
			amount = minf(amount, maxf(0.0, region.cities[p.city].sim.economy.money))
			var took := region.ledger.pledge(p.city, str(msg.get("project", "")), good, amount)
			if took > 0.0:
				_log("%s pledged $%d to %s" % [p.name, roundi(took), str(msg.project)])
				_send(from, {"t": "pledged", "project": str(msg.project), "good": good, "amount": took})
				_ledger_changed()
		"offer":
			var to := str(msg.get("to", ""))
			if p.city != "" and region.cities.has(to) and region.ledger.offer(p.city, to,
					str(msg.get("service", "")).left(40), float(msg.get("price", -1.0)), float(msg.get("capacity", 0.0))) != "":
				_ledger_changed()
		"answer":
			if region.ledger.answer(str(msg.get("id", "")), p.city, bool(msg.get("yes", false))):
				_ledger_changed()
		"end":
			if region.ledger.end(str(msg.get("id", "")), p.city):
				_ledger_changed()


func _hello(from: int, msg: Dictionary) -> void:
	var v := int(msg.get("v", 0))
	if v < MIN_PROTOCOL or PROTOCOL < int(msg.get("min", v)):
		# Says its own version, so the game can tell which side is behind.
		_send(from, {"t": "reject", "v": PROTOCOL, "reason": "This region runs a different version of the game."})
		_log("Turned away peer %d: version %d, the region's is %d" % [from, v, PROTOCOL])
		return
	# Who it is: a device that has played here comes back by its sign-in
	# (whatever code it sends, as the code may have changed); anyone else
	# types the PIN the host made for them, which says who they are. Only
	# the region's very first player (its host) comes in with just the code.
	var name := str(msg.get("name", "")).strip_edges().left(24)
	var token := str(msg.get("token", ""))
	var pin := _clean_pin(str(msg.get("pin", "")))
	var account := _account_by_token(token)
	if not account.is_empty():
		_rename(account, name)
	elif pin != "":
		if _pin_misses.size() >= PIN_MISSES and Time.get_ticks_msec() - int(_pin_misses[0]) < 60_000:
			_reject(from, "Too many wrong PINs. Wait a minute, then try again.")
			return
		account = _account_by_pin(pin)
		if account.is_empty():
			_pin_misses.append(Time.get_ticks_msec())
			while _pin_misses.size() > PIN_MISSES:
				_pin_misses.pop_front()
			_log("Wrong PIN from peer %d" % from)
			_reject(from, "That PIN isn't right. Check it with the host.")
			return
		_log("%s came in with their PIN" % account.name)
	elif accounts.is_empty() and str(msg.get("code", "")).to_upper().replace("-", "").strip_edges() == invite_code:
		account = _new_account(name if name != "" else _free_name(), str(msg.get("password", "")),
			str(msg.get("id", "")).left(64))
		_log("New player %s (%s)" % [account.name, account.status])
	else:
		_reject(from, "Type your PIN. The host makes one for each player under Players in the region panel.")
		return
	if token == "" or not token.sha256_text() in account.tokens:
		token = _issue_token(account)
	match account.status:
		"declined":
			_reject(from, "The host hasn't let %s into this region." % account.name)
		"pending":
			_waiting[from] = account.name.to_lower()
			_send(from, {"t": "waiting", "token": token,
				"reason": "Asked the host to let you in. You'll be in as soon as they say yes."})
			_send_requests()
		_:
			_admit(from, account, token)


## Lets a waiting player in, or turns them away. Only the host can.
func approve(name: String, ok: bool) -> void:
	var key := name.to_lower()
	if not accounts.has(key) or accounts[key].host:
		return
	accounts[key].status = "approved" if ok else "declined"
	_dirty = true
	_log("%s %s" % [accounts[key].name, "approved" if ok else "turned away"])
	for peer in _waiting.keys():
		if _waiting[peer] == key:
			_waiting.erase(peer)
			if ok:
				_admit(peer, accounts[key], "")
			else:
				_reject(peer, "The host hasn't let %s into this region." % accounts[key].name)
	_send_requests()


## Players who signed up and are waiting for the host, by name.
func requests() -> Array:
	var out := []
	for key in accounts:
		if accounts[key].status == "pending":
			out.append(accounts[key].name)
	out.sort()
	return out


func _new_account(name: String, password: String, device_id: String) -> Dictionary:
	var is_host := (host_name == "" and accounts.is_empty()) or name.to_lower() == host_name.to_lower()
	# The device's id is the player id, so a city made before accounts stays theirs.
	var pid := device_id
	for a in accounts.values():
		if a.player == pid:
			pid = ""
	if pid == "":
		pid = Crypto.new().generate_random_bytes(8).hex_encode()
	var salt := Crypto.new().generate_random_bytes(16).hex_encode()
	var a := {"name": name, "salt": salt, "hash": _hash(password, salt),
		"status": "pending" if require_approval and not is_host else "approved", "player": pid, "host": is_host, "tokens": [], "pin": _new_pin()}
	accounts[name.to_lower()] = a
	_dirty = true
	return a


## A token the player's device keeps, so they don't type the password every time.
func _issue_token(account: Dictionary) -> String:
	var token := Crypto.new().generate_random_bytes(24).hex_encode()
	account.tokens.append(token.sha256_text())
	while account.tokens.size() > 5:
		account.tokens.pop_front()
	_dirty = true
	return token


func _account_by_token(token: String) -> Dictionary:
	if token == "":
		return {}
	var h := token.sha256_text()
	for a in accounts.values():
		if h in a.tokens:
			return a
	return {}


## PINs: six digits the host gives each player. Wrong ones are counted,
## and after PIN_MISSES in a minute the region stops listening for a bit.
const PIN_MISSES := 10
var _pin_misses := []  # ticks of the latest wrong PINs


static func _clean_pin(pin: String) -> String:
	var out := ""
	for ch in pin:
		if ch >= "0" and ch <= "9":
			out += ch
	return out


func _account_by_pin(pin: String) -> Dictionary:
	for a in accounts.values():
		if str(a.get("pin", "")) == pin:
			return a
	return {}


func _new_pin() -> String:
	var crypto := Crypto.new()
	while true:
		var b := crypto.generate_random_bytes(4)
		var pin := "%06d" % (b.decode_u32(0) % 1000000)
		if _account_by_pin(pin).is_empty():
			return pin
	return ""


## (Host) adds a player by name, with a PIN to send them; or makes an
## existing player a new PIN.
func add_player(name: String) -> String:
	name = name.strip_edges().left(24)
	if name == "":
		return ""
	var key := name.to_lower()
	if accounts.has(key):
		accounts[key].pin = _new_pin()
		accounts[key].status = "approved"
		_dirty = true
		_log("New PIN for %s" % accounts[key].name)
	else:
		_new_account(name, "", "")
		accounts[key].status = "approved"
		_log("The host added %s" % name)
	_send_pins()
	return accounts[key].pin


## (Host) removes a player: their PIN lets nobody in and their town comes
## off the map (old towns from earlier tries leave no ghost labels behind).
func remove_pin(name: String) -> void:
	var key := name.strip_edges().to_lower()
	if accounts.has(key) and not accounts[key].host:
		accounts[key].pin = ""
		accounts[key].status = "declined"
		accounts[key].tokens = []
		var town := region.city_of(str(accounts[key].player))
		if town != "":
			for peer in _players.keys():
				if _players[peer].city == town:
					_players.erase(peer)
					_reject(peer, "The host removed you from this region.")
					get_tree().create_timer(2.0).timeout.connect(func(): if _peer: _peer.disconnect_peer(peer))
					_send_players()
			region.remove_city(town)
		_dirty = true
		_log("The host removed %s" % accounts[key].name)
		_send_pins()


## Every player and their PIN, for the host's Players list.
func pins() -> Array:
	var out := []
	for key in accounts:
		var a: Dictionary = accounts[key]
		out.append({"name": a.name, "pin": str(a.get("pin", "")), "host": a.host})
	out.sort_custom(func(x, y): return x.name.naturalnocasecmp_to(y.name) < 0)
	return out


func _send_pins() -> void:
	for peer in _players:
		if _players[peer].host:
			_send(peer, {"t": "pins", "list": pins()})


func _free_name() -> String:
	var n := accounts.size() + 1
	while accounts.has("neighbor %d" % n):
		n += 1
	return "Neighbor %d" % n


## A player picked a new name in their Profile: take it if nobody has it.
func _rename(account: Dictionary, name: String) -> void:
	var key := name.to_lower()
	if name == "" or key == account.name.to_lower() or accounts.has(key):
		return
	accounts.erase(account.name.to_lower())
	if account.host and host_name.to_lower() == account.name.to_lower():
		host_name = name
	account.name = name
	accounts[key] = account
	_dirty = true


## How long a new connection has to finish its handshake.
const HANDSHAKE_SECONDS := 30.0


static func use_big_buffers(peer: WebSocketMultiplayerPeer) -> void:
	peer.inbound_buffer_size = BUFFER_BYTES
	peer.outbound_buffer_size = BUFFER_BYTES
	peer.max_queued_packets = 4096
	# Godot gives a new connection 3 s to finish saying hello, too short for
	# a browser still loading the game or a slow link through the tunnel.
	peer.handshake_timeout = HANDSHAKE_SECONDS


## A slow salted hash, so a copied save file doesn't give passwords away.
static func _hash(password: String, salt: String) -> String:
	var bytes := (salt + password).to_utf8_buffer()
	for i in 4000:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(bytes)
		ctx.update(salt.to_utf8_buffer())
		bytes = ctx.finish()
	return bytes.hex_encode()


func _admit(from: int, account: Dictionary, token: String) -> void:
	var pid: String = account.player
	var name: String = account.name
	# Back from a dropped connection (or another window or computer): the new
	# one wins. The old one is told first, so it stops instead of reconnecting
	# and taking the town back, then closed a moment later.
	for peer in _players.keys():
		if _players[peer].id == pid:
			_players.erase(peer)
			_send(peer, {"t": "elsewhere"})
			get_tree().create_timer(2.0).timeout.connect(func(): if _peer: _peer.disconnect_peer(peer))
	var city := region.city_of(pid)
	if city == "":
		# A new town, on its county roads; the neighbors' halves of those
		# roads go to their computers too, if they're running.
		city = region.add_city(pid, name)
		region.update_metro()
		_dirty = true
		for other in region.handed:
			for peer in _players:
				if _players[peer].city == other:
					_send(peer, {"t": "apply", "cmds": region.handed[other]})
		# Everyone else gets the new town and the neighbors it joined; the
		# rest they already have.
		var fresh: Array = [city] + region.handed.keys()
		for peer in _players:
			var d := region.to_dict_with(fresh.filter(func(id): return id != _players[peer].city))
			_send(peer, {"t": "region", "z": pack(d)})
	elif region.cities[city].player != name:
		region.cities[city].player = name
	_players[from] = {"id": pid, "name": name, "city": city, "host": account.host}
	_log("%s joined" % name)
	# Everything as it is now, their own town included: the server's copy is
	# what they play from. Back from a while away: what the neighbors did
	# meanwhile, for their town to catch up on (CatchUp).
	var welcome := {"t": "welcome", "you": pid, "name": name, "code": invite_code, "z": pack(region.to_dict(city)),
		"token": token, "host": account.host}
	var away := region.away_report(city)
	if not away.is_empty():
		welcome.away = away
		_dirty = true
	_send(from, welcome)
	_send_players()
	_send_requests()
	_send_pins()
	var line := region.add_chat("", "%s joined the region" % name)
	_broadcast({"t": "chat", "line": line})


## Tells the host who is waiting to join.
func _send_requests() -> void:
	var list := requests()
	for peer in _players:
		if _players[peer].host:
			_send(peer, {"t": "requests", "list": list})


func _on_left(peer: int) -> void:
	_left.append(peer)


func _gone(peer: int) -> void:
	_waiting.erase(peer)
	if not _players.has(peer):
		return
	var name: String = _players[peer].name
	if _players[peer].city != "":
		region.mark_away(_players[peer].city)
		_dirty = true
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


## Keeps a batch of a player's play telemetry: one line in today's file.
## Returns false when there's nowhere to keep it (so the player holds on).
func store_telemetry(p: Dictionary, batch: Dictionary) -> bool:
	if telemetry_dir == "":
		return false
	batch["from"] = p.name
	batch["pid"] = p.id
	batch["recv"] = int(Time.get_unix_time_from_system())
	var line := JSON.stringify(batch, "", false, true)
	if line.length() > TELEMETRY_MAX:
		return true   # kept nothing, but sending it again won't help
	DirAccess.make_dir_recursive_absolute(telemetry_dir)
	var path := telemetry_dir.path_join(Time.get_date_string_from_system() + ".jsonl")
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		_log("Couldn't keep telemetry in %s" % path)
		return false
	f.seek_end()
	f.store_line(line)
	_new_telemetry = true
	return true


## Redoes the ranked fix list from the last two weeks of play.
func write_report() -> void:
	_new_telemetry = false
	var batches := Insights.read_dir(telemetry_dir, 14)
	var f := FileAccess.open(telemetry_dir.path_join("report.md"), FileAccess.WRITE)
	if f:
		f.store_string(Insights.to_markdown(Insights.analyze(batches)))


func save() -> void:
	if data_path == "":
		return
	var d := region.to_dict()
	d["code"] = invite_code
	d["accounts"] = accounts
	d["away"] = region.away
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
	# A new map: the towns can't move over, so the region starts fresh, but
	# accounts, PINs and sign-ins stay so nobody has to be invited again.
	var old_map := str(d.get("map", "petersburg"))
	if old_map == Region.MAP:
		region.from_dict(d)
		region.away = d.get("away", {}) if d.get("away") is Dictionary else {}
	else:
		_log("The game moved from the %s map to %s: starting the region fresh, players keep their PINs" % [old_map, Region.MAP])
		region.chat = d.get("chat", [])
		region.add_chat("", "The region moved to a new map. Everyone starts a fresh town here.")
		_dirty = true
	accounts = {}
	var saved: Dictionary = d.get("accounts", {})
	for key in saved:
		var a: Dictionary = saved[key]
		accounts[key] = {"name": str(a.name), "salt": str(a.salt), "hash": str(a.hash), "status": str(a.status),
			"player": str(a.player), "host": bool(a.host), "tokens": Array(a.get("tokens", [])),
			"pin": str(a.get("pin", ""))}
	# Regions from before PINs: every player gets one, and the first player
	# is the host if nobody is.
	var any_host := false
	for key in accounts:
		any_host = any_host or accounts[key].host
		if accounts[key].pin == "" and accounts[key].status != "declined":
			accounts[key].pin = _new_pin()
	if not any_host and not accounts.is_empty():
		accounts[accounts.keys()[0]].host = true
	# A town no account plays (left from an earlier try or a removed player)
	# can never be played again: take it off the map, so it leaves no ghost.
	if not accounts.is_empty():
		var played := {}
		for key in accounts:
			if accounts[key].status != "declined":
				played[str(accounts[key].player)] = true
		for id in region.cities.keys():
			if not played.has(str(region.cities[id].owner)):
				_log("Took %s off the map: nobody plays it any more" % region.cities[id].name)
				region.remove_city(id)
				_dirty = true
	if invite_code == "":
		invite_code = str(d.get("code", ""))
	_log("Loaded %d cities from %s" % [region.cities.size(), data_path])


func _log(text: String) -> void:
	print(text)
	log_line.emit(text)
