class_name SoundMixer
extends CanvasLayer
## Admin > Sound mixer: one row for each kind of sound in the game, with its
## own volume, mute and solo, a live meter, a sample button and a few tuning
## knobs that really change how the game plays it (see SoundMix). Opened with
## Ctrl+Shift+F12 (Cmd+Shift+F12 on a Mac) in the desktop app only; the
## browser build has no way in. Nothing here signs anyone in: it changes this
## computer, and "Save for everyone" writes data/audio_mix.json in the project
## folder (when it is on this computer) so the next build ships the mix.

const MARGIN := 20.0
const MAX_WIDTH := 1180.0
## Base volume (dB) a sample plays at, before the mix: matches the game.
const RAIL_DB := -2.0
const WORLD_DB := -6.0

var _root: Control
var _panel: PanelContainer
var _mixer_view: VBoxContainer
var _loud_view: VBoxContainer
var _status: Label
var _undo_btn: Button
var _ab_btn: Button
var _tab_btns := {}
var _master := {}
var _limiter := {}
var _groups := {}
var _rows := {}
var _loud_rows := {}
var _loud_note: Label
var _sample := AudioStreamPlayer.new()
var _sample_id := ""
var _sample_timer: SceneTreeTimer
var _tick := 0.0
var _wide_sliders := []


## The admin tools exist only in the desktop app.
static func available() -> bool:
	return not OS.has_feature("web")


## Ctrl+Shift+F12, or Cmd+Shift+F12.
static func is_hotkey(e: InputEvent) -> bool:
	if not (e is InputEventKey):
		return false
	var k := e as InputEventKey
	return k.pressed and not k.echo and k.keycode == KEY_F12 and k.shift_pressed and (k.ctrl_pressed or k.meta_pressed)


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sample)
	_build()
	get_viewport().size_changed.connect(_fit)
	visible = false


func is_open() -> bool:
	return visible


func toggle() -> void:
	if not available():
		return
	if visible:
		close()
	else:
		open()


func open() -> void:
	SoundMix.ensure_loaded()
	visible = true
	_sync()
	_fit()
	_set_status("Changes save on this computer as you make them.")


func close() -> void:
	visible = false
	SoundMix.set_hear_before(false)
	SoundMix.clear_solo()
	_stop_sample()


func _input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	if _sample_id != "" and _sample.playing:
		SoundMix.report(_sample_id, db_to_linear(_sample.volume_db))
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.08
	if _mixer_view.visible:
		for id in _rows:
			var m := SoundMix.meter(id)
			var r: Dictionary = _rows[id]
			r.meter.value = SoundMix.meter_fill(float(m.level))
			r.meter.self_modulate = Brand.CRITICAL if r.meter.value > 0.9 else (Brand.WARNING if r.meter.value > 0.75 else Brand.BRAND_MINT)
			var n := int(m.voices)
			r.voices.text = "%d playing" % n if n > 0 else ""
	else:
		_refresh_loud()


