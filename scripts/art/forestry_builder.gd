class_name ForestryBuilder
extends CivicBuilder
## Forestry, benchmarked against photos of southern Indiana hardwood
## logging and small sawmills:
##   - the woods: a closed canopy of oak, maple and hickory on a dark floor
##     of leaf litter, trees taller than yard trees and packed close
##   - a logging stand is a selective cut inside those woods, not a bare
##     field: the canopy is thinned, skid trails wind out from a dirt
##     landing, and logs wait on a deck beside a slash pile and a skidder
##   - the sawmill: a long metal mill shed on a gravel and bark yard, log
##     decks with pale cut ends, stickered lumber, a sawdust pile under its
##     conveyor, a wheel loader with a log grapple, and a small office
## Local space as the other builders; -z faces the company's drive.

const BARK := Color("#4f4336")
const CUT_END := Color("#c9a877")
const LITTER := Color("#4b4430")
const YARD := Color("#7d7462")
const LUMBER := Color("#d8c08e")
const YELLOW := Color("#d9a520")
const SKIDDER := Color("#3f6b2e")

## Where the last stand's landing went (planted rows keep off it).
var _landing := Vector2.ZERO


## A cell of woods, `size` metres square, centred on the origin. `keep` is
## the share of trees left standing (1 for untouched woods). `clear` holds
## [Vector2 a, Vector2 b, width] bands with no trees, in local x/z. `open`
## says which sides (-x, +x, -z, +z) face open land: the wood's edge there
## wanders in and out instead of running straight along the cell.
static func woods(seed: int, size: float, keep: float, clear := [], open := [false, false, false, false]) -> Array:
	var b := ForestryBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._woods(size, keep, clear, open)
	return [b._commit_house(), b._commit_flat(), b.trees]


## A logging stand: thinned woods, skid trails and a landing with a deck.
## `track_dir` points (in local x/z) to where the haul track leaves.
## `replanted`: the company has a replanting crew (Agency "replanting"), so
## the cut shows rows of tree shelters.
static func stand(seed: int, size: float, track_dir: Vector2, clear := [], open := [false, false, false, false],
		replanted := false) -> Array:
	var b := ForestryBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._stand(size, track_dir, clear, open)
	if replanted:
		UpgradeKits.planted_rows(b, b._landing, size * 0.5)
	return [b._commit_house(), b._commit_flat(), b.trees]


## The sawmill yard, with what its leader has built (Agency.TREES) and the
## add-ons beside it where Industry.ADDONS placed them (UpgradeKits).
static func mill(seed: int, size: Vector2, built := [], addons := {}) -> Array:
	var b := ForestryBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._mill(size)
	if "chip_plant" in built:
		b._chip_mill(size)
	for node in addons:
		var at := Vector3(float(addons[node][0]), 0, float(addons[node][1]))
		match str(node):
			"log_yard": UpgradeKits.wet_deck(b, at)
			"dry_kiln": UpgradeKits.dry_kilns(b, at)
			"pellet_mill": UpgradeKits.pellet_mill(b, at)
			"replanting": UpgradeKits.seedling_cooler(b, at)
	return [b._commit_house(), b._commit_flat(), b.trees]


# ---------------------------------------------------------------- woods

