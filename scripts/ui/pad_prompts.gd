class_name PadPrompts
extends Control
## Button prompts for a game controller, docked bottom right just above the
## tool bar, like the console editions of Cities: Skylines. Each prompt is the
## button as it looks on the pad in hand (Xbox letters, PlayStation shapes,
## Nintendo letters) and a word or two. They follow the moment: picking a
## tool, drawing, or the title screen.

enum Style { XBOX, PLAYSTATION, NINTENDO }

## Real controller colours (Xbox face buttons, PlayStation shapes).
const XBOX_COLORS := {"a": Color("#5dc21e"), "b": Color("#e8413c"), "x": Color("#3d8fe0"), "y": Color("#f2c032")}
const PS_COLORS := {"a": Color("#7fb2ea"), "b": Color("#f0656a"), "x": Color("#e58ac5"), "y": Color("#4fc9a5")}
## Nintendo prints the letters the other way round: the bottom button is B.
const NINTENDO_LETTERS := {"a": "B", "b": "A", "x": "Y", "y": "X"}
const SHOULDERS := {
	Style.XBOX: {"lb": "LB", "rb": "RB", "lt": "LT", "rt": "RT", "menu": "Menu", "view": "View"},
	Style.PLAYSTATION: {"lb": "L1", "rb": "R1", "lt": "L2", "rt": "R2", "menu": "Options", "view": "Create"},
	Style.NINTENDO: {"lb": "L", "rb": "R", "lt": "ZL", "rt": "ZR", "menu": "+", "view": "−"},
}
const H := 24.0
const GAP := 14.0

var _items: Array = []  # [[button, ...], label]
var _style := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiStyle.theme()


## Which prompts to show right now.
static func prompts_for(hud: Node) -> Array:
	if hud == null:
		return [[["a"], "Select"], [["b"], "Back"]]
	if hud.shape_open():
		return [[["a"], "Add point"], [["rs"], "Click: finish"], [["x"], "Cancel"], [["b"], "Back"]]
	if hud.anything_open():
		return [[["a"], "Use"], [["x"], "Cancel"], [["lb", "rb"], "Size"], [["dpad"], "Height · speed"],
			[["b"], "Back"], [["y"], "Tools"]]
	return [[["y"], "Tools"], [["a"], "Select"], [["rs"], "Turn"], [["lt", "rt"], "Zoom"], [["menu"], "Menu"]]


func refresh(hud: Node, style: int) -> void:
	var items := prompts_for(hud)
	var bottom := 8.0
	if hud != null:
		bottom += hud.pad_bottom_height()
	var vp := get_viewport_rect().size
	if items != _items or style != _style or position.y != vp.y - bottom - H:
		_items = items
		_style = style
		var w := _width()
		position = Vector2(vp.x - w - 12.0, vp.y - bottom - H)
		size = Vector2(w, H)
		queue_redraw()


func _width() -> float:
	var font := get_theme_default_font()
	var w := 16.0
	for item in _items:
		for b in item[0]:
			w += _glyph_width(b) + 3.0
		w += font.get_string_size(item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + GAP + 4.0
	return w


func _glyph_width(b: String) -> float:
	if b in ["a", "b", "x", "y", "dpad", "ls", "rs"]:
		return H
	var font := get_theme_default_font()
	return maxf(font.get_string_size(SHOULDERS[_style][b], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0, 28.0)


func _draw() -> void:
	draw_style_box(UiStyle.panel(int(H / 2)), Rect2(Vector2.ZERO, size))
	var font := get_theme_default_font()
	var x := 10.0
	for item in _items:
		for b in item[0]:
			var w := _glyph_width(b)
			glyph(self, Rect2(x, 2, w, H - 4), b, _style)
			x += w + 3.0
		x += 2.0
		draw_string(font, Vector2(x, H / 2 + 5), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Brand.INK)
		x += font.get_string_size(item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + GAP


## Draws one pad button as it looks on that controller.
static func glyph(ci: CanvasItem, r: Rect2, b: String, style: int) -> void:
	var font := ThemeDB.fallback_font
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) * 0.5
	var dark := Color("#15191b")
	if b in ["a", "b", "x", "y"]:
		ci.draw_circle(c, rad, dark)
		ci.draw_circle(c, rad, Color(1, 1, 1, 0.25), false, 1.0, true)
		if style == Style.PLAYSTATION:
			var col: Color = PS_COLORS[b]
			var s := rad * 0.45
			match b:
				"a":
					ci.draw_line(c + Vector2(-s, -s), c + Vector2(s, s), col, 2.0, true)
					ci.draw_line(c + Vector2(-s, s), c + Vector2(s, -s), col, 2.0, true)
				"b":
					ci.draw_circle(c, s, col, false, 2.0, true)
				"x":
					ci.draw_rect(Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), col, false, 2.0)
				"y":
					ci.draw_polyline(PackedVector2Array([c + Vector2(0, -s * 1.1), c + Vector2(s, s * 0.75),
						c + Vector2(-s, s * 0.75), c + Vector2(0, -s * 1.1)]), col, 2.0, true)
			return
		var letter: String = NINTENDO_LETTERS[b] if style == Style.NINTENDO else b.to_upper()
		var tint: Color = Brand.INK if style == Style.NINTENDO else XBOX_COLORS[b]
		_centered(ci, font, c, letter, 13, tint)
	elif b == "dpad":
		var s := rad * 0.3
		var l := rad * 0.9
		ci.draw_rect(Rect2(c - Vector2(s, l), Vector2(s * 2, l * 2)), Brand.INK)
		ci.draw_rect(Rect2(c - Vector2(l, s), Vector2(l * 2, s * 2)), Brand.INK)
	elif b in ["ls", "rs"]:
		ci.draw_circle(c, rad, dark)
		ci.draw_circle(c, rad * 0.62, Color(1, 1, 1, 0.3), false, 1.5, true)
		_centered(ci, font, c, "L" if b == "ls" else "R", 11, Brand.INK)
	else:
		var box := StyleBoxFlat.new()
		box.bg_color = dark
		box.set_corner_radius_all(int(r.size.y * 0.35))
		box.border_color = Color(1, 1, 1, 0.25)
		box.set_border_width_all(1)
		ci.draw_style_box(box, r)
		_centered(ci, font, c, SHOULDERS[style][b], 11, Brand.INK)


static func _centered(ci: CanvasItem, font: Font, c: Vector2, text: String, px: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	ci.draw_string(font, Vector2(c.x - w / 2.0, c.y + px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
