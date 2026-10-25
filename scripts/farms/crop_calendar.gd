class_name CropCalendar
extends RefCounted
## The crop calendar: what a corn, soybean, wheat, hay or pasture field in
## east-central Indiana looks like on any day of the year, worked out from a
## few small facts and the date (Brawn 2026-10-25, real-life details #1).
##
## A field's facts are its crop this year, last year's and (when known) next
## year's, the farm's habits (tillage, cover crop) and a timing seed: how
## early in the county's planting and harvest this farmer gets to it. From
## those and real rules (Indiana planting and harvest progress, corn heat
## units from Marion's normal temperatures, soybean maturity dates, how
## residue and tilled soil look) come the planting date, emergence, height,
## how far the canopy has closed, browning, harvest, stubble and fall
## tillage. Nothing here is saved: it is all grown again from the facts, so
## every player in a region sees the same field on the same day.
##
## Sources and the numbers used: docs/crop-calendar.md.
##
## The look of every kind of field for today goes in one small table
## (texture(), 128 x 128 texels, 64 KB) that the ground shader, the farm
## field shader and the close-up plants all read, so the date moving on
## costs one small upload, not a rebuilt mesh. Rows 0-15 are the county's
## fields (county_row), rows 16-127 the town's farms' fields (farm_row). Each row
## has COLS timing columns of TEXELS texels:
##   0: plant colour (sRGB) and how much of the ground the plants cover
##   1: ground colour (sRGB: soil, residue, stubble) and how strongly standing
##      stalk rows show in it
##   2: plant height / 4 m, greenness, row spacing (0 drilled, 0.5 15 in,
##      1 30 in), crop id / 8 (CROP_IDS)
##   3: growth (0 planted to 1 mature), leaves left, harvested, tallest / 4 m

const COLS := 32
const TEXELS := 4
const COUNTY_ROWS := 16
const ROWS := 128
const DAYS := 365.0
const ROW_M := 0.762  # 30 inch rows
const NARROW_M := 0.381  # 15 inch rows

## Farm habits for the corn and soybean ground (Indiana tillage transect:
## about 60% of soybeans and 35-40% of corn no-tilled; cover crops on about
## one acre in ten):
##   NO_TILL: never tilled, crops planted into last year's residue
##   CHISEL: corn stalks chisel-plowed in the fall, a field cultivator pass
##     before planting each spring (the conventional farm)
##   BEANS_NO_TILL: beans no-tilled into corn stalks, the bean stubble worked
##     with a field cultivator before corn
##   RYE: no-till with a cereal rye cover crop drilled after each harvest
enum { NO_TILL, CHISEL, BEANS_NO_TILL, RYE }
const PRACTICE_SHARE := [0.3, 0.7, 0.9, 1.0]  # cumulative: 30%, 40%, 20%, 10%

const CROP_IDS := {"": 0, "corn": 1, "soybeans": 2, "wheat": 3, "hay": 4, "pasture": 5, "rye": 6}

# --- Real numbers -----------------------------------------------------------

## Share of the crop planted by day of year (Jan 1 = 0), rounded from USDA
## NASS Indiana Crop Progress five-year averages.
const CORN_PLANT := [[105, 0.0], [118, 0.12], [125, 0.26], [132, 0.42], [139, 0.6], [146, 0.71], [153, 0.84],
	[160, 0.93], [171, 1.0]]
const SOY_PLANT := [[112, 0.0], [125, 0.09], [132, 0.22], [139, 0.38], [146, 0.6], [153, 0.75], [160, 0.86],
	[171, 0.96], [181, 1.0]]
## Share harvested by day of year (same source).
const CORN_HARVEST := [[255, 0.0], [272, 0.08], [279, 0.18], [286, 0.33], [295, 0.54], [302, 0.66], [309, 0.76],
	[316, 0.84], [323, 0.89], [337, 0.96], [349, 1.0]]
const SOY_HARVEST := [[258, 0.0], [265, 0.05], [272, 0.14], [279, 0.28], [286, 0.45], [295, 0.67], [302, 0.8],
	[309, 0.88], [323, 0.96], [335, 1.0]]

## Corn heat units (growing degree days, base 50 F, cap 86 F) from planting
## to each stage (Iowa State PMR 1009; Purdue/Nielsen; Ohio State AGF-0101)
## and the plant's height then, metres to the top of the leaves (tassel at
## VT), for a 2.7 m (about 9 ft) hybrid.
const CORN_HEIGHT := [[0, 0.0], [125, 0.04], [200, 0.1], [345, 0.22], [475, 0.42], [610, 0.72], [740, 1.08],
	[870, 1.5], [1000, 1.95], [1135, 2.32], [1350, 2.7]]
## Share of the ground the leaves cover from above in 30 inch rows: the rows
## close about V10-V12, late June.
const CORN_COVER := [[0, 0.0], [125, 0.01], [345, 0.06], [475, 0.16], [610, 0.36], [740, 0.62], [870, 0.86],
	[1000, 0.96], [1135, 1.0]]
const CORN_VT := 1350.0  # tassels
const CORN_R5 := 2300.0  # dent: lower leaves start to fire
const CORN_R6 := 2550.0  # black layer for a 105-110 day hybrid (Purdue picks for north-central Indiana)

## Soybean height (m) and cover by days after planting, to beginning
## flowering and on through pod fill, 30 inch rows, about 3 ft tall (Purdue
## soybean production, Iowa State soybean growth stages).
const SOY_HEIGHT := [[0, 0.0], [8, 0.03], [20, 0.1], [35, 0.22], [50, 0.38], [65, 0.6], [80, 0.8], [95, 0.92]]
const SOY_COVER_30 := [[0, 0.0], [8, 0.01], [20, 0.05], [35, 0.18], [50, 0.45], [65, 0.8], [75, 0.96], [85, 1.0]]
const SOY_COVER_15 := [[0, 0.0], [8, 0.02], [20, 0.1], [35, 0.36], [50, 0.75], [60, 0.96], [70, 1.0]]

# --- Colours (sRGB), matched to USDA NAIP aerials of Grant County and to
# photos of central Indiana fields -------------------------------------------

