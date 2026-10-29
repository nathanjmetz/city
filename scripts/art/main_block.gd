class_name MainBlock
extends RefCounted
## A commercial block (BuildingTypes "commercial_block"): a Main Street
## owner bought the storefront next door and built one front across both,
## as the 1880s-1910s blocks on Indiana's courthouse squares were built
## (Wabash, Huntington, Marion, Bluffton). Its shops and flats are a Main
## Street block's (DenseBuilder._mixed, drawn on the wider lot); over them
## it carries what marks it as one building: Indiana limestone belt
## courses at every floor line, stone piers at its ends rising to finials,
## and a raised parapet in the middle with a name-and-year panel.

const STONE := Color("#cfc6b2")  # Bedford limestone
const PANEL := Color("#b7ad97")
## DenseBuilder._mixed's storey heights (keep in step with it).
const SHOP_H := 4.2
const FLOOR_H := 3.4


static func build(seed: int, to_curb: float, lot: Dictionary, storeys: int, spec := {}) -> Array:
	var b := DenseBuilder._start(seed, lot, spec)
	if b.era != "prewar" and storeys <= 4 and not HouseBuilder.restored:
		# Built new across two lots on a postwar or recent street, it is a
		# building of its own decade, never an 1880s block with a date
		# panel: MainInfill's 1950s-60s or 2010s front, as wide as the lots.
		MainInfill.draw(b, to_curb, storeys)
		b._service_yard(false)
		return b._done()
	b._mixed(to_curb, b.half * 2.0, storeys)
	b._service_yard(b.era == "prewar")
	_crown(b, b.half * 2.0 - 0.4, storeys, hash([seed, "block"]))
	return b._done()


## The block's stonework over a Main Street front `w` wide, face at z 0.4.
static func _crown(b: DenseBuilder, w: float, storeys: int, dice: int) -> void:
	var zf := 0.4
	var top := SHOP_H + FLOOR_H * (storeys - 1) + 0.7
	# Belt courses: a stone band at each upper floor line, and a sill
	# course under the top floor's windows.
	for f in range(1, storeys):
		var y := SHOP_H + (f - 1) * FLOOR_H
		b._box("paint", Vector3(w, 0.2, 0.18), Vector3(0, y + 0.3, zf - 0.09), STONE)
	b._box("paint", Vector3(w, 0.14, 0.2), Vector3(0, SHOP_H + (storeys - 2) * FLOOR_H + 0.56, zf - 0.1), STONE)
	# Stone piers at the ends, up past the cornice to a finial each.
	for s in [-1.0, 1.0]:
		var x: float = s * (w * 0.5 - 0.3)
		b._box("paint", Vector3(0.6, top - SHOP_H + 0.6, 0.3), Vector3(x, (SHOP_H + top + 0.6) * 0.5, zf - 0.15), STONE)
		b._box("paint", Vector3(0.8, 0.2, 0.5), Vector3(x, top + 0.7, zf - 0.15), STONE.darkened(0.06))
		b._box("paint", Vector3(0.36, 0.5, 0.36), Vector3(x, top + 1.05, zf - 0.15), STONE)
	# The raised parapet in the middle: stepped (Italianate) or a gable
	# (Romanesque), with the name-and-year panel.
	var pw := clampf(w * 0.38, 6.0, 10.0)
	var gable := posmod(dice, 2) == 0
	b._box("paint", Vector3(pw, 1.1, 0.4), Vector3(0, top + 0.55, zf - 0.1), STONE)
	b._box("paint", Vector3(pw * 0.62, 0.6, 0.12), Vector3(0, top + 0.55, zf - 0.33), PANEL)
	b._box("paint", Vector3(pw + 0.3, 0.16, 0.55), Vector3(0, top + 1.18, zf - 0.15), STONE.darkened(0.06))
	if gable:
		var rise := pw * 0.22
		var y := top + 1.26
		b._tri("paint", Vector3(-pw * 0.5, y, zf - 0.3), Vector3(pw * 0.5, y, zf - 0.3), Vector3(0, y + rise, zf - 0.3), STONE, [],
			Vector3(0, 0, -1))
		b._tri("paint", Vector3(pw * 0.5, y, zf + 0.1), Vector3(-pw * 0.5, y, zf + 0.1), Vector3(0, y + rise, zf + 0.1), STONE, [],
			Vector3(0, 0, 1))
		for s in [-1.0, 1.0]:
			var a := Vector3(s * pw * 0.5, y, zf - 0.3)
			var c := Vector3(0, y + rise, zf - 0.3)
			b._quad("paint", a, c, c + Vector3(0, 0, 0.4), a + Vector3(0, 0, 0.4), STONE.darkened(0.04), [],
				Vector3(s * rise, pw * 0.5, 0))
	else:
		b._box("paint", Vector3(pw * 0.5, 0.6, 0.4), Vector3(0, top + 1.56, zf - 0.1), STONE)
		b._box("paint", Vector3(pw * 0.5 + 0.2, 0.14, 0.5), Vector3(0, top + 1.9, zf - 0.12), STONE.darkened(0.06))
