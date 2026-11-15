class_name MainInfill
extends RefCounted
## A shop with flats built new on a postwar or recent street, instead of
## an 1880s Italianate front (BuildingTypes "mixed_use", up to 4 storeys):
##   - postwar: the 1950s-60s downtown infill that replaced a burned or
##     worn-out front (Marion's Washington Street, Kokomo, Muncie): buff
##     Roman brick, a full aluminium-and-glass storefront on a polished
##     stone bulkhead under a thin cantilevered canopy with the name on
##     its fascia, the floors above a ribbon of steel sash over porcelain
##     enamel spandrel panels, a blade sign at one end and a plain metal
##     coping on a flat roof.
##   - recent: the 2010s mixed-use block of Indiana's downtown revivals
##     (Carmel City Center, Noblesville, Fishers Nickel Plate): bays
##     alternating brick and projecting fibre-cement panels with their own
##     taller parapets, black-framed storefronts with transoms under steel
##     canopies hung on tie rods, paired windows and Juliet balconies
##     upstairs, and a deep flat metal cap.
## Drawn into a DenseBuilder `b` in its local space (front at z 0, street at
## -z), with its own random numbers (lent to `b` while it draws) so the
## builder's own draws don't move.

const ROMAN := ["#d6c6a1", "#c9b48c", "#e0d3b4", "#b9a382", "#a9a49a", "#8e6a52"]
const ENAMEL := ["#4f8f8c", "#b8bba8", "#d9cfa8", "#6f8a9a", "#c96f4a", "#e8e4d8"]
const STONE := ["#2d3a33", "#3a3530", "#1f2224", "#6b2a24"]
const ALUMINIUM := Color("#a9acae")
const NEW_BRICK := ["#7a4234", "#5a3a32", "#8a4a38", "#4a4440", "#a8775c", "#9b5a42"]
const PANEL := ["#3b3f42", "#6b6f70", "#b9b4a8", "#e4e1d6", "#55606a"]
const BLACK := Color("#1f2224")

## How many of each era's shops with flats are built new in the era's own
## way (the rest are older fronts the street grew round), by era.
const CHANCE := {"prewar": 0, "postwar": 50, "recent": 75}


## True when this block is drawn as postwar or recent infill.
static func wanted(b: DenseBuilder, storeys: int) -> bool:
	if storeys > 4 or b.half * 2.0 < 12.0 or HouseBuilder.restored:
		return false
	return absi(hash([b.rng.seed, "main infill"])) % 100 < int(CHANCE.get(b.era, 0))


