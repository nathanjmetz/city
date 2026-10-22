class_name RoadStyle
extends RefCounted
## Sizes for a typical US suburban street, in metres.

## Curb to curb: two 3.6 m lanes plus gutters.
const ASPHALT_WIDTH := 9.0
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


static func half_width() -> float:
	return ASPHALT_WIDTH * 0.5


## Distance from the road's centre line to the back of the sidewalk.
static func right_of_way_half() -> float:
	return half_width() + CURB_WIDTH + PARKWAY_WIDTH + SIDEWALK_WIDTH


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
