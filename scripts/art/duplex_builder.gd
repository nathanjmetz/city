class_name DuplexBuilder
extends HouseBuilder
## Two- and four-family houses, the step between a house and a row of
## flats on a small Midwestern town's older blocks (BuildingTypes "duplex").
## Each is drawn from a real kind, by the era of its street:
##   - prewar: an up-and-down two-family, gable end to the street, with a
##     two-deck front porch and two front doors side by side (Milwaukee's
##     duplex flats, the "two-family flats" of Indianapolis and Fort Wayne);
##     or an Indianapolis double: two homes side by side under one gable
##   - postwar: a side-by-side ranch duplex, mirrored halves under one hip
##     or gable roof, a one-car garage at each end (1960s-80s Indiana
##     subdivisions and small-town infill)
##   - recent: the same in two storeys, garages at the ends
## and a fourplex: four flats in two storeys round a middle stair hall, a
## hip roof (postwar and recent, the 1960s-70s brick fourplex) or brick
## with a flat roof and a stone-trimmed entry (a prewar four-flat), parking
## out back off a side drive.
## Local space as HouseBuilder: x across the lot, -z toward the street.

const DX_BRICK := ["#8a4a38", "#9b5a42", "#7a4234", "#a8775c", "#b59a7c", "#6e3b2e"]
const DX_STONE := Color("#cfc6b2")
## Set by the art gallery to draw one style.
static var force_style := ""


## Draws the building for `level` (0 a duplex, 1 a fourplex).
static func build(seed: int, to_curb: float, lot := {}, level := 0) -> Array:
	var b := DuplexBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._fit(lot)
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plan := b._dx_plan(level)
	var info: Dictionary
	match plan.style:
		"updown": info = b._dx_updown(plan)
		"double": info = b._dx_double(plan)
		"fourplex": info = b._dx_fourplex(plan)
		_: info = b._dx_side(plan)
	b._yard(info, to_curb)
	# The second home's own drive, and its walk across to it.
	if info.drives.size() > 1:
		var d: Array = info.drives[1]
		b._flat_rect("drive", d[0] - d[1] * 0.5, d[0] + d[1] * 0.5, -to_curb, info.garage_z, 0.1)
		var door: float = info.doors[1]
		b._flat_rect("drive", minf(door, d[0]) - 0.6, maxf(door, d[0]), info.walk_z - 1.2, info.walk_z, 0.06)
	if info.has("pad"):
		var p: Rect2 = info.pad
		b._flat_rect("drive", p.position.x, p.end.x, p.position.y, p.end.y, 0.1)
	if owner_care >= 1:
		b._improve()
	b._yard_trees(info, to_curb)
	b._street_trees(info, to_curb)
	b._back_yard(info)
	b._utilities(info)
	b._front_yard(info)
	return [b._commit_house(), b._commit_flat(), b.trees]


## Where its drives, doors and parking are (for SiteLayout), worked out as
## build() does without drawing.
static func plan_info(seed: int, lot := {}, level := 0) -> Dictionary:
	var b := DuplexBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = seed
	b._fit(lot)
	return b._dx_plan(level)


