class_name UiStyle
extends RefCounted
## The game's look, from the Neighbors brand kit (see Brand): deep teal glass
## panels docked to the screen edges, Figtree for the interface, and coral
## for the one thing that means "you" (the active tool, your selection).
## One mark, one meaning (the critic, 2026-10-26: one coral ring meant six
## things, so "selected", "switched on" and "watch out" looked the same):
## - the build tool in hand: a coral ring (theme type "ToolCard");
## - a chosen tab or option (chart range, speed, a menu): a soft filled
##   pill with mint words (Revolut's and Trello's segmented tabs);
## - on/off settings: switches (Display, Advice).

const ACCENT := Brand.BRAND_CORAL
const TEXT := Brand.INK
const MUTED := Brand.INK_MUTED
const PANEL := Brand.SURFACE_PANEL
const LINE := Brand.LINE

## The smallest text drawn: caps headings, and everything else.
const MIN_HEADING := 11
const MIN_TEXT := 12
## Brand radii: sm for buttons and tool cards, md for floating cards.
const RADIUS_SM := 6
const RADIUS_MD := 10


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = Brand.ui(500)
	t.default_font_size = 13
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("normal", "Button", _box(Color(Brand.SURFACE_RAISED, 0.55), RADIUS_SM))
	t.set_stylebox("hover", "Button", _box(Brand.SURFACE_RAISED, RADIUS_SM))
	# Chosen: a soft filled pill with mint words, no ring.
	t.set_stylebox("pressed", "Button", _box(Brand.SURFACE_RAISED.lightened(0.12), RADIUS_SM))
	t.set_stylebox("hover_pressed", "Button", _box(Brand.SURFACE_RAISED.lightened(0.18), RADIUS_SM))
	# The tool in hand: a coral ring on a raised card (a coral wash over teal
	# turns brown). Only tool cards use it.
	t.set_type_variation("ToolCard", "Button")
	t.set_stylebox("pressed", "ToolCard", _box(Brand.SURFACE_RAISED, RADIUS_SM, ACCENT))
	t.set_stylebox("hover_pressed", "ToolCard", _box(Brand.SURFACE_RAISED.lightened(0.08), RADIUS_SM, ACCENT))
	var focus := _box(Color.TRANSPARENT, RADIUS_SM, Brand.FOCUS)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("disabled", "Button", _box(Color(Brand.SURFACE_RAISED, 0.25), RADIUS_SM))
	t.set_font("font", "Button", Brand.ui(600))
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(state, "Button", TEXT)
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(state, "Button", Brand.BRAND_MINT)
		t.set_color(state, "ToolCard", TEXT)
	t.set_color("font_disabled_color", "Button", Brand.INK_FAINT)
	t.set_stylebox("background", "ProgressBar", _box(Brand.SURFACE_SUNKEN, 4))
	t.set_stylebox("fill", "ProgressBar", _box(Brand.BRAND_TEAL, 4))
	t.set_stylebox("normal", "LineEdit", _box(Brand.SURFACE_SUNKEN, RADIUS_SM, Brand.LINE_STRONG, 1))
	t.set_stylebox("focus", "LineEdit", _box(Color.TRANSPARENT, RADIUS_SM, Brand.FOCUS))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Brand.INK_FAINT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	# The broad Funding and Growth sliders: a thin sunken track filled teal
	# up to a round grabber.
	var track := _box(Brand.SURFACE_SUNKEN, 3)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	var fill := _box(Brand.BRAND_TEAL, 3)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _dot(12, Brand.INK))
	t.set_icon("grabber_highlight", "HSlider", _dot(12, Brand.BRAND_MINT))
	t.set_icon("tick", "HSlider", _dot(4, Brand.INK_FAINT))
	t.set_stylebox("panel", "TooltipPanel", _box(Brand.SURFACE_RAISED, RADIUS_SM, LINE, 1))
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t


## Tooltips wrap at TOOLTIP_WIDTH instead of running across the screen (the
## critic, 2026-10-26: long card tooltips had no limit). Godot has no
## setting for it, so this catches each tooltip's label as it appears.
const TOOLTIP_WIDTH := 360.0


static func wrap_tooltips(tree: SceneTree) -> void:
	if not tree.node_added.is_connected(_wrap_tooltip):
		tree.node_added.connect(_wrap_tooltip)


static func _wrap_tooltip(n: Node) -> void:
	if not n is Label or (n as Label).theme_type_variation != &"TooltipLabel":
		return
	var l := n as Label
	var font := l.get_theme_font("font")
	var px := l.get_theme_font_size("font_size")
	var widest := 0.0
	for line in l.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	if widest > TOOLTIP_WIDTH:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = TOOLTIP_WIDTH


static func panel(radius := RADIUS_MD) -> StyleBoxFlat:
	var b := _box(PANEL, radius, LINE, 1)
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
	b.bg_color = Color(Brand.SURFACE_RAISED, PANEL.a) if raised else PANEL
	b.border_color = LINE
	if top:
		b.border_width_bottom = 1
	else:
		b.border_width_top = 1
	b.content_margin_left = 10
	b.content_margin_right = 10
	b.content_margin_top = 4
	b.content_margin_bottom = 4
	return b


## A label in the interface face. Bold weights for numbers and headings,
## e.g. label("$12,400", 17, TEXT, 700). Small caps-style headings (all caps,
## 10-11 px) get Figtree 600 automatically, as the kit's label style.
static func label(text: String, size := 15, color := TEXT, weight := 0) -> Label:
	var l := Label.new()
	l.text = text
	var heading := size <= 11 and text == text.to_upper() and text != ""
	# Text size floors (the critic, 2026-10-26: 10 px headings and chart
	# labels were too small): 11 px for caps headings, 12 px for words.
	size = maxi(size, MIN_HEADING if heading else MIN_TEXT)
	if weight == 0:
		weight = 600 if heading else 500
	l.add_theme_font_override("font", Brand.ui(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A title in the display face (Outfit), for panel headers and menus.
static func title(text: String, size := 16, color := TEXT) -> Label:
	var l := label(text, size, color, 600)
	l.add_theme_font_override("font", Brand.display(600))
	return l


## A small filled circle, for slider grabbers and ticks.
static func _dot(px: int, color: Color) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var r := px / 2.0
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(color, clampf(r - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func _box(bg: Color, radius: int, border := Color.TRANSPARENT, border_px := 2) -> StyleBoxFlat:
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
		b.set_border_width_all(border_px)
	return b
