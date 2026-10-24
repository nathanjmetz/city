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
##
## That late-morning look is the default. When the player turns on the
## day/night cycle, DayNight calls set_time() each frame and the sun follows
## its real path over southern Indiana for the season: low in winter, high
## and late in summer, golden at dusk, then moonlight and stars (Cities:
## Skylines 2 lighting is the benchmark for how it plays, reality for how
## it looks).

## Sun height above the horizon and compass direction, in degrees.
const SUN_ELEVATION := 40.0
const SUN_AZIMUTH := -38.0
const HAZE := Color(0.74, 0.79, 0.84)

## Night sky colours: deep navy overhead, a little city glow low down.
const NIGHT_TOP := Color(0.012, 0.02, 0.05)
const NIGHT_HORIZON := Color(0.05, 0.06, 0.1)
## Sky low toward the sun at sunset and sunrise.
const DUSK_HORIZON := Color(0.98, 0.56, 0.32)
const DUSK_TOP := Color(0.16, 0.22, 0.45)
const MOON_COLOR := Color(0.62, 0.72, 0.95)

var sun := DirectionalLight3D.new()
var env := Environment.new()
var sky_mat := ProceduralSkyMaterial.new()
## 0 in full daylight, 1 at full night. DayNight reads it.
var darkness := 0.0
var _day := {}  # the fixed late-morning look, to go back to
## How far from the camera shadows reach at most, in metres (Quality sets it).
var shadow_reach := 2000.0
## The browser's renderer (Compatibility) lights the same scene about twice
## as bright as the desktop's, with a blue cast from the sky's share of the
## ambient light, and takes the colour adjustments harder: fields, roads
## and roofs came out pale and washed. Measured on grey and grass cards
## against Forward+, these bring it back in line (the sky is left as is).
var _gl := RenderingServer.get_current_rendering_method() == "gl_compatibility"
var _light := 0.45 if _gl else 1.0
var _sky_share := 0.0 if _gl else 0.6


## Depth fog at street level (see _ready) and how high the haze reaches.
const HAZE_DENSITY := 0.00016
const HAZE_LAYER := 600.0


