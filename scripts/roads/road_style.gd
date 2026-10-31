class_name RoadStyle
extends RefCounted
## Road types and their real US sizes, in metres.

## Saves store a road's type by number, so new types are always appended.
enum Type { STREET, AVENUE, BOULEVARD, HIGHWAY, RAMP, RING, RING2,
	STREET_NARROW, STREET_BIKE, STREET_ONEWAY, MAIN_STREET, ALLEY, GRAVEL, COUNTY,
	AVENUE_TURN, AVENUE_BIKE, AVENUE_DIVIDED, AVENUE_ONEWAY,
	STRIP, PARKWAY,
	FREEWAY2, FREEWAY4, DIVIDED_HWY, STATE_HWY,
	RAMP2, AVENUE_BUS,
	DIRT, CHIP_SEAL, STREET_ONEWAY1, BRICK, STREET_DIVIDED,
	BOULEVARD_ONEWAY }

## The five road menus. Each variant names its menu with "group"; a type
## without one is the menu's own first road.
const GROUPS := [Type.STREET, Type.AVENUE, Type.BOULEVARD, Type.HIGHWAY, Type.RAMP]
## Parallel parking lane, 8 ft (AASHTO), and the depth of a 45-degree angled
## stall measured out from the curb (about 18 ft, ITE parking guide).
const PARKING_WIDTH := 2.4
const ANGLE_STALL := 5.5
## Bike lane, 5 ft (AASHTO Guide for the Development of Bicycle Facilities).
const BIKE_WIDTH := 1.5

