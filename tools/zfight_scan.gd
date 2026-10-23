extends SceneTree
## Finds z-fighting in the building builders: two faces that lie in the same
## plane, overlap, shade differently, and can be seen. Building materials are
## two-sided, so a roof and the ceiling drawn in the same plane under it
## fight from above and below, and so does trim drawn flush on a wall.
## Faces pressed together inside the building (a window's back against the
## wall) can't be seen, so they are skipped: a ray from the overlap out of
## either side must reach open air for the fight to count.
## Also flags faces lying flat on the ground (y = 0), which fight the terrain.
## Faces inside the walls can still slip through, so read the list, not the
## count: look first at the biggest areas.
##
##   godot --headless -s tools/zfight_scan.gd [-- seeds]

const TOL := 0.005  # metres between planes that still fight
const MIN_AREA := 0.02  # m² of overlap worth reporting

var _mat_names := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := int(args[0]) if args.size() > 0 else 12
	for k in ["paint", "siding", "brick", "roof", "glass", "yard", "metal", "sign"]:
		_mat_names[HouseMaterials.get_mat(k)] = k
	var total := 0
	for s in seeds:
		total += _scan("house %d" % s, HouseBuilder.build(s, 3.9))
		total += _scan("shop %d" % s, CommercialBuilder.build_shop(s, 3.9))
		total += _scan("factory %d" % s, CommercialBuilder.build_factory(s, 3.9))
		for chain in Balance.FACTORY_CHAINS:
			total += _scan("%s %d" % [chain, s], FactoryBuilder.build_chain(chain, s, 3.9,
				{"width": 80.0, "depth": 90.0}))
		total += _scan("farm %d" % s, FarmBuilder.build_farmstead(s, s % 3))
		for kind in ["oil", "ore"]:
			total += _scan("%s hq %d" % [kind, s], IndustryBuilder.build_hq(kind, s))
			total += _scan("%s pad %d" % [kind, s], IndustryBuilder.build_pad(kind, s))
		for k in Services.Kind.values():
			var built = CivicBuilder.build_service(k, s, Vector2(40, 40), 3.9)
			if built is Array and built.size() >= 2:
				total += _scan("civic %s %d" % [Services.Kind.keys()[k].to_lower(), s], built)
	print("z-fight scan: %d visible overlaps" % total)
	quit()


