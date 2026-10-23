class_name VehicleTypes
extends RefCounted
## Every kind of vehicle on the road, with real sizes and a realistic fleet
## mix for a Midwestern US town.
##
## Benchmark: real vehicles. Sizes are from the makers' spec sheets for the
## best seller in each class (Camry, Civic hatch, RAV4, Tahoe, F-150
## SuperCrew, F-250 regular cab, Odyssey, Mustang, Transit, P1000 step van,
## 26 ft box truck, 53 ft semi, Type C school bus, 40 ft transit bus, rear
## loader, pumper, Explorer Interceptor, Type III ambulance, JD 8R, JD S790).
## The mix leans on US registration data, with more pickups than the national
## average because this is the Midwest.
##
## The traffic simulation asks `spec()` for how a kind drives and `pick()`
## for what kind of vehicle makes a trip. Views ask `paint()` for its colour.

## len, width, height in metres. acc and brake (m/s^2) feed the Intelligent
## Driver Model; top_speed (m/s) caps the driver's speed; pref scales how fast
## the driver likes to go relative to the limit.
const SPECS := {
	"sedan":         {"len": 4.88, "width": 1.84, "height": 1.44, "acc": 2.0, "brake": 3.0, "top_speed": 55.0, "pref": 1.0},
	"hatchback":     {"len": 4.30, "width": 1.80, "height": 1.46, "acc": 2.0, "brake": 3.0, "top_speed": 52.0, "pref": 1.0},
	"crossover":     {"len": 4.60, "width": 1.86, "height": 1.70, "acc": 1.9, "brake": 3.0, "top_speed": 52.0, "pref": 1.0},
	"suv":           {"len": 5.35, "width": 2.06, "height": 1.93, "acc": 1.8, "brake": 3.0, "top_speed": 50.0, "pref": 1.0},
	"pickup":        {"len": 5.89, "width": 2.03, "height": 1.96, "acc": 1.8, "brake": 3.0, "top_speed": 50.0, "pref": 1.02},
	"work_pickup":   {"len": 5.94, "width": 2.03, "height": 2.00, "acc": 1.6, "brake": 2.8, "top_speed": 45.0, "pref": 0.98},
	"minivan":       {"len": 5.18, "width": 2.00, "height": 1.78, "acc": 1.8, "brake": 3.0, "top_speed": 50.0, "pref": 0.98},
	"sports":        {"len": 4.81, "width": 1.92, "height": 1.38, "acc": 2.8, "brake": 3.5, "top_speed": 70.0, "pref": 1.06},
	"motorcycle":    {"len": 2.20, "width": 0.85, "height": 1.25, "acc": 2.8, "brake": 3.0, "top_speed": 60.0, "pref": 1.04},
	"van":           {"len": 6.00, "width": 2.07, "height": 2.75, "acc": 1.4, "brake": 2.8, "top_speed": 40.0, "pref": 0.97},
	"delivery_van":  {"len": 7.00, "width": 2.40, "height": 3.10, "acc": 1.2, "brake": 2.6, "top_speed": 33.0, "pref": 0.95},
	"box_truck":     {"len": 10.40, "width": 2.60, "height": 3.90, "acc": 1.0, "brake": 2.5, "top_speed": 31.0, "pref": 0.95},
	"semi":          {"len": 21.90, "width": 2.60, "height": 4.10, "acc": 0.7, "brake": 2.0, "top_speed": 29.0, "pref": 0.94},
	"grain_truck":   {"len": 21.30, "width": 2.60, "height": 3.90, "acc": 0.7, "brake": 2.0, "top_speed": 29.0, "pref": 0.94},
	"log_truck":     {"len": 21.00, "width": 2.60, "height": 3.80, "acc": 0.6, "brake": 2.0, "top_speed": 29.0, "pref": 0.93},
	"ore_truck":     {"len": 20.00, "width": 2.60, "height": 3.60, "acc": 0.6, "brake": 2.0, "top_speed": 29.0, "pref": 0.93},
	"mail_truck":    {"len": 5.40, "width": 2.05, "height": 2.90, "acc": 1.6, "brake": 2.8, "top_speed": 31.0, "pref": 0.95},
	"rural_mail":    {"len": 4.88, "width": 1.89, "height": 1.85, "acc": 1.9, "brake": 3.0, "top_speed": 45.0, "pref": 0.97},
	"mail_semi":     {"len": 21.00, "width": 2.60, "height": 4.10, "acc": 0.7, "brake": 2.0, "top_speed": 29.0, "pref": 0.94},
	"livestock_truck": {"len": 21.90, "width": 2.60, "height": 4.10, "acc": 0.7, "brake": 2.0, "top_speed": 29.0, "pref": 0.94},
	"tanker":        {"len": 20.50, "width": 2.60, "height": 3.60, "acc": 0.7, "brake": 2.0, "top_speed": 29.0, "pref": 0.94},
	"flatbed":       {"len": 20.30, "width": 2.60, "height": 3.30, "acc": 0.7, "brake": 2.0, "top_speed": 29.0, "pref": 0.94},
	"dump_truck":    {"len": 9.00, "width": 2.60, "height": 3.40, "acc": 0.9, "brake": 2.3, "top_speed": 29.0, "pref": 0.93},
	"concrete_mixer": {"len": 10.40, "width": 2.60, "height": 3.95, "acc": 0.8, "brake": 2.2, "top_speed": 29.0, "pref": 0.92},
	"tow_truck":     {"len": 7.00, "width": 2.40, "height": 2.80, "acc": 1.3, "brake": 2.6, "top_speed": 36.0, "pref": 0.97},
	"school_bus":    {"len": 12.20, "width": 2.44, "height": 3.20, "acc": 1.0, "brake": 2.3, "top_speed": 27.0, "pref": 0.92},
	"city_bus":      {"len": 12.20, "width": 2.60, "height": 3.30, "acc": 1.0, "brake": 2.0, "top_speed": 27.0, "pref": 0.92},
	"garbage_truck": {"len": 9.80, "width": 2.60, "height": 3.70, "acc": 0.9, "brake": 2.3, "top_speed": 25.0, "pref": 0.9},
	"fire_engine":   {"len": 10.40, "width": 2.60, "height": 3.10, "acc": 1.2, "brake": 2.6, "top_speed": 30.0, "pref": 1.0},
	"taxi":          {"len": 4.88, "width": 1.84, "height": 1.62, "acc": 2.0, "brake": 3.0, "top_speed": 50.0, "pref": 1.0},
	"police":        {"len": 5.05, "width": 2.00, "height": 1.78, "acc": 2.4, "brake": 3.5, "top_speed": 66.0, "pref": 1.0},
	"ambulance":     {"len": 7.00, "width": 2.40, "height": 3.00, "acc": 1.4, "brake": 2.8, "top_speed": 40.0, "pref": 1.0},
	"tractor":       {"len": 5.60, "width": 2.60, "height": 3.30, "acc": 0.8, "brake": 2.0, "top_speed": 11.2, "pref": 1.0},
	"combine":       {"len": 9.00, "width": 3.60, "height": 4.00, "acc": 0.6, "brake": 1.8, "top_speed": 8.9, "pref": 1.0},
}