## Each type: name, lanes, paved width, planted median width, whether it is
## one-way (traffic runs the way it was drawn), whether buildings can face it,
## its steepest allowed grade (AASHTO maximum grades) and speed limit.
## Lanes are 3.6 m (12 ft, the AASHTO standard lane).
const TYPES := [
	# Local street: two lanes plus room to park along the gutters.
	{"name": "Street", "lanes": 2, "width": 9.0, "median": 0.0, "oneway": false, "lots": true, "grade": 0.12, "mph": 25},
	# Collector: four lanes and gutters, double yellow line.
	{"name": "Avenue", "lanes": 4, "width": 15.0, "median": 0.0, "oneway": false, "lots": true, "grade": 0.10, "mph": 35},
	# Arterial: six lanes split by a 4 m planted median.
	{"name": "Boulevard", "lanes": 6, "width": 26.0, "median": 4.0, "oneway": false, "lots": true, "grade": 0.08, "mph": 45},
	# Freeway, one direction: three lanes, 10 ft right and 4 ft left shoulders.
	# Draw one each way (Parallel mode helps). No driveways.
	{"name": "Highway", "lanes": 3, "width": 15.0, "median": 0.0, "oneway": true, "lots": false, "grade": 0.05, "mph": 65},
	# Interchange ramp: one lane, 8 ft right and 4 ft left shoulders.
	{"name": "Ramp", "lanes": 1, "width": 7.2, "median": 0.0, "oneway": true, "lots": false, "grade": 0.08, "mph": 35},
	# Roundabout rings, built by the roundabout tool rather than picked.
	# FHWA (NCHRP 672): a single-lane circulatory roadway is 16-20 ft wide.
	{"name": "Roundabout", "lanes": 1, "width": 6.0, "median": 0.0, "oneway": true, "lots": false, "grade": 0.05, "mph": 20, "menu": false},
	# Two-lane (multilane) ring, about 32 ft.
	{"name": "Roundabout, 2 lanes", "lanes": 2, "width": 9.6, "median": 0.0, "oneway": true, "lots": false, "grade": 0.05, "mph": 25, "menu": false},

	# --- Variants, picked from the row above each road menu ---
	# Extra fields: group (its menu), short (its card name), parking (sides
	# with parallel parking), angle (45-degree angled parking instead), bike
	# (bike lane each side), turn (the median is a painted two-way left-turn
	# lane), trees (street trees down the median), rural (no curbs or
	# sidewalks: shoulders run off into the grass), shoulder (paved, outside
	# the edge line), surface (gravel or concrete), walk (sidewalks).
	# Every lane is 3.6 m, so the widths below add up from their parts.

	# Newer subdivision street, no parking: 24 ft of pavement (AASHTO local
	# street minimum for low-volume residential streets).
	{"name": "Narrow street", "short": "No parking", "group": Type.STREET, "lanes": 2, "width": 7.8, "median": 0.0,
		"oneway": false, "lots": true, "grade": 0.12, "mph": 25},
	# Two lanes and a 5 ft bike lane each side.
	{"name": "Street with bike lanes", "short": "Bike lanes", "group": Type.STREET, "lanes": 2, "width": 10.8,
		"median": 0.0, "oneway": false, "lots": true, "grade": 0.12, "mph": 25, "bike": true},
	# Downtown one-way pair: two lanes one way, parking both sides.
	{"name": "One-way street", "short": "One-way", "group": Type.STREET, "lanes": 2, "width": 12.6, "median": 0.0,
		"oneway": true, "lots": true, "grade": 0.12, "mph": 25, "parking": 2},
	# Courthouse-square main street: two lanes with 45-degree angled parking
	# both sides (Petersburg, Jasper, Washington IN).
	{"name": "Main street", "short": "Main St", "group": Type.STREET, "lanes": 2, "width": 18.8, "median": 0.0,
		"oneway": false, "lots": true, "grade": 0.10, "mph": 20, "angle": true},
	# Alley behind the homes: 16 ft of concrete, no curbs, sidewalks or lines.
	# Garages open onto it; houses still face the street.
	{"name": "Alley", "short": "Alley", "group": Type.STREET, "lanes": 2, "width": 5.0, "median": 0.0,
		"oneway": false, "lots": false, "grade": 0.12, "mph": 15, "surface": "concrete", "walk": false, "rural": true,
		"verge": 1.0},
	# Indiana county gravel road: 20 ft of crushed limestone, no lines.
	{"name": "Gravel road", "short": "Gravel", "group": Type.STREET, "lanes": 2, "width": 6.0, "median": 0.0,
		"oneway": false, "lots": true, "grade": 0.10, "mph": 40, "surface": "gravel", "walk": false, "rural": true},
	# Paved county road: two 11-12 ft lanes, edge lines, gravel shoulders.
	{"name": "County road", "short": "County", "group": Type.STREET, "lanes": 2, "width": 7.8, "median": 0.0,
		"oneway": false, "lots": true, "grade": 0.10, "mph": 55, "walk": false, "rural": true},

	# Three-lane road: one lane each way and a two-way left-turn lane, the
	# usual Midwest "road diet" (FHWA Road Diet Informational Guide).
	{"name": "Avenue, center turn lane", "short": "Turn lane", "group": Type.AVENUE, "lanes": 2, "width": 11.4,
		"median": 3.6, "oneway": false, "lots": true, "grade": 0.10, "mph": 35, "turn": true},
	{"name": "Avenue with bike lanes", "short": "Bike lanes", "group": Type.AVENUE, "lanes": 4, "width": 18.0,
		"median": 0.0, "oneway": false, "lots": true, "grade": 0.10, "mph": 35, "bike": true},
	# Four lanes split by a 16 ft raised median with trees, which leaves
	# room for left-turn bays (AASHTO Green Book).
	{"name": "Divided avenue", "short": "Divided", "group": Type.AVENUE, "lanes": 4, "width": 20.4, "median": 4.8,
		"oneway": false, "lots": true, "grade": 0.10, "mph": 35, "trees": true},
	# Downtown one-way avenue: three lanes, parking both sides.
	{"name": "One-way avenue", "short": "One-way", "group": Type.AVENUE, "lanes": 3, "width": 16.2, "median": 0.0,
		"oneway": true, "lots": true, "grade": 0.10, "mph": 30, "parking": 2},

	# Five-lane commercial strip: two lanes each way and a center turn lane.
	{"name": "Five-lane strip", "short": "Strip", "group": Type.BOULEVARD, "lanes": 4, "width": 18.6, "median": 3.6,
		"oneway": false, "lots": true, "grade": 0.08, "mph": 45, "turn": true},
	# Historic parkway: four lanes either side of a 30 ft tree-lined median
	# (Indianapolis park and boulevard system).
	{"name": "Parkway", "short": "Parkway", "group": Type.BOULEVARD, "lanes": 4, "width": 24.6, "median": 9.0,
		"oneway": false, "lots": true, "grade": 0.08, "mph": 40, "trees": true},

	# Freeways, one direction each: 10 ft right and 4 ft left shoulders.
	# Rural interstate (I-64, I-69 in southern Indiana): two lanes, 70 mph.
	{"name": "Freeway, 2 lanes", "short": "2 lanes", "group": Type.HIGHWAY, "lanes": 2, "width": 11.4, "median": 0.0,
		"oneway": true, "lots": false, "grade": 0.05, "mph": 70},
	{"name": "Freeway, 4 lanes", "short": "4 lanes", "group": Type.HIGHWAY, "lanes": 4, "width": 18.6, "median": 0.0,
		"oneway": true, "lots": false, "grade": 0.05, "mph": 65},
	# Divided highway (US-231, SR-57): two lanes each way, a 40 ft grass
	# median with 4 ft inside shoulders, 10 ft outside shoulders, crossroads
	# and driveways at grade (AASHTO rural arterial).
	{"name": "Divided highway", "short": "Divided", "group": Type.HIGHWAY, "lanes": 4, "width": 34.8, "median": 14.4,
		"oneway": false, "lots": true, "grade": 0.05, "mph": 60, "walk": false, "rural": true, "shoulder": 3.0},
	# Two-lane state highway with 8 ft paved shoulders.
	{"name": "State highway", "short": "2-lane", "group": Type.HIGHWAY, "lanes": 2, "width": 12.0, "median": 0.0,
		"oneway": false, "lots": true, "grade": 0.06, "mph": 55, "walk": false, "rural": true, "shoulder": 2.4},

	# Two-lane ramp: 8 ft right and 4 ft left shoulders.
	{"name": "Ramp, 2 lanes", "short": "2 lanes", "group": Type.RAMP, "lanes": 2, "width": 10.8, "median": 0.0,
		"oneway": true, "lots": false, "grade": 0.08, "mph": 35},

	# Four lanes with the curb lane each way for buses only (MUTCD 3D
	# preferential lanes; red paint per FHWA Interim Approval IA-22). Cars
	# may cross into it to turn right at the next corner or reach a driveway.
	{"name": "Avenue with bus lanes", "short": "Bus lanes", "group": Type.AVENUE, "lanes": 4, "width": 15.0,
		"median": 0.0, "oneway": false, "lots": true, "grade": 0.10, "mph": 35, "bus": true},

	# Unimproved dirt road: a 16 ft graded earth two-track, the field lanes
	# and township roads never graveled (AASHTO Guidelines for Very Low-Volume
	# Local Roads, ADT under 400). Cars slow and squeeze by each other.
	{"name": "Dirt road", "short": "Dirt", "group": Type.STREET, "lanes": 2, "width": 4.8, "median": 0.0,
		"oneway": false, "lots": true, "grade": 0.10, "mph": 30, "surface": "dirt", "walk": false, "rural": true},
	# Chip-seal county road: liquid asphalt with stone chips rolled into it
	# over the old gravel bed, the usual Indiana county highway department
	# upgrade. About 20 ft wide and seldom striped.
	{"name": "Chip-seal road", "short": "Chip seal", "group": Type.STREET, "lanes": 2, "width": 6.0, "median": 0.0,
		"oneway": false, "lots": true, "grade": 0.10, "mph": 45, "surface": "chip seal", "walk": false, "rural": true},
	# Older-neighborhood one-way: one 12 ft lane between parking both sides,
	# about 30 ft curb to curb (MUTCD R6-1 ONE WAY signs at each corner).
	{"name": "One-way street, 1 lane", "short": "One-way 1", "group": Type.STREET, "lanes": 1, "width": 9.0,
		"median": 0.0, "oneway": true, "lots": true, "grade": 0.12, "mph": 25, "parking": 2},
	# Historic brick street: vitrified paving brick laid across the street
	# in running bond, the way Indiana towns paved from about 1890 to 1930
	# and still keep near courthouses. Same size as a local street.
	{"name": "Brick street", "short": "Brick", "group": Type.STREET, "lanes": 2, "width": 9.0, "median": 0.0,
		"oneway": false, "lots": true, "grade": 0.12, "mph": 20, "surface": "brick"},
	# Subdivision entrance boulevard: a lane each way either side of a 16 ft
	# planted median with trees.
	{"name": "Divided street", "short": "Divided", "group": Type.STREET, "lanes": 2, "width": 13.2, "median": 4.8,
		"oneway": false, "lots": true, "grade": 0.12, "mph": 25, "trees": true},
	# Downtown one-way arterial: four lanes one way with parking both sides,
	# half of a one-way pair (Indianapolis's Meridian and Illinois, Fort
	# Wayne's Clinton and Lafayette). The big one-way a growing city needs.
	{"name": "One-way boulevard", "short": "One-way", "group": Type.BOULEVARD, "lanes": 4, "width": 19.2,
		"median": 0.0, "oneway": true, "lots": true, "grade": 0.08, "mph": 35, "parking": 2},
]
## Raised concrete ring inside a roundabout that long trucks can ride over
## with their back wheels (FHWA: typically 10-15 ft).
const TRUCK_APRON := 3.5

