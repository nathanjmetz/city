class_name FirstTownTour
extends Control
## The guided first town (FirstTown has the steps): a small card just above
## the button to press says the plan, then one short goal at a time.
## The button to press pulses with an arrow bobbing over it, the camera
## glides to where the work is, the suggested grid and sites glow on the
## ground, and while a crew works the card says what they're doing with a
## progress bar. Skippable any time, and Help (?) has "Guided tour" to run it
## again. Runs by itself the first time someone starts a town.

const SETTINGS_PATH := "user://first_town.json"
const WIDTH := 300
## Guidance is mint (a hint, never coral: coral means "you").
const GLOW := Brand.BRAND_MINT
## Seconds the "Welcome to town!" card stays before closing itself.
const DONE_FOR := 10.0
## Seconds a "Power's on!" line stays up after a wait.
const CHEER_FOR := 5.0
const CHEERS := {"power_wait": "Power's on!", "water_wait": "Water's on!", "builders": "Your first family moved in!"}

## {"finished": bool (done or skipped once), "active": bool (mid-tour)}
var settings := {"finished": false, "active": false}
var running := false
var sim: CitySim
var hud: Node
var cam: CityCamera
var game: Node

var _card := PanelContainer.new()
var _count := UiStyle.label("", 10, UiStyle.MUTED)
var _title := UiStyle.title("", 16)
var _cheer := UiStyle.label("", 13, GLOW, 600)
var _body := UiStyle.label("", 13)
var _list := VBoxContainer.new()
var _work := VBoxContainer.new()
var _words := UiStyle.label("", 12, UiStyle.MUTED)
var _bar := ProgressBar.new()
var _go := Button.new()
var _skip := Button.new()
var _step := ""
var _intro := false
var _target := ""          # the HUD button to point at, or ""
var _ground := []          # world marks: [["grid", a, b] or ["ring", pos]]
var _glided := {}          # step -> true once the camera went there
var _spot := []            # the suggested grid, kept once the streets go in
var _cheer_left := 0.0
var _done_left := 0.0
var _poll := 0.0
var _t := 0.0


func setup(s: CitySim, h: Node, c: CityCamera, g: Node) -> void:
	sim = s
	hud = h
	cam = c
	game = g


func _ready() -> void:
	add_to_group("first_town_tour")
	_load_settings()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var b := UiStyle.panel()
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.content_margin_top = 10
	b.content_margin_bottom = 10
	_card.add_theme_stylebox_override("panel", b)
	_card.custom_minimum_size.x = WIDTH
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.add_to_group(UiStyle.KEEP_CLEAR)
	add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_card.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var ic := Icon.new("homes", 14)
	ic.color = GLOW
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_count)
	col.add_child(_title)
	for l in [_cheer, _body, _words]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = WIDTH - 28
	col.add_child(_cheer)
	col.add_child(_body)
	_list.add_theme_constant_override("separation", 3)
	col.add_child(_list)
	_work.add_theme_constant_override("separation", 3)
	_work.add_child(_words)
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
	_work.add_child(_bar)
	col.add_child(_work)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	_skip.text = "Skip tour"
	_skip.flat = true
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.add_theme_font_size_override("font_size", 12)
	_skip.add_theme_color_override("font_color", UiStyle.MUTED)
	_skip.pressed.connect(func(): stop())
	row.add_child(_skip)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	_go.focus_mode = Control.FOCUS_NONE
	_go.pressed.connect(_on_go)
	row.add_child(_go)


## Called once the town has loaded: the first time someone starts a town
## (or if they were partway through), the tour opens.
func maybe_start() -> void:
	if running:
		return
	if settings.active or (not settings.finished and Advisor.is_new_city(sim)):
		start()


## Starts (or replays) the tour. A brand-new town opens on the plan.
func start() -> void:
	running = true
	settings.active = true
	_save_settings()
	_glided.clear()
	_spot = FirstTown.grid_spot(sim)
	_step = ""
	_intro = FirstTown.current(sim) == "streets"
	visible = true
	if hud.has_method("close_all"):
		hud.close_all()
	if game.speed == 0:
		game.set_speed(1)
	_refresh()


