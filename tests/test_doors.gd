extends SceneTree
## Garage doors that work (docs/spec-working-doors.md, step 1: house
## garages). Nathan, 2026-10-29: "it would also help if we had working doors
## and garage doors. they could open to black, allowing things to come in
## and out." A house's garage doors are logged where the art draws them; a
## car leaving its garage waits for its door; the door goes up for a car
## coming home or backing out, never for one drawn out on the drive; a town
## saved and loaded mid-wait, and every computer, carries on the same; and
## the door view draws them near the camera at High and up, never below.
## Run: godot --headless -s tests/test_doors.gd

var _failed := false


func _init() -> void:
	_logged()
	_traffic()
	_same_everywhere()
	_out_front()
	_view()
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed = true


## The art logs each garage door it draws, carried in the plan's info and
## placed with it: mirrored when the garage is on the left, moved back to
## the lot's setback. Logging takes no random numbers, so the house is
## drawn exactly as it was.
func _logged() -> void:
	var seen := 0
	var both := {}
	var bad := []
	for seed in 60:
		var lot := {"width": 22.0, "depth": 36.0}
		var info := HouseBuilder.plan_info(seed * 7919 + 13, lot, 0)
		var doors := DoorLog.placed(info)
		if doors.is_empty():
			continue
		seen += 1
		both[float(info.gs) < 0.0] = true
		for d in doors:
			var c: Vector3 = d[1]
			# On the garage's front wall, across its drive, facing the street.
			# (A split-level's brick front sets its door 12 cm out.)
			if d[0] != "garage" or absf(c.z - (float(info.garage_z) - 0.06)) > 0.2 \
					or absf(c.x - float(info.drive_x)) > float(info.drive_w) * 0.5 + 0.5 or d[2] != Vector3(0, 0, -1) \
					or float(d[3]) < 2.0 or float(d[4]) < 1.9:
				bad.append([seed, d])
	_check(seen >= 50, "most house plans log their garage doors (%d of 60)" % seen)
	_check(both.size() == 2, "on lots with the garage on the right and on the left")
	_check(bad.is_empty(), "every door sits on its garage's front wall, across its drive, facing the street %s" % [bad.slice(0, 2)])
	var a := HouseBuilder.build(4242, 8.0, {"width": 22.0, "depth": 36.0})
	var b := HouseBuilder.build(4242, 8.0, {"width": 22.0, "depth": 36.0})
	_check(a[0].get_faces().size() == b[0].get_faces().size(), "a house is drawn the same with its doors logged")


func _traffic() -> void:
	var sim := CitySim.new()
	PerfTown.build(sim, "small")
	var t: TrafficSim = sim.traffic
	var ev := DoorEvents.new(t)
	# Every garage spot on a house lot faces a logged door.
	var spots := 0
	var matched := 0
	for key in sim.lots:
		var b = sim.buildings.get(key)
		if b == null or int(b.zone) != ZoneMap.Zone.RESIDENTIAL:
			continue
		var pl := t.place("lot:" + key)
		if pl.is_empty() or pl.get("lay", {}).get("doors", []).is_empty():
			continue
		for i in pl.spots.size():
			if pl.spots[i].kind == "garage":
				spots += 1
				matched += 1 if ev._door_of(pl, i) >= 0 else 0
	_check(spots > 50 and matched == spots, "every home's garage spot faces a door (%d of %d)" % [matched, spots])
	# A car leaving its garage never waits: its door goes up while its
	# driver walks out to it, so it is most of the way up as they get in,
	# and how far up it is is exact (the simulation's door_t and door_n).
	var doored := {}  # car id -> [door_t, door_n, tick it set off, how far up then]
	var exact_ok := true
	var opened_leaving := 0
	var opened_coming := 0
	for i in 2400:
		sim.tick()
		for vid in t._doored:
			var car: Dictionary = t._doored[vid]
			if not doored.has(vid):
				doored[vid] = [int(car.door_t), int(car.door_n), -1, -1.0]
		for car in t.cars:
			if doored.has(car.id) and doored[car.id][2] < 0:
				doored[car.id][2] = t._tick
				doored[car.id][3] = DoorEvents.up(car, t._tick) if car.has("door_t") else -1.0
		var open := ev.open_near(Vector3.ZERO, 1e6)
		for key in open:
			var ref: String = open[key][0]
			for car in t.cars:
				if car.get("from_place", "") == ref and car.get("j") != null and int(car.j.wi) == -1:
					opened_leaving += 1
				if car.get("to_place", "") == ref and car.get("j") != null and int(car.j.wo) == -1 and float(open[key][3]) < 0.0:
					opened_coming += 1
		for vid in t._doored:
			var car: Dictionary = t._doored[vid]
			if t._tick < int(car.door_t):
				continue
			var want := DoorEvents.up(car, t._tick)
			var found := false
			for key in open:
				var e: Array = open[key]
				# (Or another car under the same wide door is going in or out.)
				if e[0] == car.at_place and (absf(float(e[3]) - want) < 1e-6 or float(e[3]) < 0.0 or float(e[3]) > want):
					found = true
			exact_ok = exact_ok and found
		if doored.size() > 40 and opened_coming > 0 and opened_leaving > 0 and i > 900:
			break
	var gone := doored.values().filter(func(w): return w[2] >= 0)
	var low := gone.filter(func(w): return w[3] < TrafficSim.DOOR_SHARE - 0.05)
	print("doors: %d doors went up, %d cars set off; ticks %d" % [doored.size(), gone.size(), t._tick])
	_check(gone.size() >= 5, "cars leave their garages (%d)" % gone.size())
	_check(low.size() * 10 <= gone.size(), "their door is most of the way up as they set off (%d of %d lower) %s" % [low.size(), gone.size(), low.slice(0, 3)])
	_check(exact_ok, "a door is exactly as far up as the simulation says")
	_check(opened_leaving > 0, "a door stays up while its car backs down the drive (%d)" % opened_leaving)
	_check(opened_coming > 0, "a door goes up for a car coming home and turning in (%d)" % opened_coming)


