extends SceneTree
## Fuller towns (critic 2026-10-26: "towns look bare for years ... no
## street trees on the parkways ... most roofs are the same mid-grey").
## Street trees stand down the middle of the parkway about every 40 ft,
## clear of driveways, mailboxes, streetlights, bus stops and corners'
## sight lines, on both streets of a corner lot; yard trees go in at
## nursery size; roofs come in the mix a Grant County street shows.
## Run: godot --headless -s tests/test_street_trees.gd

var sim := CitySim.new()
var view: BuildingView
var _frames := 0
var _failed := false
var _phase := 0
var _at := 0
var _before := 0


func _initialize() -> void:
	_builder()
	_roofs()
	sim.economy.money = 900_000_000
	PerfTown.build(sim, "3")
	view = BuildingView.new()
	root.add_child(view)
	view.setup(sim)


## One lot at a time, as HouseBuilder plants it.
func _builder() -> void:
	var wrong := []
	var lots := 0
	var planted := 0
	var two := 0
	var wide := 0
	for i in 240:
		var width: float = [12.0, 15.0, 18.0, 21.0, 24.0, 28.0][i % 6]
		var lot := {"width": width, "depth": [30.0, 36.0, 44.0][i % 3], "at": Vector2((i % 16) * 90.0, (i / 16) * 130.0),
			"mail_x": width * 0.3 * (1.0 if i % 2 == 0 else -1.0)}
		var built: Array = HouseBuilder.build(i * 7919 + 13, 3.9, lot, [0, 1, 2][i % 3])
		var street := (built[2] as Array).filter(func(t): return (t[0] as Vector3).z < 0.0)
		lots += 1
		planted += street.size()
		if width >= 21.0:
			wide += 1
			two += 1 if street.size() >= 2 else 0
		var xs := []
		for t in street:
			var p: Vector3 = t[0]
			xs.append(p.x)
			if absf(p.z + 2.7) > 0.01:
				wrong.append("lot %d: a street tree %.1f m out, not mid-parkway" % [i, -p.z])
			if absf(p.x) > width * 0.5 - HouseBuilder.STREET_TREE_SIDE + 0.01:
				wrong.append("lot %d: a street tree %.1f m from the side line" % [i, width * 0.5 - absf(p.x)])
			if absf(p.x - float(lot.mail_x)) < 1.59:
				wrong.append("lot %d: a street tree on the mailbox" % i)
			if t[1] in [TreeField.Species.SPRUCE, TreeField.Species.CRABAPPLE]:
				wrong.append("lot %d: a %s in the parkway" % [i, TreeField.Species.keys()[t[1]]])
		xs.sort()
		for k in range(1, xs.size()):
			if xs[k] - xs[k - 1] < HouseBuilder.STREET_TREE_GAP * 0.6 - 0.01:
				wrong.append("lot %d: street trees %.1f m apart" % [i, xs[k] - xs[k - 1]])
		# Clear of the drive the house paints, by 2 m (6-7 ft) or more.
		for x in xs:
			for dx in [-1.9, -1.0, 0.0, 1.0, 1.9]:
				if _on_drive(built[1], Vector2(x + dx, -2.7)):
					wrong.append("lot %d: a street tree %.0f m from the drive" % [i, absf(dx)])
					break
	_check(wrong.is_empty(), "street trees stand mid-parkway, off drives, mailboxes and side lines, 7.5 m apart or more %s" % [wrong.slice(0, 4)])
	_check(planted > lots * 1.05 and two > wide * 0.3,
		"most homes have a street tree, wide lots two (%d on %d lots; %d of %d wide lots have two)" % [planted, lots, two, wide])
	# A flag lot's front is its drive, and a country road has no parkway.
	var none := 0
	for i in 40:
		var flag := i % 2 == 0
		var built: Array = HouseBuilder.build(i * 31 + 7, 11.9 if flag else 3.3, {"width": 20.0, "depth": 36.0, "pad": 8.0 if flag else 0.0})
		none += (built[2] as Array).filter(func(t): return (t[0] as Vector3).z < 0.0).size()
	_check(none == 0, "no street trees on flag lots or along country roads (%d)" % none)


