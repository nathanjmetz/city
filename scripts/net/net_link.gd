class_name NetLink
extends RefCounted
## Messages of any size over a WebSocket connection, both ways.
##
## A message bigger than PART_BYTES goes as several parts, put back together
## on the other side, so a region of big towns never outgrows the socket's
## buffer (it used to fail to send at 16 MB and the player waited forever).
## Each connection is given only as much as its send buffer has room for;
## the rest waits here, in order, and goes out as the buffer drains. A
## message tagged (a town's newest copy, a pointer) replaces an older one
## with the same tag that hasn't started going out yet, so a slow or busy
## player gets the newest copy sooner instead of a backlog.
##
## A part is a binary packet: PART, then flags (1: more parts follow, 2:
## this is the first part), the whole message's size (u32), then the bytes. Whole messages
## are JSON text as before; a game too old for parts can't parse a part and
## ignores it (RegionServer.MIN_PROTOCOL keeps such games out anyway).

const PART := 1
const PART_HEAD := 6
## Bytes per part. Small enough to sit in any buffer, big enough that a
## 20 MB region is twenty parts.
const PART_BYTES := 1024 * 1024
## The most one message may be, put back together (a bigger one is dropped).
## This is what a game takes from the server; the server takes less (below).
const MAX_MESSAGE := 256 * 1024 * 1024
## The most a signed-in player may send the server in one message: a town's
## full copy (12 MB packed when grown). Everything else they send is small.
const MAX_CITY := 64 * 1024 * 1024
## A message over this is a town's copy or nothing (see big_start).
const SMALL_MAX := 2 * 1024 * 1024
## The most all the half-arrived messages may hold, from every peer together.
const MAX_HELD := 192 * 1024 * 1024
## A message that stops coming (no part for this long) is dropped.
const PART_TIMEOUT_MS := 30000
## A connection's send buffer is filled to at most this much.
const ROOM := RegionServer.BUFFER_BYTES / 2
## A peer with more than this waiting to go to it has stopped reading: its
## queue is dropped and on_failed says so (tag "queue").
const MAX_QUEUED := 128 * 1024 * 1024
const MORE := 1
const FIRST := 2
## A part with only this: the sender gave up, forget what came before it.
const ABORT := 4

var peer: WebSocketMultiplayerPeer
## Called with (from peer id, received bytes, total bytes) while a big
## message comes in, for a progress bar.
var on_progress := Callable()
## The most a peer may send in one message: (peer id) -> bytes. The server
## lets a connection that hasn't signed in send only small ones.
var max_for := Callable()
## What a message over SMALL_MAX must begin with (empty: no such rule). The
## server sets it to a town's copy, so nothing else can be big.
var big_start := PackedByteArray()
## The most half-arrived messages may hold in all.
var max_held := MAX_MESSAGE
## Called with (peer id, why) when a peer breaks a limit; whoever listens
## closes it. Nothing more is read from it meanwhile.
var on_violation := Callable()
## Called with (peer id, the message's tag, error) when a message can't be
## sent at all, so whoever sent it can say so.
var on_failed := Callable()
## Messages that couldn't be sent.
var failures := 0

var _out := {}   # peer id -> [{"tag", "packets": Array[PackedByteArray], "next": int}]
var _in := {}    # peer id -> PackedByteArray of a message coming in parts
var _in_at := {} # peer id -> msec of its newest part
var _dead := {}  # peers that broke a limit: nothing more is read from them


func _init(p: WebSocketMultiplayerPeer) -> void:
	peer = p


## Queues a message for a peer (1 is the server, on a game's side).
func send(to: int, bytes: PackedByteArray, tag := "") -> void:
	if not _out.has(to):
		_out[to] = []
	var q: Array = _out[to]
	var entry := {"tag": tag, "packets": split(bytes), "next": 0}
	if tag != "":
		# The older one, not started yet, is dropped. The newer goes to the
		# back, so it never overtakes what was queued after the older one (a
		# postcard ahead of an older full copy would be undone by it).
		for i in q.size():
			if q[i].tag == tag and q[i].next == 0:
				q.remove_at(i)
				break
	q.append(entry)
	if waiting_bytes(to) > MAX_QUEUED:
		_out.erase(to)
		failures += 1
		if on_failed.is_valid():
			on_failed.call(to, "queue", ERR_OUT_OF_MEMORY)
		return
	flush_peer(to)


## Sends what fits now, for every peer.
func flush() -> void:
	for to in _out.keys():
		flush_peer(to)


