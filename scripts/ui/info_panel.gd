class_name InfoPanel
extends PanelContainer
## The selected-object panel (Cities: Skylines 2's info panel): docked to the
## left edge under the top bar, it shows what the selected thing is, whether
## it's working, its numbers and any problem, refreshed as the city runs.
##
## A summary first, the detail folded away (the critic, 2026-10-26: a home's
## panel was a 30-row wall of text that grew to 640 px and ran off the
## bottom; Felt's place card and Telescope's fact grid show a few key facts
## and tuck the rest under tabs). Under the title: the status, small chips
## for the key facts, and one "what would help" line. Rows tagged with a
## section (Inspect.describe) fold under that heading, closed until opened;
## the panel is never wider than WIDTH and scrolls past `max_height`.

const GOOD := Brand.POSITIVE
const BAD := Brand.CRITICAL
const WIDTH := 340
## Rows tagged with this section are said by the chips and the help line instead.
const SUMMARY := "Summary"

var sim: CitySim
var tool: SelectTool
## The tallest the panel may grow; the HUD keeps it between the bars.
var max_height := 600.0

var _icon_slot := Control.new()
var _title := UiStyle.label("", 16)
var _kind := UiStyle.label("", 11, UiStyle.MUTED)
var _status := UiStyle.label("", 13)
var _chips := HFlowContainer.new()
var _help := UiStyle.label("", 12)
var _scroll := ScrollContainer.new()
var _body := VBoxContainer.new()
var _rows := GridContainer.new()
var _pollution := VBoxContainer.new()
var _sections := VBoxContainer.new()
var _problems := VBoxContainer.new()
var _log := VBoxContainer.new()
## Tips in plain words (how to fix a pollution source, say).
var _notes := VBoxContainer.new()
## Buttons for what the selection can do (upgrade, demolish), when it says.
var _actions := VBoxContainer.new()
var _action_key := ""
## A hub's development tree (built, next up, locked), when it has one.
var _tree := VBoxContainer.new()
var _tree_text := ""
var _follow := Button.new()
var _icon_name := ""
## The layout last built (row names and sections), so a refresh with the same
## shape only changes the words and the panel holds still.
var _shape := ""
var _values: Array[Label] = []
var _chip_key := ""
var _pollution_key := ""
## Sections the player opened, by title (kept from one selection to the next).
static var _open := {}
## Asks the HUD to open the Economy page (from a hub's sliders).
signal open_economy

var _guide: HubSliders
var _guide_for := {}
var _wait := 0.0


func setup(s: CitySim, t: SelectTool) -> void:
	sim = s
	tool = t
	tool.selected.connect(func(_sel): _refresh())


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.dock(false))
	custom_minimum_size = Vector2(WIDTH, 0)
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	_icon_slot.custom_minimum_size = Vector2(28, 28)
	head.add_child(_icon_slot)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(_kind)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_title)
	head.add_child(names)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(func(): tool.select({}))
	head.add_child(close)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	_chips.add_theme_constant_override("h_separation", 4)
	_chips.add_theme_constant_override("v_separation", 4)
	col.add_child(_chips)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_help)

	# Everything else scrolls, so the panel never covers the tool bar.
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_problems.add_theme_constant_override("separation", 2)
	_body.add_child(_problems)
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 12)
	_rows.add_theme_constant_override("v_separation", 2)
	_body.add_child(_rows)
	_pollution.add_theme_constant_override("separation", 2)
	_body.add_child(_pollution)
	_sections.add_theme_constant_override("separation", 2)
	_body.add_child(_sections)
	_tree.add_theme_constant_override("separation", 2)
	_body.add_child(_tree)
	_log.add_theme_constant_override("separation", 1)
	_body.add_child(_log)
	_notes.add_theme_constant_override("separation", 2)
	_body.add_child(_notes)
	_actions.add_theme_constant_override("separation", 4)
	_body.add_child(_actions)
	_follow.text = "Follow"
	_follow.toggle_mode = true
	_follow.tooltip_text = "Keep the camera on it"
	_follow.toggled.connect(func(on): tool.follow(on))
	_body.add_child(_follow)


func _process(delta: float) -> void:
	if not visible:
		return
	_wait -= delta
	if _wait <= 0.0:
		_refresh()