## The building's layout from its own dice and the lot's width: its style,
## size and setback, and its drives ([x, width]), doors and parking.
func _dx_plan(level: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "duplex", level])
	var room := _avail()
	var zf := snappedf(clampf(r.randf_range(6.5, 9.0), 4.5, depth * 0.25), 0.5)
	var style := "fourplex"
	if level == 0:
		match era:
			"prewar": style = "double" if room >= 15.5 and r.randf() < 0.4 else "updown"
			"postwar": style = "ranch"
			_: style = "two"
		if style in ["ranch", "two"] and room < 15.0:
			style = "updown"
		if force_style != "":
			style = force_style
	var p := {"style": style, "zf": zf, "level": level, "seed": r.randi(), "gs": -1.0 if r.randf() < 0.5 else 1.0}
	match style:
		"updown":
			var w := clampf(room - 4.2, 7.0, 8.6)
			var d := r.randf_range(12.5, 14.5)
			var cx: float = -p.gs * minf(1.2, (room - w - 3.2) * 0.5)
			var dx: float = cx + p.gs * (w * 0.5 + 1.8)
			p.merge({"w": w, "d": d, "cx": cx, "drives": [[dx, 2.8]], "doors": [cx - 0.75, cx + 0.75]})
		"double":
			var w := clampf(room - 5.0, 10.5, 12.5)
			var d := r.randf_range(11.0, 13.0)
			var cx: float = -p.gs * minf(1.0, (room - w - 3.4) * 0.5)
			var dx: float = cx + p.gs * (w * 0.5 + 1.8)
			p.merge({"w": w, "d": d, "cx": cx, "drives": [[dx, 2.8]], "doors": [cx - w * 0.3, cx + w * 0.3]})
		"fourplex":
			if room < 13.5:
				# A narrow prewar lot: a four-flat to the side lines, no
				# drive; its people park on the street.
				var nw := room - 1.2
				p.merge({"w": nw, "d": r.randf_range(13.0, 15.0), "cx": 0.0, "drives": [[0.0, 0.0]], "doors": [0.0], "narrow": true})
			else:
				var w := clampf(room - 4.4, 9.0, 15.0)
				var d := r.randf_range(10.5, 12.5)
				var cx: float = -p.gs * minf(1.0, (room - w - 3.4) * 0.5)
				var dx: float = cx + p.gs * (w * 0.5 + 1.9)
				p.merge({"w": w, "d": d, "cx": cx, "drives": [[dx, 3.0]], "doors": [cx]})
		_:
			# Side by side: garages at the ends where the lot is wide enough,
			# else drives down both sides.
			var garages := room >= 19.0
			var gw := 3.8 if garages else 0.0
			var w := clampf(room - 2.0 * gw - (0.0 if garages else 6.4), 9.0, 15.0)
			var d := r.randf_range(8.8, 10.0) if style == "ranch" else r.randf_range(9.0, 10.5)
			var reach := w * 0.5 + gw
			var dxs: Array = [reach - gw * 0.5, -(reach - gw * 0.5)] if garages else [w * 0.5 + 1.6, -(w * 0.5 + 1.6)]
			p.merge({"w": w, "d": d, "cx": 0.0, "gw": gw,
				"drives": [[dxs[0], 3.0 if garages else 2.8], [dxs[1], 3.0 if garages else 2.8]],
				"doors": [w * 0.5 - 1.3, -(w * 0.5 - 1.3)]})
	# Front porches reach out in front of the house.
	var porch := 2.4 if style == "updown" else (2.3 if style == "double" else 0.0)
	p.front_z = zf - porch
	p.walk_z = zf - porch - (1.3 if porch > 0.0 else 1.9)
	# Parking: in the garages, on the drives, or a pad out back.
	p.garage_z = zf + p.d + 2.5
	var spots := []
	if style in ["ranch", "two"] and p.gw > 0.0:
		p.garage_z = zf - 0.6
		for dr in p.drives:
			spots.append({"pos": Vector2(dr[0], p.garage_z + 3.0), "face": Vector2(0, 1), "kind": "garage"})
			spots.append({"pos": Vector2(dr[0], p.garage_z - 3.2), "face": Vector2(0, 1), "kind": "drive"})
	elif style in ["ranch", "two"]:
		for dr in p.drives:
			spots.append({"pos": Vector2(dr[0], zf + 2.5), "face": Vector2(0, 1), "kind": "drive"})
	elif style != "fourplex":
		for z in [zf + 2.0, zf + 7.5]:
			spots.append({"pos": Vector2(p.drives[0][0], z), "face": Vector2(0, 1), "kind": "drive"})
	if style == "fourplex" and not p.has("narrow"):
		var pz: float = zf + p.d + 2.0
		var pw := 2.0 * 2.7 + (2.7 if p.w >= 12.0 else 0.0)
		var px: float = clampf(p.drives[0][0] - p.gs * (pw * 0.5 - 1.5), -half + pw * 0.5 + 0.6, half - pw * 0.5 - 0.6)
		var pd := minf(5.8, depth - pz - 1.5)
		if pd >= 5.0:
			p.pad = Rect2(px - pw * 0.5, pz, pw, pd)
			p.garage_z = pz
			for i in roundi(pw / 2.7):
				spots.append({"pos": Vector2(px - pw * 0.5 + 1.35 + i * 2.7, pz + pd * 0.5), "face": Vector2(0, 1), "kind": "stall"})
		else:
			for z in [zf + 2.0, zf + 7.5]:
				spots.append({"pos": Vector2(p.drives[0][0], z), "face": Vector2(0, 1), "kind": "drive"})
	p.spots = spots
	return p