static func draw(b: DenseBuilder, to_curb: float, storeys: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([b.rng.seed, "main infill art"])
	var own := b.rng
	b.rng = r
	if b.era == "postwar":
		_mi_midcentury(b, r, to_curb, storeys)
	else:
		_mi_newbuild(b, r, to_curb, storeys)
	b.rng = own


## The 1950s-60s front.
static func _mi_midcentury(b: DenseBuilder, r: RandomNumberGenerator, to_curb: float, storeys: int) -> void:
	var width := b.half * 2.0
	var w := width - 0.4
	var d := r.randf_range(18.0, 24.0)
	var zf := 0.4
	var cz := zf + d * 0.5
	var shop_h := 4.0
	var floor_h := 3.2
	var deck := shop_h + floor_h * (storeys - 1)
	var top := deck + 0.5
	var wall := Color(ROMAN[r.randi() % ROMAN.size()])
	var enamel := Color(ENAMEL[r.randi() % ENAMEL.size()])
	var stone := Color(STONE[r.randi() % STONE.size()])
	b._block("brick", 0.0, w, d, cz, deck, top, wall)
	var fronts := maxi(1, roundi(w / 9.0))
	var fw := w / fronts
	for k in fronts:
		var fx := -w * 0.5 + (k + 0.5) * fw
		var sw := fw - 0.8
		if DenseBuilder.fine:
			b._light_pool(Vector3(fx, 0.1, zf - 0.2), sw * 1.4, 4.4, Color(0.78, 0.7, 0.58))  # the windows' spill after dark
		# Polished stone bulkhead, then glass to the canopy in tall lights.
		b._box("paint", Vector3(sw, 0.5, 0.12), Vector3(fx, 0.25, zf - 0.06), stone)
		var lights := maxi(3, roundi(sw / 1.6))
		var lw := sw / lights
		# A shop whose sign says it serves food shows its booths and counter.
		var eats := DenseBuilder.fine and b.sign_spec.is_empty() and int(b._word_slot(fx) * 0.5) - 1 in CommercialBuilder.EATERIES
		# Desktop: the room behind the glass fits the trade on the sign
		# (an insurance agent's desks, not a dress shop's racks).
		b.shop_kind = b._trade_room(int(b._word_slot(fx) * 0.5) - 1) if DenseBuilder.fine and b.sign_spec.is_empty() else 0
		for i in lights:
			var x := fx - sw * 0.5 + (i + 0.5) * lw
			if i == lights / 2:
				# The entry: a glass door in a wide aluminium stile.
				b._box("paint", Vector3(lw, 2.5, 0.06), Vector3(x, 1.25, zf - 0.03), ALUMINIUM)
				b._glass(Vector3(x, 1.2, zf - 0.07), Vector3(-1, 0, 0), lw - 0.3, 2.1, 0.0)
				b._glass(Vector3(x, 2.75, zf - 0.07), Vector3(-1, 0, 0), lw - 0.1, 0.4, 0.0)
				b._box("metal", Vector3(0.06, 2.5, 0.1), Vector3(x - lw * 0.5, 1.75, zf - 0.06), ALUMINIUM)
				if DenseBuilder.fine:
					# Desktop: the 1950s wide-stile door's hardware: a
					# horizontal push bar across the glass, a pull on the
					# stile, a kick plate and an aluminium threshold.
					b._box("metal", Vector3(lw - 0.4, 0.045, 0.045), Vector3(x, 1.05, zf - 0.13), ALUMINIUM.lightened(0.1))
					for t in [-1.0, 1.0]:
						b._box("metal", Vector3(0.03, 0.03, 0.07), Vector3(x + t * (lw * 0.5 - 0.25), 1.05, zf - 0.1), ALUMINIUM)
					b._box("metal", Vector3(lw - 0.3, 0.2, 0.01), Vector3(x, 0.25, zf - 0.075), ALUMINIUM.darkened(0.08))
					b._box("metal", Vector3(lw, 0.015, 0.2), Vector3(x, 0.008, zf - 0.13), Color("#9a9c9d"))
				continue
			b.shopfront = DenseBuilder.fine
			b.diner_room = 7.0 if eats else 0.0
			b._glass(Vector3(x, 1.75, zf - 0.03), Vector3(-1, 0, 0), lw - 0.06, 2.5, r.randf_range(0.0, 0.15))
			b.shopfront = false
			b.diner_room = 0.0
			b._box("metal", Vector3(0.06, 2.5, 0.1), Vector3(x - lw * 0.5, 1.75, zf - 0.06), ALUMINIUM)
		b.shop_kind = 0
		b._box("metal", Vector3(0.06, 2.5, 0.1), Vector3(fx + sw * 0.5, 1.75, zf - 0.06), ALUMINIUM)
		b._box("metal", Vector3(sw, 0.06, 0.1), Vector3(fx, 3.0, zf - 0.06), ALUMINIUM)
		# The cantilevered canopy, the shop's name on its fascia.
		b._box("paint", Vector3(sw + 0.4, 0.22, 1.8), Vector3(fx, 3.25, zf - 0.9), Color("#e8e4d8"))
		b._box("paint", Vector3(sw + 0.42, 0.36, 0.06), Vector3(fx, 3.3, zf - 1.8), enamel)
		b._sign(Vector3(fx, 3.37, zf - 1.86), minf(sw * 0.7, 6.0), 0.4)
		# Roman-brick piers between the shops.
		b._box("brick", Vector3(0.8, shop_h, 0.16), Vector3(fx - fw * 0.5 + 0.4, shop_h * 0.5, zf - 0.08), wall.darkened(0.05))
	b._box("brick", Vector3(0.8, shop_h, 0.16), Vector3(w * 0.5 - 0.4, shop_h * 0.5, zf - 0.08), wall.darkened(0.05))
	# Upstairs: steel ribbon windows over enamel spandrels.
	for f in range(1, storeys):
		var y0 := shop_h + (f - 1) * floor_h
		b._box("paint", Vector3(w - 1.2, 0.85, 0.06), Vector3(0, y0 + 0.43, zf - 0.04), enamel)
		b._glass(Vector3(0, y0 + 1.65, zf - 0.03), Vector3(-1, 0, 0), w - 1.6, 1.5, r.randf_range(0.0, 0.5))
		var n := maxi(3, roundi((w - 1.6) / 1.4))
		if DenseBuilder.fine:
			# Desktop: the spandrel is a row of separate enamelled steel
			# panels, one per window bay, held in aluminium battens with a
			# cap along the top (1950s storefront remodelling catalogues).
			for i in n + 1:
				b._box("metal", Vector3(0.05, 0.85, 0.08), Vector3(lerpf(-w * 0.5 + 0.8, w * 0.5 - 0.8, float(i) / n), y0 + 0.43, zf - 0.07),
					ALUMINIUM)
			for i in n:
				# Each panel faded a little differently by sixty summers.
				var fade := float(posmod(hash([r.seed, f, i, 77]), 100)) / 100.0
				var x0 := lerpf(-w * 0.5 + 0.8, w * 0.5 - 0.8, float(i) / n)
				var x1 := lerpf(-w * 0.5 + 0.8, w * 0.5 - 0.8, float(i + 1) / n)
				b._box("paint", Vector3(x1 - x0 - 0.04, 0.8, 0.02), Vector3((x0 + x1) * 0.5, y0 + 0.43, zf - 0.075),
					enamel.lightened(0.03 + fade * 0.07))
			b._box("metal", Vector3(w - 1.2, 0.05, 0.09), Vector3(0, y0 + 0.02, zf - 0.07), ALUMINIUM)
		for i in n + 1:
			b._box("metal", Vector3(0.05, 1.5, 0.08), Vector3(lerpf(-w * 0.5 + 0.8, w * 0.5 - 0.8, float(i) / n), y0 + 1.65, zf - 0.05),
				Color("#3a3d3e"))
		b._box("paint", Vector3(w - 1.4, 0.08, 0.2), Vector3(0, y0 + 0.88, zf - 0.1), Color("#d9d3c3"))
	b._box("metal", Vector3(w + 0.06, 0.14, 0.3), Vector3(0, top - 0.07, zf - 0.1), ALUMINIUM)
	# A blade sign at one end (1950s porcelain-and-neon), the flats' door
	# with a glass-block sidelight at the other.
	var e := 1.0 if r.randf() < 0.5 else -1.0
	if storeys >= 2:
		var by := shop_h + minf(1.6, (storeys - 1) * floor_h * 0.5)
		b._box("paint", Vector3(0.22, 2.6, 1.2), Vector3(e * (w * 0.5 - 0.5), by, zf - 0.7), enamel.darkened(0.25))
		b._box("paint", Vector3(0.26, 2.3, 1.0), Vector3(e * (w * 0.5 - 0.5), by, zf - 0.7), Color("#efe9d8"))
		b._box("metal", Vector3(0.08, 0.08, 0.6), Vector3(e * (w * 0.5 - 0.5), by + 1.35, zf - 0.3), BLACK)
		if DenseBuilder.fine:
			# Desktop: the blade's porcelain faces carry the tenant's name
			# across the top of the board, both sides, lit from
			# within after dark (1950s porcelain-enamel blade signs on
			# Indiana main streets, Marion and Kokomo).
			var bx := e * (w * 0.5 - 0.5)
			var v0 := b._word_slot(bx)
			var lit := enamel.darkened(0.2)
			lit.a = 0.9 / 60.0
			for sd in [-1.0, 1.0]:
				var x: float = bx + sd * 0.135
				var y0 := by + 0.45
				var za := zf - 0.25
				var zb := zf - 1.15
				# Reading from the wall out on one face, from the tip in on the other.
				var ua := 0.0 if sd > 0.0 else 0.9
				b._quad("sign", Vector3(x, y0, za), Vector3(x, y0, zb), Vector3(x, y0 + 0.42, zb), Vector3(x, y0 + 0.42, za), lit,
					[Vector2(ua, v0), Vector2(0.9 - ua, v0), Vector2(0.9 - ua, v0 + 1.0), Vector2(ua, v0 + 1.0)], Vector3(sd, 0, 0))
				# A band of the enamel colour below it, as the porcelain's
				# second colour, and a pinstripe.
				b._box("paint", Vector3(0.012, 1.2, 0.9), Vector3(x + sd * 0.002, by - 0.35, zf - 0.7), enamel)
				b._box("paint", Vector3(0.012, 0.03, 0.9), Vector3(x + sd * 0.004, by + 0.33, zf - 0.7), enamel.darkened(0.3))
	var sx := -e * (w * 0.5 - 0.9)
	b._box("paint", Vector3(1.0, 2.2, 0.06), Vector3(sx, 1.1, zf - 0.17), Color("#6b5038"))
	b._box("paint", Vector3(0.5, 2.2, 0.06), Vector3(sx + e * 0.8, 1.1, zf - 0.17), Color("#d8dcd8"))
	if DenseBuilder.fine:
		# Desktop: the flats' door as built: a stained flush door with a
		# narrow wired-glass lite, in an aluminium frame, a kick plate, a
		# lever and the street number; the sidelight is real glass block,
		# 8 in units set in white mortar, catching the light unevenly.
		var al := ALUMINIUM
		b._box("metal", Vector3(1.12, 0.06, 0.08), Vector3(sx, 2.23, zf - 0.19), al)
		for jx in [-0.53, 0.53]:
			b._box("metal", Vector3(0.06, 2.2, 0.08), Vector3(sx + jx, 1.1, zf - 0.19), al)
		b._glass(Vector3(sx + e * 0.22, 1.45, zf - 0.205), Vector3(-1, 0, 0), 0.16, 0.9, 0.4)
		b._box("metal", Vector3(0.84, 0.25, 0.01), Vector3(sx, 0.17, zf - 0.205), Color("#b8b4a8"))  # kick plate
		b._box("metal", Vector3(0.14, 0.025, 0.04), Vector3(sx - e * 0.36, 1.0, zf - 0.23), Color("#c9c6bc"))  # lever
		b._box("paint", Vector3(0.24, 0.1, 0.01), Vector3(sx, 2.36, zf - 0.205), Color("#1c1d1f"))  # number plate
		b._box("concrete", Vector3(1.3, 0.12, 0.5), Vector3(sx, 0.06, zf - 0.4), Color("#c4beb2"))  # the step
		var gx := sx + e * 0.8
		b._box("paint", Vector3(0.5, 2.2, 0.05), Vector3(gx, 1.1, zf - 0.165), Color("#e9e6dd"))  # mortar
		for row in 10:
			for col in 2:
				var lit := float(posmod(hash([r.seed, row, col, 31]), 100)) / 100.0
				b._box("paint", Vector3(0.2, 0.2, 0.03), Vector3(gx - 0.11 + col * 0.22, 0.12 + row * 0.215, zf - 0.2),
					Color("#a9c3c8").lightened(0.1 + lit * 0.25))
	b._box("metal", Vector3(1.8, 1.0, 1.2), Vector3(r.randf_range(-w * 0.3, w * 0.3), deck + 0.5, cz + 2.0), Color("#b9bcbc"))
	b._alley_side(w, zf + d, fronts, fw, storeys, shop_h, floor_h, wall)
	b._downtown_walk(to_curb, width, zf)


## The 2010s front.
static func _mi_newbuild(b: DenseBuilder, r: RandomNumberGenerator, to_curb: float, storeys: int) -> void:
	var width := b.half * 2.0
	var w := width - 0.4
	var d := r.randf_range(18.0, 24.0)
	var zf := 0.4
	var cz := zf + d * 0.5
	var shop_h := 4.6  # today's taller retail floor
	var floor_h := 3.2
	var deck := shop_h + floor_h * (storeys - 1)
	var top := deck + 0.8
	var brick := Color(NEW_BRICK[r.randi() % NEW_BRICK.size()])
	var panel := Color(PANEL[r.randi() % PANEL.size()])
	var stone := Color("#c8c0ae")
	b._block("brick", 0.0, w, d, cz, deck, top, brick)
	var bays := maxi(2, roundi(w / 7.0))
	var bw := w / bays
	var first_panel := r.randi() % 2
	for k in bays:
		var bx := -w * 0.5 + (k + 0.5) * bw
		var is_panel := k % 2 == first_panel and bays >= 2 and storeys >= 2
		var face := zf - (0.35 if is_panel else 0.0)
		# Shopfront: black frames, a transom over each light.
		var sw := bw - 0.8
		var lights := maxi(2, roundi(sw / 1.8))
		var lw := sw / lights
		var eats := DenseBuilder.fine and b.sign_spec.is_empty() and int(b._word_slot(bx) * 0.5) - 1 in CommercialBuilder.EATERIES
		b.shop_kind = b._trade_room(int(b._word_slot(bx) * 0.5) - 1) if DenseBuilder.fine and b.sign_spec.is_empty() else 0
		if DenseBuilder.fine:
			b._light_pool(Vector3(bx, 0.1, zf - 0.2), sw * 1.4, 4.4, Color(0.78, 0.7, 0.58))  # the windows' spill after dark
		b._box("paint", Vector3(sw, 0.45, 0.1), Vector3(bx, 0.22, zf - 0.05), stone)
		for i in lights:
			var x := bx - sw * 0.5 + (i + 0.5) * lw
			# Every shop has its own door, in its middle light (the odd bays
			# used to have none). The odd bays still take the random draw
			# their display light took, so nothing after it moves.
			if i == lights / 2:
				if k % 2 == 1:
					r.randf()
				b._box("paint", Vector3(1.1, 2.5, 0.05), Vector3(x, 1.25, zf - 0.03), BLACK)
				b._glass(Vector3(x, 1.25, zf - 0.07), Vector3(-1, 0, 0), 0.8, 2.2, 0.0)
				if DenseBuilder.fine:
					# Desktop: a brushed pull, a deep bottom rail and a threshold.
					b._box("metal", Vector3(0.035, 0.9, 0.035), Vector3(x + 0.28, 1.05, zf - 0.16), Color("#b9bbbc"))
					for y in [0.68, 1.42]:
						b._box("metal", Vector3(0.025, 0.025, 0.08), Vector3(x + 0.28, y, zf - 0.11), Color("#b9bbbc"))
					b._box("metal", Vector3(0.8, 0.22, 0.03), Vector3(x, 0.26, zf - 0.08), BLACK)
					b._box("metal", Vector3(1.1, 0.015, 0.2), Vector3(x, 0.01, zf - 0.12), Color("#9a9c9d"))
			else:
				b.shopfront = DenseBuilder.fine
				b.diner_room = 7.0 if eats else 0.0
				b._glass(Vector3(x, 1.85, zf - 0.03), Vector3(-1, 0, 0), lw - 0.08, 2.8, r.randf_range(0.0, 0.15))
				b.shopfront = false
				b.diner_room = 0.0
			b._glass(Vector3(x, 3.75, zf - 0.03), Vector3(-1, 0, 0), lw - 0.08, 0.7, 0.0)
			b._box("metal", Vector3(0.07, 3.8, 0.1), Vector3(x - lw * 0.5, 2.05, zf - 0.06), BLACK)
		b.shop_kind = 0
		b._box("metal", Vector3(0.07, 3.8, 0.1), Vector3(bx + sw * 0.5, 2.05, zf - 0.06), BLACK)
		b._box("metal", Vector3(sw, 0.08, 0.1), Vector3(bx, 3.3, zf - 0.06), BLACK)
		# A steel canopy on tie rods, the sign band above it.
		b._box("metal", Vector3(sw, 0.16, 1.5), Vector3(bx, 3.35, zf - 0.75), BLACK)
		for t in [-1.0, 1.0]:
			var a := Vector3(bx + t * sw * 0.35, 4.35, zf)
			var c := Vector3(bx + t * sw * 0.35, 3.45, zf - 1.45)
			b._box("metal", Vector3(0.04, 0.04, a.distance_to(c)), (a + c) * 0.5, BLACK,
				Basis(Vector3.RIGHT, -atan2(a.y - c.y, a.z - c.z)))
		if DenseBuilder.fine:
			# Desktop: the canopy's formed fascia channel with a drip lip,
			# and LED cans in its soffit lighting the walk (hung steel
			# canopies on new Indiana main-street infill, Carmel and
			# Noblesville).
			b._box("metal", Vector3(sw + 0.04, 0.28, 0.06), Vector3(bx, 3.33, zf - 1.5), BLACK)
			b._box("metal", Vector3(sw + 0.04, 0.03, 0.1), Vector3(bx, 3.195, zf - 1.53), BLACK)
			var cans := maxi(2, roundi(sw / 2.2))
			for q in cans:
				var lx := bx - sw * 0.5 + (q + 0.5) * sw / cans
				b._box("sign", Vector3(0.16, 0.012, 0.16), Vector3(lx, 3.265, zf - 0.85), Color(0.98, 0.95, 0.88, 1.0))
				b._light_pool(Vector3(lx, 0.11, zf - 1.0), 2.4, 2.6, Color(1.0, 0.95, 0.86))
		b._sign(Vector3(bx, 3.6, zf - 0.12), minf(sw * 0.6, 5.0), 0.45)
		b._box("brick", Vector3(0.8, shop_h, 0.2), Vector3(bx - bw * 0.5 + 0.4, shop_h * 0.5, zf - 0.1), brick.darkened(0.08))
		# Upstairs: projecting panel bays rise past the brick parapet.
		var bay_top := top + (0.9 if is_panel else 0.0)
		if is_panel:
			b._box("paint", Vector3(bw - 0.8, bay_top - shop_h, 0.35), Vector3(bx, (shop_h + bay_top) * 0.5, zf - 0.175), panel)
		b._box("metal", Vector3(bw - (0.6 if is_panel else 0.0), 0.3, 0.5 + (0.35 if is_panel else 0.0)),
			Vector3(bx, bay_top - 0.15, zf - 0.25 - (0.17 if is_panel else 0.0)), BLACK if is_panel else panel.darkened(0.3))
		for f in range(1, storeys):
			var y := shop_h + (f - 1) * floor_h + 1.6
			if is_panel:
				# One wide window pair with a Juliet balcony rail.
				for e in [-0.5, 0.5]:
					b._glass(Vector3(bx + e * 1.25, y, face - 0.02), Vector3(-1, 0, 0), 1.15, 2.0, r.randf_range(0.0, 0.6))
				if DenseBuilder.fine:
					# Desktop: the door pair in its dark aluminium frame
					# (jambs, a meeting mullion, head and sill), a formed
					# sill flashing over the panel below, and a lever on
					# each leaf, as new main-street flats are built.
					for jx in [-1.24, 0.0, 1.24]:
						b._box("metal", Vector3(0.08, 2.16, 0.07), Vector3(bx + jx, y, face - 0.045), BLACK)
					for hy in [1.04, -1.04]:
						b._box("metal", Vector3(2.56, 0.08, 0.07), Vector3(bx, y + hy, face - 0.045), BLACK)
					b._box("metal", Vector3(2.7, 0.03, 0.14), Vector3(bx, y - 1.095, face - 0.07), panel.darkened(0.25))
					for e in [-1.0, 1.0]:
						b._box("metal", Vector3(0.12, 0.025, 0.04), Vector3(bx + e * 0.14, y - 0.05, face - 0.1), Color("#b9bbbc"))
				b._box("metal", Vector3(2.6, 0.06, 0.4), Vector3(bx, y - 0.1, face - 0.2), BLACK)
				for q in 9:
					b._box("metal", Vector3(0.025, 0.9, 0.025), Vector3(bx - 1.3 + q * 2.6 / 8.0, y - 0.55, face - 0.38), BLACK)
				b._box("metal", Vector3(2.6, 0.05, 0.05), Vector3(bx, y - 0.1, face - 0.38), BLACK)
			else:
				var n := maxi(1, roundi((bw - 1.6) / 2.4))
				for i in n:
					var x := bx - (bw - 1.6) * 0.5 + (i + 0.5) * (bw - 1.6) / n
					b._glass(Vector3(x, y, zf - 0.02), Vector3(-1, 0, 0), 1.2, 1.9, r.randf_range(0.0, 0.6))
					b._box("paint", Vector3(1.5, 0.12, 0.18), Vector3(x, y - 1.01, zf - 0.09), stone)
					b._box("paint", Vector3(1.5, 0.22, 0.12), Vector3(x, y + 1.06, zf - 0.06), stone)
	b._box("brick", Vector3(0.8, shop_h, 0.2), Vector3(w * 0.5 - 0.4, shop_h * 0.5, zf - 0.1), brick.darkened(0.08))
	b._box("paint", Vector3(w, 0.3, 0.2), Vector3(0, shop_h + 0.05, zf - 0.1), stone)
	for i in r.randi_range(1, 3):
		b._box("metal", Vector3(1.6, 1.0, 1.1), Vector3(r.randf_range(-w * 0.35, w * 0.35), deck + 0.5, cz + 2.0), Color("#b9bcbc"))
	# The flats' lobby door at one end.
	var sx := (w * 0.5 - 0.9) * (-1.0 if r.randf() < 0.5 else 1.0)
	b._box("paint", Vector3(1.0, 2.3, 0.06), Vector3(sx, 1.15, zf - 0.21), BLACK)
	b._glass(Vector3(sx, 1.15, zf - 0.25), Vector3(-1, 0, 0), 0.75, 2.0, 0.0)
	b._alley_side(w, zf + d, bays, bw, storeys, shop_h, floor_h, brick)
	b._downtown_walk(to_curb, width, zf)