const CURB_WIDTH := 0.3
## Grass strip between curb and sidewalk ("parkway").
const PARKWAY_WIDTH := 1.8
## The concrete gutter pan inside the curb (2 ft), part of the pavement width.
const GUTTER_WIDTH := 0.6
const SIDEWALK_WIDTH := 1.5

## Height of each layer above the ground, to keep them from flickering.
const Y_SIDEWALK := 0.04
const Y_CURB := 0.07
const Y_ASPHALT := 0.09
const Y_JUNCTION := 0.11

## Tightest bend allowed on a street's centre line: 42 ft, the AASHTO minimum
## design turning radius of a single-unit truck (SU-30, a box or garbage
## truck), which every local street has to serve.
const MIN_CURVE_RADIUS := 12.8

const ASPHALT_COLOR := Color(0.23, 0.23, 0.24)
## Weathered grey concrete, 20 to 60 years old, not new white pour
## (critic round 3, 2026-10-30: 197 in sun, outlining every block in white
## from 300 m). Measured albedo of real pavement (LBNL Heat Island Group,
## EPA Cool Pavements): new concrete 0.35 to 0.45, aged 0.25 to 0.35; aged
## asphalt 0.10 to 0.15, which the streets' own grey already is (about
## 0.11 linear), and the repo's two photo scans (art/textures/roads) put
## concrete at 2.1 times asphalt. So the walk is about 0.27 linear (0.48
## before; 0.25 with its weathering, Surfaces.CONCRETE) and the curb,
## splashed by the street, about 0.23.
const CURB_COLOR := Color(0.53, 0.52, 0.49)
const SIDEWALK_COLOR := Color(0.56, 0.55, 0.52)


