extends SceneTree
## Trees at every distance (TreeLook, TreeField, FarWoods, GrownTrees): the
## wild woods are drawn out toward the horizon, each version of a tree
## stands at the same spot at the same size as the next, every hand-over
## leaves each tree drawn exactly once, and a camera hovering at a
## hand-over never flips a tree back and forth between versions.
## Nathan (2026-10-26): "As I move forward, trees swell up out of the
## ground ... Then as I move around the trees, skip and flutter because
## they're changing drawing types as I'm moving."
## Run: godot --headless -s tests/test_tree_lod.gd

var _failed := false


func _init() -> void:
	_light_fits_full()
	_far_matches_cards()
	_grown_matches_cards()
	_lit_alike()
	_dappled_shadows()
	_no_swelling()
	_shares()
	_jitter()
	_chunk_versions()
	_grown_bands_trail()
	_reaches()
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


## The light cards are fitted to the full cards' crown: the hand-over
## between them neither swells nor shrinks a tree.
func _light_fits_full() -> void:
	var worst := 0.0
	for sp in TreeKinds.count():
		var full := TreeField.crown_bounds(sp)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		var a: Array = TreeField.tree_mesh(sp, true).surface_get_arrays(0)
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for i in v.size():
			if uv[i].x < -0.5:
				continue  # the trunk riding in the leaf surface
			lo = lo.min(v[i])
			hi = hi.max(v[i])
		var half_full := maxf(maxf(absf(full.position.x), absf(full.end.x)), maxf(absf(full.position.z), absf(full.end.z)))
		var half_light := maxf(maxf(absf(lo.x), absf(hi.x)), maxf(absf(lo.z), absf(hi.z)))
		worst = maxf(worst, maxf(absf(hi.y - full.end.y) / full.end.y, absf(half_light - half_full) / half_full))
		worst = maxf(worst, absf(lo.y - full.position.y) / full.end.y)
	_check(worst < 0.02, "every kind's light cards fill the same crown as its full cards (worst %.1f%% off)" % (worst * 100.0))


## The far woods draw exactly WildView's trees: the same spot, size, kind
## and colour as the cards (TreeField.resolve), and no brush.
func _far_matches_cards() -> void:
	var far := FarWoods.new()
	var c := Vector2i(-7, 3)
	var trees := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 40:
		var p := Vector3((c.x + rng.randf()) * Vegetation.CHUNK, rng.randf_range(-5.0, 30.0), (c.y + rng.randf()) * Vegetation.CHUNK)
		var sp := rng.randi() % TreeKinds.count()
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.3, 1.3)), p)
		var facts := {"age": rng.randf_range(5.0, 90.0)} if i % 5 else {"shrub": true}
		trees.append([xf, sp, Color(0.3, 0.4, 0.15), facts])
	far.set_chunk(c, trees)
	var drawn := far.chunk_trees(c)
	var want := []
	for t in trees:
		if not t[3].has("shrub"):
			var r := TreeField.resolve(t)
			want.append([r[0], TreeField.custom_of(r[2], r[1], true)])
	var same := drawn.size() == want.size()
	var worst := 0.0
	for i in mini(drawn.size(), want.size()):
		var a: Transform3D = drawn[i][0]
		var b: Transform3D = want[i][0]
		worst = maxf(worst, a.origin.distance_to(b.origin))
		same = same and a.basis.is_equal_approx(b.basis) and (drawn[i][1] as Color).is_equal_approx(want[i][1])
	_check(same and worst < 0.01 and far.tree_count() == want.size(),
		"the far woods stand each tree where the cards do (worst %.3f m), at its size and colour, and leave out brush" % worst)
	far.drop_chunk(c)
	_check(far.tree_count() == 0 and not far.has_chunk(c), "a dropped chunk's far trees are gone")
	far.free()
	# Each kind's quad is the size of its card crown.
	var boxes := FarWoods.crown_boxes()
	var ok := true
	for sp in TreeKinds.count():
		var b := TreeField.crown_bounds(sp)
		ok = ok and absf(boxes[sp].x - (b.position.y + b.size.y * 0.5)) < 0.01 \
			and absf(boxes[sp].z - b.size.y * 0.5 * FarWoods.FILL) < 0.01 and boxes[sp].w > 0.0 and boxes[sp].w < 0.2
	_check(ok, "each kind's far quad stands at its card crown's height and size, with a thin trunk")