## A town saved and loaded while a door goes up carries on the same, and so
## does every computer running the town: the car sets off on the same tick
## and every door is as far up on each. And the door costs the trip
## nothing: with no door at all (a save from before doors), it sets off on
## that very tick too.
func _same_everywhere() -> void:
	var a := CitySim.new()
	PerfTown.build(a, "small")
	var b := CitySim.new()
	PerfTown.build(b, "small")
	var watch := -1
	for i in 2400:
		a.tick()
		b.tick()
		for vid in a.traffic._doored:
			var car: Dictionary = a.traffic._doored[vid]
			if int(car.door_t) <= a.traffic._tick - 10:
				watch = vid  # its door part way up
		if watch >= 0:
			break
	_check(watch >= 0, "a door goes up while its driver walks out (car %d)" % watch)
	var saved := a.to_dict()
	var c := CitySim.new()
	c.from_dict(JSON.parse_string(JSON.stringify(saved)))
	var d := CitySim.new()
	d.from_dict(JSON.parse_string(JSON.stringify(saved)))
	for car in d.traffic.parked:
		car.erase("door_t")
		car.erase("door_n")
	d.traffic._index_parked()
	var sims := [a, b, c, d]
	var evs := sims.map(func(s): return DoorEvents.new(s.traffic))
	var off := [-1, -1, -1, -1]
	var apart := -1
	for i in 300:
		for k in 4:
			sims[k].tick()
			if off[k] < 0 and sims[k].traffic.cars.any(func(car): return car.id == watch):
				off[k] = sims[k].traffic._tick
		var seen: Array = evs.slice(0, 3).map(func(e): return _canon_open(e.open_near(Vector3.ZERO, 1e6)))
		if apart < 0 and (seen[0] != seen[1] or seen[0] != seen[2]):
			apart = i
	_check(off[0] > 0 and off[0] == off[1] and off[0] == off[2],
		"it sets off on the same tick on every computer and after a load (%s)" % [off.slice(0, 3)])
	_check(apart < 0, "every door is as far up on each, tick for tick" + ("" if apart < 0 else " (apart at %d)" % apart))
	_check(off[3] == off[0], "with no door at all it sets off on the very same tick (%d, %d)" % [off[3], off[0]])


static func _canon_open(open: Dictionary) -> Array:
	var keys := open.keys()
	keys.sort()
	return keys.map(func(k): return [k, snappedf(float(open[k][3]), 1e-6)])


