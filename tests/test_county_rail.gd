extends SceneTree
## Run: godot --headless -s tests/test_county_rail.gd

var _failed := false


func _init() -> void:
	var routes := CountyRail.all()
	var total := 0.0
	for r in routes.size():
		total += CountyRail.length(r)
	_check(routes.size() > 20 and total > 150000.0, "the county's real railroads load (%d lines, %d km on the map)" % [routes.size(), roundi(total / 1000.0)])

	# Every line's track is laid on or above the ground, never steeper than
	# a real line can climb, and comes down to each road it crosses.
	var under := 0
	var steep := 0
	var crossings := 0
	var flush := 0
	var bridges := 0
	for r in routes.size():
		var ramp := PackedByteArray()
		var prof := CountyRail.profile(r)
		var at: PackedVector2Array = prof.at
		var bed: PackedFloat32Array = prof.bed
		var kind: PackedByteArray = prof.kind
		# The approaches to a crossing ease down into the road's level.
		ramp.resize(at.size())
		for i in at.size():
			if kind[i] == 1:
				for j in range(maxi(0, i - 7), mini(at.size(), i + 8)):
					ramp[j] = 1
		for i in at.size():
			if kind[i] == 0 and ramp[i] == 0 and bed[i] < Terrain.height(at[i].x, at[i].y) - 0.05:
				under += 1
			if kind[i] == 2:
				bridges += 1
			if kind[i] == 1:
				crossings += 1
				if absf(bed[i] + CountyRail.RAIL_TOP - RailView.CROSSING_RAIL - Terrain.height(at[i].x, at[i].y)) < 0.6:
					flush += 1
			if i > 0 and kind[i] == 0 and kind[i - 1] == 0 and ramp[i] == 0 and absf(bed[i] - bed[i - 1]) / CountyRail.STEP > CountyRail.GRADE + 0.001:
				steep += 1
	_check(under == 0, "the track is never laid under the ground (%d samples under)" % under)
	_check(crossings > 50 and flush > crossings * 0.8, "it comes down level at the grade crossings (%d of %d)" % [flush, crossings])
	_check(bridges > 0, "it bridges the creeks and rivers (%d samples on bridges)" % bridges)
	_check(steep == 0, "it climbs gently (%d steep samples)" % steep)

	# A train can find its way along: near() and point() agree.
	var mid := CountyRail.point(0, CountyRail.length(0) * 0.5)
	var n := CountyRail.near(mid.x + 3.0, mid.y, 20.0)
	_check(not n.is_empty() and n.route == 0 and absf(n.along - CountyRail.length(0) * 0.5) < 5.0, "near() finds the track and where along it")
	_check(CountyRail.clears(mid.x + 5.0, mid.y) and not CountyRail.clears(mid.x + 200.0, mid.y + 200.0) or CountyRail.kind_at(0, CountyRail.length(0) * 0.5) == 3,
		"trees keep off its right of way, and only there")
	var cross := CountyRail.crossing(mid + Vector2(-30, -30), mid + Vector2(30, 30))
	_check(not cross.is_empty() or CountyRail.near(mid.x, mid.y, 1.0).is_empty(), "a line drawn over the track crosses it")

	# Farmhouses stand back from the track, past its right of way.
	FarmsteadPlan.load_places()
	var close := 0
	var data := FileAccess.get_file_as_bytes(Terrain.DIR + "farmsteads.bin")
	for i in data.decode_u32(4):
		var at := 8 + i * 7
		var q := FarmsteadPlan.off_rail(Vector2(data.decode_s16(at), data.decode_s16(at + 2)))
		if CountyRail.distance(q.x, q.y, 40.0) < 40.0:
			close += 1
	_check(close == 0, "no farmstead stands on the railroad (%d too close)" % close)

	# Where a town street crosses the track (CountyRailView, 2026-10-31):
	# the bed eases down so the rail tops sit flush in the street, and is
	# back at full height RAMP past the pavement; the trains ride the same.
	var x_prof0 := CountyRail.profile(0)
	var x_bed0: PackedFloat32Array = x_prof0.bed
	var x_mid := x_bed0.size() / 2
	var x_street: float = x_bed0[x_mid] - 0.5
	var x_paved := {x_mid: x_street, x_mid + 1: x_street}
	var x_level := x_street - CountyRail.RAIL_TOP + CountyRailView.TOWN_RAIL
	var x_off := int(CountyRail.RAMP / CountyRail.STEP)
	_check(absf(CountyRailView._eased(x_mid, x_bed0, x_paved) - x_level) < 0.001 and absf(CountyRailView._eased(x_mid + 1, x_bed0, x_paved) - x_level) < 0.001,
		"the track is flush with a town street under its pavement")
	_check(absf(CountyRailView._eased(x_mid + 1 + x_off, x_bed0, x_paved) - x_bed0[x_mid + 1 + x_off]) < 0.001
		and absf(CountyRailView._eased(x_mid - x_off, x_bed0, x_paved) - x_bed0[x_mid - x_off]) < 0.001,
		"the track is back at full height %d m past the street" % roundi(CountyRail.RAMP))
	var x_mids := CountyRailView._eased(x_mid + 3, x_bed0, x_paved)
	_check(x_mids <= x_bed0[x_mid + 3] + 0.001 and x_mids >= minf(x_level, x_bed0[x_mid + 3]) - 0.001, "the track eases between the two")
	CountyRailView._sunk.clear()
	var x_same := true
	for s in [0.0, 3.0, x_mid * CountyRail.STEP + 1.7, CountyRail.length(0) - 2.0]:
		x_same = x_same and absf(CountyRailView.bed_at(0, s) - CountyRail.bed_at(0, s)) < 0.0001
	_check(x_same, "with no town crossing drawn the trains ride the county's own bed")
	CountyRailView._sunk[0] = {x_mid: x_level, x_mid + 1: x_level}
	_check(absf(CountyRailView.bed_at(0, (x_mid + 0.5) * CountyRail.STEP) - x_level) < 0.001, "the trains ride the eased bed at a town crossing")
	CountyRailView._sunk.clear()

	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