## Share of household trips by kind, in percent. Pickups are the top seller
## in the Midwest, then crossovers, sedans and full-size SUVs.
const PERSONAL := {
	"pickup": 20.0, "work_pickup": 4.0, "crossover": 20.0, "suv": 12.0, "sedan": 15.0,
	"hatchback": 4.0, "minivan": 5.0, "sports": 1.5, "motorcycle": 1.0, "van": 2.0,
}

## Real US car colours (share of the cars on the road): white, black, grey
## and silver make up three quarters. Each is [sRGB colour, weight].
const CAR_COLORS := [
	[Color(0.91, 0.91, 0.90), 23.0],  # white
	[Color(0.97, 0.96, 0.93), 3.0],   # pearl white
	[Color(0.04, 0.04, 0.05), 22.0],  # black
	[Color(0.33, 0.34, 0.36), 13.0],  # gunmetal grey
	[Color(0.52, 0.53, 0.55), 8.0],   # mid grey
	[Color(0.70, 0.71, 0.72), 9.0],   # silver
	[Color(0.06, 0.17, 0.40), 5.0],   # dark blue
	[Color(0.19, 0.36, 0.62), 4.0],   # bright blue
	[Color(0.55, 0.05, 0.06), 5.0],   # dark red
	[Color(0.75, 0.10, 0.08), 3.0],   # bright red
	[Color(0.15, 0.24, 0.18), 1.5],   # forest green
	[Color(0.42, 0.34, 0.26), 1.5],   # brown
	[Color(0.70, 0.64, 0.52), 1.0],   # beige
	[Color(0.85, 0.40, 0.08), 0.6],   # orange
	[Color(0.88, 0.70, 0.12), 0.4],   # yellow
]