func _ready() -> void:
	sky_mat.sky_top_color = Color(0.17, 0.36, 0.70)
	sky_mat.sky_horizon_color = HAZE
	sky_mat.sky_curve = 0.12
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_horizon_color = HAZE
	# Below the horizon the sky shows only past the farthest land: the same
	# haze, so there is no grey band where the land runs out.
	sky_mat.ground_bottom_color = HAZE
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
	env.ambient_light_sky_contribution = _sky_share
	env.ambient_light_color = Color(0.66, 0.66, 0.64)
	env.ambient_light_energy = 0.62 * _light
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
	# About 24 km visibility, a clear Midwestern day (extinction 3.9 / range):
	# fields 2-3 km off keep their colour, and the land 20 km out, where it is
	# last drawn, is all but haze.
	env.fog_density = HAZE_DENSITY
	env.fog_sun_scatter = 0.15
	env.fog_sky_affect = 0.25
	# AgX mutes colour, so bring saturation and contrast back up to photo levels.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0 if _gl else 1.08
	env.adjustment_contrast = 1.0 if _gl else 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun.rotation_degrees = Vector3(-SUN_ELEVATION, SUN_AZIMUTH, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.7 * _light
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.04
	# The browser's renderer (Compatibility) self-shadows flat ground at a
	# low sun: fine diagonal stripes over every lawn, roof and road ("shadow
	# acne"), which read as a grid of lines. A bigger normal offset clears
	# them; Forward+ doesn't need it.
	sun.shadow_normal_bias = 2.5 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 600.0
	add_child(sun)
	# Stars, faded in at night.
	sky_mat.sky_cover = _stars()
	sky_mat.sky_cover_modulate = Color(1, 1, 1, 0)
	# Lamps, lit windows and headlights bloom a little; daylight never does.
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.2
	env.glow_intensity = 0.0
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_day = {"top": sky_mat.sky_top_color, "horizon": sky_mat.sky_horizon_color,
		"ambient": env.ambient_light_energy, "ambient_color": env.ambient_light_color,
		"sun_color": sun.light_color, "sun_energy": sun.light_energy, "rot": sun.rotation_degrees}
	if GraphicsQuality.current:
		GraphicsQuality.current.changed.connect(_apply_quality)
		_apply_quality()


## The desktop app's quality tier (see Quality). Ambient occlusion darkens
## the creases real photos show: under eaves, where walls meet the ground,
## between houses close together. The browser build keeps the look above.
func _apply_quality() -> void:
	var q := GraphicsQuality.current
	if q == null or not q.active:
		return
	var t := q.settings()
	shadow_reach = t.shadow_reach
	sun.directional_shadow_max_distance = minf(sun.directional_shadow_max_distance, shadow_reach)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if t.splits == 4 \
		else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if q.browser:
		return  # the effects below need Forward+
	env.ssao_enabled = t.ssao
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.6
	env.ssao_power = 1.5
	env.ssao_light_affect = 0.1
	env.ssil_enabled = t.ssil
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.6
	# Sky and clouds mirrored in ponds, the river and wet pavement.
	env.ssr_enabled = t.ssr
	env.ssr_max_steps = 48
	env.ssr_fade_out = 2.0
	# Sunlight bouncing off lawns, walls and streets into the shade, the
	# way a real street's shadows are never black (Cinematic only).
	env.sdfgi_enabled = t.sdfgi
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 6
	env.sdfgi_min_cell_size = 0.4
	env.sdfgi_energy = 0.8
	# Light you can see in the air: low sun through haze, shafts between
	# buildings. Thin, so the aerial perspective above still does the
	# distance (Cinematic only). Clear Midwestern air sees 20-40 km, about
	# 0.0001-0.0002 extinction per metre, and the depth fog already gives
	# that; 0.0012 laid a 30% grey veil over a town seen from 300 m and made
	# Cinematic duller than Ultra.
	env.volumetric_fog_enabled = t.fog
	env.volumetric_fog_density = 0.0003
	env.volumetric_fog_albedo = HAZE
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 600.0
	env.volumetric_fog_sky_affect = 0.0


## Back to the fixed late-morning look (day/night cycle off).
func set_fixed() -> void:
	darkness = 0.0
	sky_mat.sky_top_color = _day.top
	sky_mat.sky_horizon_color = _day.horizon
	sky_mat.ground_horizon_color = _day.horizon
	sky_mat.ground_bottom_color = _day.horizon
	sky_mat.sky_cover_modulate = Color(1, 1, 1, 0)
	sky_mat.sky_energy_multiplier = 1.0
	env.fog_light_color = _day.horizon
	env.ambient_light_energy = _day.ambient
	env.ambient_light_color = _day.ambient_color
	env.ambient_light_sky_contribution = _sky_share
	env.glow_intensity = 0.0
	sun.light_color = _day.sun_color
	sun.light_energy = _day.sun_energy
	sun.rotation_degrees = _day.rot


## Where the sun is, in degrees: x its height above the horizon, y its
## compass bearing (0 north, 90 east). `hour` is local clock time and `months`
## comes from Seasons.months().
static func sun_position(hour: float, months: float) -> Vector2:
	var m := fposmod(months, 12.0)
	var decl := deg_to_rad(23.44) * sin(TAU * (m * 30.44 - 80.0) / 365.0)
	# Pike County is on Eastern time but west of its meridian, so the sun is
	# highest at about 12:50, or 1:50 in summer on daylight saving time.
	var noon := 13.8 if m > 2.4 and m < 10.2 else 12.8
	var h := deg_to_rad((hour - noon) * 15.0)
	var lat := deg_to_rad(Seasons.LATITUDE)
	var elev := asin(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(h))
	var az := atan2(sin(h), cos(h) * sin(lat) - tan(decl) * cos(lat)) + PI
	return Vector2(rad_to_deg(elev), rad_to_deg(az))


## Light the town for a time of day (hours, 0 to 24) and time of year.
func set_time(hour: float, months: float) -> void:
	var pos := sun_position(hour, months)
	var elev := pos.x
	# Daylight fades out through civil twilight (sun 6 degrees below).
	var day := smoothstep(-8.0, 5.0, elev)
	var low := 1.0 - smoothstep(0.0, 22.0, absf(elev))  # sun near the horizon
	darkness = 1.0 - smoothstep(-7.0, 3.0, elev)
	var dusk := low * (1.0 - smoothstep(-1.0, 6.0, -elev))
	var top: Color = NIGHT_TOP.lerp(_day.top, day).lerp(DUSK_TOP, dusk * 0.5)
	var horizon: Color = NIGHT_HORIZON.lerp(_day.horizon, day).lerp(DUSK_HORIZON, dusk * 0.75)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = horizon
	sky_mat.sky_cover_modulate = Color(1, 1, 1, smoothstep(0.5, 1.0, darkness) * 0.9)
	# The air itself only takes a little of the sunset colour; the land
	# under a dusk sky is lit by the blue of the open sky.
	env.fog_light_color = NIGHT_HORIZON.lerp(_day.horizon, day).lerp(Color(0.62, 0.5, 0.5), dusk * 0.35)
	env.ambient_light_color = Color(0.32, 0.42, 0.72).lerp(_day.ambient_color, day)
	env.ambient_light_energy = lerpf(0.6 * _light, _day.ambient, day)
	env.glow_intensity = 0.9 * darkness
	if elev > -2.0:
		# The sun, warming to orange as it gets low.
		var dir := _toward(pos)
		sun.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
		sun.light_color = Color(1.0, 0.52, 0.28).lerp(_day.sun_color, smoothstep(2.0, 28.0, elev))
		sun.light_energy = _day.sun_energy * smoothstep(-2.0, 5.0, elev)
	else:
		# Moonlight: a full moon riding opposite the sun, at least 25 degrees up.
		var moon := Vector2(maxf(-elev, 25.0), fposmod(pos.y + 180.0, 360.0))
		var dir := _toward(moon)
		sun.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP)
		sun.light_color = MOON_COLOR
		sun.light_energy = 0.7 * _light * smoothstep(-2.0, -10.0, elev)