func _woods(size: float, keep: float, clear: Array, open: Array) -> void:
	var h := size * 0.5
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	# How far the wood's edge sits in from an open side, at position t along it.
	var inset := func(side: int, t: float) -> float:
		if not open[side]:
			return 0.0
		return 7.0 + 5.0 * sin(t * 0.09 + ph[side]) + 3.0 * sin(t * 0.27 + ph[side] * 2.0)
	# Leaf litter under the canopy, following the edge.
	var floor := []
	var n_edge := 10
	var corners := [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		for i in n_edge:
			var q := a.lerp(b, float(i) / n_edge)
			# Push in from whichever sides this point lies on (both, at a corner).
			var dx: float = inset.call(0 if q.x < 0.0 else 1, q.y) if absf(absf(q.x) - h) < 0.01 else 0.0
			var dz: float = inset.call(2 if q.y < 0.0 else 3, q.x) if absf(absf(q.y) - h) < 0.01 else 0.0
			floor.append(Vector3(q.x - signf(q.x) * dx, 0, q.y - signf(q.y) * dz))
	_flat_poly(floor, 0.03, LITTER)
	var step := 8.5
	var n := int(size / step)
	for i in n:
		for j in n:
			var p := Vector3(-h + (i + 0.5) * step + rng.randf_range(-3.0, 3.0), 0,
				-h + (j + 0.5) * step + rng.randf_range(-3.0, 3.0))
			if rng.randf() > keep or _in_clear(p, clear):
				continue
			if p.x + h < inset.call(0, p.z) + 2.0 or h - p.x < inset.call(1, p.z) + 2.0 \
					or p.z + h < inset.call(2, p.x) + 2.0 or h - p.z < inset.call(3, p.x) + 2.0:
				continue
			trees.append([p, _forest_species(), _forest_tint(), rng.randf_range(1.25, 1.75)])


func _forest_species() -> int:
	var r := rng.randf()
	if r < 0.42:
		return TreeField.Species.OAK
	if r < 0.86:
		return TreeField.Species.MAPLE
	return TreeField.Species.LOCUST  # stands in for hickory and ash


func _forest_tint() -> Color:
	var c: Color = TreeField.LEAF[TreeField.Species.OAK]
	return c.lerp(Color("#556b22"), rng.randf()).darkened(rng.randf_range(0.0, 0.12))


func _in_clear(p: Vector3, clear: Array) -> bool:
	for c in clear:
		var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), c[0], c[1])
		if q.distance_to(Vector2(p.x, p.z)) < c[2]:
			return true
	return false


# ---------------------------------------------------------------- stand

func _stand(size: float, track_dir: Vector2, extra: Array, open: Array) -> void:
	var h := size * 0.5
	var td := track_dir.normalized() if track_dir.length() > 0.1 else Vector2(0, -1)
	# The landing sits toward the haul track; skid trails wind back into the cut.
	var land := td * rng.randf_range(8.0, 14.0)
	_landing = land
	# (The haul road out of the stand comes in with the extra clearings.)
	var clear := [[Vector2.ZERO, td * 16.0, 4.0], [land, land, 15.0]]
	var trail_pts := []
	for k in rng.randi_range(3, 4):
		var a := atan2(-td.y, -td.x) + rng.randf_range(-1.3, 1.3)
		var pts := [land]
		var p := land
		for s in 4:
			a += rng.randf_range(-0.5, 0.5)
			p += Vector2(cos(a), sin(a)) * rng.randf_range(8.0, 11.0)
			p = p.clamp(Vector2(-h + 4, -h + 4), Vector2(h - 4, h - 4))
			pts.append(p)
		trail_pts.append(pts)
		for s in pts.size() - 1:
			clear.append([pts[s], pts[s + 1], 3.0])
	_woods(size, 0.55, clear + extra, open)
	# Landing: churned dirt, ragged.
	var ring := []
	for i in 14:
		var a := TAU * i / 14.0
		var r := rng.randf_range(12.0, 16.0)
		ring.append(Vector3(land.x + cos(a) * r * 1.2, 0, land.y + sin(a) * r * 0.9))
	_flat_poly(ring, 0.06, DIRT.darkened(0.08))
	for pts in trail_pts:
		for s in pts.size() - 1:
			_flat_band(pts[s], pts[s + 1], 1.8, 0.055, DIRT)
	# Log deck along the landing's edge, the slash pile, a skidder.
	var side := Vector2(-td.y, td.x)
	var deck := land - td * 5.0
	_log_deck(Vector3(deck.x, 0, deck.y), atan2(side.x, side.y), 11.0, 9, 0.28)
	var slash := land + side * 8.0
	_slash(Vector3(slash.x, 0, slash.y), 4.0)
	_slash(Vector3(slash.x, 0, slash.y) + Vector3(td.x, 0, td.y) * 6.0, 3.0)
	var sk := land - side * 7.0
	_skidder(Vector3(sk.x, 0, sk.y), atan2(td.x, td.y) + rng.randf_range(-0.6, 0.6))
	# Stumps where trees came down near the landing.
	for i in 10:
		var p := land + Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-22.0, 22.0))
		if p.distance_to(land) > 15.0 and absf(p.x) < h - 2.0 and absf(p.y) < h - 2.0:
			_cylinder("paint", Vector3(p.x, 0, p.y), rng.randf_range(0.25, 0.4), 0.45, BARK, 8)