## The plan's shared info for the yard (HouseBuilder._yard and the rest).
func _dx_info(p: Dictionary) -> Dictionary:
	var x0: float = p.cx - p.w * 0.5 - p.get("gw", 0.0)
	var x1: float = p.cx + p.w * 0.5 + p.get("gw", 0.0)
	var out := {"drive_x": p.drives[0][0], "drive_w": p.drives[0][1], "garage_z": p.garage_z, "door_x": p.doors[0],
		"walk_z": p.walk_z, "front_z": p.front_z, "doors": p.doors, "x0": x0, "x1": x1, "gs": p.gs, "drives": p.drives,
		"bed": [x0 + 0.3, x1 - 0.3]}
	if p.has("pad"):
		out.pad = p.pad
		out.keep_out = p.pad
	return out


func _dx_paint(r: RandomNumberGenerator) -> Dictionary:
	var was := rng
	rng = r
	var out := {"siding": Color(_pick(SIDING)), "roof": Color(_pick(ROOF)), "door": Color(_pick(DOOR)),
		"shutter": Color(_pick(SHUTTER.slice(0, 4))), "brick": Color(_pick(DX_BRICK))}
	rng = was
	return out


## Up and down: one flat a floor, the gable end to the street, a two-deck
## porch across the front and two doors side by side (one to each flat).
func _dx_updown(p: Dictionary) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = p.seed
	var paint := _dx_paint(r)
	var w: float = p.w
	var d: float = p.d
	var cx: float = p.cx
	var zf: float = p.zf
	var zb := zf + d
	var cz := zf + d * 0.5
	var sill := 0.75
	var fh := 2.75
	var top := sill + fh * 2.0
	_box("concrete", Vector3(w + 0.1, sill, d + 0.1), Vector3(cx, sill * 0.5, cz), FOUNDATION)
	_box("siding", Vector3(w, top - sill, d), Vector3(cx, (sill + top) * 0.5, cz), paint.siding)
	_corners(cx - w * 0.5, cx + w * 0.5, zf, zb, sill, top)
	var rise := w * r.randf_range(0.42, 0.55)
	_gable_roof(cx, cz, top, w, rise, d, false, paint.roof, paint.siding)
	# An attic window in the front gable.
	_window(Vector3(cx, top + rise * 0.4, zf), Vector3(-1, 0, 0), 0.8, 1.0, true, false, TRIM)
	# The porch: a deck on each floor, posts, rails, a roof over the top.
	var pd := 2.4
	var pz := zf - pd * 0.5
	var wood := TRIM
	for f in 2:
		var y := sill + f * fh
		if f == 0:
			_box("concrete", Vector3(w, sill, pd), Vector3(cx, sill * 0.5, pz), FOUNDATION)
		else:
			_box("paint", Vector3(w, 0.2, pd), Vector3(cx, y + 0.02, pz), wood)
		for s in [-1.0, -0.33, 0.33, 1.0]:
			_box("paint", Vector3(0.16, fh - 0.1, 0.16), Vector3(cx + s * (w * 0.5 - 0.15), y + fh * 0.5, zf - pd + 0.15), wood)
		_box("paint", Vector3(w, 0.07, 0.07), Vector3(cx, y + 0.95, zf - pd + 0.15), wood)
		_box("paint", Vector3(w, 0.07, 0.07), Vector3(cx, y + 0.12, zf - pd + 0.15), wood)
		var n := int(w / 0.14)
		for i in n:
			var x := cx - w * 0.5 + 0.2 + i * (w - 0.4) / n
			if f == 0 and absf(x - cx) < 0.7:
				continue  # the steps
			_box("paint", Vector3(0.04, 0.8, 0.04), Vector3(x, y + 0.53, zf - pd + 0.15), wood)
	_box("paint", Vector3(w + 0.3, 0.15, pd + 0.3), Vector3(cx, top + 0.05, pz), paint.roof.darkened(0.1))
	_stoop(cx, zf - pd, 1.4, 1.2, sill)
	for x in p.doors:
		_front_door(x, zf, sill, paint.door)
	# Big front windows each floor, double-hungs down the sides.
	for f in 2:
		var y := sill + f * fh + 1.5
		_window(Vector3(cx - w * 0.3, y, zf), Vector3(-1, 0, 0), 1.0, 1.5, false, false, TRIM)
		_window(Vector3(cx + w * 0.3, y, zf), Vector3(-1, 0, 0), 1.0, 1.5, false, false, TRIM)
		if f == 1:
			_box("paint", Vector3(0.95, 2.05, 0.06), Vector3(cx, sill + fh + 1.02, zf - 0.02), paint.door)
		for s in [-1.0, 1.0]:
			for i in 3:
				var z := zf + d * (i + 0.6) / 3.4
				_window(Vector3(cx + s * w * 0.5, y, z), Vector3(0, 0, -s), 0.85, 1.4, false, false, TRIM)
	# Back stairs up to the upper flat (Milwaukee flats have them out back).
	_box("siding", Vector3(1.4, sill + fh + 0.3, 2.6), Vector3(cx + p.gs * (w * 0.5 - 0.8), (sill + fh + 0.3) * 0.5, zb + 1.3), paint.siding)
	_back_shed(cx + p.gs * (w * 0.5 - 0.8), 1.7, zb, 2.75, sill + fh + 0.3, 0.5, paint.roof)
	_back(cx - w * 0.5, cx + w * 0.5, zb, [sill + 1.5, sill + fh + 1.5], sill)
	var info := _dx_info(p)
	var g := _back_garage(p.drives[0][0], zb + 1.0, paint.siding, paint.roof)
	info.garage_z = g.garage_z
	if g.garage_w > 0.0:
		info.garage_x = g.garage_x
		info.garage_w = g.garage_w
		info.keep_out = g.keep_out
	return info


