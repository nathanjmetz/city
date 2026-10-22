class_name RoadStyle
extends RefCounted
## Road types and their real US sizes, in metres.

enum Type { STREET, AVENUE, BOULEVARD, HIGHWAY, RAMP }

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
]

const CURB_WIDTH := 0.3
## Grass strip between curb and sidewalk ("parkway").
const PARKWAY_WIDTH := 1.8
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
const CURB_COLOR := Color(0.62, 0.61, 0.58)
const SIDEWALK_COLOR := Color(0.72, 0.71, 0.67)


const MARKING_YELLOW := Color(0.85, 0.68, 0.18)
const MARKING_WHITE := Color(0.88, 0.88, 0.86)
const MEDIAN_COLOR := Color(0.26, 0.36, 0.17)


## Half the curb-to-curb width.
static func half_width(type := 0) -> float:
	return TYPES[type].width * 0.5


## Distance from the road's centre line to the back of the sidewalk.
static func right_of_way_half(type := 0) -> float:
	if TYPES[type].oneway:
		return half_width(type) + 1.5  # barrier and clear zone, no sidewalk
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