# --- Building the panel ----------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = ShellStyle.theme()
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(Brand.SURFACE, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	_panel = PanelContainer.new()
	var box := ShellStyle.panel()
	box.set_corner_radius_all(10)
	box.set_border_width_all(1)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	box.shadow_color = Color(0, 0, 0, 0.4)
	box.shadow_size = 24
	box.bg_color = Brand.SURFACE_PANEL.lightened(0.0)
	box.bg_color.a = 0.98
	_panel.add_theme_stylebox_override("panel", box)
	_root.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)

	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", 12)
	head.add_child(ShellStyle.title("Sound mixer", 22))
	var sub := ShellStyle.text("Admin only. Turn any one sound up or down. Changes affect this computer; \"Save for everyone\" ships them.", 13, 500, Brand.INK_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(260, 0)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)
	head.add_child(_btn("Close", close))
	col.add_child(head)

	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 8)
	bar.add_theme_constant_override("v_separation", 6)
	_undo_btn = _btn("Undo last change", func():
		SoundMix.undo()
		_sync()
		_set_status("Undone."))
	bar.add_child(_undo_btn)
	bar.add_child(_btn("Reset all", func():
		SoundMix.reset_all()
		_sync()
		_set_status("Everything is back to the shipped mix.")))
	_ab_btn = _btn("Hearing: your mix", _toggle_before)
	_ab_btn.tooltip_text = "Before and after: switch between the mix as it was when the game started, and your changes."
	bar.add_child(_ab_btn)
	var save := _btn("Save for everyone", _save_for_everyone)
	ShellStyle.primary(save)
	save.tooltip_text = "Writes data/audio_mix.json in the project folder. Commit it to ship this mix to every player."
	bar.add_child(save)
	col.add_child(bar)
	_status = ShellStyle.text("", 13, 600, Brand.BRAND_MINT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)

	# Master strip.
	var strip := HFlowContainer.new()
	strip.add_theme_constant_override("h_separation", 24)
	strip.add_theme_constant_override("v_separation", 6)
	_master = _slider_row(strip, "Master", "Overall loudness of the whole game, on top of the pause menu's Master.",
		-SoundMix.DB_LIMIT, SoundMix.DB_LIMIT, 0.5, func(v: float): SoundMix.set_master_db(v), _pct_text)
	_limiter = _slider_row(strip, "Keep everything balanced",
		"Gently squeezes the loudest moments so lots of sounds at once don't blare. Off = as now.",
		0.0, 1.0, 0.05, func(v: float): SoundMix.set_limiter(v), _limiter_text)
	col.add_child(strip)
	_wide_sliders = [_master.slider, _limiter.slider]

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for t in [["mixer", "Mixer"], ["loud", "Too loud? Find it"]]:
		var b := _btn(t[1], func(): _show_tab(t[0]))
		b.toggle_mode = true
		_tab_btns[t[0]] = b
		tabs.add_child(b)
	col.add_child(tabs)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var views := VBoxContainer.new()
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(views)
	_mixer_view = VBoxContainer.new()
	_mixer_view.add_theme_constant_override("separation", 6)
	_mixer_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	views.add_child(_mixer_view)
	_loud_view = VBoxContainer.new()
	_loud_view.add_theme_constant_override("separation", 6)
	_loud_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	views.add_child(_loud_view)
	_build_mixer()
	_build_loud()
	_show_tab("mixer")


func _build_mixer() -> void:
	for cat in SoundMix.CATEGORIES:
		var head := HFlowContainer.new()
		head.add_theme_constant_override("h_separation", 16)
		_mixer_view.add_child(HSeparator.new())
		var name := ShellStyle.text(cat[1], 16, 700, Brand.BRAND_MINT)
		name.custom_minimum_size = Vector2(190, 0)
		head.add_child(name)
		_groups[cat[0]] = _slider_row(head, "All of these", "Turns every sound in this group up or down together.",
			-SoundMix.DB_LIMIT, SoundMix.DB_LIMIT, 0.5, func(v: float): SoundMix.set_group(cat[0], v), _pct_text, 150.0)
		_mixer_view.add_child(head)
		for k in SoundMix.KINDS:
			if k.cat == cat[0]:
				_mixer_view.add_child(_sound_row(k))


