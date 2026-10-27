class_name AwayCard
extends Control
## The card for CatchUp: docked flush under the top bar on the right (where
## the advisor and the guided tour go). While the town catches up it says so
## with a progress bar; then it says, in a few lines, what the neighbors did
## while you were away. No pop-ups, no feed: one card, closed with a click.

const WIDTH := 300
## Seconds after arriving before the town starts catching up: time to look
## around, and for the neighbors' towns to be unpacked (trade needs them).
const WAIT_MIN := 2.0
const WAIT_MAX := 12.0
## The summary closes itself after this long.
const SHOW_FOR := 45.0

var catch_up: CatchUp
var client: RegionClient
var hud: Node
var game: Node

var _card := PanelContainer.new()
var _title := UiStyle.title("", 15)
var _sub := UiStyle.label("", 11, UiStyle.MUTED)
var _list := VBoxContainer.new()
var _bar := ProgressBar.new()
var _ok := Button.new()
var _wait := 0.0
var _phase := "wait"  # wait, run, summary
var _shown_for := 0.0


func setup(c: CatchUp, cl: RegionClient, h: Node, g: Node) -> void:
	catch_up = c
	client = cl
	hud = h
	game = g


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var b := UiStyle.dock(true)
	b.border_width_left = 1
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.content_margin_top = 10
	b.content_margin_bottom = 10
	_card.add_theme_stylebox_override("panel", b)
	_card.custom_minimum_size.x = WIDTH
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	var ic := Icon.new("homes", 14)
	ic.color = Brand.BRAND_TEAL
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_sub)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = WIDTH - 28
	col.add_child(_title)
	_list.add_theme_constant_override("separation", 4)
	col.add_child(_list)
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(WIDTH - 28, 8)
	_bar.max_value = 1.0
	_bar.step = 0.001
	var bg := UiStyle._box(Brand.SURFACE_SUNKEN, 4)
	bg.set_content_margin_all(0)
	var fill := UiStyle._box(Brand.BRAND_TEAL, 4)
	fill.set_content_margin_all(0)
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fill)
	col.add_child(_bar)
	var row := HBoxContainer.new()
	col.add_child(row)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	_ok.text = "Back to town"
	_ok.focus_mode = Control.FOCUS_NONE
	_ok.pressed.connect(close)
	row.add_child(_ok)
	_ok.visible = false


func close() -> void:
	_phase = "closed"
	visible = false
	queue_free()


func _process(delta: float) -> void:
	match _phase:
		"wait":
			if game != null and game.get("loading"):
				return
			_wait += delta
			# (Neighbors still on their way after the welcome count as not in.)
			var unpacked := client == null or (client.region.stale_ids().is_empty() and client.region.awaiting.is_empty())
			if _wait >= WAIT_MAX or (_wait >= WAIT_MIN and unpacked):
				_phase = "run"
				_sub.text = "WHILE YOU WERE AWAY"
				_title.text = "Catching up with the neighbors"
				visible = true
		"run":
			if game == null or game.speed != 0:
				var t := Perf.now()
				catch_up.step(CatchUp.WEB_BUDGET_MS if OS.has_feature("web") else CatchUp.BUDGET_MS)
				Perf.add("net.catch_up", t)
			_bar.value = catch_up.progress()
			_sub.text = "DAY %d OF %d" % [clampi(catch_up.months_done(), 1, catch_up.months()), catch_up.months()]
			if catch_up.done():
				_finish()
		"summary":
			_shown_for += delta
			if _shown_for >= SHOW_FOR:
				close()
				return
	if visible:
		var top: float = hud._top_bar.size.y if hud != null and "_top_bar" in hud and hud._top_bar != null else 40.0
		_card.position = Vector2(size.x - _card.size.x, top)


func _finish() -> void:
	if client:
		client.away = {}
		# The neighbors see the town as it is now, not as it was.
		client.send_town(true)
	var lines := catch_up.lines()
	if lines.is_empty():
		close()
		return
	_phase = "summary"
	_bar.visible = false
	var m := catch_up.months()
	_sub.text = "%d DAY%s CAUGHT UP" % [m, "" if m == 1 else "S"]
	_title.text = "While you were away, your neighbors were at work"
	for line in lines:
		var l := UiStyle.label(line, 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = WIDTH - 28
		_list.add_child(l)
	_ok.visible = true
