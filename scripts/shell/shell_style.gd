class_name ShellStyle
extends RefCounted
## The Neighbors look for the menus and chat (title screen, pause menu,
## region chat), from the brand kit: deep ink panels docked to the edge,
## cream Figtree text, Outfit titles, one coral primary action.


static func theme() -> Theme:
	var t := UiStyle.theme()
	t.default_font = Brand.ui(500)
	t.default_font_size = 15
	t.set_color("font_color", "Label", Brand.INK)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("normal", "Button", _box(Brand.SURFACE_RAISED, 6))
	t.set_stylebox("hover", "Button", _box(Brand.SURFACE_RAISED.lightened(0.12), 6))
	t.set_stylebox("pressed", "Button", _box(Brand.BRAND_CORAL, 6))
	t.set_stylebox("hover_pressed", "Button", _box(Brand.BRAND_CORAL, 6))
	t.set_stylebox("focus", "Button", _focus())
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(state, "Button", Brand.INK)
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(state, "Button", Brand.ON_CORAL)
	var field := _box(Brand.SURFACE_SUNKEN, 6, Brand.LINE_STRONG)
	field.content_margin_left = 12
	t.set_stylebox("normal", "LineEdit", field)
	var focused := _box(Brand.SURFACE_SUNKEN, 6, Brand.FOCUS)
	focused.content_margin_left = 12
	t.set_stylebox("focus", "LineEdit", focused)
	t.set_color("font_color", "LineEdit", Brand.INK)
	t.set_color("font_placeholder_color", "LineEdit", Brand.INK_FAINT)
	t.set_color("caret_color", "LineEdit", Brand.BRAND_CORAL)
	t.set_color("default_color", "RichTextLabel", Brand.INK)
	return t


## A panel docked flush to the left edge: square on the screen side, only
## the inner corners rounded, a hairline on the inner edge.
static func panel(inner_radius := 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Brand.SURFACE_PANEL
	b.border_color = Brand.LINE
	b.border_width_right = 1
	b.corner_radius_top_right = inner_radius
	b.corner_radius_bottom_right = inner_radius
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.content_margin_top = 10
	b.content_margin_bottom = 10
	return b


## The one primary action on a screen is coral.
static func primary(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _box(Brand.BRAND_CORAL, 6))
	b.add_theme_stylebox_override("hover", _box(Brand.BRAND_CORAL.lightened(0.1), 6))
	for state in ["font_color", "font_hover_color"]:
		b.add_theme_color_override(state, Brand.ON_CORAL)
	b.set_meta("primary", true)


static func text(s: String, size := 15, weight := 500, color := Brand.INK) -> Label:
	return Brand.label(s, "ui", size, weight, color)


static func title(s: String, size := 24, weight := 600) -> Label:
	return Brand.label(s, "display", size, weight)


static func _box(bg: Color, radius: int, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(radius)
	b.content_margin_left = 8
	b.content_margin_right = 8
	b.content_margin_top = 4
	b.content_margin_bottom = 4
	if border.a > 0.0:
		b.border_color = border
		b.set_border_width_all(1)
	return b


static func _focus() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.draw_center = false
	b.border_color = Brand.FOCUS
	b.set_border_width_all(2)
	b.set_corner_radius_all(8)
	b.set_expand_margin_all(2)
	return b