func _refresh() -> void:
	_wait = 0.5
	var d := Inspect.describe(sim, tool.selection)
	visible = not d.is_empty()
	if d.is_empty():
		return
	if d.icon != _icon_name:
		_icon_name = d.icon
		for c in _icon_slot.get_children():
			_icon_slot.remove_child(c)
			c.queue_free()
		var ic := Icon.new(d.icon, 28)
		ic.size = Vector2(28, 28)
		_icon_slot.add_child(ic)
	_follow.visible = d.get("follow", false)
	_follow.set_pressed_no_signal(tool.cam.following)
	_title.text = d.title
	_kind.text = d.kind.to_upper()
	_status.text = "●  " + d.status
	_status.visible = str(d.status) != ""
	_status.add_theme_color_override("font_color", GOOD if d.ok else BAD)
	_fill_chips(d.get("chips", []))
	var help := str(d.get("help", ""))
	_help.text = "↑  " + help if help != "" else ""
	_help.visible = help != ""
	_fill_rows(d)
	_fill_pollution(d.get("pollution", []), str(d.get("pollution_section", "")))
	var tree_text := JSON.stringify(d.get("tree", []))
	if tree_text != _tree_text:
		_tree_text = tree_text
		for c in _tree.get_children():
			_tree.remove_child(c)
			c.queue_free()
		for t in d.get("tree", []):
			_tree.add_child(_wrapped("%s: %s" % [t[0], t[1]], 12, UiStyle.MUTED))
	# The tree folds into its own section when Inspect names one.
	_place_tree(str(d.get("tree_section", "")))
	for c in _problems.get_children():
		_problems.remove_child(c)
		c.queue_free()
	for p in d.problems:
		_problems.add_child(_wrapped("⚠  " + p, 12, Brand.WARNING))
	# What the hub decided lately, and why.
	for c in _log.get_children():
		_log.remove_child(c)
		c.queue_free()
	for line in d.get("log", []):
		_log.add_child(_wrapped("·  " + line, 12, UiStyle.MUTED))
	for c in _notes.get_children():
		_notes.remove_child(c)
		c.queue_free()
	for n in d.get("notes", []):
		_notes.add_child(_wrapped("•  " + n, 12, UiStyle.MUTED))
	_show_actions(d.get("actions", []))
	_sync_guide()
	_fit()


