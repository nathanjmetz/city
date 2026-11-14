class_name PropField
extends Node3D
## The scanned props the builders stood on their lots (PropLog), drawn as
## one MultiMesh per prop and map square, so a downtown full of benches and
## planters costs a few draw calls. Desktop only (the browser never logs
## any). Each square's MultiMeshes are rebuilt once a frame at most, when a
## lot in it changes. Props are close-up detail: they fade out past
## VISIBLE_TO metres, where the far versions of the buildings take over.

const SQUARE := 256.0
const VISIBLE_TO := 420.0

var _of := {}  # lot key -> [square, [[mesh key, world Transform3D], ...]]
var _squares := {}  # square -> {mesh key: MultiMeshInstance3D}
var _dirty := {}  # squares to rebuild


## Files lot `key`'s props, `props` from PropLog in the lot frame `frame`.
func put(key: String, frame: Transform3D, props: Array) -> void:
	drop(key)
	if props.is_empty():
		return
	var sq := Vector2i(floori(frame.origin.x / SQUARE), floori(frame.origin.z / SQUARE))
	var placed := []
	for p in props:
		placed.append([p[0], frame * (p[1] as Transform3D)])
	_of[key] = [sq, placed]
	_dirty[sq] = true


func drop(key: String) -> void:
	if _of.has(key):
		_dirty[_of[key][0]] = true
		_of.erase(key)


## How many props stand (for tests and the stats overlay).
func count() -> int:
	var n := 0
	for k in _of:
		n += _of[k][1].size()
	return n


func _process(_delta: float) -> void:
	if _dirty.is_empty():
		return
	var squares := _dirty.keys()
	_dirty.clear()
	for sq in squares:
		_rebuild(sq)


func _rebuild(sq: Vector2i) -> void:
	var by_mesh := {}
	for k in _of:
		if _of[k][0] != sq:
			continue
		for p in _of[k][1]:
			if not by_mesh.has(p[0]):
				by_mesh[p[0]] = []
			by_mesh[p[0]].append(p[1])
	var had: Dictionary = _squares.get(sq, {})
	for mk in had.keys():
		if not by_mesh.has(mk):
			had[mk].queue_free()
			had.erase(mk)
	for mk in by_mesh:
		var mesh := PropLog.mesh_of(mk)
		if mesh == null:
			continue
		var mmi: MultiMeshInstance3D = had.get(mk)
		if mmi == null:
			mmi = MultiMeshInstance3D.new()
			mmi.visibility_range_end = VISIBLE_TO
			mmi.visibility_range_end_margin = 40.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mmi)
			had[mk] = mmi
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var xfs: Array = by_mesh[mk]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		mmi.multimesh = mm
	if had.is_empty():
		_squares.erase(sq)
	else:
		_squares[sq] = had