const SOIL_FRESH := Color(0.27, 0.22, 0.17)  # just-worked moist silt loam (Blount, Pewamo)
const SOIL_DRY := Color(0.45, 0.39, 0.30)  # the same surface a week or two later
const CORN_STALKS := Color(0.66, 0.59, 0.42)  # fresh corn residue, pale straw
const CORN_STALKS_OLD := Color(0.56, 0.52, 0.44)  # weathered grey-tan by spring
const BEAN_STUBBLE := Color(0.62, 0.53, 0.40)
const RESIDUE_ROTTED := Color(0.42, 0.38, 0.31)
const STRAW := Color(0.80, 0.70, 0.47)  # wheat stubble
const CORN_YOUNG := Color(0.38, 0.52, 0.22)
const CORN_GREEN := Color(0.20, 0.33, 0.12)  # dark blue-green from the air
const CORN_TASSEL := Color(0.60, 0.55, 0.33)
const CORN_FIRING := Color(0.44, 0.45, 0.22)
const CORN_DRY := Color(0.63, 0.55, 0.37)
const CORN_LATE := Color(0.58, 0.52, 0.38)
const SOY_YOUNG := Color(0.38, 0.52, 0.21)
const SOY_GREEN := Color(0.28, 0.43, 0.15)  # brighter, yellower than corn
const SOY_YELLOW := Color(0.75, 0.66, 0.24)
const SOY_BROWN := Color(0.47, 0.37, 0.26)
const RYE_GREEN := Color(0.30, 0.45, 0.18)
const RYE_DORMANT := Color(0.40, 0.42, 0.25)
const RYE_DEAD := Color(0.62, 0.56, 0.38)
const WHEAT_GREEN := Color(0.29, 0.45, 0.18)
const WHEAT_DORMANT := Color(0.38, 0.42, 0.24)
const WHEAT_GOLD := Color(0.80, 0.68, 0.34)
const HAY_GREEN := Color(0.27, 0.45, 0.18)
const HAY_DORMANT := Color(0.44, 0.43, 0.29)
const HAY_CUT := Color(0.56, 0.55, 0.33)
## Cool-season pasture by month, March to November (as FarmView had it).
const PASTURE := [Color(0.46, 0.48, 0.3), Color(0.34, 0.5, 0.22), Color(0.3, 0.5, 0.2), Color(0.32, 0.49, 0.2),
	Color(0.4, 0.48, 0.24), Color(0.5, 0.48, 0.28), Color(0.4, 0.49, 0.25), Color(0.38, 0.47, 0.24),
	Color(0.48, 0.46, 0.3)]
const PASTURE_WINTER := Color(0.52, 0.49, 0.34)

# --- Temperature: Marion, Indiana -------------------------------------------

static var _cum := PackedFloat32Array()


## Normal daily high and low (F) by month, Marion, Indiana (1991-2020
## normals: NOAA NCEI, and Indianapolis's a degree or two cooler): spring
## warms slower than fall cools, so a table, not a curve.
const NORMAL_HIGH := [33.0, 37.0, 48.0, 61.0, 72.0, 81.0, 84.0, 82.0, 77.0, 64.0, 50.0, 37.0]
const NORMAL_LOW := [18.0, 21.0, 29.0, 39.0, 50.0, 59.0, 63.0, 61.0, 54.0, 42.0, 33.0, 23.0]


## Normal daily high and low (F) on a day of the year, straight lines
## between mid-month values.
static func normal_temps(doy: float) -> Vector2:
	var m := fposmod(doy / DAYS * 12.0 - 0.5, 12.0)
	var i := int(m)
	var j := (i + 1) % 12
	var t := m - i
	return Vector2(lerpf(NORMAL_HIGH[i], NORMAL_HIGH[j], t), lerpf(NORMAL_LOW[i], NORMAL_LOW[j], t))


## Corn growing degree days on a normal day (base 50 F, cap 86 F).
static func gdd_on(doy: float) -> float:
	var t := normal_temps(doy)
	return (clampf(t.x, 50.0, 86.0) + clampf(t.y, 50.0, 86.0)) * 0.5 - 50.0


## Heat units from January 1 to a day of the year (fractional days
## interpolate). Days past the year go on into the next one.
static func gdd(doy: float) -> float:
	if _cum.is_empty():
		_cum.resize(368)
		var s := 0.0
		for d in 368:
			_cum[d] = s
			s += gdd_on(d + 0.5)
	var d := clampf(doy, 0.0, 366.99)
	var i := int(d)
	return lerpf(_cum[i], _cum[i + 1], d - i)


## The first day the heat units reach `g` (searches forward from `from`).
static func day_of_gdd(g: float, from := 0.0) -> float:
	gdd(0.0)
	var i := int(clampf(from, 0.0, 366.0))
	while i < 366 and _cum[i + 1] < g:
		i += 1
	if i >= 366:
		return 999.0
	var a := _cum[i]
	var b := _cum[i + 1]
	return i + (clampf((g - a) / maxf(b - a, 0.001), 0.0, 1.0))


# --- Small helpers ----------------------------------------------------------

## A whole-number hash, the same here and in the shaders (GLSL), so a field
## the ground paints as corn is the field the close-up plants grow corn in.
static func hash32(x: int, y: int, salt: int) -> int:
	var h := ((x + 65536) * 2376512323 + (y + 65536) * 3625334849 + salt * 3407524639) & 0xFFFFFFFF
	h ^= h >> 13
	h = (h * 1540483477) & 0xFFFFFFFF
	h ^= h >> 15
	return h


static func h01(x: int, y: int, salt: int) -> float:
	return float(hash32(x, y, salt) & 0xFFFFFF) / 16777216.0


## Value of a [[x, y], ...] table at x, straight lines between.
static func interp(table: Array, x: float) -> float:
	if x <= table[0][0]:
		return table[0][1]
	for i in range(1, table.size()):
		if x <= table[i][0]:
			var a: Array = table[i - 1]
			var b: Array = table[i]
			return lerpf(a[1], b[1], (x - a[0]) / float(b[0] - a[0]))
	return table[-1][1]


## Where a rising progress table reaches share q (the day that share of the
## county is done).
static func when(table: Array, q: float) -> float:
	if q <= table[0][1]:
		return table[0][0]
	for i in range(1, table.size()):
		if q <= table[i][1]:
			var a: Array = table[i - 1]
			var b: Array = table[i]
			return lerpf(a[0], b[0], (q - a[1]) / maxf(b[1] - a[1], 0.0001))
	return table[-1][0]


static func fract(x: float) -> float:
	return x - floorf(x)


static func _ramp(x: float, a: float, b: float) -> float:
	return clampf((x - a) / (b - a), 0.0, 1.0)