## A pile of logs with pale cut ends: `rows` across the bottom, stacked.
func _log_deck(c: Vector3, yaw: float, length: float, rows: int, r: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var layer := 0
	var count := rows
	while count > 0 and layer < 5:
		for i in count:
			var off := (i - (count - 1) * 0.5) * r * 2.05
			var rr := r * rng.randf_range(0.8, 1.15)
			var l := length * rng.randf_range(0.9, 1.0)
			var shift := rng.randf_range(-0.4, 0.4)
			var p := c + basis * Vector3(off, rr + layer * r * 1.75, shift)
			_log(p, basis * Vector3(0, 0, 1), l, rr)
		count -= rng.randi_range(1, 2)
		layer += 1


## One log lying along `axis` (horizontal), centred on `c`.
func _log(c: Vector3, axis: Vector3, l: float, r: float) -> void:
	var segs := 7
	var up := Vector3.UP
	var side := axis.cross(up).normalized()
	var a0 := c - axis * l * 0.5
	var a1 := c + axis * l * 0.5
	var bark := BARK.lightened(rng.randf_range(-0.05, 0.1))
	for i in segs:
		var t0 := TAU * i / segs
		var t1 := TAU * (i + 1) / segs
		var d0 := side * cos(t0) + up * sin(t0)
		var d1 := side * cos(t1) + up * sin(t1)
		_quad("paint", a0 + d0 * r, a1 + d0 * r, a1 + d1 * r, a0 + d1 * r, bark, [], (d0 + d1))
		_tri("paint", a0, a0 + d0 * r, a0 + d1 * r, CUT_END, [], -axis)
		_tri("paint", a1, a1 + d0 * r, a1 + d1 * r, CUT_END.darkened(rng.randf_range(0.0, 0.15)), [], axis)


## Tops and limbs left from felling: a low, rough grey-brown mound.
func _slash(c: Vector3, r: float) -> void:
	for k in 6:
		var p := c + Vector3(rng.randf_range(-r, r) * 0.6, 0, rng.randf_range(-r, r) * 0.6)
		var yaw := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
		_box("paint", Vector3(0.18, 0.18, r * rng.randf_range(0.8, 1.4)), p + Vector3(0, 0.35, 0), BARK.lightened(0.15), yaw)
	var rings := 3
	var segs := 8
	var pts := []
	for i in rings + 1:
		var row := []
		var t := PI * 0.5 * i / rings
		for j in segs:
			var a := TAU * j / segs
			var k := r * rng.randf_range(0.75, 1.15)
			row.append(c + Vector3(cos(t) * cos(a) * k, sin(t) * r * 0.35 * rng.randf_range(0.8, 1.2), cos(t) * sin(a) * k))
		pts.append(row)
	for i in rings:
		for j in segs:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][(j + 1) % segs]
			var cc: Vector3 = pts[i + 1][(j + 1) % segs]
			var d: Vector3 = pts[i + 1][j]
			var col := Color("#6a5a45").lerp(Color("#5b5a3a"), rng.randf())
			_tri("foliage", a, b, cc, col, [], (a + cc) * 0.5 - c)
			_tri("foliage", a, cc, d, col, [], (a + cc) * 0.5 - c)


