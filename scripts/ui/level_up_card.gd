class_name LevelUpCard
extends Control
## The celebration when the town reaches a step of its charter ladder
## (Charter.STEPS): the new title, how the town got there, what it opens, and
## how far it is to the next step. One card in the middle of the screen over a
## dimmed town, with a burst of confetti in the brand colors; closed with a
## click, Enter or Esc. Steps reached together show one after another.

const WIDTH := 420
const CONFETTI := 140
const COLORS := [Brand.BRAND_CORAL, Brand.BRAND_TEAL, Brand.BRAND_MINT, Brand.BRAND_CREAM, Brand.PLAYER_GOLDENROD]

var sim: CitySim
var town_name := "Your town"

var _queue: Array = []
var _dim := 0.0
var _rays := 0.0
var _bits: Array = []  # {p, v, spin, a, size, color, life}
var _card: PanelContainer
var _bar: ProgressBar
var _ok: Button
var _closing := false
var _fx := Control.new()  # the confetti, over the card


func setup(s: CitySim, town: String) -> void:
	sim = s
	town_name = town


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.draw.connect(_draw_fx)
	add_child(_fx)


## Queues a step to celebrate.
func celebrate(id: String) -> void:
	_queue.append(id)
	if _card == null:
		_next()


func _next() -> void:
	if _queue.is_empty():
		visible = false
		set_process(false)
		return
	_show(sim.charter.celebration(sim, _queue.pop_front(), town_name))