## A grown tree and the card it hands over to stand about as tall: the
## same tree, not a bigger or smaller one.
func _grown_matches_cards() -> void:
	var worst := 0.0
	var worst_kind := ""
	for sp in TreeKinds.count():
		var card_top := TreeField.crown_bounds(sp).end.y
		var g := TreeGrower.grown(sp, 1)
		for age in [15.0, 40.0, 80.0]:
			var b := GrownTrees.bucket(age)
			var s: float = TreeKinds.size_at(sp, age) / GrownTrees.bucket_size(sp, b)
			var leaves: PackedVector3Array = TreeMesher.build(sp, g.at_age(GrownTrees.BUCKETS[b]), TreeMesher.Lod.LIGHT, 1)[1][Mesh.ARRAY_VERTEX]
			var top := -INF
			for v in leaves:
				top = maxf(top, v.y)
			var off := absf(top * s - card_top * TreeKinds.size_at(sp, age)) / (card_top * TreeKinds.size_at(sp, age))
			if off > worst:
				worst = off
				worst_kind = "%s at %d" % [TreeKinds.kind(sp).name, age]
	_check(worst < 0.2, "grown trees and their cards stand within 20%% of the same height (worst %.0f%%, %s)" % [worst * 100.0, worst_kind])


## A grown tree and the cards standing in for it are shaded alike: the
## cards carry the same height up the crown and cluster hue as the grown
## tree's (the leaf shader lights a crown's top and drifts its clusters'
## hue by them), so a near tree is not brighter and yellower than the same
## tree farther off. The look critic (2026-10-29): "near trees are acid
## yellow-green and look lit from inside."
func _lit_alike() -> void:
	var worst := 0.0
	var worst_kind := ""
	for sp in TreeKinds.count():
		var g := TreeGrower.grown(sp, 1)
		var grown: PackedColorArray = TreeMesher.build(sp, g.at_age(GrownTrees.BUCKETS[7]), TreeMesher.Lod.FULL, 1)[1][Mesh.ARRAY_COLOR]
		for far in [false, true]:
			var a: Array = TreeField.tree_mesh(sp, far).surface_get_arrays(0)
			var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			var cards := PackedColorArray()
			for i in uv.size():
				if uv[i].x > -0.5:  # not the trunk riding in the leaf surface
					cards.append(a[Mesh.ARRAY_COLOR][i])
			var gm := _mean_colour(grown)
			var cm := _mean_colour(cards)
			# A conifer's grown cards crowd its wide lower tiers more than
			# the cards' even tiers do: its height up the crown may differ more.
			var off := maxf(absf(gm.g - cm.g) * (0.8 if TreeKinds.kind(sp).evergreen else 1.0), absf(gm.b - cm.b))
			if off > worst:
				worst = off
				worst_kind = "%s%s: grown top %.2f hue %.2f, cards %.2f, %.2f" % [TreeKinds.kind(sp).name, " (light)" if far else "",
					gm.g, gm.b, cm.g, cm.b]
	_check(worst < 0.2, "each kind's cards are lit like its grown tree: the same height up the crown and hue drift (worst %.2f, %s)" % [
		worst, worst_kind])
	_check("LEAF_INNER" in TreeLook.LEAF_SHADER and not "* mix(0.85, 1.2, tp) * 2.0" in TreeLook.LEAF_SHADER,
		"the leaf shader shades the crown's inside and underside, not a glow from within")


## A tree's shadow is dappled, not a solid hole: in the sun's shadow map
## every leaf lets the sun through the crown's gaps, a share OPEN_CORE of
## it through the middle and OPEN_RIM round the rim (the look critic,
## 2026-10-29: "tree shadows are near-black holes", 22,29,45 on a road lit at
## 111,103,101). The gaps' cut lets through the share it says, and the
## shader's numbers are the ones checked here.
func _dappled_shadows() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worst := 0.0
	var n := 20000
	var vals := PackedFloat32Array()
	for i in n:
		vals.append(TreeLook.fleck_value(Vector2(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-3000.0, 3000.0))))
	for open in [0.09, TreeLook.OPEN_CORE, 0.3, TreeLook.OPEN_RIM, 0.7]:
		var cut := TreeLook.fleck_cut(open)
		var through := 0
		for v in vals:
			if v >= cut:
				through += 1
		worst = maxf(worst, absf(float(through) / n - open))
	_check(worst < 0.03, "the shadow's gaps let through the share of sun they say (worst %.3f off)" % worst)
	var code := TreeLook.LEAF_SHADER
	_check(("OPEN_CORE = %s;" % TreeLook.OPEN_CORE) in code and ("OPEN_RIM = %s;" % TreeLook.OPEN_RIM) in code
		and ("SHADOW_FADE = %s;" % TreeLook.SHADOW_FADE) in code and "alpha *= sun_through(" in code
		and "fleck_noise(p * 2.5) * 0.6 + fleck_noise(p * 6.0 + 17.0) * 0.4" in code,
		"the leaf shader lets the sun through in the shadow map, with the numbers checked here")
	# Gaps a few tenths of a metre across: flecks the size real ones are,
	# big enough for the shadow map to show near the camera.
	var flips := 0
	var steps := 0
	for i in 400:
		var p := Vector2(rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0))
		var was := TreeLook.fleck_value(p) >= TreeLook.fleck_cut(TreeLook.OPEN_RIM)
		for k in 20:
			p.x += 0.05
			var now := TreeLook.fleck_value(p) >= TreeLook.fleck_cut(TreeLook.OPEN_RIM)
			flips += 1 if now != was else 0
			was = now
			steps += 1
	var run := 0.05 * steps / maxf(flips, 1.0)
	_check(run > 0.1 and run < 0.6, "the gaps and leaf clusters run about %.2f m across" % run)