## A grapple skidder: articulated frame, big tyres, cab and blade.
func _skidder(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	_box("paint", Vector3(2.2, 1.0, 3.0), p + b * Vector3(0, 1.4, 1.2), SKIDDER, b)
	_box("paint", Vector3(2.0, 1.0, 2.6), p + b * Vector3(0, 1.4, -1.6), SKIDDER, b)
	_box("paint", Vector3(1.4, 1.5, 1.4), p + b * Vector3(0, 2.6, 0.6), DARK, b)
	_box("paint", Vector3(1.5, 0.12, 1.5), p + b * Vector3(0, 3.4, 0.6), SKIDDER, b)
	_box("paint", Vector3(2.8, 0.9, 0.2), p + b * Vector3(0, 0.6, 3.0), SKIDDER.darkened(0.2), b)
	_box("paint", Vector3(1.8, 0.4, 0.4), p + b * Vector3(0, 2.0, -3.0), DARK, b)  # grapple
	for z in [1.5, -1.8]:
		for x in [-1.25, 1.25]:
			_box("paint", Vector3(0.75, 1.5, 1.5), p + b * Vector3(x, 0.75, z), Color("#1c1c1c"), b)


# ---------------------------------------------------------------- mill

func _mill(size: Vector2) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	# Gravel and bark yard over the whole site.
	_flat_rect("gravel", -hx, hx, -hz, hz, 0.05, YARD)
	# The mill shed: long, metal, low gable; logs go in one end, boards out the other.
	var wall := Color(_pick(["#9aa3a6", "#b9b4a6", "#8e9aa3", "#a39a86"]))
	var band := Color(_pick(["#4a4c4f", "#5a2a26", "#2f3b4a"]))
	var sw := 26.0
	var sd := 11.0
	var sx := hx - sw * 0.5 - 1.5
	var sz := 4.0
	_box("paint", Vector3(sw + 0.2, 0.3, sd + 0.2), Vector3(sx, 0.15, sz), FOUNDATION)
	_box("metal", Vector3(sw, 6.2, sd), Vector3(sx, 3.4, sz), wall)
	_box("metal", Vector3(sw + 0.04, 1.0, sd + 0.04), Vector3(sx, 0.8, sz), band)
	_metal_roof(sx, sz, 6.5, sw, sd, Color(_pick(["#7f8486", "#8a3a2c", "#3e5a48"])))
	# Open infeed end with the log deck conveyor, and a roll-up door on the front.
	_box("paint", Vector3(0.1, 4.0, 5.0), Vector3(sx - sw * 0.5 - 0.05, 2.3, sz), DARK)
	_box("metal", Vector3(6.0, 0.4, 1.2), Vector3(sx - sw * 0.5 - 3.0, 1.0, sz), Color("#5a5e60"))
	_box("siding", Vector3(4.0, 4.2, 0.08), Vector3(sx + 6.0, 2.4, sz - sd * 0.5 - 0.04), Color(TRIM, 0.0))
	_steel_door(Vector3(sx - 4.0, 1.35, sz - sd * 0.5 - 0.04), -1.0)
	# Sawdust: a conveyor up to a tan pile at the back corner.
	var pile := Vector3(hx - 5.0, 0, hz - 5.0)
	_cone_pile(pile, 4.5, 3.6, Color("#b08a5c"))
	_strut(Vector3(sx + 2.0, 4.0, sz + sd * 0.5), pile + Vector3(-0.5, 4.8, -0.5), 0.5, Color("#6b6e70"))
	# Bark pile, darker.
	_cone_pile(Vector3(hx - 13.0, 0, hz - 4.5), 3.5, 2.6, Color("#4e3c2c"))
	# Log decks waiting to be sawn.
	for i in 3:
		_log_deck(Vector3(-hx + 7.0 + i * 0.6, 0, -hz + 14.0 + i * 8.0), PI * 0.5, 9.0, rng.randi_range(7, 10), 0.3)
	# Stickered lumber stacks off the outfeed.
	for i in 4:
		_lumber(Vector3(sx - 8.0 + i * 5.0, 0, hz - 3.5), rng.randf_range(1.0, 1.6))
	for i in 2:
		_lumber(Vector3(sx + 4.0 + i * 5.0, 0, -hz + 6.0), rng.randf_range(1.0, 1.4))
	# Wheel loader with a log grapple, working the decks.
	_loader(Vector3(-hx + 15.0, 0, -hz + 9.0), rng.randf_range(-0.4, 0.4) + PI * 0.5)
	# Scale office: a small sided box with a shed roof, at the gate.
	var ox := -hx + 6.0
	var oz := -hz + 3.5
	_box("paint", Vector3(7.4, 0.5, 4.4), Vector3(ox, 0.25, oz), FOUNDATION)
	_box("siding", Vector3(7.0, 2.8, 4.0), Vector3(ox, 1.9, oz), Color(_pick(["#d8d2c2", "#b8a98c", "#e9e6dc"])))
	_quad("roof", Vector3(ox - 3.8, 3.5, oz - 2.3), Vector3(ox + 3.8, 3.5, oz - 2.3), Vector3(ox + 3.8, 3.15, oz + 2.3), Vector3(ox - 3.8, 3.15, oz + 2.3), Color("#5c5c5e"), [], Vector3.UP)
	_glass(Vector3(ox + 1.6, 2.0, oz - 2.03), Vector3(-1, 0, 0), 1.6, 1.0, 0.3)
	_box("paint", Vector3(0.9, 2.0, 0.06), Vector3(ox - 1.8, 1.5, oz - 2.03), Color("#7a1f1f"))
	_sign(Vector3(ox, 3.6, oz - 2.35), 4.0, 0.6)
	# Truck scale in front of the office.
	_flat_rect("drive", ox + 5.0, ox + 8.5, -hz, -hz + 18.0, 0.08)


## A wood chip mill in the back corner of the yard (Agency "chip_plant"):
## a drum chipper fed tops and slash, a blower spout throwing chips onto a
## tall pale pile, and a chip van waiting to haul them to a paper mill or a
## power plant, as at chip mills beside southern Indiana sawmills.
func _chip_mill(size: Vector2) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var at := Vector3(-hx + 13.0, 0, hz - 8.0)
	_box("paint", Vector3(6.5, 0.3, 3.4), at + Vector3(0, 0.15, 0), FOUNDATION)
	_box("metal", Vector3(5.0, 2.4, 2.6), at + Vector3(0, 1.5, 0), Color("#c9a227"))  # chipper
	_box("metal", Vector3(1.6, 1.2, 2.8), at + Vector3(-3.0, 1.0, 0), Color("#5a5e60"))  # infeed
	var pile := Vector3(-hx + 6.0, 0, hz - 6.0)
	_cone_pile(pile, 5.5, 4.6, Color("#cfae74"))
	_strut(at + Vector3(1.0, 2.8, 0), pile + Vector3(0.5, 5.2, 0.5), 0.35, Color("#6b6e70"))
	# A chip van: a 53 ft open-top aluminium trailer, by the pile.
	_box("metal", Vector3(2.6, 3.6, 15.0), Vector3(-hx + 15.0, 2.2, -hz + 22.0), Color("#c4c8ca"))
	for z in [-5.5, 5.5]:
		_box("paint", Vector3(2.5, 0.9, 1.2), Vector3(-hx + 15.0, 0.45, -hz + 22.0 + z), Color("#262626"))


func _cone_pile(c: Vector3, r: float, h: float, col: Color) -> void:
	var segs := 12
	var top := c + Vector3(0, h, 0)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * r * rng.randf_range(0.9, 1.1)
		var p1 := c + Vector3(cos(a1), 0, sin(a1)) * r
		_tri("foliage", p0, p1, top, col.darkened(rng.randf_range(0.0, 0.1)), [], (p0 + p1) * 0.5 - c + Vector3(0, r, 0))


## A stickered stack of green lumber: board layers with dark gaps.
func _lumber(c: Vector3, h: float) -> void:
	var layers := int(h / 0.18)
	_box("paint", Vector3(1.3, 0.12, 5.0), c + Vector3(0, 0.06, 0), DARK)
	for i in layers:
		_box("paint", Vector3(1.2, 0.13, 4.9), c + Vector3(0, 0.12 + i * 0.18 + 0.065, 0), LUMBER.darkened(rng.randf_range(0.0, 0.08)))
	_box("paint", Vector3(1.24, h, 4.6), c + Vector3(0, 0.12 + h * 0.5, 0), LUMBER.darkened(0.45))


## A wheel loader with a log grapple.
func _loader(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	_box("paint", Vector3(2.4, 1.4, 3.2), p + b * Vector3(0, 1.6, -1.0), YELLOW, b)
	_box("paint", Vector3(2.2, 1.2, 2.2), p + b * Vector3(0, 1.5, 1.8), YELLOW, b)
	_box("paint", Vector3(1.5, 1.6, 1.5), p + b * Vector3(0, 3.1, -0.2), DARK, b)
	_box("paint", Vector3(1.7, 0.12, 1.7), p + b * Vector3(0, 3.95, -0.2), YELLOW, b)
	for x in [-1.0, 1.0]:
		_box("paint", Vector3(0.3, 0.3, 3.0), p + b * Vector3(x * 0.8, 1.9, 3.8), YELLOW.darkened(0.1), b * Basis(Vector3.RIGHT, 0.35))
	_box("paint", Vector3(2.6, 0.5, 0.6), p + b * Vector3(0, 1.5, 5.4), DARK, b)
	for i in 4:
		_box("paint", Vector3(0.12, 1.2, 0.12), p + b * Vector3(-0.9 + i * 0.6, 1.0, 5.6), DARK, b)
	for z in [1.8, -1.4]:
		for x in [-1.3, 1.3]:
			_box("paint", Vector3(0.6, 1.5, 1.5), p + b * Vector3(x, 0.75, z), Color("#1c1c1c"), b)


## A straight flat strip from a to b (local x/z), for trails.
func _flat_band(a: Vector2, b: Vector2, hw: float, y: float, col: Color) -> void:
	var d := (b - a)
	if d.length() < 0.01:
		return
	var n := Vector2(-d.y, d.x).normalized() * hw
	_flat_poly([Vector3(a.x + n.x, 0, a.y + n.y), Vector3(b.x + n.x, 0, b.y + n.y),
		Vector3(b.x - n.x, 0, b.y - n.y), Vector3(a.x - n.x, 0, a.y - n.y)], y, col)