func flush_peer(to: int) -> void:
	var q: Array = _out.get(to, [])
	if q.is_empty():
		return
	var ws := _ws(to)
	if ws == null:
		return
	while not q.is_empty():
		var entry: Dictionary = q[0]
		var packets: Array = entry.packets
		while entry.next < packets.size():
			var pkt: PackedByteArray = packets[entry.next]
			var buffered := ws.get_current_outbound_buffered_amount()
			if buffered > 0 and buffered + pkt.size() > ROOM:
				return
			peer.set_target_peer(to)
			var err := peer.put_packet(pkt)
			if err != OK:
				if buffered > 0:
					return  # the buffer is full after all: try again next frame
				# It doesn't go even with nothing else waiting: it never will.
				# Dropped, and said so (the player is told, never left waiting).
				q.pop_front()
				if entry.next > 0:
					# Some parts went: the other side is told to forget them.
					peer.set_target_peer(to)
					peer.put_packet(_abort_packet())
				failures += 1
				if on_failed.is_valid():
					on_failed.call(to, str(entry.tag), err)
				break
			entry.next += 1
		if entry.next >= packets.size():
			q.pop_front()


## Bytes still waiting to go to a peer: queued here, and in the socket.
func waiting_bytes(to: int) -> int:
	var n := 0
	for entry in _out.get(to, []):
		for i in range(entry.next, entry.packets.size()):
			n += entry.packets[i].size()
	var ws := _ws(to)
	if ws != null:
		n += ws.get_current_outbound_buffered_amount()
	return n


## Forgets a peer that left.
func drop(to: int) -> void:
	_out.erase(to)
	_in.erase(to)
	_in_at.erase(to)
	_dead.erase(to)


## Bytes held in half-arrived messages, from everyone.
func held_bytes() -> int:
	var n := 0
	for from in _in:
		n += _in[from].size()
	return n


func _violated(from: int, why: String) -> void:
	_in.erase(from)
	_in_at.erase(from)
	_dead[from] = true
	if on_violation.is_valid():
		on_violation.call(from, why)


## Drops messages that stopped coming (the sender went quiet half way).
func _expire() -> void:
	var now := Time.get_ticks_msec()
	for from in _in.keys():
		if now - int(_in_at.get(from, now)) > PART_TIMEOUT_MS:
			_violated(from, "a message stopped half way")


## Reads every packet that came in: [[from, text], ...], whole messages only.
## A peer that breaks a limit (too big, parts that don't add up, too much
## held in all) is reported to on_violation, and nothing more is read from it.
func receive() -> Array:
	var got := []
	_expire()
	while peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var pkt := peer.get_packet()
		if _dead.has(from):
			continue
		if pkt.size() >= PART_HEAD and pkt[0] == PART:
			if (pkt[1] & ABORT) != 0:
				_in.erase(from)
				_in_at.erase(from)
				continue
			var more := (pkt[1] & MORE) != 0
			var total := pkt.decode_u32(2)
			var most := mini(int(max_for.call(from)) if max_for.is_valid() else MAX_MESSAGE, MAX_MESSAGE)
			# (Taken out while it grows, so it isn't copied each time.)
			# A first part starts afresh (what came before it was cut short).
			var first := (pkt[1] & FIRST) != 0
			var buf: PackedByteArray = PackedByteArray() if first else _in.get(from, PackedByteArray())
			_in.erase(from)
			if total > most:
				_violated(from, "a message of %d bytes (the most is %d)" % [total, most])
				continue
			if not first and buf.is_empty():
				_violated(from, "a part without its start")
				continue
			buf.append_array(pkt.slice(PART_HEAD))
			if buf.size() > total or (not more and buf.size() != total):
				_violated(from, "parts that don't add up")
				continue
			if first and total > SMALL_MAX and not big_start.is_empty() and buf.slice(0, big_start.size()) != big_start:
				_violated(from, "a big message that isn't a town's copy")
				continue
			if more:
				_in[from] = buf
				_in_at[from] = Time.get_ticks_msec()
				if held_bytes() > max_held:
					_violated(from, "too much half-arrived at once")
					continue
				if on_progress.is_valid():
					on_progress.call(from, buf.size(), total)
				continue
			_in_at.erase(from)
			got.append([from, buf.get_string_from_utf8()])
		else:
			if max_for.is_valid() and pkt.size() > mini(int(max_for.call(from)), SMALL_MAX):
				_violated(from, "a message of %d bytes that wasn't sent in parts" % pkt.size())
				continue
			got.append([from, pkt.get_string_from_utf8()])
	return got


## A message as the packets that carry it: itself when it's small, else parts.
static func split(bytes: PackedByteArray) -> Array:
	if bytes.size() <= PART_BYTES:
		return [bytes]
	var out := []
	var at := 0
	while at < bytes.size():
		var end := mini(at + PART_BYTES, bytes.size())
		var pkt := PackedByteArray()
		pkt.resize(PART_HEAD)
		pkt[0] = PART
		pkt[1] = (MORE if end < bytes.size() else 0) | (FIRST if at == 0 else 0)
		pkt.encode_u32(2, bytes.size())
		pkt.append_array(bytes.slice(at, end))
		out.append(pkt)
		at = end
	return out


static func _abort_packet() -> PackedByteArray:
	var pkt := PackedByteArray()
	pkt.resize(PART_HEAD)
	pkt[0] = PART
	pkt[1] = ABORT
	return pkt


func _ws(to: int) -> WebSocketPeer:
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return null
	if not peer.has_method("get_peer"):
		return null
	var ws = peer.get_peer(to)
	return ws as WebSocketPeer
