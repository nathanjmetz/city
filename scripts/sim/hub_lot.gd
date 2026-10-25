class_name HubLot
extends RefCounted
## A hub's lot growing into the land next door: a strip behind it, or beside
## it once it's deep, never past Balance.HUB_MAX_GROWTH times its first
## size. Empty lots can be taken; built homes and shops only through a land
## permit (BusNet.land_free says which). The builder's yard uses this; the
## bus depot and taxi company still have their own copies of it.


## Grows service `id`'s lot by `step` metres if the land is free: ["ok"],
## ["built", [x, z], [w, d]] when only homes or shops stand in the way (the
## strip a permit would buy), or ["no"].
static func grow(sim: CitySim, id: int, step: float) -> Array:
	var b: Dictionary = sim.services.buildings[id]
	var size := Services.size_of(b)
	var first: Vector2 = Services.KINDS[b.kind].size
	var side := Vector3(-b.dir.z, 0.0, b.dir.x)
	var tries := [[Vector2(0, step), -b.dir * step * 0.5],
		[Vector2(step, 0), side * step * 0.5], [Vector2(step, 0), -side * step * 0.5]]
	if size.y >= size.x * 2.0:
		tries = [tries[1], tries[2], tries[0]]
	var built := []
	for t in tries:
		var new_size: Vector2 = size + t[0]
		if new_size.x * new_size.y > first.x * first.y * Balance.HUB_MAX_GROWTH:
			continue
		var pos: Vector3 = b.pos + t[1]
		var why := BusNet.land_free(sim, id, pos, b.dir, new_size)
		if why == "":
			b.pos = pos
			b.size = new_size
			sim.buildings_changed.emit()
			return ["ok"]
		if why == "built" and built.is_empty():
			built = [[pos.x, pos.z], [new_size.x, new_size.y]]
	if not built.is_empty():
		return ["built", built[0], built[1]]
	return ["no"]