## An Indianapolis double: two homes side by side under one front gable,
## two doors under one porch roof.
func _dx_double(p: Dictionary) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = p.seed
	var paint := _dx_paint(r)
	var w: float = p.w
	var d: float = p.d
	var cx: float = p.cx
	var zf: float = p.zf
	var zb := zf + d
	var cz := zf + d * 0.5
	var sill := 0.7
	var top := sill + 5.3
	_box("concrete", Vector3(w + 0.1, sill, d + 0.1), Vector3(cx, sill * 0.5, cz), FOUNDATION)
	_box("siding", Vector3(w, top - sill, d), Vector3(cx, (sill + top) * 0.5, cz), paint.siding)
	_corners(cx - w * 0.5, cx + w * 0.5, zf, zb, sill, top)
	var rise := w * 0.36
	_gable_roof(cx, cz, top, w, rise, d, false, paint.roof, paint.siding)
	_window(Vector3(cx - 0.6, top + rise * 0.35, zf), Vector3(-1, 0, 0), 0.7, 0.95, true, false, TRIM)
	_window(Vector3(cx + 0.6, top + rise * 0.35, zf), Vector3(-1, 0, 0), 0.7, 0.95, true, false, TRIM)
	# A full-width porch on square columns, a hipped roof over it.
	var pd := 2.3
	_box("concrete", Vector3(w, sill, pd), Vector3(cx, sill * 0.5, zf - pd * 0.5), FOUNDATION)
	for s in [-1.0, -0.12, 0.12, 1.0]:
		_box("paint", Vector3(0.22, 2.5, 0.22), Vector3(cx + s * (w * 0.5 - 0.2), sill + 1.25, zf - pd + 0.2), TRIM)
	_shed_roof(cx, w + 0.4, zf, pd + 0.3, sill + 2.55, 0.5, paint.roof)
	for x in p.doors:
		_stoop(x, zf - pd, 1.2, 1.0, sill)
		_front_door(x, zf, sill, paint.door)
	for s in [-1.0, 1.0]:
		var x: float = cx + s * w * 0.22
		_window(Vector3(cx + s * w * 0.12, sill + 1.5, zf), Vector3(-1, 0, 0), 0.9, 1.45, true, false, TRIM)
		_window(Vector3(x, sill + 4.0, zf), Vector3(-1, 0, 0), 0.9, 1.4, true, false, TRIM)
		_window(Vector3(cx + s * w * 0.4, sill + 4.0, zf), Vector3(-1, 0, 0), 0.9, 1.4, true, false, TRIM)
		for i in 3:
			var z := zf + d * (i + 0.6) / 3.4
			for y in [sill + 1.5, sill + 4.0]:
				_window(Vector3(cx + s * w * 0.5, y, z), Vector3(0, 0, -s), 0.85, 1.35, true, false, TRIM)
	_back(cx - w * 0.5, cx + w * 0.5, zb, [sill + 1.5, sill + 4.0], sill)
	var info := _dx_info(p)
	var g := _back_garage(p.drives[0][0], zb + 1.0, paint.siding, paint.roof)
	info.garage_z = g.garage_z
	if g.garage_w > 0.0:
		info.garage_x = g.garage_x
		info.garage_w = g.garage_w
		info.keep_out = g.keep_out
	return info


