extends SceneTree
## Run: godot --headless -s tests/test_crop_calendar.gd
## The crop calendar (CropCalendar): planting and harvest windows, growth,
## browning, stubble, tillage, cover crops and the rotation, held to the
## real east-central Indiana numbers in docs/crop-calendar.md.

var _failed := false

const MAY_1 := 120.0
const JUN_1 := 151.0
const JUL_1 := 181.0
const AUG_1 := 212.0
const SEP_1 := 243.0
const OCT_1 := 273.0
const NOV_1 := 304.0
const DEC_1 := 334.0


func _init() -> void:
	# Heat: a normal Marion summer gives corn about 2,600-3,000 heat units
	# from May through September.
	var season := CropCalendar.gdd(OCT_1) - CropCalendar.gdd(MAY_1)
	_check(season > 2500.0 and season < 3100.0, "May-September heat units near Marion's normal (%.0f)" % season)

	# Planting windows (USDA NASS Indiana five-year averages).
	var corn := []
	var beans := []
	for i in 40:
		var u := (i + 0.5) / 40.0
		corn.append(CropCalendar.plan("corn", "soybeans", "soybeans", CropCalendar.NO_TILL, false, false, u, 2))
		beans.append(CropCalendar.plan("soybeans", "corn", "corn", CropCalendar.NO_TILL, false, false, u, 2))
	var normal := 2
	while float(CropCalendar.year_weather(normal).delay) > 3.0:
		normal += 1
	var corn_n := []
	var beans_n := []
	for i in 40:
		var u := (i + 0.5) / 40.0
		corn_n.append(CropCalendar.plan("corn", "soybeans", "", CropCalendar.NO_TILL, false, false, u, normal))
		beans_n.append(CropCalendar.plan("soybeans", "corn", "", CropCalendar.NO_TILL, false, false, u, normal))
	var cp := corn_n.map(func(p): return p.plant)
	var bp := beans_n.map(func(p): return p.plant)
	_check(cp.min() >= 105.0 and cp.max() <= 176.0, "corn is planted from mid April into June (%.0f-%.0f)" % [cp.min(), cp.max()])
	_check(_median(cp) >= 128.0 and _median(cp) <= 140.0, "half the corn is in by mid May (%.0f)" % _median(cp))
	_check(bp.min() >= 112.0 and bp.max() <= 182.0, "soybeans are planted late April to June (%.0f-%.0f)" % [bp.min(), bp.max()])
	_check(_median(bp) > _median(cp) and _median(bp) <= 150.0, "beans go in after the corn, half by late May (%.0f)" % _median(bp))
	var wet := 1
	while float(CropCalendar.year_weather(wet).delay) < 5.0:
		wet += 1
	var wet_corn := CropCalendar.plan("corn", "soybeans", "", CropCalendar.NO_TILL, false, false, 0.3, wet)
	var dry_corn := CropCalendar.plan("corn", "soybeans", "", CropCalendar.NO_TILL, false, false, 0.3, normal)
	_check(wet_corn.plant > dry_corn.plant + 3.0, "a wet spring (year %d) holds planting back" % wet)

	# Corn growth: up in a week or two, rows showing in June, the canopy
	# closed by mid July, 8-9 ft and tasseled by the end of July.
	var mid: Dictionary = corn_n[20]
	var up: float = mid.plant
	while CropCalendar.state(mid, up).height <= 0.0 and up < mid.plant + 30.0:
		up += 1.0
	_check(up - mid.plant >= 5.0 and up - mid.plant <= 16.0, "corn emerges %d days after planting" % int(up - mid.plant))
	var june := CropCalendar.state(mid, JUN_1 + 5.0)
	_check(june.cover > 0.0 and june.cover < 0.5 and june.spacing == 1.0, "early June: rows of young corn, 30 in apart, soil between (%.2f)" % june.cover)
	_check(CropCalendar.state(mid, JUL_1 + 14.0).cover >= 0.9, "the corn canopy closes by mid July")
	var tassel := CropCalendar.state(mid, AUG_1)
	_check(tassel.height >= 2.4 and tassel.height <= 2.9 and tassel.stage == "tasseled",
		"corn is 8-9 ft and tasseled by August 1 (%.2f m, %s)" % [tassel.height, tassel.stage])
	var all_tall := corn_n.all(func(p): return CropCalendar.state(p, AUG_1 + 20.0).height >= 2.3)
	_check(all_tall, "every corn field is tall by late August")
	# Browning: dent, then black layer in September; leaves tan and drying.
	var mature := corn_n.map(func(p): return p.mature)
	_check(_median(mature) >= SEP_1 + 5.0 and _median(mature) <= OCT_1 + 5.0, "corn reaches black layer in September (median %.0f)" % _median(mature))
	_check(CropCalendar.state(mid, OCT_1).green < 0.3, "corn is brown and drying by October 1")
	_check(CropCalendar.state(mid, AUG_1).green == 1.0, "and green in early August")

	# Soybeans: closing rows, yellow leaves in mid to late September, then bare stems.
	var mb: Dictionary = beans_n[20]
	_check(CropCalendar.state(mb, AUG_1 + 10.0).cover >= 0.9 and CropCalendar.state(mb, AUG_1 + 10.0).height > 0.6,
		"bean rows close by mid August, about 2-3 ft tall")
	var sept := CropCalendar.state(mb, SEP_1 + 18.0)
	_check(sept.green < 0.6 and sept.leaves > 0.5, "beans turn yellow in mid September (%s)" % sept.stage)
	var drop := CropCalendar.state(mb, OCT_1 + 2.0)
	_check(drop.leaves < 0.3 or drop.harvested == 1.0, "and drop their leaves by early October (%s)" % drop.stage)

	# Harvest (NASS): beans before corn; about half the corn and two thirds
	# of the beans in by October 22.
	var ch := corn_n.map(func(p): return p.harvest)
	var bh := beans_n.map(func(p): return p.harvest)
	_check(bh.min() >= SEP_1 + 14.0 and bh.max() <= DEC_1 + 5.0, "bean harvest runs late September to November")
	_check(ch.min() >= SEP_1 + 20.0 and ch.max() <= DEC_1 + 16.0, "corn harvest runs late September into December")
	_check(_median(bh) < _median(ch), "beans come out before the corn")
	var oct22 := 295.0
	var corn_done := ch.filter(func(d): return d <= oct22).size() / 40.0
	var beans_done := bh.filter(func(d): return d <= oct22).size() / 40.0
	_check(absf(corn_done - 0.54) < 0.15 and absf(beans_done - 0.67) < 0.15,
		"by October 22 about half the corn and two thirds of the beans are harvested (%.0f%%, %.0f%%)" % [corn_done * 100, beans_done * 100])
	for p in corn_n + beans_n:
		_check_quiet(p.harvest > p.mature, "a field is harvested after it matures")

	# Stubble and tillage.
	var stalks := CropCalendar.state(mid, mid.harvest + 2.0)
	_check(stalks.stage == "corn stalks" and absf(stalks.height - 0.4) < 0.01 and stalks.rows > 0.3,
		"after the combine: corn stalks standing in rows")
	var stub := CropCalendar.state(mb, mb.harvest + 2.0)
	_check(stub.stage == "bean stubble" and stub.height <= 0.15, "bean stubble is short")
	var chisel := CropCalendar.plan("corn", "soybeans", "soybeans", CropCalendar.CHISEL, false, false, 0.3, normal)
	var tilled := CropCalendar.state(chisel, chisel.till_fall + 3.0)
	_check(chisel.till_fall > chisel.harvest and chisel.till_fall < DEC_1 and tilled.stage == "chiseled" and tilled.height == 0.0,
		"a conventional farm chisels its corn stalks in the fall")
	_check(Color(tilled.ground).v < Color(stalks.ground).v, "fresh-worked ground is darker than stubble")
	var next_beans := CropCalendar.plan("soybeans", "corn", "corn", CropCalendar.NO_TILL, false, false, 0.3, normal + 1)
	var jan := CropCalendar.state(next_beans, 20.0)
	_check(jan.crop == "corn" and jan.stage == "corn stalks", "no-till corn stalks stand through the winter")
	var worked := CropCalendar.plan("soybeans", "corn", "corn", CropCalendar.CHISEL, false, false, 0.3, normal + 1)
	_check(CropCalendar.state(worked, 20.0).stage == "stubble", "chiseled ground has no standing stalks in winter")
	_check(CropCalendar.state(worked, worked.plant - 0.2).stage == "worked ground", "a field cultivator pass just before planting")

	# Cover crops: rye green after harvest and again in spring, sprayed before corn.
	var rye_fall := CropCalendar.plan("soybeans", "corn", "corn", CropCalendar.RYE, true, true, 0.3, normal)
	var dec := CropCalendar.state(rye_fall, DEC_1 + 5.0)
	_check(dec.crop == "rye" and dec.cover > 0.2, "rye cover crop is up in the bean stubble in December")
	var rye_spring := CropCalendar.plan("corn", "soybeans", "soybeans", CropCalendar.RYE, true, true, 0.3, normal)
	var april := CropCalendar.state(rye_spring, 110.0)
	_check(april.crop == "rye" and april.cover > 0.6, "the rye greens up and grows in April")
	_check(rye_spring.rye_kill < rye_spring.plant, "and is sprayed before the corn is planted")

	# Winter: no living row crop anywhere in January.
	for p in corn_n + beans_n:
		var s := CropCalendar.state(p, 15.0)
		_check_quiet(s.green == 0.0 or s.crop == "rye", "nothing green in the row-crop fields in January")
	# Wheat: green over winter, gold in June, cut around July 1, beans after.
	var wheat := CropCalendar.plan("wheat", "soybeans", "corn", CropCalendar.NO_TILL, false, false, 0.5, normal)
	_check(CropCalendar.state(wheat, 20.0).crop == "wheat" and CropCalendar.state(wheat, 20.0).cover > 0.2, "winter wheat shows green in January")
	_check(CropCalendar.state(wheat, 172.0).stage == "ripe", "wheat is gold by late June")
	_check(wheat.harvest >= 176.0 and wheat.harvest <= 190.0 and wheat.double, "and cut around July 1, double-crop beans after")
	_check(CropCalendar.state(wheat, AUG_1 + 20.0).crop == "soybeans", "double-crop soybeans in August")

	# The county: fields of 40, 80 and 160 acres; corn and beans about half
	# and half, swapping every year; the same answer every time.
	var counts := {}
	var swap := 0
	var rotation := 0
	var sizes := {}
	for x in 60:
		for z in 60:
			var r := Vector2(x * 131.0 - 4000.0, z * 127.0 - 3000.0)
			var f := CropCalendar.county_field(r)
			var slot := CropCalendar.county_slot(Vector2i(f.x, f.y))
			var a: String = CropCalendar.county_row(slot.x, 5).crop
			var b: String = CropCalendar.county_row(slot.x, 6).crop
			counts[a] = counts.get(a, 0) + 1
			if slot.x < 8:
				rotation += 1
				swap += 1 if a != b else 0
			sizes[Vector2i(f.x, f.y)] = true
	var total := 3600.0
	_check(counts.get("corn", 0) / total > 0.4 and counts.get("corn", 0) / total < 0.62, "about half the county is corn (%s)" % str(counts))
	_check(counts.get("soybeans", 0) / total > 0.33 and counts.get("soybeans", 0) / total < 0.55, "and most of the rest soybeans")
	_check(swap == rotation, "corn and soybean fields swap every year")
	_check(CropCalendar.county_row(8, 3).crop == "corn" and CropCalendar.county_row(8, 4).crop == "corn", "corn-on-corn fields stay corn")
	_check(CropCalendar.county_field(Vector2(1234.5, -876.0)) == CropCalendar.county_field(Vector2(1234.5, -876.0)), "the same field every time")
	_check(CropCalendar.hash32(3, -7, 5) == 3536973489, "the field hash is the one the shaders use (%d)" % CropCalendar.hash32(3, -7, 5))
	var ids := {}
	for x in 8:
		for z in 8:
			var f := CropCalendar.county_field(Vector2(x * 201.0 + 100.5, z * 201.0 + 100.5))
			ids[Vector2i(f.x, f.y)] = true
	_check(ids.size() >= 2 and ids.size() <= 16, "a 1,608 m square of section holds 4 to 16 fields here (%d)" % ids.size())

	# The table: today's look for every kind of field, a small texture.
	var tex := CropCalendar.texture()
	_check(tex.get_width() == CropCalendar.COLS * CropCalendar.TEXELS and tex.get_height() == CropCalendar.ROWS, "the crop table is %dx%d" % [tex.get_width(), tex.get_height()])
	var v := CropCalendar.version
	CropCalendar.set_date(6.5, 4)
	CropCalendar.refresh(true)
	_check(CropCalendar.version > v and CropCalendar.today() == Vector2(snappedf(CropCalendar.day_of_year(6.5), 0.5), 4), "the table moves to a new date")
	var row := CropCalendar.farm_row("corn", "soybeans", CropCalendar.NO_TILL, false, false)
	_check(row >= CropCalendar.COUNTY_ROWS and CropCalendar.farm_row("corn", "soybeans", CropCalendar.NO_TILL, false, false) == row, "a farm field's facts get one row")
	_check(CropCalendar.state_at(row, 5).crop == "corn" and CropCalendar.state_at(row, 5).height > 2.0, "and its state today (mid July corn)")
	var t0 := Time.get_ticks_usec()
	CropCalendar.set_date(6.6, 4)
	var steps := 0
	while not CropCalendar.refresh(false, 1.0) or CropCalendar.today() != Vector2(snappedf(CropCalendar.day_of_year(6.6), 0.5), 4) or steps == 0:
		steps += 1
		if steps > 200:
			break
	print("table pass: %d frames, %.1f ms in all" % [steps, (Time.get_ticks_usec() - t0) / 1000.0])

	# A town's farm fields look the same in two copies of the town and after
	# a save and load: the look comes from saved facts and the date only.
	var a_sim := _town()
	var b_sim := _town()
	var a_look := _looks(a_sim)
	_check(not a_look.is_empty(), "the farm has fields")
	_check(a_look == _looks(b_sim), "two copies of the town show the same fields")
	var back := CitySim.new()
	back.from_dict(JSON.parse_string(JSON.stringify(a_sim.to_dict())))
	_check(_looks(back) == a_look, "and the same after a save and load")
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _town() -> CitySim:
	var fm := CitySim.new()
	fm.economy.money = 10_000_000
	fm.apply({"type": "build_road", "start": [-600, 0], "ctrl": [0, 0], "end": [600, 0]})
	fm.apply({"type": "paint_farmland", "points": [[-500, 20], [500, 20], [500, 600], [-500, 600]]})
	fm.apply({"type": "place_farmhouse", "pos": [0, 60], "dir": [0, -1], "crop": "corn"})
	for i in 60:
		fm.farms.decide(fm.field_usable)
	for y in 3:
		fm.farms.year += 1
		fm.farms.decide(fm.field_usable)
	return fm


## Every farm cell's table slot and its look on a few days of the year.
func _looks(sim: CitySim) -> Array:
	var out := []
	var ids := sim.farms.farms.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = sim.farms.farms[id]
		var cells: Array = f.cells.duplicate()
		cells.sort()
		for c in cells:
			var slot := FarmView.slot_of(id, f, c)
			var fl := CropPlan.field(f, c)
			var p := CropCalendar.plan(fl.crop, fl.prev, "", CropCalendar.farm_practice(int(id), f), fl.cover,
				fl.cover_prev, (slot.y + 0.5) / CropCalendar.COLS, 4)
			var days := []
			for d in [20.0, 140.0, 200.0, 260.0, 300.0]:
				var s := CropCalendar.state(p, d)
				days.append([s.stage, snappedf(s.height, 0.001), Color(s.plant).to_html()])
			out.append([c, fl.crop, slot.y, days])
	return out


static func _median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2]


func _check_quiet(ok: bool, what: String) -> void:
	if not ok:
		_check(false, what)


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
