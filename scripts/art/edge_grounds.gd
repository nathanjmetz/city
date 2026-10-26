class_name EdgeGrounds
extends RefCounted
## Drawing helpers for edge pieces, the land a boxed-in hub takes up to the
## sidewalk (CivicHubs, BlockEdges): its outside sides, flat ground over any
## outline in small tiles, a fence, trees on a loose grid and parking
## stalls. Shared by HubBuilder and the bank, campus and phone company
## builders. Local space as HubBuilder's: -z faces the road, z = 0 is the
## front edge of the land, piece (x, y) spans x*cell +- cell/2 across and
## y*cell .. (y+1)*cell back.

## Lawn: mown grass, a little greener than the fields round town.
const LAWN := Color("#557a35")


## Each side of the edge pieces `with` (local outlines), less what runs
## along one of the whole pieces `set` or another edge piece of `all` (by
## default `with` itself), as [a, b] pairs.
static func sides(set: Array, cell: float, with: Dictionary, all := {}) -> Array:
	var others: Dictionary = with if all.is_empty() else all
	var squares := []
	var hc := cell * 0.5
	for c in set:
		squares.append(PackedVector2Array([Vector2(c.x * cell - hc, c.y * cell), Vector2(c.x * cell + hc, c.y * cell),
			Vector2(c.x * cell + hc, c.y * cell + cell), Vector2(c.x * cell - hc, c.y * cell + cell)]))
	var keys := others.keys()
	var polys := []
	for c in keys:
		polys.append(others[c])
	var out := []
	for c in with:
		var poly: PackedVector2Array = with[c]
		var skip := squares.size() + keys.find(c)
		for k in poly.size():
			out.append_array(HubBuilder._uncovered([poly[k], poly[(k + 1) % poly.size()]], squares + polys, skip))
	return out


## Flat ground over any outline (as CivicBuilder's _flat_rect: `kind` is
## drive, asphalt, line, mulch or gravel), in tiles of at most `tile`
## metres, so the terrain drape (which moves only vertices) bends it over
## the real ground.
static func ground(b: CivicBuilder, kind: String, poly: PackedVector2Array, y: float, col: Color, tile := 6.0) -> void:
	if poly.size() < 3:
		return
	var alpha := {"drive": 0.0, "asphalt": 0.4, "line": 0.72, "mulch": 1.0, "gravel": 1.0}
	col.a = alpha[kind]
	var box := HubBuilder._bounds(poly)
	var nx := maxi(1, ceili(box.size.x / tile))
	var nz := maxi(1, ceili(box.size.y / tile))
	for i in nx:
		for j in nz:
			var x0 := box.position.x + box.size.x * i / nx
			var x1 := box.position.x + box.size.x * (i + 1) / nx
			var z0 := box.position.y + box.size.y * j / nz
			var z1 := box.position.y + box.size.y * (j + 1) / nz
			var sq := PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
			for part in Geometry2D.intersect_polygons(poly, sq):
				if part.size() < 3:
					continue
				for tri in HubBuilder._tris(part):
					for q in tri:
						b._flat.set_normal(Vector3.UP)
						b._flat.set_color(col)
						b._flat.set_uv(q * 0.25)
						b._flat.add_vertex(Vector3(q.x, y, q.y))


## A fence along `runs` ([a, b] pairs): posts every `gap` metres or so,
## a top and a bottom rail, and three strands of barbed wire if `barbed`.
static func fence(b: CivicBuilder, runs: Array, h: float, col: Color, gap := 3.0, barbed := false) -> void:
	for e in runs:
		var a: Vector2 = e[0]
		var z: Vector2 = e[1]
		var len := a.distance_to(z)
		if len < 0.5:
			continue
		var dir := (z - a) / len
		var yaw := Basis(Vector3.UP, atan2(dir.x, dir.y))
		var n := maxi(1, int(len / gap))
		for k in n + 1:
			var p := a + dir * (len * k / n)
			b._box("paint", Vector3(0.08, h, 0.08), Vector3(p.x, h * 0.5, p.y), col)
		var mid := (a + z) * 0.5
		for y in [h, 0.15]:
			b._box("paint", Vector3(0.05, 0.05, len), Vector3(mid.x, y, mid.y), col, yaw)
		if barbed:
			for k in 3:
				b._box("paint", Vector3(0.02, 0.02, len), Vector3(mid.x, h + 0.15 + k * 0.15, mid.y), CivicBuilder.DARK, yaw)