func _sound_row(k: Dictionary) -> Control:
	var id: String = k.id
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 2)
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 8)
	line.add_theme_constant_override("v_separation", 4)
	holder.add_child(line)
	var name := ShellStyle.text(k.name, 14, 600)
	name.custom_minimum_size = Vector2(150, 28)
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(name)
	var slider := _slider(-SoundMix.DB_LIMIT, SoundMix.DB_LIMIT, 0.5, 130.0)
	line.add_child(slider)
	var pct := ShellStyle.text("", 13, 600, Brand.INK_MUTED)
	pct.custom_minimum_size = Vector2(64, 28)
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(pct)
	var mute := _btn("Mute", func(): pass)
	mute.toggle_mode = true
	mute.tooltip_text = "Silence just this sound."
	line.add_child(mute)
	var solo := _btn("Solo", func(): pass)
	solo.toggle_mode = true
	solo.tooltip_text = "Hear only this sound."
	line.add_child(solo)
	var meter := ProgressBar.new()
	meter.min_value = 0.0
	meter.max_value = 1.0
	meter.show_percentage = false
	meter.custom_minimum_size = Vector2(96, 12)
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.tooltip_text = "How loud this is right now."
	line.add_child(meter)
	var voices := ShellStyle.text("", 12, 500, Brand.INK_MUTED)
	voices.custom_minimum_size = Vector2(70, 28)
	voices.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(voices)
	if id != "music/theme":
		var play := _btn("Play a sample", func(): _play_sample(id))
		play.set_meta("silent", true)
		line.add_child(play)
	var tune_btn: Button = null
	var tuning := _tuning_ids(k)
	if not tuning.is_empty():
		tune_btn = _btn("Tune", func(): pass)
		tune_btn.toggle_mode = true
		line.add_child(tune_btn)
	var help := ShellStyle.text(k.help, 12, 500, Brand.INK_FAINT)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	holder.add_child(help)

	var r := {"slider": slider, "pct": pct, "mute": mute, "solo": solo, "meter": meter, "voices": voices, "tune": {}, "tune_btn": tune_btn}
	_rows[id] = r
	slider.value_changed.connect(func(v: float):
		SoundMix.set_sound(id, "db", v)
		pct.text = SoundMix.percent_text(v))
	mute.toggled.connect(func(on: bool):
		SoundMix.set_sound(id, "mute", on)
		_set_status("%s muted." % k.name if on else "%s is back on." % k.name))
	solo.toggled.connect(func(on: bool):
		SoundMix.set_solo(id, on)
		_set_status("Hearing only %s." % k.name if on else ("Solo off." if not SoundMix.has_solo() else "")))
	if tune_btn:
		var tune := VBoxContainer.new()
		tune.visible = false
		tune.add_theme_constant_override("separation", 4)
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 24)
		pad.add_child(tune)
		holder.add_child(pad)
		tune_btn.toggled.connect(func(on: bool): tune.visible = on)
		_tuning_rows(k, tune, r)
	return holder


func _tuning_ids(k: Dictionary) -> Array:
	var out := []
	if float(k.range) > 0.0:
		out.append("range")
	if int(k.max) > 0:
		out.append("cap")
	if float(k.pitch) >= 0.0:
		out.append("pitch")
	if k.get("gap", false):
		out.append("gap")
	return out


func _tuning_rows(k: Dictionary, into: Control, r: Dictionary) -> void:
	var id: String = k.id
	var flow := VBoxContainer.new()
	flow.add_theme_constant_override("separation", 4)
	into.add_child(flow)
	if float(k.range) > 0.0:
		r.tune.range = _slider_row(flow, "How far it carries",
			"How far away this can be heard. Shorter = only nearby ones play. Longer = it carries across town.",
			0.25, 2.0, 0.05, func(v: float): SoundMix.set_sound(id, "range", v),
			func(v: float): return "%d m%s" % [roundi(float(k.range) * v), " (as now)" if is_equal_approx(v, 1.0) else ""])
	if int(k.max) > 0:
		r.tune.cap = _slider_row(flow, "Most at once",
			"The most of this sound allowed at the same time, so 40 of them don't pile into a roar.",
			0.0, float(k.max), 1.0, func(v: float): SoundMix.set_sound(id, "cap", int(v)),
			func(v: float): return ("up to %d" % int(v)) + (" (as now)" if int(v) == int(k.cap) else "") if v > 0.0 else "none (silent)")
	if float(k.pitch) >= 0.0:
		r.tune.pitch = _slider_row(flow, "Sound less identical",
			"Shifts each repeat slightly up or down in pitch so the same sound doesn't feel copied.",
			0.0, 0.15, 0.005, func(v: float): SoundMix.set_sound(id, "pitch", v),
			func(v: float): return "none" if v < 0.001 else "+/- %d%%" % roundi(v * 100.0))
	if k.get("gap", false):
		r.tune.gap = _slider_row(flow, "How often it repeats",
			"Rests this long between plays. 0 = plays non-stop, as now. Higher = occasional, like a bird now and then.",
			0.0, 60.0, 1.0, func(v: float): SoundMix.set_sound(id, "gap", v),
			func(v: float): return "non-stop (as now)" if v < 0.5 else "rests ~%d s" % int(v))
	var reset := _btn("Reset this row", func():
		SoundMix.reset_sound(id)
		_sync()
		_set_status("%s is back to normal." % k.name))
	flow.add_child(reset)


