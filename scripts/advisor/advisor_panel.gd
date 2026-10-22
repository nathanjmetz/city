class_name AdvisorPanel
extends PanelContainer
## The advisor's panel, docked flush to the right edge under the top bar and
## opened from the Advice button up there. It never opens by itself, except
## for the one-time welcome and, if the player turns it on, for new problems.
## With automatic advice on, the button gets a small dot when there's
## something new worth a look; that's all.

signal opened

const SETTINGS_PATH := "user://advisor.json"
const WIDTH := 320
## A tip has to stick around this long (game ticks) before it earns a dot,
## so numbers bobbing around a threshold don't nag.
const SETTLE_TICKS := 120
## Neighbors brand colours.
const TEAL := Color("2f8f8c")
const MINT := Color("8fcfbf")
const CORAL := Color("ef6f51")

var sim: CitySim
var category := func() -> String: return ""
## {"welcomed": bool, "auto": bool, "interrupt": bool}
var settings := {"welcomed": false, "auto": true, "interrupt": false}

var _button: Button
var _dot := _Dot.new()
var _list := VBoxContainer.new()
var _more := Button.new()
var _auto := CheckButton.new()
var _interrupt := CheckButton.new()
var _tips := []
var _since := {}     # tip id -> tick it first showed up
var _seen := {}      # tip id -> true once the player has seen it
var _idea_offset := 0
var _welcome := false
var _wait := 0.0
var _shown_key := ""


func setup(s: CitySim, category_getter: Callable) -> void:
	sim = s
	category = category_getter


func _ready() -> void:
	_load_settings()
	add_theme_stylebox_override("panel", _style())
	custom_minimum_size.x = WIDTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	var ic := Icon.new("advice", 16)
	ic.color = MINT
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var title := UiStyle.label("ADVICE", 11, UiStyle.MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(close_panel)
	head.add_child(close)

	_list.add_theme_constant_override("separation", 6)
	col.add_child(_list)

	_more.text = "Another idea"
	_more.focus_mode = Control.FOCUS_NONE
	_more.flat = true
	_more.add_theme_font_size_override("font_size", 12)
	_more.add_theme_color_override("font_color", MINT)
	_more.add_theme_color_override("font_hover_color", MINT.lightened(0.3))
	_more.size_flags_horizontal = Control.SIZE_SHRINK_END
	_more.pressed.connect(func():
		_idea_offset += 1
		_show_tips())
	col.add_child(_more)

	col.add_child(HSeparator.new())
	for entry in [[_auto, "Tips on their own", "auto",
				"A dot on the Advice button when something's worth a look"],
			[_interrupt, "Pop open for problems", "interrupt",
				"Open this panel by itself when a new problem comes up (the game keeps running)"]]:
		var cb: CheckButton = entry[0]
		var key: String = entry[2]
		cb.text = entry[1]
		cb.tooltip_text = entry[3]
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 12)
		cb.button_pressed = settings[key]
		cb.toggled.connect(func(on):
			settings[key] = on
			_save_settings()
			_update_dot())
		col.add_child(cb)

	visible = false
	_refresh()
	if not settings.welcomed:
		_show_welcome.call_deferred()


## The Advice button for the top bar, with its little dot.
func make_button() -> Button:
	_button = Button.new()
	_button.toggle_mode = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.tooltip_text = "Advice"
	_button.custom_minimum_size = Vector2(82, 24)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_button.add_child(row)
	var ic := Icon.new("advice", 15)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var t := UiStyle.label("Advice", 12)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	_dot.position = Vector2(4, 3)
	_button.add_child(_dot)
	_button.toggled.connect(func(on): open_panel() if on else close_panel())
	return _button


func open_panel() -> void:
	if not visible:
		_idea_offset = 0
	visible = true
	_show_tips()
	if _button:
		_button.set_pressed_no_signal(true)
	opened.emit()


func close_panel() -> void:
	visible = false
	if _welcome:
		_welcome = false
		_show_tips()
	if _button:
		_button.set_pressed_no_signal(false)
	_update_dot()


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 1.0  # always up to date, re-read once a second
	_refresh()


## Re-reads the town, then updates the dot, the open panel, or (if allowed)
## pops open for a new problem.
func _refresh() -> void:
	if sim == null:
		return
	_tips = Advisor.tips(sim, category.call())
	var now := {}
	for t in _tips:
		now[t.id] = true
		if not _since.has(t.id):
			_since[t.id] = sim.tick_count
	for id in _since.keys():
		if not now.has(id):
			# Gone: forget it, so it can be raised again if it comes back.
			_since.erase(id)
			_seen.erase(id)
	if visible and not _welcome:
		_show_tips()
	elif settings.interrupt and not visible and _fresh(Advisor.Kind.PROBLEM):
		open_panel()
	_update_dot()