## Side by side: two mirrored homes under one roof, a door and picture
## window each, and a one-car garage at each end (or drives down both
## sides on a narrower lot). One storey (postwar) or two (recent).
func _dx_side(p: Dictionary) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = p.seed
	var paint := _dx_paint(r)
	var w: float = p.w
	var d: float = p.d
	var gw: float = p.gw
	var zf: float = p.zf
	var zb := zf + d
	var cz := zf + d * 0.5
	var two: bool = p.style == "two"
	var sill := 0.4
	var top := sill + (5.3 if two else 2.7)
	var brick := r.randf() < 0.5
	_box("concrete", Vector3(w + 0.1, sill, d + 0.1), Vector3(0, sill * 0.5, cz), FOUNDATION)
	_box("siding", Vector3(w, top - sill, d), Vector3(0, (sill + top) * 0.5, cz), paint.siding)
	if brick:
		var bh := 1.0 if two else top - sill - 0.05
		_box("brick", Vector3(w + 0.03, bh, 0.14), Vector3(0, sill + bh * 0.5, zf - 0.05), paint.brick)
	_corners(-w * 0.5, w * 0.5, zf, zb, sill, top)
	var hip := r.randf() < 0.5
	var rise := r.randf_range(1.2, 1.7)
	if hip:
		_hip_roof(0.0, cz, top, w, d, rise, paint.roof)
	else:
		_gable_roof(0.0, cz, top, d, rise, w, true, paint.roof, paint.siding)
	# The party wall shows as a strip of trim up the front.
	_box("paint", Vector3(0.12, top - sill, 0.06), Vector3(0, (sill + top) * 0.5, zf - 0.04), TRIM)
	var face := zf - (0.12 if brick else 0.0)
	for s in [-1.0, 1.0]:
		var door_x: float = s * absf(p.doors[0])
		_stoop(door_x, zf, 1.8, 1.3, sill)
		_front_door(door_x, face, sill, paint.door)
		var pict: float = s * w * 0.2
		_window(Vector3(pict, 1.95, face), Vector3(-1, 0, 0), minf(2.0, w * 0.16), 1.4, r.randf() < 0.5, false, TRIM)
		if two:
			for x in [s * w * 0.12, s * w * 0.38]:
				_window(Vector3(x, sill + 4.0, face), Vector3(-1, 0, 0), 0.9, 1.35, true, true, paint.shutter)
		_window(Vector3(s * w * 0.5, sill + 1.6, cz), Vector3(0, 0, -s), 0.9, 1.35, true, false, TRIM)
		if gw > 0.0:
			# A one-car garage at this end, its roof run off the house's.
			var gx: float = s * (w * 0.5 + gw * 0.5)
			var gz0 := zf - 0.6
			var gd := d * 0.8
			_box("concrete", Vector3(gw + 0.05, 0.15, gd + 0.05), Vector3(gx, 0.075, gz0 + gd * 0.5), FOUNDATION)
			_box("siding", Vector3(gw, 2.75, gd), Vector3(gx, 1.52, gz0 + gd * 0.5), paint.siding)
			_corners(gx - gw * 0.5, gx + gw * 0.5, gz0, gz0 + gd, 0.15, 2.9)
			_gable_roof(gx, gz0 + gd * 0.5, 2.9, gd, 1.0, gw, true, paint.roof, paint.siding)
			_garage(gx, gz0, gw, 2.1)
	var floors := [sill + 1.6, sill + 4.0] if two else [sill + 1.6]
	_back(-w * 0.5, -0.4, zb, floors, sill)
	_back(0.4, w * 0.5, zb, floors, sill)
	return _dx_info(p)


