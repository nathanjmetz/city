class_name PerfBudget
extends RefCounted
## How much time, drawing and memory each system may use, so the game stays
## smooth on a typical Mac or Windows PC and in the browser.
##
## The frame is 16.7 ms at 60 frames a second. At the top speed (4x) the
## simulation runs 40 ticks a second, so a tick that averages 3 ms takes
## 120 ms of every second: about 7 ms a frame, with the rest left for drawing.
## The browser runs the same code about twice as slowly on one thread, which
## these budgets leave room for.
##
## Every new system gets a line here. Numbers are measured on the big test
## town (PerfTown "big", about 10,000 people) by tools/perf_run.gd.
##   per_tick: average ms per tick, counting rare work spread over every tick
##   max: worst single tick, in ms; above about 8 ms the player sees a hitch

const SIM := {
	"sim.tick":         {"per_tick": 3.0, "max": 12.0, "what": "The whole simulation tick"},
	"sim.traffic":      {"per_tick": 1.6, "max": 6.0, "what": "Cars driving, lanes, junctions"},
	"sim.logistics":    {"per_tick": 0.2, "max": 4.0, "what": "Freight trips between businesses"},
	"sim.lots":         {"per_tick": 0.3, "max": 8.0, "what": "Lot survey after road and zone changes"},
	"sim.people":       {"per_tick": 0.3, "max": 4.0, "what": "Move-ins and jobs"},
	"sim.stats":        {"per_tick": 1.0, "max": 6.0, "what": "Demand, happiness, services and the budget"},
	"sim.growth":       {"per_tick": 0.2, "max": 3.0, "what": "New buildings going up"},
	"sim.vegetation":   {"per_tick": 0.1, "max": 4.0, "what": "Wild trees and brush regrowing"},
	"sim.farms":        {"per_tick": 0.05, "max": 6.0, "what": "Farm decisions"},
	"sim.industry":     {"per_tick": 0.05, "max": 6.0, "what": "Oil, ore and forestry decisions"},
	"sim.education":    {"per_tick": 0.05, "max": 6.0, "what": "Schools and campuses deciding"},
	"sim.school_trips": {"per_tick": 0.1, "max": 3.0, "what": "School buses at bell times"},
	"sim.banks":        {"per_tick": 0.05, "max": 6.0, "what": "Banks lending and deciding"},
	"sim.warehouses":   {"per_tick": 0.05, "max": 6.0, "what": "Warehouse decisions"},
	"sim.parks":        {"per_tick": 0.05, "max": 6.0, "what": "Parks filling in and growing"},
	"sim.power":        {"per_tick": 0.05, "max": 6.0, "what": "Power company decisions"},
	"sim.water":        {"per_tick": 0.05, "max": 6.0, "what": "Water utility decisions"},
	"sim.hub_leaders":  {"per_tick": 0.1, "max": 8.0, "what": "Monthly leader decisions (development trees)"},
	"sim.families":     {"per_tick": 0.05, "max": 6.0, "what": "Monthly family business decisions"},
	"sim.heritage":     {"per_tick": 0.05, "max": 6.0, "what": "Monthly heritage, markers, culture, leader asks, timelapse"},
	"sim.care":         {"per_tick": 0.05, "max": 8.0, "what": "Monthly property upkeep (a sixth of town an hour) and developers' asks"},
	"sim.civic_hubs":   {"per_tick": 0.2, "max": 6.0, "what": "Landfill, recycling, cemetery, garbage trucks"},
	"sim.mail":         {"per_tick": 0.1, "max": 4.0, "what": "Mail carriers and routes"},
	"sim.pollution":    {"per_tick": 0.2, "max": 6.0, "what": "Smoke, noise and dirty ground"},
	"sim.healthcare":   {"per_tick": 0.1, "max": 6.0, "what": "Hospital, ambulances and care"},
	"sim.telecom":      {"per_tick": 0.05, "max": 6.0, "what": "Phone company decisions"},
	"sim.rail":         {"per_tick": 0.1, "max": 4.0, "what": "Rail depots, trains and crossings"},
	"sim.buses":        {"per_tick": 0.1, "max": 4.0, "what": "Bus depots and routes"},
	"sim.permits":      {"per_tick": 0.05, "max": 3.0, "what": "Hub leaders' permit requests"},
	"sim.trade":        {"per_tick": 0.05, "max": 6.0, "what": "Monthly trade with neighbors"},
	"sim.tourism":      {"per_tick": 0.1, "max": 4.0, "what": "Fair and football events, visitors"},
}

## Per drawn frame, ms of CPU, on a typical PC.
const FRAME := {
	"frame.sim":       {"avg": 7.0, "max": 14.0, "what": "Simulation ticks run this frame"},
	"frame.vehicles":  {"avg": 1.5, "max": 4.0, "what": "Placing every vehicle on screen"},
	"frame.buildings": {"avg": 0.5, "max": 20.0, "what": "Adding new buildings to the scene"},
	"frame.trees":     {"avg": 0.3, "max": 10.0, "what": "Tree batches"},
	"frame.roads":     {"avg": 0.3, "max": 30.0, "what": "Road meshes (rebuilt after an edit)"},
	"frame.terrain":   {"avg": 1.0, "max": 8.0, "what": "Ground chunks: detail levels and grading under new roads"},
	"frame.audio":     {"avg": 0.5, "max": 2.0, "what": "Placing sounds on real objects"},
	"frame.ui":        {"avg": 0.5, "max": 3.0, "what": "HUD and panels"},
	"frame.quality":   {"avg": 0.05, "max": 0.5, "what": "Desktop quality governor"},
}

## Whole-frame limits for the drawing side.
const RENDER := {
	"draw_calls":  {"desktop": 2500, "web": 1500, "what": "Draw calls in a frame (each one costs CPU)"},
	"primitives":  {"desktop": 4_000_000, "web": 2_000_000, "what": "Triangles drawn in a frame"},
	"objects":     {"desktop": 6000, "web": 4000, "what": "Visible objects in a frame"},
	"memory_mb":   {"desktop": 1024, "web": 512, "what": "Memory the game itself uses"},
	"fps":         {"desktop": 60, "web": 30, "what": "Frames a second, at least"},
}


## "ok", "warn" (over 80% of budget) or "over".
static func grade(value: float, budget: float) -> String:
	if value > budget:
		return "over"
	return "warn" if value > budget * 0.8 else "ok"


## A plain text table of a perf_run.gd report against the budgets.
static func sim_table(report: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("Town: %s, %d people, %d buildings, %d road pieces, %d vehicles, %.0f MB" % [
		report.size, report.population, report.buildings, report.segments, report.vehicles, report.memory_mb])
	lines.append("%-17s %9s %7s %9s %7s  %s" % ["system", "ms/tick", "budget", "worst ms", "budget", ""])
	var keys: Array = report.systems.keys()
	keys.sort_custom(func(a, b): return report.systems[a].per_tick > report.systems[b].per_tick)
	for key in keys:
		var s: Dictionary = report.systems[key]
		var b: Dictionary = SIM.get(key, {})
		var flag := "(no budget)"
		if not b.is_empty():
			var g1 := grade(s.per_tick, b.per_tick)
			var g2 := grade(s.max, b.max)
			flag = "OVER" if "over" in [g1, g2] else ("near" if "warn" in [g1, g2] else "ok")
		lines.append("%-17s %9.3f %7.2f %9.2f %7.1f  %s" % [key, s.per_tick, b.get("per_tick", 0.0),
			s.max, b.get("max", 0.0), flag])
	return "\n".join(lines)
