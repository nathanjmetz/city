class_name LawnLook
extends RefCounted
## Each yard's own lawn (Nathan, 2026-10-29: "every lawn is the same color").
## Real Grant County lawns in July differ yard to yard: a watered, fed lawn
## stays deep green; the next one, never watered, goes pale and patchy in a
## dry spell; a weedy one is blotched with clover and crabgrass; a
## showpiece has mower stripes; paths are worn to the back door, along the
## fence where the dog runs and under the swing set; an untrimmed edge goes
## ragged along the walk. A lawn under a big tree is thinner and darker.
##
## Everything here is worked out from the town's seed, the lot's key and
## its upkeep tier (PropertyCare: -2 derelict to 2 showpiece), so the same
## lot always gets the same lawn, on every copy of the town, and a lot that
## is let go or done up changes the way the house does. No random draws.
## LawnMap paints it into the textures the ground shader reads
## (TerrainView, desktop only).
##
## Real references: Purdue Turf Program (AY-8, "Lawn Watering"): unwatered
## Kentucky bluegrass and tall fescue go dormant and straw-coloured within
## 2 to 4 dry weeks in July and August; watered lawns stay green. Shade
## under a mature maple cuts turf density (Purdue AY-10, "Turf in Shade").

## Metres a texel of the lawn map covers, and texels across a tile.
const TEXEL := 2.0
const TILE := 256.0
const TILE_PX := 128
## The values a texel holds where no lot is: today's even lawn.
## a: lushness (0 tired .. 0.5 as today .. 1 deep green), weeds, grass kind
##    (0 yellow-green fescue .. 1 blue-green bluegrass), wear (bare paths).
## b: mower stripes, their direction as (cos 2a, sin 2a), tree shade.
const NEUTRAL_A := Color(0.5, 0.0, 0.5, 0.0)
const NEUTRAL_B := Color(0.0, 0.5, 0.5, 0.0)

## Mower stripes fade out between these shares of a pass pair (1.8 m) per
## pixel: gone by 0.25 m a pixel, where a pair still spans 7 pixels, far
## above the 2 a pattern needs not to alias, so they can never turn into a
## fine "lined pattern" on the grass (Nathan once saw one): they show from
## the street to about 40-60 m up and are gone well before they get fine.
## `foot` in the shader is |dx| + |dy| of the ground a pixel covers, which
## over- rather than under-states it.
const STRIPE_FADE := Vector2(0.06, 0.14)
const STRIPE_PAIR := 1.8
const STRIPE_GLSL := "const vec2 LAWN_STRIPE_FADE = vec2(0.06, 0.14);\n"

## How hard a lawn browns with the season (TerrainView): an unwatered lawn
## (lawn_resp above 1) browns harder only in the late-summer dry spell (no
## leaves turning, none down), not in the autumn and winter dormancy, when every town lawn goes the same
## muted olive, capped at 0.4 (the critic, 2026-10-26: browner lawns made the
## town read as desert from November to April). Kept in step with
## brown_of(), which the tests check.
const BROWN_GLSL := """	float lawn_brown = clamp(season_look.w * 0.45 * mix(1.0, lawn_resp, (1.0 - smoothstep(0.0, 0.02, season_look.y)) * (1.0 - smoothstep(0.0, 0.05, season_look.x))) - (1.0 - dryness) * 0.1, 0.0, 0.4);
"""


## brown_of(): BROWN_GLSL in GDScript, for the tests. `look` is
## Seasons.look(), `resp` the lawn's lawn_resp, `dryness` the ground's.
static func brown_of(look: Dictionary, resp: float, dryness: float) -> float:
	var k := (1.0 - smoothstep(0.0, 0.02, float(look.bare))) * (1.0 - smoothstep(0.0, 0.05, float(look.autumn)))
	return clampf(float(look.dry) * 0.45 * lerpf(1.0, resp, k) - (1.0 - dryness) * 0.1, 0.0, 0.4)


