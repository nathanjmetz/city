class_name MarionWeather
extends Node
## Marion's real weather for the home screen (Nathan, 2026-10-25: "instead
## of just time and day and season you include the weather"): the latest
## report from Marion Municipal Airport (KMZZ) on the National Weather
## Service's free public API, read when the home screen opens and every 20
## minutes after. Only that fixed station is asked about; nothing about the
## player is sent. Offline, or with a report older than three hours, the
## home screen keeps the game's own odds (Weather.conditions). Never in play,
## never without a screen, and not when a time is forced for a picture.

const URL := "https://api.weather.gov/stations/KMZZ/observations/latest"
const EVERY := 20 * 60.0
const STALE := 3 * 3600.0
## Sky cover by the report's cloud layer codes (METAR).
const COVER := {"SKC": 0.0, "CLR": 0.0, "FEW": 0.2, "SCT": 0.45, "BKN": 0.75, "OVC": 1.0, "VV": 1.0}

var weather: Weather
var _http: HTTPRequest
var _wait := 0.0


func setup(w: Weather) -> void:
	weather = w


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(_on_report)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0 or not Weather.on or _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_wait = EVERY
	_http.request(URL, ["Accept: application/geo+json"])


func _on_report(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or weather == null:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not d is Dictionary or not d.has("properties"):
		return
	var live := read(d.properties, Time.get_unix_time_from_system())
	if not live.is_empty():
		weather.live = live


## [cover 0-1, rain 0-1] from a report's properties, or [] when it's too old
## or unreadable. Rain counts drizzle and showers; thunderstorms pour.
static func read(p: Dictionary, now: float) -> Array:
	var at := Time.get_unix_time_from_datetime_string(str(p.get("timestamp", "")).left(19))
	if at <= 0 or now - at > STALE:
		return []
	var cover := 0.0
	for layer in p.get("cloudLayers", []):
		if layer is Dictionary:
			cover = maxf(cover, float(COVER.get(str(layer.get("amount", "")), 0.0)))
	var rain := 0.0
	for w in p.get("presentWeather", []):
		if not w is Dictionary:
			continue
		var kind := str(w.get("weather", ""))
		var k := 0.0
		if kind in ["rain", "showers", "rain_showers", "freezing_rain"]:
			k = 0.6
		elif kind in ["drizzle", "freezing_drizzle"]:
			k = 0.3
		elif kind in ["thunderstorms", "thunderstorm"]:
			k = 0.9
		var intensity := str(w.get("intensity", ""))
		if k > 0.0 and intensity == "light":
			k *= 0.6
		elif k > 0.0 and intensity == "heavy":
			k = minf(k * 1.5, 1.0)
		rain = maxf(rain, k)
	if rain > 0.0:
		cover = maxf(cover, 0.9)
	return [cover, rain]
