class_name LotGround
extends RefCounted
## Everything that keeps lots off the ground (CitySim._lot_blocked looks at
## all of it), item by item: a service building, a farm, a hub's land, a
## company's pads... Each is kept as [a hash of its shape, the boxes it
## covers], or [hash, null] when its ground is too spread out to box (then
## a change to it means checking every lot).
##
## When something changes that could keep lots off the ground, the town
## compares these with the last full check's (diff): only lots in the boxes
## of what came, went or changed shape can have gained or lost something
## under them, so only they are checked again, not every lot in town (three
## seconds in a 69,000-person town). The answers are the same either way.

## A little room around every box, for rounding.
const MARGIN := 1.0


static func items(sim: CitySim) -> Dictionary:
	var out := {}
	# Service buildings (services.at, overlaps) and water utilities' yard
	# pieces (services.covers).
	for id in sim.services.buildings:
		var b: Dictionary = sim.services.buildings[id]
		var fp := sim.services.footprint(id)
		out["svc:%d" % id] = [hash([b.kind, b.pos, b.dir, Services.size_of(b), fp]), [_box(fp)]]
	var water := sim.services.water
	for id in water.utilities:
		var polys := []
		var b: Dictionary = sim.services.buildings.get(id, {})
		if not b.is_empty():
			for work in water.utilities[id].works:
				var c: Vector2i = work[1]
				if c != Vector2i.ZERO and c.x > -99:
					polys.append(WaterUtility.cell_corners(b, c))
		out["water:%d" % id] = [hash(polys), _boxes(polys)]
	# Farms: yards, lanes, fields and barns (Capital.owner_of).
	var farm_ground := sim.farms.ground_boxes()
	for id in farm_ground:
		out["farm:%d" % id] = [farm_ground[id][0], [farm_ground[id][1]]]
	# Companies: yards, roads in, add-ons, pads and their working ground,
	# leases, land bought and woods (Industry.claim_at).
	var buffer := float(Balance.INDUSTRY_CLAIM_BUFFER) + MARGIN
	for id in sim.industry.sites:
		var s: Dictionary = sim.industry.sites[id]
		var cells: Array = Array(s.pads) + Array(s.get("leases", [])) + s.get("owned", {}).keys() \
			+ s.get("cut", {}).keys() + s.get("regrow", {}).keys()
		var boxes := [_box(sim.industry._yard(s))]
		for c in cells:
			boxes.append(_box(Industry.pad_corners(s, c)).grow(buffer))
		boxes.append_array(_drive_boxes(s.drive, Farms.DRIVE_WIDTH * 0.5 + 3.0))
		var right := Vector3(-s.dir.z, 0.0, s.dir.x)
		for node in s.get("addons", {}):
			var r := Industry.addon_rect(s, node).grow(2.0)
			var poly := PackedVector2Array()
			for k in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
				var p: Vector3 = s.pos + right * k.x - s.dir * k.y
				poly.append(Vector2(p.x, p.z))
			boxes.append(_box(poly))
		out["ind:%d" % id] = [hash([s.pos, s.dir, s.kind, s.drive, cells, s.get("addons", {})]), boxes]
	# Outlines the player painted (Reserves.kind_at).
	var res := []
	for o in sim.reserves.outlines:
		res.append(o.points)
	out["reserves"] = [hash(sim.reserves.outlines), _boxes(res)]
	# Landfills, recycling centers and cemeteries; the post office (cells and
	# edge pieces).
	for id in sim.hubs.hubs:
		var h: Dictionary = sim.hubs.hubs[id]
		out["hub:%d" % id] = [hash([h.pos, h.dir, h.cell, h.cells, h.get("edge", {})]), _land_boxes(h)]
	for id in sim.mail.offices:
		var h: Dictionary = sim.mail.offices[id]
		out["mail:%d" % id] = [hash([h.pos, h.dir, h.cell, h.cells, h.get("edge", {})]), _land_boxes(h)]
	for id in sim.warehouses.buildings:
		var w: Dictionary = sim.warehouses.buildings[id]
		var poly := Warehouses.corners(w)
		out["wh:%d" % id] = [hash([poly, Warehouses.is_store(w)]), [_box(poly)]]
	for id in sim.parks.sites:
		var fp := sim.parks.footprint(id)
		out["park:%d" % id] = [hash(fp), [_box(fp)]]
	out["trails"] = [hash(sim.parks.trails.paths), null]
	# Campuses, banks and the phone company: their blocks (block 0 always).
	for id in sim.education.campuses:
		var c: Dictionary = sim.education.campuses[id]
		var polys := [Education.block_corners(c, Vector2i.ZERO)]
		for blk in c.blocks:
			polys.append(Education.block_corners(c, blk.c))
		out["edu:%d" % id] = [hash(polys), _boxes(polys)]
	for id in sim.banks.banks:
		var bk: Dictionary = sim.banks.banks[id]
		var polys := [Banks.block_corners(bk, Vector2i.ZERO)]
		for blk in bk.blocks:
			polys.append(Banks.block_corners(bk, blk.c))
		out["bank:%d" % id] = [hash(polys), _boxes(polys)]
	for id in sim.telecom.companies:
		var c: Dictionary = sim.telecom.companies[id]
		var polys := [Telecom.block_corners(c, Vector2i.ZERO)]
		for blk in c.blocks:
			polys.append(Telecom.block_corners(c, blk.c))
		var half := float(Balance.TELECOM_COMPOUND) * 0.5
		var towers := []
		for t in c.towers:
			var q := Vector2(t.pos[0], t.pos[1])
			polys.append(PackedVector2Array([q - Vector2(half, half), q + Vector2(half, half)]))
			towers.append(q)
		out["tel:%d" % id] = [hash([polys, towers]), _boxes(polys)]
	# Power companies: yards, roads in and units.
	for id in sim.power.sites:
		var s: Dictionary = sim.power.sites[id]
		var polys := [sim.power.yard(s)]
		for c in s.cells:
			polys.append(Power.cell_corners(s, c))
		var boxes := _boxes(polys)
		boxes.append_array(_drive_boxes(s.drive, Farms.DRIVE_WIDTH * 0.5 + 3.0))
		out["pow:%d" % id] = [hash([polys, s.drive]), boxes]
	for id in sim.big.sites:
		var poly := BigFactories.corners(sim.big.sites[id])
		out["big:%d" % id] = [hash(poly), [_box(poly)]]
	# The railroad's yards and track, county roads bulldozed or not, and
	# where the town sits on the county: too spread out to box.
	# Rail.covers reads the depot yards (yard_poly) and the track's cells:
	# both by content, so swapping track for the same number of cells counts.
	var yards := []
	for id in sim.rail.depots:
		var d: Dictionary = sim.rail.depots[id]
		yards.append([id, d.pos, d.dir, d.axis])
	out["rail"] = [hash([yards, sim.rail.cover_hash]), null]
	out["county"] = [hash(sim.county_removed), null]
	out["terrain"] = [hash(sim.terrain_offset), null]
	return out