## Work vehicles are mostly fleet white.
const FLEET_COLORS := [
	[Color(0.92, 0.92, 0.91), 70.0], [Color(0.70, 0.71, 0.72), 10.0], [Color(0.06, 0.17, 0.40), 6.0],
	[Color(0.75, 0.10, 0.08), 6.0], [Color(0.04, 0.04, 0.05), 8.0],
]
const SEMI_COLORS := [
	[Color(0.92, 0.92, 0.91), 30.0], [Color(0.65, 0.07, 0.07), 18.0], [Color(0.05, 0.05, 0.06), 16.0],
	[Color(0.10, 0.22, 0.50), 16.0], [Color(0.70, 0.71, 0.72), 10.0], [Color(0.13, 0.32, 0.18), 6.0],
	[Color(0.90, 0.55, 0.05), 4.0],
]
## Fixed liveries.
const LIVERY := {
	"school_bus": [[Color(0.97, 0.71, 0.0), 1.0]],    # National School Bus Glossy Yellow
	"city_bus": [[Color(0.93, 0.93, 0.92), 1.0]],
	"fire_engine": [[Color(0.72, 0.04, 0.06), 1.0]],
	"ambulance": [[Color(0.95, 0.95, 0.94), 1.0]],
	"mail_truck": [[Color(0.95, 0.95, 0.94), 1.0]],     # postal white
	"mail_semi": [[Color(0.92, 0.92, 0.91), 3.0], [Color(0.10, 0.22, 0.50), 2.0], [Color(0.65, 0.07, 0.07), 1.0]],
	"police": [[Color(0.05, 0.05, 0.06), 1.0], [Color(0.93, 0.93, 0.92), 1.0]],
	"taxi": [[Color(0.97, 0.76, 0.05), 3.0], [Color(0.91, 0.91, 0.90), 1.0]],  # cab yellow, or a white fleet
	"garbage_truck": [[Color(0.93, 0.93, 0.92), 3.0], [Color(0.16, 0.36, 0.20), 1.0]],
	"delivery_van": [[Color(0.93, 0.93, 0.92), 3.0], [Color(0.33, 0.22, 0.13), 1.0]],
	# Ready-mix fleets: white drums with a coloured cab, or all one colour.
	"concrete_mixer": [[Color(0.93, 0.93, 0.92), 3.0], [Color(0.92, 0.52, 0.05), 1.0], [Color(0.10, 0.22, 0.50), 1.0], [Color(0.70, 0.07, 0.07), 1.0]],
	"dump_truck": [[Color(0.92, 0.92, 0.91), 2.0], [Color(0.92, 0.52, 0.05), 1.0], [Color(0.90, 0.72, 0.05), 1.0]],
	"tow_truck": [[Color(0.92, 0.92, 0.91), 1.0], [Color(0.70, 0.07, 0.07), 1.0], [Color(0.05, 0.05, 0.06), 1.0]],
	# John Deere green, Case IH red, New Holland blue.
	"tractor": [[Color(0.21, 0.49, 0.17), 5.0], [Color(0.70, 0.08, 0.07), 3.0], [Color(0.10, 0.28, 0.58), 1.0]],
	"grain_truck": [[Color(0.65, 0.07, 0.07), 3.0], [Color(0.92, 0.92, 0.91), 3.0], [Color(0.10, 0.22, 0.50), 2.0], [Color(0.05, 0.05, 0.06), 2.0]],
	"combine": [[Color(0.21, 0.49, 0.17), 3.0], [Color(0.70, 0.08, 0.07), 2.0]],
}
## Every vehicle has a purpose. The simulation names the job (what the trip
## carries or what call it answers) and gets the right vehicle, the way every
## truck in Cities: Skylines is a real delivery. Each job lists the kinds
## that can do it, with weights.
const PURPOSE := {
	"commute": PERSONAL,
	"shopping": PERSONAL,
	# Freight.
	"grain": {"grain_truck": 8.0, "tractor": 2.0},       # hopper semis, tractors with wagons
	"livestock": {"livestock_truck": 1.0},  # pot-belly cattle and hog trailers
	"milk": {"tanker": 1.0},
	"fuel": {"tanker": 1.0},
	"goods": {"semi": 6.0, "box_truck": 4.0},             # factory to shop or warehouse
	"raw": {"log_truck": 3.0, "ore_truck": 3.0, "flatbed": 2.0, "dump_truck": 2.0},  # logs, ore, steel, gravel
	"parcels": {"delivery_van": 7.0, "van": 3.0},
	"food": {"box_truck": 5.0, "semi": 3.0},              # to grocery stores and restaurants
	"construction": {"dump_truck": 3.0, "concrete_mixer": 2.0, "flatbed": 2.0, "work_pickup": 3.0},
	"field_work": {"tractor": 4.0, "combine": 1.0},       # farmhouse to its own fields
	"harvest": {"combine": 1.0},
	# Services.
	"garbage": {"garbage_truck": 1.0},
	"fire": {"fire_engine": 1.0},
	"police": {"police": 1.0},
	"medical": {"ambulance": 1.0},
	"school": {"school_bus": 1.0},
	"transit": {"city_bus": 1.0},
	"taxi": {"taxi": 1.0},                               # the cab company's own cars
	"tow": {"tow_truck": 1.0},
	"service_call": {"work_pickup": 3.0, "van": 2.0},     # plumbers, electricians
	# Mail (Mail in scripts/sim/mail.gd).
	"mail": {"mail_truck": 1.0},                         # Oshkosh NGDV
	"rural_mail": {"rural_mail": 1.0},                   # carrier's own RHD Jeep
	"mail_freight": {"mail_semi": 1.0},                  # USPS 53 ft trailer
	"telecom": {"van": 4.0, "work_pickup": 3.0, "box_truck": 1.0},  # splicing vans, line crews, reel trucks
}

