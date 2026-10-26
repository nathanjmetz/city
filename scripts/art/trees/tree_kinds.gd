class_name TreeKinds
extends RefCounted
## How each kind of tree grows in real life, as numbers the tree grower and
## the tests read. One entry per TreeField.Species. The written reference
## (with sources) is docs/trees.md; keep the two in step.
##
## A tree is three small facts: its kind, a seed and its age (from the day
## it was planted). Everything drawn is grown from these by the rules here,
## so the same facts always give the same tree, on every computer.
##
## Heights are open-grown trees on a fair Indiana site, counted from seed
## (USDA Silvics of North America, Purdue and Morton Arboretum growth notes).
## "Size 1" in the game (the scale builders and the wild woods hand over) is
## the height a kind reaches at REF_AGE.

## Age in years whose height is "size 1".
const REF_AGE := 40.0
## Street and yard trees go in as balled-and-burlapped nursery stock, the
## size a builder or a town forester plants (ANSI Z60.1, the American
## Standard for Nursery Stock): a 2 to 3 in caliper shade tree is 12 to 14
## ft (about 3.7 m) tall; an ornamental like a crabapple 1.5 in and 8 to 10
## ft; an evergreen 6 to 7 ft. Height in metres a tree of each kind has on
## the day it goes in (at size 1; planters scale it a little either way).
const NURSERY_HEIGHT := [3.8, 3.6, 4.0, 2.0, 2.8, 3.8, 4.0, 4.0, 3.8, 3.7, 4.0, 1.8]
## The oldest age the grower models; older trees keep that shape.
const MAX_AGE := 120.0

enum Crown { ROUND, SPREAD, VASE, CONE, COLUMN }
enum Leaf { LOBED, OVATE, COMPOUND, NEEDLE, SCALE }

