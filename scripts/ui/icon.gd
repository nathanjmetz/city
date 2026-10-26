class_name Icon
extends Control
## Small game icons by name. Common ones come from the brand's icon set
## (Phosphor Bold, white SVGs in assets/brand/icons/, tinted with `color`);
## road shapes, resources and other game-specific ones are drawn in code.
## Set `kind` to a name in _FILES or one handled in _draw().

@export var kind := "road":
	set(v):
		kind = v
		queue_redraw()
var color := Brand.INK:
	set(v):
		color = v
		queue_redraw()
## Optional second colour (zone tints and the like).
var accent := Brand.BRAND_TEAL:
	set(v):
		accent = v
		queue_redraw()


## Names drawn from the brand icon set: kind -> file in assets/brand/icons/.
const _FILES := {
	"road": "road", "roads": "road", "bulldoze": "bulldoze", "homes": "homes", "zones": "zones",
	"shops": "shops", "industry": "industry", "dezone": "dezone", "pause": "pause", "people": "people",
	"jobs": "jobs", "car": "car", "money": "money", "budget": "money", "power": "power", "water": "water",
	"fire": "fire", "police": "police", "health": "health", "school": "school", "services": "services",
	"farms": "farms", "farmland": "farms", "traffic": "traffic", "signal": "signal", "views": "views",
	"help": "help", "grid": "grid", "curve": "curve", "roundabout": "roundabout",
	"bus": "bus", "transit": "bus", "taxi": "taxi",
	"permits": "permits", "check": "check", "close": "close",
	"power_line": "power_line", "substation": "substation", "power_co": "power_co",
	"well": "well", "water_tower": "water_tower", "water_utility": "water_utility",
	"landfill": "landfill", "recycling": "recycling", "phone_co": "phone_co", "tower": "phone_co",
	"elementary": "elementary", "daycare": "daycare", "high_school": "high_school", "college": "college",
	"university": "university", "clinic": "clinic", "hospital": "hospital", "nursing_home": "nursing_home",
	"cemetery": "cemetery",
	"bus_depot": "bus_depot", "taxi_company": "taxi_company", "rail_depot": "rail_depot", "builder_yard": "builder_yard",
	"parking_small": "parking_small", "parking_downtown": "parking_downtown", "parking_large": "parking_large",
	"park_and_ride": "park_and_ride", "parking_garage": "parking_garage",
	"farm_corn": "farm_corn", "farm_soy": "farm_soy", "oil_co": "oil_co", "mine_co": "mine_co", "forestry_co": "forestry_co",
	"warehouse_co": "warehouse_co", "ethanol": "ethanol", "meatpacker": "meatpacker", "furniture": "furniture", "rv_plant": "rv_plant",
	"fire_station": "fire_station", "police_station": "police_station", "post_office": "post_office", "bank_co": "bank_co", "farm_credit": "farm_credit",
}
## These get a soft `accent` fill behind the line (zone tints and the like).
const _DUOTONE := ["homes", "zones", "shops", "industry", "farms", "farmland"]
## Detailed Neighbors icons (one per service, drawn from a real reference
## and split by the House mark's gaps): a soft shade layer, a mint accent
## piece like the mark's roof, then the line art. Files: name, name-shade,
## name-accent.
const _LAYERED := ["power_line", "substation", "power_co", "well", "water_tower",
	"water_utility", "landfill", "recycling", "phone_co", "elementary", "daycare", "high_school",
	"college", "university", "clinic", "hospital", "nursing_home", "cemetery",
	"bus_depot", "taxi_company", "rail_depot", "builder_yard", "parking_small", "parking_downtown", "parking_large",
	"park_and_ride", "parking_garage",
	"farm_corn", "farm_soy", "oil_co", "mine_co", "forestry_co", "warehouse_co",
	"ethanol", "meatpacker", "furniture", "rv_plant", "fire_station", "police_station",
	"post_office", "bank_co", "farm_credit"]
static var _textures := {}


