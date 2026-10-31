extends SceneTree
## What the ground map costs in the big test town (docs/spec-ground-map.md,
## step 1): how long it takes to build (reading the footprints, filing
## them), the memory it holds, and what one ask costs, at grid squares of
## 12, 16 and 24 m.
##
## Run headless only, with HOME set to a scratch folder:
##   HOME=/tmp/x godot --headless -s tools/ground_map_bench.gd [-- --town=perf_big]
## Towns are the overlap auditor's (tools/overlap_audit.gd town): perf_big
## (PerfTown big as built, the default) or look_round.

const Audit := preload("res://tools/overlap_audit.gd")
const CELLS := [12.0, 16.0, 24.0]


func _initialize() -> void:
	if not Audit._throwaway_home():
		printerr("ground_map_bench: refusing to run: the user folder is %s. Set HOME to a scratch folder." % OS.get_user_data_dir())
		quit(1)
		return
	var town := "perf_big"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--town="):
			town = a.trim_prefix("--town=")
	var t0 := Time.get_ticks_msec()
	var sim := Audit.town(town)
	print("ground_map_bench: %s built in %.1f s: %d buildings, %d lots, %d roads" % [town,
		(Time.get_ticks_msec() - t0) / 1000.0, sim.buildings.size(), sim.lots.size(), sim.network.segments.size()])
	# Reading the footprints (runs every building's builder once).
	var tc := Time.get_ticks_usec()
	var shapes := GroundFootprints.collect(sim)
	var collect_ms := (Time.get_ticks_usec() - tc) / 1000.0
	print("ground_map_bench: read %d footprints in %.0f ms" % [shapes.size(), collect_ms])
	print("| Square | File (ms) | Claims | Pieces | Squares | Pieces per square | Memory (MB) | Counted (MB) | Ask: post (us) | Ask: building (us) | Ask: lot (us) | Curb gap 30 m (us) |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|")
	for cell in CELLS:
		var before := OS.get_static_memory_usage()
		var map := GroundMap.new(cell)
		map.fill_from(sim, shapes)
		var held := OS.get_static_memory_usage() - before
		var st := map.stats()
		var spots := []
		for p in range(0, map._p_claim.size(), 10):
			spots.append(map._piece_box(p).get_center())
		var post := _time(map, spots, "post:mailbox", 0.25)
		var house := _time(map, spots, "building", 5.0)
		var lot := _time(map, spots, "lot", 12.0)
		var curb := _time_curb(map)
		print("| %.0f m | %.0f | %d | %d | %d | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |" % [cell, map.last_file_ms,
			st.claims, st.pieces, st.cells, float(st.grid_refs) / maxf(st.cells, 1), held / 1048576.0, st.bytes / 1048576.0,
			post, house, lot, curb])
		map = null
	# Built the way the game would: read and filed in one go.
	var tb := Time.get_ticks_usec()
	var whole := GroundMap.build(sim)
	print("ground_map_bench: built whole at %.0f m squares in %.0f ms (reading %.0f ms, filing %.0f ms); %d curb claims on %d street sides" % [
		whole.cell, (Time.get_ticks_usec() - tb) / 1000.0, whole.last_collect_ms, whole.last_file_ms,
		whole.stats().curb_claims, whole.stats().curb_sides])
	quit(0)


## Microseconds one ask takes: a square `half` either way round each spot.
func _time(map: GroundMap, spots: Array, kind: String, half: float) -> float:
	var t := Time.get_ticks_usec()
	for q in spots:
		map.ask(kind, GroundFootprints._sq(q, half))
	return float(Time.get_ticks_usec() - t) / maxf(spots.size(), 1)


## Microseconds a 30 m free-curb search takes, at every curb cut.
func _time_curb(map: GroundMap) -> float:
	var asks := []
	for id in map.all_claims():
		if map.kind_of(id) == "curb_cut" and map._curb[id * 2] >= 0:
			var k: int = map._curb[id * 2]
			asks.append([k / 2, 1 if k % 2 == 1 else -1, map._curb_s[id * 2]])
	var t := Time.get_ticks_usec()
	for a in asks:
		map.curb_gap(a[0], a[1], a[2], 30.0)
	return float(Time.get_ticks_usec() - t) / maxf(asks.size(), 1)