## Per kind (index = TreeField.Species):
##   name; h10, h30, h60, hmax: height in metres at 10, 30, 60 years and
##     the most it reaches; dbh30, dbh60: trunk thickness at chest height
##     (cm) at 30 and 60 years;
##   crown: shape; wide: crown width / height when mature; wide_young: when
##     young; base: clear trunk / height when mature (yard trees);
##   angle: [least, most] degrees a side branch leaves its parent at;
##   up: how strongly shoots turn upward (negative droops); lobes: how many
##     big limbs the crown breaks into; leader: a central leader to the top;
##   bark: [base colour, furrow colour, patch colour, pattern, scale m]
##     pattern 0 plates, 1 furrows, 2 diamond ridges, 3 shaggy strips,
##     4 corky warts, 5 smooth, 6 shreds, 7 mottled (patches peel to white);
##   leaf: shape; leaf_cm: leaf (or leaflet) length; green: summer colour;
##   fall: autumn colour; evergreen; winter: winter tint for evergreens;
##   leaf_out, turn, drop: months later (+) or earlier (-) than the
##     Seasons average for buds breaking, colour turning, leaves falling;
##   bloom: spring blossom colour (alpha 0 for none).
const KINDS := [
	{"name": "sugar maple", "h10": 4.5, "h30": 13.0, "h60": 21.0, "hmax": 26.0, "dbh30": 22.0, "dbh60": 45.0,
		"crown": Crown.ROUND, "wide": 0.68, "wide_young": 0.5, "base": 0.22, "angle": [38.0, 60.0], "up": 0.35,
		"lobes": 9, "leader": false,
		"bark": [Color("#6d6a64"), Color("#3e3a35"), Color("#8a867e"), 0, 0.35],
		"leaf": Leaf.LOBED, "leaf_cm": 11.0, "green": Color("#46661f"), "fall": Color("#d2521a"),
		"evergreen": false, "winter": Color(0, 0, 0, 0), "leaf_out": 0.0, "turn": 0.0, "drop": 0.0,
		"bloom": Color(0, 0, 0, 0)},
	{"name": "white oak", "h10": 3.5, "h30": 11.0, "h60": 18.0, "hmax": 25.0, "dbh30": 21.0, "dbh60": 48.0,
		"crown": Crown.SPREAD, "wide": 1.15, "wide_young": 0.7, "base": 0.2, "angle": [55.0, 85.0], "up": 0.05,
		"lobes": 6, "leader": false,
		"bark": [Color("#8f8b84"), Color("#56524c"), Color("#a9a59d"), 0, 0.22],
		"leaf": Leaf.LOBED, "leaf_cm": 15.0, "green": Color("#3f5c1e"), "fall": Color("#6e2a1c"),
		"evergreen": false, "winter": Color(0, 0, 0, 0), "leaf_out": 0.2, "turn": 0.35, "drop": 0.4,
		"bloom": Color(0, 0, 0, 0)},
	{"name": "honey locust", "h10": 6.5, "h30": 15.0, "h60": 21.0, "hmax": 24.0, "dbh30": 28.0, "dbh60": 50.0,
		"crown": Crown.SPREAD, "wide": 0.95, "wide_young": 0.6, "base": 0.28, "angle": [45.0, 65.0], "up": 0.2,
		"lobes": 6, "leader": false,
		"bark": [Color("#4e4640"), Color("#2a2522"), Color("#6a615a"), 3, 0.3],
		"leaf": Leaf.COMPOUND, "leaf_cm": 2.5, "green": Color("#627424"), "fall": Color("#d7b21c"),
		"evergreen": false, "winter": Color(0, 0, 0, 0), "leaf_out": 0.4, "turn": -0.2, "drop": -0.25,
		"bloom": Color(0, 0, 0, 0)},
	{"name": "blue spruce", "h10": 3.0, "h30": 10.0, "h60": 17.0, "hmax": 21.0, "dbh30": 22.0, "dbh60": 40.0,
		"crown": Crown.CONE, "wide": 0.45, "wide_young": 0.6, "base": 0.03, "angle": [70.0, 95.0], "up": -0.15,
		"lobes": 0, "leader": true,
		"bark": [Color("#5e5852"), Color("#3a3531"), Color("#77706a"), 0, 0.12],
		"leaf": Leaf.NEEDLE, "leaf_cm": 2.5, "green": Color("#2c4433"), "fall": Color("#2c4433"),
		"evergreen": true, "winter": Color("#2e4536"), "leaf_out": 0.0, "turn": 0.0, "drop": 0.0,
		"bloom": Color(0, 0, 0, 0)},
	{"name": "crabapple", "h10": 3.5, "h30": 6.0, "h60": 7.0, "hmax": 7.5, "dbh30": 18.0, "dbh60": 28.0,
		"crown": Crown.ROUND, "wide": 1.1, "wide_young": 0.8, "base": 0.18, "angle": [45.0, 70.0], "up": 0.25,
		"lobes": 5, "leader": false,
		"bark": [Color("#5d5148"), Color("#372f29"), Color("#76695e"), 0, 0.1],
		"leaf": Leaf.OVATE, "leaf_cm": 6.0, "green": Color("#4a6326"), "fall": Color("#c8641c"),
		"evergreen": false, "winter": Color(0, 0, 0, 0), "leaf_out": -0.1, "turn": 0.0, "drop": 0.0,
		"bloom": Color("#e9a6be")},
	{"name": "red oak", "h10": 5.0, "h30": 14.0, "h60": 22.0, "hmax": 26.0, "dbh30": 28.0, "dbh60": 55.0,
		"crown": Crown.ROUND, "wide": 0.9, "wide_young": 0.55, "base": 0.24, "angle": [45.0, 65.0], "up": 0.15,
		"lobes": 7, "leader": false,
		"bark": [Color("#4f4a45"), Color("#2b2724"), Color("#6c6863"), 1, 0.3],
		"leaf": Leaf.LOBED, "leaf_cm": 16.0, "green": Color("#3d5a1d"), "fall": Color("#8e2414"),
		"evergreen": false, "winter": Color(0, 0, 0, 0), "leaf_out": 0.15, "turn": 0.25, "drop": 0.3,
		"bloom": Color(0, 0, 0, 0)},
	{"name": "silver maple", "h10": 8.0, "h30": 18.0, "h60": 24.0, "hmax": 27.0, "dbh30": 45.0, "dbh60": 80.0,
		"crown": Crown.VASE, "wide": 0.8, "wide_young": 0.55, "base": 0.16, "angle": [25.0, 45.0], "up": 0.5,
		"lobes": 5, "leader": false,
		"bark": [Color("#7c7a76"), Color("#4a4744"), Color("#9a9894"), 3, 0.25],
		"leaf": Leaf.LOBED, "leaf_cm": 13.0, "green": Color("#56702c"), "fall": Color("#c9b04a"),
		"evergreen": false, "winter": Color(0, 0, 0, 0), "leaf_out": -0.25, "turn": 0.1, "drop": 0.0,
		"bloom": Color(0, 0, 0, 0)},
	{"name": "sycamore", "h10": 7.0, "h30": 18.0, "h60": 27.0, "hmax": 32.0, "dbh30": 40.0, "dbh60": 80.0,
		"crown": Crown.SPREAD, "wide": 0.85, "wide_young": 0.55, "base": 0.2, "angle": [45.0, 70.0], "up": 0.1,
		"lobes": 5, "leader": false,
		"bark": [Color("#7d7363"), Color("#52493d"), Color("#e8e6dc"), 7, 0.45],
		"leaf": Leaf.LOBED, "leaf_cm": 18.0, "green": Color("#5b7330"), "fall": Color("#8c6a32"),
		"evergreen": false, "winter": Color(0, 0, 0, 0), "leaf_out": 0.1, "turn": -0.3, "drop": -0.15,
		"bloom": Color(0, 0, 0, 0)},
	{"name": "black walnut", "h10": 5.5, "h30": 15.0, "h60": 22.0, "hmax": 27.0, "dbh30": 28.0, "dbh60": 55.0,
		"crown": Crown.ROUND, "wide": 0.78, "wide_young": 0.5, "base": 0.3, "angle": [40.0, 60.0], "up": 0.2,
		"lobes": 6, "leader": false,
		"bark": [Color("#3a332d"), Color("#1e1a17"), Color("#4f4740"), 2, 0.2],
		"leaf": Leaf.COMPOUND, "leaf_cm": 9.0, "green": Color("#5e7426"), "fall": Color("#c2a828"),
		"evergreen": false, "winter": Color(0, 0, 0, 0), "leaf_out": 0.5, "turn": -0.7, "drop": -0.8,
		"bloom": Color(0, 0, 0, 0)},
	{"name": "hackberry", "h10": 4.5, "h30": 12.0, "h60": 18.0, "hmax": 22.0, "dbh30": 22.0, "dbh60": 45.0,
		"crown": Crown.ROUND, "wide": 0.88, "wide_young": 0.55, "base": 0.24, "angle": [40.0, 60.0], "up": 0.05,
		"lobes": 7, "leader": false,
		"bark": [Color("#7a756e"), Color("#4c4842"), Color("#99938a"), 4, 0.12],
		"leaf": Leaf.OVATE, "leaf_cm": 8.0, "green": Color("#4f6a28"), "fall": Color("#b5a33c"),
		"evergreen": false, "winter": Color(0, 0, 0, 0), "leaf_out": 0.15, "turn": 0.0, "drop": 0.0,
		"bloom": Color(0, 0, 0, 0)},
	{"name": "cottonwood", "h10": 11.0, "h30": 24.0, "h60": 30.0, "hmax": 33.0, "dbh30": 55.0, "dbh60": 95.0,
		"crown": Crown.VASE, "wide": 0.7, "wide_young": 0.42, "base": 0.3, "angle": [30.0, 50.0], "up": 0.4,
		"lobes": 4, "leader": false,
		"bark": [Color("#77736b"), Color("#3f3c37"), Color("#8e8a82"), 1, 0.45],
		"leaf": Leaf.OVATE, "leaf_cm": 10.0, "green": Color("#4c6b22"), "fall": Color("#d9b827"),
		"evergreen": false, "winter": Color(0, 0, 0, 0), "leaf_out": -0.1, "turn": -0.1, "drop": -0.1,
		"bloom": Color(0, 0, 0, 0)},
	{"name": "eastern red cedar", "h10": 3.0, "h30": 8.0, "h60": 13.0, "hmax": 16.0, "dbh30": 15.0, "dbh60": 30.0,
		"crown": Crown.COLUMN, "wide": 0.34, "wide_young": 0.4, "base": 0.04, "angle": [40.0, 65.0], "up": 0.35,
		"lobes": 0, "leader": true,
		"bark": [Color("#7a4a33"), Color("#4a2b1d"), Color("#93664c"), 6, 0.15],
		"leaf": Leaf.SCALE, "leaf_cm": 0.3, "green": Color("#2f472a"), "fall": Color("#2f472a"),
		"evergreen": true, "winter": Color("#4f4a2c"), "leaf_out": 0.0, "turn": 0.0, "drop": 0.0,
		"bloom": Color(0, 0, 0, 0)},
]

