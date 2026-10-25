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
## A part is a binary packet: PART, then 1 if more parts follow (0 on the
## last), the whole message's size (u32), then the bytes. Whole messages
## are JSON text as before; a game too old for parts can't parse a part and
## ignores it (RegionServer.MIN_PROTOCOL keeps such games out anyway).

const PART := 1
const PART_HEAD := 6
## Bytes per part. Small enough to sit in any buffer, big enough that a
## 20 MB region is twenty parts.
const PART_BYTES := 1024 * 1024
## The most one message may be, put back together (a bigger one is dropped).
const MAX_MESSAGE := 256 * 1024 * 1024
## A connection's send buffer is filled to at most this much.
const ROOM := RegionServer.BUFFER_BYTES / 2

var peer: WebSocketMultiplayerPeer
## Called with (from peer id, received bytes, total bytes) while a big
## message comes in, for a progress bar.
var on_progress := Callable()
## The most a peer may send in one message: (peer id) -> bytes. The server
## lets a connection that hasn't signed in send only small ones.
var max_for := Callable()

var _out := {}   # peer id -> [{"tag", "packets": Array[PackedByteArray], "next": int}]
var _in := {}    # peer id -> PackedByteArray of a message coming in parts


func _init(p: WebSocketMultiplayerPeer) -> void:
	peer = p


## Queues a message for a peer (1 is the server, on a game's side).
func send(to: int, bytes: PackedByteArray, tag := "") -> void:
	if not _out.has(to):
		_out[to] = []
	var q: Array = _out[to]
	var entry := {"tag": tag, "packets": split(bytes), "next": 0}
	if tag != "":
		for i in q.size():
			if q[i].tag == tag and q[i].next == 0:
				q[i] = entry
				flush_peer(to)
				return
	q.append(entry)
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
				# The buffer is full after all: try again next frame.
				return
			entry.next += 1
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


## Reads every packet that came in: [[from, text], ...], whole messages only.
func receive() -> Array:
	var got := []
	while peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var pkt := peer.get_packet()
		if pkt.size() >= PART_HEAD and pkt[0] == PART:
			var more := pkt[1] == 1
			var total := pkt.decode_u32(2)
			var most := int(max_for.call(from)) if max_for.is_valid() else MAX_MESSAGE
			# (Taken out while it grows, so it isn't copied each time.)
			var buf: PackedByteArray = _in.get(from, PackedByteArray())
			_in.erase(from)
			if total > mini(most, MAX_MESSAGE):
				continue
			buf.append_array(pkt.slice(PART_HEAD))
			if buf.size() > total or (not more and buf.size() != total):
				continue  # parts that don't add up: dropped
			if more:
				_in[from] = buf
				if on_progress.is_valid():
					on_progress.call(from, buf.size(), total)
				continue
			got.append([from, buf.get_string_from_utf8()])
		else:
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
		pkt[1] = 1 if end < bytes.size() else 0
		pkt.encode_u32(2, bytes.size())
		pkt.append_array(bytes.slice(at, end))
		out.append(pkt)
		at = end
	return out


func _ws(to: int) -> WebSocketPeer:
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return null
	if not peer.has_method("get_peer"):
		return null
	var ws = peer.get_peer(to)
	return ws as WebSocketPeer
