class_name UiStyle
extends RefCounted
## The game's look: dark glass panels, rounded tool cards and one blue
## accent, in the spirit of Cities: Skylines 2.

const ACCENT := Color(0.33, 0.66, 0.93)
const TEXT := Color(0.93, 0.95, 0.97)
const MUTED := Color(0.62, 0.67, 0.73)
const PANEL := Color(0.075, 0.09, 0.115, 0.9)


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 13
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("normal", "Button", _box(Color(1, 1, 1, 0.045), 10))
	t.set_stylebox("hover", "Button", _box(Color(1, 1, 1, 0.11), 10))
	t.set_stylebox("pressed", "Button", _box(Color(ACCENT, 0.35), 10, ACCENT))
	t.set_stylebox("hover_pressed", "Button", _box(Color(ACCENT, 0.45), 10, ACCENT))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", _box(Color(1, 1, 1, 0.02), 10))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(state, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.5))
	t.set_stylebox("background", "ProgressBar", _box(Color(1, 1, 1, 0.08), 4))
	return t


static func panel(radius := 14) -> StyleBoxFlat:
	var b := _box(PANEL, radius, Color(1, 1, 1, 0.07))
	b.border_width_left = 1
	b.border_width_top = 1
	b.border_width_right = 1
	b.border_width_bottom = 1
	b.shadow_color = Color(0, 0, 0, 0.35)
	b.shadow_size = 10
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	return b


## A bar docked flush to the top or bottom edge: square, with a hairline on
## its inner edge. `raised` is the lighter tool tray that sits on the bottom bar.
static func dock(top: bool, raised := false) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = PANEL.lightened(0.06) if raised else PANEL
	b.border_color = Color(1, 1, 1, 0.08)
	if top:
		b.border_width_bottom = 1
	else:
		b.border_width_top = 1
	b.content_margin_left = 10
	b.content_margin_right = 10
	b.content_margin_top = 4
	b.content_margin_bottom = 4
	return b


static func label(text: String, size := 15, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _box(bg: Color, radius: int, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(radius)
	b.content_margin_left = 6
	b.content_margin_right = 6
	b.content_margin_top = 4
	b.content_margin_bottom = 4
	b.anti_aliasing = true
	if border.a > 0.0:
		b.border_color = border
		b.set_border_width_all(2)
	return b
