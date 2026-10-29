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
## its real path over Grant County for the date and clock time (SunPath:
## NOAA's formulas, daylight saving included): 73 degrees up at 1:45 pm in
## late June, 26 at 12:41 pm in late December, setting near 9:17 pm and
## 5:19 pm. Its colour, strength, the sky and the haze follow its height
## (Daylight): golden low down, white at midday, blue hour, then moonlight
## and stars. The haze follows the year either way: humid and white in
## summer, crisp and blue in winter. See docs/daylight.md.

## Sun height above the horizon and compass direction, in degrees.
const SUN_ELEVATION := 40.0
const SUN_AZIMUTH := -38.0
const HAZE := Color(0.74, 0.79, 0.84)
## The tuned strengths at that sun (Daylight scales them for other heights).
const SUN_ENERGY := 1.7
const SHADE_ENERGY := 0.62

const MOON_COLOR := Color(0.62, 0.72, 0.95)

var sun := DirectionalLight3D.new()
var env := Environment.new()
var sky_mat := ProceduralSkyMaterial.new()
## The desktop app's sky with clouds (CloudSky); null in the browser, which
## draws sky_mat. sky_mat still holds the colours either way.
var clouds: ShaderMaterial
## Their shadows on the land (CloudSky.make_shadow), with them.
var cloud_shadows: MeshInstance3D
var _sky: Sky
var _moving := false
## 0 in full daylight, 1 at full night. DayNight reads it.
var darkness := 0.0
var _day := {}  # the fixed late-morning look, to go back to
## How thick the haze is for the time of year (Daylight.at().haze).
var haze_scale := 1.0
## Fog from the weather on top of the day's haze (Weather): 1 is none.
var weather_haze := 1.0
var _humid := -1.0  # the humidity the fixed look's haze was last set for
var _fixed := true  # showing the fixed look (day/night off)
var _season_months := 6.5  # the time of year set_season last saw
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
## The desktop's skylight. Open ground in a building's shadow on a clear
## day gets about a quarter to a third of the light of ground in sun (sky
## 15-25 klux against 60-80 klux of direct sun at 40 degrees up), and in
## photos a lawn in shade is a darker green, never black. The desktop's
## deeper blue sky (CloudSky) gives less skylight than the old pale one,
## and lawns in shadow came out near black up close; this brings the
## shade back to the measured share (Forward+ only).
var _shade_k := 1.0 if _gl else 2.1


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
	_sky = sky

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Skylight fills the shadows; a little less than the sun so shadows read.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Part sky, part neutral bounce light from lawns and pavement, so shade
	# reads blue-grey like in photos rather than saturated blue.
	env.ambient_light_sky_contribution = _sky_share
	env.ambient_light_color = Color(0.66, 0.66, 0.64)
	env.ambient_light_energy = SHADE_ENERGY * _light * _shade_k
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
	sun.light_energy = SUN_ENERGY * _light
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.04
	# The browser's renderer (Compatibility) self-shadows flat ground at a
	# low sun: fine diagonal stripes over every lawn, roof and road ("shadow
	# acne"), which read as a grid of lines. A bigger normal offset clears
	# them. Forward+ shows the same stripes at the default 1.2 on the
	# desktop app, so it gets a big offset too.
	sun.shadow_normal_bias = 2.5 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 3.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 600.0
	add_child(sun)
	# Stars, faded in at night.
	sky_mat.sky_cover = _stars()
	sky_mat.sky_cover_modulate = Color(1, 1, 1, 0)
	if not _gl:
		_use_clouds(false)
		# The desktop sky does its own haze toward the horizon; fog laid
		# over the whole dome greyed the blue overhead to slate (a quarter
		# of the haze colour at every height); about half that keeps a hazy
		# summer sky pale but blue.
		env.fog_sky_affect = 0.14
		# AgX's default curve left the town under a grey veil from the
		# heights it's played at: woods olive-grey, lawns khaki, shade
		# lifted. Aerial photos of a Grant County town in July have dark
		# tree crowns, saturated green lawns and crisp roofs; a steeper
		# curve gets there (Forward+ only). Steeper than 1.3 crushes the
		# shade on lawns to black.
		env.tonemap_agx_contrast = 1.3
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
	if clouds != null and (q.tier >= GraphicsQuality.HIGH) != _moving:
		_use_clouds(q.tier >= GraphicsQuality.HIGH)
	# Low's coarse 2-split map stripes lawns even at 3.0; it needs more.
	sun.shadow_normal_bias = 4.5 if t.splits == 2 else 3.0
	# The real sun is a disc half a degree across, so a car's shadow is
	# crisp (a penumbra of a centimetre or two from a 1.5 m roof). Godot's
	# own sun-size shadows (light_angular_distance) came out stair-stepped,
	# a shadow-map texel per step, along car roofs and the ground under
	# them (vehicles loop, 2026-10-29), so they stay off. Instead Ultra and
	# up, with their 8192 shadow map, blur less than the rest: a crisper
	# edge with no steps (0.6 still showed them).
	sun.light_angular_distance = 0.0
	sun.shadow_blur = 0.8 if q.tier >= GraphicsQuality.ULTRA else 1.2
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
	# way a real street's shadows are never black. No tier turns it on now
	# (see GraphicsQuality.TIERS): its sky light made shade cobalt.
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
	_sky_colors(_day.top, _day.horizon, 0.0)
	env.fog_light_color = _day.horizon
	env.ambient_light_energy = _day.ambient
	env.ambient_light_color = _day.ambient_color
	env.ambient_light_sky_contribution = _sky_share
	env.glow_intensity = 0.0
	env.tonemap_exposure = 1.0
	sun.light_color = _day.sun_color
	sun.light_energy = _day.sun_energy
	sun.rotation_degrees = _day.rot
	_fixed = true
	_humid = -1.0
	set_season(_season_months)