## True if a settled, unseen tip of this kind (or more urgent) is waiting.
func _fresh(worst: int) -> bool:
	for t in _tips:
		if t.kind <= worst and t.kind != Advisor.Kind.TOOL and not _seen.has(t.id) \
				and sim.tick_count - int(_since[t.id]) >= SETTLE_TICKS:
			return true
	return false


func _update_dot() -> void:
	if _button == null:
		return
	var problem := _fresh(Advisor.Kind.PROBLEM)
	_dot.visible = settings.auto and not visible and (problem or _fresh(Advisor.Kind.IDEA))
	_dot.color = CORAL if problem else MINT
	_button.tooltip_text = "Advice" if _tips.is_empty() else "Advice: " + _tips[0].text


func _show_tips() -> void:
	if _welcome:
		return
	var fixed := []   # problems, heads-ups and the tool note
	var ideas := []
	for t in _tips:
		(ideas if t.kind == Advisor.Kind.IDEA else fixed).append(t)
	var shown := fixed.slice(0, Advisor.SHOWN)
	var room := maxi(Advisor.SHOWN - shown.size(), 1 if fixed.size() < 4 else 0)
	for i in mini(room, ideas.size()):
		shown.append(ideas[(i + _idea_offset) % ideas.size()])
	_more.visible = ideas.size() > room and room > 0
	for t in shown:
		_seen[t.id] = true
	# Only rebuild when the words change, so the panel holds still.
	var key := "|".join(shown.map(func(t): return t.text))
	if key == _shown_key and _list.get_child_count() > 0:
		_update_dot()
		return
	_shown_key = key
	for c in _list.get_children():
		c.queue_free()
	if shown.is_empty():
		_list.add_child(_text(_quiet_line(), UiStyle.MUTED))
	for t in shown:
		_list.add_child(_row(t))
	_update_dot()


func _show_welcome() -> void:
	settings.welcomed = true
	_save_settings()
	_welcome = true
	_shown_key = ""
	open_panel()
	for c in _list.get_children():
		c.queue_free()
	_list.add_child(_text("Well hey there, welcome to town! Couple ideas to get you rolling:"))
	var ideas := Advisor.first_ideas(sim) if Advisor.is_new_city(sim) else \
		_tips.filter(func(t): return t.kind != Advisor.Kind.TOOL).map(func(t): return t.text).slice(0, 2)
	for idea in ideas:
		_list.add_child(_row({"kind": Advisor.Kind.IDEA, "text": idea}))
	_list.add_child(_text("I'll keep an eye on things and put a little dot on the Advice button up top when something's worth a look. Click it anytime. Rather I hush? Switch off \"Tips on their own\" down below. I won't pop up on you unless you turn that on too.", UiStyle.MUTED))
	var ok := Button.new()
	ok.text = "Sounds good"
	ok.focus_mode = Control.FOCUS_NONE
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(close_panel)
	_list.add_child(ok)
	_more.visible = false


## One tip: a coloured mark for how much it matters, then the words.
func _row(t: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var mark := ColorRect.new()
	mark.custom_minimum_size = Vector2(3, 0)
	mark.color = [CORAL, Color(CORAL, 0.55), MINT, TEAL][t.kind]
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mark)
	var l := _text(t.text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


func _text(s: String, color := UiStyle.TEXT) -> Label:
	var l := UiStyle.label(s, 13, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 40
	return l


func _quiet_line() -> String:
	var lines := ["All quiet. Town's humming right along.", "Nothing to fuss about. Not too shabby.",
		"Things are lookin' real good out there."]
	return lines[int(sim.tick_count / (CitySim.TICKS_PER_HOUR * 6)) % lines.size()]


## Docked flush to the right edge: square, hairlines on the open sides.
func _style() -> StyleBoxFlat:
	var b := UiStyle.dock(true)
	b.border_width_left = 1
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	return b


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(data) == TYPE_DICTIONARY:
		for key in settings:
			if data.has(key):
				settings[key] = bool(data[key])


func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))


## The little "something new" dot on the button.
class _Dot extends Control:
	var color := Color("8fcfbf"):
		set(v):
			color = v
			queue_redraw()

	func _init() -> void:
		size = Vector2(7, 7)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _draw() -> void:
		draw_circle(size * 0.5, 3.5, color, true, -1.0, true)
