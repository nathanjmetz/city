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