static var _anchor_cache := {}
## Each kind's age (years from seed) at its NURSERY_HEIGHT, worked out once
## when the class loads (on the main thread, before any tree is resolved).
static var _nursery := _nursery_ages()


static func count() -> int:
	return KINDS.size()


static func kind(sp: int) -> Dictionary:
	return KINDS[clampi(sp, 0, KINDS.size() - 1)]


## Height in metres at an age in years: a smooth, always-rising curve through
## the reference heights (monotone cubic, so it never overshoots them).
static func height(sp: int, age: float) -> float:
	var pts: Array = _anchors(sp)
	age = clampf(age, 0.0, MAX_AGE)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		if age <= b.x:
			var h := b.x - a.x
			var t := (age - a.x) / h
			var t2 := t * t
			var t3 := t2 * t
			return (2 * t3 - 3 * t2 + 1) * a.y + (t3 - 2 * t2 + t) * h * a.z + (-2 * t3 + 3 * t2) * b.y + (t3 - t2) * h * b.z
	return pts[-1].y


## Anchor points (age, height, slope) for the growth curve, with
## Fritsch-Carlson slopes so it rises steadily between them.
static func _anchors(sp: int) -> Array:
	if _anchor_cache.has(sp):
		return _anchor_cache[sp]
	var k := kind(sp)
	# A seedling is a few centimetres; by 3 years it is knee to waist high.
	var xs := [0.0, 3.0, 10.0, 30.0, 60.0, MAX_AGE]
	var ys := [0.05, float(k.h10) * 0.22, float(k.h10), float(k.h30), float(k.h60), float(k.hmax)]
	var n := xs.size()
	var d := []
	for i in n - 1:
		d.append((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]))
	var m := [d[0]]
	for i in range(1, n - 1):
		if d[i - 1] * d[i] <= 0.0:
			m.append(0.0)
			continue
		# Weighted harmonic mean of the neighbouring slopes (PCHIP).
		var h0: float = xs[i] - xs[i - 1]
		var h1: float = xs[i + 1] - xs[i]
		var w1 := 2.0 * h1 + h0
		var w2 := h1 + 2.0 * h0
		m.append((w1 + w2) / (w1 / d[i - 1] + w2 / d[i]))
	m.append(d[-1] * 0.5)
	# Keep each piece monotone (Fritsch-Carlson limit).
	for i in n - 1:
		if d[i] == 0.0:
			m[i] = 0.0
			m[i + 1] = 0.0
			continue
		var a: float = m[i] / d[i]
		var b: float = m[i + 1] / d[i]
		var s := a * a + b * b
		if s > 9.0:
			var t := 3.0 / sqrt(s)
			m[i] = t * a * d[i]
			m[i + 1] = t * b * d[i]
	var pts := []
	for i in n:
		pts.append(Vector3(xs[i], ys[i], m[i]))
	_anchor_cache[sp] = pts
	return pts


