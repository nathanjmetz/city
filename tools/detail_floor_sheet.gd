extends SceneTree
## Contact sheets from tools/detail_floor_shots.gd pictures: a grid with each
## picture labelled. Needs a window (labels are drawn by the engine).
## Run: godot --resolution 800x450 -s tools/detail_floor_sheet.gd -- RUN_DIR OUT.png [targets=a,b] [dists=40,60] [tilt=40]
##        [cols=4] [cell=600] [title=text] [pairs=target:dist,target:dist]
## Without `pairs`, one cell for every target and distance (targets are rows,
## distances columns when the grid is wide enough, else it just wraps).
## `pairs` gives the exact cells, in order: the sheet of each tier's floor.

var _frames := 0
var _vp: SubViewport
var _out := ""


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var dir := a[0]
	_out = a[1]
	var targets: Array = []
	var dists: Array = []
	var tilt := 40
	var cols := 4
	var cell := 600
	var title := ""
	var pairs: Array = []
	for s in a.slice(2):
		if s.begins_with("targets="):
			targets = Array(s.trim_prefix("targets=").split(","))
		elif s.begins_with("dists="):
			dists = Array(s.trim_prefix("dists=").split(",")).map(func(x): return int(x))
		elif s.begins_with("tilt="):
			tilt = int(s.trim_prefix("tilt="))
		elif s.begins_with("cols="):
			cols = int(s.trim_prefix("cols="))
		elif s.begins_with("cell="):
			cell = int(s.trim_prefix("cell="))
		elif s.begins_with("title="):
			title = s.trim_prefix("title=")
		elif s.begins_with("pairs="):
			for p in s.trim_prefix("pairs=").split(","):
				var kv := p.split(":")
				pairs.append([kv[0], int(kv[1])])
	if pairs.is_empty():
		if targets.is_empty():
			var names := {}
			for f in DirAccess.get_files_at(dir):
				if f.ends_with(".png"):
					names[f.get_slice("_d", 0)] = true
			targets = names.keys()
			targets.sort()
		if dists.is_empty():
			dists = [25, 40, 60, 80, 100, 150, 200]
		for t in targets:
			for d in dists:
				pairs.append([t, d])
	var ch := cell * 9 / 16
	var rows := ceili(float(pairs.size()) / cols)
	var head := 40 if title != "" else 0
	_vp = SubViewport.new()
	_vp.size = Vector2i(cols * cell, rows * ch + head)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.disable_3d = true
	root.add_child(_vp)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1)
	bg.size = Vector2(_vp.size)
	_vp.add_child(bg)
	if title != "":
		var tl := Label.new()
		tl.text = title
		tl.position = Vector2(8, 6)
		tl.add_theme_font_size_override("font_size", 22)
		_vp.add_child(tl)
	for i in pairs.size():
		var path := dir.path_join("%s_d%d_t%d.png" % [pairs[i][0], pairs[i][1], tilt])
		var at := Vector2((i % cols) * cell, (i / cols) * ch + head)
		var img := Image.load_from_file(path)
		if img == null:
			continue
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(img)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.size = Vector2(cell - 2, ch - 2)
		tr.position = at + Vector2(1, 1)
		_vp.add_child(tr)
		var l := Label.new()
		l.text = "%s  %d m" % [pairs[i][0], pairs[i][1]]
		l.position = at + Vector2(8, 4)
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 6)
		_vp.add_child(l)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 6:
		_vp.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