## Ends the tour, finished or skipped. The advisor takes it from here.
func stop() -> void:
	running = false
	visible = false
	settings.active = false
	settings.finished = true
	_save_settings()
	if "advisor" in hud:
		hud.advisor.settings.welcomed = true
		hud.advisor._save_settings()


func _on_go() -> void:
	if _intro:
		_intro = false
		_refresh()
	elif _step == "done":
		stop()


func _process(delta: float) -> void:
	if not running:
		return
	_t += delta
	_cheer_left -= delta
	if _step == "done":
		_done_left -= delta
		if _done_left <= 0.0:
			stop()
			return
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.2
		_refresh()
	_place_card()
	queue_redraw()


## The card sits just above the button it talks about, clear of the arrow
## (the critic, 2026-10-26: docked in the Advice corner, it covered the
## Advice and bell panels; Deel keeps a tour's card next to its target).
## With nothing to press, it waits bottom right, above the tool bar.
func _place_card() -> void:
	var top: float = hud._top_bar.size.y if "_top_bar" in hud and hud._top_bar != null else 40.0
	var target := _pointed()
	if target != null:
		var r := target.get_global_rect()
		var x := clampf(r.get_center().x - _card.size.x * 0.5, 8.0, size.x - _card.size.x - 8.0)
		var y := r.position.y - _card.size.y - 48.0
		_card.position = Vector2(x, maxf(y, top + 8.0))
		return
	var bottom: float = hud.pad_bottom_height() if hud.has_method("pad_bottom_height") else 60.0
	_card.position = Vector2(size.x - _card.size.x - 8.0, maxf(size.y - bottom - _card.size.y - 12.0, top + 8.0))


## The button the arrow points at now, or null: none while the player has
## another menu open (the arrow sat on Utilities while they were in Parks).
func _pointed() -> Control:
	if _target == "" or not hud.has_method("tour_target"):
		return null
	var target: Control = hud.tour_target(_target)
	if target == null or not target.is_visible_in_tree():
		return null
	if _target.begins_with("cat:") and "_category" in hud and hud._category != "" \
			and hud._category != _target.substr(4):
		return null
	return target


func _refresh() -> void:
	# Steps check themselves off: a player who builds without pressing
	# "Let's go" skips the plan, as CS2's tutorial cards do.
	if _intro and FirstTown.current(sim) != "streets":
		_intro = false
	var now := "plan" if _intro else FirstTown.current(sim)
	if now == "done" and _step in ["", "plan"]:
		stop()  # the town got there on its own: nothing left to show
		return
	if now != _step:
		if now == "done":
			_done_left = DONE_FOR
		if CHEERS.has(_step) and FirstTown.index_of(now) > FirstTown.index_of(_step):
			_cheer.text = CHEERS[_step]
			_cheer_left = CHEER_FOR
		_step = now
	_cheer.visible = _cheer_left > 0.0 and _step != "done"
	_fill()
	_card.reset_size()  # shrink to the step's text