func _scan(label: String, built: Array) -> int:
	var tris := []  # [a, b, c, normal, material, colour]
	for k in 2:
		if not built[k] is ArrayMesh:
			continue
		var mesh: ArrayMesh = built[k]
		for i in mesh.get_surface_count():
			var name: String = ("flat " if k == 1 else "") + str(_mat_names.get(mesh.surface_get_material(i), i))
			var arr := mesh.surface_get_arrays(i)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var col: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var idx = arr[Mesh.ARRAY_INDEX]
			var n: int = idx.size() if idx != null and idx.size() > 0 else v.size()
			for t in range(0, n, 3):
				var i0: int = idx[t] if idx else t
				var a: Vector3 = v[i0]
				var b: Vector3 = v[idx[t + 1] if idx else t + 1]
				var c: Vector3 = v[idx[t + 2] if idx else t + 2]
				var nn := (b - a).cross(c - a)
				if nn.length() < 1e-6:
					continue
				nn = nn.normalized()
				# Face the way the shading normal says.
				if nn.dot(nrm[i0]) < 0.0:
					nn = -nn
				tris.append([a, b, c, nn, name, col[i0] if col.size() > 0 else Color.WHITE])
	# Bucket by plane, whichever way it faces.
	var buckets := {}
	for i in tris.size():
		var cn: Vector3 = _canon(tris[i][3])
		var key := Vector3i(roundi(cn.x * 50), roundi(cn.y * 50), roundi(cn.z * 50))
		var dk := floori(cn.dot(tris[i][0]) / TOL)
		for o in [0, 1]:
			var bk := [key, dk + o]
			if not buckets.has(bk):
				buckets[bk] = []
			buckets[bk].append(i)
	var seen := {}
	var reports := {}
	for bk in buckets:
		var list: Array = buckets[bk]
		for x in list.size():
			for y in range(x + 1, list.size()):
				var pk := Vector2i(list[x], list[y])
				if seen.has(pk):
					continue
				seen[pk] = true
				var a = tris[list[x]]
				var b = tris[list[y]]
				if absf(a[3].dot(b[3])) < 0.9995 or absf(a[3].dot(a[0]) - a[3].dot(b[0])) > TOL:
					continue
				# Same material and colour shade the same, so a fight can't show.
				if a[4] == b[4] and (a[5] as Color).is_equal_approx(b[5]):
					continue
				var ov := _overlap(a, b)
				if ov[0] < MIN_AREA:
					continue
				var at: Vector3 = ov[1]
				if not (_open(tris, at, a[3]) or _open(tris, at, -a[3])):
					continue
				var rk := "%s | %s/%s n=%s at ~%s" % [label, a[4], b[4], _r(a[3]), _r(at)]
				reports[rk] = reports.get(rk, 0.0) + ov[0]
	for t in tris:
		if t[3].y > 0.999 and absf(t[0].y) < 0.005 and absf(t[1].y) < 0.005 and absf(t[2].y) < 0.005:
			var rk := "%s | %s on the ground (y = 0) at ~%s" % [label, t[4], _r((t[0] + t[1] + t[2]) / 3.0)]
			reports[rk] = reports.get(rk, 0.0) + (t[1] - t[0]).cross(t[2] - t[0]).length() * 0.5
	for rk in reports:
		print("  %s  (%.2f m²)" % [rk, reports[rk]])
	return reports.size()


static func _canon(n: Vector3) -> Vector3:
	if n.x < -1e-3 or (absf(n.x) <= 1e-3 and (n.y < -1e-3 or (absf(n.y) <= 1e-3 and n.z < 0))):
		return -n
	return n


## True when a ray from `p` along `dir` reaches open air: it reaches the
## sky, or the first thing it hits faces back at it (so `p` isn't inside a
## solid). Boxes have no bottoms, so a ray that reaches the ground proves
## nothing and counts as closed; faces tied for first hit count as closed
## if any of them is seen from behind (a window's back against the wall).
func _open(tris: Array, p: Vector3, dir: Vector3) -> bool:
	var from := p + dir * TOL * 2.0
	var hits := []
	for t in tris:
		var hit = Geometry3D.ray_intersects_triangle(from, dir, t[0], t[1], t[2])
		if hit != null:
			hits.append([(hit - from).length(), t[3].dot(dir) > 0.0])
	var best := INF
	for h in hits:
		best = minf(best, h[0])
	if best == INF:
		return dir.y >= -0.01
	for h in hits:
		if h[0] < best + TOL and h[1]:
			return false
	return true


func _r(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]


## [overlap area, a point inside the overlap] of two coplanar triangles.
func _overlap(a: Array, b: Array) -> Array:
	var n: Vector3 = a[3]
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := n.cross(u)
	var pa := PackedVector2Array()
	var pb := PackedVector2Array()
	for k in 3:
		pa.append(Vector2(a[k].dot(u), a[k].dot(w)))
		pb.append(Vector2(b[k].dot(u), b[k].dot(w)))
	var area := 0.0
	var best := 0.0
	var mid := Vector2.ZERO
	for poly in Geometry2D.intersect_polygons(pa, pb):
		var s := absf(_area(poly))
		area += s
		if s > best:
			best = s
			mid = Vector2.ZERO
			for q in poly:
				mid += q
			mid /= poly.size()
	return [area, u * mid.x + w * mid.y + n * n.dot(a[0])]


func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		s += p[i].cross(p[(i + 1) % p.size()])
	return s * 0.5