## Some cargo needs its own rig, whatever the job is called: logs ride a
## log trailer between stakes, ore an end-dump, crude oil a tanker.
const CARGO_KIND := {
	"logs": "log_truck", "ore": "ore_truck", "crude oil": "tanker", "fuel": "tanker",
	"milk": "tanker", "grain": "grain_truck", "cattle": "livestock_truck", "hogs": "livestock_truck",
	"livestock": "livestock_truck", "gravel": "dump_truck", "steel": "flatbed",
}

const FLEET := ["work_pickup", "van", "box_truck", "garbage_truck"]


static func kinds() -> Array:
	return SPECS.keys()


## How a kind drives. Unknown kinds drive like a sedan.
static func spec(kind: String) -> Dictionary:
	return SPECS.get(kind, SPECS["sedan"])


## What kind of vehicle makes a trip to a zone (ZoneMap.Zone) at an hour.
## ctx can say which services exist so their vehicles show up:
## {police, fire, clinic, school, farms: bool, population: int}.
## Uses one random number, so the simulation stays deterministic.
## Prefer `for_purpose()` when the trip has a reason; this is the fallback
## for background traffic.
static func pick(dest_zone: int, hour: int, rng: RandomNumberGenerator, ctx := {}) -> String:
	var w := PERSONAL.duplicate()
	var day := hour >= 6 and hour < 20
	if day:
		match dest_zone:
			ZoneMap.Zone.INDUSTRIAL:
				_add(w, {"semi": 8.0, "box_truck": 5.0, "dump_truck": 1.5, "work_pickup": 4.0})
			ZoneMap.Zone.COMMERCIAL:
				_add(w, {"delivery_van": 4.0, "box_truck": 3.0, "semi": 1.5})
			_:
				_add(w, {"delivery_van": 2.0, "tow_truck": 0.3})
	if ctx.get("police", false):
		_add(w, {"police": 1.2})
	if ctx.get("fire", false):
		_add(w, {"fire_engine": 0.3})
	if ctx.get("clinic", false):
		_add(w, {"ambulance": 0.4})
	if ctx.get("school", false) and (hour >= 6 and hour < 9 or hour >= 14 and hour < 17):
		_add(w, {"school_bus": 3.0})
	if int(ctx.get("population", 0)) >= 1500 and hour >= 5 and hour < 23:
		_add(w, {"city_bus": 0.8})
	if ctx.get("farms", false) and day:
		_add(w, {"tractor": 2.0, "combine": 0.6})
	return _weighted(w, rng.randf())