func _init(k := "road", size_px := 40.0) -> void:
	kind = k
	custom_minimum_size = Vector2(size_px, size_px)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var w := maxf(1.5, s * 0.07)
	# Everything below is drawn on a 0..1 square, scaled by P().
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var line := func(a: Vector2, b: Vector2, width := w, col := color): draw_line(a, b, col, width, true)
	if _FILES.has(kind):
		var rect := Rect2(o, Vector2(s, s))
		if kind in _DUOTONE:
			draw_texture_rect(_texture(_FILES[kind] + "-fill"), rect, false, Color(accent, 0.45))
		elif _FILES[kind] in _LAYERED:
			# Bold single-front icons have no shade layer.
			if ResourceLoader.exists("res://assets/brand/icons/%s-shade.svg" % _FILES[kind]):
				draw_texture_rect(_texture(_FILES[kind] + "-shade"), rect, false, Color(color, 0.5))
			draw_texture_rect(_texture(_FILES[kind] + "-accent"), rect, false, Brand.BRAND_MINT)
		draw_texture_rect(_texture(_FILES[kind]), rect, false, color)
		return
	match kind:
		"music":
			# Two beamed eighth notes.
			for x in [0.3, 0.76]:
				draw_circle(P.call(x - 0.1, 0.78), s * 0.12, color)
				line.call(P.call(x, 0.78), P.call(x, 0.2))
			_poly([P.call(0.3, 0.2), P.call(0.76, 0.1), P.call(0.76, 0.24), P.call(0.3, 0.34)], color)
		"parking":
			# The MUTCD parking sign: a P in a rounded square.
			var r := Rect2(P.call(0.18, 0.14), Vector2(s * 0.64, s * 0.72))
			draw_rect(r, color, false, w)
			line.call(P.call(0.4, 0.3), P.call(0.4, 0.74))
			var bowl := PackedVector2Array()
			for i in 17:
				var a := -PI * 0.5 + PI * i / 16.0
				bowl.append(P.call(0.47, 0.42) + Vector2(cos(a), sin(a)) * s * 0.12)
			draw_polyline(PackedVector2Array([P.call(0.4, 0.3), P.call(0.47, 0.3)]) + bowl
				+ PackedVector2Array([P.call(0.4, 0.54)]), color, w, true)
		"region":
			# A globe: the region's shared projects and neighbors.
			var c: Vector2 = P.call(0.5, 0.5)
			draw_arc(c, s * 0.38, 0.0, TAU, 32, color, w, true)
			line.call(P.call(0.12, 0.5), P.call(0.88, 0.5))
			var pts := PackedVector2Array()
			for i in 33:
				var a := TAU * i / 32.0
				pts.append(c + Vector2(cos(a) * s * 0.16, sin(a) * s * 0.38))
			draw_polyline(pts, color, w, true)
		"search":
			# A magnifying glass: find a building or tool.
			draw_arc(P.call(0.42, 0.42), s * 0.26, 0.0, TAU, 28, color, w, true)
			line.call(P.call(0.61, 0.61), P.call(0.86, 0.86), w * 1.4)
		"chat":
			# A speech bubble: the region chat.
			var box := PackedVector2Array([P.call(0.12, 0.16), P.call(0.88, 0.16), P.call(0.88, 0.66),
				P.call(0.46, 0.66), P.call(0.26, 0.86), P.call(0.3, 0.66), P.call(0.12, 0.66), P.call(0.12, 0.16)])
			_poly(box, Color(color, 0.25))
			draw_polyline(box, color, w, true)
		"road", "roads":
			_poly([P.call(0.3, 0.92), P.call(0.42, 0.08), P.call(0.58, 0.08), P.call(0.7, 0.92)], Color(color, 0.25))
			line.call(P.call(0.3, 0.92), P.call(0.42, 0.08))
			line.call(P.call(0.7, 0.92), P.call(0.58, 0.08))
			for i in 3:
				var y0 := 0.15 + i * 0.28
				line.call(P.call(0.5, y0), P.call(0.5, y0 + 0.14), w * 0.8)
		"curve":
			draw_arc(P.call(0.95, 0.95), s * 0.62, PI, PI * 1.5, 24, color, w, true)
			draw_arc(P.call(0.95, 0.95), s * 0.32, PI, PI * 1.5, 24, color, w, true)
			draw_arc(P.call(0.95, 0.95), s * 0.47, PI * 1.05, PI * 1.45, 12, Color(color, 0.6), w * 0.6, true)
		"grid":
			for i in 3:
				var t := 0.18 + i * 0.32
				line.call(P.call(0.08, t), P.call(0.92, t))
				line.call(P.call(t, 0.08), P.call(t, 0.92))
		"roundabout":
			draw_arc(P.call(0.5, 0.5), s * 0.24, 0, TAU, 32, color, w, true)
			draw_arc(P.call(0.5, 0.5), s * 0.1, 0, TAU, 24, color, w * 0.8, true)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				line.call(o + Vector2(0.5, 0.5) * s + d * s * 0.27, o + Vector2(0.5, 0.5) * s + d * s * 0.46)
		"upgrade":
			line.call(P.call(0.22, 0.92), P.call(0.22, 0.4))
			line.call(P.call(0.78, 0.92), P.call(0.78, 0.4))
			line.call(P.call(0.5, 0.75), P.call(0.5, 0.1))
			draw_polyline(PackedVector2Array([P.call(0.3, 0.3), P.call(0.5, 0.1), P.call(0.7, 0.3)]), color, w, true)
		"parallel":
			for x in [0.14, 0.4, 0.6, 0.86]:
				line.call(P.call(x, 0.9), P.call(x, 0.1))
			_poly([P.call(0.14, 0.9), P.call(0.14, 0.1), P.call(0.4, 0.1), P.call(0.4, 0.9)], Color(color, 0.2))
			_poly([P.call(0.6, 0.9), P.call(0.6, 0.1), P.call(0.86, 0.1), P.call(0.86, 0.9)], Color(color, 0.2))
		"bulldoze":
			_poly([P.call(0.3, 0.62), P.call(0.3, 0.42), P.call(0.48, 0.42), P.call(0.55, 0.25),
				P.call(0.75, 0.25), P.call(0.75, 0.62)], Color(color, 0.85))
			draw_rect(Rect2(P.call(0.28, 0.66), Vector2(0.52, 0.18) * s), color, false, w)
			for x in [0.37, 0.54, 0.71]:
				draw_circle(P.call(x, 0.75), s * 0.05, color)
			line.call(P.call(0.08, 0.38), P.call(0.14, 0.86), w * 1.4)
			line.call(P.call(0.14, 0.62), P.call(0.3, 0.55))
		"move":
			# Four arrows out from the middle, like Move It's icon.
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var tip: Vector2 = Vector2(0.5, 0.5) + d * 0.4
				var side: Vector2 = Vector2(-d.y, d.x) * 0.12
				line.call(P.call(0.5 + d.x * 0.1, 0.5 + d.y * 0.1), P.call(tip.x, tip.y))
				draw_polyline(PackedVector2Array([P.call(tip.x - d.x * 0.13 + side.x, tip.y - d.y * 0.13 + side.y),
					P.call(tip.x, tip.y), P.call(tip.x - d.x * 0.13 - side.x, tip.y - d.y * 0.13 - side.y)]), color, w, true)
		"homes", "zones":
			var tint := accent if kind == "homes" else Color(0.35, 0.85, 0.35)
			_poly([P.call(0.15, 0.48), P.call(0.5, 0.15), P.call(0.85, 0.48), P.call(0.78, 0.48),
				P.call(0.78, 0.88), P.call(0.22, 0.88), P.call(0.22, 0.48)], Color(tint, 0.35))
			draw_polyline(PackedVector2Array([P.call(0.1, 0.52), P.call(0.5, 0.15), P.call(0.9, 0.52)]), color, w, true)
			draw_polyline(PackedVector2Array([P.call(0.22, 0.45), P.call(0.22, 0.88), P.call(0.78, 0.88),
				P.call(0.78, 0.45)]), color, w, true)
			draw_rect(Rect2(P.call(0.43, 0.62), Vector2(0.14, 0.26) * s), color)
			if kind == "zones":
				draw_rect(Rect2(P.call(0.62, 0.62), Vector2(0.3, 0.3) * s), Color(0.30, 0.60, 1.0))
				draw_rect(Rect2(P.call(0.62, 0.62), Vector2(0.3, 0.3) * s), color, false, w * 0.6)
		"shops":
			_poly([P.call(0.12, 0.45), P.call(0.88, 0.45), P.call(0.88, 0.88), P.call(0.12, 0.88)], Color(accent, 0.3))
			draw_rect(Rect2(P.call(0.12, 0.45), Vector2(0.76, 0.43) * s), color, false, w)
			for i in 4:
				var x0 := 0.1 + i * 0.2
				_poly([P.call(x0, 0.2), P.call(x0 + 0.2, 0.2), P.call(x0 + 0.2, 0.4), P.call(x0, 0.4)],
					accent if i % 2 == 0 else color)
			draw_rect(Rect2(P.call(0.24, 0.58), Vector2(0.24, 0.3) * s), color, false, w * 0.7)
			draw_rect(Rect2(P.call(0.56, 0.58), Vector2(0.22, 0.16) * s), color, false, w * 0.7)
		"industry":
			var roof := PackedVector2Array([P.call(0.08, 0.9), P.call(0.08, 0.5), P.call(0.32, 0.36),
				P.call(0.32, 0.5), P.call(0.56, 0.36), P.call(0.56, 0.5), P.call(0.66, 0.5), P.call(0.66, 0.12),
				P.call(0.8, 0.12), P.call(0.8, 0.5), P.call(0.92, 0.5), P.call(0.92, 0.9)])
			_poly(Array(roof), Color(accent, 0.35))
			roof.append(roof[0])
			draw_polyline(roof, color, w, true)
		"warehouse":
			# A long low box with dock doors along its front.
			_poly([P.call(0.06, 0.88), P.call(0.06, 0.4), P.call(0.94, 0.3), P.call(0.94, 0.88)], Color(accent, 0.35))
			draw_polyline(PackedVector2Array([P.call(0.06, 0.88), P.call(0.06, 0.4), P.call(0.94, 0.3),
				P.call(0.94, 0.88), P.call(0.06, 0.88)]), color, w, true)
			for x in [0.3, 0.5, 0.7]:
				draw_rect(Rect2(P.call(x - 0.07, 0.58), Vector2(0.14, 0.3) * s), color, false, w * 0.7)
			draw_rect(Rect2(P.call(0.12, 0.56), Vector2(0.08, 0.1) * s), color)
		"zone_street":
			# A street with its block face shaded along one side.
			line.call(P.call(0.08, 0.3), P.call(0.92, 0.3))
			line.call(P.call(0.08, 0.44), P.call(0.92, 0.44))
			_poly([P.call(0.12, 0.52), P.call(0.88, 0.52), P.call(0.88, 0.88), P.call(0.12, 0.88)], Color(color, 0.35))
			for x in [0.37, 0.62]:
				line.call(P.call(x, 0.52), P.call(x, 0.88), w * 0.6)
		"zone_brush":
			# A round brush over a painted patch.
			draw_circle(P.call(0.5, 0.5), s * 0.34, Color(color, 0.3))
			draw_arc(P.call(0.5, 0.5), s * 0.34, 0.0, TAU, 32, color, w, true)
			draw_circle(P.call(0.5, 0.5), s * 0.06, color)
		"zone_smart":
			# A shaded block face with a spark: it guesses for you.
			_poly([P.call(0.1, 0.56), P.call(0.6, 0.56), P.call(0.6, 0.9), P.call(0.1, 0.9)], Color(color, 0.35))
			line.call(P.call(0.06, 0.48), P.call(0.66, 0.48))
			var c: Vector2 = P.call(0.74, 0.26)
			for a in 4:
				var d := Vector2.from_angle(a * PI * 0.5)
				line.call(c + d * s * 0.05, c + d * s * 0.2, w * 0.9)
			for a in 4:
				var d := Vector2.from_angle(PI * 0.25 + a * PI * 0.5)
				line.call(c + d * s * 0.05, c + d * s * 0.11, w * 0.7)
		"dezone":
			draw_rect(Rect2(P.call(0.12, 0.12), Vector2(0.76, 0.76) * s), Color(color, 0.5), false, w * 0.6)
			line.call(P.call(0.25, 0.25), P.call(0.75, 0.75), w * 1.3, Color(1, 0.45, 0.4))
			line.call(P.call(0.75, 0.25), P.call(0.25, 0.75), w * 1.3, Color(1, 0.45, 0.4))
		"street", "avenue", "boulevard", "highway", "ramp":
			_road_section(P, w)
		_ when kind.begins_with("road:"):
			_road_type(P, w, int(kind.substr(5)))
		"raise", "lower":
			var up := kind == "raise"
			line.call(P.call(0.08, 0.72), P.call(0.92, 0.72))
			for x in [0.25, 0.75]:
				line.call(P.call(x, 0.72), P.call(x, 0.92), w * 0.8)
			var tip := 0.12 if up else 0.55
			var tail := 0.55 if up else 0.12
			line.call(P.call(0.5, tail), P.call(0.5, tip))
			var dy := 0.14 if up else -0.14
			draw_polyline(PackedVector2Array([P.call(0.36, tip + dy), P.call(0.5, tip), P.call(0.64, tip + dy)]),
				color, w, true)
		"pause":
			draw_rect(Rect2(P.call(0.28, 0.22), Vector2(0.14, 0.56) * s), color)
			draw_rect(Rect2(P.call(0.58, 0.22), Vector2(0.14, 0.56) * s), color)
		"play", "fast", "faster":
			var n: int = {"play": 1, "fast": 2, "faster": 3}[kind]
			var wid: float = 0.62 / n
			for i in n:
				var x0: float = 0.2 + i * wid
				_poly([P.call(x0, 0.22), P.call(x0 + wid, 0.5), P.call(x0, 0.78)], color)
		"people":
			draw_circle(P.call(0.5, 0.3), s * 0.15, color)
			draw_arc(P.call(0.5, 0.95), s * 0.34, PI, TAU, 24, color, w * 2.2, true)
		"jobs":
			draw_rect(Rect2(P.call(0.14, 0.34), Vector2(0.72, 0.5) * s), color, false, w)
			draw_rect(Rect2(P.call(0.38, 0.2), Vector2(0.24, 0.14) * s), color, false, w * 0.8)
			line.call(P.call(0.14, 0.55), P.call(0.86, 0.55), w * 0.7)
		"car":
			_poly([P.call(0.08, 0.68), P.call(0.08, 0.5), P.call(0.24, 0.48), P.call(0.36, 0.3),
				P.call(0.68, 0.3), P.call(0.82, 0.48), P.call(0.92, 0.52), P.call(0.92, 0.68)], color)
			draw_circle(P.call(0.27, 0.7), s * 0.09, Color(0.12, 0.13, 0.15))
			draw_circle(P.call(0.73, 0.7), s * 0.09, Color(0.12, 0.13, 0.15))
		"money", "budget":
			# A stack of coins with a dollar sign on the top one.
			for i in 3:
				var y := 0.78 - i * 0.14
				draw_rect(Rect2(P.call(0.2, y - 0.07), Vector2(0.6, 0.14) * s), Color(color, 0.35 + i * 0.15))
				draw_rect(Rect2(P.call(0.2, y - 0.07), Vector2(0.6, 0.14) * s), color, false, w * 0.6)
			draw_circle(P.call(0.5, 0.28), s * 0.2, accent if kind == "budget" else Color(0.45, 0.8, 0.45))
			line.call(P.call(0.5, 0.15), P.call(0.5, 0.41), w * 0.7, Color(0.08, 0.1, 0.12))
			draw_arc(P.call(0.5, 0.23), s * 0.06, PI * 0.5, PI * 1.9, 10, Color(0.08, 0.1, 0.12), w * 0.6, true)
			draw_arc(P.call(0.5, 0.33), s * 0.06, -PI * 0.5, PI * 0.9, 10, Color(0.08, 0.1, 0.12), w * 0.6, true)
		"power":
			_poly([P.call(0.58, 0.06), P.call(0.22, 0.56), P.call(0.48, 0.56), P.call(0.4, 0.94),
				P.call(0.78, 0.4), P.call(0.52, 0.4)], Color(1.0, 0.82, 0.3))
		"water":
			# Water tower: a round tank on legs.
			draw_circle(P.call(0.5, 0.32), s * 0.24, Color(0.55, 0.78, 0.95))
			line.call(P.call(0.34, 0.5), P.call(0.24, 0.94))
			line.call(P.call(0.66, 0.5), P.call(0.76, 0.94))
			line.call(P.call(0.5, 0.56), P.call(0.5, 0.94))
		"fire":
			_poly([P.call(0.5, 0.06), P.call(0.78, 0.5), P.call(0.74, 0.76), P.call(0.5, 0.94),
				P.call(0.26, 0.76), P.call(0.22, 0.5), P.call(0.38, 0.34)], Color(0.95, 0.42, 0.25))
			_poly([P.call(0.5, 0.46), P.call(0.62, 0.7), P.call(0.5, 0.86), P.call(0.38, 0.7)], Color(1.0, 0.82, 0.35))
		"police":
			_poly([P.call(0.5, 0.06), P.call(0.86, 0.2), P.call(0.8, 0.6), P.call(0.5, 0.94),
				P.call(0.2, 0.6), P.call(0.14, 0.2)], Color(0.4, 0.58, 0.9))
			draw_circle(P.call(0.5, 0.45), s * 0.12, Color(1.0, 0.85, 0.4))
		"health":
			draw_rect(Rect2(P.call(0.38, 0.12), Vector2(0.24, 0.76) * s), Color(0.95, 0.35, 0.35))
			draw_rect(Rect2(P.call(0.12, 0.38), Vector2(0.76, 0.24) * s), Color(0.95, 0.35, 0.35))
		"school":
			_poly([P.call(0.5, 0.14), P.call(0.94, 0.36), P.call(0.5, 0.58), P.call(0.06, 0.36)], color)
			draw_arc(P.call(0.5, 0.5), s * 0.24, 0.15, PI - 0.15, 16, color, w, true)
			line.call(P.call(0.86, 0.38), P.call(0.86, 0.72))
		"train", "rail":
			# A diesel locomotive from the side, on its rail.
			_poly([P.call(0.08, 0.7), P.call(0.08, 0.46), P.call(0.6, 0.46), P.call(0.6, 0.7)], color)
			_poly([P.call(0.6, 0.7), P.call(0.6, 0.26), P.call(0.86, 0.26), P.call(0.92, 0.4), P.call(0.92, 0.7)], color)
			draw_rect(Rect2(P.call(0.66, 0.32), Vector2(0.16, 0.1) * s), Color(0.12, 0.14, 0.16))
			for x in [0.2, 0.36, 0.64, 0.8]:
				draw_circle(P.call(x, 0.76), s * 0.07, color)
			line.call(P.call(0.02, 0.86), P.call(0.98, 0.86), w)
		"mail":
			# A curbside mailbox on its post, flag up.
			line.call(P.call(0.42, 0.56), P.call(0.42, 0.94), w * 1.4)
			_poly([P.call(0.14, 0.58), P.call(0.14, 0.36), P.call(0.66, 0.36), P.call(0.66, 0.58)], color)
			draw_circle(P.call(0.66, 0.47), s * 0.11, color)
			_poly([P.call(0.66, 0.36), P.call(0.77, 0.36), P.call(0.77, 0.58), P.call(0.66, 0.58)], color)
			line.call(P.call(0.86, 0.5), P.call(0.86, 0.14), w)
			_poly([P.call(0.86, 0.14), P.call(0.97, 0.14), P.call(0.97, 0.26), P.call(0.86, 0.26)], Color(0.95, 0.35, 0.35))
		"bank":
			# A temple-front bank: pediment, four columns, steps.
			_poly([P.call(0.08, 0.32), P.call(0.5, 0.1), P.call(0.92, 0.32)], color)
			draw_rect(Rect2(P.call(0.1, 0.34), Vector2(0.8, 0.07) * s), color)
			for i in 4:
				draw_rect(Rect2(P.call(0.17 + i * 0.19, 0.44), Vector2(0.09, 0.32) * s), color)
			draw_rect(Rect2(P.call(0.08, 0.8), Vector2(0.84, 0.1) * s), color)
		"services":
			draw_rect(Rect2(P.call(0.14, 0.4), Vector2(0.72, 0.5) * s), color, false, w)
			_poly([P.call(0.08, 0.42), P.call(0.5, 0.1), P.call(0.92, 0.42)], Color(color, 0.6))
			draw_rect(Rect2(P.call(0.42, 0.62), Vector2(0.16, 0.28) * s), color)
		"farms", "farmland":
			# Field rows in perspective under a barn roof line.
			for i in 4:
				var y := 0.5 + i * 0.12
				line.call(P.call(0.1 + i * 0.02, y), P.call(0.9 - i * 0.02, y), w * 0.7,
					Color(0.55, 0.78, 0.35) if kind == "farmland" else color)
			_poly([P.call(0.3, 0.42), P.call(0.3, 0.22), P.call(0.5, 0.08), P.call(0.7, 0.22), P.call(0.7, 0.42)],
				Color(0.85, 0.3, 0.25))
		"corn":
			line.call(P.call(0.5, 0.95), P.call(0.5, 0.2), w, Color(0.45, 0.75, 0.35))
			_poly([P.call(0.42, 0.62), P.call(0.5, 0.28), P.call(0.58, 0.62), P.call(0.5, 0.72)], Color(0.98, 0.82, 0.3))
			line.call(P.call(0.5, 0.7), P.call(0.22, 0.42), w, Color(0.45, 0.75, 0.35))
			line.call(P.call(0.5, 0.8), P.call(0.8, 0.5), w, Color(0.45, 0.75, 0.35))
		"soybeans":
			line.call(P.call(0.5, 0.95), P.call(0.5, 0.3), w, Color(0.45, 0.75, 0.35))
			for leaf in [Vector2(0.32, 0.36), Vector2(0.68, 0.42), Vector2(0.36, 0.6), Vector2(0.66, 0.66)]:
				draw_circle(P.call(leaf.x, leaf.y), s * 0.12, Color(0.4, 0.7, 0.3))
			draw_circle(P.call(0.5, 0.22), s * 0.1, Color(0.85, 0.8, 0.45))
		"traffic", "signal":
			# A traffic light: red, yellow and green lamps in a housing.
			draw_rect(Rect2(P.call(0.32, 0.06), Vector2(0.36, 0.88) * s), Color(color, 0.25))
			draw_rect(Rect2(P.call(0.32, 0.06), Vector2(0.36, 0.88) * s), color, false, w * 0.7)
			draw_circle(P.call(0.5, 0.24), s * 0.1, Color(0.95, 0.3, 0.25))
			draw_circle(P.call(0.5, 0.5), s * 0.1, Color(1.0, 0.78, 0.25))
			draw_circle(P.call(0.5, 0.76), s * 0.1, Color(0.35, 0.85, 0.45))
		"stop", "allstop":
			var pts := []
			var c: Vector2 = P.call(0.5, 0.5)
			var r := s * (0.44 if kind == "stop" else 0.3)
			for k in 8:
				var a := TAU * k / 8.0 + PI / 8.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			if kind == "allstop":
				# Four small signs, one per corner.
				for d in [Vector2(-0.2, -0.2), Vector2(0.2, -0.2), Vector2(-0.2, 0.2), Vector2(0.2, 0.2)]:
					var moved := []
					for q in pts:
						moved.append((q - c) * 0.55 + c + d * s)
					_poly(moved, Color(0.85, 0.2, 0.18))
			else:
				_poly(pts, Color(0.85, 0.2, 0.18))
				line.call(P.call(0.3, 0.5), P.call(0.7, 0.5), w, Color.WHITE)
		"nocontrol":
			line.call(P.call(0.5, 0.06), P.call(0.5, 0.94), w * 1.6)
			line.call(P.call(0.06, 0.5), P.call(0.94, 0.5), w * 1.6)
		"auto":
			line.call(P.call(0.5, 0.2), P.call(0.5, 0.94), w * 1.4)
			line.call(P.call(0.2, 0.62), P.call(0.8, 0.62), w * 1.4)
			_poly([P.call(0.5, 0.02), P.call(0.56, 0.14), P.call(0.68, 0.16), P.call(0.58, 0.24),
				P.call(0.5, 0.3), P.call(0.42, 0.24), P.call(0.32, 0.16), P.call(0.44, 0.14)], accent)
		"flow":
			# Roads coloured by how well traffic moves.
			line.call(P.call(0.1, 0.8), P.call(0.4, 0.5), w * 1.8, Color(0.35, 0.85, 0.45))
			line.call(P.call(0.4, 0.5), P.call(0.65, 0.35), w * 1.8, Color(1.0, 0.78, 0.25))
			line.call(P.call(0.65, 0.35), P.call(0.92, 0.15), w * 1.8, Color(0.95, 0.3, 0.25))
		"views":
			# Stacked map layers.
			for i in 3:
				var y := 0.28 + i * 0.2
				_poly([P.call(0.5, y - 0.16), P.call(0.92, y), P.call(0.5, y + 0.16), P.call(0.08, y)],
					Color(color, 0.25 + i * 0.25))
		"fertility":
			_poly([P.call(0.08, 0.92), P.call(0.92, 0.92), P.call(0.92, 0.7), P.call(0.08, 0.7)], Color(0.55, 0.4, 0.25))
			line.call(P.call(0.5, 0.7), P.call(0.5, 0.2), w, Color(0.4, 0.8, 0.3))
			_poly([P.call(0.5, 0.42), P.call(0.22, 0.3), P.call(0.3, 0.18)], Color(0.4, 0.8, 0.3))
			_poly([P.call(0.5, 0.34), P.call(0.8, 0.2), P.call(0.72, 0.1)], Color(0.4, 0.8, 0.3))
		"oil":
			_poly([P.call(0.5, 0.06), P.call(0.78, 0.55), P.call(0.72, 0.82), P.call(0.5, 0.94),
				P.call(0.28, 0.82), P.call(0.22, 0.55)], Color(0.55, 0.5, 0.72))
			draw_arc(P.call(0.5, 0.66), s * 0.28, 0, TAU, 24, color, w * 0.6, true)
		"ore":
			_poly([P.call(0.12, 0.85), P.call(0.25, 0.45), P.call(0.5, 0.25), P.call(0.8, 0.4),
				P.call(0.9, 0.85)], Color(0.55, 0.5, 0.48))
			draw_circle(P.call(0.45, 0.6), s * 0.08, Color(0.9, 0.5, 0.2))
			draw_circle(P.call(0.66, 0.68), s * 0.06, Color(0.9, 0.5, 0.2))
		"forest":
			for t in [[0.32, 0.9], [0.66, 0.7]]:
				var x: float = t[0]
				var sc: float = t[1]
				_poly([P.call(x, 0.92 - 0.82 * sc), P.call(x + 0.22 * sc, 0.8), P.call(x - 0.22 * sc, 0.8)],
					Color(0.25, 0.6, 0.3))
				line.call(P.call(x, 0.8), P.call(x, 0.94), w * 0.8, Color(0.45, 0.32, 0.2))
		"reserve":
			# A dashed outline with corner nodes.
			var pts := [P.call(0.12, 0.2), P.call(0.86, 0.12), P.call(0.9, 0.84), P.call(0.16, 0.9)]
			for i in 4:
				var a2: Vector2 = pts[i]
				var b2: Vector2 = pts[(i + 1) % 4]
				for k in 3:
					line.call(a2.lerp(b2, k / 3.0 + 0.05), a2.lerp(b2, k / 3.0 + 0.25), w * 0.8)
				draw_circle(a2, s * 0.07, accent)
		"park", "parks":
			# A round shade tree over a bench.
			draw_circle(P.call(0.5, 0.36), s * 0.27, Color(0.35, 0.68, 0.35))
			line.call(P.call(0.5, 0.6), P.call(0.5, 0.9), w * 1.2, Color(0.55, 0.4, 0.28))
			line.call(P.call(0.14, 0.82), P.call(0.4, 0.82), w)
			line.call(P.call(0.6, 0.82), P.call(0.86, 0.82), w)
		"courthouse":
			# Columns under a pediment, a clock tower above.
			_poly([P.call(0.12, 0.42), P.call(0.5, 0.26), P.call(0.88, 0.42)], Color(color, 0.7))
			draw_rect(Rect2(P.call(0.4, 0.06), Vector2(0.2, 0.22) * s), color, false, w * 0.7)
			draw_circle(P.call(0.5, 0.16), s * 0.05, color)
			for x in [0.2, 0.4, 0.6, 0.8]:
				line.call(P.call(x, 0.46), P.call(x, 0.84), w)
			line.call(P.call(0.1, 0.9), P.call(0.9, 0.9), w * 1.2)
		"water_landmark":
			draw_circle(P.call(0.5, 0.3), s * 0.26, Color(0.55, 0.78, 0.95))
			draw_rect(Rect2(P.call(0.3, 0.26), Vector2(0.4, 0.08) * s), Color(0.12, 0.23, 0.43))
			line.call(P.call(0.32, 0.52), P.call(0.22, 0.94))
			line.call(P.call(0.68, 0.52), P.call(0.78, 0.94))
			line.call(P.call(0.27, 0.74), P.call(0.73, 0.74), w * 0.7)
		"elevator":
			# Concrete silos and a tall headhouse.
			for x in [0.14, 0.34, 0.54]:
				draw_rect(Rect2(P.call(x, 0.34), Vector2(0.18, 0.58) * s), Color(0.82, 0.8, 0.74))
			draw_rect(Rect2(P.call(0.72, 0.08), Vector2(0.18, 0.84) * s), color)
		"football":
			# A goalpost over field lines.
			for i in 3:
				line.call(P.call(0.12, 0.66 + i * 0.12), P.call(0.88, 0.66 + i * 0.12), w * 0.6, Color(0.55, 0.8, 0.45))
			line.call(P.call(0.5, 0.92), P.call(0.5, 0.5), w, Color(1.0, 0.82, 0.3))
			line.call(P.call(0.26, 0.5), P.call(0.74, 0.5), w, Color(1.0, 0.82, 0.3))
			line.call(P.call(0.26, 0.5), P.call(0.26, 0.1), w, Color(1.0, 0.82, 0.3))
			line.call(P.call(0.74, 0.5), P.call(0.74, 0.1), w, Color(1.0, 0.82, 0.3))
		"fairgrounds":
			# A Ferris wheel on its legs.
			draw_arc(P.call(0.5, 0.42), s * 0.3, 0, TAU, 24, color, w, true)
			for k in 4:
				var a := PI * k / 4.0
				var d := Vector2(cos(a), sin(a)) * s * 0.3
				line.call(P.call(0.5, 0.42) - d, P.call(0.5, 0.42) + d, w * 0.6)
			line.call(P.call(0.5, 0.42), P.call(0.3, 0.92), w)
			line.call(P.call(0.5, 0.42), P.call(0.7, 0.92), w)
		"smoke", "pollution":
			# A stack with a drifting plume.
			_poly([P.call(0.18, 0.92), P.call(0.18, 0.5), P.call(0.32, 0.5), P.call(0.32, 0.92)], color)
			for c in [[0.36, 0.38, 0.12], [0.55, 0.26, 0.15], [0.76, 0.18, 0.13]]:
				draw_circle(P.call(c[0], c[1]), s * c[2], Color(color, 0.55))
		"noise":
			# A speaker with sound rings.
			_poly([P.call(0.1, 0.38), P.call(0.26, 0.38), P.call(0.46, 0.18), P.call(0.46, 0.82),
				P.call(0.26, 0.62), P.call(0.1, 0.62)], color)
			for r in [0.18, 0.32]:
				draw_arc(P.call(0.48, 0.5), s * r, -0.9, 0.9, 12, color, w * 0.8, true)
		"ground":
			# A drop seeping into the ground.
			_poly([P.call(0.08, 0.92), P.call(0.92, 0.92), P.call(0.92, 0.68), P.call(0.08, 0.68)], Color(0.55, 0.42, 0.28))
			_poly([P.call(0.5, 0.08), P.call(0.68, 0.38), P.call(0.6, 0.52), P.call(0.4, 0.52), P.call(0.32, 0.38)], color)
			draw_circle(P.call(0.5, 0.42), s * 0.12, color)
			for x in [0.3, 0.55, 0.75]:
				draw_circle(P.call(x, 0.8), s * 0.04, Color(0.25, 0.2, 0.1))
		"trailhead":
			# A bicycle: two wheels, a frame and handlebars.
			draw_arc(P.call(0.26, 0.66), s * 0.17, 0, TAU, 18, color, w, true)
			draw_arc(P.call(0.74, 0.66), s * 0.17, 0, TAU, 18, color, w, true)
			draw_polyline(PackedVector2Array([P.call(0.26, 0.66), P.call(0.46, 0.66), P.call(0.66, 0.4),
				P.call(0.38, 0.4), P.call(0.26, 0.66)]), color, w * 0.8, true)
			line.call(P.call(0.66, 0.4), P.call(0.74, 0.66), w * 0.8)
			line.call(P.call(0.62, 0.3), P.call(0.72, 0.3), w * 0.8)
			line.call(P.call(0.38, 0.4), P.call(0.35, 0.32), w * 0.8)
		"town":
			# A state historical marker: a sign with a crest on top, on a post.
			line.call(P.call(0.5, 0.62), P.call(0.5, 0.94), w * 1.2)
			_poly([P.call(0.16, 0.24), P.call(0.36, 0.24), P.call(0.5, 0.08), P.call(0.64, 0.24),
				P.call(0.84, 0.24), P.call(0.84, 0.64), P.call(0.16, 0.64)], color)
			for y in [0.36, 0.46, 0.54]:
				line.call(P.call(0.26, y), P.call(0.74, y), w * 0.5, Color(accent, 0.9))
		"advice":
			# A speech bubble with three dots.
			var bubble := PackedVector2Array([P.call(0.12, 0.18), P.call(0.88, 0.18), P.call(0.88, 0.68),
				P.call(0.46, 0.68), P.call(0.26, 0.86), P.call(0.3, 0.68), P.call(0.12, 0.68), P.call(0.12, 0.18)])
			draw_polyline(bubble, color, w, true)
			for x in [0.32, 0.5, 0.68]:
				draw_circle(P.call(x, 0.43), s * 0.055, color)
		"warning":
			# A triangle with an exclamation mark.
			draw_polyline(PackedVector2Array([P.call(0.5, 0.1), P.call(0.92, 0.86), P.call(0.08, 0.86),
				P.call(0.5, 0.1)]), color, w, true)
			line.call(P.call(0.5, 0.38), P.call(0.5, 0.6), w * 1.2)
			draw_circle(P.call(0.5, 0.72), s * 0.05, color)
		"daynight":
			# A sun and a moon.
			draw_arc(P.call(0.42, 0.55), s * 0.2, 0, TAU, 24, color, w, true)
			for k in 8:
				var a := TAU * k / 8.0
				var d := Vector2(cos(a), sin(a))
				line.call(P.call(0.42, 0.55) + d * s * 0.28, P.call(0.42, 0.55) + d * s * 0.36, w * 0.8)
			draw_circle(P.call(0.72, 0.3), s * 0.2, accent)
			draw_arc(P.call(0.72, 0.3), s * 0.2, PI * 0.35, PI * 1.6, 16, color, w, true)
		"weather":
			# A cloud with rain falling from it.
			draw_arc(P.call(0.38, 0.42), s * 0.17, PI * 0.55, PI * 1.6, 16, color, w, true)
			draw_arc(P.call(0.58, 0.36), s * 0.21, PI * 1.05, PI * 2.05, 16, color, w, true)
			draw_arc(P.call(0.74, 0.47), s * 0.13, PI * 1.45, PI * 2.45, 12, color, w, true)
			line.call(P.call(0.24, 0.57), P.call(0.8, 0.57), w)
			for k in 3:
				var x := 0.34 + 0.16 * k
				line.call(P.call(x, 0.68), P.call(x - 0.06, 0.86), w * 0.9)
		"seasons":
			# A maple leaf outline, with a stem.
			var leaf := PackedVector2Array([P.call(0.5, 0.1), P.call(0.6, 0.32), P.call(0.86, 0.26),
				P.call(0.74, 0.5), P.call(0.9, 0.62), P.call(0.6, 0.64), P.call(0.5, 0.8),
				P.call(0.4, 0.64), P.call(0.1, 0.62), P.call(0.26, 0.5), P.call(0.14, 0.26),
				P.call(0.4, 0.32), P.call(0.5, 0.1)])
			draw_polyline(leaf, color, w, true)
			line.call(P.call(0.5, 0.4), P.call(0.5, 0.94))
		"help":
			draw_arc(P.call(0.5, 0.5), s * 0.4, 0, TAU, 32, color, w, true)
			draw_arc(P.call(0.5, 0.4), s * 0.13, PI * 1.1, PI * 2.4, 16, color, w, true)
			line.call(P.call(0.5, 0.53), P.call(0.5, 0.62))
			draw_circle(P.call(0.5, 0.74), s * 0.04, color)