## True when a spot (lot x/z) is on the paving the lot drew (as in
## test_house_lots).
func _on_drive(flat: ArrayMesh, p: Vector2) -> bool:
	if flat.get_surface_count() == 0:
		return false
	var a := flat.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = a[Mesh.ARRAY_COLOR]
	for i in range(0, v.size(), 3):
		if c[i].a > 0.01:
			continue
		var tri := PackedVector2Array([Vector2(v[i].x, v[i].z), Vector2(v[i + 1].x, v[i + 1].z), Vector2(v[i + 2].x, v[i + 2].z)])
		if Geometry2D.is_point_in_polygon(p, tri):
			return true
	return false


## The plan book's paint schemes: roofs in a realistic mix, not one grey.
func _roofs() -> void:
	var kinds := {"grey": 0, "charcoal": 0, "brown": 0, "colour": 0}
	var colours := {}
	var n := 0
	for era in ["prewar", "postwar", "recent"]:
		var b := HouseBuilder.new()
		b.rng = RandomNumberGenerator.new()
		b.era = era
		for scheme in HouseBuilder.SCHEMES:
			var c: Color = b._paint(scheme).roof
			colours[c.to_html(false)] = true
			n += 1
			if c.get_luminance() < 0.3:
				kinds.charcoal += 1
			elif c.r - c.b > 0.07 and c.g > c.b:
				kinds.brown += 1
			elif absf(c.r - c.b) < 0.05 and absf(c.g - c.b) < 0.05:
				kinds.grey += 1
			else:
				kinds.colour += 1
	var most := 0
	for k in kinds:
		most = maxi(most, kinds[k])
	_check(colours.size() >= 12 and kinds.charcoal > 0 and kinds.brown > 0 and kinds.grey > 0 and most < n * 0.6,
		"roofs come in greys, charcoals, browns and the odd colour, none more than 60%% (%d colours, %s)" % [colours.size(), kinds])


func _process(_d: float) -> bool:
	_frames += 1
	if _frames > 4000:
		_check(false, "the town settles")
		print("TESTS FAILED")
		quit(1)
		return true
	if _frames < 5 or not view.idle():
		return false
	if _phase == 0:
		_town()
		# A new street across the middle of a block: its corners and new
		# streetlights take back the street trees in their way.
		_before = view.street_trees
		var x := _block_middle()
		sim.apply({"type": "build_road", "start": [x.x, x.y - 60.0], "ctrl": [x.x, x.y], "end": [x.x, x.y + 60.0], "road": 0})
		_phase = 1
		_at = _frames
		return false
	if _frames - _at < 20:
		return false
	_check(_clear_of_corners().is_empty(), "a new street's corners are cleared of street trees too %s" % [_clear_of_corners().slice(0, 3)])
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)
	return true


## The town's street trees, where the view filed them.
func _street_trees() -> Array:
	var out := []
	for key in view._planted:
		var lot: PackedVector2Array = sim.lots[key].corners if sim.lots.has(key) else PackedVector2Array()
		for t in view._trees._trees.get(key, []):
			var o: Vector3 = (t[0] as Transform3D).origin
			# Out past the lot lines: in a parkway.
			if lot.size() >= 3 and not Geometry2D.is_point_in_polygon(Vector2(o.x, o.z), lot):
				out.append([key, Vector2(o.x, o.z)])
	return out


