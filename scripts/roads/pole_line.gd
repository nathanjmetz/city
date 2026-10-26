class_name PoleLine
extends RefCounted
## The wooden power line along a country road, benchmarked against the
## REMC and Duke Energy distribution lines on Grant County roads and the
## RUS (REA) construction drawings:
##   - 40 ft treated pine poles about every 130 ft (40 m), set back past
##     the gravel shoulder, all on one side of the road
##   - the same side all along a road, and on every road running the same
##     way, so the line never hops across: it crosses a road only where it
##     carries on over a side road at a junction
##   - single-phase on most roads (the primary on a pin at the pole top, the
##     neutral a few feet below), three-phase on a crossarm along state
##     highways and avenues
##   - the wires follow the road and sag between poles, about 2% of the span
##   - poles stand clear of every road and back from every junction
##   - a house along the line gets its service drop from the nearest pole,
##     under a transformer can
## Lines running north-south ride a metre lower than east-west ones, so
## where two cross at a corner their wires pass over each other.

## Pole spacing along the road (130 ft).
const SPACING := 40.0
## How far a pole may slide along the road to get clear of a side road.
const SLIDE := 15.0
## Poles stand at least this far from a junction's centre.
const CLEAR := 15.0
## The side every line keeps to: the side of the road this way (roughly
## south and east), whichever way the road was drawn.
const PREFER := Vector2(0.8, 0.6)
## Sag at mid-span, as a share of the span.
const SAG := 0.022
const PIECES := 3
const WIRE := 0.035
## Height of the top conductor above the ground.
const TOP := 10.6
const NEUTRAL_DROP := 1.5
const HOUSE_ATTACH := 3.4
const HOUSE_SETBACK := 8.5
## A house farther than this from every pole gets no drop (a triplex drop
## runs about 100 ft at most).
const DROP_REACH := 32.0


## The side of a road (RoadMesh's +1 / -1) a line along it keeps to.
static func side_for(dir: Vector3) -> float:
	var n := Vector2(-dir.z, dir.x)
	return 1.0 if n.dot(PREFER) >= 0.0 else -1.0


## Three-phase lines run along the bigger roads.
static func three_phase(type: int) -> bool:
	return type in [RoadStyle.Type.STATE_HWY, RoadStyle.Type.DIVIDED_HWY] or RoadStyle.group(type) in [
		RoadStyle.Type.AVENUE, RoadStyle.Type.BOULEVARD]


## The top conductor's height for a line running along `dir`.
static func top_for(dir: Vector3) -> float:
	return TOP if absf(dir.x) >= absf(dir.z) else TOP - 1.0


## Pole bases down a road's whole run: `pts` along it, `off` metres to the
## side, starting `ends.x` in from the start and stopping `ends.y` short of
## the end. A pole that would stand on another road or in a junction
## (`blocked(p)`) or a drive (`avoid`) slides along the road to the nearest
## clear spot, or is left out. Each: [base, the road's side direction].
static func place(pts: PackedVector3Array, off: float, ends: Vector2, avoid := [], blocked := Callable()) -> Array:
	var length := RoadNetwork.polyline_length(pts)
	var usable := length - ends.x - ends.y
	if usable < 8.0:
		return []
	var n := maxi(1, roundi(usable / SPACING))
	var out := []
	var last := -INF
	for k in n + 1:
		var want := ends.x + usable * k / n
		var got := -1.0
		var base := Vector3.ZERO
		var side := Vector3.ZERO
		for t in 11:
			# 0, +3, -3, +6, -6 ... metres along the road.
			var s := want + (ceilf(t / 2.0) * 3.0 * (1.0 if t % 2 == 1 else -1.0))
			if s < 0.0 or s > length or s - last < SPACING * 0.45:
				continue
			var at := LotPlanner.point_at(pts, s)
			var dir: Vector3 = at[1] if at.size() > 1 else Vector3.FORWARD
			dir.y = 0.0
			dir = dir.normalized()
			var sd := Vector3(-dir.z, 0.0, dir.x)
			var p: Vector3 = at[0]
			var b := Vector3(p.x, maxf(p.y, 0.0), p.z) + sd * off
			var free := true
			for q in avoid:
				if Vector2(q.x - b.x, q.z - b.z).length() < 6.0:
					free = false
					break
			if free and blocked.is_valid() and blocked.call(b):
				free = false
			if free:
				got = s
				base = b
				side = sd
				break
		if got < 0.0:
			continue
		last = got
		out.append([base, side])
	return out