## The haze for the time of year (months from January), day/night on or
## off: thicker and whiter in a humid summer, thinner and bluer in winter.
## With day/night off this also tints the fixed look's horizon; set_time
## does its own.
func set_season(months: float) -> void:
	_season_months = months
	var humid := Daylight.humidity(months)
	haze_scale = lerpf(Daylight.HAZE_THIN, Daylight.HAZE_THICK, humid)
	if _fixed and absf(humid - _humid) > 0.01:
		_humid = humid
		var horizon: Color = Daylight.at(SUN_ELEVATION, humid).horizon
		_sky_colors(_day.top, horizon, 0.0)
		env.fog_light_color = horizon


## Where the sun is, in degrees: x its height above the horizon, y its
## compass bearing (0 north, 90 east). `hour` is local clock time and `months`
## comes from Seasons.months() (see SunPath.position_game).
static func sun_position(hour: float, months: float) -> Vector2:
	return SunPath.position_game(months, hour)


## Light the town for a time of day (hours, 0 to 24) and time of year.
func set_time(hour: float, months: float) -> void:
	var pos := sun_position(hour, months)
	var elev := pos.x
	var l := Daylight.at(elev, Daylight.humidity(months))
	_fixed = false
	darkness = l.darkness
	_sky_colors(l.zenith, l.horizon, l.stars)
	env.fog_light_color = l.fog_color
	haze_scale = l.haze
	env.ambient_light_color = l.shade_color
	# Moonlit shade keeps its own tuned strength.
	env.ambient_light_energy = SHADE_ENERGY * _light * lerpf(_shade_k, 1.0, darkness) * l.shade_energy
	env.glow_intensity = 0.9 * darkness
	env.tonemap_exposure = l.exposure
	if elev > -2.0:
		# The sun: warm and dim low down, white at midday (Daylight).
		var dir := SunPath.toward(pos)
		sun.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
		sun.light_color = l.sun_color
		sun.light_energy = SUN_ENERGY * _light * l.sun_energy
	else:
		# Moonlight: a full moon riding opposite the sun, at least 25 degrees up.
		var moon := Vector2(maxf(-elev, 25.0), fposmod(pos.y + 180.0, 360.0))
		var dir := SunPath.toward(moon)
		sun.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP)
		sun.light_color = MOON_COLOR
		sun.light_energy = 0.7 * _light * smoothstep(-2.0, -10.0, elev)


## Sky colours and stars, sent on only when they change enough to see: each
## change re-renders the sky's lighting, and at midday the sky barely moves.
func _sky_colors(top: Color, horizon: Color, stars: float) -> void:
	if _near(top, sky_mat.sky_top_color) and _near(horizon, sky_mat.sky_horizon_color) \
			and absf(stars - sky_mat.sky_cover_modulate.a) < 0.004:
		return
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = horizon
	sky_mat.sky_cover_modulate = Color(1, 1, 1, stars)
	_clouds_colors()


## Puts up the desktop sky (CloudSky), its clouds drifting or still.
func _use_clouds(moving: bool) -> void:
	var cov := 0.15
	var off := Vector2.ZERO
	if clouds != null:
		cov = clouds.get_shader_parameter("cover")
		off = clouds.get_shader_parameter("drift")
	_moving = moving
	clouds = CloudSky.make(moving)
	clouds.set_shader_parameter("stars", sky_mat.sky_cover)
	clouds.set_shader_parameter("cover", cov)
	clouds.set_shader_parameter("drift", off)
	_clouds_colors()
	_sky.sky_material = clouds
	if cloud_shadows != null:
		cloud_shadows.queue_free()
	cloud_shadows = CloudSky.make_shadow(moving)
	add_child(cloud_shadows)
	_shadow_param("cover", cov)
	_shadow_param("drift", off)


func _clouds_colors() -> void:
	if clouds == null:
		return
	clouds.set_shader_parameter("top_color", sky_mat.sky_top_color)
	clouds.set_shader_parameter("horizon_color", sky_mat.sky_horizon_color)
	clouds.set_shader_parameter("curve", sky_mat.sky_curve)
	clouds.set_shader_parameter("stars_alpha", sky_mat.sky_cover_modulate.a)


## How much of the sky is cloud, 0 to 1 (Weather sets it). Only the desktop
## sky draws clouds; sent on only when it changes enough to see.
func set_cover(c: float) -> void:
	if clouds == null:
		return
	if absf(float(clouds.get_shader_parameter("cover")) - c) > 0.004:
		clouds.set_shader_parameter("cover", c)
		_shadow_param("cover", c)


func _shadow_param(key: String, v: Variant) -> void:
	if cloud_shadows != null:
		(cloud_shadows.material_override as ShaderMaterial).set_shader_parameter(key, v)


static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.002 and absf(a.g - b.g) < 0.002 and absf(a.b - b.b) < 0.002


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
	env.fog_density = HAZE_DENSITY * share * haze_scale * weather_haze
	if cloud_shadows != null:
		_shadow_param("fog_density", env.fog_density)
		# Toward the sun (a directional light shines down its -Z); the moon
		# casts no cloud shadows worth drawing.
		_shadow_param("to_sun", sun.global_basis.z if darkness < 0.5 else Vector3.DOWN)