## A road seen from above, wide or narrow to match its type.
func _road_section(P: Callable, w: float) -> void:
	var half: float = {"street": 0.2, "avenue": 0.28, "boulevard": 0.4, "highway": 0.3, "ramp": 0.14}[kind]
	var l: float = 0.5 - half
	var r: float = 0.5 + half
	_poly([P.call(l, 0.05), P.call(r, 0.05), P.call(r, 0.95), P.call(l, 0.95)], Color(0.32, 0.34, 0.37))
	draw_line(P.call(l, 0.05), P.call(l, 0.95), color, w * 0.6, true)
	draw_line(P.call(r, 0.05), P.call(r, 0.95), color, w * 0.6, true)
	match kind:
		"street":
			_dash(P, 0.5, Color(0.95, 0.8, 0.3), w * 0.5)
		"avenue":
			draw_line(P.call(0.48, 0.05), P.call(0.48, 0.95), Color(0.95, 0.8, 0.3), w * 0.4)
			draw_line(P.call(0.52, 0.05), P.call(0.52, 0.95), Color(0.95, 0.8, 0.3), w * 0.4)
			_dash(P, 0.36, color, w * 0.45)
			_dash(P, 0.64, color, w * 0.45)
		"boulevard":
			_poly([P.call(0.45, 0.05), P.call(0.55, 0.05), P.call(0.55, 0.95), P.call(0.45, 0.95)], Color(0.35, 0.6, 0.3))
			for x in [0.2, 0.3, 0.7, 0.8]:
				_dash(P, x, color, w * 0.4)
		"highway":
			for x in [0.4, 0.6]:
				_dash(P, x, color, w * 0.45)
			draw_polyline(PackedVector2Array([P.call(0.42, 0.42), P.call(0.5, 0.28), P.call(0.58, 0.42)]),
				color, w * 0.7, true)
		"ramp":
			draw_polyline(PackedVector2Array([P.call(0.42, 0.42), P.call(0.5, 0.28), P.call(0.58, 0.42)]),
				color, w * 0.6, true)


