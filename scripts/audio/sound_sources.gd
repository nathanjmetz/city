class_name SoundSources
extends RefCounted
## Where the town makes noise, as plain data: every home, shop, factory,
## utility and farm field is a source with a position and a sound. The audio
## view plays only the ones nearest the camera, so what you see (or are close
## to) is what you hear. Plain data so it can be tested headless.

## Loops in assets/audio/world/, and how loud each sits in the mix (dB).
const GAIN := {
	"birds_day": -4.0, "crickets_night": -8.0, "leaves": -10.0, "rooftop_hvac": -9.0,
	"industry_hum": -3.0, "transformer": -12.0, "corn_field": -6.0,
}
## Most players any one sound may use at once, so a street of houses does not
## drown out the factory next to it.
const CAPS := {
	"birds_day": 4, "crickets_night": 4, "leaves": 2, "rooftop_hvac": 3,
	"industry_hum": 3, "transformer": 2, "corn_field": 3,
}
const UTILITY_KINDS := [Services.Kind.SUBSTATION, Services.Kind.POWER_FEED,
	Services.Kind.WATER_TOWER, Services.Kind.WELL]


## Birds sing from dawn to dusk; crickets take over on summer nights.
static func is_day(hour: int) -> bool:
	return hour >= 5 and hour < 21


## Every source in town: [{key, sound, pos}].
static func gather(sim: CitySim, hour: int) -> Array:
	var out := []
	var yard := "birds_day" if is_day(hour) else "crickets_night"
	for key in sim.buildings:
		if not sim.lots.has(key):
			continue
		var lot: Dictionary = sim.lots[key]
		var pos: Vector3 = lot.pos
		match int(sim.buildings[key].zone):
			ZoneMap.Zone.RESIDENTIAL:
				out.append({"key": "y" + key, "sound": yard, "pos": pos})
				out.append({"key": "l" + key, "sound": "leaves", "pos": pos})
			ZoneMap.Zone.COMMERCIAL:
				out.append({"key": "c" + key, "sound": "rooftop_hvac", "pos": pos + Vector3.UP * 6.0})
			ZoneMap.Zone.INDUSTRIAL:
				out.append({"key": "i" + key, "sound": "industry_hum", "pos": pos + Vector3.UP * 4.0})
	for id in sim.services.buildings:
		var b: Dictionary = sim.services.buildings[id]
		if int(b.kind) in UTILITY_KINDS:
			out.append({"key": "s%d" % id, "sound": "transformer", "pos": b.pos + Vector3.UP * 2.0})
	for id in sim.farms.farms:
		for c in sim.farms.farms[id].cells:
			out.append({"key": "f%d_%d_%d" % [id, c.x, c.y], "sound": "corn_field",
				"pos": Farms.cell_center(c) + Vector3.UP * 1.5})
	return out


## The sources to play: nearest first, within `max_dist` of the listener,
## at most `slots` in all and at most CAPS[sound] of each sound.
static func pick(sources: Array, listener: Vector3, slots: int, max_dist: float) -> Array:
	var near := []
	var max2 := max_dist * max_dist
	for s in sources:
		var d2: float = listener.distance_squared_to(s.pos)
		if d2 <= max2:
			near.append([d2, s])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var used := {}
	var out := []
	for e in near:
		var s: Dictionary = e[1]
		var n: int = used.get(s.sound, 0)
		if n >= CAPS.get(s.sound, 2):
			continue
		used[s.sound] = n + 1
		out.append(s)
		if out.size() >= slots:
			break
	return out