func _build_loud() -> void:
	_loud_note = ShellStyle.text("", 14, 500, Brand.INK_MUTED)
	_loud_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loud_view.add_child(_loud_note)
	for k in SoundMix.KINDS:
		var id: String = k.id
		var line := HFlowContainer.new()
		line.add_theme_constant_override("h_separation", 8)
		var rank := ShellStyle.text("", 14, 700, Brand.CORAL_TEXT)
		rank.custom_minimum_size = Vector2(24, 28)
		line.add_child(rank)
		var name := ShellStyle.text(k.name, 14, 600)
		name.custom_minimum_size = Vector2(210, 28)
		line.add_child(name)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(200, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(bar)
		var voices := ShellStyle.text("", 12, 500, Brand.INK_MUTED)
		voices.custom_minimum_size = Vector2(80, 28)
		line.add_child(voices)
		line.add_child(_btn("Turn down", func():
			SoundMix.set_sound(id, "db", maxf(SoundMix.db_of(id) - 3.0, -SoundMix.DB_LIMIT))
			_sync()
			_set_status("%s turned down a little (now %s)." % [k.name, SoundMix.percent_text(SoundMix.db_of(id))])))
		line.add_child(_btn("Mute", func():
			SoundMix.set_sound(id, "mute", true)
			_sync()
			_set_status("%s muted. Find it in the Mixer to turn it back on." % k.name)))
		line.visible = false
		_loud_view.add_child(line)
		_loud_rows[id] = {"line": line, "rank": rank, "bar": bar, "voices": voices}


func _refresh_loud() -> void:
	var ranked := SoundMix.loudest()
	_loud_note.text = "Play with the camera near the noise. The loudest sounds of the last few seconds float to the top. Turn the top one down a little and listen again." \
		if not ranked.is_empty() else "Nothing is playing right now. Start a town, move the camera around, and come back: the loudest sounds will be listed here."
	var shown := {}
	var n := 0
	for e in ranked.slice(0, 10):
		var r: Dictionary = _loud_rows[e.id]
		n += 1
		shown[e.id] = true
		r.line.visible = true
		r.rank.text = "%d" % n
		r.bar.value = SoundMix.meter_fill(float(e.peak))
		r.bar.self_modulate = Brand.CRITICAL if r.bar.value > 0.9 else (Brand.WARNING if r.bar.value > 0.75 else Brand.BRAND_MINT)
		r.voices.text = "%d playing" % int(e.voices) if int(e.voices) > 0 else "stopped"
		_loud_view.move_child(r.line, n)
	for id in _loud_rows:
		if not shown.has(id):
			_loud_rows[id].line.visible = false


# --- Pieces -----------------------------------------------------------------------

func _btn(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("silent", true)
	b.pressed.connect(on_press)
	return b


func _slider(lo: float, hi: float, step: float, min_w: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(min_w, 28)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	# Scrolling the page must never move a slider by itself.
	s.scrollable = false
	return s


## A labelled slider with a value readout and one line of help. Returns
## {slider, text, format} so _sync can set it.
func _slider_row(into: Control, label: String, help: String, lo: float, hi: float, step: float,
		on_change: Callable, fmt: Callable, min_w := 110.0) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var name := ShellStyle.text(label, 13, 600)
	name.custom_minimum_size = Vector2(0 if label == "All of these" else 130, 0)
	line.add_child(name)
	var slider := _slider(lo, hi, step, min_w)
	line.add_child(slider)
	var val := ShellStyle.text("", 13, 600, Brand.INK_MUTED)
	val.custom_minimum_size = Vector2(88, 0)
	line.add_child(val)
	box.add_child(line)
	if help != "":
		var h := ShellStyle.text(help, 12, 500, Brand.INK_FAINT)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(h)
	into.add_child(box)
	slider.value_changed.connect(func(v: float):
		on_change.call(v)
		val.text = fmt.call(v))
	return {"slider": slider, "text": val, "fmt": fmt}


func _pct_text(v: float) -> String:
	return SoundMix.percent_text(v)


func _limiter_text(v: float) -> String:
	return "Off (as now)" if v <= 0.0 else "%d%%" % roundi(v * 100.0)


## Puts every control back in step with the mix (after undo, reset, A/B).
func _sync() -> void:
	_set_row(_master, SoundMix.master_db())
	_set_row(_limiter, SoundMix.limiter())
	for cat in _groups:
		_set_row(_groups[cat], SoundMix.group_db(cat))
	for id in _rows:
		var r: Dictionary = _rows[id]
		var db := SoundMix.db_of(id)
		r.slider.set_value_no_signal(db)
		r.pct.text = SoundMix.percent_text(db)
		r.mute.set_pressed_no_signal(SoundMix.is_muted(id))
		r.solo.set_pressed_no_signal(SoundMix.is_solo(id))
		for f in r.tune:
			var v = SoundMix.value_of(id, f)
			_set_row(r.tune[f], float(v))
	for t in _tab_btns:
		_tab_btns[t].set_pressed_no_signal(t == ("mixer" if _mixer_view.visible else "loud"))
	_undo_btn.disabled = not SoundMix.can_undo()
	_ab_btn.text = "Hearing: how it was" if SoundMix.hearing_before() else "Hearing: your mix"
	_ab_btn.set_pressed_no_signal(SoundMix.hearing_before())


func _set_row(row: Dictionary, v: float) -> void:
	row.slider.set_value_no_signal(v)
	row.text.text = row.fmt.call(v)


func _show_tab(which: String) -> void:
	_mixer_view.visible = which == "mixer"
	_loud_view.visible = which == "loud"
	for t in _tab_btns:
		_tab_btns[t].set_pressed_no_signal(t == which)


func _toggle_before() -> void:
	SoundMix.set_hear_before(not SoundMix.hearing_before())
	_sync()
	_set_status("Hearing the mix as it was when the game started. Press again for your changes." if SoundMix.hearing_before() \
		else "Hearing your changes.")


func _save_for_everyone() -> void:
	var r := SoundMix.save_for_everyone()
	_set_status(str(r.message), not bool(r.ok))


func _set_status(text: String, bad := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Brand.BRAND_CORAL if bad else Brand.BRAND_MINT)
	_undo_btn.disabled = not SoundMix.can_undo()


func _fit() -> void:
	if _panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var m := MARGIN if vp.x > 700.0 else 6.0
	var w := minf(vp.x - 2.0 * m, MAX_WIDTH)
	for sl in _wide_sliders:
		sl.custom_minimum_size.x = 200.0 if vp.x > 700.0 else 110.0
	_panel.size = Vector2(w, vp.y - 2.0 * m)
	_panel.position = Vector2((vp.x - w) * 0.5, m)


# --- Samples ----------------------------------------------------------------------

## Plays one sound through the real bus, at the volume the mix gives it
## (mute and solo are ignored so a sample can always be tried).
func _play_sample(id: String) -> void:
	var k := SoundMix.kind(id)
	var stream := SoundSettings.stream(id)
	if stream == null or k.is_empty():
		return
	_stop_sample()
	var base := WORLD_DB
	if id.begins_with("ui/"):
		base = float(UiSounds.VOLUME.get(id.get_file(), -6.0))
	elif id.begins_with("world/rail/"):
		base = RAIL_DB
	else:
		base = WORLD_DB + float(SoundSources.GAIN.get(id.get_file(), 0.0))
	if id == "world/car_engine":
		base = WORLD_DB
	_sample_id = id
	_sample.stream = stream
	_sample.bus = SoundMix.SAMPLE_BUS.get(k.cat, "Master") if AudioServer.get_bus_index(SoundMix.SAMPLE_BUS.get(k.cat, "Master")) != -1 else "Master"
	_sample.volume_db = base + SoundMix.sample_db(id)
	_sample.pitch_scale = SoundMix.pitch_for(id)
	_sample.play()
	_sample_timer = get_tree().create_timer(3.0)
	var t := _sample_timer
	t.timeout.connect(func():
		if t == _sample_timer:
			_stop_sample())
	if SoundMix.is_silenced(id):
		_set_status("%s is muted (or something else is soloed) in the game, but the sample plays anyway." % k.name)


func _stop_sample() -> void:
	_sample_id = ""
	_sample_timer = null
	if _sample.playing:
		_sample.stop()