## The year's weather, from the year alone (the same for every player): one
## spring in four is wet and planting runs a week or two late; some summers
## run warm or cool. {delay: days, heat: x heat units}
static func year_weather(year: int) -> Dictionary:
	var w := h01(year, 7, 11)
	var delay := 5.0 + 10.0 * h01(year, 7, 12) if w < 0.25 else 2.0 * h01(year, 7, 13)
	return {"delay": delay, "heat": 0.97 + 0.06 * h01(year, 7, 14)}


## The day of the year (0 = January 1) for a point in the game's calendar
## (Seasons.months).
static func day_of_year(months: float) -> float:
	return fposmod(months, 12.0) * DAYS / 12.0


# --- One field's year -------------------------------------------------------

## A field's plan for a year: every date that matters, from its facts.
##   crop, prev, next: this year's, last year's and next year's crop ("" when
##     next year is not decided yet)
##   practice: NO_TILL, CHISEL, BEANS_NO_TILL or RYE
##   cover, cover_prev: rye after this year's / went in after last year's harvest
##   u: timing seed, 0 (among the first in the county) to 1 (the last)
##   year: for the year's weather
static func plan(crop: String, prev: String, next: String, practice: int, cover: bool, cover_prev: bool,
		u: float, year: int, narrow := false) -> Dictionary:
	var w := year_weather(year)
	var hq := clampf(0.55 * u + 0.45 * fract(u * 7.13 + 0.31), 0.0, 0.999)  # harvest order follows planting, loosely
	var v := fract(u * 3.71 + 0.17)  # the hybrid or variety
	var p := {"crop": crop, "prev": prev, "next": next, "practice": practice, "cover": cover,
		"cover_prev": cover_prev, "u": u, "plant": 999.0, "harvest": 999.0, "mature": 999.0,
		"till_spring": -999.0, "till_fall": -999.0, "rye_sow": -999.0, "rye_kill": -999.0,
		"heat": float(w.heat), "hmax": 0.0, "narrow": narrow, "double": false}
	# Was the ground tilled last fall? (corn stalks chiseled on a CHISEL farm)
	p.prev_fall_till = practice == CHISEL and prev == "corn"
	match crop:
		"corn":
			p.plant = minf(when(CORN_PLANT, u) + float(w.delay) * (1.0 - 0.6 * u), 176.0)
			p.hmax = 2.55 + 0.3 * v  # 8.4 to 9.4 ft
			# Late corn needs about 200 fewer heat units to black layer (Nielsen).
			p.r6 = CORN_R6 * (0.95 + 0.1 * v) - maxf(p.plant - 140.0, 0.0) * 6.0
			var g0: float = gdd(p.plant) * p.heat
			p.mature = day_of_gdd((g0 + p.r6) / p.heat, p.plant)
			# The first hard freeze (mid to late October in Grant County) ends it.
			p.mature = minf(p.mature, 292.0 + 8.0 * h01(year, 9, 3))
			# Field drying from about 32% moisture at black layer to the
			# farmer's harvest moisture (18-25%): about 0.8 points a day in
			# September, 0.5 in October, 0.25 in November.
			var wet := 32.0
			var goal := 18.0 + 7.0 * fract(u * 5.9 + 0.4)
			var d: float = p.mature
			while wet > goal and d < 345.0:
				wet -= 0.8 if d < 273.0 else (0.5 if d < 304.0 else 0.25)
				d += 1.0
			p.harvest = minf(maxf(d, when(CORN_HARVEST, hq)), 350.0)
			if practice == CHISEL and next != "corn" and p.harvest < 330.0:
				p.till_fall = p.harvest + 3.0 + 14.0 * fract(u * 5.3)
			if practice in [CHISEL, BEANS_NO_TILL] and not cover_prev:
				p.till_spring = p.plant - 0.5 - 3.0 * fract(u * 9.1)
			if cover_prev:
				p.rye_kill = p.plant - 14.0  # sprayed two weeks ahead of corn
		"soybeans":
			p.plant = minf(when(SOY_PLANT, u) + float(w.delay) * (1.0 - 0.6 * u), 182.0)
			p.hmax = 0.85 + 0.2 * v
			# Maturity group 3: leaves yellow in mid September, a little
			# later for later planting (about a day for every three).
			p.r7 = 256.0 + 0.35 * (p.plant - 135.0) + 10.0 * (v - 0.4)
			p.mature = p.r7 + 12.0  # R8: 95% of pods at mature colour
			p.harvest = minf(maxf(p.mature + 5.0, when(SOY_HARVEST, hq)), 340.0)
			if practice == CHISEL and not cover_prev:
				p.till_spring = p.plant - 0.5 - 3.0 * fract(u * 9.1)
			if cover_prev:
				p.rye_kill = p.plant + 3.0  # planted green into the rye, sprayed after
		"wheat":
			# Soft red winter wheat, drilled in October after the beans: green
			# up in March, heads in late May, gold by mid June, cut around
			# July 1 (Purdue wheat calendar).
			p.plant = 278.0 + 14.0 * u - DAYS  # last fall
			p.hmax = 0.9
			p.heading = 140.0 + 6.0 * v
			p.mature = 168.0 + 6.0 * v
			p.harvest = 176.0 + 12.0 * hq
			# A no-till farm follows with double-crop soybeans; the rest bale
			# the straw and leave the stubble.
			p.double = practice in [NO_TILL, RYE] or fract(u * 11.3) < 0.3
			if p.double:
				p.dc_plant = p.harvest + 2.0 + 3.0 * fract(u * 4.7)
				p.dc_r7 = 280.0 + 6.0 * v
				p.dc_harvest = minf(p.dc_r7 + 20.0 + 10.0 * hq, 330.0)
		"hay":
			p.hmax = 0.7
			p.cuts = [145.0 + 6.0 * u, 180.0 + 6.0 * u, 216.0 + 6.0 * u, 252.0 + 6.0 * u]
		"pasture":
			p.hmax = 0.15
	if crop in ["corn", "soybeans"]:
		if cover:
			p.rye_sow = p.harvest + 2.0 + 4.0 * fract(u * 6.1)
		elif next == "wheat":
			p.rye_sow = maxf(p.harvest + 2.0, 278.0 + 14.0 * u)  # wheat goes in instead
			p.wheat_next = true
	return p


