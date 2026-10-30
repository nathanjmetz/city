class_name RoadSection
extends Control
## A road seen end-on, the way a street plan's cross-section (and Streetmix)
## shows one: walks, grass strips, curbs, parking, bike and bus lanes, a car
## in each lane, the median and its trees, drawn from the road's own numbers
## in RoadStyle, like Icon._road_type draws the small top-down icons. The All
## roads catalog's picture cards use it, so there are no image files.
## Cars coming toward you show headlights; cars going away show tail lights.

var type := 0:
	set(v):
		type = v
		queue_redraw()

const LANE := 3.6
## The narrowest stretch a picture shows, in metres, so an alley isn't drawn
## as big as a boulevard; and the height it keeps room for (a street tree).
const MIN_SPAN := 13.0
const TALL := 5.4

const YARD := Color(0.24, 0.39, 0.22)
const GRASS := Color(0.33, 0.52, 0.28)
const ASPHALT := Color(0.30, 0.31, 0.33)
const SHOULDER := Color(0.37, 0.37, 0.38)
const GUTTER := Color(0.52, 0.52, 0.50)
const BIKE := Color(0.27, 0.50, 0.36)
const BUS := Color(0.62, 0.20, 0.17)
const BARRIER := Color(0.66, 0.65, 0.62)
const TYRE := Color(0.08, 0.08, 0.09)
const GLASS := Color(0.12, 0.17, 0.20)
const HEAD := Color(1.0, 0.93, 0.7)
const TAIL := Color(0.9, 0.18, 0.15)
const TREE := Color(0.20, 0.42, 0.18)
const TREE_LIT := Color(0.30, 0.55, 0.25)
const BARK := Color(0.36, 0.26, 0.18)
const POLE := Color(0.42, 0.33, 0.24)
const STEEL := Color(0.55, 0.57, 0.58)
const SKIN := Color(0.86, 0.69, 0.55)
## Everyday car colours: white, silver, a dark blue, a red, charcoal, tan.
const CAR_COLORS := [Color("#dedad0"), Color("#9ea6ab"), Color("#2f4f86"), Color("#8c2f2a"), Color("#3b464c"), Color("#b9a27a")]
const SURFACES := {"gravel": Color(0.62, 0.56, 0.45), "concrete": Color(0.58, 0.58, 0.56),
	"dirt": Color(0.52, 0.40, 0.28), "chip seal": Color(0.45, 0.43, 0.40), "brick": Color(0.58, 0.30, 0.22)}
## Strips at curb height; the rest lie at the pavement.
const RAISED := ["walk", "grass", "curb", "median"]
## Strips paved with the road's own surface.
const PAVED := ["lane", "parking", "angle", "turn", "edge", "center"]

static var _well: StyleBoxFlat