func _show(c: Dictionary) -> void:
	_closing = false
	visible = true
	set_process(true)
	_card = PanelContainer.new()
	var box := UiStyle.panel(16)
	box.bg_color = Brand.SURFACE_PANEL
	box.border_color = Brand.BRAND_TEAL
	box.set_border_width_all(2)
	box.set_content_margin_all(22)
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 24
	_card.add_theme_stylebox_override("panel", box)
	_card.custom_minimum_size.x = WIDTH
	add_child(_card)
	move_child(_fx, -1)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_card.add_child(col)

	# The House mark, then the step and the new name.
	var mark := TextureRect.new()
	mark.texture = load(Brand.MARK)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(0, 56)
	col.add_child(mark)
	var sub := UiStyle.label("STEP %d OF %d  ·  %s" % [int(c.step), Charter.STEPS.size(), str(c.name).to_upper()], 11, Brand.CORAL_TEXT, 700)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var title := UiStyle.title(str(c.title), 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = WIDTH - 44
	col.add_child(title)
	col.add_child(_ladder(int(c.step)))
	if str(c.how) != "":
		var how := UiStyle.label(str(c.how), 13, Brand.INK_MUTED)
		how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		how.custom_minimum_size.x = WIDTH - 44
		col.add_child(how)

	# What it opens: the tools, then the rest of the new powers.
	var rows: Array = []
	if not c.powers.is_empty():
		col.add_child(HSeparator.new())
		col.add_child(UiStyle.label("NOW YOU HAVE", 11, Brand.BRAND_MINT, 700))
		for p in c.powers:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var icon: String = p[1]
			var ic := Icon.new(icon, 18)
			ic.color = Brand.BRAND_MINT
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(ic)
			var l := UiStyle.label(str(p[0]), 14)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = WIDTH - 70
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			row.modulate.a = 0.0
			col.add_child(row)
			rows.append(row)

	# How far to the next step.
	var next := sim.charter.next_progress(sim)
	var frac := 0.0
	if not next.is_empty():
		col.add_child(HSeparator.new())
		frac = clampf(float(next.have) / maxf(1.0, float(next.need)), 0.0, 1.0)
		var line := UiStyle.label("Next: %s  ·  %s of %s people" % [next.name, CitySim.money_text(int(next.have)),
			CitySim.money_text(int(next.need))], 12, Brand.INK_MUTED)
		col.add_child(line)
		_bar = ProgressBar.new()
		_bar.show_percentage = false
		_bar.custom_minimum_size = Vector2(WIDTH - 44, 10)
		_bar.max_value = 1.0
		_bar.step = 0.001
		var bg := UiStyle._box(Brand.SURFACE_SUNKEN, 5)
		bg.set_content_margin_all(0)
		var fill := UiStyle._box(Brand.BRAND_CORAL, 5)
		fill.set_content_margin_all(0)
		_bar.add_theme_stylebox_override("background", bg)
		_bar.add_theme_stylebox_override("fill", fill)
		col.add_child(_bar)

	_ok = Button.new()
	_ok.text = "Keep building"
	_ok.custom_minimum_size = Vector2(0, 36)
	var ob := UiStyle._box(Brand.BRAND_CORAL, 8)
	_ok.add_theme_stylebox_override("normal", ob)
	_ok.add_theme_stylebox_override("hover", UiStyle._box(Brand.BRAND_CORAL.lightened(0.12), 8))
	_ok.add_theme_stylebox_override("focus", UiStyle._box(Brand.BRAND_CORAL.lightened(0.12), 8, Brand.FOCUS))
	_ok.add_theme_color_override("font_color", Brand.ON_CORAL)
	_ok.add_theme_color_override("font_hover_color", Brand.ON_CORAL)
	_ok.add_theme_color_override("font_focus_color", Brand.ON_CORAL)
	_ok.pressed.connect(close)
	col.add_child(_ok)

	# In: the town dims, the card pops, the mark bounces, the rows come in
	# one by one and the bar fills.
	_card.reset_size()
	_place()
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.6, 0.6)
	_card.modulate.a = 0.0
	mark.pivot_offset = Vector2(WIDTH * 0.5 - 22, 28)
	mark.scale = Vector2(0.2, 0.2)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "_dim", 0.6, 0.3)
	t.tween_property(_card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_card, "modulate:a", 1.0, 0.2)
	t.tween_property(mark, "scale", Vector2.ONE, 0.6).set_delay(0.15).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	for i in rows.size():
		t.tween_property(rows[i], "modulate:a", 1.0, 0.25).set_delay(0.45 + 0.1 * i)
	if _bar != null:
		_bar.value = 0.0
		t.tween_property(_bar, "value", frac, 1.1).set_delay(0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst()
	_ok.grab_focus.call_deferred()


## Eight dots for the ladder: the steps reached filled, the new one coral and
## pulsing.
func _ladder(step: int) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	for i in Charter.STEPS.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(26, 6)
		var on: bool = sim.charter.reached.has(Charter.STEPS[i].id)
		var color := Brand.BRAND_CORAL if i + 1 == step else (Brand.BRAND_TEAL if on else Brand.SURFACE_SUNKEN)
		dot.add_theme_stylebox_override("panel", UiStyle._box(color, 3))
		row.add_child(dot)
		if i + 1 == step:
			dot.pivot_offset = Vector2(13, 3)
			var p := dot.create_tween().set_loops()
			p.tween_property(dot, "scale", Vector2(1.25, 1.6), 0.5).set_trans(Tween.TRANS_SINE)
			p.tween_property(dot, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)
	return row


func _burst() -> void:
	_bits.clear()
	var from := _card.position + Vector2(_card.size.x * 0.5, 40)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in CONFETTI:
		var ang := rng.randf_range(-PI * 0.95, -PI * 0.05)
		var speed := rng.randf_range(260.0, 720.0)
		_bits.append({"p": from + Vector2(rng.randf_range(-60, 60), 0), "v": Vector2(cos(ang), sin(ang)) * speed,
			"spin": rng.randf_range(-9.0, 9.0), "a": rng.randf() * TAU, "size": Vector2(rng.randf_range(5, 10), rng.randf_range(3, 6)),
			"color": COLORS[i % COLORS.size()], "life": rng.randf_range(2.2, 3.6)})


func close() -> void:
	if _closing or _card == null:
		return
	_closing = true
	var card := _card
	var t := create_tween().set_parallel(true)
	t.tween_property(card, "modulate:a", 0.0, 0.2)
	t.tween_property(card, "scale", Vector2(0.9, 0.9), 0.2)
	if _queue.is_empty():
		t.tween_property(self, "_dim", 0.0, 0.25)
	t.chain().tween_callback(func():
		card.queue_free()
		_card = null
		_bar = null
		_next())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _card != null \
			and not _card.get_global_rect().has_point(event.global_position):
		close()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
		close()
		get_viewport().set_input_as_handled()


func _place() -> void:
	if _card != null:
		_card.position = ((size - _card.size) * 0.5).round()


func _process(delta: float) -> void:
	_rays += delta * 0.25
	for b in _bits:
		b.v.y += 900.0 * delta
		b.v *= 1.0 - 1.2 * delta
		b.p += b.v * delta
		b.a += b.spin * delta
		b.life -= delta
	_bits = _bits.filter(func(b): return b.life > 0.0 and b.p.y < size.y + 20)
	if not _closing:
		_place()
	if _card == null and _dim <= 0.0 and _queue.is_empty():
		visible = false
		set_process(false)
	queue_redraw()
	_fx.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Brand.SURFACE_SUNKEN, _dim))
	if _card != null:
		# Soft rays turning slowly behind the card.
		var c := _card.position + _card.size * 0.5
		var r := maxf(size.x, size.y)
		var fade := clampf(_dim / 0.6, 0.0, 1.0) * _card.modulate.a
		for i in 12:
			var a := _rays + TAU * i / 12.0
			var col := Color(Brand.BRAND_TEAL if i % 2 == 0 else Brand.BRAND_MINT, 0.05 * fade)
			draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a - 0.12) * r, c + Vector2.from_angle(a + 0.12) * r]), col)


func _draw_fx() -> void:
	for b in _bits:
		_fx.draw_set_transform(b.p, b.a)
		_fx.draw_rect(Rect2(-b.size * 0.5, b.size), Color(b.color, clampf(b.life, 0.0, 1.0)))
	_fx.draw_set_transform(Vector2.ZERO, 0.0)
