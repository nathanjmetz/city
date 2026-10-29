extends SceneTree
## Homes' growth stages draw on their lots: a house built on out back
## (Home with addition), and duplexes and fourplexes of every era, with
## their parking where SiteLayout says it is.

var failed := false


func _init() -> void:
	# Load every builder first: a helper named like another builder's
	# breaks the chain silently.
	for f in DirAccess.get_files_at("res://scripts/art"):
		if f.ends_with(".gd"):
			load("res://scripts/art/" + f)
	var grew := 0
	var tried := 0
	for s in 24:
		var lot := {"width": 22.0, "depth": 45.0, "era": ["prewar", "postwar", "recent"][s % 3]}
		HouseBuilder.build(300 + s, 3.9, lot, 2)
		var before := HouseBuilder.last_masses.size()
		HouseBuilder.grown = 1
		HouseBuilder.build(300 + s, 3.9, lot, 2)
		HouseBuilder.grown = 0
		tried += 1
		if HouseBuilder.last_masses.size() > before:
			grew += 1
		_check(_inside(HouseBuilder.last_masses, 11.0, 45.0), "addition %d stays inside its lot" % s)
	_check(grew >= tried * 0.6, "most owners build on out back (%d of %d)" % [grew, tried])
	var styles := {}
	for level in [0, 1]:
		for era in ["prewar", "postwar", "recent"]:
			for w in [14.0, 16.0, 18.0, 20.0, 24.0, 30.0]:
				for s in 3:
					var lot := {"width": w, "depth": 40.0, "era": era}
					var out := DuplexBuilder.build(s, 3.9, lot, level)
					var plan := DuplexBuilder.plan_info(s, lot, level)
					styles[plan.style] = true
					_check(out.size() == 3 and _inside(HouseBuilder.last_masses, w * 0.5, 40.0),
						"%s on a %d m %s lot fits it" % [plan.style, w, era])
					var ok := true
					for sp in plan.spots:
						ok = ok and absf(sp.pos.x) < w * 0.5 - 1.0 and sp.pos.y > 0.0 and sp.pos.y < 40.0
					_check(ok, "%s on a %d m %s lot parks inside it" % [plan.style, w, era])
					var lay := SiteLayout.for_building(ZoneMap.Zone.RESIDENTIAL, 9, {"width": w, "depth": 40.0}, 0, "duplex", level)
					_check(lay.has("spots") and lay.has("door"), "SiteLayout lays out a duplex")
	# Row homes of each kind fit their lots, two storeys and three.
	for kind in ["townhomes", "mansard", "flats", "row"]:
		MetroBuilder.force_row = kind
		for w in [15.0, 22.0, 30.0, 45.0]:
			for storeys in [2, 3]:
				var units := maxi(2, floori(w / 7.5))
				var out := MetroBuilder.build_row(5, 3.9, {"width": w, "depth": 40.0}, units, storeys)
				_check(out.size() >= 3 and _inside(HouseBuilder.last_masses, w * 0.5, 40.0),
					"%s row of %d on a %d m lot fits it" % [kind, units, w])
		MetroBuilder.force_row = ""
	MetroBuilder.force_row = "garden"
	for era in ["postwar", "recent"]:
		for w in [24.0, 30.0, 40.0, 60.0]:
			for storeys in [2, 3]:
				var out := MetroBuilder.build_apartments(3, 3.9, {"width": w, "depth": 50.0, "era": era}, storeys)
				_check(out.size() >= 3 and _inside(HouseBuilder.last_masses, w * 0.5, 50.0),
					"%s garden apartments on a %d m lot fit it" % [era, w])
	MetroBuilder.force_row = ""
	# A commercial block across two storefront lots.
	for era in ["prewar", "postwar"]:
		for w in [24.0, 30.0, 34.0]:
			for storeys in [3, 4]:
				var out := MainBlock.build(7, 3.9, {"width": w, "depth": 45.0, "era": era}, storeys)
				_check(out.size() >= 3 and _inside(HouseBuilder.last_masses, w * 0.5, 45.0),
					"%s commercial block on a %d m lot fits it" % [era, w])
	# Corner stores, a shop's first stage: on a corner (either side) and
	# mid-block, prewar at the sidewalk with no lot, postwar with stalls;
	# what SiteLayout reads from its dry run is what's drawn.
	var corners := 0
	for era in ["prewar", "postwar"]:
		for w in [10.0, 13.0, 16.0, 22.0]:
			for side in [-1.0, 0.0, 1.0]:
				for s in 4:
					var lot := {"width": w, "depth": 36.0, "era": era, "corner": side != 0.0, "side": side}
					CommercialBuilder.force_shop = "corner"
					var out := DenseBuilder.build_retail(40 + s, 3.9, lot, {}, 0)
					var masses: Array = HouseBuilder.last_masses
					var plan := DenseBuilder.site_plan(40 + s, lot, false, 0)
					CommercialBuilder.force_shop = ""
					var what := "%s corner store on a %d m lot (side %d)" % [era, w, side]
					_check(out.size() >= 3 and _inside(masses, w * 0.5, 36.0), what + " fits it")
					_check(plan.main_street == (era == "prewar"), what + (" parks at the curb" if era == "prewar" else " has its own stalls"))
					var ok := true
					for st in plan.stalls:
						ok = ok and absf(st[0].x) < w * 0.5 and st[0].y > 0.0 and st[0].y < 36.0
					_check(ok, what + " parks inside it")
					_check(absf(plan.door.x) < w * 0.5 and plan.door.y >= 0.0, what + " has its door on the lot")
	# Only the first stage, of the eras that built them, is ever one.
	for s in 300:
		for era in ["prewar", "postwar", "recent"]:
			var lot := {"width": 16.0, "depth": 36.0, "era": era}
			var b0 := DenseBuilder._start(s, lot)
			b0.small_store = true
			var b1 := DenseBuilder._start(s, lot)
			_check(b1._shop_kind(lot) != "corner", "a grown shop is no corner store")
			if b0._shop_kind(lot) == "corner":
				corners += 1
				_check(era != "recent", "a recent street builds no corner store")
	_check(corners > 250 and corners < 450, "about 70%% prewar and 45%% postwar first shops are corner stores (%d of 600)" % corners)
	# A corner lot knows which way its side street lies.
	var net := RoadNetwork.new()
	net.build_road(Vector3(-60, 0, 0), Vector3(0, 0, 0), Vector3(60, 0, 0))  # its own street, along x
	net.build_road(Vector3(20, 0, -60), Vector3(20, 0, 0), Vector3(20, 0, 60))  # the side street
	var corner_lot := {"corner": true, "width": 16.0, "depth": 36.0, "front": Vector3(4.0, 0, 9.0), "normal": Vector3(0, 0, 1),
		"seg": net.find_segment_near(Vector3(0, 0, 0), 2.0).seg}
	var toward := SiteLayout.corner_side(net, corner_lot)
	_check(toward != 0.0 and (SiteLayout.world(corner_lot, Vector2(toward * 8.0, 0.0)).x > 4.0), "the side street is found on the right side")
	corner_lot.corner = false
	_check(SiteLayout.corner_side(net, corner_lot) == 0.0, "a lot mid-block has no side street")
	_check(styles.size() == 5, "every kind of duplex and the fourplex come up (%s)" % str(styles.keys()))
	print("FAILED" if failed else "ALL PASSED")
	quit(1 if failed else 0)


## Every footprint within half-width `half` across and `depth` back.
func _inside(masses: Array, half: float, depth: float) -> bool:
	for m: Rect2 in masses:
		if m.position.x < -half - 0.05 or m.end.x > half + 0.05 or m.position.y < -0.05 or m.end.y > depth:
			return false
	return true


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
	failed = failed or not ok