## Trees on a loose grid `gap` metres apart over `poly`, kept `back` metres
## in from its edges (and off `keep_off`, local outlines). `front` picks
## the flowering kinds a front yard gets.
static func trees(b: CivicBuilder, poly: PackedVector2Array, gap: float, back: float, front := false,
		keep_off := []) -> void:
	var plot := HubBuilder._inset(poly, back)
	if plot.size() < 3:
		return
	var box := HubBuilder._bounds(plot)
	var z := box.position.y + fmod(box.size.y, gap) * 0.5
	while z <= box.end.y:
		var x := box.position.x + fmod(box.size.x, gap) * 0.5
		while x <= box.end.x:
			var q := Vector2(x + b.rng.randf_range(-1.2, 1.2), z + b.rng.randf_range(-1.2, 1.2))
			var off := false
			for o in keep_off:
				off = off or Geometry2D.is_point_in_polygon(q, o)
			if not off and Geometry2D.is_point_in_polygon(q, plot):
				var pick := TreeField.pick(b.rng, front)
				b.trees.append([Vector3(q.x, 0, q.y), pick[0], pick[1], b.rng.randf_range(0.8, 1.1)])
			x += gap
		z += gap


## A parking lot over `poly`: asphalt, and rows of stall lines wherever a
## whole 2.75 by 5.5 m stall fits, two rows back to back with a 7 m aisle
## between pairs. Returns how many stalls it drew.
static func parking(b: CivicBuilder, poly: PackedVector2Array) -> int:
	if poly.size() < 3:
		return 0
	ground(b, "asphalt", poly, 0.06, HouseBuilder.MULCH)
	var box := HubBuilder._bounds(poly)
	var n := 0
	# Rows run along x; each pair of rows is 11 m deep, then a 7 m aisle.
	var z := box.position.y + 7.0
	while z + 5.5 <= box.end.y:
		for row in [[z, z + 5.5], [z + 5.5, z + 11.0]]:
			if row[1] > box.end.y:
				continue
			var x := box.position.x + 0.5
			while x + 2.75 <= box.end.x - 0.5:
				var fits := true
				for q in [Vector2(x, row[0]), Vector2(x + 2.75, row[0]), Vector2(x, row[1]), Vector2(x + 2.75, row[1])]:
					fits = fits and Geometry2D.is_point_in_polygon(q, poly)
				if fits:
					for lx in [x, x + 2.75]:
						b._flat_rect("line", lx - 0.06, lx + 0.06, row[0], row[1], 0.07, CommercialBuilder.LINE)
					n += 1
				x += 2.75
		z += 18.0
	return n


## Puts the drawing of hub `c`'s edge pieces (`built`: [building, ground,
## trees] from its builder, in CivicHubs' frame) under `view`: at the middle
## of its first block's front edge (`cell` deep), -z toward its street, the
## ground draped over the land and each tree on the ground where it stands.
static func place(view: Node3D, field: TreeField, key: String, c: Dictionary, cell: float, built: Array) -> Node3D:
	var root := Node3D.new()
	view.add_child(root)
	root.basis = Basis.looking_at(c.dir, Vector3.UP)
	root.position = Terrain.lift(c.pos + c.dir * (cell * 0.5))
	var frame := Transform3D(root.basis, root.position)
	var things := MeshInstance3D.new()
	things.mesh = built[0]
	root.add_child(things)
	var ground_mesh := MeshInstance3D.new()
	ground_mesh.mesh = Terrain.drape_local(built[1], frame)
	ground_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground_mesh)
	var trees := []
	for t in built[2]:
		var yaw := Basis(Vector3.UP, fposmod(t[0].x * 7.3 + t[0].z * 3.1, TAU))
		var at := frame * Transform3D(yaw.scaled(Vector3.ONE * t[3]), t[0])
		at.origin.y = Terrain.ground_y(at.origin.x, at.origin.z)
		trees.append([at, t[1], t[2]])
	field.set_trees(key, trees)
	return root


## A parking lot's drive out to the street behind it: for a piece straight
## behind the hub's land (`c`, blocks `cell` deep) cut back by a road at its
## back, a 7.2 m drive from the lot's back edge across the gap and the
## sidewalk to the curb.
static func back_drive(b: CivicBuilder, lot: PackedVector2Array, poly: PackedVector2Array, c: Vector2i,
		cell: float) -> void:
	var piece := HubBuilder._bounds(poly)
	if c.x != 0 or c.y < 1 or piece.end.y >= (c.y + 1) * cell - 1.0 or lot.size() < 3:
		return
	var box := HubBuilder._bounds(lot)
	var to_curb := CivicHubs.SETBACK + RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH
	var x := box.get_center().x
	b._flat_rect("asphalt", x - 3.6, x + 3.6, box.end.y - 0.5, piece.end.y + to_curb, 0.1)