## Any road type seen from above, drawn from its spec: its width, surface,
## median or turn lane, lane lines, bike lanes, parking and trees.
func _road_type(P: Callable, w: float, type: int) -> void:
	var spec: Dictionary = RoadStyle.TYPES[type]
	var yellow := Color(0.95, 0.8, 0.3)
	var half := clampf(spec.width / 44.0, 0.12, 0.44)
	var k: float = half / (spec.width * 0.5)  # icon units per metre
	var l: float = 0.5 - half
	var r: float = 0.5 + half
	var surface: Dictionary = {"gravel": Color(0.62, 0.56, 0.45), "concrete": Color(0.58, 0.58, 0.56),
		"dirt": Color(0.52, 0.40, 0.28), "chip seal": Color(0.45, 0.43, 0.40), "brick": Color(0.58, 0.30, 0.22)}
	var rural: bool = spec.get("rural", false)
	if rural:
		_poly([P.call(0.0, 0.05), P.call(1.0, 0.05), P.call(1.0, 0.95), P.call(0.0, 0.95)], Color(0.35, 0.55, 0.3, 0.5))
	_poly([P.call(l, 0.05), P.call(r, 0.05), P.call(r, 0.95), P.call(l, 0.95)],
		surface.get(spec.get("surface", ""), Color(0.32, 0.34, 0.37)))
	if not rural:
		draw_line(P.call(l, 0.05), P.call(l, 0.95), color, w * 0.6, true)
		draw_line(P.call(r, 0.05), P.call(r, 0.95), color, w * 0.6, true)
	if spec.get("surface", "asphalt") != "asphalt":
		return
	var hm: float = spec.median * 0.5 * k
	var lane: float = 3.6 * k
	if spec.median > 0.0 and not spec.get("turn", false):
		var g: float = hm - (1.2 * k if rural else 0.0)
		_poly([P.call(0.5 - g, 0.05), P.call(0.5 + g, 0.05), P.call(0.5 + g, 0.95), P.call(0.5 - g, 0.95)], Color(0.35, 0.6, 0.3))
		if spec.get("trees", false):
			for y in [0.22, 0.5, 0.78]:
				draw_circle(P.call(0.5, y), maxf(g, 0.05) * s_of(P) * 0.9, Color(0.2, 0.42, 0.18))
	elif spec.get("turn", false):
		for x in [0.5 - hm, 0.5 + hm]:
			draw_line(P.call(x, 0.05), P.call(x, 0.95), yellow, w * 0.4)
	elif spec.oneway:
		pass
	elif spec.lanes > 2 or spec.get("bike", false) or spec.get("angle", false):
		draw_line(P.call(0.485, 0.05), P.call(0.485, 0.95), yellow, w * 0.35)
		draw_line(P.call(0.515, 0.05), P.call(0.515, 0.95), yellow, w * 0.35)
	elif rural:
		_dash(P, 0.5, yellow, w * 0.45)
	var edge: float
	if spec.oneway:
		edge = lane * spec.lanes * 0.5
		if RoadStyle.is_freeway(type):
			edge = half - 1.2 * k
			for i in range(1, spec.lanes):
				_dash(P, 0.5 - half + 1.2 * k + lane * i, color, w * 0.4)
		else:
			for i in range(1, spec.lanes):
				_dash(P, 0.5 - edge + lane * i, color, w * 0.4)
		draw_polyline(PackedVector2Array([P.call(0.42, 0.42), P.call(0.5, 0.28), P.call(0.58, 0.42)]), color, w * 0.6, true)
	else:
		var inner: float = hm + (RoadStyle.CURB_WIDTH * k if RoadStyle.raised_median(type) else 0.0)
		edge = inner + lane * (spec.lanes / 2)
		for i in range(1, spec.lanes / 2):
			_dash(P, 0.5 - inner - lane * i, color, w * 0.4)
			_dash(P, 0.5 + inner + lane * i, color, w * 0.4)
	if spec.get("bus", false):
		for x0 in [0.5 - edge, 0.5 + edge - lane]:
			_poly([P.call(x0, 0.05), P.call(x0 + lane, 0.05), P.call(x0 + lane, 0.95), P.call(x0, 0.95)], Color(0.75, 0.22, 0.18))
	if spec.get("bike", false) or (rural and not RoadStyle.is_freeway(type)):
		for x in [0.5 - edge, 0.5 + edge]:
			draw_line(P.call(x, 0.05), P.call(x, 0.95), color, w * 0.35)
	if spec.get("bike", false):
		for x in [0.5 - edge - 0.75 * 1.5 * k, 0.5 + edge + 0.75 * 1.5 * k]:
			draw_circle(P.call(x, 0.5), s_of(P) * 0.025, color)
	if spec.get("angle", false):
		for x0 in [l, r]:
			var dx: float = (0.5 - edge) - l if x0 == l else (0.5 + edge) - r
			for y in [0.15, 0.35, 0.55, 0.75]:
				draw_line(P.call(x0, y), P.call(x0 + dx, y + 0.12), color, w * 0.3, true)
	elif spec.get("parking", 0) > 0:
		for x0 in [l + 0.02, r - 0.02 - 2.0 * k]:
			for y in [0.12, 0.42, 0.72]:
				_poly([P.call(x0, y), P.call(x0 + 2.0 * k, y), P.call(x0 + 2.0 * k, y + 0.18), P.call(x0, y + 0.18)],
					Color(color, 0.55))


## The icon's side in pixels, from its scaling callable.
func s_of(P: Callable) -> float:
	return (P.call(1.0, 0.0) - P.call(0.0, 0.0)).x


func _dash(P: Callable, x: float, col: Color, width: float) -> void:
	for i in 4:
		var y0 := 0.1 + i * 0.23
		draw_line(P.call(x, y0), P.call(x, y0 + 0.12), col, width, true)


static func _texture(file: String) -> Texture2D:
	if not _textures.has(file):
		_textures[file] = load("res://assets/brand/icons/%s.svg" % file)
	return _textures[file]


func _poly(points: Array, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), col)