static func _mean_colour(cols: PackedColorArray) -> Color:
	var s := Color(0, 0, 0, 0)
	for c in cols:
		s += c
	return s / maxf(cols.size(), 1.0)


## Nothing scales a tree up out of the ground any more: the old fade shrank
## trees toward the edge of the woods drawn.
func _no_swelling() -> void:
	_check(not "mix(0.4, 1.0, fade)" in TreeLook.LEAF_SHADER and not "VERTEX *= fade" in TreeLook.CARD_BARK_SHADER
		and "step(0.0001, keep.y - keep.x)" in TreeLook.LEAF_SHADER,
		"trees are handed over in place, never shrunk or swollen at the edge of the woods")


## Sets the trees' camera and reaches as WildView would.
func _view(eye: Vector3, reach: float, far_r: float) -> void:
	TreeLook.wild_fade = Vector4(eye.x, eye.z, reach, 30.0)
	TreeLook.far_reach = far_r
	TreeLook.brush_reach = 300.0
	TreeLook.set_eye(eye, true)


## Every tree is drawn by exactly one version at every pixel: the shares of
## the full cards, light cards and far woods never overlap and add up to
## the whole, from the camera out to the far woods' reach.
func _shares() -> void:
	var eye := Vector3(10.0, 30.0, -20.0)
	var ok := true
	var drawn_far := 0
	var gone := 0
	var bad := ""
	for reach in [420.0, 700.0, 1600.0]:
		_view(eye, reach, 3500.0)
		for i in 4000:
			var d := float(i)
			var a := float(i) * 2.399
			var o := eye + Vector3(cos(a) * d, -30.0 + fmod(i * 7.3, 20.0), sin(a) * d)
			var full := TreeLook.keep_share(o, false, false)
			var light := TreeLook.keep_share(o, true, false)
			var far := TreeLook.keep_share(o, false, true)
			var sum := (full.y - full.x) + (light.y - light.x) + (far.y - far.x)
			var tidy := full.x <= full.y and light.x <= light.y and far.x <= far.y \
				and is_equal_approx(far.y, light.x) and is_equal_approx(light.y, full.x)
			if sum < 0.001:
				gone += 1
				tidy = tidy and d > 3500.0 * 0.85
			elif not is_equal_approx(sum, 1.0):
				tidy = false
			if far.y > far.x:
				drawn_far += 1
				tidy = tidy and d > reach * 0.5
			if not tidy and bad == "":
				bad = "reach %d, %d m: full %s light %s far %s" % [reach, d, full, light, far]
			ok = ok and tidy
	_check(ok, "full cards, light cards and far woods share each tree's pixels exactly, out to the far woods' reach %s" % bad)
	_check(drawn_far > 1000 and gone > 0, "past the cards the far woods draw the trees (%d), which drop out only near their own reach (%d)" % [drawn_far, gone])


## A camera hovering at a hand-over (moving half a metre either way) moves
## each tree's shares only a little: no tree jumps from one version to
## another and back.
func _jitter() -> void:
	var worst := 0.0
	for reach in [420.0, 700.0]:
		for i in 3000:
			var d := 100.0 + float(i) * 0.25
			var o := Vector3(d, 0.0, 3.0)
			var shares := []
			for step in [-0.5, 0.0, 0.5]:
				_view(Vector3(step, 30.0, 0.0), reach, 3500.0)
				shares.append([TreeLook.keep_share(o, false, false), TreeLook.keep_share(o, true, false), TreeLook.keep_share(o, false, true)])
			for k in 2:
				for v in 3:
					var a: Vector2 = shares[k][v]
					var b: Vector2 = shares[k + 1][v]
					worst = maxf(worst, maxf(absf(a.x - b.x), absf(a.y - b.y)))
	_check(worst < 0.03, "half a metre of camera movement moves any tree's share of a version by at most %.3f (no flipping)" % worst)