## Fills the card for the step and decides what to point at.
func _fill() -> void:
	var i := FirstTown.index_of(_step)
	var step: Dictionary = FirstTown.STEPS[i]
	_title.text = step.title
	_count.text = "GETTING STARTED" if _step == "plan" else ("GETTING STARTED  ·  ALL DONE" if _step == "done"
		else "GETTING STARTED  ·  STEP %d OF %d" % [_goal_number(), FirstTown.plan().size()])
	_target = ""
	_ground = []
	_go.visible = _step in ["plan", "done"]
	_go.text = "Let's go" if _step == "plan" else "Finish"
	_skip.visible = _step != "done"
	_list.visible = _step == "plan"
	_work.visible = false
	var rt: RoadTool = hud.road_tool
	var st: ServiceTool = hud.service_tool
	var zt: ZoneTool = hud.zone_tool
	match _step:
		"plan":
			_body.text = "Here's the plan. I'll show you each step as we go."
			if _list.get_child_count() == 0:
				var n := 1
				for goal in FirstTown.plan():
					var l := UiStyle.label("%d   %s" % [n, goal], 13)
					_list.add_child(l)
					n += 1
			_glide("plan", _grid_middle(), 620.0)
		"streets":
			if _spot.is_empty():
				_spot = FirstTown.grid_spot(sim)
			if rt.mode == RoadTool.Mode.NONE or rt.mode == RoadTool.Mode.BULLDOZE:
				_say("First, streets. Open Roads at the bottom.", "cat:roads")
			elif rt.mode != RoadTool.Mode.GRID:
				_say("Pick Grid. It lays out a whole block of streets at once.", "road:grid")
			elif rt.grid_preset != FirstTown.GRID_PRESET:
				_say("Pick Town: 400 by 300 ft blocks, like an old Midwest town plat.", "grid:%d" % FirstTown.GRID_PRESET)
			else:
				_say("Click the glowing corner, then the far one. Four blocks is plenty.", "")
			if not _spot.is_empty():
				_ground.append(["grid", _spot[0], _spot[1]])
			_glide("streets", _grid_middle(), 620.0)
		"yard":
			var yk := Services.Kind.BUILDER_YARD
			if st.kind == ServiceTool.OFF:
				_say("Every town needs a builder. Your first builder's yard is free: open Utilities.", "cat:utilities")
			elif st.kind != yk:
				_say("Pick Builder.", "svc:%d" % yk)
			else:
				_say("Click beside a street. Its crews and concrete trucks build your houses from here: green roads are close enough.", "")
			var yat := FirstTown.yard_spot(sim, _grid_middle())
			if yat != Vector3.INF:
				# The spot glows only once there's something to place: before
				# that the arrow is on the button, not on bare ground.
				if st.kind == yk:
					_ground.append(["ring", yat])
				_glide("yard", yat, 300.0)
		"power", "water":
			var kind: int = Services.Kind.POWER_FEED if _step == "power" else Services.Kind.WELL
			if st.kind == ServiceTool.OFF:
				_say("Homes need power and water before anyone moves in. Open Utilities." if _step == "power"
					else "Now water. Open Utilities.", "cat:utilities")
			elif st.kind != kind:
				_say("Pick Power line." if _step == "power" else "Pick Well.", "svc:%d" % kind)
			elif _step == "power":
				_say("Click beside one of your new streets. The electric co-op will run a line in from the highway.", "")
			else:
				_say("Click beside a street. A well and pump house covers about 650 homes.", "")
			var at := FirstTown.site_spot(sim, _step, _grid_middle())
			if at != Vector3.INF:
				if st.kind == kind:
					_ground.append(["ring", at])
				_glide(_step, at, 300.0)
		"power_wait", "water_wait", "builders":
			var c := FirstTown.crew(sim, _step)
			match _step:
				"power_wait":
					_body.text = "The co-op's line crew is setting poles and stringing wire. Homes hook up once it's live."
				"water_wait":
					_body.text = "The driller is putting down your well. It gets tested before it goes on line."
				"builders":
					_body.text = "Families are buying lots and builders are breaking ground. Watch the first house go up." \
						if not c.is_empty() else "Families are looking over your lots. A builder breaks ground any minute."
			if game.speed == 0:
				_body.text += " (The game's paused: press Space.)"
			if not c.is_empty():
				_work.visible = true
				_words.text = "%s  ·  %d%%" % [c.words, roundi(float(c.total) * 100.0)]
				_bar.value = float(c.total)
				_ground.append(["ring", c.pos])
				_glide(_step, c.pos, 160.0 if _step == "builders" else 200.0)
		"homes":
			if zt.zone == ZoneTool.OFF:
				_say("Last step: homes. Open Zoning.", "cat:zones")
			elif zt.zone != ZoneMap.Zone.RESIDENTIAL:
				_say("Pick Homes.", "zone:%d" % ZoneMap.Zone.RESIDENTIAL)
			else:
				_say("Click a street side, or drag along your streets. Lots get laid out along the curb.", "")
			_glide("homes", _grid_middle(), 420.0)
		"done":
			_body.text = "Your first neighbors are moving in. From here it's your town: more streets, shops and jobs. Advice up top has ideas anytime."


func _say(text: String, target: String) -> void:
	_body.text = text
	_target = target


## Which goal of the plan this step belongs to (wait steps count with theirs).
func _goal_number() -> int:
	var n := 0
	for s in FirstTown.STEPS.slice(0, FirstTown.index_of(_step) + 1):
		if s.has("goal"):
			n += 1
	return clampi(n, 1, FirstTown.plan().size())