## How the field looks on day `d` of the plan's year: {plant: Color, cover,
## ground: Color, rows (stalk rows in the ground), height (m), green,
## spacing (0, 0.5 or 1), crop (what stands there now), growth, leaves,
## harvested, stage (a word for tests and Inspect)}.
static func state(p: Dictionary, d: float) -> Dictionary:
	var s := {"plant": SOY_GREEN, "cover": 0.0, "ground": SOIL_DRY, "rows": 0.0, "height": 0.0, "green": 0.0,
		"spacing": 0.0, "crop": "", "growth": 0.0, "leaves": 0.0, "harvested": 0.0, "stage": "bare",
		"hmax": float(p.hmax)}
	_ground(p, d, s)
	match str(p.crop):
		"corn": _corn(p, d, s)
		"soybeans": _soy(p, d, s)
		"wheat": _wheat(p, d, s)
		"hay": _hay(p, d, s)
		"pasture": _pasture(d, s)
	return s


## The soil and residue under the crop, by what has happened to the ground
## since last harvest.
static func _ground(p: Dictionary, d: float, s: Dictionary) -> void:
	var crop := str(p.crop)
	if crop in ["hay", "pasture"]:
		s.ground = Color(0.42, 0.40, 0.30)
		return
	# Residue on the surface: [colour, cover, standing stalk rows, made on day].
	var res := _residue(str(p.prev), bool(p.prev_fall_till), -60.0)
	var tilled := -999.0
	if bool(p.prev_fall_till):
		tilled = -45.0
	if d >= float(p.till_spring) and float(p.till_spring) > -999.0:
		tilled = float(p.till_spring)
		res[1] *= 0.35
		res[2] = 0.0
	if d >= float(p.harvest):
		var cut: String = crop if crop != "wheat" else "wheat"
		res = _residue(cut, false, float(p.harvest))
		if crop == "wheat" and bool(p.double) and d >= float(p.dc_harvest):
			res = _residue("soybeans", false, float(p.dc_harvest))
	if d >= float(p.till_fall) and float(p.till_fall) > -999.0:
		tilled = float(p.till_fall)
		res[1] *= 0.45
		res[2] = 0.0
	# Worked soil is dark and moist, drying lighter over the next two weeks.
	var fresh := 1.0 - _ramp(d - tilled, 0.0, 14.0) if tilled > -999.0 else 0.0
	var soil := SOIL_DRY.lerp(SOIL_FRESH, fresh * 0.9)
	# Residue weathers from pale straw to grey-tan over the winter.
	var age := d - float(res[3])
	var rc: Color = res[0]
	if res[0] == CORN_STALKS:
		rc = CORN_STALKS.lerp(CORN_STALKS_OLD, _ramp(age, 20.0, 160.0))
	# Over the summer the residue rots down and darkens into the soil
	# (about a third of corn residue is gone by midsummer).
	rc = rc.lerp(RESIDUE_ROTTED, _ramp(age, 150.0, 330.0))
	res[1] *= 1.0 - 0.4 * _ramp(age, 120.0, 330.0)
	s.ground = soil.lerp(rc, float(res[1]))
	s.rows = float(res[2]) * (1.0 - 0.5 * _ramp(age, 30.0, 180.0))
	s.residue = res[1]


## [colour, share of the ground covered, stalk rows, day made] that a crop
## leaves at harvest (Purdue residue estimates: corn 80-90% no-till, beans
## 30-40%; a chisel pass leaves about half).
static func _residue(crop: String, chiseled: bool, day: float) -> Array:
	match crop:
		"corn":
			return [CORN_STALKS, 0.4 if chiseled else 0.85, 0.0 if chiseled else 0.7, day]
		"soybeans":
			return [BEAN_STUBBLE, 0.35, 0.25, day]
		"wheat":
			return [STRAW, 0.85, 0.0, day]
		"hay", "pasture":
			return [HAY_DORMANT, 0.9, 0.0, day]
	return [BEAN_STUBBLE, 0.2, 0.0, day]


## Cereal rye cover on the ground: drilled after harvest, up in a week, a
## low green mat by December, dormant over winter, greening and growing in
## March and April until it's sprayed before planting.
static func _rye(p: Dictionary, d: float, s: Dictionary) -> bool:
	var sow := float(p.rye_sow)
	var kill := float(p.rye_kill)
	var growing := false
	var c := 0.0
	var h := 0.0
	var col := RYE_GREEN
	if sow > -999.0 and d >= sow + 7.0:  # this fall's rye (or wheat)
		growing = true
		c = 0.08 + 0.27 * _ramp(d - sow, 7.0, 45.0)
		h = 0.04 + 0.1 * _ramp(d - sow, 7.0, 45.0)
		col = RYE_GREEN.lerp(RYE_DORMANT, _ramp(d, 330.0, 350.0))
	elif bool(p.cover_prev) and (kill <= -999.0 or d < kill + 20.0) and d < 200.0:
		growing = true
		var spring := _ramp(d, 70.0, 120.0)
		c = 0.3 + 0.6 * spring
		h = 0.12 + 0.45 * spring
		col = RYE_DORMANT.lerp(RYE_GREEN, _ramp(d, 60.0, 90.0))
		if kill > -999.0 and d >= kill:
			col = col.lerp(RYE_DEAD, _ramp(d, kill, kill + 14.0))
			h *= 1.0 - 0.6 * _ramp(d, kill, kill + 14.0)
	if not growing:
		return false
	s.plant = col
	s.cover = c
	s.height = h
	s.green = 1.0 if col != RYE_DEAD else 0.0
	s.spacing = 0.0
	s.crop = "rye" if not p.get("wheat_next", false) else "wheat"
	s.growth = 0.2
	s.leaves = 1.0
	s.stage = "cover crop" if s.crop == "rye" else "wheat drilled"
	return true


## Before planting: last year's stubble, standing corn stalks over the
## winter where they weren't chiseled, worked ground, or the rye cover.
static func _before(p: Dictionary, d: float, s: Dictionary) -> void:
	if _rye(p, d, s):
		return
	var worked := d >= float(p.till_spring) and float(p.till_spring) > -999.0
	s.stage = "worked ground" if worked else "stubble"
	if str(p.prev) == "corn" and not bool(p.prev_fall_till) and not worked:
		s.crop = "corn"
		s.harvested = 1.0
		s.height = 0.3
		s.plant = CORN_STALKS_OLD
		s.growth = 1.0
		s.stage = "corn stalks"


