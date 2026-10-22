class_name SkyLight
extends Node3D
## Sky, sun, haze and shadows, tuned against real photos of a Midwestern
## town on a clear late-morning day (benchmark: reality, not other games).
## What the photos show, and what this copies:
##   - a deep blue zenith fading to a pale, slightly warm haze at the horizon
##   - a warm sun about 40 degrees up, so walls and roofs cast clear shadows
##   - shadow sides lit by blue skylight, about a third as bright as sunlit sides
##   - distant blocks fading into blue-grey air (aerial perspective)
## Works in the Compatibility renderer, so it runs on the web build too.

## Sun height above the horizon and compass direction, in degrees.
const SUN_ELEVATION := 40.0
const SUN_AZIMUTH := -38.0
const HAZE := Color(0.74, 0.79, 0.84)

var sun := DirectionalLight3D.new()
var env := Environment.new()


func _ready() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.17, 0.36, 0.70)
	sky_mat.sky_horizon_color = HAZE
	sky_mat.sky_curve = 0.12
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_horizon_color = HAZE
	sky_mat.ground_bottom_color = Color(0.32, 0.34, 0.30)
	sky_mat.ground_curve = 0.05
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Skylight fills the shadows; a little less than the sun so shadows read.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Part sky, part neutral bounce light from lawns and pavement, so shade
	# reads blue-grey like in photos rather than saturated blue.
	env.ambient_light_sky_contribution = 0.6
	env.ambient_light_color = Color(0.66, 0.66, 0.64)
	env.ambient_light_energy = 0.62
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# AgX keeps bright roofs and concrete from clipping to flat white.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	# Aerial perspective: far blocks fade into haze, with a warm glow toward the sun.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = HAZE
	env.fog_light_energy = 1.0
	env.fog_density = 0.00045
	env.fog_sun_scatter = 0.15
	env.fog_sky_affect = 0.25
	# AgX mutes colour, so bring saturation and contrast back up to photo levels.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun.rotation_degrees = Vector3(-SUN_ELEVATION, SUN_AZIMUTH, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 600.0
	add_child(sun)


func _process(_delta: float) -> void:
	# Fit the shadow range to what the camera is looking at, so shadows stay
	# sharp up close and still reach the whole view when zoomed out.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var dir := -cam.global_basis.z
	var reach := 600.0
	if dir.y < -0.05:
		reach = cam.global_position.y / -dir.y
	sun.directional_shadow_max_distance = clampf(reach * 2.0, 120.0, 2000.0)