## The boxes where lots must be checked again between two items(), or null
## when every lot must (no earlier items, or something unboxed changed).
static func diff(before: Dictionary, after: Dictionary) -> Variant:
	if before.is_empty():
		return null
	var out := []
	for key in before:
		if not after.has(key) or after[key][0] != before[key][0]:
			if before[key][1] == null:
				return null
			out.append_array(before[key][1])
	for key in after:
		if not before.has(key) or after[key][0] != before[key][0]:
			if after[key][1] == null:
				return null
			out.append_array(after[key][1])
	return out


## A lot's own box: its outline and the points _lot_blocked looks at.
static func lot_box(lot: Dictionary) -> Rect2:
	var box := Rect2(Vector2(lot.pos.x, lot.pos.z), Vector2.ZERO)
	for q in lot.corners:
		box = box.expand(q)
	for p in [lot.front, lot.zone_pt]:
		box = box.expand(Vector2(p.x, p.z))
	return box.grow(MARGIN)


static func _box(poly: PackedVector2Array) -> Rect2:
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
	return box.grow(MARGIN)


static func _boxes(polys: Array) -> Array:
	var out := []
	for poly in polys:
		if not (poly as PackedVector2Array).is_empty():
			out.append(_box(poly))
	return out


## A farm or company lane, as boxes around each stretch (Farms._near_drive).
static func _drive_boxes(drive: Array, reach: float) -> Array:
	var out := []
	for i in drive.size() - 1:
		var a := Vector2(drive[i].x, drive[i].z)
		var b := Vector2(drive[i + 1].x, drive[i + 1].z)
		out.append(Rect2(a, Vector2.ZERO).expand(b).grow(reach + MARGIN))
	return out


## A hub's or the post office's land: its cells (CivicHubs.at reads them by
## rounding, which is each cell's own square, cell_poly) and edge pieces.
static func _land_boxes(h: Dictionary) -> Array:
	var out := []
	for poly in CivicHubs.land_polys(h):
		out.append(_box(poly))
	return out