## Small fact chips under the title: [label, value] or [label, value, ok].
func _fill_chips(chips: Array) -> void:
	var key := JSON.stringify(chips)
	if key == _chip_key:
		return
	_chip_key = key
	for c in _chips.get_children():
		_chips.remove_child(c)
		c.queue_free()
	_chips.visible = not chips.is_empty()
	for ch in chips:
		var ok: bool = ch[2] if ch.size() > 2 else true
		var box := PanelContainer.new()
		var sb := UiStyle._box(Color(Brand.SURFACE_RAISED, 0.8) if ok else Color(Brand.WARNING, 0.16), 8)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		box.add_theme_stylebox_override("panel", sb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		box.add_child(row)
		row.add_child(UiStyle.label(str(ch[0]), 12, UiStyle.MUTED))
		row.add_child(UiStyle.label(str(ch[1]), 12, UiStyle.TEXT if ok else Brand.WARNING, 600))
		_chips.add_child(box)


## The rows: untagged ones in the grid at the top, tagged ones folded under
## their section's heading. Rebuilt only when the shape changes.
func _fill_rows(d: Dictionary) -> void:
	var top := []
	var groups := {}   # section -> rows
	var order := []
	for r in d.rows:
		var sec: String = str(r[2]) if r.size() > 2 else ""
		if sec == SUMMARY:
			continue
		if sec == "":
			top.append(r)
			continue
		if not groups.has(sec):
			groups[sec] = []
			order.append(sec)
		groups[sec].append(r)
	for extra in [str(d.get("pollution_section", "")), str(d.get("tree_section", ""))]:
		if extra != "" and not groups.has(extra):
			groups[extra] = []
			order.append(extra)
	var names := []
	for r in top:
		names.append(r[0])
	for sec in order:
		names.append("#" + sec)
		for r in groups[sec]:
			names.append(r[0])
	var shape := JSON.stringify(names)
	if shape != _shape:
		_shape = shape
		_values.clear()
		for c in _rows.get_children():
			_rows.remove_child(c)
			c.queue_free()
		for c in _sections.get_children():
			# The pollution and tree blocks live in sections; keep them.
			for k in [_pollution, _tree]:
				if k.get_parent() != null and c.is_ancestor_of(k):
					k.get_parent().remove_child(k)
			_sections.remove_child(c)
			c.queue_free()
		_grid_rows(_rows, top)
		for sec in order:
			_sections.add_child(_section(sec, groups[sec]))
	var i := 0
	for r in top:
		_values[i].text = str(r[1])
		i += 1
	for sec in order:
		for r in groups[sec]:
			_values[i].text = str(r[1])
			i += 1


## Label and value pairs into a two-column grid; values wrap.
func _grid_rows(grid: GridContainer, rows: Array) -> void:
	grid.visible = not rows.is_empty()
	for r in rows:
		var l := UiStyle.label(str(r[0]), 12, UiStyle.MUTED)
		l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.add_child(l)
		var v := UiStyle.label("", 12)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.custom_minimum_size.x = 120
		grid.add_child(v)
		_values.append(v)


## A heading that opens and closes, with its rows under it.
func _section(title: String, rows: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.set_meta("section", title)
	var head := Button.new()
	head.flat = true
	head.focus_mode = Control.FOCUS_NONE
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", Brand.BRAND_MINT)
	head.add_theme_color_override("font_hover_color", Brand.BRAND_MINT.lightened(0.3))
	head.add_theme_color_override("font_pressed_color", Brand.BRAND_MINT)
	box.add_child(head)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	box.add_child(inner)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)
	inner.add_child(grid)
	_grid_rows(grid, rows)
	var show := func():
		var on: bool = _open.get(title, false)
		head.text = ("▾  " if on else "▸  ") + title
		inner.visible = on
	head.pressed.connect(func():
		_open[title] = not _open.get(title, false)
		show.call()
		_fit())
	show.call()
	return box


## The inner box of a section by title, or null.
func _section_body(title: String) -> VBoxContainer:
	for c in _sections.get_children():
		if c.get_meta("section", "") == title:
			return c.get_child(1)
	return null


## Pollution, one line a kind: the reading, then who makes it, each name a
## link that flies there (the critic, 2026-10-26: nine rows and four "Go
## to" buttons said the same three factories over and over).
func _fill_pollution(lines: Array, section: String) -> void:
	var parent: Control = _section_body(section) if section != "" else _body
	if parent == null:
		parent = _body
	if _pollution.get_parent() != parent:
		if _pollution.get_parent():
			_pollution.get_parent().remove_child(_pollution)
		parent.add_child(_pollution)
		if parent == _body:
			_body.move_child(_pollution, _rows.get_index() + 1)
	var key := JSON.stringify(lines.map(func(l): return [l.kind, l.reading, l.from.map(func(f): return [f.name, f.share])]))
	if key == _pollution_key:
		return
	_pollution_key = key
	for c in _pollution.get_children():
		_pollution.remove_child(c)
		c.queue_free()
	_pollution.visible = not lines.is_empty()
	for l in lines:
		var t := RichTextLabel.new()
		t.bbcode_enabled = true
		t.fit_content = true
		t.scroll_active = false
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size.x = WIDTH - 48
		t.add_theme_font_override("normal_font", Brand.ui(500))
		t.add_theme_font_override("bold_font", Brand.ui(700))
		t.add_theme_font_size_override("normal_font_size", 12)
		t.add_theme_font_size_override("bold_font_size", 12)
		t.add_theme_color_override("default_color", UiStyle.TEXT)
		t.meta_underlined = true
		var bits := []
		for i in l.from.size():
			var f: Dictionary = l.from[i]
			var name := str(f.name).replace("[", "(").replace("]", ")")
			bits.append(("[url=%d][color=#%s]%s[/color][/url] %d%%" % [i, Brand.BRAND_MINT.to_html(false), name, roundi(float(f.share) * 100.0)])
				if not f.go.is_empty() else "%s %d%%" % [name, roundi(float(f.share) * 100.0)])
		t.text = "[color=#%s]%s[/color]  %s%s" % [UiStyle.MUTED.to_html(false), l.kind, l.reading,
			(":  " + ", ".join(bits)) if not bits.is_empty() else ""]
		var from: Array = l.from
		t.meta_clicked.connect(func(meta):
			var f: Dictionary = from[int(str(meta))]
			tool.cam.fly_to(f.at)
			tool.select(f.go))
		t.tooltip_text = "Click a name to go there"
		_pollution.add_child(t)


## Puts the needs list (or a hub's tree) under its section, or at the bottom.
func _place_tree(section: String) -> void:
	var parent: Control = _section_body(section) if section != "" else null
	if parent == null:
		parent = _body
	if _tree.get_parent() != parent:
		if _tree.get_parent():
			_tree.get_parent().remove_child(_tree)
		parent.add_child(_tree)
		if parent == _body:
			_body.move_child(_tree, _sections.get_index() + 1)


func _wrapped(text: String, px: int, color: Color) -> Label:
	var l := UiStyle.label(text, px, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 48, 0)
	return l


## Grows to the content, up to max_height; past that the body scrolls.
func _fit() -> void:
	var head_h: float = (get_child(0) as Control).get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var want := _body.get_combined_minimum_size().y
	_scroll.custom_minimum_size = Vector2(WIDTH - 24, clampf(want, 0.0, maxf(max_height - head_h - 24.0, 80.0)))
	reset_size()


func _show_actions(actions: Array) -> void:
	var key := str(actions)
	if key == _action_key:
		return
	_action_key = key
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	for a in actions:
		var b := Button.new()
		b.text = a.label
		b.disabled = not a.get("enabled", true)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(WIDTH - 48, 0)
		if a.has("go"):
			# Jump to another thing (a pollution source) and select it.
			var go: Dictionary = a.go
			var at: Vector3 = a.at
			b.pressed.connect(func():
				tool.cam.fly_to(at)
				tool.select(go))
			_actions.add_child(b)
			continue
		var cmd: Dictionary = a.cmd
		b.pressed.connect(func():
			sim.apply(cmd)
			_refresh())
		_actions.add_child(b)


## Hubs get their Funding and Growth sliders at the bottom (see HubSliders).
func _sync_guide() -> void:
	if tool.selection == _guide_for:
		return
	_guide_for = tool.selection.duplicate()
	if _guide:
		_guide.queue_free()
		_guide = null
	if HubSliders.takes(sim, tool.selection):
		_guide = HubSliders.new()
		_guide.open_economy.connect(func(): open_economy.emit())
		_guide.setup(sim, str(tool.selection.type), int(tool.selection.id))
		_body.add_child(_guide)