static func _corn(p: Dictionary, d: float, s: Dictionary) -> void:
	var plant := float(p.plant)
	s.spacing = 1.0
	if d < plant:
		_before(p, d, s)
		return
	if d >= float(p.harvest):
		s.crop = "corn"
		s.harvested = 1.0
		s.height = 0.0 if d >= float(p.till_fall) and float(p.till_fall) > -999.0 else 0.4
		s.plant = CORN_STALKS
		s.cover = 0.0
		s.stage = "corn stalks" if s.height > 0.0 else "chiseled"
		s.growth = 1.0
		_rye(p, d, s)
		return
	var heat := float(p.heat)
	var g := (gdd(d) - gdd(plant)) * heat
	var scale := float(p.hmax) / 2.7
	s.crop = "corn"
	s.height = interp(CORN_HEIGHT, g) * scale
	s.cover = interp(CORN_COVER, g)
	s.growth = clampf(g / float(p.r6), 0.0, 1.0)
	s.leaves = 1.0
	s.green = 1.0
	if g < 125.0:
		s.stage = "planted"
		s.cover = 0.0
		s.height = 0.0
		return
	var col := CORN_YOUNG.lerp(CORN_GREEN, _ramp(g, 300.0, 800.0))
	s.stage = "emerged" if g < 345.0 else ("rows closing" if s.cover < 0.9 else "canopy")
	if g >= CORN_VT - 60.0:
		s.stage = "tasseled"
		col = col.lerp(CORN_TASSEL, 0.16 * _ramp(g, CORN_VT - 60.0, CORN_VT + 50.0))
	# Leaves fire from the bottom after dent, and the plant goes tan by black
	# layer; after it the stalks and leaves dry and bleach in the field.
	var r5 := float(p.r6) * CORN_R5 / CORN_R6
	var mature := float(p.mature)
	if g >= r5 or d >= mature:
		var t := _ramp(g, r5, float(p.r6))
		if d >= mature:
			t = 1.0
		s.green = 1.0 - t
		col = col.lerp(CORN_FIRING, minf(t * 1.6, 1.0)).lerp(CORN_DRY, _ramp(t, 0.45, 1.0))
		s.stage = "denting" if t < 1.0 else "drying down"
		if d >= mature:
			col = CORN_DRY.lerp(CORN_LATE, _ramp(d - mature, 15.0, 50.0))
			s.cover = 1.0 - 0.15 * _ramp(d - mature, 10.0, 50.0)  # leaves shred and hang
	s.plant = col


static func _soy(p: Dictionary, d: float, s: Dictionary) -> void:
	var plant := float(p.plant)
	s.spacing = 0.5 if bool(p.narrow) else 1.0
	if d < plant:
		_before(p, d, s)
		if s.crop == "corn":
			s.spacing = 1.0
		return
	if d >= float(p.harvest):
		s.crop = "soybeans"
		s.harvested = 1.0
		s.height = 0.1
		s.plant = BEAN_STUBBLE
		s.stage = "bean stubble"
		s.growth = 1.0
		_rye(p, d, s)
		return
	_soy_growth(d - plant, d, float(p.r7), float(p.hmax), bool(p.narrow), s)
	if d < float(p.rye_kill) + 14.0 and float(p.rye_kill) > -999.0 and s.cover < 0.3:
		# Planted green: the dying rye still shows between the young rows.
		s.ground = Color(s.ground).lerp(RYE_DEAD, 0.5)


## A soybean crop `age` days after planting, on day d, its leaves yellowing
## at r7 (R7, beginning maturity) and dropping by R8 twelve days later.
static func _soy_growth(age: float, d: float, r7: float, hmax: float, narrow: bool, s: Dictionary) -> void:
	s.crop = "soybeans"
	s.height = interp(SOY_HEIGHT, age) * hmax / 0.92
	s.cover = interp(SOY_COVER_15 if narrow else SOY_COVER_30, age)
	s.growth = clampf((d - (r7 - 110.0)) / 122.0, 0.0, 1.0)
	s.leaves = 1.0
	s.green = 1.0
	if age < 8.0:
		s.stage = "planted"
		s.cover = 0.0
		s.height = 0.0
		return
	var col := SOY_YOUNG.lerp(SOY_GREEN, _ramp(age, 15.0, 45.0))
	s.stage = "emerged" if age < 30.0 else ("rows closing" if s.cover < 0.9 else "canopy")
	if d >= r7 - 8.0:
		var y := _ramp(d, r7 - 8.0, r7)
		var drop := _ramp(d, r7 + 2.0, r7 + 12.0)
		col = col.lerp(SOY_YELLOW, y).lerp(SOY_BROWN, drop)
		s.green = 1.0 - y
		s.leaves = 1.0 - drop
		# With the leaves down the rows open up and the soil shows.
		s.cover = s.cover * (1.0 - 0.6 * drop)
		s.stage = "turning yellow" if drop < 0.3 else "dropping leaves"
		if drop >= 1.0:
			s.stage = "mature"
	s.plant = col


static func _wheat(p: Dictionary, d: float, s: Dictionary) -> void:
	s.crop = "wheat"
	s.spacing = 0.0
	s.leaves = 1.0
	if d < float(p.harvest):
		# Up in the fall, a thin green over the winter, then green-up,
		# jointing and heading; gold by mid June.
		var c := 0.3 + 0.7 * _ramp(d, 70.0, 125.0)
		var col := WHEAT_DORMANT.lerp(WHEAT_GREEN, _ramp(d, 60.0, 95.0))
		col = col.lerp(WHEAT_GOLD, _ramp(d, float(p.heading) + 10.0, float(p.mature)))
		s.plant = col
		s.cover = c
		s.height = 0.12 + 0.78 * _ramp(d, 80.0, float(p.heading))
		s.green = 1.0 - _ramp(d, float(p.heading) + 10.0, float(p.mature))
		s.growth = _ramp(d, 60.0, float(p.mature))
		s.stage = "wheat" if d < float(p.heading) else ("headed" if d < float(p.mature) else "ripe")
		return
	s.harvested = 1.0
	s.stage = "wheat stubble"
	s.height = 0.15
	s.plant = STRAW
	s.cover = 0.0
	if bool(p.double) and d >= float(p.dc_plant):
		if d >= float(p.dc_harvest):
			s.crop = "soybeans"
			s.stage = "bean stubble"
			s.height = 0.1
			return
		s.spacing = 0.5
		_soy_growth(d - float(p.dc_plant), d, float(p.dc_r7), 0.7, true, s)
		s.stage = "double-crop " + str(s.stage)