## The shader's lawn_resp for a lushness (texel a.r): 2.6 for a lawn never
## watered, 1 as before, 0.3 for one watered and fed.
static func resp_of(lush: float) -> float:
	return lerpf(2.6, 1.0, lush * 2.0) if lush < 0.5 else lerpf(1.0, 0.3, lush * 2.0 - 1.0)


## By upkeep tier (-2..2): the share of owners who water in a dry spell, how
## green the lawn runs, how weedy, who stripes it, and how often a path
## wears to the back door, along the fence or under a swing set, and the
## edge along the walk goes ragged.
const WATERED := [0.0, 0.05, 0.3, 0.65, 0.95]
const LUSH := [0.1, 0.27, 0.47, 0.62, 0.78]
const WEEDS := [0.95, 0.6, 0.0, 0.08, 0.0]
const STRIPED := [0.0, 0.0, 0.14, 0.45, 0.9]
const BACK_PATH := [0.7, 0.55, 0.4, 0.25, 0.1]
const BACK_DOOR := [0.65, 0.5, 0.35, 0.2, 0.05]
const FENCE_RUN := [0.45, 0.35, 0.18, 0.08, 0.0]
const PLAY := [0.15, 0.2, 0.22, 0.25, 0.1]
const RAGGED := [1.0, 0.85, 0.3, 0.1, 0.0]


## A number from 0 to 1 for this lot and `what`, the same every time.
static func roll(seed: int, key: String, what: String) -> float:
	return float(hash([seed, key, "lawn", what]) & 0xFFFFF) / float(0x100000)


## The lawn of lot `key` at upkeep `tier`, for a home (`home`) or another
## building's grounds (kept by a crew: no paths, swing sets or dog runs).
## {lush, weeds, kind, stripes, stripe_along (true: rows run front to back),
## stripe_turn (radians more, a showpiece's diagonal), watered, wear: [[kind,
## a, b, radius, strength] in the lot's own metres (x across the frontage
## from its middle, z back from the front line)]}.
static func of(seed: int, key: String, tier: int, home := true) -> Dictionary:
	var t := clampi(tier, -2, 2) + 2
	var watered: bool = roll(seed, key, "water") < float(WATERED[t])
	var lush := clampf(LUSH[t] + (roll(seed, key, "lush") - 0.5) * 0.36 + (0.12 if watered else 0.0), 0.0, 1.0)
	var weeds: float = WEEDS[t]
	if tier == 0:
		# Most kept lawns are fairly clean; one in four is clover-weedy.
		weeds = 0.6 * pow(roll(seed, key, "weeds"), 2.5)
	var kind := roll(seed, key, "kind")
	if tier >= 2:
		kind = 0.65 + kind * 0.35  # sodded bluegrass
	var stripes := 0.0
	if roll(seed, key, "stripes") < STRIPED[t]:
		stripes = 0.9 if tier >= 2 else 0.65
	var along := roll(seed, key, "rows") < 0.6
	var turn := 0.0
	if tier >= 2 and roll(seed, key, "diagonal") < 0.3:
		turn = PI / 4.0
	var out := {"lush": lush, "weeds": weeds, "kind": kind, "stripes": stripes, "stripe_along": along,
		"stripe_turn": turn, "watered": watered, "wear": []}
	out.wear = _wear(seed, key, t, home)
	return out


