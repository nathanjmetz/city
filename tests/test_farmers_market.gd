extends SceneTree
## The Saturday farmers' market (Brawn's pick #19): from May to October the
## farms' pickups drive in to the courthouse square, the stalls go up for
## the day, each stall's sales go to its farm, and it all packs up after.
## Run: godot --headless -s tests/test_farmers_market.gd


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 80_000_000
	sim.apply({"type": "build_county_road", "a": [-700, 0], "b": [700, 0], "links": [0, 1]})
	var cid := -1
	for x in [0, 150, -150, 300]:
		var cs := Parks.site_near(sim.network, "courthouse", Vector3(x, 0, 80))
		if not cs.is_empty() and sim.apply({"type": "place_park", "kind": "courthouse", "pos": [cs[0].x, cs[0].z],
				"dir": [cs[1].x, cs[1].z]}):
			cid = sim.parks.sites.keys()[-1]
			break
	_check(cid != -1, "a courthouse square goes up")
	_check(FarmersMarket.find_venue(sim) == -1, "no market while it's still being built")
	sim.construction.sites.erase("park:%d" % cid)
	_check(FarmersMarket.find_venue(sim) == cid, "the market is held on the courthouse square")
	var farms := 0
	for x in range(-650, 651, 130):
		if sim.apply({"type": "place_farmhouse", "pos": [x, -90], "dir": [0, 1], "crop": "corn"}):
			farms += 1
	for fid in sim.farms.farms:
		sim.construction.sites.erase("farm:%d" % fid)
	_check(farms >= 5, "farms around town (%d)" % farms)

	# A Friday in June, the day before market.
	var tpd := Seasons.TICKS_PER_DAY
	var d := int(Seasons.tick_at(Seasons.months(0) + 1.0) / tpd)
	while not (Seasons.weekday(d * tpd) == 5 and Seasons.month(d * tpd) == 6):
		d += 1
	sim.set_calendar(d * tpd)
	var cash := 0.0
	for fid in sim.farms.farms:
		cash += float(sim.farms.farms[fid].cash)
	var was_open := false
	var stalls := 0
	var pickups := 0
	var wrong_day := false
	for i in 2 * tpd + 60:
		sim.tick()
		for id in sim.farmers_market.trips:
			pickups = maxi(pickups, sim.farmers_market.trips.size())
		if sim.farmers_market.open:
			was_open = true
			stalls = maxi(stalls, sim.farmers_market.stalls_at(cid))
			wrong_day = wrong_day or Seasons.weekday(sim.calendar_tick()) != 6
	_check(not wrong_day, "it's only on a Saturday")
	_check(pickups > 0, "farm pickups drive in (%d on the road at once)" % pickups)
	_check(was_open and stalls > 0 and stalls <= Balance.FARMERS_MARKET_MAX_VENDORS,
		"the market opened with %d stalls" % stalls)
	_check(not sim.farmers_market.open and int(sim.farmers_market.last.get("vendors", 0)) > 0,
		"and closed after Saturday (%s)" % str(sim.farmers_market.last))
	var after := 0.0
	for fid in sim.farms.farms:
		after += float(sim.farms.farms[fid].cash)
	_check(after >= cash + Balance.FARMERS_MARKET_SALES, "the farms took home their sales (+$%d)" % roundi(after - cash))
	_check(sim.chains.links().any(func(l): return l.from == "farm" and l.to == "market"),
		"the chain page shows farms to the market")

	# The stalls are drawn on the square while it's on.
	var s: Dictionary = sim.parks.sites[cid].duplicate()
	var plain: ArrayMesh = ParkBuilder.build_site(s, 1, 6.0, "Town")[0]
	s["market_stalls"] = 12
	var market: ArrayMesh = ParkBuilder.build_site(s, 1, 6.0, "Town")[0]
	_check(_tris(market) > _tris(plain) + 12 * 20, "12 canopies stand on the square (%d -> %d triangles)" % [
		_tris(plain), _tris(market)])

	# In winter there's none.
	var winter := d
	while Seasons.month(winter * tpd) != 1:
		winter += 1
	sim.set_calendar(winter * tpd)
	for i in tpd * 7 / FarmersMarket.EVERY:
		sim.tick_count += FarmersMarket.EVERY
		sim.farmers_market.tick(sim)
	_check(not sim.farmers_market.open, "no market in January")

	var copy := FarmersMarket.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(sim.farmers_market.to_dict())))
	_check(copy.to_dict() == sim.farmers_market.to_dict(), "the market is saved")

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _tris(m: ArrayMesh) -> int:
	var n := 0
	for i in m.get_surface_count():
		var a := m.surface_get_arrays(i)
		n += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
	return n


var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