static func _hay(p: Dictionary, d: float, s: Dictionary) -> void:
	s.crop = "hay"
	s.leaves = 1.0
	s.green = 1.0
	# Dormant over winter, green by mid April; cut four times, each cutting
	# regrowing in about four weeks.
	var spring := _ramp(d, 75.0, 110.0)
	var fall := _ramp(d, 300.0, 335.0)
	var last := -999.0
	for c in p.cuts:
		if d >= c:
			last = c
	var regrow := _ramp(d - last, 2.0, 28.0) if last > -999.0 else 1.0
	s.cover = lerpf(0.55, 1.0, spring * (1.0 - fall)) * lerpf(0.25, 1.0, regrow)
	s.height = lerpf(0.08, float(p.hmax), spring * (1.0 - fall) * regrow)
	var col := HAY_DORMANT.lerp(HAY_GREEN, spring * (1.0 - fall))
	if last > -999.0 and d - last < 6.0:
		s.ground = HAY_CUT  # windrows drying
		s.stage = "cut"
	else:
		s.stage = "hay"
	s.plant = col
	s.growth = regrow


static func _pasture(d: float, s: Dictionary) -> void:
	s.crop = "pasture"
	s.leaves = 1.0
	s.green = 1.0
	s.cover = 1.0
	s.height = 0.15
	var m := d / DAYS * 12.0  # months from January
	if m < 2.0 or m >= 11.0:
		s.plant = PASTURE_WINTER
	else:
		var i := clampi(int(m - 2.0), 0, 8)
		var j := clampi(i + 1, 0, 8)
		var t := clampf(m - 2.0 - i, 0.0, 1.0)
		s.plant = PASTURE[i].lerp(PASTURE[j], t)
		if m < 3.0:
			s.plant = PASTURE_WINTER.lerp(PASTURE[0], m - 2.0)
	s.stage = "pasture"


# --- The county's fields ----------------------------------------------------

## The field a region point is in. The mile grid's quarter sections (804 m,
## 160 acres) are farmed as one 160-acre field, two 80s or four 40s, as
## Grant County's are; rows run along a field's long side, either way in a
## square one. Returns Vector3i(field x, field z, 1 if rows run north-south).
## (TerrainView's shader works it out the same way: GLSL below.)
static func county_field(r: Vector2) -> Vector3i:
	var q := Vector2i(floori(r.x / 804.0), floori(r.y / 804.0))
	var sub := Vector2i(int(floorf((r.x / 804.0 - q.x) * 2.0)), int(floorf((r.y / 804.0 - q.y) * 2.0)))
	var t := h01(q.x, q.y, 1)
	var id := q * 2
	if t < 0.35:
		id += sub
	elif t < 0.6:
		id.x += sub.x
	elif t < 0.85:
		id.y += sub.y
	var dd := h01(id.x, id.y, 2)
	var ns := dd < 0.5
	if t >= 0.35 and t < 0.6:
		ns = dd < 0.8
	elif t >= 0.6 and t < 0.85:
		ns = dd >= 0.8
	return Vector3i(id.x, id.y, 1 if ns else 0)


## A county field's row and timing column in the table: most fields in a
## corn and soybean rotation, by farm habit and which crop is in this year;
## about one in eleven corn after corn; a few in a wheat rotation, hay or
## pasture (Grant County: roughly half corn, half beans, a few percent wheat
## and hay, USDA NASS county estimates).
static func county_slot(id: Vector2i) -> Vector2i:
	var s := h01(id.x, id.y, 3)
	var h2 := h01(id.x, id.y, 4)
	var col := int(h01(id.x, id.y, 5) * COLS)
	var row := 0
	if s < 0.03:
		row = 10 + int(h2 * 3.0) % 3
	elif s < 0.05:
		row = 13
	elif s < 0.06:
		row = 14
	elif s < 0.15:
		row = 8 if h2 < 0.6 else 9
	else:
		var practice := 0
		while practice < 3 and h2 >= PRACTICE_SHARE[practice]:
			practice += 1
		row = practice * 2 + (1 if h01(id.x, id.y, 6) < 0.5 else 0)
	return Vector2i(row, col)


## What a county row grows in a year, and its habits: {crop, prev, next,
## practice, cover, cover_prev, narrow}.
static func county_row(row: int, year: int) -> Dictionary:
	if row < 8:
		var practice := row / 2
		var phase := row % 2
		var rot := func(y: int) -> String: return "corn" if (y + phase) % 2 == 0 else "soybeans"
		var rye := practice == RYE
		return {"crop": rot.call(year), "prev": rot.call(year - 1), "next": rot.call(year + 1),
			"practice": practice, "cover": rye, "cover_prev": rye, "narrow": practice != CHISEL}
	if row < 10:
		return {"crop": "corn", "prev": "corn", "next": "corn", "practice": CHISEL if row == 8 else NO_TILL,
			"cover": false, "cover_prev": false, "narrow": false}
	if row < 13:
		var phase := row - 10
		var rot := func(y: int) -> String: return ["corn", "soybeans", "wheat"][posmod(y + phase, 3)]
		return {"crop": rot.call(year), "prev": rot.call(year - 1), "next": rot.call(year + 1),
			"practice": NO_TILL, "cover": false, "cover_prev": false, "narrow": true}
	if row == 13:
		return {"crop": "hay", "prev": "hay", "next": "hay", "practice": NO_TILL, "cover": false,
			"cover_prev": false, "narrow": false}
	if row == 15:
		# No county field uses it: bare ground, for a farm crop the county
		# never grows (county_row_like).
		return {"crop": "", "prev": "", "next": "", "practice": NO_TILL, "cover": false, "cover_prev": false,
			"narrow": false}
	return {"crop": "pasture", "prev": "pasture", "next": "pasture", "practice": NO_TILL, "cover": false,
		"cover_prev": false, "narrow": false}


## A farm's tillage habit, from the farm alone (its leader's schooling
## tilts it toward no-till, as with cover crops in CropPlan).
static func farm_practice(id: int, f: Dictionary) -> int:
	var h := h01(id, 0, 21)
	var edu := float(f.get("leader", {}).get("edu", 0.5))
	h = clampf(h - (edu - 0.5) * 0.3, 0.0, 0.999)
	# Most farms here till before planting; the schooled lean no-till.
	if h < 0.35:
		return NO_TILL
	if h < 0.75:
		return CHISEL
	return BEANS_NO_TILL