## How old a kind's nursery stock is the day it goes in: the age at which
## it stands its NURSERY_HEIGHT on the growth curve (about 7 to 9 years from
## seed for a shade tree). A planted tree starts here and grows on.
static func nursery_age(sp: int) -> float:
	return _nursery[clampi(sp, 0, _nursery.size() - 1)]


static func _nursery_ages() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for sp in KINDS.size():
		# The curve always rises, so halve the bracket until it's found.
		var lo := 0.0
		var hi := 30.0
		for i in 30:
			var mid := (lo + hi) * 0.5
			if height(sp, mid) < float(NURSERY_HEIGHT[sp]):
				lo = mid
			else:
				hi = mid
		out.append((lo + hi) * 0.5)
	return out


## Size (1 = the height at REF_AGE) at an age.
static func size_at(sp: int, age: float) -> float:
	return height(sp, age) / height(sp, REF_AGE)


## The age at which a kind reaches a size (the inverse of size_at): how
## old a wild tree of that size is. Sizes past the oldest are MAX_AGE.
## Looked up in a table of the curve every AGE_STEP years (worked out once
## per kind), then read between its two nearest entries: the curve is
## smooth, so this is within about a thousandth of a year of solving it.
static func age_for_size(sp: int, size: float) -> float:
	var hs := _size_table(sp)
	var target := size * height(sp, REF_AGE)
	if target >= hs[-1]:
		return MAX_AGE
	if target <= hs[0]:
		return 0.0
	# The first entry at or above the target, and the one below it.
	var j := hs.bsearch(target)
	var a := hs[j - 1]
	var b := hs[j]
	return AGE_STEP * (float(j - 1) + (target - a) / maxf(b - a, 1e-12))