## Worn ground, in the lot's own metres: ["line", from, to, radius, strength]
## or ["spot", at, at, radius, strength]. Sizes are filled in by paint (they
## need the lot's width and depth), so here they are shares of it.
static func _wear(seed: int, key: String, t: int, home: bool) -> Array:
	var out := []
	# Ragged edge along the walk: thin, browned grass, not bare dirt.
	if roll(seed, key, "ragged") < RAGGED[t]:
		# Let go, it wears to bare dirt along the walk.
		var bare := t <= 1
		out.append(["edge", 0.0, 0.0, 1.5 if bare else 1.2, (0.55 if bare else 0.32) + 0.1 * roll(seed, key, "ragged_k")])
	if not home:
		return out
	# The back door: about the middle of the house, which stands 7 to 9.5 m
	# back with 8 to 12 m of house (HouseBuilder).
	var door_x: float = (roll(seed, key, "door_x") - 0.5) * 0.5
	if roll(seed, key, "door") < BACK_DOOR[t]:
		out.append(["door", door_x, 0.0, 1.6, 0.75])
	if roll(seed, key, "path") < BACK_PATH[t]:
		# To a back corner (the shed, the alley gate) or the back middle.
		var to: float = [-0.42, 0.42, 0.0][int(roll(seed, key, "path_to") * 3.0) % 3]
		out.append(["path", door_x, to, 0.75, 0.85])
	if roll(seed, key, "fence") < FENCE_RUN[t]:
		out.append(["fence", -1.0 if roll(seed, key, "fence_side") < 0.5 else 1.0, 0.0, 0.8, 0.8])
	if roll(seed, key, "play") < PLAY[t]:
		out.append(["play", (roll(seed, key, "play_x") - 0.5) * 0.5, 0.55 + roll(seed, key, "play_z") * 0.3, 2.2, 0.7])
	return out


## The lot's frame: [front point, across (unit, along the street), back
## (unit, into the lot)] in x/z.
static func frame(lot: Dictionary) -> Array:
	var f: Vector3 = lot.get("front", lot.get("pos", Vector3.ZERO))
	var n: Vector3 = lot.get("normal", Vector3.FORWARD)
	var back := Vector2(n.x, n.z).normalized()
	if back == Vector2.ZERO:
		back = Vector2(0.0, 1.0)
	return [Vector2(f.x, f.z), Vector2(-back.y, back.x), back]


## The wear marks as segments in world x/z: [[a, b, radius, strength]],
## from the look's shares and the lot's own size.
static func wear_marks(lot: Dictionary, look: Dictionary) -> Array:
	var fr := frame(lot)
	var o: Vector2 = fr[0]
	var u: Vector2 = fr[1]
	var v: Vector2 = fr[2]
	var w := float(lot.get("width", 18.0))
	var d := float(lot.get("depth", 36.0))
	# Where the back of the house is: shallow lots have smaller houses.
	var house_back := minf(d * 0.55, 20.0)
	var at := func(x: float, z: float) -> Vector2: return o + u * x + v * z
	var out := []
	for m in look.wear:
		match m[0]:
			"edge":
				out.append([at.call(-w * 0.5 + 0.8, 0.4), at.call(w * 0.5 - 0.8, 0.4), m[3], m[4]])
			"door":
				var p: Vector2 = at.call(m[1] * w, house_back + 1.2)
				out.append([p, p, m[3], m[4]])
			"path":
				var to_z := d - 1.6
				out.append([at.call(m[1] * w, house_back + 1.0), at.call(m[2] * w, to_z), m[3], m[4]])
			"fence":
				var x: float = m[1] * (w * 0.5 - 0.9)
				out.append([at.call(x, house_back + 2.0), at.call(x, d - 1.2), m[3], m[4]])
			"play":
				var p: Vector2 = at.call(m[1] * w, m[2] * d)
				out.append([p, p, m[3], m[4]])
	return out


## The angle (radians, in x/z, measured as atan2(z, x)) the mower runs.
static func stripe_angle(lot: Dictionary, look: Dictionary) -> float:
	var fr := frame(lot)
	var dir: Vector2 = fr[2] if look.stripe_along else fr[1]
	return atan2(dir.y, dir.x) + float(look.stripe_turn)


## The two texel colours a lot paints over its whole area (the wear and
## shade are added after).
static func colours(lot: Dictionary, look: Dictionary) -> Array:
	var ang := stripe_angle(lot, look) * 2.0
	var a := Color(look.lush, look.weeds, look.kind, 0.0)
	var b := Color(look.stripes, cos(ang) * 0.5 + 0.5, sin(ang) * 0.5 + 0.5, 0.0)
	return [a, b]


