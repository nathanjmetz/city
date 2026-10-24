class_name Resources
extends RefCounted
## What lies in and under the land, the same everywhere for every player and
## forever: soil fertility for farms, and oil, ore and forest deposits for
## industry. Nothing runs out (Brawn's rule): a deposit is as rich in a
## hundred years as on the first day.
##
## Each is 0 to 1 at any point on the map, with no grid, read from the real
## land (Terrain): fertility from real farmland, slopes and river bottoms;
## forest from real tree cover; ore is the coal under the uplands and old
## strip mines; oil the Illinois Basin's pools (see
## tools/terrain/build_region.py for how each is worked out).
##
## `offset` is where the city sits in the region (its sim's terrain_offset);
## 0 in solo play. Left out, it is `origin`, which the town's sim keeps set,
## so the sim reads the same land the player sees under the town.

enum Kind { FERTILITY, OIL, ORE, FOREST }

const NAMES := ["Fertility", "Oil", "Ore", "Forest"]
## Where this computer's town sits in the region (CitySim.terrain_offset).
static var origin := Vector2.ZERO
## Set once the game pins `origin` to the player's own town, so loading a
## neighbor's copy doesn't move it.
static var pinned := false


## A sim's land moved: follow it unless the game pinned its own town's.
static func follow(offset: Vector2) -> void:
	if not pinned:
		origin = offset


## The player's own town: its land is the one read from now on.
static func pin(offset: Vector2) -> void:
	origin = offset
	pinned = true


## How much of a resource is at a point, 0 to 1.
static func at(kind: int, p: Vector3, offset := Vector2.INF) -> float:
	if offset == Vector2.INF:
		offset = origin
	if kind == Kind.FERTILITY:
		return fertility(p, offset)
	return Terrain.resource(kind, p.x + offset.x, p.z + offset.y)


## How good the soil is at a point: about 0.35 (wooded hills, strip mines)
## to 1 (river-bottom loam); 0 in the water.
static func fertility(p: Vector3, offset := Vector2.INF) -> float:
	if offset == Vector2.INF:
		offset = origin
	var x := p.x + offset.x
	var z := p.z + offset.y
	if Terrain.is_water(x, z):
		return 0.0
	return clampf(0.35 + 0.65 * Terrain.resource(Kind.FERTILITY, x, z), 0.35, 1.0)


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