## The vehicle for a job, e.g. for_purpose("grain", rng) -> "grain_truck".
## Cargo with its own rig (see CARGO_KIND) wins over the job. Unknown jobs
## get a household vehicle. One random number per call.
static func for_purpose(purpose: String, rng: RandomNumberGenerator, cargo := {}) -> String:
	var r := rng.randf()
	var rig := for_cargo(cargo)
	return rig if rig != "" else _weighted(PURPOSE.get(purpose, PERSONAL), r)


## The rig a load needs ({"good": "logs", ...}), or "" if any truck will do.
static func for_cargo(cargo) -> String:
	if cargo is Dictionary:
		return CARGO_KIND.get(str(cargo.get("good", "")), "")
	return ""


## The jobs a kind can do (for tooltips and checks).
static func purposes_of(kind: String) -> Array:
	var out := []
	for p in PURPOSE:
		if PURPOSE[p].has(kind):
			out.append(p)
	return out


## A household vehicle from the fleet mix, fixed by an id (for cars the
## simulation hasn't given a kind).
static func household(id: int) -> String:
	return _weighted(PERSONAL, _hash01(id * 7 + 3))


## The sRGB body colour of one vehicle, fixed by its id so it never changes.
static func paint(kind: String, id: int) -> Color:
	var table: Array = LIVERY.get(kind, FLEET_COLORS if kind in FLEET else
		SEMI_COLORS if kind in ["semi", "tanker", "flatbed", "log_truck", "ore_truck", "livestock_truck"] else CAR_COLORS)
	var total := 0.0
	for e in table:
		total += e[1]
	var x := _hash01(id) * total
	for e in table:
		x -= e[1]
		if x <= 0.0:
			return e[0]
	return table[table.size() - 1][0]


static func _add(w: Dictionary, more: Dictionary) -> void:
	for k in more:
		w[k] = w.get(k, 0.0) + more[k]


static func _weighted(w: Dictionary, r: float) -> String:
	var keys := w.keys()
	keys.sort()
	var total := 0.0
	for k in keys:
		total += w[k]
	var x := r * total
	for k in keys:
		x -= w[k]
		if x <= 0.0:
			return k
	return keys[keys.size() - 1]


static func _hash01(id: int) -> float:
	var h := (id * 2654435761) & 0xffffffff
	h = ((h >> 13) ^ h) * 1274126177 & 0xffffffff
	return float(h & 0xffffff) / float(0x1000000)
