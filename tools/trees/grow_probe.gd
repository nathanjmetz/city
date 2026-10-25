extends SceneTree
## Grows every kind of tree and prints what came out next to the reference
## (docs/trees.md): height, crown width and trunk thickness at 10, 30 and
## 60 years, how many nodes, and how long it took.
## Run: godot --headless -s tools/trees/grow_probe.gd


func _init() -> void:
	for sp in TreeKinds.count():
		var t := Time.get_ticks_msec()
		var g := TreeGrower.grown(sp, 1)
		var ms := Time.get_ticks_msec() - t
		var line := "%-18s nodes %5d %5d ms |" % [TreeKinds.kind(sp).name, g.pos.size(), ms]
		for age in [10.0, 30.0, 60.0]:
			var m := TreeGrower.measure(g.at_age(age))
			line += " %d: h %.1f/%.1f w %.1f/%.1f dbh %.0f/%.0f |" % [age, m.height, TreeKinds.height(sp, age), m.width,
				TreeKinds.height(sp, age) * TreeKinds.wide_at(sp, age), m.dbh_cm, TreeKinds.dbh(sp, age)]
		print(line)
		# What drawing it costs at 40 years: triangles and build time per level.
		var cost := "    at 40:"
		for lod in [TreeMesher.Lod.FULL, TreeMesher.Lod.LIGHT]:
			var t0 := Time.get_ticks_usec()
			var tree := g.at_age(40.0)
			var t1 := Time.get_ticks_usec()
			var parts := TreeMesher.build(sp, tree, lod, 1)
			var t2 := Time.get_ticks_usec()
			var bark_tris: int = parts[0][Mesh.ARRAY_INDEX].size() / 3 if not parts[0].is_empty() else 0
			var leaf_tris: int = parts[1][Mesh.ARRAY_INDEX].size() / 3 if not parts[1].is_empty() else 0
			cost += " %s bark %d leaf %d tris (shape %.1f ms, mesh %.1f ms) |" % [["full", "light"][lod], bark_tris, leaf_tris,
				(t1 - t0) / 1000.0, (t2 - t1) / 1000.0]
		print(cost)
	quit()