## Years between the entries of the size table.
const AGE_STEP := 0.25
static var _size_cache := {}


## The kind's height every AGE_STEP years from 0 to MAX_AGE. Only plain
## sums and products (the curve's own maths), so every computer gets the
## same table. Worked out on the main thread first (GrownTrees warms it).
static func _size_table(sp: int) -> PackedFloat64Array:
	if _size_cache.has(sp):
		return _size_cache[sp]
	var hs := PackedFloat64Array()
	var n := int(MAX_AGE / AGE_STEP)
	hs.resize(n + 1)
	for i in n + 1:
		hs[i] = height(sp, AGE_STEP * float(i))
	_size_cache[sp] = hs
	return hs


## Trunk thickness at chest height (1.37 m), cm, at an age: through the
## reference points at 30 and 60 years, thinner when young.
static func dbh(sp: int, age: float) -> float:
	var k := kind(sp)
	var d30: float = k.dbh30
	var d60: float = k.dbh60
	if age <= 30.0:
		# Thickness follows height early on (a sapling under chest height has none).
		return d30 * pow(maxf(height(sp, age) - 1.0, 0.0) / maxf(float(k.h30) - 1.0, 0.1), 1.15)
	var rate := (d60 - d30) / 30.0
	if age <= 60.0:
		return d30 + rate * (age - 30.0)
	# Old trees keep thickening, more slowly.
	return d60 + rate * 0.6 * (age - 60.0)


## Crown width / height at an age: young trees are narrower and fill out
## as they mature (evergreens are the other way: broad young cones).
static func wide_at(sp: int, age: float) -> float:
	var k := kind(sp)
	return lerpf(float(k.wide_young), float(k.wide), smoothstep(5.0, 45.0, age))


## Clear trunk below the crown at an age, in metres: saplings branch near
## the ground; as a tree grows the lowest limbs die in the shade (or are
## cut for headroom) and the crown lifts.
static func crown_base(sp: int, age: float) -> float:
	var k := kind(sp)
	var h := height(sp, age)
	var frac := lerpf(0.12, float(k.base), smoothstep(3.0, 30.0, age))
	if k.leader:
		frac = float(k.base)
	return h * frac


## The look of a kind through the year: the Seasons look at a date shifted
## by the kind's own timing (walnuts drop their leaves weeks ahead of the
## oaks). Returns Vector3(autumn, bare, spring).
static func season(sp: int, months: float) -> Vector3:
	var k := kind(sp)
	if k.evergreen:
		return Vector3.ZERO
	# Fall: shifting the date later than the kind's own timing.
	var fall := Seasons.look(months - float(k.turn))
	var drop := Seasons.look(months - float(k.drop))
	var y := fposmod(months, 12.0)
	var bare: float = drop.bare
	if y < 6.0:
		bare = Seasons.look(months - float(k.leaf_out)).bare
	var spring: float = Seasons.look(months - float(k.leaf_out)).spring
	return Vector3(fall.autumn, bare, spring)
