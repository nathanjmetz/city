class_name Brand
extends RefCounted
## The Neighbors brand kit in code: colors, the player palette and the type
## styles from the kit's spec/tokens.json (Game theme), token names in
## SCREAMING_CASE. Coral always means you.

# Colors (Game theme), generated from branding/kit/spec/tokens.json.
## Page or screen ground: menus, map backdrop, the kit page. In game, the color behind loading screens.
const SURFACE := Color("#10272b")
## Docked HUD panels (top bar, toolbar, tool panel, inspector). 94% opaque in game so the world shows faintly at the edges.
const SURFACE_PANEL := Color("#16343af0")
## Cards, inputs and hovered rows inside a panel.
const SURFACE_RAISED := Color("#1f454c")
## Wells: meters, segmented-control tracks, code fields.
const SURFACE_SUNKEN := Color("#0c1f22")
## Hairlines between docked panels and rows. Decorative only; never the only edge of a control.
const LINE := Color("#2c5a62")
## Borders of inputs and unselected controls (3:1 or better on surface-panel).
const LINE_STRONG := Color("#5d8b90")
## Primary text and idle icons on surface, surface-panel and surface-raised.
const INK := Color("#f6f4ef")
## Labels, units and secondary text on surface-panel and surface-raised.
const INK_MUTED := Color("#a9c1c0")
## Disabled controls and placeholder hints. Not for text that must be read.
const INK_FAINT := Color("#6f8f93")
## The neighbor wall of the mark; info accents, links, focus on paper. As text only on paper (5.3:1).
const BRAND_TEAL := Color("#3a9a94")
## The roof of the mark: the shared map. Region-map water and parks highlights; focus ring in game.
const BRAND_MINT := Color("#8fcfbf")
## YOU. Your city, your selection, the active tool and the one primary action on a screen. Never for errors.
const BRAND_CORAL := Color("#ef6f51")
## Text and icons placed on brand-coral (5.2:1).
const ON_CORAL := Color("#10272b")
## Coral used as text, e.g. your city name in a list, on the theme's surfaces.
const CORAL_TEXT := Color("#ff8a6e")
## Fixed deep ink: app icon tile, badge ground, on-dark logo ground. Same in both themes.
const BRAND_INK := Color("#16343a")
## Fixed cream: city-line gaps on maps, logo on dark, street-label text.
const BRAND_CREAM := Color("#f6f4ef")
## Keyboard and gamepad focus ring, 2px solid, offset 2px (5.8:1 on raised surfaces).
const FOCUS := Color("#8fcfbf")
## Good news: income up, service covered, deal accepted. Always with an icon or a + sign.
const POSITIVE := Color("#5cc98f")
## Needs attention soon: low funds, rising traffic, demand stalling. Always with the warning icon.
const WARNING := Color("#f2c14e")
## Act now: no power, abandoned buildings, bankrupt. Always with the warning icon and a word. Pink-red so it never reads as coral.
const CRITICAL := Color("#ff6b8a")
## Your city on every map and badge, on your own screen.
const PLAYER_YOU := Color("#ef6f51")
## Neighbor color 1. Region map fill, badge wall, name chip.
const PLAYER_LAKE := Color("#2c58b0")
## Neighbor color 2.
const PLAYER_SKY := Color("#8fd3f0")
## Neighbor color 3.
const PLAYER_LILAC := Color("#c2a6ee")
## Neighbor color 4.
const PLAYER_GOLDENROD := Color("#f0cc45")
## Neighbor color 5.
const PLAYER_PINE := Color("#16766a")
## Neighbor color 6.
const PLAYER_PLUM := Color("#7a2a6a")
## Neighbor color 7.
const PLAYER_PRAIRIE := Color("#bcd866")
## Neighbor color 8.
const PLAYER_BARN := Color("#8a5a2b")
## Zoning overlay and legend: low-density residential (houses).
const ZONE_RES_LOW := Color("#7cc36b")
## High-density residential (apartments).
const ZONE_RES_HIGH := Color("#3f9a4a")
## Low-density commercial (Main Street shops).
const ZONE_COM_LOW := Color("#6bb3e8")
## High-density commercial.
const ZONE_COM_HIGH := Color("#2f6fbf")
## Industrial zones and industry buildings.
const ZONE_INDUSTRY := Color("#e6b43c")
## Office zones.
const ZONE_OFFICE := Color("#9a7fd1")
## Painted farmland and farm plots.
const ZONE_FARM := Color("#b89a5a")
## Traffic view: flowing at the speed limit.
const TRAFFIC_FREE := Color("#4cc38a")
## Traffic view: slowing.
const TRAFFIC_BUSY := Color("#f2c14e")
## Traffic view: heavy, stop and go.
const TRAFFIC_HEAVY := Color("#ee8a3a")
## Traffic view: gridlock.
const TRAFFIC_JAM := Color("#d6334a")
## Info-view ramp, lowest value (coverage, land value, pollution). Five steps mint to ink.
const DATA_1 := Color("#e6f2ee")
## Info-view ramp, step 2.
const DATA_2 := Color("#8fcfbf")
## Info-view ramp, step 3.
const DATA_3 := Color("#3a9a94")
## Info-view ramp, step 4.
const DATA_4 := Color("#1f6f78")
## Info-view ramp, highest value.
const DATA_5 := Color("#16343a")
## Region map: unclaimed land.
const MAP_LAND := Color("#2a3a2c")
## Region map: lakes and rivers.
const MAP_WATER := Color("#24505a")
## The city line: the gap between two cities, drawn halfway between their closest buildings. Cream, like the gaps in the mark.
const CITY_LINE := Color("#f6f4efd9")
## Street-name blade background in the world (MUTCD guide-sign green).
const STREET_SIGN := Color("#0f6b3e")

