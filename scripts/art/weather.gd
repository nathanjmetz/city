class_name Weather
extends Node3D
## Grant County weather on the town (Nathan, 2026-10-25: match the real feel
## of the place, with "a simple toggle switch" to turn it off). Drawn only:
## the town's thinking never sees it. Each game day gets its own sky from
## the date (the same for everyone, every time), by Indiana's odds for the
## month: overcast or fair, and some days a few hours of rain. Overcast dims
## and greys the picture and softens shadows; rain streaks over it. Off:
## always fair.

## Share of days with rain, January to December (Indianapolis has 10-13
## days of measurable precipitation a month; winter's falls as snow, which
## the seasons already show).
const RAIN_DAYS := [0.0, 0.0, 0.3, 0.4, 0.42, 0.38, 0.33, 0.3, 0.27, 0.28, 0.3, 0.0]
const OVERCAST_DAYS := 0.3
## Faint streaks over the picture, three depths of them, nearer ones longer
## and faster. Drawn flat over the screen like most city builders do: from
## high up, real drops would be thinner than a pixel.
const RAIN_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float streaks(vec2 uv, float cells, float speed) {
	vec2 p = uv * vec2(cells, cells * 0.25);
	p.x += p.y * 0.3;
	p.y -= TIME * speed;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	if (hash(cell) > amount) {
		return 0.0;
	}
	float x = 0.15 + 0.7 * hash(cell + 7.1);
	float len = 0.45 + 0.4 * hash(cell + 3.3);
	float y0 = hash(cell + 1.7) * (1.0 - len);
	float line = 1.0 - smoothstep(0.0, 0.07, abs(f.x - x));
	float along = step(y0, f.y) * step(f.y, y0 + len);
	return line * along * (f.y - y0) / len;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float a = 0.5 * streaks(uv, 60.0, 20.0) + 0.6 * streaks(uv + 0.37, 38.0, 16.0)
		+ 0.7 * streaks(uv + 0.71, 24.0, 12.0);
	COLOR = vec4(0.82, 0.86, 0.92, a * 0.4);
}
"""

static var on := true

var sim: CitySim
var sky: SkyLight
## Now: how much of the sky is cloud (0-1), and how hard it rains (0-1).
var cover := 0.0
var rain := 0.0
## Real conditions to show instead of the odds, [cover, rain] (the home
## screen's Marion report, MarionWeather), or [] for the odds.
var live := []
var _rain: ColorRect
## The sky's colour settings before any cloud.
var _base := []
var _rain_mat: ShaderMaterial


func setup(s: CitySim, light: SkyLight) -> void:
	sim = s
	sky = light


func _ready() -> void:
	# Under the game's menus and panels, over the town.
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	var sh := Shader.new()
	sh.code = RAIN_SHADER
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = sh
	_rain = ColorRect.new()
	_rain.material = _rain_mat
	_rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rain.visible = false
	layer.add_child(_rain)


## The sky at a clock time (CitySim.clock(): year, month, day, hour,
## minute): [cover 0-1, rain 0-1]. Keyed to the date shown, so the home
## screen's real Marion clock and the game's own both work.
static func conditions(clock: Dictionary) -> Array:
	var month := int(clock.month)
	var hour := float(clock.hour) + float(clock.get("minute", 0.0)) / 60.0
	var h := hash([int(clock.year), month, int(clock.day), "weather"])
	var roll := float(h % 1000) / 1000.0
	var rain_share: float = RAIN_DAYS[month - 1]
	if roll < rain_share:
		# A rainy day: overcast, with three to seven hours of rain.
		var start := 4.0 + float((h >> 10) % 14)
		var length := 3.0 + float((h >> 14) % 5)
		var raining := hour >= start and hour < start + length
		var edge := clampf(minf(hour - start, start + length - hour), 0.0, 1.0)
		return [0.95, (0.45 + float((h >> 18) % 50) / 100.0) * edge if raining else 0.0]
	if roll < rain_share + OVERCAST_DAYS * (1.0 - rain_share):
		return [0.7, 0.0]
	return [float((h >> 6) % 30) / 100.0, 0.0]


func _process(_delta: float) -> void:
	if sim == null or sky == null:
		return
	var c := [0.0, 0.0]
	if on:
		c = live if not live.is_empty() else conditions(sim.clock())
	cover = lerpf(cover, float(c[0]), 0.02)
	rain = lerpf(rain, float(c[1]), 0.03)
	# Overcast: a flatter, greyer, dimmer picture.
	# On top of the sky's own colour settings, never in place of them.
	var env := sky.env
	if _base.is_empty():
		_base = [env.adjustment_enabled, env.adjustment_brightness, env.adjustment_saturation, env.adjustment_contrast]
	env.adjustment_enabled = bool(_base[0]) or cover > 0.02
	env.adjustment_brightness = float(_base[1]) * (1.0 - 0.22 * cover)
	env.adjustment_saturation = float(_base[2]) * (1.0 - 0.35 * cover)
	env.adjustment_contrast = float(_base[3]) * (1.0 - 0.12 * cover)
	# Cloud spreads the sun: shadows go soft and faint.
	sky.sun.shadow_opacity = 1.0 - 0.7 * cover
	_rain.visible = rain > 0.05
	if _rain.visible:
		_rain_mat.set_shader_parameter("amount", clampf(rain, 0.0, 1.0) * 0.55)