## A unit vector toward a point in the sky (height, bearing). North is -Z
## and east is +X.
static func _toward(p: Vector2) -> Vector3:
	var e := deg_to_rad(p.x)
	var a := deg_to_rad(p.y)
	return Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e))


## A star field for the sky dome (equirectangular), brighter stars rarer.
static func _stars() -> ImageTexture:
	var w := 2048
	var h := 1024
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 2600:
		# Only the upper half is sky; spread evenly over the dome.
		var y := int(acos(rng.randf()) / PI * h)
		var x := rng.randi_range(0, w - 1)
		var b := pow(rng.randf(), 3.0) * 0.85 + 0.15
		var tint := Color(0.85, 0.9, 1.0).lerp(Color(1.0, 0.9, 0.78), rng.randf())
		img.set_pixel(x, clampi(y, 0, h - 1), Color(tint.r, tint.g, tint.b, b))
	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> void:
	# Fit the shadow range to what the camera is looking at, so shadows stay
	# sharp up close and still reach the whole view when zoomed out.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_fit_haze(cam)
	var dir := -cam.global_basis.z
	var reach := 600.0
	if dir.y < -0.05:
		reach = cam.global_position.y / -dir.y
	# Change the range only in big steps: a shadow map that resizes every
	# frame makes every shadow edge crawl while the camera moves.
	var want := clampf(reach * 2.0, 120.0, shadow_reach)
	var cur := sun.directional_shadow_max_distance
	if want > cur or want < cur * 0.55:
		sun.directional_shadow_max_distance = minf(120.0 * pow(1.5, ceilf(log(want / 120.0) / log(1.5))), shadow_reach)


## Haze is thickest near the ground: most of it lies in the lowest few
## hundred metres of air, so looking down from a plane the land below is
## clear while the horizon still fades. Depth fog only knows distance, so
## the camera's height thins it by the share of the haze layer (scale
## height HAZE_LAYER) its sight lines pass through: the same at street level,
## about half from 1 km up, about a third from 1.5 km (Brawn: zoomed-out
## views were washed out, 2026-10-24).
func _fit_haze(cam: Camera3D) -> void:
	var h := maxf(cam.global_position.y - Terrain.ground_y(cam.global_position.x, cam.global_position.z), 1.0)
	var share := HAZE_LAYER / h * (1.0 - exp(-h / HAZE_LAYER))
	env.fog_density = HAZE_DENSITY * share