# --- The table --------------------------------------------------------------

static var _img: Image
static var _tex: ImageTexture
## Day of the year and year the table shows, and the row being filled.
static var _day := -1.0
static var _year := -999
static var _want_day := 196.0  # mid July until a town sets the date
static var _want_year := 1
static var _cursor := ROWS
## The date each row was last filled for (day, year): a date that moves on
## part way through a pass leaves the rows already passed on the old date,
## and the pass goes round again for them.
static var _stamp := PackedVector2Array()
## (row facts hash, col) -> plan, for _plans_year. Cleared when the year
## turns, and capped at one plan per table cell (PLANS_CAP); sizes in
## docs/crop-calendar.md (Cost).
static var _plans := {}
static var _plans_year := -999
const PLANS_CAP := ROWS * COLS
## Farm field rows in use: spec key -> row, and row -> spec.
static var _farm_rows := {}
static var _farm_specs := {}
## CPU copy of each row's states today, for the close-up plants: row -> Array of state.
static var states := {}
## Bumped each time a whole pass of the table is done.
static var version := 0


## The table texture (made on first use, filled for the current date).
static func texture() -> ImageTexture:
	if _tex == null:
		_img = Image.create(COLS * TEXELS, ROWS, false, Image.FORMAT_RGBA8)
		_tex = ImageTexture.create_from_image(_img)
		_stamp.resize(ROWS)
		_stamp.fill(Vector2(-1.0, -999.0))
		refresh(true)
	return _tex


## The date the fields should show, from Seasons.months (any year count).
## The table follows over the next frames.
static func set_date(months: float, year: int) -> void:
	var d := snappedf(day_of_year(months), 0.5)
	if d == _want_day and year == _want_year:
		return
	_want_day = d
	_want_year = year
	if _cursor >= ROWS:
		_cursor = 0


static func today() -> Vector2:
	return Vector2(_want_day, _want_year)


## Whether the table is still catching up with the date.
static func busy() -> bool:
	return _cursor < ROWS


## A row for a farm field with these facts (allocates one if new). When
## every farm row is taken the field borrows the county row nearest its
## facts: the same crop this year, never another crop.
static func farm_row(crop: String, prev: String, practice: int, cover: bool, cover_prev: bool) -> int:
	var key := "%s|%s|%d|%d|%d" % [crop, prev, practice, int(cover), int(cover_prev)]
	if _farm_rows.has(key):
		return _farm_rows[key]
	var row := COUNTY_ROWS + _farm_rows.size()
	if row >= ROWS:
		return county_row_like(crop, prev, practice, cover, cover_prev)
	_farm_rows[key] = row
	_farm_specs[row] = {"crop": crop, "prev": prev, "next": "", "practice": practice, "cover": cover,
		"cover_prev": cover_prev, "narrow": practice != CHISEL}
	texture()
	_fill_row(row)
	_tex.update(_img)
	return row


## The county row (this year) growing `crop`, with as many of the other
## facts as one has; row 15 (bare ground) for a crop the county never grows.
static func county_row_like(crop: String, prev: String, practice: int, cover: bool, cover_prev: bool) -> int:
	var best := COUNTY_ROWS - 1
	var score := -1
	for row in COUNTY_ROWS - 1:
		var s := county_row(row, _want_year)
		if s.crop != crop:
			continue
		var k := (4 if s.prev == prev else 0) + (2 if s.practice == practice else 0) \
			+ (1 if s.cover == cover and s.cover_prev == cover_prev else 0)
		if k > score:
			score = k
			best = row
	return best


## How many farm rows are in use.
static func farm_rows_used() -> int:
	return _farm_rows.size()


## Forget the farm rows (FarmView reassigns them when it redraws).
static func clear_farm_rows() -> void:
	_farm_rows.clear()
	_farm_specs.clear()
	for row in range(COUNTY_ROWS, mini(ROWS, _stamp.size())):
		_stamp[row] = Vector2(-1.0, -999.0)
		states.erase(row)


static func spec(row: int, year: int) -> Dictionary:
	if row < COUNTY_ROWS:
		return county_row(row, year)
	return _farm_specs.get(row, {})


## Fill the table toward the wanted date, spending at most `budget_ms`
## (all of it when `all`). Returns true when it changed the texture.
static func refresh(all := false, budget_ms := 1.0) -> bool:
	if _tex == null:
		texture()
		return true
	if all:
		_cursor = 0
	if _cursor >= ROWS:
		return false
	var start := Time.get_ticks_usec()
	var want := Vector2(_want_day, _want_year)
	var changed := false
	while _cursor < ROWS:
		if _stamp[_cursor] != want:
			_fill_row(_cursor)
			changed = true
		_cursor += 1
		if _cursor >= ROWS:
			# Rows passed before the date moved on: go round again for them.
			for r in ROWS:
				if _stamp[r] != want:
					_cursor = r
					break
		if not all and Time.get_ticks_usec() - start > budget_ms * 1000.0:
			break
	if _cursor >= ROWS:
		_day = _want_day
		_year = _want_year
		version += 1
	if changed:
		_tex.update(_img)
	return changed


static func _fill_row(row: int) -> void:
	_stamp[row] = Vector2(_want_day, _want_year)
	var sp := spec(row, _want_year)
	var out := []
	if sp.is_empty():
		states[row] = out
		return
	if _plans_year != _want_year or _plans.size() >= PLANS_CAP:
		_plans.clear()
		_plans_year = _want_year
	var h := sp.hash()
	for col in COLS:
		var u := (col + 0.5) / COLS
		var key := Vector2i(h, col)
		var p: Dictionary = _plans.get(key, {})
		if p.is_empty():
			p = plan(sp.crop, sp.prev, sp.next, sp.practice, sp.cover, sp.cover_prev, u, _want_year, sp.narrow)
			_plans[key] = p
		var s := state(p, _want_day)
		out.append(s)
		_write(row, col, s)
	states[row] = out


