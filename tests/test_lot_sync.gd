extends SceneTree
## Run: godot --headless -s tests/test_lot_sync.gd
## The lot check's shortcuts (LotGround: only lots by what changed are looked
## at again) and the services' kept rows give the same answers as working
## everything out afresh. With CitySim.verify_ground and Services.verify_rows
## on, every shortcut is compared with the full answer as it runs, and any
## difference fails. A twin of the town that checks every lot every time is
## given the same changes, and its lots must come out the same. Rail (built,
## swapped for track of the same length, taken up), a service, farm fields,
## a company's pad and a hub (placed, moved, removed) each come and go by a
## street of open lots; partway through, the town is saved and loaded, and
## the copy must keep agreeing.

var _fails := 0
var sim: CitySim
var twin: CitySim  # the same town, checking every lot every time
var copy: CitySim  # loaded partway, then given every change sim gets
## A street west of town with open lots both sides, where things are placed.
const X := -700.0
const Z0 := -340.0  # the county road (PerfTown "small": z0 - 60)


func _init() -> void:
	CitySim.verify_ground = true
	Services.verify_rows = true
	var built := CitySim.new()
	built.simulate_traffic = false
	PerfTown.build(built, "small")
	# PerfTown fills in bare buildings: loading gives them every field, as
	# the loaded copy will have.
	sim = _load(built)
	twin = _load(built)
	_both(func(s: CitySim): s.apply({"type": "build_road", "start": [X, Z0], "ctrl": [X, Z0 + 250.0], "end": [X, Z0 + 500.0]}))
	for seg in sim.network.segments:
		var c := sim.network.curve_of(seg)
		if absf(c[0].x - X) < 1.0 and absf(c[2].x - X) < 1.0:
			for side in [-1, 1]:
				_both(func(s: CitySim): s.apply({"type": "zone_frontage", "seg": seg, "side": side, "zone": ZoneMap.Zone.RESIDENTIAL}))
	_tick(5)
	var open := _open_lots()
	_check(open.size() >= 10, "the new street has open lots (%d)" % open.size())
	_full("the town as built")

	# --- Rail: a depot on the county road, then track across the street ---
	var site := Rail.site_near(sim.network, Vector3(-1600.0, 0.0, Z0 - 60.0))
	_check(not site.is_empty(), "a depot fits beside the county road")
	if site.is_empty():
		_done()
		return
	var placed := []
	_both(func(s: CitySim): placed.append(s.apply({"type": "place_rail_depot", "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z], "axis": [site[2].x, site[2].z]})))
	_check(placed.all(func(ok): return ok), "the depot is placed")
	_tick(3)
	_full("after the depot")
	var did: int = sim.rail.depots.keys()[0]
	var pid := -1
	for s in _sims():
		pid = _lay_track(s, did, Z0 + 150.0)
	_tick(3)
	var cover: int = sim.rail._cover.size()
	_check(_lots_under_track(sim) == 0, "no lots left under new track")
	_check(_open_lots().size() < open.size(), "the track took some of the street's lots (%d of %d left)"
		% [_open_lots().size(), open.size()])
	_full("after track is laid")
	# The same track moved one block up the street: as many cells covered,
	# but other ones. The lots under it now must go, those it left come back.
	var hash_was: int = sim.rail.cover_hash
	_both(func(s: CitySim): _shift_track(s, pid, 140.0))
	_tick(3)
	_check(sim.rail._cover.size() == cover, "the swap covers as many cells (%d, %d)" % [sim.rail._cover.size(), cover])
	_check(sim.rail.cover_hash != hash_was, "but the cells' hash changed")
	_check(_lots_under_track(sim) == 0, "no lots under the moved track")
	_full("after a same-length track swap")
	_both(func(s: CitySim): _take_up_track(s, pid))
	_tick(3)
	_full("after the track is taken up")

	# --- A service on the street, then gone ---
	var fs := Services.site_near(sim.network, Services.Kind.FIRE, Vector3(X + 40.0, 0.0, Z0 + 250.0))
	_check(not fs.is_empty(), "a fire station fits on the street")
	placed = []
	_both(func(s: CitySim): placed.append(s.apply({"type": "place_service", "kind": Services.Kind.FIRE,
		"pos": [fs[0].x, fs[0].z], "dir": [fs[1].x, fs[1].z]})))
	_check(placed.all(func(ok): return ok), "the fire station is placed")
	_tick(3)
	_full("after a service is placed")

	# --- Saved and loaded: from here on the copy gets every change too ---
	copy = _load(sim)
	_tick(3)
	# The planner's working state ("plan") comes back to match over the
	# next few checks, as on main; the town itself must match at once.
	_agree("just after loading", ["plan"])
	var svc: int = sim.services.buildings.keys().max()
	_both(func(s: CitySim): s.apply({"type": "remove_service", "id": svc}))
	_tick(3)
	_full("after the service is removed")
	_agree("after the service is removed")

	# Rail again: laid, swapped and taken up after the load.
	var pid2 := -1
	for s in _sims():
		pid2 = _lay_track(s, did, Z0 + 320.0)
	_tick(3)
	_full("after track is laid (after loading)")
	_both(func(s: CitySim): _shift_track(s, pid2, -140.0))
	_tick(3)
	_full("after a same-length swap (after loading)")
	_agree("after a same-length swap")
	_both(func(s: CitySim): _take_up_track(s, pid2))
	_tick(3)
	_full("after track is taken up (after loading)")

	# --- Farm fields over the street's lots, then given up ---
	var fid: int = sim.farms.farms.keys()[0]
	var cells := _farm_cells_over_lots(fid)
	_check(not cells.is_empty(), "farm fields can cover lots (%d cells)" % cells.size())
	_both(func(s: CitySim): _farm_fields(s, fid, cells, true))
	_tick(3)
	_check(_lots_on_fields(sim, fid) == 0, "no lots under the new fields")
	_full("after farm fields are planted")
	_agree("after farm fields are planted")
	_both(func(s: CitySim): _farm_fields(s, fid, cells, false))
	_tick(3)
	_full("after the fields are given up")

	# --- A company with a pad on the street ---
	var hq := Vector3(X - 300.0, 0.0, Z0 + 250.0)
	_both(func(s: CitySim):
		s.industry.add_site("oil", hq, Vector3(1, 0, 0), [hq, Vector3(X, 0.0, hq.z)])
		s.mark_lots_dirty())
	_tick(3)
	var iid: int = sim.industry.sites.keys().max()
	var pad := _pad_over_lots(iid)
	_both(func(s: CitySim):
		s.industry.sites[iid].pads.append(pad)
		s.mark_lots_dirty())
	_tick(3)
	_check(_lots_owned(sim) == 0, "no lots on the company's ground")
	_full("after a company pad")
	_agree("after a company pad")
	_both(func(s: CitySim):
		s.industry.sites[iid].pads.erase(pad)
		s.mark_lots_dirty())
	_tick(3)
	_full("after the pad goes")

	# --- A hub: placed, moved along the street, removed ---
	var hs := CivicHubs.site_near(sim.network, Vector3(X + 60.0, 0.0, Z0 + 120.0))
	_check(not hs.is_empty(), "a cemetery fits on the street")
	placed = []
	_both(func(s: CitySim): placed.append(s.apply({"type": "place_hub", "kind": "cemetery",
		"pos": [hs[0].x, hs[0].z], "dir": [hs[1].x, hs[1].z]})))
	_check(placed.all(func(ok): return ok), "the cemetery is placed")
	_tick(3)
	_full("after a hub is placed")
	var hid: int = sim.hubs.hubs.keys().max()
	var moved := []
	_both(func(s: CitySim): moved.append(s.apply(MoveIt.command([{"type": "hub", "id": hid}], hs[0], Vector3(0, 0, 140)))))
	_check(moved.all(func(ok): return ok), "the cemetery moves up the street")
	_tick(3)
	_full("after a hub moves")
	_agree("after a hub moves")
	_both(func(s: CitySim): s.apply({"type": "remove_hub", "id": hid}))
	_tick(3)
	_full("after the hub is removed")
	_agree("at the end")

	_check(CitySim.ground_mismatches == 0, "every lot check's shortcut matched the full check (%d mismatches)"
		% CitySim.ground_mismatches)
	_check(Services.rows_mismatches == 0, "every kept service row matched one worked out afresh (%d mismatches)"
		% Services.rows_mismatches)
	_done()


# --- Changes ------------------------------------------------------------------

## A straight piece of built track across the street at z, from the depot's
## railroad. Returns its piece id.
func _lay_track(s: CitySim, depot: int, z: float) -> int:
	var pts := []
	for x in range(int(X) - 200, int(X) + 201, 20):
		pts.append(Vector3(x, 0.0, z))
	var a := s.rail._add_node(pts[0])
	var b := s.rail._add_node(pts[-1])
	return s.rail._add_piece(a, b, pts, "yard", depot, -1, -1.0)


## Slides a piece and its ends by dz (a whole number of 10 m cells).
func _shift_track(s: CitySim, pid: int, dz: float) -> void:
	var pc: Dictionary = s.rail.pieces[pid]
	var pts := []
	for p in pc.pts:
		pts.append(p + Vector3(0.0, 0.0, dz))
	pc.pts = pts
	s.rail.nodes[pc.a] = pts[0]
	s.rail.nodes[pc.b] = pts[-1]
	s.rail._dirty = true


func _take_up_track(s: CitySim, pid: int) -> void:
	var pc: Dictionary = s.rail.pieces[pid]
	s.rail.pieces.erase(pid)
	s.rail.nodes.erase(pc.a)
	s.rail.nodes.erase(pc.b)
	s.rail._dirty = true


## The farm's field cells under the street's west side lots.
func _farm_cells_over_lots(fid: int) -> Array:
	var f: Dictionary = sim.farms.farms[fid]
	var out := []
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		if absf(lot.pos.x - X) < 60.0 and lot.pos.x < X and lot.pos.z > Z0 + 380.0:
			var local := Farms._local(f, lot.pos)
			var c := Vector2i(roundi(local.x / Farms.CELL), roundi(local.y / Farms.CELL))
			if not c in out and not c in f.cells:
				out.append(c)
	return out


## Plants (or gives up) fields as the farm's own leader does: only the lots
## by what changed are checked again (CitySim.lots_changed_near).
func _farm_fields(s: CitySim, fid: int, cells: Array, on: bool) -> void:
	var before := s.farms.ground_boxes()
	for c in cells:
		if on:
			s.farms.farms[fid].cells.append(c)
		else:
			s.farms.farms[fid].cells.erase(c)
	s.lots_changed_near(CitySim._farm_boxes(before, s.farms.ground_boxes()))
	s._lots_light = true
	s.farms_changed.emit()


## A pad cell of the company's under a lot on the street's west side.
func _pad_over_lots(iid: int) -> Vector2i:
	var st: Dictionary = sim.industry.sites[iid]
	var right := Vector3(-st.dir.z, 0.0, st.dir.x)
	for key in sim.lots:
		var lot: Dictionary = sim.lots[key]
		if absf(lot.pos.x - X) < 60.0 and lot.pos.x < X and absf(lot.pos.z - st.pos.z) < 100.0:
			var d: Vector3 = lot.pos - st.pos
			return Vector2i(roundi(d.dot(right) / Industry.PAD), roundi(-d.dot(st.dir) / Industry.PAD))
	return Vector2i(0, 2)


# --- Checks -------------------------------------------------------------------

func _sims() -> Array:
	return [sim, twin] if copy == null else [sim, twin, copy]


func _load(from: CitySim) -> CitySim:
	var s := CitySim.new()
	s.from_dict(JSON.parse_string(JSON.stringify(from.to_dict(), "", false, true)))
	s.simulate_traffic = false
	return s


func _both(f: Callable) -> void:
	for s in _sims():
		f.call(s)


func _tick(n: int) -> void:
	for i in n:
		for s in _sims():
			if s == twin:
				# Forgets what kept lots off the ground, so its next lot
				# check looks at every lot; and every check is a full one.
				s._ground_was = {}
				if s._lots_light or not s._lots_near.is_empty():
					s._lots_dirty = true
			s.tick()


func _open_lots() -> Array:
	var out := []
	for key in sim.lots:
		if absf(sim.lots[key].pos.x - X) < 80.0 and sim.lots[key].pos.z > Z0 + 10.0:
			out.append(key)
	return out


func _lots_under_track(s: CitySim) -> int:
	var n := 0
	for key in s.lots:
		var lot: Dictionary = s.lots[key]
		for p in [lot.pos, lot.front, lot.zone_pt]:
			if s.rail.covers(p):
				n += 1
				break
	return n


func _lots_on_fields(s: CitySim, fid: int) -> int:
	var n := 0
	for key in s.lots:
		if s.farms.field_at(s.lots[key].pos) == fid:
			n += 1
	return n


func _lots_owned(s: CitySim) -> int:
	var n := 0
	for key in s.lots:
		var lot: Dictionary = s.lots[key]
		for p in [lot.pos, lot.front, lot.zone_pt]:
			if Capital.owner_of(s, p) != "":
				n += 1
				break
	return n


## The town's lots (and the loaded copy's) match its twin's, which checked
## every lot, and no lot of any of them has anything standing on it.
func _full(what: String) -> void:
	for s in _sims():
		var blocked := 0
		for key in s.lots:
			if s._lot_blocked(s.lots[key]):
				blocked += 1
		var differ := []
		for key in s.lots:
			if not twin.lots.has(key) or twin.lots[key].corners != s.lots[key].corners:
				differ.append(key)
		for key in twin.lots:
			if not s.lots.has(key):
				differ.append(key)
		var who := " (twin)" if s == twin else (" (loaded copy)" if s == copy else "")
		_check(blocked == 0 and differ.is_empty(), "%s%s: the lots match a full check (%d lots, %d blocked, %d differ %s)"
			% [what, who, s.lots.size(), blocked, differ.size(), str(differ.slice(0, 4))])


## The saved and loaded copy still matches the town it came from.
func _agree(what: String, skip := []) -> void:
	if copy == null:
		return
	var da := copy.to_dict()
	var db := sim.to_dict()
	var diff := []
	for k in db:
		if not k in skip and JSON.stringify(da.get(k)) != JSON.stringify(db[k]):
			diff.append(k)
	_check(diff.is_empty(), "%s: the copies agree %s" % [what, str(diff)])


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _done() -> void:
	print("RESULT: %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)