## A fourplex: two flats a floor either side of a middle stair hall, one
## entry in the middle. Brick with a hip roof (postwar, recent), or a
## prewar four-flat in brick with a flat roof, parapet and stone trim.
func _dx_fourplex(p: Dictionary) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = p.seed
	var paint := _dx_paint(r)
	var w: float = p.w
	var d: float = p.d
	var cx: float = p.cx
	var zf: float = p.zf
	var zb := zf + d
	var cz := zf + d * 0.5
	if era == "recent" and not p.has("narrow"):
		return _dx_bighouse(p, r, paint)
	var sill := 0.9  # a garden-level half basement under the first floor
	var fh := 2.8
	var top := sill + fh * 2.0
	var flat := era == "prewar"
	var brick: Color = paint.brick
	_box("concrete", Vector3(w + 0.1, sill, d + 0.1), Vector3(cx, sill * 0.5, cz), FOUNDATION)
	_box("brick", Vector3(w, top - sill, d), Vector3(cx, (sill + top) * 0.5, cz), brick)
	if flat:
		_box("brick", Vector3(w + 0.1, 0.7, d + 0.1), Vector3(cx, top + 0.35, cz), brick)
		_box("paint", Vector3(w + 0.3, 0.16, d + 0.3), Vector3(cx, top + 0.75, cz), DX_STONE)
		_box("roof", Vector3(w - 0.3, 0.05, d - 0.3), Vector3(cx, top + 0.3, cz), Color("#55524d"))
		_box("paint", Vector3(w + 0.06, 0.14, 0.1), Vector3(cx, sill + fh, zf - 0.05), DX_STONE)
	else:
		_hip_roof(cx, cz, top, w, d, r.randf_range(1.3, 1.8), paint.roof)
	# The middle entry: a door with a light over it, stone or a little
	# gabled hood, and the stair hall's tall window above.
	var door_x: float = p.doors[0]
	_stoop(door_x, zf, 2.0, 1.6, sill)
	_front_door(door_x, zf, sill, paint.door)
	if flat:
		_box("paint", Vector3(1.7, 2.7, 0.1), Vector3(door_x, sill + 1.25, zf - 0.04), DX_STONE)
		_front_door(door_x, zf - 0.08, sill, paint.door)
	else:
		_gable_roof(door_x, zf - 0.55, sill + 2.55, 1.9, 0.6, 1.2, false, paint.roof, TRIM, false)
	_window(Vector3(door_x, sill + fh + 1.2, zf), Vector3(-1, 0, 0), 0.8, 1.8, false, false, TRIM)
	for s in [-1.0, 1.0]:
		for f in 2:
			var y := sill + f * fh + 1.5
			for x in [door_x + s * w * 0.2, door_x + s * w * 0.38]:
				_window(Vector3(x, y, zf), Vector3(-1, 0, 0), 1.0, 1.4, false, false, TRIM)
			for i in 2:
				_window(Vector3(cx + s * w * 0.5, y, zf + d * (i + 0.7) / 2.4), Vector3(0, 0, -s), 0.9, 1.35, false, false, TRIM)
		# Garden-level windows in the foundation.
		_window(Vector3(door_x + s * w * 0.3, sill * 0.5 + 0.05, zf - 0.02), Vector3(-1, 0, 0), 0.9, 0.45, false, false, TRIM)
	# Back doors and a small balcony for each upstairs flat.
	for s in [-1.0, 1.0]:
		var bx: float = cx + s * w * 0.25
		_box("paint", Vector3(0.95, 2.05, 0.06), Vector3(bx, sill + 1.02, zb + 0.02), Color("#5a5e60"))
		_box("paint", Vector3(2.4, 0.15, 1.3), Vector3(bx, sill + fh, zb + 0.65), FOUNDATION)
		_box("paint", Vector3(2.4, 0.9, 0.05), Vector3(bx, sill + fh + 0.5, zb + 1.28), Color("#1e1f20"))
		_box("paint", Vector3(0.95, 2.05, 0.06), Vector3(bx, sill + fh + 1.1, zb + 0.02), Color("#5a5e60"))
		_window(Vector3(cx + s * w * 0.42, sill + 1.5, zb), Vector3(1, 0, 0), 0.9, 1.35, false, false, TRIM)
		_window(Vector3(cx + s * w * 0.42, sill + fh + 1.5, zb), Vector3(1, 0, 0), 0.9, 1.35, false, false, TRIM)
	return _dx_info(p)