## A car TrafficView draws out on the drive opens no door: the garage looks
## shut with the car outside. One drawn in its garage gets its door.
func _out_front() -> void:
	var sim := CitySim.new()
	PerfTown.build(sim, "small")
	var t: TrafficSim = sim.traffic
	var view := TrafficView.new()
	view.setup(t, func(): return 0.0, sim)
	var ev := DoorEvents.new(t, sim)
	ev.out_front = view.out_front
	var plain := DoorEvents.new(t)
	var outs := 0
	var ins := 0
	var wrong := []
	var leaving_out := 0
	for i in 2400:
		sim.tick()
		view._rebuild_parked()
		for car in t.cars:
			view._sample(car, view._info_of(car))  # as drawing does: follows who set off from the drive
		var open := ev.open_near(Vector3.ZERO, 1e6)
		var all := plain.open_near(Vector3.ZERO, 1e6)
		for vid in t._doored:
			var car: Dictionary = t._doored[vid]
			if t._tick < int(car.door_t):
				continue
			var out := view.out_front(car, true)
			var listed := open.keys().any(func(k): return open[k][0] == car.at_place)
			var other := all.keys().filter(func(k): return all[k][0] == car.at_place).size()
			if out:
				outs += 1
				if listed and other <= 1:
					wrong.append(car.id)  # its door went up anyway
			else:
				ins += 1
				if not listed:
					wrong.append(car.id)  # its door stayed shut
		leaving_out += view._leaving_out.size()
		if outs > 200 and ins > 100:
			break
	_check(outs > 0 and ins > 0, "some cars stand on the drive, some in the garage, as their doors would go up (%d, %d ticks)" % [outs, ins])
	_check(wrong.is_empty(), "a door opens for a car in its garage, never for one drawn on the drive %s" % [wrong.slice(0, 4)])
	_check(leaving_out > 0, "one drawn on the drive backs out from there, not from the garage (%d)" % leaving_out)
	view.free()


## The door view: at High (doors_m) the door a car goes in or out of is
## drawn going up, as a dark opening below the door's panels; it comes
## down again after; at Medium (no doors_m) nothing is drawn. Measures what
## a frame of it costs.
func _view() -> void:
	var sim := CitySim.new()
	PerfTown.build(sim, "small")
	var t: TrafficSim = sim.traffic
	var was: Dictionary = GraphicsQuality.budget
	GraphicsQuality.budget = GraphicsQuality.budget_for(GraphicsQuality.HIGH)
	var view := DoorView.new()
	view.setup(t, sim, func(_c, _l): return false, func(key: String):
		var lot: Dictionary = sim.lots[key]
		var xf := SiteLayout.frame(lot)
		xf.origin.y = Terrain.base_y(lot.pos.x, lot.pos.z)
		return xf)
	view._ready()
	var ev := DoorEvents.new(t)
	var eye := Vector3.INF
	var key := ""
	for i in 2400:
		sim.tick()
		var open := ev.open_near(Vector3.ZERO, 1e6)
		if not open.is_empty():
			key = open.keys()[0]
			var lot: Dictionary = sim.lots[str(open[key][0]).substr(4)]
			eye = lot.front + Vector3(0, 40, 0)
			break
	_check(key != "", "a door goes up somewhere in the town (%s)" % key)
	var most := 0
	var mid := false
	var closed_at := -1
	var us := 0
	var frames := 0
	for i in 400:
		sim.tick()
		var t0 := Time.get_ticks_usec()
		view.step(eye)
		us += Time.get_ticks_usec() - t0
		frames += 1
		most = maxi(most, view.drawn)
		if view._shown.has(key):
			var up: float = view._shown[key][0]
			if up > 0.3 and up < 0.7 and view._cards.multimesh.visible_instance_count > 0 \
					and view._panels.multimesh.visible_instance_count > 0:
				mid = true
		elif closed_at < 0 and most > 0:
			closed_at = i
	print("doors: a frame of the door view took %.3f ms on average (%d frames, at most %d doors)" % [us / 1000.0 / frames, frames, most])
	_check(most > 0 and most <= int(GraphicsQuality.knob("doors", 0)), "at High the view draws the doors going up (%d)" % most)
	_check(mid, "half way up: a dark opening below and the door's panels above")
	_check(closed_at > 0, "and it comes back down after (%d ticks on)" % closed_at)
	_check(us / 1000.0 / frames < 0.3, "under 0.3 ms a frame (%.3f)" % [us / 1000.0 / frames])
	GraphicsQuality.budget = GraphicsQuality.budget_for(GraphicsQuality.MEDIUM)
	for i in 50:
		sim.tick()
		view.step(eye)
	_check(view.drawn == 0 and view._cards.multimesh.visible_instance_count == 0, "at Medium no door moves")
	GraphicsQuality.budget = was
	view.free()
