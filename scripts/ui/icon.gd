class_name Icon
extends Control
## Small line icons drawn in code, so they stay sharp at any size and need no
## image files. Set `kind` to one of the names handled in _draw().

@export var kind := "road":
	set(v):
		kind = v
		queue_redraw()
var color := Color(0.93, 0.95, 0.97):
	set(v):
		color = v
		queue_redraw()
## Optional second colour (zone tints and the like).
var accent := Color(0.45, 0.72, 0.95):
	set(v):
		accent = v
		queue_redraw()


func _init(k := "road", size_px := 40.0) -> void:
	kind = k
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var w := maxf(1.5, s * 0.07)
	# Everything below is drawn on a 0..1 square, scaled by P().
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var line := func(a: Vector2, b: Vector2, width := w, col := color): draw_line(a, b, col, width, true)
	match kind:
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
		"dezone":
			draw_rect(Rect2(P.call(0.12, 0.12), Vector2(0.76, 0.76) * s), Color(color, 0.5), false, w * 0.6)
			line.call(P.call(0.25, 0.25), P.call(0.75, 0.75), w * 1.3, Color(1, 0.45, 0.4))
			line.call(P.call(0.75, 0.25), P.call(0.25, 0.75), w * 1.3, Color(1, 0.45, 0.4))
		"street", "avenue", "boulevard", "highway", "ramp":
			_road_section(P, w)
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


func _dash(P: Callable, x: float, col: Color, width: float) -> void:
	for i in 4:
		var y0 := 0.1 + i * 0.23
		draw_line(P.call(x, y0), P.call(x, y0 + 0.12), col, width, true)


func _poly(points: Array, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), col)
