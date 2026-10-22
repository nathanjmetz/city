class_name Resources
extends RefCounted
## What lies in and under the land, the same everywhere for every player and
## forever: soil fertility for farms, and oil, ore and forest deposits for
## industry. Nothing runs out (Brawn's rule): a deposit is as rich in a
## hundred years as on the first day.
##
## Each is 0 to 1 at any point on the map, with no grid: smooth noise.

enum Kind { FERTILITY, OIL, ORE, FOREST }

const NAMES := ["Fertility", "Oil", "Ore", "Forest"]
## Feature size in metres and the noise salt for each deposit kind.
const _SHAPES := {
	Kind.OIL: [700.0, 11, 0.6, 0.78],
	Kind.ORE: [520.0, 23, 0.62, 0.8],
	Kind.FOREST: [380.0, 37, 0.52, 0.72],
}


## How much of a resource is at a point, 0 to 1.
static func at(kind: int, p: Vector3) -> float:
	if kind == Kind.FERTILITY:
		return fertility(p)
	var shape: Array = _SHAPES[kind]
	var n := _fbm(Vector2(p.x, p.z) / float(shape[0]), int(shape[1]))
	return smoothstep(float(shape[2]), float(shape[3]), n)


## How good the soil is at a point, about 0.45 to 1 (mostly good Midwest
## loam, with poorer patches).
static func fertility(p: Vector3) -> float:
	var f := 0.0
	var amp := 0.5
	var scale := 9.0
	for octave in 3:
		f += amp * value_noise(Vector2(p.x, p.z) / 40.0 / scale, octave)
		amp *= 0.5
		scale *= 0.5
	return clampf(0.45 + f * 0.7, 0.35, 1.0)


## Three octaves of value noise, about 0 to 1.
static func _fbm(p: Vector2, salt: int) -> float:
	var f := 0.0
	var amp := 0.5
	var total := 0.0
	for octave in 3:
		f += amp * value_noise(p * pow(2.0, octave), salt * 10 + octave)
		total += amp
		amp *= 0.5
	return f / total


## Smooth random value at a point, the same every time.
static func value_noise(p: Vector2, salt: int) -> float:
	var i := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(i)
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	var a := hash01(i, salt)
	var b := hash01(i + Vector2i(1, 0), salt)
	var c := hash01(i + Vector2i(0, 1), salt)
	var d := hash01(i + Vector2i(1, 1), salt)
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


static func hash01(i: Vector2i, salt: int) -> float:
	var h := (i.x * 374761393 + i.y * 668265263 + salt * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10007) / 10006.0