static func _write(row: int, col: int, s: Dictionary) -> void:
	var x := col * TEXELS
	var pc: Color = s.plant
	var gc: Color = s.ground
	_img.set_pixel(x, row, Color(pc.r, pc.g, pc.b, clampf(s.cover, 0.0, 1.0)))
	_img.set_pixel(x + 1, row, Color(gc.r, gc.g, gc.b, clampf(s.rows, 0.0, 1.0)))
	_img.set_pixel(x + 2, row, Color(clampf(s.height / 4.0, 0.0, 1.0), clampf(s.green, 0.0, 1.0), s.spacing,
		CROP_IDS.get(s.crop, 0) / 8.0))
	_img.set_pixel(x + 3, row, Color(clampf(s.growth, 0.0, 1.0), clampf(s.leaves, 0.0, 1.0), s.harvested,
		clampf(s.hmax / 4.0, 0.0, 1.0)))


## Today's state of a table cell (CPU side, for the close-up plants).
static func state_at(row: int, col: int) -> Dictionary:
	var r: Array = states.get(row, [])
	return r[col] if col < r.size() else {}


## The GLSL the shaders share: the table, the hash and the county field
## (keep in step with hash32, county_field and county_slot above).
const GLSL := """
uniform sampler2D crop_table : filter_nearest;
// The hash needs all 32 bits: highp throughout, so a phone's WebGL2 (where
// a fragment shader's int and uint default to mediump, 16 bits) picks the
// same crop as the desktop. Returned through an out highp, not a return
// value, so no default precision can narrow it on the way.
void crop_hash(highp ivec2 c, highp uint salt, out highp uint h) {
	highp uint x = uint(c.x + 65536);
	highp uint y = uint(c.y + 65536);
	h = x * 2376512323u + y * 3625334849u + salt * 3407524639u;
	h = h ^ (h >> 13u);
	h = h * 1540483477u;
	h = h ^ (h >> 15u);
}
highp float crop_h01(highp ivec2 c, highp uint salt) {
	highp uint h;
	crop_hash(c, salt, h);
	highp float v = float(h & 16777215u) / 16777216.0;
	return v;
}
// x, z: the field; w: 1 when its rows run north-south.
ivec3 crop_field(highp vec2 r) {
	highp vec2 qf = floor(r / 804.0);
	highp ivec2 q = ivec2(qf);
	highp ivec2 sub = ivec2(floor((r / 804.0 - qf) * 2.0));
	highp float t = crop_h01(q, 1u);
	highp ivec2 id = q * 2;
	if (t < 0.35) {
		id += sub;
	} else if (t < 0.6) {
		id.x += sub.x;
	} else if (t < 0.85) {
		id.y += sub.y;
	}
	highp float dd = crop_h01(id, 2u);
	bool ns = dd < 0.5;
	if (t >= 0.35 && t < 0.6) {
		ns = dd < 0.8;
	} else if (t >= 0.6 && t < 0.85) {
		ns = dd >= 0.8;
	}
	return ivec3(id, ns ? 1 : 0);
}
// Row and column of a county field in the table.
ivec2 crop_slot(highp ivec2 id) {
	highp float s = crop_h01(id, 3u);
	highp float h2 = crop_h01(id, 4u);
	int col = int(crop_h01(id, 5u) * 32.0);
	int row = 0;
	if (s < 0.03) {
		row = 10 + int(h2 * 3.0) % 3;
	} else if (s < 0.05) {
		row = 13;
	} else if (s < 0.06) {
		row = 14;
	} else if (s < 0.15) {
		row = h2 < 0.6 ? 8 : 9;
	} else {
		int practice = h2 < 0.3 ? 0 : (h2 < 0.7 ? 1 : (h2 < 0.9 ? 2 : 3));
		row = practice * 2 + (crop_h01(id, 6u) < 0.5 ? 1 : 0);
	}
	return ivec2(row, col);
}
vec4 crop_texel(ivec2 slot, int k) {
	return texelFetch(crop_table, ivec2(slot.y * 4 + k, slot.x), 0);
}
// The table's sRGB colours as the renderer wants them: linear on the
// desktop; the browser's Compatibility renderer takes them as they are
// (as its vertex colours and colour uniforms are).
vec3 crop_lin(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
#endif
}
// A field's colour from the table, with its rows: plants in stripes along
// `along` (metres across the rows), the soil and residue between. Near the
// camera the stripes are sharp; once they are smaller than a pixel they
// blend to their average (`aw`: fwidth(across), from the fragment).
// `tilt`: how sideways the view is (horizontal over vertical): tall plants
// hide the gaps between rows when seen at a slant.
// Where the close-up plants stand (CropPlants): x, z, radius, on. Inside
// it the plants are drawn for real, so the stripe under them is the shaded
// ground between their leaves, not painted leaves.
uniform vec4 plants_near = vec4(0.0);
vec3 crop_look(ivec2 slot, vec2 at, float across, float aw, float tilt, float noise) {
	vec4 t0 = crop_texel(slot, 0);
	vec4 t1 = crop_texel(slot, 1);
	vec4 t2 = crop_texel(slot, 2);
	float height = t2.r * 4.0;
	float spacing = t2.b > 0.75 ? 0.762 : 0.381;
	float cover = t0.a;
	float seen = cover + (1.0 - cover) * clamp(height * tilt / spacing * 0.6, 0.0, 1.0) * 0.85;
	float rc = across / spacing;
	float w = aw / spacing;
	float d = abs(fract(rc) - 0.5) * 2.0;
	// Rows only for row crops; drilled wheat, rye, hay and grass are even.
	float rowed = step(0.25, t2.b);
	float stripe = 1.0 - smoothstep(seen - w - 0.05, seen + w + 0.05, d);
	float share = mix(seen, mix(stripe, seen, smoothstep(0.25, 0.7, w)), rowed);
	vec3 plant = crop_lin(t0.rgb) * (0.9 + 0.2 * noise);
	// Under a closing canopy the ground between the rows is in shade.
	vec3 ground = crop_lin(t1.rgb) * (1.0 - 0.55 * cover);
	float under = plants_near.w * (1.0 - smoothstep(plants_near.z * 0.6, plants_near.z, distance(at, plants_near.xy)));
	plant *= 1.0 - 0.12 * under * step(0.25, t2.b);
	// Standing stalk rows in the stubble, a little lighter than the soil.
	float stalks = (1.0 - smoothstep(0.25 - w, 0.25 + w, d)) * (1.0 - smoothstep(0.25, 0.7, w));
	ground *= 1.0 + t1.a * mix(0.05, stalks * 0.25, 1.0 - smoothstep(0.25, 0.7, w)) * step(0.25, t2.b);
	return mix(ground, plant, share);
}
"""
