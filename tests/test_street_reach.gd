extends SceneTree
## Run: godot --headless -s tests/test_street_reach.gd
## Street reach, after Cities: Skylines (Brawn, 2026-10-29): picking a
## station shows the ones already built on the streets, red where homes sit
## past every reach, with the new one's reach added from where it would go;
## a clicked station shows just its own; parks, landfills and the mail
## tint the streets they reach too.

var _failed := false


func _init() -> void:
	var sim := CitySim.new()
	sim.economy.money = 50_000_000
	# A long main road: the fire station at the west end, homes at both ends.
	for x in range(-3000, 3000, 1000):
		sim.apply({"type": "build_road", "start": [x, 0], "ctrl": [x + 500, 0], "end": [x + 1000, 0]})
	for x in [-2900, -2800, 2800, 2900]:
		sim.apply({"type": "paint_zone", "center": [x, -25], "radius": 12, "zone": ZoneMap.Zone.RESIDENTIAL})
	var site := Services.site_near(sim.network, Services.Kind.FIRE, Vector3(-2600, 0, -40))
	_check(sim.apply({"type": "place_service", "kind": Services.Kind.FIRE, "pos": [site[0].x, site[0].z],
		"dir": [site[1].x, site[1].z]}), "a fire station at the west end")
	for i in 30:
		sim.tick()
	sim.update_stats()
	_check(not sim.lots.is_empty(), "lots platted at both ends (%d)" % sim.lots.size())
	var sid: int = sim.services.buildings.keys()[0]

	var view := ServiceView.new()
	get_root().add_child(view)
	view.setup(sim)

	# Picking a fire station: the built one's reach, and the far homes red.
	view.show_kind = Services.Kind.FIRE
	var c := _colors(view)
	_check(_has(c, ServiceView.COVER_COLOR), "the streets the station reaches are green")
	_check(_has(c, ServiceView.GAP_COLOR), "the homes past its reach are red")
	# From where a new one would go, at the east end, the gap fills in.
	var reach := float(Services.KINDS[Services.Kind.FIRE].reach)
	view.preview = sim.services.reach_from(sim.network, Vector3(2700, 0, 0), reach)
	_check(not _has(_colors(view), ServiceView.GAP_COLOR), "a second station at the east end covers the gap")
	var far := 0.0
	for n in view.preview:
		far = maxf(far, float(view.preview[n]))
	_check(far <= reach, "its reach is worked out only as far as it goes (%.0f m)" % far)
	view.preview = {}
	view.show_kind = -1
	_check(not view._coverage.visible, "nothing in hand: nothing on the streets")

	# A clicked station: its own reach, no red.
	view.focus = {"type": "service", "id": sid}
	c = _colors(view)
	_check(_has(c, ServiceView.COVER_COLOR) and not _has(c, ServiceView.GAP_COLOR), "a clicked station shows just its reach")
	var own := sim.services.reach_of(sim.network, sid, reach)
	_check(not own.is_empty() and own.size() < sim.network.nodes.size(), "one station's reach stops at its edge")
	view.focus = {"type": "lot", "id": "x"}
	_check(not view._coverage.visible, "a lot has no reach to show")
	view.focus = {}

	# A hospital counts as the clinic in the Health view.
	_check(ServiceView.ALSO[Services.Kind.CLINIC].has(Services.Kind.HOSPITAL), "a hospital serves as a clinic")
	view.show_kind = Services.Kind.CLINIC
	_check(_has(_colors(view), ServiceView.GAP_COLOR) and not _has(_colors(view), ServiceView.COVER_COLOR),
		"no clinic yet: every lined street is red")
	view.show_kind = -1

	# Area effects: green for a lift, brown for a drag, fading out.
	_check(ServiceView.area_color(0.01).a == 0.0, "too little to show")
	_check(ServiceView.area_color(0.8).is_equal_approx(Color(ServiceView.LIFT_COLOR,
		ServiceView.LIFT_COLOR.a * (0.25 + 0.75 * 0.8))), "a lift is green")
	_check(ServiceView.area_color(-1.0) == ServiceView.DRAG_COLOR, "a full drag is brown")
	_check(ServiceView.area_color(-0.3).a < ServiceView.area_color(-0.9).a, "and fades with distance")
	var ls := CivicHubs.site_near(sim.network, Vector3(0, 0, -60))
	if not ls.is_empty() and sim.apply({"type": "place_hub", "kind": "landfill", "pos": [ls[0].x, ls[0].z],
			"dir": [ls[1].x, ls[1].z]}):
		var hid: int = sim.hubs.hubs.keys()[0]
		_check(sim.hubs.lift_from(hid, sim.hubs.hubs[hid].pos) < 0.0, "a landfill drags its own land down")
		_check(is_equal_approx(sim.hubs.lift_reach(hid), float(Balance.WASTE_SITES.landfill.reach)), "out to its reach")
		view.focus = {"type": "hub", "id": hid}
		var hc := _colors(view)
		var brown := false
		for col in hc:
			brown = brown or (col.r > col.g and col.a > 0.0)
		_check(brown, "a clicked landfill tints the road by it brown")
		view.focus = {}
	else:
		_check(false, "a landfill by the road")

	view.queue_free()
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


## The colours on the streets now.
func _colors(view: ServiceView) -> Array:
	if not view._coverage.visible or view._coverage.mesh == null:
		return []
	var out := []
	var mesh: Mesh = view._coverage.mesh
	for i in mesh.get_surface_count():
		for col in mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR]:
			if not out.has(col):
				out.append(col)
	return out


## Whether `col` is among them (vertex colours keep 8 bits a channel).
func _has(colors: Array, col: Color) -> bool:
	for c in colors:
		if absf(c.r - col.r) < 0.01 and absf(c.g - col.g) < 0.01 and absf(c.b - col.b) < 0.01 and absf(c.a - col.a) < 0.01:
			return true
	return false


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
