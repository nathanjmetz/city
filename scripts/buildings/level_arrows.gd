class_name LevelArrows
extends Node3D
## A green arrow rises over a home or business that has just gone up a
## level, a red one over one that has gone down, and fades in about 2 s
## (Nathan, 2026-10-25: "when properties reach a new level, an animated up
## (or down) arrow should show above the building for a moment").
## Drawing only: it watches the levels, it never changes them.

const RISE := 6.0      # metres the arrow floats up
const LIFE := 2.0      # seconds it shows
const MAX_AT_ONCE := 30
const UP := Color(0.25, 0.85, 0.35)
const DOWN := Color(0.9, 0.25, 0.2)

var sim: CitySim
var _levels := {}
var _live := 0


func setup(s: CitySim) -> void:
	sim = s
	_levels = _snapshot()
	sim.buildings_changed.connect(_on_changed)


func _snapshot() -> Dictionary:
	var out := {}
	for key in sim.buildings:
		out[key] = int(sim.buildings[key].get("level", 0))
	return out


func _on_changed() -> void:
	var now := _snapshot()
	for key in now:
		if _levels.has(key) and now[key] != _levels[key] and sim.lots.has(key) and _live < MAX_AT_ONCE:
			_show(Terrain.stand(sim.lots[key].pos), now[key] > _levels[key])
	_levels = now


func _show(at: Vector3, up: bool) -> void:
	# Neighbors' cities are drawn moved over to their place on the land.
	var shift := Terrain.shift_for(self)
	at += Vector3(shift.x, 0.0, shift.y)
	var l := Label3D.new()
	l.text = "▲" if up else "▼"
	l.font_size = 160
	l.outline_size = 24
	l.modulate = UP if up else DOWN
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.02
	l.position = at + Vector3(0, 12.0, 0)
	add_child(l)
	_live += 1
	var t := create_tween().set_parallel(true)
	t.tween_property(l, "position:y", l.position.y + RISE, LIFE).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, LIFE).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func():
		_live -= 1
		l.queue_free())
