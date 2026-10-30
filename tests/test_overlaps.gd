extends SceneTree
## Run: godot --headless -s tests/test_overlaps.gd
## Nothing new stands on ground something else has taken (Nathan,
## 2026-10-29: "railroad tracks running right through the city ... They run
## right underneath the buildings. I also noticed street signs in the middle
## of driveways."). Runs the overlap auditor (tools/overlap_audit.gd) on the
## small test town (the county map at the region origin, where a railroad
## already runs through it) and on the same town grown over the real county
## map on a main line (CountyTrains corridor 0), and fails on any clash in
## its "never" pairs beyond today's known ones (KNOWN). Those counts may only go down: when a fix
## lowers one, lower it here too, so it can't creep back.
##
## Also checks the auditor itself: it finds the things it should (so an
## empty audit can't pass), and a clash planted far out of town is caught.

const Audit := preload("res://tools/overlap_audit.gd")

## Today's known clashes (2026-10-30), per town: "a vs b" -> the most allowed.
## The county's railroads come first now (#943): no lot, building, drive,
## parking, public site or street on their right of way; streets cross only
## at grade crossings. Left on the track: a few posts at a junction beside a
## crossing. No count here is above main's before #943.
const KNOWN := {
	"small": {
		"rail_bed:county vs post:stop_sign": 2,
		"rail_bed:county vs post:signal_pole": 1,
		"building vs public_site": 5,
		"post:stop_sign vs curb_cut": 5,
		"post:streetlight vs curb_cut": 3,
		"post:mailbox vs curb_cut": 32,
		"post:mailbox vs curb_ramp": 5,
		"tree_trunk vs curb_ramp": 1,
		"lot vs lot": 31,
	},
	"county_small": {
		"rail_bed:county vs post:stop_sign": 1,
		"building vs public_site": 4,
		"post:stop_sign vs curb_cut": 3,
		"post:streetlight vs curb_cut": 9,
		"post:mailbox vs curb_cut": 35,
		"post:mailbox vs curb_ramp": 7,
		"lot vs lot": 24,
	},
}
## Kinds the audit must find in each town, at least this many.
const MIN_SHAPES := {"building": 200, "lot": 200, "road": 500, "sidewalk_line": 500, "drive": 50, "curb_cut": 50,
	"front_walk": 20, "curb_ramp": 50, "crosswalk": 50, "post:stop_sign": 20, "post:signal_pole": 4,
	"post:no_turn_sign": 1, "post:street_name": 10, "post:streetlight": 20, "post:utility_pole": 10, "post:mailbox": 20,
	"tree_trunk": 50, "prop": 50, "parking_stall": 50, "rail_bed:county": 100, "drive_car": 5, "garage_apron": 20}

var _failed := false


func _initialize() -> void:
	for name in KNOWN:
		var sim := Audit.town(name)
		# A clash planted far out of town: town track under a building.
		var far := Vector2(9000.0, 9000.0)
		var planted := [["rail_bed", "town", "planted:rail", Audit._obb(far, Vector2.RIGHT, 20.0, 2.3)],
			["building", "house", "planted:house", Audit._sq(far, 5.0)]]
		var res := Audit.audit(sim, planted)
		var got := Audit.never_counts(res)
		var key := "rail_bed:town vs building"
		_check(int(got.get(key, 0)) == 1, "%s: a planted clash (%s) is caught (%d)" % [name, key, int(got.get(key, 0))])
		got.erase(key)
		for kind in MIN_SHAPES:
			var n := int(res.shapes.get(kind, 0))
			_check(n >= MIN_SHAPES[kind], "%s: the audit finds %s (%d, at least %d)" % [name, kind, n, MIN_SHAPES[kind]])
		var known: Dictionary = KNOWN[name]
		for k in got:
			# A big count gets 2 % slack for float rounding on other
			# machines (the cloud runs Linux); a small one none.
			var allowed := int(known.get(k, 0))
			allowed += allowed / 50
			_check(int(got[k]) <= allowed, "%s: %s no more than the %d known (%d)" % [name, k, int(known.get(k, 0)), int(got[k])])
		for k in known:
			if int(got.get(k, 0)) < int(known[k]):
				print("note %s: %s is down to %d from %d: lower KNOWN" % [name, k, int(got.get(k, 0)), int(known[k])])
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