const MARKING_YELLOW := Color(0.85, 0.68, 0.18)
const MARKING_WHITE := Color(0.88, 0.88, 0.86)
const MEDIAN_COLOR := Color(0.26, 0.36, 0.17)


## The ring a roundabout gets when built with this road type: one lane for
## streets and ramps, two for bigger roads.
static func ring_type(type: int) -> int:
	return Type.RING if type == Type.STREET or type == Type.RAMP else Type.RING2


## Gravel and dirt: no pavement, so no zoning frontage or resurfacing.
static func unpaved(type: int) -> bool:
	return TYPES[type].get("surface", "") in ["gravel", "dirt"]


static func is_ring(type: int) -> bool:
	return type == Type.RING or type == Type.RING2


## The menu a road type belongs to (STREET, AVENUE, BOULEVARD, HIGHWAY or RAMP).
static func group(type: int) -> int:
	return TYPES[type].get("group", type)


## The road types in one menu, its own first.
static func variants(menu: int) -> Array:
	var out := []
	for t in TYPES.size():
		if TYPES[t].get("menu", true) and group(t) == menu:
			out.append(t)
	return out


## Freeways and ramps: one-way, walled, no driveways.
static func is_freeway(type: int) -> bool:
	return TYPES[type].oneway and not TYPES[type].lots


## A median with curbs (planted), not a painted turn lane or a grass ditch.
static func raised_median(type: int) -> bool:
	var spec: Dictionary = TYPES[type]
	return spec.median > 0.0 and not spec.get("turn", false) and not spec.get("rural", false)


## The bus-only lane on each way of a road (its curb lane), or -1.
static func bus_lane(type: int) -> int:
	var spec: Dictionary = TYPES[type]
	if not spec.get("bus", false):
		return -1
	return (spec.lanes if spec.oneway else spec.lanes / 2) - 1


## Width of the parking lane each side (0 without parking).
static func parking_width(type: int) -> float:
	var spec: Dictionary = TYPES[type]
	if spec.get("angle", false):
		return ANGLE_STALL
	return PARKING_WIDTH if spec.get("parking", 0) > 0 else 0.0


## Half the curb-to-curb width.
static func half_width(type := 0) -> float:
	return TYPES[type].width * 0.5


## Distance from the road's centre line to the back of the sidewalk.
static func right_of_way_half(type := 0) -> float:
	if is_freeway(type):
		return half_width(type) + 1.5  # barrier and clear zone, no sidewalk
	if TYPES[type].get("rural", false):
		return half_width(type) + TYPES[type].get("verge", 3.0)  # gravel shoulder and a mowed verge
	return half_width(type) + CURB_WIDTH + PARKWAY_WIDTH + SIDEWALK_WIDTH


const MPH := 0.44704  # metres per second


## Highest speed a curve of this radius is safe for, in mph (AASHTO:
## R = V^2 / 15(e + f), with 6% superelevation and a typical side friction).
static func safe_speed_mph(radius_m: float) -> int:
	var feet := radius_m * 3.28084
	return int(minf(sqrt(15.0 * feet * (0.06 + 0.15)), 75.0))


static func material(color: Color, transparent := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
	return m
