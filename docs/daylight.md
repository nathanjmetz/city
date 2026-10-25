# Daylight: the real sun over Grant County (2026-10-25)

Idea #8 in `docs/real-life-details.md`, "Light through the day and year", plus the haze half of #23 ("Flat sky and distant farms"). The sun, sky and shadows follow real Grant County, Indiana (40.5° N, 85.66° W, Eastern Time with daylight saving) for the game's date and clock.

## What you see

With **Day and night on**, the sun rises and sets at the real times for the date and walks the real path. It is warm and low after sunrise, white at midday, and golden before sunset. Then comes about half an hour of blue dusk, then moonlight and stars. Shadows point the right way and are the right length.

With **Day and night off** (the default), the town keeps its tuned late-morning look. The haze still follows the year: whiter and thicker in a humid summer, crisp and blue in winter.

Screenshots of the same view (desktop renderer, real game window) are in `docs/daylight/`:

| Moment | Sun height | Bearing | Shadow (× height) | Picture |
| --- | --- | --- | --- | --- |
| June 21, 7:00 am | 7° | 65° (ENE) | 7.9 | `06-21_0700.jpg` |
| June 21, 10:00 am | 40° | 92° (E) | 1.2 | `06-21_1000.jpg` |
| June 21, 1:40 pm | 72.9° (near its highest) | 177° (S) | 0.3 | `06-21_1340.jpg` |
| June 21, 6:00 pm | 34° | 273° (W) | 1.5 | `06-21_1800.jpg` |
| June 21, 8:45 pm | 4° | 297° (WNW) | 13 | `06-21_2045.jpg` |
| December 21, 1:00 pm | 26° | 185° (S) | 2.1 | `12-21_1300.jpg` |

The browser's renderer (Compatibility) uses the same sun, sky and colours: `browser_06-21_1340.jpg` and `browser_06-21_2045.jpg`.

## The formulas (`scripts/art/light/`)

**Where the sun is** (`sun_path.gd`, class `SunPath`). These are NOAA Global Monitoring Laboratory's "General Solar Position Calculations":

- Fractional year: γ = 2π/365 · (day − 1 + (hour − 12)/24)
- Equation of time (minutes) = 229.18 · (0.000075 + 0.001868 cos γ − 0.032077 sin γ − 0.014615 cos 2γ − 0.040849 sin 2γ)
- Declination (radians) = 0.006918 − 0.399912 cos γ + 0.070257 sin γ − 0.006758 cos 2γ + 0.000907 sin 2γ − 0.002697 cos 3γ + 0.00148 sin 3γ
- True solar time (minutes) = clock minutes + equation of time + 4 · longitude − 60 · time zone. Hour angle = solar time / 4 − 180°.
- Height: sin h = sin φ sin δ + cos φ cos δ cos H. Bearing: atan2(sin H, cos H sin φ − tan δ cos φ) + 180°.
- Refraction (the air lifts the sun's image, about half a degree at the horizon) uses NOAA's solar calculator fit.
- Sunrise and sunset happen when the sun's centre is at −0.833°. Civil twilight ends at −6°.

**Daylight saving.** US clocks change on the second Sunday of March and the first Sunday of November. A game day runs through a whole month, so the game changes its clocks at the 2 am nearest those dates: the end of the February game day (about February 26) and of the October game day (about October 27). Using the real dates would make the sun jump an hour in mid-afternoon. For real dates (tests, notes), March 10 to November 3 is used.

**What the light looks like** (`daylight.gd`, class `Daylight`). It is all driven by the sun's height, and every value at 40° reproduces the tuned look.

- Sun colour: the colour temperature of direct sunlight by height. It is about 2,000 K at the horizon, 3,000 K at 5°, 4,800 K at 20° and 5,500 K at 40°, rising to 5,850 K overhead. These are rounded from published direct-beam measurements, which agree only loosely, so the colour was checked on screen. The kelvin values are turned into RGB with Tanner Helland's blackbody fit (2012). Humid summer air warms a low sun a little more.
- Sun strength: Meinel and Meinel's clear-air fit for direct sunlight, I ∝ 0.7^(AM^0.678), with the Kasten and Young (1989) air mass. It is softened by a square root, because the game has no exposure change of its own and a real sunset is about 30 times dimmer than noon.
- Exposure: the eye opening up. Light on open ground (sun plus skylight) is compared with the tuned look, then raised to the power 0.6 and limited to between 0.92 and 2. Mornings and evenings stay readable, and night stays dark.
- Sky, shade light and stars: a table by sun height. It runs from day, through a golden horizon at 3° and an orange one at 0°, to blue hour at −3° to −6°. Nautical twilight is at −12° and night at −18°. The first stars appear at −5°, and almost all are out by −13°.
- Haze through the year: humidity = 0.5 − 0.5 cos(2π (month − 0.55)/12). That is 0 in mid-January and 1 in mid-July, when Indiana's dew points peak. Haze thickness runs from 0.75× (about 32 km visibility) to 1.25× (about 19 km) of the tuned 24 km. The summer horizon is whiter and the winter one bluer.

**Moon:** this is unchanged. There is still a full moon opposite the sun, at least 25° up. A real moon phase doesn't fit the game's calendar, because a whole lunar month would pass in one game day.

## Tests

`tests/test_sun_path.gd` is in the web-preview run. It checks these against the US Naval Observatory's table for 40.50° N, 85.66° W (2026 dates), all within 3 minutes:

- June 21: sunrise 6:12 am, sunset 9:17 pm, highest at 1:45 pm, 72.9° up.
- December 21: sunrise 8:03 am, sunset 5:19 pm, highest at 12:41 pm, 26.1° up.
- March 20: sunrise 7:46 am, nearly due east; sunset 7:55 pm.
- Day lengths: 15 h 5 m in June and 9 h 16 m in December.
- Civil dusk: 33 minutes in June, 27 in March and 31 in December.

It also checks the shadow direction and length (a 10 m pole casts 3.1 m at June's midday and 20.5 m at December's), the 2 am clock change, the light's colours, and that the lit scene's sun points where the formulas say.

## Cost

This was measured in a real 1600×900 game window on the M5 Max. The clock moved one game minute a frame from 7 am to 7 pm, so the light changed every frame. Day and night was switched on and off in turns (4 × 300 frames each), with vsync off. Other helpers' tests were running at the same time, so single numbers vary by about ±0.5 ms. Compare the on/off differences.

| | Main before | This branch |
| --- | --- | --- |
| Desktop: day and night on vs off | +1.04 ms | +0.70 ms |
| Browser renderer: on vs off | +0.51 ms | +0.44 ms |
| Lighting's own CPU time a frame | not measured | 0.022 ms |
| Memory | — | no new textures or nodes |

So the new light costs no more than the old. It is cheaper, because the sky's colours are only sent on when they change enough to see; each change re-renders the sky's lighting. Re-run with `tools/daylight_shot.gd` (instructions at the top of the file).
