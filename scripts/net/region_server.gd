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

const PROTOCOL := 3
## How often the region is written to disk, in seconds (a server that's
## switched off loses at most this much).
const SAVE_EVERY := 10.0
## WebSocket buffer size: a whole region goes out in one message when a
## player joins or resyncs (Godot's 64 KB default is far too small).
const BUFFER_BYTES := 16 * 1024 * 1024
## Biggest telemetry batch kept, unpacked (anything bigger is dropped).
const TELEMETRY_MAX := 512 * 1024
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


func _process(delta: float) -> void:
	_peer.poll()
	while _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var msg = JSON.parse_string(_peer.get_packet().get_string_from_utf8())
		if typeof(msg) == TYPE_DICTIONARY:
			_handle(from, msg)
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
static func pack(d: Dictionary) -> String:
	return Marshalls.raw_to_base64(JSON.stringify(d, "", false, true).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP))


static func unpack(z: String) -> Variant:
	var raw := Marshalls.base64_to_raw(z)
	if raw.is_empty():
		return null
	var bytes := raw.decompress_dynamic(64 * 1024 * 1024, FileAccess.COMPRESSION_GZIP)
	return JSON.parse_string(bytes.get_string_from_utf8())


func _handle(from: int, msg: Dictionary) -> void:
	if not _players.has(from):
		if msg.get("t") == "hello":
			_hello(from, msg)
		return
	var p: Dictionary = _players[from]
	match msg.get("t", ""):
		"city":
			# A copy of the player's own town (never anyone else's).
			var d = unpack(str(msg.get("z", "")))
			if p.city != "" and typeof(d) == TYPE_DICTIONARY:
				region.update_city(p.city, d)
				_dirty = true
				_broadcast({"t": "city", "id": p.city, "z": msg.z}, from)
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
		"pledge":
			# Money only for now; goods need each town to set them aside.
			var good := str(msg.get("good", "money"))
			var amount := float(msg.get("amount", 0.0))
			if p.city == "" or good != "money" or not is_finite(amount) or amount <= 0.0:
				return
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
	if int(msg.get("v", 0)) != PROTOCOL:
		_reject(from, "This region runs a different version of the game. Refresh to update.")
		return
	if str(msg.get("code", "")).to_upper().replace("-", "").strip_edges() != invite_code:
		_reject(from, "That invite code doesn't match this region.")
		return
	# The invite code is the only key: no name or password to type. A device
	# comes back by its token; a new one gets an account (named from its
	# profile, or "Neighbor 2"). Only the host's own name is guarded.
	var name := str(msg.get("name", "")).strip_edges().left(24)
	var token := str(msg.get("token", ""))
	var account := _account_by_token(token)
	if not account.is_empty():
		_rename(account, name)
	elif name != "" and accounts.has(name.to_lower()):
		account = accounts[name.to_lower()]
		var password := str(msg.get("password", ""))
		var by_password: bool = password != "" and _hash(password, account.salt) == account.hash
		if account.host and not account.tokens.is_empty() and not by_password:
			_reject(from, "%s is the host's name. Pick another in your Profile." % account.name)
			return
	else:
		account = _new_account(name if name != "" else _free_name(), str(msg.get("password", "")),
			str(msg.get("id", "")).left(64))
		_log("New player %s (%s)" % [account.name, account.status])
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
		"status": "pending" if require_approval and not is_host else "approved", "player": pid, "host": is_host, "tokens": []}
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


static func use_big_buffers(peer: WebSocketMultiplayerPeer) -> void:
	peer.inbound_buffer_size = BUFFER_BYTES
	peer.outbound_buffer_size = BUFFER_BYTES
	peer.max_queued_packets = 4096


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
	# Back from a dropped connection (or another window): the new one wins.
	for peer in _players.keys():
		if _players[peer].id == pid:
			_players.erase(peer)
			_peer.disconnect_peer(peer)
	var city := region.city_of(pid)
	if city == "":
		# A new town, on its county roads; the neighbors' halves of those
		# roads go to their computers too, if they're running.
		city = region.add_city(pid, name)
		_dirty = true
		for other in region.handed:
			for peer in _players:
				if _players[peer].city == other:
					_send(peer, {"t": "apply", "cmds": region.handed[other]})
		for peer in _players:
			_send(peer, {"t": "region", "z": pack(region.to_dict_without(_players[peer].city))})
	elif region.cities[city].player != name:
		region.cities[city].player = name
	_players[from] = {"id": pid, "name": name, "city": city, "host": account.host}
	_log("%s joined" % name)
	# Everything as it is now, their own town included: the server's copy is
	# what they play from.
	_send(from, {"t": "welcome", "you": pid, "name": name, "code": invite_code, "z": pack(region.to_dict()),
		"token": token, "host": account.host})
	_send_players()
	_send_requests()
	var line := region.add_chat("", "%s joined the region" % name)
	_broadcast({"t": "chat", "line": line})


## Tells the host who is waiting to join.
func _send_requests() -> void:
	var list := requests()
	for peer in _players:
		if _players[peer].host:
			_send(peer, {"t": "requests", "list": list})


func _on_left(peer: int) -> void:
	_waiting.erase(peer)
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
	accounts = {}
	var saved: Dictionary = d.get("accounts", {})
	for key in saved:
		var a: Dictionary = saved[key]
		accounts[key] = {"name": str(a.name), "salt": str(a.salt), "hash": str(a.hash), "status": str(a.status),
			"player": str(a.player), "host": bool(a.host), "tokens": Array(a.get("tokens", []))}
	if invite_code == "":
		invite_code = str(d.get("code", ""))
	_log("Loaded %d cities from %s" % [region.cities.size(), data_path])


func _log(text: String) -> void:
	print(text)
	log_line.emit(text)