func _init(t := 0) -> void:
	type = t
	custom_minimum_size = Vector2(0, 96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


## The road from one side's edge to the other, left to right, as
## [kind, metres, way]: way is 1 for a lane going away from you, -1 for one
## coming toward you, 0 for everything else. Kinds: walk, grass, curb,
## gutter, parking, angle (angled stalls), bike, bus, lane, turn (a shared
## left-turn lane), center (the double yellow, no width), median (raised and
## planted), median_grass (a highway's grass median), shoulder, edge (a paved
## strip past the edge line), verge (grass beside a road with no curb) and
## barrier. They add up to the road's whole width, walks included
## (RoadStyle.right_of_way_half).
static func parts(t: int) -> Array:
	var spec: Dictionary = RoadStyle.TYPES[t]
	var lanes: int = spec.lanes
	var paved: float = spec.width
	if RoadStyle.is_freeway(t):
		# 10 ft right and 4 ft left shoulders, a wall and a clear zone each side.
		var out := [["verge", 0.9, 0], ["barrier", 0.6, 0], ["shoulder", 1.2, 0]]
		for i in lanes:
			out.append(["lane", LANE, 1])
		out.append_array([["shoulder", maxf(paved - lanes * LANE - 1.2, 0.0), 0], ["barrier", 0.6, 0], ["verge", 0.9, 0]])
		return out
	var rural: bool = spec.get("rural", false)
	var median: float = spec.median
	var bike: float = RoadStyle.BIKE_WIDTH if spec.get("bike", false) else 0.0
	var shoulder: float = spec.get("shoulder", 0.0)
	var park := RoadStyle.parking_width(t)
	if park == 0.0 and RoadCatalog.parks(t):
		park = 2.2  # a plain street parks along both curbs
	var lane := LANE
	var each: float = (paved - median - lanes * LANE) * 0.5 - park - bike - shoulder
	if each < 0.0:
		# Narrower lanes where the parking or the surface leaves less room
		# (a 30 ft street with cars parked both sides, a gravel road).
		lane = (paved - median - 2.0 * (park + bike + shoulder)) / lanes
		each = 0.0
	var side := []  # the right side, outside in
	if rural:
		side.append(["verge", spec.get("verge", 3.0), 0])
	else:
		side.append_array([["walk", RoadStyle.SIDEWALK_WIDTH, 0], ["grass", RoadStyle.PARKWAY_WIDTH, 0],
			["curb", RoadStyle.CURB_WIDTH, 0]])
	if shoulder > 0.0:
		side.append(["shoulder", shoulder, 0])
	if each > 0.01:
		side.append(["edge" if rural else "gutter", each, 0])
	if park > 0.0:
		side.append(["angle" if spec.get("angle", false) else "parking", park, 0])
	if bike > 0.0:
		side.append(["bike", bike, 0])
	var bus: bool = spec.get("bus", false)
	var away: int = lanes if spec.oneway else lanes - lanes / 2
	var toward: int = 0 if spec.oneway else lanes / 2
	var out := side.duplicate()
	for i in toward:
		out.append(["bus" if bus and i == 0 else "lane", lane, -1])
	if spec.get("turn", false):
		out.append(["turn", median, 0])
	elif median > 0.0 and rural:
		out.append_array([["shoulder", 1.2, 0], ["median_grass", median - 2.4, 0], ["shoulder", 1.2, 0]])
	elif median > 0.0:
		out.append(["median", median, 0])
	elif not spec.oneway:
		out.append(["center", 0.0, 0])
	for i in away:
		out.append(["bus" if bus and i == away - 1 else "lane", lane, 1])
	var back := side.duplicate()
	back.reverse()
	out.append_array(back)
	return out


func _draw() -> void:
	if _well == null:
		_well = UiStyle._box(Brand.SURFACE_SUNKEN, UiStyle.RADIUS_SM)
	draw_style_box(_well, Rect2(Vector2.ZERO, size))
	if type < 0 or type >= RoadStyle.TYPES.size() or size.x < 20.0:
		return
	var spec: Dictionary = RoadStyle.TYPES[type]
	var ps := parts(type)
	var total := 0.0
	for p in ps:
		total += p[1]
	var band := clampf(size.y * 0.17, 10.0, 16.0)
	var gy := size.y - band - 4.0  # the ground line
	var s := minf((size.x - 10.0) / maxf(total, MIN_SPAN), (gy - 6.0) / TALL)  # pixels per metre
	var x0 := (size.x - total * s) * 0.5
	var surface: String = spec.get("surface", "")
	var pave: Color = SURFACES.get(surface, ASPHALT)
	var marked := surface == ""
	var lift := maxf(2.0, 0.18 * s)
	var xs := []
	var x := x0
	for p in ps:
		xs.append(x)
		x += p[1] * s
	# The ground: yards either side, then each strip's own surface.
	draw_rect(Rect2(4.0, gy, size.x - 8.0, band), YARD)
	for i in ps.size():
		var k: String = ps[i][0]
		var top := gy - (lift if k in RAISED else 0.0)
		draw_rect(Rect2(xs[i], top, ps[i][1] * s + 0.5, gy + band - top), _ground(k, pave))
	# Paint: lane lines, the double yellow, edge and bike lines, arrows.
	if marked:
		for i in ps.size():
			var k: String = ps[i][0]
			var a: float = xs[i]
			var w: float = ps[i][1] * s
			if k == "center":
				_line(a - 2.0, gy, band, RoadStyle.MARKING_YELLOW)
				_line(a + 0.5, gy, band, RoadStyle.MARKING_YELLOW)
			elif k == "turn":
				_line(a + 1.0, gy, band, RoadStyle.MARKING_YELLOW)
				_line(a + w - 2.5, gy, band, RoadStyle.MARKING_YELLOW)
			elif k in ["lane", "bus"]:
				_arrow(a + w * 0.5, gy + band * 0.55, minf(band * 0.32, w * 0.3), ps[i][2])
				if i + 1 < ps.size() and ps[i + 1][0] in ["lane", "bus"] and ps[i + 1][2] == ps[i][2]:
					_dash(a + w, gy, band)
				elif i + 1 < ps.size() and ps[i + 1][0] in ["shoulder", "edge", "bike"]:
					_line(a + w - 0.75, gy, band, RoadStyle.MARKING_WHITE)
				if i > 0 and ps[i - 1][0] in ["shoulder", "edge", "bike"]:
					_line(a - 0.75, gy, band, RoadStyle.MARKING_WHITE)
	# What stands on it.
	var lane_n := 0
	var walk_n := 0
	var cx := 0.0
	for i in ps.size():
		var k: String = ps[i][0]
		var w: float = ps[i][1] * s
		cx = xs[i] + w * 0.5
		match k:
			"lane":
				var col: Color = CAR_COLORS[(lane_n * 2 + type) % CAR_COLORS.size()]
				_car(cx, gy, s, minf(w * 0.86, 1.8 * s), col, ps[i][2])
				lane_n += 1
			"bus":
				_bus(cx, gy, s, minf(w * 0.9, 2.6 * s), ps[i][2])
			"parking", "angle":
				_car(cx, gy, s, minf(w * 0.86, 1.8 * s), Color(0.55, 0.57, 0.6) if i < ps.size() / 2 else Color(0.70, 0.66, 0.58), 0)
			"bike":
				_cyclist(cx, gy, s, ps[i - 1][2] if i > 0 and ps[i - 1][0] == "lane" else (ps[i + 1][2] if i + 1 < ps.size() else 1))
			"walk":
				_person(cx + (w * 0.1 if walk_n == 0 else -w * 0.1), gy - lift, s,
					Brand.PLAYER_SKY if walk_n == 0 else Brand.PLAYER_GOLDENROD)
				walk_n += 1
			"grass":
				# A street light on the right-hand strip, its arm over the road.
				if i > ps.size() / 2:
					_lamp(cx, gy - lift, s, -1.0)
			"median":
				if spec.get("trees", false):
					_tree(cx, gy - lift, s, minf(w * 0.5, 2.2 * s))
				elif w > 1.6 * s:
					_lamp(cx, gy - lift, s, 0.0)
			"barrier":
				_barrier(cx, gy, s)
			"verge":
				# Wood poles carry the wires along a country road.
				if i > ps.size() / 2 and spec.get("rural", false) and not RoadStyle.is_freeway(type) and spec.lots:
					_pole(xs[i] + w * 0.6, gy, s)


static func _ground(k: String, pave: Color) -> Color:
	match k:
		"walk":
			return RoadStyle.SIDEWALK_COLOR
		"curb":
			return RoadStyle.CURB_COLOR
		"grass", "median", "median_grass", "verge":
			return GRASS
		"gutter":
			return GUTTER
		"shoulder":
			return SHOULDER if pave == ASPHALT else pave.lightened(0.06)
		"bike":
			return BIKE
		"bus":
			return BUS
		"barrier":
			return SHOULDER
	return pave


func _line(x: float, gy: float, band: float, col: Color) -> void:
	draw_rect(Rect2(x, gy, 1.5, band * 0.42), col)


func _dash(x: float, gy: float, band: float) -> void:
	draw_rect(Rect2(x - 0.75, gy, 1.5, band * 0.42), Color(RoadStyle.MARKING_WHITE, 0.85))


## A lane arrow painted on the road: up for away, down for toward.
func _arrow(cx: float, cy: float, r: float, way: int) -> void:
	if way == 0 or r < 1.5:
		return
	var d := -float(way)
	draw_colored_polygon(PackedVector2Array([Vector2(cx, cy + d * r), Vector2(cx - r * 0.9, cy - d * r * 0.6),
		Vector2(cx + r * 0.9, cy - d * r * 0.6)]), Color(RoadStyle.MARKING_WHITE, 0.75))


## A car seen from behind (way 1, tail lights) or the front (way -1,
## headlights); parked cars (way 0) show neither.
func _car(cx: float, gy: float, s: float, width: float, col: Color, way: int) -> void:
	var w := maxf(width, 7.0)
	var h := maxf(1.45 * s, 6.0)
	var l := cx - w * 0.5
	draw_rect(Rect2(l + w * 0.05, gy - h * 0.24, w * 0.18, h * 0.24), TYRE)
	draw_rect(Rect2(l + w * 0.77, gy - h * 0.24, w * 0.18, h * 0.24), TYRE)
	draw_rect(Rect2(l, gy - h * 0.62, w, h * 0.44), col)
	draw_rect(Rect2(l + w * 0.13, gy - h, w * 0.74, h * 0.4), col.darkened(0.12))
	draw_rect(Rect2(l + w * 0.2, gy - h * 0.93, w * 0.6, h * 0.28), GLASS)
	if way != 0:
		var lc := HEAD if way < 0 else TAIL
		draw_rect(Rect2(l + w * 0.05, gy - h * 0.54, w * 0.17, h * 0.11), lc)
		draw_rect(Rect2(l + w * 0.78, gy - h * 0.54, w * 0.17, h * 0.11), lc)


func _bus(cx: float, gy: float, s: float, width: float, way: int) -> void:
	var w := maxf(width, 9.0)
	var h := maxf(3.1 * s, 13.0)
	var l := cx - w * 0.5
	draw_rect(Rect2(l + w * 0.08, gy - h * 0.12, w * 0.2, h * 0.12), TYRE)
	draw_rect(Rect2(l + w * 0.72, gy - h * 0.12, w * 0.2, h * 0.12), TYRE)
	draw_rect(Rect2(l, gy - h, w, h * 0.9), Color(0.90, 0.88, 0.82))
	draw_rect(Rect2(l + w * 0.1, gy - h * 0.82, w * 0.8, h * 0.36), GLASS)
	draw_rect(Rect2(l + w * 0.18, gy - h * 0.96, w * 0.64, h * 0.1), Brand.PLAYER_GOLDENROD)
	draw_rect(Rect2(l, gy - h * 0.34, w, h * 0.08), Brand.PLAYER_LAKE)
	var lc := HEAD if way < 0 else TAIL
	draw_rect(Rect2(l + w * 0.06, gy - h * 0.24, w * 0.14, h * 0.07), lc)
	draw_rect(Rect2(l + w * 0.8, gy - h * 0.24, w * 0.14, h * 0.07), lc)


func _person(cx: float, gy: float, s: float, shirt: Color) -> void:
	var h := maxf(1.7 * s, 9.0)
	var w := maxf(0.45 * s, 3.0)
	draw_rect(Rect2(cx - w * 0.4, gy - h * 0.45, w * 0.8, h * 0.45), Color(0.18, 0.22, 0.3))
	draw_rect(Rect2(cx - w * 0.5, gy - h * 0.8, w, h * 0.38), shirt)
	draw_circle(Vector2(cx, gy - h * 0.89), maxf(0.12 * s, 1.6), SKIN)


func _cyclist(cx: float, gy: float, s: float, way: int) -> void:
	var tyre := maxf(0.68 * s, 4.0)
	draw_rect(Rect2(cx - 0.75, gy - tyre, 1.5, tyre), TYRE)
	var hb := maxf(0.5 * s, 3.0)
	draw_line(Vector2(cx - hb, gy - tyre * 1.35), Vector2(cx + hb, gy - tyre * 1.35), STEEL, 1.2, true)
	_person(cx, gy - tyre * 0.55, s * 0.85, Brand.PLAYER_PRAIRIE)
	draw_rect(Rect2(cx - 1.0, gy - tyre * 0.75, 2.0, tyre * 0.18), TAIL if way > 0 else HEAD)


func _tree(cx: float, gy: float, s: float, r: float) -> void:
	r = maxf(r, 4.0)
	var trunk := maxf(2.6 * s, 8.0)
	draw_rect(Rect2(cx - maxf(0.15 * s, 1.0), gy - trunk, maxf(0.3 * s, 2.0), trunk), BARK)
	var c := Vector2(cx, gy - trunk - r * 0.7)
	draw_circle(c, r, TREE)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.55, TREE_LIT)