## Neighbors' colors, in the order they joined the region (you are PLAYER_YOU).
const PLAYERS := [
	PLAYER_LAKE,
	PLAYER_SKY,
	PLAYER_LILAC,
	PLAYER_GOLDENROD,
	PLAYER_PINE,
	PLAYER_PLUM,
	PLAYER_PRAIRIE,
	PLAYER_BARN,
]

const LOGO := "res://assets/brand/logos/neighbors-horizontal-on-dark.png"
const MARK := "res://assets/brand/logos/neighbors-mark-on-dark.png"

const _FONTS := {
	"display": "res://assets/brand/fonts/Outfit.ttf",
	"ui": "res://assets/brand/fonts/Figtree.ttf",
	"sign": "res://assets/brand/fonts/Overpass.ttf",
}
static var _cache := {}


## A neighbor's color: coral if it's you, otherwise theirs by join order.
static func player_color(color_index: int, is_you: bool) -> Color:
	return PLAYER_YOU if is_you else PLAYERS[posmod(color_index, PLAYERS.size())]


## Outfit, for titles (title screen, panel titles, banners).
static func display(weight := 600) -> Font:
	return font("display", weight)


## Figtree, for the interface: 500 body, 600 labels, 700 stats. Tabular figures.
static func ui(weight := 500) -> Font:
	return font("ui", weight)


## Overpass, for words in the world (street, district and city names).
## Multichannel SDF so Label3D text stays crisp at any zoom.
static func sign(weight := 700) -> Font:
	return font("sign", weight)


## One of the brand's typefaces at a weight: "display", "ui" or "sign".
static func font(family: String, weight := 500) -> Font:
	var key := "%s-%d" % [family, weight]
	if not _cache.has(key):
		var base: FontFile = load(_FONTS[family])
		if family == "sign":
			base = base.duplicate()
			base.multichannel_signed_distance_field = true
		var f := FontVariation.new()
		f.base_font = base
		f.variation_opentype = {"wght": weight}
		if family == "ui":
			f.opentype_features = {"tnum": 1}
		_cache[key] = f
	return _cache[key]


## A label in a brand type style, e.g. label("Neighbors", "display", 64, 700).
static func label(text: String, family: String, size: int, weight := 500, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(family, weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
