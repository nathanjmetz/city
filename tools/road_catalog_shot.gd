extends SceneTree
## A picture of All roads open over the map, for checking it at every size.
## Run in a window: godot --resolution 390x844 -s tools/road_catalog_shot.gd -- out.png [search] [filter,filter]
## e.g. -- out.png "" bike     or     -- out.png brick
## Also saves out_bar.png (the Roads menu's bar with its All roads card) and
## out_picked.png (Brick street picked from it: in hand, and in the recents).
## A screen bigger than this Mac's (2560 or 3440 wide) can't open a window
## that big, so add as=3440x1440: the window (open it at the same shape,
## e.g. 1920x804) then lays out exactly as that screen does under Auto size
## (UiScale: 3440 x 1440 is 2150 x 900 at 160%), drawn at a lower sharpness.

var _main: Node
var _hud: Hud
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var args := Array(OS.get_cmdline_user_args()).filter(func(a): return not a.begins_with("as="))
	var out: String = args[0] if args.size() > 0 else "road_catalog.png"
	if _frames == 2:
		for c in _main.get_children():
			if c is Hud:
				_hud = c
		_hud.close_all()
		for n in _main.find_children("*", "FirstTownTour", true, false):
			n.stop()
		_main.set_speed(0)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("as="):
				var wh: PackedStringArray = a.substr(3).split("x")
				var target := Vector2i(int(wh[0]), int(wh[1]))
				var logical := Vector2(target) / UiScale.factor_for(target, UiScale.AUTO)
				UiScale.choice = minf(root.size.x / logical.x, root.size.y / logical.y)
				UiScale.apply()
	if _frames == 60:
		_hud._open("roads")
		_hud._pick_road(RoadStyle.Type.AVENUE_DIVIDED)
	if _frames == 90:
		_save(out.get_basename() + "_bar.png")
		_hud.open_catalog()
		if args.size() > 1 and args[1] != "":
			_hud.catalog.search(args[1])
		if args.size() > 2:
			for f in args[2].split(",", false):
				_hud.catalog.set_filter(f, true)
	if _frames == 130:
		var cat := _hud.catalog
		print("window %s, scale %.2f, catalog %s, panel %s, inside needs %s, %d across" % [root.size,
			root.content_scale_factor, cat.size, cat._panel.get_global_rect(),
			(cat._panel.get_child(0) as Control).get_combined_minimum_size(), cat._cols])
		_save(out)
		# Picked from the catalog: the road in hand, and in the recent tools.
		_hud.catalog.road_cards[RoadStyle.Type.BRICK].pressed.emit()
	if _frames == 160:
		_save(out.get_basename() + "_picked.png")
		quit()
	return false


func _save(path: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