func _town() -> void:
	var trees := _street_trees()
	var homes := 0
	for key in sim.buildings:
		if int(sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL and sim.lots.has(key):
			homes += 1
	_check(trees.size() == view.street_trees and trees.size() > homes * 0.8,
		"a built-out town's homes have street trees (%d for %d homes)" % [trees.size(), homes])
	# Down the middle of a parkway: the curb plus half the strip out from
	# the nearest street's edge.
	var off := []
	var pieces := StreetLights._pieces(sim.network)
	for t in trees:
		var q: Vector2 = t[1]
		var best := INF
		var hw := 0.0
		for piece in pieces.get(Vector2i(floori(q.x / StreetLights.PIECE_CELL), floori(q.y / StreetLights.PIECE_CELL)), []):
			var d := Geometry2D.get_closest_point_to_segment(q, piece[0], piece[1]).distance_to(q)
			if d < best:
				best = d
				hw = piece[3]
		var want := hw + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH * 0.5
		if absf(best - want) > 0.35:
			off.append("%s %.1f m from the street, not %.1f" % [t[0], best, want])
	_check(off.is_empty(), "every street tree stands mid-parkway %s" % [off.slice(0, 3)])
	var near_lamp := []
	for l in StreetLights.place(sim.network):
		for t in trees:
			if (t[1] as Vector2).distance_to(Vector2(l[1].x, l[1].z)) < BuildingView.LAMP_CLEAR - 0.01:
				near_lamp.append(t[0])
	_check(near_lamp.is_empty(), "street trees stand clear of the streetlights %s" % [near_lamp.slice(0, 3)])
	var near_mail := []
	for t in trees:
		if (t[1] as Vector2).distance_to(view._mailbox_at(t[0])) < BuildingView.MAILBOX_CLEAR - 0.01:
			near_mail.append(t[0])
	_check(near_mail.is_empty(), "and the mailboxes %s" % [near_mail.slice(0, 3)])
	_check(_clear_of_corners().is_empty(), "and the corners' sight lines %s" % [_clear_of_corners().slice(0, 3)])
	# Corner lots have them down the side street as well.
	var sides := 0
	var corners := 0
	for key in view._planted:
		if sim.lots.has(key) and sim.lots[key].get("corner", false) and int(sim.buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL:
			corners += 1
			sides += 1 if not view._side_trees(key).is_empty() else 0
	_check(corners > 0 and sides >= corners * 0.8, "corner lots have street trees down the side street (%d of %d)" % [sides, corners])
	# Planted at nursery size: a shade tree 12-14 ft the day it goes in.
	var small := []
	TreeField.now_tick = sim.tick_count
	for key in view._planted:
		if int(sim.buildings[key].zone) != ZoneMap.Zone.RESIDENTIAL:
			continue
		for t in view._trees._trees.get(key, []):
			var r := TreeField.resolve(t)
			var h: float = (r[0] as Transform3D).basis.get_scale().y * TreeKinds.height(r[1], TreeKinds.REF_AGE)
			if r[1] not in [TreeField.Species.SPRUCE, TreeField.Species.CRABAPPLE] and h < 2.6:
				small.append("%s %.1f m" % [TreeField.Species.keys()[r[1]], h])
	_check(small.is_empty(), "new yard and street trees go in at nursery size, never saplings %s" % [small.slice(0, 3)])


## Street trees inside a junction's sight-line clearance.
func _clear_of_corners() -> Array:
	var bad := []
	var trees := _street_trees()
	for n in sim.network.nodes:
		var segs := sim.network.segments_at(n)
		if segs.size() < 3:
			continue
		var hw := 0.0
		for id in segs:
			hw = maxf(hw, RoadStyle.half_width(sim.network.segments[id].type))
		var p: Vector3 = sim.network.nodes[n]
		for t in trees:
			if (t[1] as Vector2).distance_to(Vector2(p.x, p.z)) < hw + BuildingView.SIGHT_CLEAR - 0.01:
				bad.append("%s at %s" % [t[0], t[1]])
	return bad


## The middle of a block of homes (between two streets).
func _block_middle() -> Vector2:
	var best := Vector2.ZERO
	var most := -1
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		if not sim.buildings.has(key) or int(sim.buildings[key].zone) != ZoneMap.Zone.RESIDENTIAL:
			continue
		var at := Vector2(lot.front.x, lot.front.z)
		var near := 0
		for k2 in sim.lots:
			var l2: Dictionary = sim.lots[k2]
			if Vector2(l2.front.x, l2.front.z).distance_to(at) < 40.0:
				near += 1
		if near > most:
			most = near
			best = at
	return best


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