## Paints one lot into a tile's two images (RGBA8, TILE_PX square, the tile's
## north-west corner at `origin` in x/z): its lawn over its whole shape.
static func fill(img_a: Image, img_b: Image, origin: Vector2, lot: Dictionary, look: Dictionary) -> void:
	var poly: PackedVector2Array = lot.get("corners", PackedVector2Array())
	if poly.size() < 3:
		return
	var cols := colours(lot, look)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in poly:
		lo = lo.min(q)
		hi = hi.max(q)
	var j0 := maxi(0, floori((lo.y - origin.y) / TEXEL - 0.5))
	var j1 := mini(TILE_PX - 1, ceili((hi.y - origin.y) / TEXEL - 0.5))
	var n := poly.size()
	for j in range(j0, j1 + 1):
		# The texel row's middle, across the polygon: each pair of edge
		# crossings is a span inside (scanline fill).
		var y := origin.y + (float(j) + 0.5) * TEXEL
		var xs := PackedFloat32Array()
		for k in n:
			var a := poly[k]
			var b := poly[(k + 1) % n]
			if (a.y <= y) != (b.y <= y):
				xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
		if xs.size() < 2:
			continue
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var i0 := maxi(0, ceili((xs[k] - origin.x) / TEXEL - 0.5))
			var i1 := mini(TILE_PX - 1, floori((xs[k + 1] - origin.x) / TEXEL - 0.5))
			if i1 < i0:
				continue
			var r := Rect2i(i0, j, i1 - i0 + 1, 1)
			img_a.fill_rect(r, cols[0])
			img_b.fill_rect(r, cols[1])


## Adds worn ground (segments from wear_marks) to a tile's `a` bytes (RGBA8,
## alpha), keeping the most worn where marks overlap.
static func add_wear(bytes: PackedByteArray, origin: Vector2, marks: Array) -> void:
	for m in marks:
		_soft_line(bytes, origin, m[0], m[1], m[2], m[3], 3)


## Adds tree shade (centre in x/z, crown radius m, strength) to a tile's `b`
## bytes (alpha): darkest under the middle of the crown.
static func add_shade(bytes: PackedByteArray, origin: Vector2, at: Vector2, radius: float, strength: float) -> void:
	_soft_line(bytes, origin, at, at, radius, strength, 3)


## A soft-edged line (or spot, when a == b) of `radius` metres, its value
## `strength` in the middle falling to 0 at the edge, max-ed into channel `ch`.
static func _soft_line(bytes: PackedByteArray, origin: Vector2, a: Vector2, b: Vector2, radius: float,
		strength: float, ch: int) -> void:
	var reach := radius + TEXEL * 0.5
	var lo := a.min(b) - Vector2(reach, reach) - origin
	var hi := a.max(b) + Vector2(reach, reach) - origin
	var i0 := maxi(0, floori(lo.x / TEXEL))
	var i1 := mini(TILE_PX - 1, floori(hi.x / TEXEL))
	var j0 := maxi(0, floori(lo.y / TEXEL))
	var j1 := mini(TILE_PX - 1, floori(hi.y / TEXEL))
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var q := origin + Vector2(float(i) + 0.5, float(j) + 0.5) * TEXEL
			var s := clampf((q - a).dot(ab) / len2, 0.0, 1.0)
			var dist := q.distance_to(a + ab * s)
			# Full strength to half the radius, then easing out: a 2 m texel
			# can only hold a soft line; the shader sharpens its edge.
			var k := clampf(1.0 - (dist - radius * 0.5) / (radius * 0.5 + TEXEL * 0.5), 0.0, 1.0)
			if k <= 0.0:
				continue
			var at := (j * TILE_PX + i) * 4 + ch
			bytes[at] = maxi(bytes[at], int(round(strength * k * 255.0)))