## A street light: a pole with its arm reaching toward `toward` (-1 left,
## 1 right, 0 both ways from a median).
func _lamp(cx: float, gy: float, s: float, toward: float) -> void:
	var h := minf(maxf(6.0 * s, 16.0), gy - 4.0)
	var pw := maxf(0.16 * s, 1.5)
	draw_rect(Rect2(cx - pw * 0.5, gy - h, pw, h), STEEL)
	var arm := maxf(1.6 * s, 6.0)
	for d in ([-1.0, 1.0] if toward == 0.0 else [toward]):
		var tip := Vector2(cx + d * arm, gy - h)
		draw_line(Vector2(cx, gy - h), tip, STEEL, pw, true)
		draw_rect(Rect2(tip.x - pw * 1.5, tip.y, pw * 3.0, pw * 1.2), HEAD)


func _barrier(cx: float, gy: float, s: float) -> void:
	var base := maxf(0.6 * s, 4.0)
	var h := maxf(0.82 * s, 5.0)
	draw_colored_polygon(PackedVector2Array([Vector2(cx - base * 0.5, gy), Vector2(cx + base * 0.5, gy),
		Vector2(cx + base * 0.2, gy - h * 0.35), Vector2(cx + base * 0.15, gy - h), Vector2(cx - base * 0.15, gy - h),
		Vector2(cx - base * 0.2, gy - h * 0.35)]), BARRIER)


func _pole(cx: float, gy: float, s: float) -> void:
	var h := minf(maxf(7.5 * s, 18.0), gy - 3.0)
	var pw := maxf(0.25 * s, 1.5)
	draw_rect(Rect2(cx - pw * 0.5, gy - h, pw, h), POLE)
	var arm := maxf(1.2 * s, 5.0)
	draw_rect(Rect2(cx - arm, gy - h * 0.94, arm * 2.0, pw * 0.8), POLE)
	for d in [-0.8, 0.0, 0.8]:
		draw_circle(Vector2(cx + d * arm, gy - h * 0.94 - 1.0), 1.2, STEEL)