## A chunk draws every version some tree in it is drawn with (so no tree is
## left out), with the camera moving to and fro across each hand-over.
func _chunk_versions() -> void:
	var missing := 0
	var checked := 0
	var near_d := TreeLook.card_near()
	var c := Vector2i(2, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var trees := []
	for i in 300:
		trees.append(Vector3((c.x + rng.randf()) * TreeField.CHUNK, rng.randf_range(-20.0, 20.0), (c.y + rng.randf()) * TreeField.CHUNK))
	for reach in [420.0, 700.0]:
		for x in range(-1200, 600, 3):
			# The versions are worked out for one spot and kept until the
			# camera has moved SHOW_MOVE from it.
			var at := Vector3(float(x) + rng.randf_range(-1.5, 1.5), 40.0, 100.0)
			var mask := TreeField.chunk_versions(c, Vector2(at.x, at.z), at.y, near_d, Vector2(at.x, at.z), reach)
			var eye := at + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.3), rng.randf_range(-1.0, 1.0)).limit_length(1.0) \
				* TreeField.SHOW_MOVE * 0.99
			_view(eye, reach, 3500.0)
			for o in trees:
				var full := TreeLook.keep_share(o, false, false)
				var light := TreeLook.keep_share(o, true, false)
				checked += 1
				if (full.y > full.x and (mask & 1) == 0) or (light.y > light.x and (mask & 2) == 0):
					missing += 1
	_check(missing == 0, "each chunk draws every version its trees need, wherever the camera is (%d of %d trees left out)" % [missing, checked])


## The grown trees' bands follow the camera, trailing it only by as much as
## the lookup's slack, and move on smoothly when a lookup lands: a fast
## camera no longer turns every grown tree back into a card.
func _grown_bands_trail() -> void:
	# A camera flying at 180 m/s (60 frames a second); each lookup takes ten
	# frames, aimed where the camera will be when it lands.
	var vel := Vector3(180.0, 0.0, 0.0)
	var centre := Vector3.ZERO
	var aimed := Vector3.ZERO
	var cam := Vector3.ZERO
	var last := 0.0
	var worst_jump := 0.0
	var behind := true
	var within := true
	var off := 0.0
	for frame in 600:
		cam += vel / 60.0
		if frame % 10 == 9:
			centre = aimed  # the lookup lands
			aimed = GrownTrees.scan_point(cam, vel, 10.0 / 60.0)  # and the next begins
		var z := GrownTrees.zone_point(cam, centre)
		within = within and z.distance_to(centre) <= GrownTrees.ZONE_SLACK + 0.001
		behind = behind and z.x >= last - 0.001
		if frame > 20:
			worst_jump = maxf(worst_jump, z.x - last)
			off = maxf(off, cam.distance_to(z))
		last = z.x
	_check(within and behind and worst_jump < 6.0 and off < 5.0,
		"at 180 m/s the grown trees' bands keep within %.1f m of the camera, only ever move forward, at most %.1f m a frame" % [off, worst_jump])
	_check(GrownTrees.zone_point(Vector3(5, 0, 5), Vector3.ZERO) == Vector3(5, 0, 5),
		"a camera within the lookup's slack is the bands' own centre")


## The far woods reach well past the cards on every tier, further on
## better ones, and the browser keeps them nearer.
func _reaches() -> void:
	var ok := true
	var last := 0.0
	for t in GraphicsQuality.BUDGETS.size():
		var b := GraphicsQuality.budget_for(t)
		var web := GraphicsQuality.budget_for(t, true)
		ok = ok and b.far_woods >= last and b.far_woods >= WildView.MAX_RADIUS and web.far_woods <= GraphicsQuality.BROWSER_FAR_WOODS
		last = b.far_woods
	_check(ok, "every tier draws far woods past the cards' widest reach, more on better tiers, the browser at most %d m" % GraphicsQuality.BROWSER_FAR_WOODS)
	_check(WildView.far_reach(WildView.MAX_RADIUS) >= WildView.MAX_RADIUS * 1.4, "the far woods always reach well past the cards")


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