## Draws the poles and the wires between them (flat, at ground level 0:
## drape onto the land after). `top`: the top conductor's height.
static func draw(wood: SurfaceTool, wire: SurfaceTool, poles: Array, three: bool, top: float) -> void:
	var prev := []
	for pole in poles:
		var base: Vector3 = pole[0]
		var side: Vector3 = pole[1]
		var yaw := atan2(side.x, side.z)
		var h := top + 0.4
		RoadMesh._post(wood, base + Vector3(0, h * 0.5, 0), Vector3(0.26, h, 0.26), Basis(Vector3.UP, yaw))
		var row := attach(pole, three, top)
		if three:
			# Crossarm square to the road, three pin insulators on it.
			RoadMesh._post(wood, base + Vector3(0, top - 0.25, 0), Vector3(2.4, 0.12, 0.12),
				Basis(Vector3.UP, yaw + PI * 0.5))
		for i in row.size():
			var q: Vector3 = row[i]
			# Pin insulators (the neutral's spool is short): two crossed strips.
			var tall := 0.24 if i < row.size() - 1 else 0.1
			_wire(wire, q - Vector3(0, tall, 0), q, 0.05)
		if not prev.is_empty():
			for i in row.size():
				span(wire, prev[i], row[i])
		prev = row


## The points a pole carries its wires at: the primaries, then the neutral.
static func attach(pole: Array, three: bool, top: float) -> Array:
	var base: Vector3 = pole[0]
	var side: Vector3 = pole[1]
	var out := []
	if three:
		for s in [-1.0, 0.0, 1.0]:
			out.append(base + side * (s * 1.05) + Vector3(0, top, 0))
	else:
		out.append(base + Vector3(0, top + 0.35, 0))
	# The neutral, a few feet down the pole.
	out.append(base + Vector3(0, top - NEUTRAL_DROP, 0))
	return out


## One wire from a to b, sagging `SAG` of its length at mid-span.
static func span(st: SurfaceTool, a: Vector3, b: Vector3, sag := -1.0, pieces := PIECES) -> void:
	var dip := (a.distance_to(b) * SAG) if sag < 0.0 else sag
	var last := a
	for k in range(1, pieces + 1):
		var t := float(k) / pieces
		var p := a.lerp(b, t) - Vector3(0, 4.0 * dip * t * (1.0 - t), 0)
		_wire(st, last, p)
		last = p


## A thin wire piece: two crossed strips (seen from any side, no caps).
static func _wire(st: SurfaceTool, a: Vector3, b: Vector3, half := WIRE) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var across := d.cross(Vector3.UP)
	across = Vector3.RIGHT if across.length() < 0.001 else across.normalized()
	var up := across.cross(d).normalized()
	for w in [across * half, up * half]:
		var n: Vector3 = (w as Vector3).cross(d).normalized()
		for v in [a - w, a + w, b + w, a - w, b + w, b - w]:
			st.set_normal(n)
			st.add_vertex(v)


## A service drop from a pole's neutral to a house wall, and a transformer
## can on the pole. Points already on the land.
static func drop(wire: SurfaceTool, from: Vector3, to: Vector3, can: bool) -> void:
	span(wire, from, to, 0.35, 3)
	if can:
		RoadMesh._post(wire, from + Vector3(0, 0.9, 0), Vector3(0.45, 0.75, 0.45), Basis.IDENTITY)
