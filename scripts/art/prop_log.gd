class_name PropLog
extends RefCounted
## Scanned props (AssetLib) that a builder stands on its lot: a bench, a
## planter, a cafe's sandwich board. Builders draw everything else into one
## merged mesh; a scan is far too heavy to copy into every building's mesh,
## so the builder only notes where it goes and the view instances it
## (PropField, one MultiMesh per prop and map square).
##
##     if not PropLog.place(self, "planter_box_02", Transform3D(Basis(), Vector3(x, 0, z))):
##         _code_built_planter(x, z)   # the browser, a fresh install, a dry run
##
## place() says true only while a view collects (collect()) and this
## machine has the scan; otherwise the builder draws its own version. Keep
## that fallback free of the builder's rng (or on its own rng), so a
## building comes out the same with or without the art.
##
## A prop is [mesh key, Transform3D] in the builder's local frame (x across
## the lot, y up, -z toward the street); the key is "id|parts|skip" as
## AssetLib.mesh takes them (mesh_of turns it back into the mesh).

## While a caller collects, every prop placed; null otherwise.
static var drawn = null


## Stands prop `id` (AssetLib.mesh(id, parts, skip)) at `xf` in builder
## `b`'s frame. False when it can't be shown: draw the code-built one.
static func place(b: Object, id: String, xf: Transform3D, parts: Array = [], skip: Array = []) -> bool:
	if drawn == null:
		return false
	var key := "%s|%s|%s" % [id, ",".join(parts), ",".join(skip)]
	if mesh_of(key) == null:
		return false
	drawn.append([key, xf])
	return true


## The mesh a prop key names, or null.
static func mesh_of(key: String) -> Mesh:
	var p := key.split("|")
	var parts: Array = [] if p.size() < 2 or p[1] == "" else Array(p[1].split(","))
	var skip: Array = [] if p.size() < 3 or p[2] == "" else Array(p[2].split(","))
	return AssetLib.mesh(p[0], parts, skip)


## The props placed while `draw` runs (it draws one building). An outer
## collection is put back after. In the browser it only draws.
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
