class_name DoorLog
extends RefCounted
## Where a builder drew the doors that open: garage doors now, and dock,
## bay, shed and roll-up doors as their steps come (docs/spec-working-doors.md).
## Each door function logs its door with add(), as the builders keep
## _glass_log for windows. A house plan then carries its doors in its info
## (take()), so they ride along wherever the plan is placed: mirrored for a
## garage on the left and moved back to the lot's setback with the rest of
## its info (HouseBuilder._placed_info), and on to SiteLayout, where the
## traffic finds the door each garage spot faces (DoorEvents).
##
## A door is [kind, centre, facing, width, height, colour] in the builder's
## local space (x across the lot, y up, -z toward the street): centre is
## the middle of the closed door's outside face, facing points out of it.
## Logging draws nothing and takes no random numbers, so every building is
## drawn exactly as before.
##
## Kinds: "garage" (a home's sectional door), "dock" (a warehouse's dock
## door), "bay" (a factory's or a service building's 12 x 14 ft overhead
## door, CivicBuilder._overhead_door), "rollup" (a shop's stockroom
## shutter) and "slider" (a machine shed's or Quonset's sliding leaves).
##
## A view that draws a whole building (a factory, a shop, a service
## building, a farmstead) keeps the doors its builder logged while drawing
## it (collect), so the door view can open them where they are drawn.

## While a caller collects (collect()), every door logged, in the frame the
## builder draws in; null otherwise.
static var drawn = null


## Notes a door builder `b` just drew.
static func add(b: Object, kind: String, centre: Vector3, facing: Vector3, width: float, height: float,
		colour: Color) -> void:
	var log: Array = b.get_meta("door_log", [])
	var d := [kind, centre, facing, width, height, colour]
	log.append(d)
	b.set_meta("door_log", log)
	if drawn != null:
		drawn.append(d)  # (the same entry, not a copy)


## The doors logged while `draw` runs (it draws one building): the list a
## view keeps beside the building's drawing. An outer collection is put
## back after (it doesn't see the inner one's doors). In the browser, which
## has no door view, it only draws and collects nothing.
static func collect(draw: Callable) -> Array:
	if OS.has_feature("web"):
		draw.call()
		return []
	var keep = drawn
	drawn = []
	draw.call()
	var out: Array = drawn
	drawn = keep
	return out


## Moves the doors `b` logged while drawing a plan into the plan's `info`.
## doors_x and doors_z start at 0: placing the plan mirrors and moves every
## *_x and *_z key, so on a lot they say where the plan's origin went.
static func take(b: Object, info: Dictionary) -> void:
	info.doors = b.get_meta("door_log", [])
	info.doors_x = 0.0
	info.doors_z = 0.0
	if b.has_meta("door_log"):
		b.remove_meta("door_log")


## A placed plan's doors (its info as HouseBuilder.plan_info gives it) in
## the lot's frame: [[kind, centre, facing, width, height, colour], ...].
static func placed(info: Dictionary) -> Array:
	var out := []
	var flip: bool = float(info.get("gs", 1.0)) < 0.0
	var at := Vector3(float(info.get("doors_x", 0.0)), 0.0, float(info.get("doors_z", 0.0)))
	for d in info.get("doors", []):
		var c: Vector3 = d[1]
		var f: Vector3 = d[2]
		if flip:
			c.x = -c.x
			f.x = -f.x
		out.append([d[0], c + at, f, d[3], d[4], d[5]])
	return out