## A fourplex built new on a recent street: the "big house" plex of the
## missing-middle infill Indiana cities allow again (Bloomington's and
## Indianapolis's near-east-side plexes since 2020), four flats that look
## like one large house: two storeys of lap siding under a side gable, a
## wide front gable in board-and-batten over the middle, a full-width
## porch on square craftsman columns with two doors (each to a stair), and
## black-framed windows. The footprint, door and parking are the fourplex
## plan's, so the site plan is unchanged.
func _dx_bighouse(p: Dictionary, r: RandomNumberGenerator, paint: Dictionary) -> Dictionary:
	var w: float = p.w
	var d: float = p.d
	var cx: float = p.cx
	var zf: float = p.zf
	var zb := zf + d
	var cz := zf + d * 0.5
	var sill := 0.6
	var fh := 2.9
	var top := sill + fh * 2.0
	var siding: Color = paint.siding
	var accent := siding.darkened(0.25) if r.randf() < 0.5 else Color(["#2f3a32", "#3b3f42", "#e8e4d8"][r.randi() % 3])
	var black := Color("#1f2224")
	_box("concrete", Vector3(w + 0.1, sill, d + 0.1), Vector3(cx, sill * 0.5, cz), FOUNDATION)
	_box("siding", Vector3(w, top - sill, d), Vector3(cx, (sill + top) * 0.5, cz), siding)
	_gable_roof(cx, cz, top, d, d * 0.5 * 0.5, w, true, paint.roof, siding)
	# The front gable over the middle, board-and-batten.
	var gw := minf(w * 0.55, 7.5)
	_box("siding", Vector3(gw, 0.6, 0.6), Vector3(cx, top + 0.3, zf + 0.1), accent)
	_gable_roof(cx, zf + 1.6, top + 0.6, gw, gw * 0.5 * 0.75, 3.6, false, paint.roof, accent)
	for i in maxi(4, int(gw / 0.4)):
		_box("paint", Vector3(0.05, 0.5, 0.04), Vector3(cx - gw * 0.5 + 0.2 + i * 0.4, top + 0.3, zf - 0.22), accent.darkened(0.1))
	# The porch: a deck, square columns on brick-clad piers, a shed roof.
	var pd := 1.8
	var pw := w - 0.6
	_box("concrete", Vector3(pw, sill, pd), Vector3(cx, sill * 0.5, zf - pd * 0.5), FOUNDATION)
	_box("paint", Vector3(pw, 0.06, pd), Vector3(cx, sill + 0.03, zf - pd * 0.5), Color("#8d7b5f"))
	var cols := 4 if pw > 10.0 else 3
	for i in cols:
		var x := cx - pw * 0.5 + 0.25 + i * (pw - 0.5) / (cols - 1)
		_box("brick", Vector3(0.5, 0.9, 0.5), Vector3(x, sill + 0.45, zf - pd + 0.3), paint.brick)
		_box("paint", Vector3(0.3, 1.75, 0.3), Vector3(x, sill + 0.9 + 0.87, zf - pd + 0.3), TRIM)
	_box("paint", Vector3(pw + 0.3, 0.3, 0.3), Vector3(cx, sill + 2.75, zf - pd + 0.3), TRIM)
	var a := Vector3(cx - pw * 0.5 - 0.15, sill + 3.3, zf)
	var b := Vector3(cx + pw * 0.5 + 0.15, sill + 3.3, zf)
	_quad("roof", Vector3(b.x, sill + 2.9, zf - pd - 0.3), Vector3(a.x, sill + 2.9, zf - pd - 0.3), a, b, paint.roof, [], Vector3(0, 1, -0.4).normalized())
	_quad("paint", Vector3(a.x, sill + 2.9, zf - pd - 0.3), Vector3(b.x, sill + 2.9, zf - pd - 0.3), b - Vector3(0, 0.02, 0), a - Vector3(0, 0.02, 0), SOFFIT, [], Vector3.DOWN)
	# Two doors under the porch, one to each stair; the steps at the middle.
	var door_x: float = p.doors[0]
	for e in [-1.0, 1.0]:
		_front_door(door_x + e * 0.9, zf, sill, paint.door)
	_stoop(door_x, zf - pd, 2.0, 1.0, sill)
	# Black-framed windows, two pairs a floor either side of the doors.
	for s in [-1.0, 1.0]:
		for f in 2:
			var y := sill + f * fh + 1.45
			for x in [door_x + s * w * 0.22, door_x + s * w * 0.38]:
				_box("metal", Vector3(1.1, 1.6, 0.04), Vector3(x, y, zf - 0.01), black)
				_glass(Vector3(x, y, zf - 0.04), Vector3(-1, 0, 0), 0.95, 1.45, r.randf_range(0.0, 0.6))
			for i in 2:
				_window(Vector3(cx + s * w * 0.5, y, zf + d * (i + 0.7) / 2.4), Vector3(0, 0, -s), 0.9, 1.35, false, false, black)
	_glass(Vector3(door_x, top + 0.9, zf + 0.05 - 0.3), Vector3(-1, 0, 0), 1.2, 0.6, 0.0)
	# Out back: a door and a stacked deck for each side.
	for s in [-1.0, 1.0]:
		var bx: float = cx + s * w * 0.25
		_box("paint", Vector3(0.95, 2.05, 0.06), Vector3(bx, sill + 1.02, zb + 0.02), black)
		_box("paint", Vector3(2.6, 0.15, 1.6), Vector3(bx, sill + fh, zb + 0.8), Color("#8d7b5f"))
		_box("paint", Vector3(2.6, 0.9, 0.05), Vector3(bx, sill + fh + 0.5, zb + 1.58), black)
		_box("paint", Vector3(0.95, 2.05, 0.06), Vector3(bx, sill + fh + 1.1, zb + 0.02), black)
		_window(Vector3(cx + s * w * 0.42, sill + 1.5, zb), Vector3(1, 0, 0), 0.9, 1.35, false, false, black)
		_window(Vector3(cx + s * w * 0.42, sill + fh + 1.5, zb), Vector3(1, 0, 0), 0.9, 1.35, false, false, black)
	return _dx_info(p)