## The middle of the player's streets: their crossings once there are some
## (a grid laid somewhere other than the suggested one put the yard's ring
## by the highway, the critic 2026-10-26), else the suggested grid's.
func _grid_middle() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for id in sim.network.nodes:
		if sim.network.segments_at(id).size() >= 3:
			sum += sim.network.nodes[id]
			n += 1
	if n >= FirstTown.JUNCTIONS:
		return Vector3(sum.x / n, 0.0, sum.z / n)
	if _spot.is_empty():
		return Vector3(sim.streets.main_at.x, 0.0, sim.streets.main_at.y)
	return (_spot[0] + _spot[1]) * 0.5


## Takes the camera to a step's spot, once per step.
func _glide(key: String, at: Vector3, dist: float) -> void:
	if _glided.has(key) or cam == null:
		return
	_glided[key] = true
	cam.glide_to(at, dist)


# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var target := _pointed()
	if target != null:
		var r := target.get_global_rect().grow(3.0 + 3.0 * pulse)
		draw_rect(r, Color(GLOW, 0.18 + 0.12 * pulse), true)
		draw_rect(r, Color(GLOW, 0.95), false, 2.0, true)
		_arrow(Vector2(r.get_center().x, r.position.y - 6.0 - 8.0 * pulse), true)
	for g in _ground:
		if g[0] == "grid":
			_grid(g[1], g[2], pulse)
		else:
			_ring(g[1], pulse)


## A bobbing arrow whose tip is at `tip`, pointing down (or up).
func _arrow(tip: Vector2, down: bool) -> void:
	var s := -1.0 if down else 1.0
	var pts := PackedVector2Array([tip, tip + Vector2(-11, 14 * s), tip + Vector2(-4, 14 * s),
		tip + Vector2(-4, 28 * s), tip + Vector2(4, 28 * s), tip + Vector2(4, 14 * s), tip + Vector2(11, 14 * s)])
	draw_colored_polygon(pts, GLOW)
	pts.append(tip)
	draw_polyline(pts, Brand.BRAND_INK, 1.5, true)


## The suggested grid's outline on the ground, with its two corners pulsing
## and an arrow over the first.
func _grid(a: Vector3, b: Vector3, pulse: float) -> void:
	var corners := [a, Vector3(b.x, 0, a.z), b, Vector3(a.x, 0, b.z), a]
	var line := PackedVector2Array()
	var ok := true
	for i in 4:
		for k in 12:
			var p: Vector3 = corners[i].lerp(corners[i + 1], k / 12.0)
			var s = _screen(p)
			if s == null:
				ok = false
				break
			line.append(s)
	if ok and line.size() > 1:
		line.append(line[0])
		draw_polyline(line, Color(GLOW, 0.35 + 0.35 * pulse), 3.0, true)
	for c in [a, b]:
		var s = _screen(c)
		if s != null:
			draw_circle(s, 7.0 + 5.0 * pulse, Color(GLOW, 0.35), true, -1.0, true)
			draw_circle(s, 5.0, GLOW, true, -1.0, true)
	var first = _screen(a)
	if first != null:
		_arrow(first - Vector2(0, 14 + 8 * pulse), true)


## A pulsing ring on the ground with an arrow over it.
func _ring(p: Vector3, pulse: float) -> void:
	var pts := PackedVector2Array()
	var r := 14.0 + 4.0 * pulse
	for k in 33:
		var a := TAU * k / 32.0
		var s = _screen(p + Vector3(cos(a) * r, 0, sin(a) * r))
		if s == null:
			return
		pts.append(s)
	draw_polyline(pts, Color(GLOW, 0.5 + 0.4 * pulse), 3.0, true)
	var top = _screen(p)
	if top != null:
		_arrow(top - Vector2(0, 30 + 10 * pulse), true)


## Where a point on the map is on screen, or null behind the camera.
func _screen(p: Vector3):
	if cam == null:
		return null
	var w := Terrain.lift(p) + Vector3(0, 0.5, 0)
	if cam.camera.is_position_behind(w):
		return null
	return cam.camera.unproject_position(w)


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
