extends SceneTree
## Run: godot --headless -s tests/test_cursor_cards.gd
##
## The cards that follow the cursor (HoverCard: "Hiatt home", "Empty lot";
## PlacementHints: the wind card, "You have no builder's yards yet.") never
## cover the bottom toolbar, its open menu, the top bar or an open panel, at
## every screen size. The critic (2026-10-27) found "Hiatt home" over the
## Zoning button and the wind card over Utilities and Civic. Nathan,
## 2026-10-09: "We can't just build things for one monitor size."

## Phone, tablet, laptop, monitor, wide and ultrawide.
const SIZES := [Vector2i(390, 844), Vector2i(768, 1024), Vector2i(1280, 800), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3440, 1440)]

var _failed := false
var _main: Node


func _initialize() -> void:
	_pure()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


## The placement rule on its own.
func _pure() -> void:
	var screen := Rect2(0, 0, 1600, 900)
	var bar := Rect2(0, 855, 1600, 45)
	var top := Rect2(0, 0, 1600, 38)
	var card := Vector2(120, 36)
	var avoid: Array[Rect2] = [bar, top]
	var p := UiStyle.beside_cursor(card, Vector2(800, 400), screen, avoid)
	_check(p == Vector2(818, 418), "in open ground it sits below and right of the cursor (%s)" % p)
	p = UiStyle.beside_cursor(card, Vector2(300, 845), screen, avoid)
	_check(not Rect2(p, card).intersects(bar) and p.y < 845, "just above the toolbar it flips above the cursor (%s)" % p)
	p = UiStyle.beside_cursor(card, Vector2(1590, 400), screen, avoid)
	_check(screen.encloses(Rect2(p, card)) and not Rect2(p, card).has_point(Vector2(1590, 400)),
		"at the right edge it stays on screen and off the cursor (%s)" % p)
	p = UiStyle.beside_cursor(card, Vector2(1595, 850), screen, avoid)
	var r := Rect2(p, card)
	_check(not r.intersects(bar) and not r.has_point(Vector2(1595, 850)), "in the bottom right corner it goes up and left (%s)" % p)
	p = UiStyle.beside_cursor(card, Vector2(700, 45), screen, avoid)
	_check(not Rect2(p, card).intersects(top), "just under the top bar it stays below it (%s)" % p)
	# A panel beside the cursor: it goes the other way.
	var panel := Rect2(830, 300, 400, 300)
	avoid.append(panel)
	p = UiStyle.beside_cursor(card, Vector2(810, 400), screen, avoid)
	_check(not Rect2(p, card).intersects(panel) and not Rect2(p, card).has_point(Vector2(810, 400)),
		"an open panel to the right sends it left (%s)" % p)


func _run() -> void:
	while _main.loading:
		await process_frame
	var hud: Hud
	var hints: PlacementHints
	for c in _main.get_children():
		if c is Hud:
			hud = c
		if c is PlacementHints:
			hints = c
	_check(hud != null and hints != null, "found the HUD and the placement hints")
	if hud == null or hints == null:
		_end()
		return
	hud.hover._title.text = "Hiatt home"
	hud.hover._problem.text = "Not enough customers: few people live within a short drive"
	hud.hover._problem.visible = true
	hints._text.text = "Wind from the southwest: smoke drifts northeast\nHere: clean air and quiet.\nYou have no builder's yards yet."
	# The menus that cover the most: Zoning and Utilities, then a panel.
	for size in SIZES:
		root.size = size
		UiScale.apply()
		for cat in ["zones", "utilities"]:
			hud.close_all()
			hud._open(cat)
			await _frames(4)
			_sweep(hud, hints, "%dx%d (%s), %s open" % [size.x, size.y, root.get_visible_rect().size, cat])
		hud.close_all()
		hud.advisor.visible = true
		await _frames(4)
		_sweep(hud, hints, "%dx%d (%s), the advisor open" % [size.x, size.y, root.get_visible_rect().size])
		hud.advisor.visible = false
	_end()


## Rests the cursor all over the map (anywhere not on a bar or panel) and
## checks both cards stay clear, on screen and off the cursor.
func _sweep(hud: Hud, hints: PlacementHints, where: String) -> void:
	var screen := root.get_visible_rect()
	var avoid := UiStyle.keep_clear_rects(self)
	_check(avoid.has(hud._top_bar.get_global_rect()) and avoid.has(hud._drawer_dock.get_global_rect()) == hud._drawer_dock.is_visible_in_tree() and avoid.size() >= 3,
		"%s: the top bar, the toolbar and any open menu keep clear (%d rects)" % [where, avoid.size()])
	var bottom_top := screen.end.y
	for r in avoid:
		if r.end.y >= screen.end.y - 1.0:
			bottom_top = minf(bottom_top, r.position.y)
	var spots: Array[Vector2] = []
	# The row just above the toolbar and its menu (where "Hiatt home" was),
	# the row under the top bar, the edges, and a coarse grid.
	for i in 41:
		var x := screen.size.x * i / 40.0
		for y in [bottom_top - 1.0, bottom_top - 6.0, bottom_top - 20.0, hud._top_bar.get_global_rect().end.y + 2.0]:
			spots.append(Vector2(x, y))
	for i in 13:
		for j in 9:
			spots.append(Vector2(screen.size.x * i / 12.0, screen.size.y * j / 8.0))
	var bad := 0
	var tried := 0
	var first := ""
	for p in spots:
		if avoid.any(func(r: Rect2): return r.has_point(p)) or not screen.grow(0.5).has_point(p):
			continue  # on a bar or panel: both cards hide there
		tried += 1
		hud.hover.place(p)
		hints._place_card(p)
		for c in [hud.hover, hints._card]:
			var r: Rect2 = c.get_global_rect()
			var over := avoid.any(func(a: Rect2): return r.intersects(a))
			if over or not screen.grow(0.5).encloses(r) or r.has_point(p):
				bad += 1
				if first == "":
					first = "%s at %s: %s" % [c.name, p, r]
	_check(tried > 100, "%s: rested the cursor in %d places" % [where, tried])
	_check(bad == 0, "%s: neither card covers a bar, the menu or a panel, or leaves the screen (%d bad, first %s)" % [where, bad, first])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _end() -> void:
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	_failed = _failed or not ok
